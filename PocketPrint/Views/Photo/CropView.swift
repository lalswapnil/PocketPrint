import SwiftUI

/// Pan and pinch a photo inside a frame of the chosen shape.
/// State is kept in normalised image coordinates, so it doesn't depend on screen layout.
struct CropView: View {
    @Binding var block: ImageBlock
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var aspect: CropAspect = .original
    @State private var zoom: CGFloat = 1
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var dragStartCenter: CGPoint?
    @State private var pinchStartZoom: CGFloat?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    if let image {
                        cropArea(image: image, available: proxy.size)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Color.black)

                ChipPicker(options: CropAspect.allCases, selection: aspectBinding) { Text($0.title) }
                    .padding(.horizontal)
                Text("Drag to move · Pinch to zoom")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                }
            }
        }
        .task { load() }
    }

    private var aspectBinding: Binding<CropAspect> {
        Binding(get: { aspect }, set: { newValue in
            aspect = newValue
            zoom = 1
            center = CGPoint(x: 0.5, y: 0.5)
        })
    }

    @ViewBuilder
    private func cropArea(image: UIImage, available: CGSize) -> some View {
        let ratio = frameRatio(image)
        let maxWidth = max(1, available.width - 32), maxHeight = max(1, available.height - 32)
        let frameWidth = min(maxWidth, maxHeight * ratio)
        let frameHeight = frameWidth / ratio
        let visible = visibleSize(image)
        let shown = CGSize(width: frameWidth / visible.width, height: frameHeight / visible.height)
        let c = clampedCenter(center, visible: visible)

        Image(uiImage: image)
            .resizable()
            .frame(width: shown.width, height: shown.height)
            .offset(x: (0.5 - c.x) * shown.width, y: (0.5 - c.y) * shown.height)
            .frame(width: frameWidth, height: frameHeight)
            .clipped()
            .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
            .frame(width: available.width, height: available.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(shown: shown, image: image).simultaneously(with: pinchGesture(image: image)))
    }

    private func dragGesture(shown: CGSize, image: UIImage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartCenter == nil { dragStartCenter = center }
                let start = dragStartCenter ?? center
                center = clampedCenter(CGPoint(x: start.x - value.translation.width / shown.width,
                                               y: start.y - value.translation.height / shown.height),
                                       visible: visibleSize(image))
            }
            .onEnded { _ in dragStartCenter = nil }
    }

    private func pinchGesture(image: UIImage) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartZoom == nil { pinchStartZoom = zoom }
                zoom = min(6, max(1, (pinchStartZoom ?? zoom) * value.magnification))
                center = clampedCenter(center, visible: visibleSize(image))
            }
            .onEnded { _ in pinchStartZoom = nil }
    }

    private func frameRatio(_ image: UIImage) -> CGFloat {
        aspect.ratio.map { CGFloat($0) } ?? image.size.width / max(1, image.size.height)
    }

    /// Visible part of the image (0...1 in each axis) at the current zoom.
    private func visibleSize(_ image: UIImage) -> CGSize {
        let frame = frameRatio(image)
        let photo = image.size.width / max(1, image.size.height)
        return CGSize(width: min(1, frame / photo) / zoom, height: min(1, photo / frame) / zoom)
    }

    private func clampedCenter(_ point: CGPoint, visible: CGSize) -> CGPoint {
        CGPoint(x: min(1 - visible.width / 2, max(visible.width / 2, point.x)),
                y: min(1 - visible.height / 2, max(visible.height / 2, point.y)))
    }

    private func load() {
        guard image == nil,
              let source = ImageStore.shared.cgImage(for: block.imageID),
              let oriented = source.oriented(quarterTurns: block.rotation, mirrored: block.mirrored) else { return }
        let loaded = UIImage(cgImage: oriented)
        image = loaded
        aspect = block.cropAspect
        if let crop = block.crop, crop.width > 0, crop.height > 0 {
            let frame = frameRatio(loaded)
            let photo = loaded.size.width / max(1, loaded.size.height)
            zoom = min(6, max(1, min(1, frame / photo) / CGFloat(crop.width)))
            center = CGPoint(x: crop.x + crop.width / 2, y: crop.y + crop.height / 2)
        }
    }

    private func commit() {
        guard let image else { return }
        block.cropAspect = aspect
        if aspect == .original, zoom <= 1.001 {
            block.crop = nil
            return
        }
        let visible = visibleSize(image)
        let c = clampedCenter(center, visible: visible)
        block.crop = CropRect(x: Double(c.x - visible.width / 2), y: Double(c.y - visible.height / 2),
                              width: Double(visible.width), height: Double(visible.height))
    }
}
