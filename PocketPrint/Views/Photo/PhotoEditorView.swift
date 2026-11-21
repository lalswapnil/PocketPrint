import PhotosUI
import SwiftUI

struct PhotoEditorView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    @State private var block: ImageBlock
    @State private var caption = ""
    @State private var captionStyle = TextStyle(size: 30, bold: true, align: .center)
    @State private var addDate = false
    @State private var preview: RasterPreview?
    @State private var renderer = DesignRenderer()
    @State private var printJob: PrintJob?
    @State private var appliedDefaults = false
    @State private var showReplacePicker = false
    @State private var replaceItem: PhotosPickerItem?
    @State private var showControls = true

    // Stable block identities keep the renderer's cache effective.
    @State private var imageBlockID = UUID()
    @State private var captionBlockID = UUID()
    @State private var dateBlockID = UUID()

    init(imageID: String) {
        _block = State(initialValue: ImageBlock(imageID: imageID))
    }

    private var design: Design {
        var blocks: [Block] = []
        var image = Block(.image(block))
        image.id = imageBlockID
        blocks.append(image)
        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var text = Block(.text(TextBlock(text: caption, style: captionStyle)))
            text.id = captionBlockID
            blocks.append(text)
        }
        if addDate {
            var date = Block(.text(TextBlock(text: "{date}", style: TextStyle(size: 22, align: .center))))
            date.id = dateBlockID
            blocks.append(date)
        }
        return Design(title: caption.isEmpty ? "Photo" : caption, blocks: blocks, margin: 0, spacing: 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    PaperPreview(preview: preview, emptyMessage: "Preparing preview…", onTap: { _ in
                        withAnimation(.snappy) { showControls.toggle() }
                    })
                    if let preview {
                        Text("48 mm × \(PaperLength.describe(dots: preview.height)) · exactly as it will print")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))

            if showControls {
                Form {
                    PhotoAdjustmentsPanel(block: $block, showsSize: true)
                    Section("Caption") {
                        TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                            .lineLimit(1...3)
                        if !caption.isEmpty {
                            TextStyleControls(style: $captionStyle, sizeRange: 16...96)
                        }
                        Toggle("Add today's date", isOn: $addDate)
                    }
                }
                .frame(height: 340)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Replace Photo", systemImage: "photo.on.rectangle") { showReplacePicker = true }
                    Button("Add Text, Lists & More…", systemImage: "square.and.pencil") {
                        router.open(.design(DesignRoute(design: design)))
                    }
                    Button(showControls ? "Hide Controls" : "Show Controls", systemImage: "slider.horizontal.3") {
                        withAnimation(.snappy) { showControls.toggle() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .bottomActionBar {
            EditorActionBar(onPrint: preparePrint) {
                Button {
                    withAnimation(.snappy) { showControls.toggle() }
                } label: {
                    ToolBarButtonLabel(title: showControls ? "Hide Tools" : "Adjust", systemImage: "slider.horizontal.3")
                }
                .secondaryActionStyle()
                .controlSize(.large)
            }
        }
        .photosPicker(isPresented: $showReplacePicker, selection: $replaceItem, matching: .images)
        .onChange(of: replaceItem) { _, item in
            guard let item else { return }
            replaceItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let id = await Task.detached(operation: { ImageStore.shared.save(data: data) }).value else { return }
                block.imageID = id
                block.crop = nil
                block.rotation = 0
                block.mirrored = false
            }
        }
        .sheet(item: $printJob) { PrintSheet(job: $0) }
        .task(id: design) {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let result = await renderer.render(design, purpose: .print)
            guard !Task.isCancelled else { return }
            preview = RasterPreview(result.bitmap)
        }
        .onAppear {
            guard !appliedDefaults else { return }
            appliedDefaults = true
            block.adjustments.style = settings.photoStyle
        }
    }

    private func preparePrint() {
        let current = design
        Task {
            let result = await renderer.render(current, purpose: .print)
            guard !result.bitmap.isEmpty else { return }
            printJob = PrintJob(title: current.title, kind: .photo, bitmap: result.bitmap, isTextMode: false, design: current)
        }
    }
}
