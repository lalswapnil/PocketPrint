import PencilKit
import SwiftUI

struct DrawView: View {
    @State private var canvas = PKCanvasView()
    @State private var lengthMM = 60
    @State private var shaded = false
    @State private var isEmpty = true
    @State private var canvasWidth: CGFloat = 0
    @State private var printJob: PrintJob?
    @State private var confirmClear = false

    private let lengths = [40, 60, 80, 120, 160]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ChipPicker(options: lengths, selection: $lengthMM) { Text("\($0) mm") }
                Toggle(isOn: $shaded) { Image(systemName: "circle.lefthalf.striped.horizontal") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Shaded strokes")
            }
            .padding(.horizontal, 16)

            GeometryReader { proxy in
                let width = proxy.size.width - 40
                let contentHeight = width * CGFloat(lengthMM) * PrinterCatalog.dotsPerMillimeter / CGFloat(PrinterCatalog.printWidth)
                DrawingCanvas(canvas: canvas, contentHeight: contentHeight) {
                    isEmpty = canvas.drawing.strokes.isEmpty
                }
                .frame(width: width, height: min(contentHeight, proxy.size.height - 8))
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear { canvasWidth = width }
                .onChange(of: width) { _, newValue in canvasWidth = newValue }
            }
            Text(shaded ? "Shaded: soft pencil strokes keep their texture." : "Crisp: every stroke prints solid black.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 90)
        }
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Draw")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { canvas.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("Undo")
                Button { confirmClear = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Clear")
                    .disabled(isEmpty)
                Button("Print") { preparePrint() }
                    .fontWeight(.semibold)
                    .disabled(isEmpty)
            }
        }
        .confirmationDialog("Clear the drawing?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                canvas.drawing = PKDrawing()
                isEmpty = true
            }
        }
        .sheet(item: $printJob) { PrintSheet(job: $0) }
    }

    private func preparePrint() {
        guard canvasWidth > 0 else { return }
        let width = PrinterCatalog.printWidth
        let height = Int(CGFloat(lengthMM) * PrinterCatalog.dotsPerMillimeter)
        let bounds = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasWidth * CGFloat(height) / CGFloat(width))
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = canvas.drawing.image(from: bounds, scale: CGFloat(width) / canvasWidth)
        }
        guard let cgImage = image?.cgImage else { return }
        let gray = GrayImage(cgImage: cgImage, width: width, height: height)
        let bitmap = shaded ? Dither.atkinson(gray) : Dither.threshold(gray, level: 0.85)
        printJob = PrintJob(title: "Drawing", kind: .drawing, bitmap: bitmap, isTextMode: !shaded, design: nil)
    }
}

/// PencilKit canvas with the system tool picker. Ink is always black on white, even in Dark Mode.
struct DrawingCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    let contentHeight: CGFloat
    var onChange: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvas.delegate = context.coordinator
        canvas.alwaysBounceVertical = false
        let picker = context.coordinator.toolPicker
        picker.overrideUserInterfaceStyle = .light
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        let size = CGSize(width: view.bounds.width, height: max(contentHeight, view.bounds.height))
        if view.contentSize != size { view.contentSize = size }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var onChange: () -> Void

        init(onChange: @escaping () -> Void) {
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange()
        }
    }
}
