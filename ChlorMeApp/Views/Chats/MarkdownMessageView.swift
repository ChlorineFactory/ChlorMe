import SwiftUI
import UIKit
import ChlorCore

// MARK: - Collapsible Thinking / Reasoning Chain Card

public struct ThinkingDisclosureCard: View {
    public let reasoning: String
    public let isStillThinking: Bool
    public let accent: Color
    public let palette: ChlorPalette
    @State private var isExpanded: Bool = false

    public init(reasoning: String, isStillThinking: Bool = false, accent: Color, palette: ChlorPalette) {
        self.reasoning = reasoning
        self.isStillThinking = isStillThinking
        self.accent = accent
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                ChlorHaptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if isStillThinking {
                        ProgressView()
                            .scaleEffect(0.72)
                            .tint(accent)
                        Text("正在深度思考…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    } else {
                        Image(systemName: "brain.filled.head.profile")
                            .font(.caption)
                            .foregroundStyle(accent)
                        Text("已深度思考 · \(reasoning.count) 字")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if isExpanded || (isStillThinking && reasoning.count < 260) {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlass(cornerRadius: 16, tint: accent, isDark: palette.isDark, interactive: true)
    }
}

// MARK: - Rich Markdown Message Renderer (Headings, Lists, Quotes, Tables, Code Blocks with Copy, Companion *Action*)

public struct MarkdownMessageView: View {
    public let markdown: String
    public let isUser: Bool
    public let accent: Color
    public let palette: ChlorPalette

    public init(markdown: String, isUser: Bool, accent: Color, palette: ChlorPalette) {
        self.markdown = markdown
        self.isUser = isUser
        self.accent = accent
        self.palette = palette
    }

    public var body: some View {
        let blocks = Self.parseBlocks(markdown)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .code(let lang, let code):
            CodeBlockCard(language: lang, code: code, accent: accent, palette: palette)

        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .title3.bold() : (level == 2 ? .headline : .subheadline.bold()))
                .foregroundStyle(isUser ? Color.white : palette.primaryText)

        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isUser ? Color.white.opacity(0.6) : accent)
                    .frame(width: 3)
                inlineText(text)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? Color.white.opacity(0.9) : palette.secondaryText)
            }
            .padding(.vertical, 2)

        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                            Text(h)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minWidth: 76, alignment: .leading)
                        }
                    }
                    .background(accent.opacity(0.16))

                    ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                        Divider().opacity(0.3)
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .frame(minWidth: 76, alignment: .leading)
                            }
                        }
                        .background(rIdx % 2 == 1 ? Color.white.opacity(0.04) : Color.clear)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 0.7))
            }

        case .actionLine(let text):
            Text(text)
                .font(.subheadline.italic())
                .foregroundStyle(isUser ? Color.white.opacity(0.86) : palette.secondaryText)
                .textSelection(.enabled)

        case .divider:
            Divider().opacity(0.4)

        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .foregroundStyle(isUser ? Color.white : palette.primaryText)
                .textSelection(.enabled)
        }
    }

    private func inlineText(_ text: String) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(text)
    }

    // MARK: - Lightweight Block Parser

    private enum MarkdownBlock {
        case code(language: String, code: String)
        case heading(level: Int, text: String)
        case quote(String)
        case table(headers: [String], rows: [[String]])
        case actionLine(String)
        case divider
        case paragraph(String)
    }

    private static func parseBlocks(_ raw: String) -> [MarkdownBlock] {
        let lines = raw.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block ```lang
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.code(language: lang.isEmpty ? "code" : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal divider
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
                i += 1
                continue
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
                i += 1
                continue
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quoteLines.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    i += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Markdown table detection
            if trimmed.contains("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).contains("---"),
               lines[i + 1].contains("|") {
                let headers = splitTableRow(trimmed)
                i += 2
                var rows: [[String]] = []
                while i < lines.count && lines[i].contains("|") && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitTableRow(lines[i]))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // Companion roleplay *action* line
            if trimmed.hasPrefix("*") && trimmed.hasSuffix("*") && !trimmed.hasPrefix("**") && trimmed.count > 2 {
                blocks.append(.actionLine(String(trimmed.dropFirst().dropLast())))
                i += 1
                continue
            }

            // Regular paragraph (merge consecutive normal lines)
            var paraLines: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("```") || next.hasPrefix("# ") || next.hasPrefix("## ") || next.hasPrefix("### ") || next.hasPrefix("> ") || next == "---" {
                    break
                }
                if next.hasPrefix("*") && next.hasSuffix("*") && !next.hasPrefix("**") && next.count > 2 {
                    break
                }
                paraLines.append(lines[i])
                i += 1
            }
            blocks.append(.paragraph(paraLines.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [.paragraph(raw)] : blocks
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct CodeBlockCard: View {
    let language: String
    let code: String
    let accent: Color
    let palette: ChlorPalette
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(accent)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    ChlorHaptics.light()
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制代码", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.bold())
                        .foregroundStyle(copied ? .green : palette.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(palette.isDark ? 0.35 : 0.08))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color.black.opacity(palette.isDark ? 0.42 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.8)
        )
    }
}

// MARK: - Message Attachments & Web Search Sources Strips

public struct MessageAttachmentsRow: View {
    public let attachments: [MessageAttachment]
    public let accent: Color
    public let palette: ChlorPalette
    @State private var previewImage: UIImage?

    public init(attachments: [MessageAttachment], accent: Color, palette: ChlorPalette) {
        self.attachments = attachments
        self.accent = accent
        self.palette = palette
    }

    public var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { att in
                        if att.kind == .image, let img = MediaStorage.loadImage(fileName: att.localFileName) {
                            Button {
                                previewImage = img
                            } label: {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 112, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: att.mimeType == "application/pdf" ? "doc.richtext.fill" : "doc.text.fill")
                                    .foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(att.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(palette.primaryText)
                                        .lineLimit(1)
                                    Text(MemoryBudgetAdvisor.formatBytes(att.byteSize))
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .liquidGlass(cornerRadius: 14, tint: accent, isDark: palette.isDark)
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { previewImage != nil }, set: { if !$0 { previewImage = nil } })) {
                if let img = previewImage {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Button {
                            previewImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding()
                        }
                    }
                }
            }
        }
    }
}

public struct WebSourcesStrip: View {
    public let sources: [WebSearchSource]
    public let accent: Color
    public let palette: ChlorPalette

    public init(sources: [WebSearchSource], accent: Color, palette: ChlorPalette) {
        self.sources = sources
        self.accent = accent
        self.palette = palette
    }

    public var body: some View {
        if !sources.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { idx, src in
                        if let url = URL(string: src.url) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                        .font(.caption2)
                                        .foregroundStyle(accent)
                                    Text("[\(idx + 1)] \(src.title)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(palette.primaryText)
                                        .lineLimit(1)
                                        .frame(maxWidth: 160)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .liquidGlassCapsule(tint: accent, isDark: palette.isDark, interactive: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
