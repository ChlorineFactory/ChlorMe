import Foundation

public struct PromptImageData: Hashable, Sendable {
    public let mimeType: String
    public let base64Data: String

    public init(mimeType: String = "image/jpeg", base64Data: String) {
        self.mimeType = mimeType
        self.base64Data = base64Data
    }
}

public struct PromptMessage: Hashable, Sendable {
    public let role: MessageRole
    public let content: String
    public let images: [PromptImageData]

    public init(role: MessageRole, content: String, images: [PromptImageData] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

public struct GenerationChunk: Sendable {
    public let text: String
    public let reasoningDelta: String?
    public let tokensPerSecond: Double?
    public let isDone: Bool

    public init(text: String, reasoningDelta: String? = nil, tokensPerSecond: Double? = nil, isDone: Bool = false) {
        self.text = text
        self.reasoningDelta = reasoningDelta
        self.tokensPerSecond = tokensPerSecond
        self.isDone = isDone
    }
}

public protocol LLMBackend: Sendable {
    func streamCompletion(
        messages: [PromptMessage],
        model: ModelConfig,
        preset: SamplerPreset
    ) -> AsyncThrowingStream<GenerationChunk, Error>
}

// MARK: - Chat Template Formatter for Local GGUF Models

public enum ChatTemplateFormatter {
    public static func detectStyle(for model: ModelConfig) -> ChatTemplateStyle {
        if model.chatTemplate != .auto {
            return model.chatTemplate
        }
        let lower = (model.name + " " + (model.localFileName ?? "")).lowercased()
        if lower.contains("llama-3") || lower.contains("llama3") { return .llama3 }
        if lower.contains("gemma") { return .gemma }
        if lower.contains("mistral") || lower.contains("nemo") { return .mistral }
        if lower.contains("alpaca") { return .alpaca }
        return .chatML
    }

    public static func format(messages: [PromptMessage], style: ChatTemplateStyle) -> String {
        switch style {
        case .auto, .chatML:
            var out = ""
            for msg in messages {
                out += "<|im_start|>\(msg.role.rawValue)\n\(msg.content)<|im_end|>\n"
            }
            out += "<|im_start|>assistant\n"
            return out

        case .llama3:
            var out = "<|begin_of_text|>"
            for msg in messages {
                out += "<|start_header_id|>\(msg.role.rawValue)<|end_header_id|>\n\n\(msg.content)<|eot_id|>"
            }
            out += "<|start_header_id|>assistant<|end_header_id|>\n\n"
            return out

        case .gemma:
            // Gemma merges system into the first user turn cleanly
            var systemTexts: [String] = []
            var dialogue: [PromptMessage] = []
            for msg in messages {
                if msg.role == .system {
                    systemTexts.append(msg.content)
                } else {
                    dialogue.append(msg)
                }
            }
            var out = "<bos>"
            let sysPrefix = systemTexts.joined(separator: "\n\n")
            var injectedSystem = false
            for msg in dialogue {
                let roleName = msg.role == .assistant ? "model" : "user"
                var body = msg.content
                if !injectedSystem && roleName == "user" && !sysPrefix.isEmpty {
                    body = sysPrefix + "\n\n" + body
                    injectedSystem = true
                }
                out += "<start_of_turn>\(roleName)\n\(body)<end_of_turn>\n"
            }
            if !injectedSystem && !sysPrefix.isEmpty {
                out += "<start_of_turn>user\n\(sysPrefix)<end_of_turn>\n"
            }
            out += "<start_of_turn>model\n"
            return out

        case .mistral:
            var out = "<s>"
            var sys = ""
            for msg in messages {
                switch msg.role {
                case .system:
                    sys += (sys.isEmpty ? "" : "\n") + msg.content
                case .user:
                    let content = sys.isEmpty ? msg.content : "\(sys)\n\n\(msg.content)"
                    sys = ""
                    out += "[INST] \(content) [/INST]"
                case .assistant:
                    out += " \(msg.content)</s>"
                }
            }
            return out

        case .alpaca:
            var out = ""
            for msg in messages {
                switch msg.role {
                case .system:
                    out += "### System:\n\(msg.content)\n\n"
                case .user:
                    out += "### User:\n\(msg.content)\n\n"
                case .assistant:
                    out += "### Assistant:\n\(msg.content)\n\n"
                }
            }
            out += "### Assistant:\n"
            return out
        }
    }
}

// MARK: - WeChat-style Natural Bubble Splitter

public enum BubbleSplitter {
    /// Splits a companion response into natural sequential bubbles (2...4 chunks) without breaking action markers.
    public static func split(_ text: String, enabled: Bool) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !trimmed.isEmpty else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        // First split by explicit line breaks
        let rawLines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if rawLines.count >= 2 && rawLines.count <= 5 {
            return rawLines
        }

        // If it's a single long paragraph (> 42 chars), split smoothly at sentence punctuation
        if rawLines.count == 1 && trimmed.count > 42 {
            var chunks: [String] = []
            var current = ""
            let terminators: Set<Character> = ["。", "！", "？", "!", "?", "…"]
            for ch in trimmed {
                current.append(ch)
                if terminators.contains(ch) && current.count >= 16 {
                    chunks.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
            let tail = current.trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty {
                if let last = chunks.last, tail.count < 8 {
                    chunks[chunks.count - 1] = last + tail
                } else {
                    chunks.append(tail)
                }
            }
            if chunks.count > 4 {
                let firstThree = Array(chunks.prefix(3))
                let rest = chunks.dropFirst(3).joined()
                return firstThree + [rest]
            }
            return chunks.isEmpty ? [trimmed] : chunks
        }

        return rawLines.isEmpty ? [trimmed] : rawLines
    }
}

// MARK: - Memory Safety Traffic Light

public enum MemorySafetyLevel: String, Sendable {
    case safe
    case caution
    case danger

    public var label: String {
        switch self {
        case .safe: return "流畅"
        case .caution: return "偏高"
        case .danger: return "高风险"
        }
    }
}

public enum MemoryBudgetAdvisor {
    public static func evaluate(estimatedModelBytes: Int64, availableMemoryBytes: Int64) -> MemorySafetyLevel {
        guard availableMemoryBytes > 0 else { return .caution }
        let ratio = Double(estimatedModelBytes) / Double(availableMemoryBytes)
        if ratio <= 0.72 { return .safe }
        if ratio <= 0.90 { return .caution }
        return .danger
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}
