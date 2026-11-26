import Foundation

public enum OpenAIClientError: LocalizedError {
    case invalidEndpoint
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "远程 API 地址格式无效，请检查 Base URL"
        case .httpError(let code, let body):
            return "远程接口返回错误 (\(code))：\(body.prefix(220))"
        }
    }
}

/// Streams chat completions from OpenAI-compatible endpoints (OpenAI, DeepSeek, Ollama, LM Studio, OpenRouter, etc.)
/// with multimodal image input, reasoning_content separation, and custom HTTP headers.
public struct OpenAICompatibleClient: LLMBackend {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchAvailableModels(baseURL: String, apiKey: String?, customHeaders: [String: String] = [:]) async throws -> [String] {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAIClientError.invalidEndpoint }
        var base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        guard let url = URL(string: "\(base)/models") else {
            throw OpenAIClientError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in customHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIClientError.httpError(http.statusCode, body)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = obj["data"] as? [[String: Any]] {
            return list.compactMap { $0["id"] as? String }.sorted()
        }
        return []
    }

    public static func exportMarkdownTranscript(
        character: CharacterCard,
        conversation: Conversation,
        messages: [ChatMessage]
    ) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var lines: [String] = [
            "# 与 \(character.name) 的私密回忆记录",
            "> 会话：\(conversation.title.isEmpty ? character.name : conversation.title) · 导出时间：\(df.string(from: Date()))",
            ""
        ]
        if !conversation.rollingSummary.isEmpty {
            lines.append("## 早期聊天摘要")
            lines.append(conversation.rollingSummary)
            lines.append("")
        }
        lines.append("## 对话记录")
        for msg in messages {
            let speaker = msg.role == .user ? "我" : character.name
            lines.append("**\(speaker)** (\(df.string(from: msg.createdAt))):")
            if let r = msg.reasoningContent, !r.isEmpty {
                lines.append("<details><summary>思考过程</summary>\n\n\(r)\n\n</details>")
            }
            lines.append(msg.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public func streamCompletion(
        messages: [PromptMessage],
        model: ModelConfig,
        preset: SamplerPreset
    ) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let baseStr = model.apiBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !baseStr.isEmpty else {
                        throw OpenAIClientError.invalidEndpoint
                    }
                    let cleanedBase = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
                    let endpointStr = cleanedBase.hasSuffix("/chat/completions")
                        ? cleanedBase
                        : "\(cleanedBase)/chat/completions"

                    guard let url = URL(string: endpointStr) else {
                        throw OpenAIClientError.invalidEndpoint
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let key = model.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    for (k, v) in model.parsedCustomHeaders() {
                        request.setValue(v, forHTTPHeaderField: k)
                    }

                    let serializedMessages: [[String: Any]] = messages.map { msg in
                        if msg.images.isEmpty {
                            return ["role": msg.role.rawValue, "content": msg.content]
                        } else {
                            var parts: [[String: Any]] = [["type": "text", "text": msg.content]]
                            for img in msg.images {
                                parts.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64Data)"]
                                ])
                            }
                            return ["role": msg.role.rawValue, "content": parts]
                        }
                    }

                    let payload: [String: Any] = [
                        "model": (model.remoteModelName?.isEmpty == false ? model.remoteModelName! : model.name),
                        "stream": true,
                        "temperature": preset.temperature,
                        "top_p": preset.topP,
                        "max_tokens": preset.maxTokens,
                        "frequency_penalty": preset.frequencyPenalty,
                        "presence_penalty": preset.presencePenalty,
                        "messages": serializedMessages
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let startTime = Date()
                    var chunkCount = 0
                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
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
                        if jsonPart == "[DONE]" {
                            let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                            continuation.yield(GenerationChunk(text: "", tokensPerSecond: Double(chunkCount) / elapsed, isDone: true))
                            continuation.finish()
                            return
                        }
                        if let data = jsonPart.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = obj["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any] {
                            let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String)
                            let content = (delta["content"] as? String) ?? ""
                            if !content.isEmpty || (reasoning != nil && !reasoning!.isEmpty) {
                                chunkCount += 1
                                let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                                continuation.yield(GenerationChunk(
                                    text: content,
                                    reasoningDelta: reasoning,
                                    tokensPerSecond: Double(chunkCount) / elapsed,
                                    isDone: false
                                ))
                            }
                        }
                    }

                    let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                    continuation.yield(GenerationChunk(text: "", tokensPerSecond: Double(chunkCount) / elapsed, isDone: true))
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
