import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Keeps source photos used in designs on disk (upright, at most 2048 px) so designs can be re-edited.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let directory: URL
    private let cache = NSCache<NSString, CGImageBox>()

    private final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketPrint/Images", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cache.countLimit = 24
    }

    /// Saves an image and returns its identifier.
    @discardableResult
    func save(_ image: UIImage, maxDimension: CGFloat = 2048) -> String? {
        guard let upright = Self.uprightCGImage(image, maxDimension: maxDimension) else { return nil }
        let id = UUID().uuidString
        guard Self.writeJPEG(upright, to: url(for: id)) else { return nil }
        cache.setObject(CGImageBox(upright), forKey: id as NSString)
        return id
    }

    func save(data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return save(image)
    }

    func cgImage(for id: String) -> CGImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached.image }
        guard let source = CGImageSourceCreateWithURL(url(for: id) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache.setObject(CGImageBox(image), forKey: id as NSString)
        return image
    }

    func uiImage(for id: String) -> UIImage? {
        cgImage(for: id).map { UIImage(cgImage: $0) }
    }

    func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    /// Removes stored images that are not referenced and older than a day (they may belong to an open editor).
    func removeUnreferenced(keeping ids: Set<String>) {
        let cutoff = Date().addingTimeInterval(-86_400)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            guard !ids.contains(id) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
                cache.removeObject(forKey: id as NSString)
            }
        }
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("jpg")
    }

    /// Applies EXIF orientation and limits the size, compositing transparency over white.
    static func uprightCGImage(_ image: UIImage, maxDimension: CGFloat) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width * image.scale, size.height * image.scale)) * image.scale
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

extension CGImage {
    /// Rotates by quarter turns clockwise and optionally mirrors horizontally.
    func oriented(quarterTurns: Int, mirrored: Bool) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns == 0, !mirrored { return self }
        let swap = turns % 2 == 1
        let w = swap ? height : width, h = swap ? width : height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Core Graphics uses a bottom-left origin, so a clockwise turn on screen is a negative rotation here.
        // The image is rotated first, then mirrored, so "flip" mirrors what the user sees.
        context.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        if mirrored { context.scaleBy(x: -1, y: 1) }
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.draw(self, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }

    /// Crops to a normalised rectangle (origin top-left).
    func cropped(normalized rect: CGRect) -> CGImage? {
        let r = CGRect(x: rect.minX * CGFloat(width), y: rect.minY * CGFloat(height),
                       width: rect.width * CGFloat(width), height: rect.height * CGFloat(height)).integral
        let bounded = r.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !bounded.isNull, bounded.width >= 1, bounded.height >= 1 else { return nil }
        return cropping(to: bounded)
    }
}
