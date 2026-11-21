import SwiftUI
import UIKit

/// A rendered bitmap prepared once for display, with white paper margins around the 48 mm print area.
struct RasterPreview: Equatable {
    /// 57 mm paper around a 48 mm (384 dot) print area leaves 36 dots per side.
    static let paperMargin = 36

    let image: UIImage
    /// Size of the displayed image in dots, including margins.
    let width: Int
    let height: Int
    let margin: Int

    init?(_ bitmap: MonoBitmap, margin: Int = RasterPreview.paperMargin) {
        guard bitmap.height > 0, let cgImage = bitmap.padded(left: margin, right: margin).makeCGImage() else { return nil }
        image = UIImage(cgImage: cgImage)
        width = bitmap.width + margin * 2
        height = bitmap.height
        self.margin = margin
    }

    static func == (lhs: RasterPreview, rhs: RasterPreview) -> Bool { lhs.image === rhs.image }
}

struct PreviewHint: Identifiable {
    let id: UUID
    let range: Range<Int>
    let text: String
}

/// Shows printed dots on a white "paper strip". Taps report the row (in dots) that was touched.
struct PaperPreview: View {
    let preview: RasterPreview?
    var highlight: Range<Int>?
    var hints: [PreviewHint] = []
    var emptyHeight: CGFloat = 220
    var emptyMessage: String?
    var onTap: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(Color.white)
            TornEdge()
                .fill(Color.white)
                .frame(height: 8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    @ViewBuilder
    private var content: some View {
        if let preview {
            Image(uiImage: preview.image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(CGFloat(preview.width) / CGFloat(preview.height), contentMode: .fit)
                .accessibilityLabel("Print preview")
                .overlay {
                    GeometryReader { proxy in
                        let scale = proxy.size.width / CGFloat(preview.width)
                        let left = CGFloat(preview.margin) * scale
                        let contentWidth = CGFloat(preview.width - preview.margin * 2) * scale
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    onTap?(Int(location.y / scale))
                                }
                            ForEach(hints) { hint in
                                hintView(hint.text)
                                    .frame(width: contentWidth - 4, height: max(20, CGFloat(hint.range.count) * scale - 4))
                                    .offset(x: left + 2, y: CGFloat(hint.range.lowerBound) * scale + 2)
                                    .allowsHitTesting(false)
                            }
                            if let highlight {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2))
                                    .frame(width: contentWidth + 12, height: CGFloat(highlight.count) * scale + 12)
                                    .offset(x: left - 6, y: CGFloat(highlight.lowerBound) * scale - 6)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
        } else {
            Text(emptyMessage ?? "")
                .font(.callout)
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: emptyHeight)
                .contentShape(Rectangle())
                .onTapGesture { onTap?(0) }
        }
    }

    private func hintView(_ text: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(Color.gray.opacity(0.6))
            .overlay(
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
            )
    }
}

/// Zig-zag bottom edge like torn receipt paper.
struct TornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tooth: CGFloat = 10
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        var x = rect.maxX
        var down = true
        while x > rect.minX {
            x -= tooth / 2
            path.addLine(to: CGPoint(x: max(rect.minX, x), y: down ? rect.maxY : rect.minY))
            down.toggle()
        }
        path.closeSubpath()
        return path
    }
}

/// Horizontally scrolling single-choice chips.
struct ChipPicker<Value: Hashable, Label: View>: View {
    let options: [Value]
    @Binding var selection: Value
    @ViewBuilder let label: (Value) -> Label

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button {
                        selection = option
                    } label: {
                        label(option)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill)))
                            .overlay(Capsule().stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(Int(($0 * 100).rounded())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}

struct DarknessPicker: View {
    @Binding var darkness: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Darkness", systemImage: "circle.lefthalf.filled")
                Spacer()
                Text(Self.title(for: darkness)).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Picker("Darkness", selection: $darkness) {
                ForEach(1...5, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    static func title(for level: Int) -> String {
        switch level {
        case 1: return "Lightest"
        case 2: return "Light"
        case 3: return "Normal"
        case 4: return "Dark"
        default: return "Darkest"
        }
    }
}

/// Approximate printer charge, e.g. "83%" with a matching battery symbol.
struct BatteryBadge: View {
    let percent: Int
    var isLow = false

    private var symbol: String {
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text("\(percent)%")
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isLow || percent <= 17 ? Color.red : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Printer battery about \(percent) percent")
    }
}

/// Connection status as a small coloured dot with text.
struct PrinterStatusBadge: View {
    @Environment(PrinterService.self) private var printer

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .lineLimit(1)
        }
        .font(.footnote.weight(.medium))
    }

    private var color: Color {
        if printer.bluetoothState != .poweredOn && printer.bluetoothState != .unknown { return .red }
        switch printer.phase {
        case .ready: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        }
    }

    private var text: String {
        if printer.bluetoothState == .poweredOff { return "Bluetooth off" }
        if printer.bluetoothState == .unauthorized { return "Bluetooth not allowed" }
        if printer.bluetoothState == .unsupported { return "Bluetooth unavailable" }
        switch printer.phase {
        case .ready: return printer.printerName ?? "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return printer.hasSavedPrinter ? "\(printer.printerName ?? "Printer") · not connected" : "No printer"
        }
    }
}

extension View {
    /// A custom bottom bar: on iOS 26 it gets the system scroll-edge effect, before that a bar material.
    @ViewBuilder
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom) { bar() }
        } else {
            self.safeAreaInset(edge: .bottom) { bar().background(.bar) }
        }
    }

    /// Prominent action style: Liquid Glass on iOS 26, filled button before that.
    @ViewBuilder
    func prominentActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Lengths shown to people in millimetres or centimetres.
enum PaperLength {
    static func describe(dots: Int) -> String {
        let mm = Double(dots) / PrinterCatalog.dotsPerMillimeter
        if mm >= 100 {
            return String(format: "%.1f cm", mm / 10)
        }
        return "\(Int(mm.rounded())) mm"
    }
}

/// Editor tools on the left, a clearly labelled Print button on the right.
struct EditorActionBar<Tools: View>: View {
    var printTitle = "Print"
    var isPrintDisabled = false
    let onPrint: () -> Void
    @ViewBuilder var tools: () -> Tools

    var body: some View {
        HStack(spacing: 10) {
            tools()
            Spacer(minLength: 8)
            Button(action: onPrint) {
                Label(printTitle, systemImage: "printer.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .disabled(isPrintDisabled)
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension EditorActionBar where Tools == EmptyView {
    init(printTitle: String = "Print", isPrintDisabled: Bool = false, onPrint: @escaping () -> Void) {
        self.init(printTitle: printTitle, isPrintDisabled: isPrintDisabled, onPrint: onPrint) { EmptyView() }
    }
}

/// Groups several small controls in one capsule: Liquid Glass on iOS 26, a material before that.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

/// Secondary tool button used in `EditorActionBar`.
struct ToolBarButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
    }
}
