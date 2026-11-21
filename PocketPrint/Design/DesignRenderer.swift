import UIKit

/// Result of rendering a design: the exact dots that will be printed, plus layout info for the editor.
struct RenderedDesign: Sendable {
    var bitmap: MonoBitmap
    /// Vertical extent of each block in `bitmap` coordinates.
    var blockRanges: [UUID: Range<Int>]
    /// Blocks that print nothing visible yet; the editor outlines them with a hint.
    var hints: [UUID: String]
    var isTextMode: Bool
    /// Content is longer than the fixed label length.
    var overflows: Bool

    static let empty = RenderedDesign(bitmap: MonoBitmap(width: PrinterCatalog.printWidth, height: 0),
                                      blockRanges: [:], hints: [:], isTextMode: true, overflows: false)
}

/// Renders designs off the main thread, re-rendering only blocks that changed.
actor DesignRenderer {
    enum Purpose { case preview, print }

    private struct CacheEntry {
        let content: BlockContent
        let width: Int
        let timeKey: String
        let bitmap: MonoBitmap
    }

    private var cache: [UUID: CacheEntry] = [:]
    private let images: ImageStore

    init(images: ImageStore = .shared) {
        self.images = images
    }

    func render(_ design: Design, purpose: Purpose = .print) -> RenderedDesign {
        let paperWidth = PrinterCatalog.printWidth
        let inset = design.frame.inset
        let contentWidth = max(64, paperWidth - 2 * (max(0, design.margin) + inset))
        let timeKey = Self.timeKey()
        let previewHintHeight = 64

        var parts: [(id: UUID, bitmap: MonoBitmap)] = []
        var hints: [UUID: String] = [:]
        for block in design.blocks {
            var bitmap = cachedBitmap(for: block, width: contentWidth, timeKey: timeKey)
            if purpose == .preview, let hint = Self.hint(for: block.content, isEmpty: bitmap.height == 0) {
                hints[block.id] = hint
                if bitmap.height == 0 {
                    bitmap = MonoBitmap(width: contentWidth, height: previewHintHeight)
                }
            }
            if bitmap.height > 0 {
                parts.append((block.id, bitmap))
            }
        }
        let liveIDs = Set(design.blocks.map(\.id))
        cache = cache.filter { liveIDs.contains($0.key) }

        let spacing = max(0, design.spacing)
        let verticalPadding = design.frame == .none ? 0 : inset + 6
        let contentHeight = parts.reduce(0) { $0 + $1.bitmap.height } + max(0, parts.count - 1) * spacing
        var totalHeight = contentHeight + verticalPadding * 2
        let fixedHeight = design.lengthMM > 0 ? Int(Double(design.lengthMM) * PrinterCatalog.dotsPerMillimeter) : 0
        var top = verticalPadding
        if fixedHeight > totalHeight {
            top += (fixedHeight - totalHeight) / 2
            totalHeight = fixedHeight
        }
        let overflows = fixedHeight > 0 && contentHeight + verticalPadding * 2 > fixedHeight

        var canvas = MonoBitmap(width: paperWidth, height: totalHeight)
        var ranges: [UUID: Range<Int>] = [:]
        var y = top
        for part in parts {
            canvas.draw(part.bitmap.placed(inWidth: contentWidth), x: design.margin + inset, y: y)
            ranges[part.id] = y..<(y + part.bitmap.height)
            y += part.bitmap.height + spacing
        }
        if design.frame != .none, totalHeight > 0 {
            canvas.draw(FrameRenderer.render(design.frame, width: paperWidth, height: totalHeight), x: 0, y: 0)
        }
        return RenderedDesign(bitmap: canvas, blockRanges: ranges, hints: hints,
                              isTextMode: !design.prefersImageMode, overflows: overflows)
    }

    private func cachedBitmap(for block: Block, width: Int, timeKey: String) -> MonoBitmap {
        if let entry = cache[block.id], entry.content == block.content, entry.width == width, entry.timeKey == timeKey {
            return entry.bitmap
        }
        let bitmap = BlockRenderer.render(block.content, width: width, images: images)
        cache[block.id] = CacheEntry(content: block.content, width: width, timeKey: timeKey, bitmap: bitmap)
        return bitmap
    }

    private static func timeKey() -> String {
        let minute = Int(Date().timeIntervalSince1970 / 60)
        return String(minute)
    }

    private static func hint(for content: BlockContent, isEmpty: Bool) -> String? {
        switch content {
        case .spacer: return "Space"
        case .text where isEmpty: return "Tap to type text"
        case .qr where isEmpty: return "Tap to add QR content"
        case .barcode where isEmpty: return "Barcode needs plain letters or numbers"
        case .image where isEmpty: return "Photo not available"
        case .symbol where isEmpty: return "Tap to pick an emoji or icon"
        default: return nil
        }
    }
}

/// Renders individual blocks at a given content width.
enum BlockRenderer {
    static func render(_ content: BlockContent, width: Int, images: ImageStore = .shared) -> MonoBitmap {
        switch content {
        case .text(let block): return text(block, width: width)
        case .image(let block): return image(block, width: width, images: images)
        case .checklist(let block): return checklist(block, width: width)
        case .qr(let block): return qr(block, width: width)
        case .barcode(let block): return barcode(block, width: width)
        case .divider(let block): return divider(block, width: width)
        case .spacer(let block): return MonoBitmap(width: width, height: max(0, block.height))
        case .symbol(let block): return symbol(block, width: width)
        case .calendar(let block): return calendar(block, width: width)
        }
    }

    // MARK: Text

    static func text(_ block: TextBlock, width: Int) -> MonoBitmap {
        let text = TextTokens.resolve(block.text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MonoBitmap(width: width, height: 0)
        }
        guard block.inverted else {
            return TextRaster.renderText(text, style: block.style, width: width)
        }
        let pad = max(8, Int(block.style.size * 0.3))
        let inner = TextRaster.renderText(text, style: block.style, width: max(16, width - 2 * pad))
        var band = inner.padded(top: pad / 2, bottom: pad / 2, left: pad, right: pad)
        band.invert()
        return band
    }

    // MARK: Image

    static func image(_ block: ImageBlock, width: Int, images: ImageStore) -> MonoBitmap {
        guard let source = images.cgImage(for: block.imageID),
              let oriented = source.oriented(quarterTurns: block.rotation, mirrored: block.mirrored) else {
            return MonoBitmap(width: width, height: 0)
        }
        var cropped = oriented
        if let crop = block.crop,
           let region = oriented.cropped(normalized: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)) {
            cropped = region
        }
        let percent = min(100, max(20, block.widthPercent))
        let targetWidth = max(16, Int(Double(width) * percent / 100))
        let gray = GrayImage(cgImage: cropped, fittingWidth: targetWidth, maxHeight: 6000)
        return ImagePipeline.mono(from: gray, adjustments: block.adjustments).placed(inWidth: width)
    }

    // MARK: Checklist

    static func checklist(_ block: ChecklistBlock, width: Int) -> MonoBitmap {
        guard !block.items.isEmpty else { return MonoBitmap(width: width, height: 0) }
        var style = block.style
        style.align = .left
        let fontSize = CGFloat(style.size)
        let font = style.font.font(size: fontSize, bold: style.bold, italic: style.italic)
        let markerColumn = ceil(block.marker == .number ? fontSize * 1.7 : fontSize * 1.25)
        let textWidth = max(32, CGFloat(width) - markerColumn)
        let rowGap = ceil(fontSize * 0.35)

        let rows: [(item: ChecklistItem, string: NSAttributedString, height: CGFloat)] = block.items.map { item in
            let text = TextTokens.resolve(item.text)
            let string = TextRaster.attributed(text.isEmpty ? " " : text, style: style)
            let height = max(ceil(font.lineHeight), TextRaster.measure(string, width: textWidth).height)
            return (item, string, height)
        }
        let total = rows.reduce(0) { $0 + $1.height } + rowGap * CGFloat(max(0, rows.count - 1)) + 4
        let gray = TextRaster.draw(width: width, height: Int(ceil(total))) { context in
            context.setStrokeColor(UIColor.black.cgColor)
            context.setFillColor(UIColor.black.cgColor)
            var y: CGFloat = 2
            for (index, row) in rows.enumerated() {
                let markerSize = round(fontSize * 0.7)
                let lineCenter = y + font.lineHeight / 2
                let markerRect = CGRect(x: 2, y: round(lineCenter - markerSize / 2), width: markerSize, height: markerSize)
                let lineWidth = max(2, round(markerSize / 11))
                context.setLineWidth(lineWidth)
                switch block.marker {
                case .box:
                    context.stroke(markerRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
                    if row.item.checked { drawCheck(in: markerRect, context: context, lineWidth: lineWidth * 1.4) }
                case .circle:
                    context.strokeEllipse(in: markerRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
                    if row.item.checked { context.fillEllipse(in: markerRect.insetBy(dx: markerSize * 0.25, dy: markerSize * 0.25)) }
                case .bullet:
                    context.fillEllipse(in: markerRect.insetBy(dx: markerSize * 0.28, dy: markerSize * 0.28))
                case .dash:
                    context.fill(CGRect(x: markerRect.minX, y: round(lineCenter - lineWidth / 2), width: markerSize, height: lineWidth))
                case .number:
                    let number = TextRaster.attributed("\(index + 1).", style: TextStyle(font: style.font, size: style.size, bold: true))
                    number.draw(at: CGPoint(x: 2, y: y))
                }
                if row.item.text.isEmpty {
                    // A writing line for filling in by hand.
                    let baseline = round(y + font.ascender + 4)
                    context.fill(CGRect(x: markerColumn, y: baseline, width: textWidth - 4, height: 2))
                } else {
                    row.string.draw(with: CGRect(x: markerColumn, y: y, width: textWidth, height: row.height + 2),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
                y += row.height + rowGap
            }
        }
        return Dither.threshold(gray, level: 0.55)
    }

    private static func drawCheck(in rect: CGRect, context: CGContext, lineWidth: CGFloat) {
        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.52))
        context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.74))
        context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.26))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Codes

    static func qr(_ block: QRBlock, width: Int) -> MonoBitmap {
        let payload = block.payload
        let maxSize = Int(Double(width) * min(100, max(25, block.sizePercent)) / 100)
        guard !payload.isEmpty, let code = CodeRaster.qrBitmap(payload, maxSize: maxSize, correction: block.correction) else {
            return MonoBitmap(width: width, height: 0)
        }
        var parts = [code]
        let caption = TextTokens.resolve(block.caption)
        if !caption.isEmpty {
            parts.append(TextRaster.renderText(caption, style: TextStyle(size: 24, bold: true, align: .center), width: width))
        }
        return MonoBitmap.stacked(parts, width: width, spacing: 2)
    }

    static func barcode(_ block: BarcodeBlock, width: Int) -> MonoBitmap {
        guard let bars = CodeRaster.code128Bitmap(block.text, maxWidth: width - 8, height: block.height) else {
            return MonoBitmap(width: width, height: 0)
        }
        var parts = [bars]
        if block.showText {
            parts.append(TextRaster.renderText(block.text, style: TextStyle(font: .mono, size: 24, align: .center), width: width))
        }
        return MonoBitmap.stacked(parts, width: width, spacing: 6)
    }

    // MARK: Dividers

    static func divider(_ block: DividerBlock, width: Int) -> MonoBitmap {
        let t = max(1, min(12, block.thickness))
        switch block.style {
        case .solid:
            return MonoBitmap(width: width, height: t, value: 1)
        case .dashed:
            var out = MonoBitmap(width: width, height: t)
            let dash = 12 + t * 2, gap = 8 + t
            var x = 0
            while x < width { out.fill(x: x, y: 0, width: dash, height: t); x += dash + gap }
            return out
        case .dotted:
            var out = MonoBitmap(width: width, height: t)
            let step = max(4, t * 3)
            var x = 0
            while x < width { out.fill(x: x, y: 0, width: t, height: t); x += step }
            return out
        case .double:
            var out = MonoBitmap(width: width, height: t * 3 + 2)
            out.fill(x: 0, y: 0, width: width, height: t)
            out.fill(x: 0, y: t * 2 + 2, width: width, height: t)
            return out
        case .wave, .zigzag:
            let amplitude = CGFloat(4 + t * 2)
            let height = Int(amplitude * 2) + t + 4
            let gray = TextRaster.draw(width: width, height: height) { context in
                context.setStrokeColor(UIColor.black.cgColor)
                context.setLineWidth(CGFloat(t))
                context.setLineJoin(.round)
                let mid = CGFloat(height) / 2
                let period = amplitude * 4
                context.move(to: CGPoint(x: 0, y: mid))
                var x: CGFloat = 0
                while x <= CGFloat(width) {
                    let phase = x / period * 2 * .pi
                    let y = block.style == .wave ? mid + sin(phase) * amplitude
                        : mid + (abs((x / period).truncatingRemainder(dividingBy: 1) * 4 - 2) - 1) * amplitude
                    context.addLine(to: CGPoint(x: x, y: y))
                    x += 1
                }
                context.strokePath()
            }
            return Dither.threshold(gray, level: 0.5)
        case .scissors:
            let iconSize: CGFloat = 26
            let gray = TextRaster.draw(width: width, height: Int(iconSize) + 4) { context in
                let config = UIImage.SymbolConfiguration(pointSize: iconSize * 0.8, weight: .semibold)
                if let icon = UIImage(systemName: "scissors", withConfiguration: config)?
                    .withTintColor(.black, renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(x: 0, y: (iconSize + 4 - icon.size.height) / 2))
                }
                context.setFillColor(UIColor.black.cgColor)
                var x: CGFloat = iconSize + 6
                let y = round((iconSize + 4) / 2 - CGFloat(t) / 2)
                while x < CGFloat(width) {
                    context.fill(CGRect(x: x, y: y, width: 10, height: CGFloat(t)))
                    x += 18
                }
            }
            return Dither.threshold(gray, level: 0.5)
        case .stars:
            let gray = TextRaster.draw(width: width, height: 28) { context in
                let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
                guard let star = UIImage(systemName: "star.fill", withConfiguration: config)?
                    .withTintColor(.black, renderingMode: .alwaysOriginal) else { return }
                let count = 5
                let spacing = CGFloat(width) / CGFloat(count)
                for i in 0..<count {
                    let x = spacing * (CGFloat(i) + 0.5) - star.size.width / 2
                    star.draw(at: CGPoint(x: x, y: (28 - star.size.height) / 2))
                }
            }
            return Dither.threshold(gray, level: 0.5)
        }
    }

    // MARK: Emoji & icons

    static func symbol(_ block: SymbolBlock, width: Int) -> MonoBitmap {
        let size = CGFloat(min(Double(width), max(24, block.size)))
        let placement: HorizontalPlacement = block.align == .left ? .leading : block.align == .right ? .trailing : .center
        switch block.kind {
        case .emoji:
            let value = block.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return MonoBitmap(width: width, height: 0) }
            let string = NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: size * 0.8)])
            let measured = TextRaster.measure(string, width: CGFloat(width))
            let gray = TextRaster.draw(width: min(width, Int(measured.width) + 4), height: Int(measured.height) + 4) { _ in
                string.draw(with: CGRect(x: 2, y: 2, width: measured.width, height: measured.height),
                            options: [.usesLineFragmentOrigin], context: nil)
            }
            let adjusted = gray.autoLevels().adjusted(brightness: 0.04, contrast: 0.25)
            return trimmedVertically(Dither.atkinson(adjusted)).placed(inWidth: width, alignment: placement)
        case .icon:
            let config = UIImage.SymbolConfiguration(pointSize: size * 0.8, weight: .regular)
            guard let icon = UIImage(systemName: block.value, withConfiguration: config)?
                .withTintColor(.black, renderingMode: .alwaysOriginal) else {
                return MonoBitmap(width: width, height: 0)
            }
            let w = min(width, Int(ceil(icon.size.width)) + 4)
            let gray = TextRaster.draw(width: w, height: Int(ceil(icon.size.height)) + 4) { _ in
                icon.draw(at: CGPoint(x: 2, y: 2))
            }
            return trimmedVertically(Dither.threshold(gray, level: 0.5)).placed(inWidth: width, alignment: placement)
        }
    }

    private static func trimmedVertically(_ bitmap: MonoBitmap) -> MonoBitmap {
        guard let bounds = bitmap.contentBounds() else { return bitmap }
        return bitmap.cropped(x: 0, y: bounds.minY, width: bitmap.width, height: bounds.maxY - bounds.minY + 1)
    }

    // MARK: Calendar

    static func calendar(_ block: CalendarBlock, width: Int) -> MonoBitmap {
        var calendar = Calendar.current
        if (1...7).contains(block.firstWeekday) { calendar.firstWeekday = block.firstWeekday }
        guard let first = calendar.date(from: DateComponents(year: block.year, month: block.month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: first) else {
            return MonoBitmap(width: width, height: 0)
        }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let rows = Int(ceil(Double(leading + dayRange.count) / 7))
        let cell = floor(CGFloat(width) / 7)
        let gridWidth = cell * 7
        let originX = floor((CGFloat(width) - gridWidth) / 2)
        let cellHeight = round(cell * 0.8)
        let titleHeight: CGFloat = block.showTitle ? 50 : 0
        let headerHeight: CGFloat = 30
        let total = titleHeight + headerHeight + cellHeight * CGFloat(rows) + 4

        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        let highlightDay = block.highlightToday && today.year == block.year && today.month == block.month ? today.day : nil

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL y")
        let title = formatter.string(from: first)
        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        symbols = Array(symbols[shift...] + symbols[..<shift])

        let gray = TextRaster.draw(width: width, height: Int(total)) { context in
            context.setFillColor(UIColor.black.cgColor)
            context.setStrokeColor(UIColor.black.cgColor)
            if block.showTitle {
                let string = TextRaster.attributed(title, style: TextStyle(size: 36, bold: true, align: .center))
                string.draw(with: CGRect(x: 0, y: 2, width: CGFloat(width), height: titleHeight),
                            options: [.usesLineFragmentOrigin], context: nil)
            }
            let headerStyle = TextStyle(size: 20, bold: true, align: .center)
            for (index, symbol) in symbols.enumerated() {
                let rect = CGRect(x: originX + CGFloat(index) * cell, y: titleHeight + 4, width: cell, height: headerHeight)
                TextRaster.attributed(symbol, style: headerStyle).draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
            }
            let gridTop = titleHeight + headerHeight
            context.setLineWidth(2)
            for row in 0...rows {
                let y = gridTop + CGFloat(row) * cellHeight
                context.fill(CGRect(x: originX, y: y - 1, width: gridWidth, height: 2))
            }
            for column in 0...7 {
                let x = originX + CGFloat(column) * cell
                context.fill(CGRect(x: x - 1, y: gridTop, width: 2, height: cellHeight * CGFloat(rows)))
            }
            for day in dayRange {
                let position = leading + day - 1
                let rect = CGRect(x: originX + CGFloat(position % 7) * cell, y: gridTop + CGFloat(position / 7) * cellHeight,
                                  width: cell, height: cellHeight)
                var style = TextStyle(size: Double(cellHeight * 0.42), bold: day == highlightDay, align: .center)
                if day == highlightDay {
                    context.fill(rect.insetBy(dx: 3, dy: 3))
                    style.bold = true
                }
                let string = NSMutableAttributedString(attributedString: TextRaster.attributed("\(day)", style: style))
                if day == highlightDay {
                    string.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: string.length))
                }
                let textHeight = TextRaster.measure(string, width: cell).height
                string.draw(with: CGRect(x: rect.minX, y: rect.midY - textHeight / 2, width: cell, height: textHeight),
                            options: [.usesLineFragmentOrigin], context: nil)
            }
        }
        return Dither.threshold(gray, level: 0.55)
    }
}

/// Decorative borders drawn around the whole design.
enum FrameRenderer {
    static func render(_ style: FrameStyle, width: Int, height: Int) -> MonoBitmap {
        let gray = TextRaster.draw(width: width, height: height) { context in
            context.setStrokeColor(UIColor.black.cgColor)
            context.setFillColor(UIColor.black.cgColor)
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            switch style {
            case .none:
                break
            case .line:
                context.setLineWidth(3)
                context.stroke(bounds.insetBy(dx: 4, dy: 4))
            case .rounded:
                context.setLineWidth(3)
                context.addPath(UIBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerRadius: 22).cgPath)
                context.strokePath()
            case .double:
                context.setLineWidth(3)
                context.stroke(bounds.insetBy(dx: 3, dy: 3))
                context.setLineWidth(2)
                context.stroke(bounds.insetBy(dx: 10, dy: 10))
            case .thick:
                context.setLineWidth(8)
                context.addPath(UIBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), cornerRadius: 10).cgPath)
                context.strokePath()
            case .dashed:
                context.setLineWidth(3)
                context.setLineDash(phase: 0, lengths: [14, 8])
                context.stroke(bounds.insetBy(dx: 4, dy: 4))
            case .dotted:
                context.setLineWidth(4)
                context.setLineCap(.round)
                context.setLineDash(phase: 0, lengths: [0.1, 10])
                context.stroke(bounds.insetBy(dx: 5, dy: 5))
            case .ticket:
                let rect = bounds.insetBy(dx: 4, dy: 4)
                let notch: CGFloat = min(18, rect.height / 4)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.minX + 12, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.minY))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 12), controlPoint: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - notch))
                path.addArc(withCenter: CGPoint(x: rect.maxX, y: rect.midY), radius: notch,
                            startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 12))
                path.addQuadCurve(to: CGPoint(x: rect.maxX - 12, y: rect.maxY), controlPoint: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + 12, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 12), controlPoint: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + notch))
                path.addArc(withCenter: CGPoint(x: rect.minX, y: rect.midY), radius: notch,
                            startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 12))
                path.addQuadCurve(to: CGPoint(x: rect.minX + 12, y: rect.minY), controlPoint: CGPoint(x: rect.minX, y: rect.minY))
                path.close()
                context.setLineWidth(3)
                context.addPath(path.cgPath)
                context.strokePath()
            case .stamp:
                let dot: CGFloat = 8, step: CGFloat = 16
                var x: CGFloat = 6
                while x + dot <= CGFloat(width) - 4 {
                    context.fillEllipse(in: CGRect(x: x, y: 4, width: dot, height: dot))
                    context.fillEllipse(in: CGRect(x: x, y: CGFloat(height) - 4 - dot, width: dot, height: dot))
                    x += step
                }
                var y: CGFloat = 6 + step
                while y + dot <= CGFloat(height) - 4 - step {
                    context.fillEllipse(in: CGRect(x: 4, y: y, width: dot, height: dot))
                    context.fillEllipse(in: CGRect(x: CGFloat(width) - 4 - dot, y: y, width: dot, height: dot))
                    y += step
                }
                context.setLineWidth(2)
                context.stroke(bounds.insetBy(dx: 16, dy: 16))
            }
        }
        return Dither.threshold(gray, level: 0.5)
    }
}
