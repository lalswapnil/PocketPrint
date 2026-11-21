import CoreBluetooth
import Foundation

/// Print parameters for one printer model, as configured by the Tiny Print vendor app.
struct PrinterProfile: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    var dialect: TinyDialect = .standard
    var dpi = 200
    let imageSpeed: UInt8
    let textSpeed: UInt8
    let imageEnergy: UInt16
    let textEnergy: UInt16
    var compress = true
    /// Reports a battery gauge in its status reply (`showElectricityModel = 1` in the vendor table).
    var batteryGauge = false
}

enum PrinterCatalog {
    /// All supported models print 384 dots per line (48 mm on 57/58 mm paper).
    static let printWidth = 384
    static let dotsPerMillimeter = 8.0

    /// P1 / X6h family ("pocket printer", profile `d1` in Tiny Print).
    static let pocketPrinter = PrinterProfile(
        id: "d1", name: "P1 Pocket Printer",
        imageSpeed: 10, textSpeed: 10, imageEnergy: 5000, textEnergy: 8000, batteryGauge: true
    )

    /// Bluetooth name prefixes mapped to profiles. Longest matching prefix wins.
    static let entries: [(prefixes: [String], profile: PrinterProfile)] = [
        (["P1", "P2", "X6h", "X5h", "X7h", "X2h", "X100", "X103h", "X18", "XC9", "XC9-FL01", "D1", "DY03",
          "Pocket Printer", "Luxorp.PX10", "EMX-040256", "SeznikEcho", "TCM690464", "UXPORTMIP", "DL_GE225",
          "ML-MP-01", "ROSSMANN", "0019B-C", "0019B-D", "DTR-R0", "GB03PL", "HT0125", "RT034h", "DT1-0",
          "DT1-R", "SC03h", "SC04h", "TD-11308"], pocketPrinter),
        (["X6H", "X5H", "X7H", "X2H", "X5HP", "X6HP", "P7H", "X102", "X103H", "SC05", "IM.04", "ewtto ET-Z0504"],
         PrinterProfile(id: "x6h", name: "X6H", imageSpeed: 10, textSpeed: 10, imageEnergy: 9500, textEnergy: 9500, batteryGauge: true)),
        (["X6"], PrinterProfile(id: "x6", name: "X6", imageSpeed: 10, textSpeed: 10, imageEnergy: 9000, textEnergy: 0)),
        (["X5"], PrinterProfile(id: "x5_2", name: "X5", imageSpeed: 10, textSpeed: 10, imageEnergy: 7500, textEnergy: 13000)),
        (["X7"], PrinterProfile(id: "x7", name: "X7", imageSpeed: 10, textSpeed: 10, imageEnergy: 7500, textEnergy: 0)),
        (["X101H"], PrinterProfile(id: "x101h", name: "X101H", imageSpeed: 10, textSpeed: 10, imageEnergy: 9500, textEnergy: 9500, batteryGauge: true)),
        (["X16", "Audio Print", "A2", "A3"],
         PrinterProfile(id: "x16", name: "X16", imageSpeed: 10, textSpeed: 10, imageEnergy: 5000, textEnergy: 8000, batteryGauge: true)),
        (["LGM01", "X7HP"], PrinterProfile(id: "x7hp", name: "X7HP", imageSpeed: 10, textSpeed: 10, imageEnergy: 20000, textEnergy: 20000, batteryGauge: true)),
        (["P10"], PrinterProfile(id: "p10", name: "P10", imageSpeed: 10, textSpeed: 10, imageEnergy: 5500, textEnergy: 9500)),
        (["P6"], PrinterProfile(id: "p6", name: "P6", imageSpeed: 10, textSpeed: 10, imageEnergy: 9500, textEnergy: 8000, batteryGauge: true)),
        (["P7"], PrinterProfile(id: "p7", name: "P7", imageSpeed: 30, textSpeed: 10, imageEnergy: 7500, textEnergy: 0)),
        (["P5AI", "PR07", "XW003", "XW009", "M01", "AI01"],
         PrinterProfile(id: "m01", name: "M01", imageSpeed: 45, textSpeed: 25, imageEnergy: 0, textEnergy: 0)),
        (["PR02", "XW008"], PrinterProfile(id: "pr02", name: "PR02", imageSpeed: 10, textSpeed: 10, imageEnergy: 5500, textEnergy: 11000)),
        (["XW001"], PrinterProfile(id: "xw001", name: "XW001", imageSpeed: 45, textSpeed: 35, imageEnergy: 0, textEnergy: 0, compress: false)),
        (["GB01"], PrinterProfile(id: "gb01", name: "GB01", imageSpeed: 35, textSpeed: 25, imageEnergy: 12000, textEnergy: 0, compress: false)),
        (["GB02"], PrinterProfile(id: "gb02", name: "GB02", imageSpeed: 26, textSpeed: 25, imageEnergy: 12000, textEnergy: 0, compress: false)),
        (["GB02SH"], PrinterProfile(id: "gb02sh", name: "GB02SH", imageSpeed: 25, textSpeed: 25, imageEnergy: 7000, textEnergy: 9500, batteryGauge: true)),
        (["GB03", "GB06"], PrinterProfile(id: "gb03_2", name: "GB03", imageSpeed: 10, textSpeed: 10, imageEnergy: 9000, textEnergy: 8000)),
        (["GB03PH", "GB03SH"], PrinterProfile(id: "gb03ph", name: "GB03PH", imageSpeed: 25, textSpeed: 25, imageEnergy: 9500, textEnergy: 9500, batteryGauge: true)),
        (["GB03SL"], PrinterProfile(id: "gb03sl", name: "GB03SL", imageSpeed: 10, textSpeed: 10, imageEnergy: 5000, textEnergy: 8000, batteryGauge: true)),
        (["GB04"], PrinterProfile(id: "gb04", name: "GB04", imageSpeed: 26, textSpeed: 25, imageEnergy: 12000, textEnergy: 0, compress: false)),
        (["GB05"], PrinterProfile(id: "gb05", name: "GB05", imageSpeed: 26, textSpeed: 25, imageEnergy: 10000, textEnergy: 12000)),
        (["GT01", "GT03"], PrinterProfile(id: "gt01", name: "GT01", imageSpeed: 30, textSpeed: 25, imageEnergy: 12000, textEnergy: 0)),
        (["GT02"], PrinterProfile(id: "gt02", name: "GT02", imageSpeed: 30, textSpeed: 25, imageEnergy: 9000, textEnergy: 8000)),
        (["GT04"], PrinterProfile(id: "gt04", name: "GT04", imageSpeed: 30, textSpeed: 25, imageEnergy: 8000, textEnergy: 0)),
        (["CMT-0510", "SC03", "SC04", "GV-MA211"],
         PrinterProfile(id: "gb03", name: "SC03", imageSpeed: 30, textSpeed: 10, imageEnergy: 7500, textEnergy: 8000)),
        (["SC03H", "FC02"], PrinterProfile(id: "fc02", name: "FC02", imageSpeed: 25, textSpeed: 25, imageEnergy: 20000, textEnergy: 20000, batteryGauge: true)),
        (["IprintIt", "DY01", "LP6"], PrinterProfile(id: "x5", name: "iPrintIt", imageSpeed: 30, textSpeed: 10, imageEnergy: 7500, textEnergy: 0)),
        (["SeznikNeo", "RS9000", "XiaoWa", "JRX01", "QDX01", "wts07", "CP01", "DY49", "S5A", "P20 max", "S9A",
          "DY33A", "YMS-BT01", "WJ-HOT-PRT"],
         PrinterProfile(id: "cp01", name: "CP01", imageSpeed: 20, textSpeed: 10, imageEnergy: 12000, textEnergy: 13000, compress: false, batteryGauge: true)),
        (["Mini Printer"], PrinterProfile(id: "mini_printer", name: "Mini Printer", imageSpeed: 20, textSpeed: 20, imageEnergy: 14000, textEnergy: 14000, batteryGauge: true)),
        (["DL_X2"], PrinterProfile(id: "dl_x2", name: "DL X2", imageSpeed: 10, textSpeed: 10, imageEnergy: 8000, textEnergy: 8000, batteryGauge: true)),
        (["PT001"], PrinterProfile(id: "pt001", name: "PT001", imageSpeed: 10, textSpeed: 10, imageEnergy: 20000, textEnergy: 8000, batteryGauge: true)),
        (["58P5", "WL01"], PrinterProfile(id: "58p5", name: "58P5", imageSpeed: 10, textSpeed: 10, imageEnergy: 6500, textEnergy: 0)),
        (["AN01"], PrinterProfile(id: "an01", name: "AN01", imageSpeed: 10, textSpeed: 10, imageEnergy: 5000, textEnergy: 5000, batteryGauge: true)),
        (["FL01", "KF-5"], PrinterProfile(id: "fl01", name: "FL01", imageSpeed: 20, textSpeed: 10, imageEnergy: 7500, textEnergy: 7500, compress: false, batteryGauge: true)),
        (["JX001", "JX002", "JX003", "JX004", "JX005", "JX006"],
         PrinterProfile(id: "jx001", name: "JX001", imageSpeed: 90, textSpeed: 45, imageEnergy: 0, textEnergy: 0)),
        (["LT01"], PrinterProfile(id: "lt01", name: "LT01", imageSpeed: 10, textSpeed: 10, imageEnergy: 4500, textEnergy: 8000)),
        (["LY01"], PrinterProfile(id: "ly01", name: "LY01", imageSpeed: 40, textSpeed: 25, imageEnergy: 9500, textEnergy: 0)),
        (["LY02"], PrinterProfile(id: "ly02", name: "LY02", imageSpeed: 45, textSpeed: 35, imageEnergy: 0, textEnergy: 0)),
        (["LY03"], PrinterProfile(id: "ly03", name: "LY03", imageSpeed: 10, textSpeed: 10, imageEnergy: 7500, textEnergy: 0)),
        (["LY10"], PrinterProfile(id: "ly10", name: "LY10", dialect: .prefixed, imageSpeed: 26, textSpeed: 25, imageEnergy: 12, textEnergy: 0)),
        (["LP100"], PrinterProfile(id: "lp100", name: "LP100", dialect: .prefixed, imageSpeed: 26, textSpeed: 25, imageEnergy: 100, textEnergy: 0)),
        (["S101"], PrinterProfile(id: "s101", name: "S101", imageSpeed: 30, textSpeed: 10, imageEnergy: 7500, textEnergy: 0)),
        (["S102"], PrinterProfile(id: "s102_2", name: "S102", imageSpeed: 30, textSpeed: 10, imageEnergy: 7500, textEnergy: 0)),
        (["S01"], PrinterProfile(id: "s01", name: "S01", imageSpeed: 10, textSpeed: 10, imageEnergy: 6500, textEnergy: 0)),
        (["ZHHC"], PrinterProfile(id: "zhhc", name: "ZHHC", imageSpeed: 10, textSpeed: 10, imageEnergy: 9000, textEnergy: 0)),
        (["A33"], PrinterProfile(id: "a33", name: "A33", imageSpeed: 25, textSpeed: 25, imageEnergy: 9500, textEnergy: 9500, batteryGauge: true)),
        (["M2"], PrinterProfile(id: "m2", name: "M2", imageSpeed: 10, textSpeed: 10, imageEnergy: 4500, textEnergy: 8000)),
        (["U1"], PrinterProfile(id: "u1", name: "U1", imageSpeed: 10, textSpeed: 10, imageEnergy: 20000, textEnergy: 8000, batteryGauge: true)),
    ]

    /// Every distinct profile, with the P1 first (used by the manual model picker).
    static var allProfiles: [PrinterProfile] {
        var seen = Set<String>()
        return entries.map(\.profile).filter { seen.insert($0.id).inserted }
    }

    static func profile(id: String) -> PrinterProfile? {
        allProfiles.first { $0.id == id }
    }

    /// Detects the profile from the advertised Bluetooth name, e.g. "P1-28F2" -> P1 Pocket Printer.
    /// Case-sensitive matches are preferred, then case-insensitive ones.
    static func profile(forDeviceName name: String?) -> PrinterProfile? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        for caseSensitive in [true, false] {
            var best: (length: Int, profile: PrinterProfile)?
            let candidate = caseSensitive ? name : name.lowercased()
            for entry in entries {
                for prefix in entry.prefixes {
                    let key = caseSensitive ? prefix : prefix.lowercased()
                    if candidate.hasPrefix(key), key.count > (best?.length ?? 0) {
                        best = (key.count, entry.profile)
                    }
                }
            }
            if let best { return best.profile }
        }
        return nil
    }

    // MARK: Bluetooth GATT layout

    /// Known serial-style services, in order of preference, with their write/notify characteristics.
    static let gattLayouts: [(service: CBUUID, write: CBUUID, notify: CBUUID?)] = [
        (CBUUID(string: "AE30"), CBUUID(string: "AE01"), CBUUID(string: "AE02")),
        (CBUUID(string: "FF00"), CBUUID(string: "FF02"), CBUUID(string: "FF01")),
        (CBUUID(string: "AE3A"), CBUUID(string: "AE3B"), CBUUID(string: "AE3C")),
        (CBUUID(string: "AE00"), CBUUID(string: "AE01"), CBUUID(string: "AE02")),
        (CBUUID(string: "AE80"), CBUUID(string: "AE81"), nil),
        (CBUUID(string: "AB00"), CBUUID(string: "AB01"), CBUUID(string: "AB03")),
        (CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
         CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3"),
         CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616")),
    ]

    static let advertisedServiceHints: Set<CBUUID> = [
        CBUUID(string: "AE30"), CBUUID(string: "AF30"), CBUUID(string: "FF00"), CBUUID(string: "AE3A"),
    ]
}
