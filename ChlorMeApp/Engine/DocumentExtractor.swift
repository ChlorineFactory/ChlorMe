import Foundation
import PDFKit
import UIKit
import ChlorCore

/// Extracts text from PDF / TXT / Markdown / source code files and encodes local images for multimodal LLM calls.
public enum DocumentExtractor {
    public static func importDocument(from securityScopedURL: URL) throws -> MessageAttachment {
        let accessed = securityScopedURL.startAccessingSecurityScopedResource()
        defer { if accessed { securityScopedURL.stopAccessingSecurityScopedResource() } }

        let fileName = securityScopedURL.lastPathComponent
        let ext = securityScopedURL.pathExtension.lowercased()
        let data = try Data(contentsOf: securityScopedURL)
        let size = Int64(data.count)

        if ext == "pdf" {
            let text = extractPDFText(from: data)
            return MessageAttachment(
                kind: .document,
                displayName: fileName,
                mimeType: "application/pdf",
                extractedText: text.isEmpty ? "（该 PDF 未检测到可提取文本，可能是纯扫描图片）" : text,
                byteSize: size
            )
        }

        // Plain text / Markdown / JSON / Code
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
        let clipped = String(decoded.prefix(18_000))
        return MessageAttachment(
            kind: .document,
            displayName: fileName,
            mimeType: "text/plain",
            extractedText: clipped,
            byteSize: size
        )
    }

    public static func makeImageAttachment(from rawData: Data, displayName: String = "photo.jpg") -> MessageAttachment? {
        guard let savedName = MediaStorage.saveImageData(rawData, maxDimension: 1280, quality: 0.80) else {
            return nil
        }
        let path = MediaStorage.mediaDirectoryURL.appendingPathComponent(savedName).path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? Int64(rawData.count)
        return MessageAttachment(
            kind: .image,
            displayName: displayName,
            localFileName: savedName,
            mimeType: "image/jpeg",
            byteSize: size
        )
    }

    public static func loadPromptImageData(for attachment: MessageAttachment) -> PromptImageData? {
        guard attachment.kind == .image,
              let fileName = attachment.localFileName,
              let image = MediaStorage.loadImage(fileName: fileName),
              let jpeg = image.jpegData(compressionQuality: 0.78) else {
            return nil
        }
        return PromptImageData(mimeType: "image/jpeg", base64Data: jpeg.base64EncodedString())
    }

    private static func extractPDFText(from data: Data) -> String {
        guard let pdf = PDFDocument(data: data) else { return "" }
        var chunks: [String] = []
        let pageLimit = min(pdf.pageCount, 40)
        for idx in 0..<pageLimit {
            if let page = pdf.page(at: idx), let str = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                chunks.append("--- 第 \(idx + 1) 页 ---\n\(str)")
            }
            if chunks.joined().count > 16_000 { break }
        }
        return String(chunks.joined(separator: "\n\n").prefix(18_000))
    }
}
