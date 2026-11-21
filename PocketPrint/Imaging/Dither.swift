import Foundation

/// How grayscale content is turned into black and white dots.
enum DitherStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case floydSteinberg
    case atkinson
    case halftone
    case ordered
    case threshold
    case document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floydSteinberg: return "Photo"
        case .atkinson: return "Bright"
        case .halftone: return "Halftone"
        case .ordered: return "Pattern"
        case .threshold: return "Line Art"
        case .document: return "Document"
        }
    }

    var systemImage: String {
        switch self {
        case .floydSteinberg: return "photo"
        case .atkinson: return "sun.max"
        case .halftone: return "circle.grid.3x3.fill"
        case .ordered: return "checkerboard.rectangle"
        case .threshold: return "scribble"
        case .document: return "doc.text"
        }
    }

    var usesThreshold: Bool { self == .threshold }
}

enum Dither {
    static func apply(_ image: GrayImage, style: DitherStyle, threshold: Float = 0.5) -> MonoBitmap {
        switch style {
        case .floydSteinberg: return floydSteinberg(image)
        case .atkinson: return atkinson(image)
        case .halftone: return ordered(image, matrix: clusteredDot8, size: 8)
        case .ordered: return ordered(image, matrix: bayer8, size: 8)
        case .threshold: return self.threshold(image, level: threshold)
        case .document: return adaptive(image)
        }
    }

    static func threshold(_ image: GrayImage, level: Float = 0.5) -> MonoBitmap {
        var out = MonoBitmap(width: image.width, height: image.height)
        image.data.withUnsafeBufferPointer { src in
            var pixels = [UInt8](repeating: 0, count: src.count)
            for i in 0..<src.count where src[i] < level { pixels[i] = 1 }
            out = MonoBitmap(width: image.width, height: image.height, pixels: pixels)
        }
        return out
    }

    /// Error diffusion with serpentine scanning, which avoids directional "worm" artefacts.
    static func floydSteinberg(_ image: GrayImage) -> MonoBitmap {
        let w = image.width, h = image.height
        var buffer = image.data
        var pixels = [UInt8](repeating: 0, count: w * h)
        buffer.withUnsafeMutableBufferPointer { b in
            for y in 0..<h {
                let leftToRight = y % 2 == 0
                let step = leftToRight ? 1 : -1
                var x = leftToRight ? 0 : w - 1
                for _ in 0..<w {
                    let i = y * w + x
                    let old = b[i]
                    let new: Float = old < 0.5 ? 0 : 1
                    if new == 0 { pixels[i] = 1 }
                    let error = old - new
                    let nx = x + step
                    if nx >= 0, nx < w { b[i + step] += error * (7 / 16) }
                    if y + 1 < h {
                        let below = i + w
                        let px = x - step
                        if px >= 0, px < w { b[below - step] += error * (3 / 16) }
                        b[below] += error * (5 / 16)
                        if nx >= 0, nx < w { b[below + step] += error * (1 / 16) }
                    }
                    x += step
                }
            }
        }
        return MonoBitmap(width: w, height: h, pixels: pixels)
    }

    /// Atkinson diffusion only spreads 3/4 of the error, keeping highlights clean and contrast high.
    static func atkinson(_ image: GrayImage) -> MonoBitmap {
        let w = image.width, h = image.height
        var buffer = image.data
        var pixels = [UInt8](repeating: 0, count: w * h)
        let offsets: [(Int, Int)] = [(1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)]
        buffer.withUnsafeMutableBufferPointer { b in
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    let old = b[i]
                    let new: Float = old < 0.5 ? 0 : 1
                    if new == 0 { pixels[i] = 1 }
                    let share = (old - new) / 8
                    for (dx, dy) in offsets {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, nx < w, ny < h { b[ny * w + nx] += share }
                    }
                }
            }
        }
        return MonoBitmap(width: w, height: h, pixels: pixels)
    }

    static func ordered(_ image: GrayImage, matrix: [Float], size: Int) -> MonoBitmap {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        image.data.withUnsafeBufferPointer { src in
            for y in 0..<h {
                let row = (y % size) * size
                for x in 0..<w {
                    let i = y * w + x
                    if src[i] < matrix[row + x % size] { pixels[i] = 1 }
                }
            }
        }
        return MonoBitmap(width: w, height: h, pixels: pixels)
    }

    /// Local-mean (Bradley) thresholding: removes shadows and uneven lighting from photos of documents.
    static func adaptive(_ image: GrayImage, sensitivity: Float = 0.15) -> MonoBitmap {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return MonoBitmap(width: w, height: h) }
        var integral = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var rowSum: Double = 0
            for x in 0..<w {
                rowSum += Double(image.data[y * w + x])
                integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + rowSum
            }
        }
        let radius = max(8, w / 16)
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - radius), y1 = min(h - 1, y + radius)
            for x in 0..<w {
                let x0 = max(0, x - radius), x1 = min(w - 1, x + radius)
                let count = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                let sum = integral[(y1 + 1) * (w + 1) + x1 + 1] - integral[y0 * (w + 1) + x1 + 1]
                    - integral[(y1 + 1) * (w + 1) + x0] + integral[y0 * (w + 1) + x0]
                let value = Double(image.data[y * w + x])
                if value * count < sum * Double(1 - sensitivity) || value < 0.12 { pixels[y * w + x] = 1 }
            }
        }
        return MonoBitmap(width: w, height: h, pixels: pixels)
    }

    // MARK: Threshold matrices (normalised to 0...1)

    static let bayer8: [Float] = {
        let m: [Int] = [
            0, 32, 8, 40, 2, 34, 10, 42,
            48, 16, 56, 24, 50, 18, 58, 26,
            12, 44, 4, 36, 14, 46, 6, 38,
            60, 28, 52, 20, 62, 30, 54, 22,
            3, 35, 11, 43, 1, 33, 9, 41,
            51, 19, 59, 27, 49, 17, 57, 25,
            15, 47, 7, 39, 13, 45, 5, 37,
            63, 31, 55, 23, 61, 29, 53, 21,
        ]
        return m.map { (Float($0) + 0.5) / 64 }
    }()

    /// 45° clustered-dot screen. Clustered dots survive thermal dot gain better than dispersed ones.
    static let clusteredDot8: [Float] = {
        let m: [Int] = [
            24, 10, 12, 26, 35, 47, 49, 37,
            8, 0, 2, 14, 45, 59, 61, 51,
            22, 6, 4, 16, 43, 57, 63, 53,
            30, 20, 18, 28, 33, 41, 55, 39,
            34, 46, 48, 36, 25, 11, 13, 27,
            44, 58, 60, 50, 9, 1, 3, 15,
            42, 56, 62, 52, 23, 7, 5, 17,
            32, 40, 54, 38, 31, 21, 19, 29,
        ]
        return m.map { (Float($0) + 0.5) / 64 }
    }()
}
