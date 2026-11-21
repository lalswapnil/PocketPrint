import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A 1-bit image, one byte per pixel (1 = black/burned dot, 0 = white), row-major.
struct MonoBitmap: Equatable, Hashable, Sendable {
    let width: Int
    private(set) var height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int, value: UInt8 = 0) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.pixels = [UInt8](repeating: value, count: self.width * self.height)
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    var isEmpty: Bool { width == 0 || height == 0 }

    /// Physical length on paper at 8 dots per millimetre.
    var lengthMillimeters: Double { Double(height) / PrinterCatalog.dotsPerMillimeter }

    subscript(x: Int, y: Int) -> Bool {
        get { pixels[y * width + x] != 0 }
        set { pixels[y * width + x] = newValue ? 1 : 0 }
    }

    // MARK: Drawing

    mutating func fill(x: Int, y: Int, width w: Int, height h: Int, value: UInt8 = 1) {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for row in y0..<y1 {
            let base = row * width
            for col in x0..<x1 { pixels[base + col] = value }
        }
    }

    mutating func invert(x: Int = 0, y: Int = 0, width w: Int? = nil, height h: Int? = nil) {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + (w ?? width)), y1 = min(height, y + (h ?? height))
        guard x0 < x1, y0 < y1 else { return }
        for row in y0..<y1 {
            let base = row * width
            for col in x0..<x1 { pixels[base + col] ^= 1 }
        }
    }

    /// Draws `other` with its top-left corner at (x, y). Black pixels are OR-ed in.
    mutating func draw(_ other: MonoBitmap, x: Int, y: Int, opaque: Bool = false) {
        for sy in 0..<other.height {
            let ty = y + sy
            guard ty >= 0, ty < height else { continue }
            let srcBase = sy * other.width
            let dstBase = ty * width
            for sx in 0..<other.width {
                let tx = x + sx
                guard tx >= 0, tx < width else { continue }
                let value = other.pixels[srcBase + sx]
                if opaque {
                    pixels[dstBase + tx] = value
                } else if value != 0 {
                    pixels[dstBase + tx] = 1
                }
            }
        }
    }

    // MARK: Geometry

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> MonoBitmap {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return MonoBitmap(width: max(0, w), height: 0) }
        var out = MonoBitmap(width: x1 - x0, height: y1 - y0)
        for row in y0..<y1 {
            let src = row * width
            let dst = (row - y0) * out.width
            for col in x0..<x1 { out.pixels[dst + col - x0] = pixels[src + col] }
        }
        return out
    }

    /// Rotates by quarter turns clockwise.
    func rotated(quarterTurns: Int) -> MonoBitmap {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return self }
        if turns == 2 {
            return MonoBitmap(width: width, height: height, pixels: pixels.reversed())
        }
        var out = MonoBitmap(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] != 0 {
                if turns == 1 {
                    out.pixels[x * out.width + (height - 1 - y)] = 1
                } else {
                    out.pixels[(width - 1 - x) * out.width + y] = 1
                }
            }
        }
        return out
    }

    /// Places this bitmap on a canvas of `targetWidth`, aligned horizontally.
    func placed(inWidth targetWidth: Int, alignment: HorizontalPlacement = .center) -> MonoBitmap {
        guard targetWidth != width else { return self }
        if width > targetWidth {
            let offset: Int
            switch alignment {
            case .leading: offset = 0
            case .center: offset = (width - targetWidth) / 2
            case .trailing: offset = width - targetWidth
            }
            return cropped(x: offset, y: 0, width: targetWidth, height: height)
        }
        var out = MonoBitmap(width: targetWidth, height: height)
        let x: Int
        switch alignment {
        case .leading: x = 0
        case .center: x = (targetWidth - width) / 2
        case .trailing: x = targetWidth - width
        }
        out.draw(self, x: x, y: 0, opaque: true)
        return out
    }

    func padded(top: Int = 0, bottom: Int = 0, left: Int = 0, right: Int = 0) -> MonoBitmap {
        var out = MonoBitmap(width: width + left + right, height: height + top + bottom)
        out.draw(self, x: left, y: top, opaque: true)
        return out
    }

    /// Bounding box of black pixels, or nil if blank.
    func contentBounds() -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let base = y * width
            for x in 0..<width where pixels[base + x] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        return maxX >= 0 ? (minX, minY, maxX, maxY) : nil
    }

    var isBlank: Bool { !pixels.contains(1) }

    /// Stacks bitmaps vertically on a canvas of `width`, centring narrower parts.
    static func stacked(_ parts: [MonoBitmap], width: Int, spacing: Int = 0) -> MonoBitmap {
        let visible = parts.filter { !$0.isEmpty }
        let total = visible.reduce(0) { $0 + $1.height } + max(0, visible.count - 1) * spacing
        var out = MonoBitmap(width: width, height: total)
        var y = 0
        for part in visible {
            out.draw(part.placed(inWidth: width), x: 0, y: y, opaque: true)
            y += part.height + spacing
        }
        return out
    }

    // MARK: Conversion

    /// 8-bit grayscale image (black = 0, white = 255) for display and export.
    func makeCGImage() -> CGImage? {
        guard !isEmpty else { return nil }
        var gray = [UInt8](repeating: 255, count: pixels.count)
        for i in 0..<pixels.count where pixels[i] != 0 { gray[i] = 0 }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func pngData() -> Data? {
        guard let image = makeCGImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    init?(pngData: Data) {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let gray = GrayImage(cgImage: image, width: image.width, height: image.height, interpolation: .none)
        self = Dither.threshold(gray, level: 0.5)
    }
}

enum HorizontalPlacement: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing
}
