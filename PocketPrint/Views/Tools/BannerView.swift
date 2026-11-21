import CoreText
import SwiftUI

struct BannerOptions: Hashable {
    var text = "HAPPY BIRTHDAY"
    var font: FontFamily = .system
    var bold = true
    var italic = false
    var inverted = false
    var border = true
}

enum BannerRenderer {
    /// Renders the banner as it reads (left to right), `PrinterCatalog.printWidth` dots tall.
    static func render(_ options: BannerOptions) -> MonoBitmap? {
        let lines = options.text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3)
        guard !lines.isEmpty else { return nil }
        let height = PrinterCatalog.printWidth
        let margin = options.border ? 30 : 12
        let gap = 10
        let band = (height - margin * 2 - gap * (lines.count - 1)) / lines.count
        let rendered = lines.map { renderLine($0, height: band, options: options) }
        let length = (rendered.map(\.width).max() ?? 0) + 64
        var banner = MonoBitmap(width: length, height: height)
        var y = margin
        for line in rendered {
            banner.draw(line, x: (length - line.width) / 2, y: y)
            y += band + gap
        }
        if options.border {
            banner.fill(x: 0, y: 6, width: length, height: 6)
            banner.fill(x: 0, y: height - 12, width: length, height: 6)
        }
        if options.inverted { banner.invert() }
        return banner
    }

    /// One line whose ink fills the band height, measured from real glyph outlines.
    private static func renderLine(_ text: String, height: Int, options: BannerOptions) -> MonoBitmap {
        func line(size: CGFloat) -> CTLine {
            let font = options.font.font(size: size, bold: options.bold, italic: options.italic)
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
            return CTLineCreateWithAttributedString(string)
        }
        let probe = CTLineGetBoundsWithOptions(line(size: 200), .useGlyphPathBounds)
        guard probe.height > 0 else { return MonoBitmap(width: 1, height: height) }
        let size = 200 * CGFloat(height) * 0.94 / probe.height
        let final = line(size: size)
        let bounds = CTLineGetBoundsWithOptions(final, .useGlyphPathBounds)
        let width = Int(ceil(bounds.width)) + 8
        let gray = TextRaster.draw(width: width, height: height) { context in
            context.saveGState()
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 4 - bounds.minX, y: (CGFloat(height) - bounds.height) / 2 - bounds.minY)
            CTLineDraw(final, context)
            context.restoreGState()
        }
        return Dither.threshold(gray, level: 0.55)
    }
}

struct BannerView: View {
    @State private var options = BannerOptions()
    @State private var banner: MonoBitmap?
    @State private var preview: UIImage?
    @State private var printJob: PrintJob?

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: true) {
                    Group {
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .interpolation(.none)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Text("Type some text below")
                                .foregroundStyle(Color.gray)
                                .frame(width: 280)
                        }
                    }
                    .frame(height: 110)
                    .padding(10)
                    .background(Color.white)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.white)
            } footer: {
                if let banner {
                    Text("Prints sideways along the paper · \(PaperLength.describe(dots: banner.width)) long")
                }
            }

            Section("Text") {
                TextField("Banner text", text: $options.text, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.title3.weight(.semibold))
                Text("Up to 3 lines. Each line is stacked across the paper width.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Style") {
                FontChips(font: $options.font)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                HStack {
                    Toggle(isOn: $options.bold) { Image(systemName: "bold") }
                        .accessibilityLabel("Bold")
                    Toggle(isOn: $options.italic) { Image(systemName: "italic") }
                        .accessibilityLabel("Italic")
                    Spacer()
                }
                .toggleStyle(.button)
                Toggle("Border lines", isOn: $options.border)
                Toggle("White text on black", isOn: $options.inverted)
            }
        }
        .navigationTitle("Banner")
        .navigationBarTitleDisplayMode(.inline)
        .bottomActionBar {
            EditorActionBar(isPrintDisabled: banner == nil) {
                guard let banner else { return }
                printJob = PrintJob(title: options.text.replacingOccurrences(of: "\n", with: " "), kind: .banner,
                                    bitmap: banner.rotated(quarterTurns: 1), isTextMode: true, design: nil)
            }
        }
        .sheet(item: $printJob) { PrintSheet(job: $0) }
        .task(id: options) {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let current = options
            let result = await Task.detached(priority: .userInitiated) { BannerRenderer.render(current) }.value
            guard !Task.isCancelled else { return }
            banner = result
            preview = result?.makeCGImage().map { UIImage(cgImage: $0) }
        }
    }
}
