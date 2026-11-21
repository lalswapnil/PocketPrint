import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// QR codes and barcodes generated on-device with Core Image, scaled with whole-dot modules.
enum CodeRaster {
    private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    enum Correction: String, Codable, CaseIterable, Identifiable, Sendable {
        case low = "L", medium = "M", quartile = "Q", high = "H"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .quartile: return "High"
            case .high: return "Max"
            }
        }
    }

    /// Module grid (true = dark) without the quiet zone.
    static func qrModules(_ text: String, correction: Correction = .medium) -> (size: Int, modules: [Bool])? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction.rawValue
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        let gray = GrayImage(cgImage: cgImage, width: cgImage.width, height: cgImage.height, interpolation: .none)
        let dark = gray.data.map { $0 < 0.5 }
        var minX = gray.width, minY = gray.height, maxX = -1, maxY = -1
        for y in 0..<gray.height {
            for x in 0..<gray.width where dark[y * gray.width + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let size = max(maxX - minX + 1, maxY - minY + 1)
        var modules = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let sx = minX + x, sy = minY + y
                if sx < gray.width, sy < gray.height { modules[y * size + x] = dark[sy * gray.width + sx] }
            }
        }
        return (size, modules)
    }

    /// QR code at most `maxSize` dots wide, with a quiet zone of `quietModules` modules.
    static func qrBitmap(_ text: String, maxSize: Int, correction: Correction = .medium, quietModules: Int = 2) -> MonoBitmap? {
        guard let (size, modules) = qrModules(text, correction: correction) else { return nil }
        let scale = max(1, maxSize / (size + quietModules * 2))
        let total = (size + quietModules * 2) * scale
        var out = MonoBitmap(width: total, height: total)
        for y in 0..<size {
            for x in 0..<size where modules[y * size + x] {
                out.fill(x: (x + quietModules) * scale, y: (y + quietModules) * scale, width: scale, height: scale)
            }
        }
        return out
    }

    /// Code 128 bars scaled by a whole number of dots per module to fit `maxWidth`.
    static func code128Bitmap(_ text: String, maxWidth: Int, height: Int) -> MonoBitmap? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII }) else { return nil }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(text.utf8)
        filter.quietSpace = 0
        filter.barcodeHeight = 4
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        let gray = GrayImage(cgImage: cgImage, width: cgImage.width, height: cgImage.height, interpolation: .none)
        let row = gray.height / 2
        let bars = (0..<gray.width).map { gray.data[row * gray.width + $0] < 0.5 }
        guard bars.count <= maxWidth else { return nil }
        let scale = max(1, maxWidth / bars.count)
        var out = MonoBitmap(width: bars.count * scale, height: max(8, height))
        for (index, dark) in bars.enumerated() where dark {
            out.fill(x: index * scale, y: 0, width: scale, height: out.height)
        }
        return out
    }
}
