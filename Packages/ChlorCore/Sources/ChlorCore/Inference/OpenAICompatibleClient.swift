import Foundation

public enum OpenAIClientError: LocalizedError {
    case invalidEndpoint
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "远程 API 地址格式无效，请检查 Base URL（例如 https://api.openai.com/v1）"
        case .httpError(let code, let body):
            return "远程接口返回错误 (\(code))：\(body.prefix(200))"
        }
    }
}

/// Streams chat completions from any OpenAI-compatible endpoint (Ollama, llama-server, LM Studio, DeepSeek, OpenAI, etc.).
public struct OpenAICompatibleClient: LLMBackend {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
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

                    let payload: [String: Any] = [
                        "model": (model.remoteModelName?.isEmpty == false ? model.remoteModelName! : model.name),
                        "stream": true,
                        "temperature": preset.temperature,
                        "top_p": preset.topP,
                        "max_tokens": preset.maxTokens,
                        "frequency_penalty": preset.frequencyPenalty,
                        "presence_penalty": preset.presencePenalty,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
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
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            chunkCount += 1
                            let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                            continuation.yield(GenerationChunk(text: content, tokensPerSecond: Double(chunkCount) / elapsed, isDone: false))
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
