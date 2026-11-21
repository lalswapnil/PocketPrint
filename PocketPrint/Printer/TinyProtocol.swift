import Foundation

/// Wire dialect of the "tiny" command set spoken by Tiny Print compatible printers.
/// Both dialects are identical after the prefix; the P1 uses `.standard`.
enum TinyDialect: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case prefixed

    var id: String { rawValue }

    var prefix: [UInt8] {
        switch self {
        case .standard: return [0x51, 0x78]
        case .prefixed: return [0x12, 0x51, 0x78]
        }
    }

    var title: String {
        switch self {
        case .standard: return "Standard (51 78)"
        case .prefixed: return "Prefixed (12 51 78)"
        }
    }
}

/// Parameters for one encoded print job.
struct TinyJobOptions: Equatable, Sendable {
    var dialect: TinyDialect = .standard
    var isTextMode = false
    /// Motor/heat speed byte (`BD`). Lower is faster.
    var speed: UInt8 = 10
    /// Heating energy (`AF`, little-endian). `0` omits the command and keeps the printer default.
    var energy: UInt16 = 5000
    /// Print density level 1...5 (`A4`, sent as 0x30 + level).
    var blackening = 3
    /// Use run-length encoded rows (`BF`) whenever they are shorter than raw rows.
    var compress = true
    var dpi = 200
    /// Speed byte sent around the trailing paper feed.
    var feedPadding: UInt8 = 12
    /// Number of paper-advance steps (`A1`, 48 dots each at 200 dpi) after the image.
    var postPrintFeedCount = 2
    /// Re-send the speed command every N rows, as the vendor app does.
    var speedRefreshInterval = 200
}

enum TinyCommand {
    static let retractPaper: UInt8 = 0xA0
    static let feedPaper: UInt8 = 0xA1
    static let rasterRow: UInt8 = 0xA2
    static let deviceState: UInt8 = 0xA3
    static let blackening: UInt8 = 0xA4
    static let deviceInfo: UInt8 = 0xA8
    static let flowControl: UInt8 = 0xAE
    static let energy: UInt8 = 0xAF
    static let speed: UInt8 = 0xBD
    static let printMode: UInt8 = 0xBE
    static let compressedRow: UInt8 = 0xBF
}

enum TinyProtocol {
    /// CRC-8, polynomial 0x07, initial value 0 (checksum over the payload only).
    static let crcTable: [UInt8] = (0..<256).map { index in
        var crc = UInt8(index)
        for _ in 0..<8 {
            crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : crc << 1
        }
        return crc
    }

    static func crc8<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc = crcTable[Int(crc ^ byte)]
        }
        return crc
    }

    /// `prefix, command, 0x00, length (u16 LE), payload, crc8(payload), 0xFF`
    static func packet(_ command: UInt8, _ payload: [UInt8], dialect: TinyDialect = .standard) -> [UInt8] {
        var out = dialect.prefix
        out.reserveCapacity(out.count + payload.count + 6)
        out.append(command)
        out.append(0x00)
        out.append(UInt8(payload.count & 0xFF))
        out.append(UInt8((payload.count >> 8) & 0xFF))
        out.append(contentsOf: payload)
        out.append(crc8(payload))
        out.append(0xFF)
        return out
    }

    static func blackening(_ level: Int, dialect: TinyDialect = .standard) -> [UInt8] {
        packet(TinyCommand.blackening, [UInt8(0x30 + min(5, max(1, level)))], dialect: dialect)
    }

    static func energy(_ value: UInt16, dialect: TinyDialect = .standard) -> [UInt8] {
        guard value > 0 else { return [] }
        return packet(TinyCommand.energy, [UInt8(value & 0xFF), UInt8(value >> 8)], dialect: dialect)
    }

    static func printMode(text: Bool, dialect: TinyDialect = .standard) -> [UInt8] {
        packet(TinyCommand.printMode, [text ? 0x01 : 0x00], dialect: dialect)
    }

    static func speed(_ value: UInt8, dialect: TinyDialect = .standard) -> [UInt8] {
        packet(TinyCommand.speed, [value], dialect: dialect)
    }

    static func feedPaper(dots: Int, dialect: TinyDialect = .standard) -> [UInt8] {
        packet(TinyCommand.feedPaper, littleEndian16(dots), dialect: dialect)
    }

    static func retractPaper(dots: Int, dialect: TinyDialect = .standard) -> [UInt8] {
        packet(TinyCommand.retractPaper, littleEndian16(dots), dialect: dialect)
    }

    static func deviceState(dialect: TinyDialect = .standard) -> [UInt8] {
        packet(TinyCommand.deviceState, [0x00], dialect: dialect)
    }

    /// One paper step as used by the vendor app: 48 dots (6 mm) at 200 dpi, 72 dots at 300 dpi.
    static func paperStepDots(dpi: Int) -> Int {
        dpi == 300 ? 72 : 48
    }

    private static func littleEndian16(_ value: Int) -> [UInt8] {
        let clamped = UInt16(clamping: max(0, value))
        return [UInt8(clamped & 0xFF), UInt8(clamped >> 8)]
    }

    /// Run-length encodes one row of pixels (non-zero = black).
    /// Each byte is `(color << 7) | runLength` with runs of 1...127.
    static func runLengthEncode(_ row: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        guard let first = row.first else { return out }
        out.reserveCapacity(16)
        var color: UInt8 = first != 0 ? 1 : 0
        var count = 0

        func flush(_ color: UInt8, _ length: Int) {
            var remaining = length
            while remaining > 127 {
                out.append((color << 7) | 127)
                remaining -= 127
            }
            if remaining > 0 {
                out.append((color << 7) | UInt8(remaining))
            }
        }

        for pixel in row {
            let value: UInt8 = pixel != 0 ? 1 : 0
            if value == color {
                count += 1
            } else {
                flush(color, count)
                color = value
                count = 1
            }
        }
        flush(color, count)
        return out
    }

    /// Packs one row into bytes. The printer expects LSB-first: bit 0 is the leftmost pixel.
    static func packRow(_ row: UnsafeBufferPointer<UInt8>, lsbFirst: Bool = true) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (row.count + 7) / 8)
        for (index, pixel) in row.enumerated() where pixel != 0 {
            let bit = index & 7
            out[index >> 3] |= lsbFirst ? UInt8(1 << bit) : UInt8(0x80 >> bit)
        }
        return out
    }

    /// Encodes a complete print job, matching the Tiny Print command flow:
    /// density, energy, mode, speed, rows, then feed/finish commands.
    static func encodeJob(_ bitmap: MonoBitmap, options: TinyJobOptions) -> Data {
        let dialect = options.dialect
        var out: [UInt8] = []
        out.reserveCapacity(bitmap.height * (bitmap.width / 8 + 9) + 96)

        out += blackening(options.blackening, dialect: dialect)
        out += energy(options.energy, dialect: dialect)
        out += printMode(text: options.isTextMode, dialect: dialect)
        out += speed(options.speed, dialect: dialect)

        let width = bitmap.width
        let widthBytes = (width + 7) / 8
        bitmap.pixels.withUnsafeBufferPointer { buffer in
            for y in 0..<bitmap.height {
                let row = UnsafeBufferPointer(rebasing: buffer[(y * width)..<((y + 1) * width)])
                if options.compress {
                    let rle = runLengthEncode(row)
                    if rle.count <= widthBytes {
                        out += packet(TinyCommand.compressedRow, rle, dialect: dialect)
                    } else {
                        out += packet(TinyCommand.rasterRow, packRow(row), dialect: dialect)
                    }
                } else {
                    out += packet(TinyCommand.rasterRow, packRow(row), dialect: dialect)
                }
                if options.speedRefreshInterval > 0, (y + 1) % options.speedRefreshInterval == 0 {
                    out += speed(options.speed, dialect: dialect)
                }
            }
        }

        out += speed(options.feedPadding, dialect: dialect)
        for _ in 0..<max(0, options.postPrintFeedCount) {
            out += feedPaper(dots: paperStepDots(dpi: options.dpi), dialect: dialect)
        }
        out += speed(options.feedPadding, dialect: dialect)
        out += deviceState(dialect: dialect)
        return Data(out)
    }
}

// MARK: - Notifications from the printer

struct TinyPacket: Equatable, Sendable {
    let command: UInt8
    let flags: UInt8
    let payload: [UInt8]
}

/// Conditions in the first byte of an `A3` reply. The vendor apps document the low four bits;
/// higher bits (charging/busy, reported inconsistently) are ignored.
struct PrinterStatusFlags: OptionSet, Equatable, Sendable {
    let rawValue: UInt8
    static let paperOut = PrinterStatusFlags(rawValue: 0x01)
    static let coverOpen = PrinterStatusFlags(rawValue: 0x02)
    static let overheated = PrinterStatusFlags(rawValue: 0x04)
    static let lowBattery = PrinterStatusFlags(rawValue: 0x08)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(statusByte: UInt8) {
        self.init(rawValue: statusByte & 0x0F)
    }

    var messages: [String] {
        var result: [String] = []
        if contains(.paperOut) { result.append("Out of paper") }
        if contains(.coverOpen) { result.append("Paper cover is open") }
        if contains(.overheated) { result.append("Print head is hot — let it cool") }
        if contains(.lowBattery) { result.append("Battery is low") }
        return result
    }
}

/// Reply to the `A3` device-state query: `[status, ?, battery gauge]`.
struct DeviceState: Equatable, Sendable {
    var flags: PrinterStatusFlags
    /// 0...100 in sixths, only for models with a battery gauge.
    var batteryPercent: Int?
    var batteryGauge: UInt8?

    init(payload: [UInt8], hasBatteryGauge: Bool) {
        flags = PrinterStatusFlags(statusByte: payload.first ?? 0)
        if hasBatteryGauge, payload.count >= 3 {
            batteryGauge = payload[2]
            batteryPercent = DeviceState.batteryPercent(gauge: payload[2])
        }
    }

    /// The vendor app shows the gauge as six bars: 0x23...0x28 is one to six bars,
    /// anything above is full and anything below is empty.
    static func batteryBars(gauge: UInt8) -> Int {
        min(6, max(0, Int(gauge) - 0x22))
    }

    static func batteryPercent(gauge: UInt8) -> Int {
        Int((Double(batteryBars(gauge: gauge)) * 100 / 6).rounded())
    }
}

/// Reassembles framed `51 78` packets from a possibly fragmented notification stream.
/// Replies always use the standard prefix, whichever dialect is used for sending.
struct TinyStreamDecoder {
    private var buffer: [UInt8] = []
    private static let headerLength = 6
    private static let maxPayload = 512

    mutating func feed(_ data: Data) -> [TinyPacket] {
        buffer.append(contentsOf: data)
        var packets: [TinyPacket] = []
        while !buffer.isEmpty {
            guard let start = firstPrefixIndex() else {
                // Keep a trailing 0x51 that may begin the next packet.
                buffer = buffer.last == 0x51 ? [0x51] : []
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= Self.headerLength else { break }
            let length = Int(buffer[4]) | (Int(buffer[5]) << 8)
            guard length <= Self.maxPayload else {
                buffer.removeFirst(2)
                continue
            }
            let total = Self.headerLength + length + 2
            guard buffer.count >= total else { break }
            let payload = Array(buffer[Self.headerLength..<(Self.headerLength + length)])
            if buffer[total - 1] == 0xFF, TinyProtocol.crc8(payload) == buffer[total - 2] {
                packets.append(TinyPacket(command: buffer[2], flags: buffer[3], payload: payload))
                buffer.removeFirst(total)
            } else {
                buffer.removeFirst(2)
            }
        }
        return packets
    }

    private func firstPrefixIndex() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for index in 0..<(buffer.count - 1) where buffer[index] == 0x51 && buffer[index + 1] == 0x78 {
            return index
        }
        return nil
    }
}
