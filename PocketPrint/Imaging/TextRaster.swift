import UIKit

/// Typefaces offered for printing. All ship with iOS, so nothing is downloaded.
enum FontFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, rounded, serif, mono, condensed, futura, typewriter, handwriting, marker, chalk, script, elegant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Classic"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .condensed: return "Condensed"
        case .futura: return "Futura"
        case .typewriter: return "Typewriter"
        case .handwriting: return "Handwriting"
        case .marker: return "Marker"
        case .chalk: return "Chalk"
        case .script: return "Script"
        case .elegant: return "Elegant"
        }
    }

    func font(size: CGFloat, bold: Bool, italic: Bool = false) -> UIFont {
        let base: UIFont
        switch self {
        case .system, .rounded, .serif, .mono:
            let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            let design: UIFontDescriptor.SystemDesign
            switch self {
            case .rounded: design = .rounded
            case .serif: design = .serif
            case .mono: design = .monospaced
            default: design = .default
            }
            if let descriptor = system.fontDescriptor.withDesign(design) {
                base = UIFont(descriptor: descriptor, size: size)
            } else {
                base = system
            }
        default:
            let names = postScriptNames
            base = UIFont(name: bold ? names.bold : names.regular, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        guard italic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    private var postScriptNames: (regular: String, bold: String) {
        switch self {
        case .condensed: return ("AvenirNextCondensed-DemiBold", "AvenirNextCondensed-Heavy")
        case .futura: return ("Futura-Medium", "Futura-Bold")
        case .typewriter: return ("AmericanTypewriter", "AmericanTypewriter-Bold")
        case .handwriting: return ("Noteworthy-Light", "Noteworthy-Bold")
        case .marker: return ("MarkerFelt-Thin", "MarkerFelt-Wide")
        case .chalk: return ("ChalkboardSE-Regular", "ChalkboardSE-Bold")
        case .script: return ("SnellRoundhand", "SnellRoundhand-Bold")
        case .elegant: return ("Didot", "Didot-Bold")
        default: return ("", "")
        }
    }
}

enum TextAlign: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, center, right
    var id: String { rawValue }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    var systemImage: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

struct TextStyle: Codable, Hashable, Sendable {
    var font: FontFamily = .system
    /// Font size in printer dots (8 dots = 1 mm).
    var size: Double = 32
    var bold = false
    var italic = false
    var underline = false
    var align: TextAlign = .left
    var lineSpacing: Double = 0
}

/// Renders text and other UIKit drawing into grayscale buffers at printer resolution (1 dot = 1 point).
enum TextRaster {
    static func attributed(_ text: String, style: TextStyle) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.align.nsAlignment
        paragraph.lineSpacing = CGFloat(style.lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.font.font(size: CGFloat(style.size), bold: style.bold, italic: style.italic),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ]
        if style.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func measure(_ string: NSAttributedString, width: CGFloat) -> CGSize {
        let rect = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// Draws with UIKit into a white canvas and returns it as grayscale.
    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> GrayImage {
        let w = max(1, width), h = max(1, height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            body(context.cgContext)
        }
        guard let cgImage = image.cgImage else { return GrayImage(width: w, height: h) }
        return GrayImage(cgImage: cgImage, width: w, height: h, interpolation: .none)
    }

    /// Renders wrapped text at `width` dots and converts it to crisp 1-bit dots.
    static func renderText(_ text: String, style: TextStyle, width: Int, threshold: Float = 0.55) -> MonoBitmap {
        let string = attributed(text.isEmpty ? " " : text, style: style)
        let size = measure(string, width: CGFloat(width))
        let gray = draw(width: width, height: Int(size.height) + 2) { _ in
            string.draw(with: CGRect(x: 0, y: 1, width: CGFloat(width), height: size.height + 1),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return Dither.threshold(gray, level: threshold)
    }
}

/// Replaces `{date}`, `{time}`, `{weekday}`, `{day}`, `{month}`, `{year}` with current values at render time.
enum TextTokens {
    static let all: [(token: String, title: String)] = [
        ("{date}", "Date"), ("{time}", "Time"), ("{weekday}", "Weekday"),
        ("{day}", "Day"), ("{month}", "Month"), ("{year}", "Year"),
    ]

    static func resolve(_ text: String, now: Date = Date()) -> String {
        guard text.contains("{") else { return text }
        var result = text
        let formatter = DateFormatter()
        formatter.locale = .current
        func formatted(_ template: String) -> String {
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: now)
        }
        let replacements: [String: () -> String] = [
            "{date}": { DateFormatter.localizedString(from: now, dateStyle: .long, timeStyle: .none) },
            "{time}": { DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short) },
            "{weekday}": { formatted("EEEE") },
            "{day}": { formatted("d") },
            "{month}": { formatted("MMMM") },
            "{year}": { formatted("y") },
        ]
        for (token, value) in replacements where result.contains(token) {
            result = result.replacingOccurrences(of: token, with: value())
        }
        return result
    }
}
