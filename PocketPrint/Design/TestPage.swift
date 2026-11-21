import Foundation

/// A self-test print: text sizes, line weights, solid black and each grayscale style.
enum TestPage {
    static func make(printerName: String, profile: PrinterProfile, darkness: Int) -> PrintJob {
        let width = PrinterCatalog.printWidth
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        var parts: [MonoBitmap] = []

        parts.append(TextRaster.renderText("PocketPrint", style: TextStyle(size: 52, bold: true, align: .center), width: width))
        parts.append(TextRaster.renderText("Test page · \(date)", style: TextStyle(size: 22, align: .center), width: width))
        parts.append(BlockRenderer.divider(DividerBlock(style: .solid, thickness: 3), width: width))
        let info = "Printer  \(printerName)\nModel    \(profile.name)\nDarkness \(darkness) of 5"
        parts.append(TextRaster.renderText(info, style: TextStyle(font: .mono, size: 24), width: width))

        parts.append(label("Text sizes", width: width))
        for size in [16.0, 24, 32, 48] {
            parts.append(TextRaster.renderText("Size \(Int(size)) Aa Bb 123", style: TextStyle(size: size), width: width))
        }

        parts.append(label("Line weights 1 · 2 · 3 · 4 dots", width: width))
        var lines = MonoBitmap(width: width, height: 40)
        for (index, weight) in [1, 2, 3, 4].enumerated() {
            lines.fill(x: 0, y: index * 10, width: width, height: weight)
        }
        parts.append(lines)

        parts.append(label("Solid black", width: width))
        parts.append(MonoBitmap(width: width, height: 48, value: 1))

        var gradient = GrayImage(width: width, height: 48)
        for y in 0..<gradient.height {
            for x in 0..<width { gradient.data[y * width + x] = Float(x) / Float(width - 1) }
        }
        for style in [DitherStyle.floydSteinberg, .atkinson, .halftone, .ordered] {
            parts.append(label("Gray · \(style.title)", width: width))
            parts.append(Dither.apply(gradient, style: style))
        }

        if let qr = CodeRaster.qrBitmap("PocketPrint test page", maxSize: 180) {
            parts.append(qr)
        }
        parts.append(BlockRenderer.divider(DividerBlock(style: .scissors, thickness: 2), width: width))

        let bitmap = MonoBitmap.stacked(parts, width: width, spacing: 12)
        return PrintJob(title: "Test Page", kind: .test, bitmap: bitmap, isTextMode: false, design: nil)
    }

    private static func label(_ text: String, width: Int) -> MonoBitmap {
        TextRaster.renderText(text, style: TextStyle(size: 22, bold: true), width: width)
    }
}
