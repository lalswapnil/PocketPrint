import SwiftUI

/// Tone, style, orientation and crop controls for a photo. Used by the photo editor and image blocks.
struct PhotoAdjustmentsPanel: View {
    @Binding var block: ImageBlock
    var showsSize = false
    @Environment(AppSettings.self) private var settings
    @State private var showCrop = false

    var body: some View {
        Section {
            ChipPicker(options: DitherStyle.allCases, selection: styleBinding) { style in
                Label(style.title, systemImage: style.systemImage)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            Text(styleDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Style")
        }

        Section("Adjust") {
            if block.adjustments.style == .threshold {
                LabeledSlider(title: "Ink level", value: $block.adjustments.threshold, range: 0.2...0.8,
                              format: { String(Int(($0 * 100).rounded())) })
            }
            LabeledSlider(title: "Brightness", value: $block.adjustments.brightness, range: -0.6...0.6,
                          format: signedPercent)
            LabeledSlider(title: "Contrast", value: $block.adjustments.contrast, range: -0.6...0.8,
                          format: signedPercent)
            if block.adjustments.style != .threshold {
                LabeledSlider(title: "Sharpness", value: $block.adjustments.sharpness, range: 0...1,
                              format: { String(Int(($0 * 100).rounded())) })
            }
            Toggle("Auto contrast", isOn: $block.adjustments.autoLevels)
            Toggle("Invert (negative)", isOn: $block.adjustments.invert)
            Button("Reset Adjustments") {
                let style = block.adjustments.style
                block.adjustments = ImageAdjustments(style: style)
            }
        }

        Section("Frame") {
            HStack(spacing: 10) {
                frameButton("Left", "rotate.left") { block.rotation = (block.rotation + 3) % 4; block.crop = nil; block.cropAspect = .original }
                frameButton("Right", "rotate.right") { block.rotation = (block.rotation + 1) % 4; block.crop = nil; block.cropAspect = .original }
                frameButton("Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right") { block.mirrored.toggle() }
                frameButton("Crop", "crop") { showCrop = true }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            if showsSize {
                LabeledSlider(title: "Width", value: $block.widthPercent, range: 30...100, step: 5,
                              format: { "\(Int($0))%" })
            }
        }
        .sheet(isPresented: $showCrop) {
            CropView(block: $block)
        }
    }

    private var styleBinding: Binding<DitherStyle> {
        Binding(
            get: { block.adjustments.style },
            set: { style in
                block.adjustments.style = style
                settings.photoStyle = style
            }
        )
    }

    private var styleDescription: String {
        switch block.adjustments.style {
        case .floydSteinberg: return "Smooth shading — best for most photos."
        case .atkinson: return "Lighter, high-contrast shading. Great for faces and bright scenes."
        case .halftone: return "Newspaper-style dots that hold up well on thermal paper."
        case .ordered: return "A regular dot pattern with a retro look."
        case .threshold: return "Pure black and white — for drawings, logos and handwriting."
        case .document: return "Cleans up photos of paper: removes shadows and keeps text sharp."
        }
    }

    private func signedPercent(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent > 0 ? "+\(percent)" : "\(percent)"
    }

    private func frameButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

