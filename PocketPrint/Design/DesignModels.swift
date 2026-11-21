import Foundation

/// A printable layout: blocks stacked from top to bottom along the paper strip.
struct Design: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title = "Untitled"
    var blocks: [Block] = []
    var frame: FrameStyle = .none
    /// Left/right margin in dots.
    var margin = 8
    /// Vertical gap between blocks in dots.
    var spacing = 14
    /// Fixed label length in millimetres; 0 = as long as the content.
    var lengthMM = 0

    /// Photos and dithered emoji print better in image mode; everything else uses the darker text mode.
    var prefersImageMode: Bool {
        blocks.contains { block in
            switch block.content {
            case .image: return true
            case .symbol(let symbol): return symbol.kind == .emoji
            default: return false
            }
        }
    }

    var imageIDs: Set<String> {
        Set(blocks.compactMap { block in
            if case .image(let image) = block.content { return image.imageID }
            return nil
        })
    }
}

struct Block: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var content: BlockContent

    init(_ content: BlockContent) {
        self.content = content
    }
}

enum BlockContent: Codable, Hashable, Sendable {
    case text(TextBlock)
    case image(ImageBlock)
    case checklist(ChecklistBlock)
    case qr(QRBlock)
    case barcode(BarcodeBlock)
    case divider(DividerBlock)
    case spacer(SpacerBlock)
    case symbol(SymbolBlock)
    case calendar(CalendarBlock)

    var kind: BlockKind {
        switch self {
        case .text: return .text
        case .image: return .image
        case .checklist: return .checklist
        case .qr: return .qr
        case .barcode: return .barcode
        case .divider: return .divider
        case .spacer: return .spacer
        case .symbol: return .symbol
        case .calendar: return .calendar
        }
    }
}

enum BlockKind: String, CaseIterable, Identifiable {
    case text, image, checklist, qr, barcode, divider, spacer, symbol, calendar
    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .image: return "Photo"
        case .checklist: return "Checklist"
        case .qr: return "QR Code"
        case .barcode: return "Barcode"
        case .divider: return "Divider"
        case .spacer: return "Space"
        case .symbol: return "Emoji & Icons"
        case .calendar: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "textformat"
        case .image: return "photo"
        case .checklist: return "checklist"
        case .qr: return "qrcode"
        case .barcode: return "barcode"
        case .divider: return "minus"
        case .spacer: return "arrow.up.and.down"
        case .symbol: return "face.smiling"
        case .calendar: return "calendar"
        }
    }
}

// MARK: - Block payloads

struct TextBlock: Codable, Hashable, Sendable {
    var text = ""
    var style = TextStyle()
    /// White text on a black band.
    var inverted = false
}

struct ImageAdjustments: Codable, Hashable, Sendable {
    var style: DitherStyle = .floydSteinberg
    var brightness: Double = 0
    var contrast: Double = 0
    var sharpness: Double = 0.4
    var threshold: Double = 0.5
    var autoLevels = true
    var invert = false
}

struct CropRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ImageBlock: Codable, Hashable, Sendable {
    var imageID: String
    var adjustments = ImageAdjustments()
    /// Quarter turns clockwise.
    var rotation = 0
    var mirrored = false
    /// Normalised crop in the rotated image; nil = full image.
    var crop: CropRect?
    var cropAspect: CropAspect = .original
    /// Printed width as a percentage of the paper width.
    var widthPercent: Double = 100
}

enum CropAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, square, fourThree, threeFour, sixteenNine, nineSixteen
    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .square: return "Square"
        case .fourThree: return "4:3"
        case .threeFour: return "3:4"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        }
    }

    /// Width / height, nil for the image's own ratio.
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeFour: return 3.0 / 4.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var text = ""
    var checked = false
}

enum ChecklistMarker: String, Codable, CaseIterable, Identifiable, Sendable {
    case box, circle, bullet, number, dash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .box: return "Boxes"
        case .circle: return "Circles"
        case .bullet: return "Bullets"
        case .number: return "Numbers"
        case .dash: return "Dashes"
        }
    }
    var systemImage: String {
        switch self {
        case .box: return "square"
        case .circle: return "circle"
        case .bullet: return "circle.fill"
        case .number: return "list.number"
        case .dash: return "minus"
        }
    }
}

struct ChecklistBlock: Codable, Hashable, Sendable {
    var items: [ChecklistItem] = [ChecklistItem(), ChecklistItem(), ChecklistItem()]
    var marker: ChecklistMarker = .box
    var style = TextStyle(size: 30)
}

enum QRMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, wifi, contact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return "Text / Link"
        case .wifi: return "Wi-Fi"
        case .contact: return "Contact"
        }
    }
}

enum WiFiSecurity: String, Codable, CaseIterable, Identifiable, Sendable {
    case wpa = "WPA", wep = "WEP", open = "nopass"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wpa: return "WPA/WPA2/WPA3"
        case .wep: return "WEP"
        case .open: return "None"
        }
    }
}

struct QRBlock: Codable, Hashable, Sendable {
    var mode: QRMode = .text
    var text = ""
    var wifiSSID = ""
    var wifiPassword = ""
    var wifiSecurity: WiFiSecurity = .wpa
    var contactName = ""
    var contactPhone = ""
    var contactEmail = ""
    var sizePercent: Double = 70
    var caption = ""
    var correction: CodeRaster.Correction = .medium

    var payload: String {
        switch mode {
        case .text:
            return text
        case .wifi:
            guard !wifiSSID.isEmpty else { return "" }
            var value = "WIFI:T:\(wifiSecurity.rawValue);S:\(Self.escape(wifiSSID));"
            if wifiSecurity != .open { value += "P:\(Self.escape(wifiPassword));" }
            return value + ";"
        case .contact:
            guard !(contactName.isEmpty && contactPhone.isEmpty && contactEmail.isEmpty) else { return "" }
            var lines = ["BEGIN:VCARD", "VERSION:3.0", "N:;\(contactName);;;", "FN:\(contactName)"]
            if !contactPhone.isEmpty { lines.append("TEL:\(contactPhone)") }
            if !contactEmail.isEmpty { lines.append("EMAIL:\(contactEmail)") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\n")
        }
    }

    private static func escape(_ value: String) -> String {
        var out = ""
        for character in value {
            if "\\;,:\"".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}

struct BarcodeBlock: Codable, Hashable, Sendable {
    var text = "123456789"
    /// Bar height in dots.
    var height = 80
    var showText = true
}

enum DividerStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case solid, dashed, dotted, double, wave, zigzag, scissors, stars
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Line"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        case .double: return "Double"
        case .wave: return "Wave"
        case .zigzag: return "Zigzag"
        case .scissors: return "Cut here"
        case .stars: return "Stars"
        }
    }
}

struct DividerBlock: Codable, Hashable, Sendable {
    var style: DividerStyle = .dashed
    var thickness = 3
}

struct SpacerBlock: Codable, Hashable, Sendable {
    /// Height in dots.
    var height = 48
}

enum SymbolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case emoji, icon
    var id: String { rawValue }
}

struct SymbolBlock: Codable, Hashable, Sendable {
    var kind: SymbolKind = .emoji
    var value = "😀"
    /// Size in dots.
    var size: Double = 160
    var align: TextAlign = .center
}

struct CalendarBlock: Codable, Hashable, Sendable {
    var year: Int
    var month: Int
    var highlightToday = true
    /// 1 = Sunday ... 7 = Saturday, 0 = follow the device setting.
    var firstWeekday = 0
    var showTitle = true

    static var currentMonth: CalendarBlock {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return CalendarBlock(year: components.year ?? 2026, month: components.month ?? 1)
    }
}

enum FrameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, line, rounded, double, thick, dashed, dotted, ticket, stamp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .line: return "Line"
        case .rounded: return "Rounded"
        case .double: return "Double"
        case .thick: return "Bold"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        case .ticket: return "Ticket"
        case .stamp: return "Stamp"
        }
    }

    /// Space between the paper edge and the content inside the frame, in dots.
    var inset: Int {
        switch self {
        case .none: return 0
        case .line, .dashed, .dotted: return 12
        case .rounded: return 14
        case .double: return 16
        case .thick: return 18
        case .ticket: return 18
        case .stamp: return 22
        }
    }
}
