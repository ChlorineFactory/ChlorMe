import Foundation
import UIKit

/// Stores compressed local images (character avatars & custom chat wallpapers) under Documents/Media.
public enum MediaStorage {
    public static var mediaDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func saveImageData(_ rawData: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.82) -> String? {
        guard let image = UIImage(data: rawData) else { return nil }
        let resized = resizeIfNeeded(image, maxDimension: maxDimension)
        guard let jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        let fileName = "img-\(UUID().uuidString).jpg"
        let dest = mediaDirectoryURL.appendingPathComponent(fileName)
        do {
            try jpeg.write(to: dest, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    public static func loadImage(fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let path = mediaDirectoryURL.appendingPathComponent(fileName).path
        return UIImage(contentsOfFile: path)
    }

    public static func deleteImage(fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        let url = mediaDirectoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

public enum ChlorHaptics {
    @MainActor
    public static func light() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }

    @MainActor
    public static func medium() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    @MainActor
    public static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }
}
