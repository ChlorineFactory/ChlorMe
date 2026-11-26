import Foundation

// MARK: - Native Anthropic Claude Client (/v1/messages)

public struct AnthropicClient: LLMBackend {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchAvailableModels(baseURL: String, apiKey: String?, customHeaders: [String: String] = [:]) async throws -> [String] {
        let base = normalizedBase(baseURL, defaultBase: "https://api.anthropic.com")
        let urlStr = base.hasSuffix("/v1") ? "\(base)/models" : "\(base)/v1/models"
        guard let url = URL(string: urlStr) else { throw OpenAIClientError.invalidEndpoint }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        for (k, v) in customHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenAIClientError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = json["data"] as? [[String: Any]] {
            return list.compactMap { $0["id"] as? String }
        }
        return ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"]
    }

    public func streamCompletion(
        messages: [PromptMessage],
        model: ModelConfig,
        preset: SamplerPreset
    ) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base = normalizedBase(model.apiBaseURL ?? "", defaultBase: "https://api.anthropic.com")
                    let endpointStr: String
                    if base.hasSuffix("/messages") {
                        endpointStr = base
                    } else if base.hasSuffix("/v1") {
                        endpointStr = "\(base)/messages"
                    } else {
                        endpointStr = "\(base)/v1/messages"
                    }
                    guard let url = URL(string: endpointStr) else {
                        throw OpenAIClientError.invalidEndpoint
                    }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    if let key = model.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                        req.setValue(key, forHTTPHeaderField: "x-api-key")
                    }
                    for (k, v) in model.parsedCustomHeaders() { req.setValue(v, forHTTPHeaderField: k) }

                    let systemText = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
                    let nonSystem = messages.filter { $0.role != .system }
                    let anthropicMessages: [[String: Any]] = nonSystem.map { msg in
                        let role = msg.role == .assistant ? "assistant" : "user"
                        if msg.images.isEmpty {
                            return ["role": role, "content": msg.content]
                        } else {
                            var blocks: [[String: Any]] = []
                            for img in msg.images {
                                blocks.append([
                                    "type": "image",
                                    "source": [
                                        "type": "base64",
                                        "media_type": img.mimeType,
                                        "data": img.base64Data
                                    ]
                                ])
                            }
                            blocks.append(["type": "text", "text": msg.content])
                            return ["role": role, "content": blocks]
                        }
                    }

                    var payload: [String: Any] = [
                        "model": (model.remoteModelName?.isEmpty == false ? model.remoteModelName! : model.name),
                        "max_tokens": max(64, preset.maxTokens),
                        "temperature": min(1.0, max(0.0, preset.temperature)),
                        "stream": true,
                        "messages": anthropicMessages
                    ]
                    if !systemText.isEmpty {
                        payload["system"] = systemText
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let startTime = Date()
                    var chunkCount = 0
                    let (bytes, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line
                            if errBody.count > 400 { break }
                        }
                        throw OpenAIClientError.httpError(http.statusCode, errBody)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let jsonPart = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = jsonPart.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let eventType = obj["type"] as? String else { continue }

                        if eventType == "content_block_delta", let delta = obj["delta"] as? [String: Any] {
                            let deltaType = delta["type"] as? String ?? ""
                            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                                chunkCount += 1
                                let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                                continuation.yield(GenerationChunk(text: text, tokensPerSecond: Double(chunkCount) / elapsed))
                            } else if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                                chunkCount += 1
                                let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                                continuation.yield(GenerationChunk(text: "", reasoningDelta: thinking, tokensPerSecond: Double(chunkCount) / elapsed))
                            }
                        } else if eventType == "message_stop" {
                            break
                        }
                    }

                    let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                    continuation.yield(GenerationChunk(text: "", tokensPerSecond: Double(chunkCount) / elapsed, isDone: true))
                    continuation.finish()
                } catch {
                    if !Task.isCancelled { continuation.finish(throwing: error) } else { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func normalizedBase(_ raw: String, defaultBase: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = t.isEmpty ? defaultBase : t
        return chosen.hasSuffix("/") ? String(chosen.dropLast()) : chosen
    }
}

// MARK: - Native Google Gemini Client (streamGenerateContent?alt=sse)

public struct GeminiClient: LLMBackend {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchAvailableModels(baseURL: String, apiKey: String?, customHeaders: [String: String] = [:]) async throws -> [String] {
        let base = normalizedBase(baseURL)
        guard let url = URL(string: "\(base)/models") else { throw OpenAIClientError.invalidEndpoint }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        for (k, v) in customHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenAIClientError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = json["models"] as? [[String: Any]] {
            return list.compactMap { item -> String? in
                guard let name = item["name"] as? String else { return nil }
                return name.replacingOccurrences(of: "models/", with: "")
            }.sorted()
        }
        return ["gemini-2.5-flash", "gemini-2.5-pro"]
    }

    public func streamCompletion(
        messages: [PromptMessage],
        model: ModelConfig,
        preset: SamplerPreset
    ) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base = normalizedBase(model.apiBaseURL ?? "")
                    let modelId = (model.remoteModelName?.isEmpty == false ? model.remoteModelName! : model.name)
                        .replacingOccurrences(of: "models/", with: "")
                    guard let url = URL(string: "\(base)/models/\(modelId):streamGenerateContent?alt=sse") else {
                        throw OpenAIClientError.invalidEndpoint
                    }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let key = model.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                    }
                    for (k, v) in model.parsedCustomHeaders() { req.setValue(v, forHTTPHeaderField: k) }

                    let systemText = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
                    let contents: [[String: Any]] = messages.filter { $0.role != .system }.map { msg in
                        let role = msg.role == .assistant ? "model" : "user"
                        var parts: [[String: Any]] = [["text": msg.content]]
                        for img in msg.images {
                            parts.append([
                                "inlineData": [
                                    "mimeType": img.mimeType,
                                    "data": img.base64Data
                                ]
                            ])
                        }
                        return ["role": role, "parts": parts]
                    }

                    var payload: [String: Any] = [
                        "contents": contents,
                        "generationConfig": [
                            "temperature": preset.temperature,
                            "topP": preset.topP,
                            "maxOutputTokens": preset.maxTokens
                        ]
                    ]
                    if !systemText.isEmpty {
                        payload["systemInstruction"] = ["parts": [["text": systemText]]]
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let startTime = Date()
                    var chunkCount = 0
                    let (bytes, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line
                            if errBody.count > 400 { break }
                        }
                        throw OpenAIClientError.httpError(http.statusCode, errBody)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let jsonPart = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = jsonPart.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = obj["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]] else { continue }

                        for part in parts {
                            guard let text = part["text"] as? String, !text.isEmpty else { continue }
                            let isThought = (part["thought"] as? Bool) ?? false
                            chunkCount += 1
                            let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                            if isThought {
                                continuation.yield(GenerationChunk(text: "", reasoningDelta: text, tokensPerSecond: Double(chunkCount) / elapsed))
                            } else {
                                continuation.yield(GenerationChunk(text: text, tokensPerSecond: Double(chunkCount) / elapsed))
                            }
                        }
                    }

                    let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                    continuation.yield(GenerationChunk(text: "", tokensPerSecond: Double(chunkCount) / elapsed, isDone: true))
                    continuation.finish()
                } catch {
                    if !Task.isCancelled { continuation.finish(throwing: error) } else { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func normalizedBase(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = t.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : t
        return chosen.hasSuffix("/") ? String(chosen.dropLast()) : chosen
    }
}
