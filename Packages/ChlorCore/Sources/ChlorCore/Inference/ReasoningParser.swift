import Foundation

public struct ParsedReasoningContent: Equatable, Sendable {
    public let reasoning: String
    public let answer: String
    public let isStillThinking: Bool

    public init(reasoning: String, answer: String, isStillThinking: Bool) {
        self.reasoning = reasoning
        self.answer = answer
        self.isStillThinking = isStillThinking
    }
}

/// Separates <think>...</think> / <thought>...</thought> reasoning chains from visible companion replies (both streaming & final).
public enum ReasoningParser {
    private static let tagPairs: [(open: String, close: String)] = [
        ("<think>", "</think>"),
        ("<thought>", "</thought>"),
        ("<|thought|>", "<|/thought|>")
    ]

    public static func split(rawText: String, explicitReasoning: String? = nil) -> ParsedReasoningContent {
        var extraReasoning = (explicitReasoning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var text = rawText
        var stillThinking = false

        for pair in tagPairs {
            while let openRange = text.range(of: pair.open, options: .caseInsensitive) {
                if let closeRange = text.range(of: pair.close, options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
                    let inside = String(text[openRange.upperBound..<closeRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inside.isEmpty {
                        extraReasoning = extraReasoning.isEmpty ? inside : (extraReasoning + "\n\n" + inside)
                    }
                    text.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
                } else {
                    // Streaming in progress inside <think> ...
                    let inside = String(text[openRange.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inside.isEmpty {
                        extraReasoning = extraReasoning.isEmpty ? inside : (extraReasoning + "\n\n" + inside)
                    }
                    text.removeSubrange(openRange.lowerBound..<text.endIndex)
                    stillThinking = true
                    break
                }
            }
        }

        return ParsedReasoningContent(
            reasoning: extraReasoning,
            answer: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isStillThinking: stillThinking
        )
    }
}
