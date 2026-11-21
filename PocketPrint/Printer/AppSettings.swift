import Foundation
import Observation

enum TransferSpeed: String, CaseIterable, Identifiable {
    case fast, balanced, reliable
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .reliable: return "Reliable"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "Quickest. Relies on the printer pausing the data stream when its buffer is full."
        case .balanced: return "Recommended for most printers."
        case .reliable: return "Slowest. Use if prints come out garbled, skewed or cut short."
        }
    }

    /// Upper bound for the average data rate sent to the printer.
    var bytesPerSecond: Double {
        switch self {
        case .fast: return 36_000
        case .balanced: return 14_000
        case .reliable: return 4_500
        }
    }
}

enum FeedAmount: String, CaseIterable, Identifiable {
    case short, normal, long
    var id: String { rawValue }
    var title: String {
        switch self {
        case .short: return "Short"
        case .normal: return "Normal"
        case .long: return "Long"
        }
    }
    /// Number of 6 mm paper steps after printing.
    var steps: Int {
        switch self {
        case .short: return 1
        case .normal: return 2
        case .long: return 4
        }
    }
}

enum HeatLevel: String, CaseIterable, Identifiable {
    case lighter, standard, darker, darkest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lighter: return "Lighter"
        case .standard: return "Standard"
        case .darker: return "Darker"
        case .darkest: return "Darkest"
        }
    }
    var multiplier: Double {
        switch self {
        case .lighter: return 0.75
        case .standard: return 1
        case .darker: return 1.3
        case .darkest: return 1.6
        }
    }
}

enum OverrideChoice: String, CaseIterable, Identifiable {
    case automatic, on, off
    var id: String { rawValue }
}

enum DialectChoice: String, CaseIterable, Identifiable {
    case automatic, standard, prefixed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .standard: return TinyDialect.standard.title
        case .prefixed: return TinyDialect.prefixed.title
        }
    }
    var dialect: TinyDialect? {
        switch self {
        case .automatic: return nil
        case .standard: return .standard
        case .prefixed: return .prefixed
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var darkness: Int { didSet { defaults.set(darkness, forKey: Keys.darkness) } }
    var feedAmount: FeedAmount { didSet { defaults.set(feedAmount.rawValue, forKey: Keys.feed) } }
    var autoConnect: Bool { didSet { defaults.set(autoConnect, forKey: Keys.autoConnect) } }
    var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Keys.keepAwake) } }
    var transferSpeed: TransferSpeed { didSet { defaults.set(transferSpeed.rawValue, forKey: Keys.transfer) } }
    var maxPacketSize: Int { didSet { defaults.set(maxPacketSize, forKey: Keys.packet) } }
    var dialectChoice: DialectChoice { didSet { defaults.set(dialectChoice.rawValue, forKey: Keys.dialect) } }
    var compressionChoice: OverrideChoice { didSet { defaults.set(compressionChoice.rawValue, forKey: Keys.compression) } }
    var heat: HeatLevel { didSet { defaults.set(heat.rawValue, forKey: Keys.heat) } }
    /// Manually selected printer model; nil = detect from the Bluetooth name.
    var profileOverrideID: String? { didSet { defaults.set(profileOverrideID, forKey: Keys.profile) } }
    var showAllDevices: Bool { didSet { defaults.set(showAllDevices, forKey: Keys.showAll) } }
    var lastPrinterID: UUID? { didSet { defaults.set(lastPrinterID?.uuidString, forKey: Keys.lastID) } }
    var lastPrinterName: String? { didSet { defaults.set(lastPrinterName, forKey: Keys.lastName) } }
    var photoStyle: DitherStyle { didSet { defaults.set(photoStyle.rawValue, forKey: Keys.photoStyle) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        darkness = (defaults.object(forKey: Keys.darkness) as? Int).map { min(5, max(1, $0)) } ?? 3
        feedAmount = FeedAmount(rawValue: defaults.string(forKey: Keys.feed) ?? "") ?? .normal
        autoConnect = defaults.object(forKey: Keys.autoConnect) as? Bool ?? true
        keepScreenAwake = defaults.object(forKey: Keys.keepAwake) as? Bool ?? true
        transferSpeed = TransferSpeed(rawValue: defaults.string(forKey: Keys.transfer) ?? "") ?? .balanced
        maxPacketSize = defaults.object(forKey: Keys.packet) as? Int ?? 180
        dialectChoice = DialectChoice(rawValue: defaults.string(forKey: Keys.dialect) ?? "") ?? .automatic
        compressionChoice = OverrideChoice(rawValue: defaults.string(forKey: Keys.compression) ?? "") ?? .automatic
        heat = HeatLevel(rawValue: defaults.string(forKey: Keys.heat) ?? "") ?? .standard
        profileOverrideID = defaults.string(forKey: Keys.profile)
        showAllDevices = defaults.bool(forKey: Keys.showAll)
        lastPrinterID = defaults.string(forKey: Keys.lastID).flatMap(UUID.init(uuidString:))
        lastPrinterName = defaults.string(forKey: Keys.lastName)
        photoStyle = DitherStyle(rawValue: defaults.string(forKey: Keys.photoStyle) ?? "") ?? .floydSteinberg
    }

    func resetAdvanced() {
        transferSpeed = .balanced
        maxPacketSize = 180
        dialectChoice = .automatic
        compressionChoice = .automatic
        heat = .standard
        profileOverrideID = nil
    }

    private enum Keys {
        static let darkness = "darkness"
        static let feed = "feedAmount"
        static let autoConnect = "autoConnect"
        static let keepAwake = "keepScreenAwake"
        static let transfer = "transferSpeed"
        static let packet = "maxPacketSize"
        static let dialect = "dialect"
        static let compression = "compression"
        static let heat = "heat"
        static let profile = "profileOverride"
        static let showAll = "showAllDevices"
        static let lastID = "lastPrinterID"
        static let lastName = "lastPrinterName"
        static let photoStyle = "photoStyle"
    }
}

enum PrintKind: String, Codable, Sendable {
    case design, photo, banner, drawing, document, web, test

    var title: String {
        switch self {
        case .design: return "Design"
        case .photo: return "Photo"
        case .banner: return "Banner"
        case .drawing: return "Drawing"
        case .document: return "Document"
        case .web: return "Web Page"
        case .test: return "Test Page"
        }
    }

    var systemImage: String {
        switch self {
        case .design: return "square.and.pencil"
        case .photo: return "photo"
        case .banner: return "textformat.size"
        case .drawing: return "scribble.variable"
        case .document: return "doc.richtext"
        case .web: return "safari"
        case .test: return "checkmark.seal"
        }
    }
}

/// A finished, ready-to-send print: exact dots plus how they should be printed.
struct PrintJob: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var kind: PrintKind
    var bitmap: MonoBitmap
    var isTextMode: Bool
    /// The editable source, kept so the print can be edited again from History.
    var design: Design?
}
