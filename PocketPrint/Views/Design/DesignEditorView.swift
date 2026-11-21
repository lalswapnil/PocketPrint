import PhotosUI
import SwiftUI

struct EditingBlock: Identifiable, Equatable {
    let id: UUID
}

/// What-you-see-is-what-prints editor: the preview *is* the canvas. Tap any part to edit it.
struct DesignEditorView: View {
    @Environment(AppSettings.self) private var settings

    @State private var design: Design
    @State private var rendered = RenderedDesign.empty
    @State private var preview: RasterPreview?
    @State private var renderer = DesignRenderer()
    @State private var editing: EditingBlock?
    @State private var pendingAutoEdit: Bool
    @State private var showPageStyle = false
    @State private var printJob: PrintJob?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var scanItem: PhotosPickerItem?
    @State private var showScanPicker = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmClear = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var previewWidth: CGFloat = 0
    @State private var busyMessage: String?
    @State private var alertMessage: String?

    init(design: Design, autoEdit: Bool = false) {
        _design = State(initialValue: design)
        _pendingAutoEdit = State(initialValue: autoEdit)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PaperPreview(preview: preview, highlight: highlightRange, hints: hints,
                             emptyMessage: "Your print is empty.\nAdd text, photos, lists and more with the buttons below.",
                             onTap: handleTap)
                    .accessibilityIdentifier("designPreview")
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { previewWidth = $0 }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if rendered.overflows {
                    Label("The content is longer than the \(design.lengthMM) mm label length.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                }

                if design.blocks.isEmpty {
                    quickAdd
                } else if let preview {
                    Text("48 mm × \(PaperLength.describe(dots: preview.height)) · Tap any part to edit it")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, editing == nil ? 24 : 420)
        }
        .scrollPosition($scrollPosition)
        .background(Color(.systemGroupedBackground))
        .bottomActionBar { actionBar }
        .navigationTitle(design.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $editing) { item in
            if let block = blockBinding(item.id) {
                BlockEditorSheet(
                    block: block,
                    canMoveUp: index(of: item.id).map { $0 > 0 } ?? false,
                    canMoveDown: index(of: item.id).map { $0 < design.blocks.count - 1 } ?? false,
                    onMove: { offset in move(item.id, by: offset) },
                    onDuplicate: { duplicate(item.id) },
                    onDelete: { delete(item.id) }
                )
                .presentationDetents([.fraction(0.5), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
                .presentationContentInteraction(.scrolls)
            }
        }
        .sheet(isPresented: $showPageStyle) {
            PageStyleSheet(design: $design)
                .presentationDetents([.fraction(0.5), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
        }
        .sheet(item: $printJob) { PrintSheet(job: $0) }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .photosPicker(isPresented: $showScanPicker, selection: $scanItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in addPhoto(image) }
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                addPhoto(image)
            }
        }
        .onChange(of: scanItem) { _, item in
            guard let item else { return }
            scanItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await addScannedText(image)
            }
        }
        .onChange(of: editing) { _, newValue in
            if let id = newValue?.id { scrollTo(id) }
        }
        .task(id: design) { await renderPreview() }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { design.title = trimmed }
            }
        }
        .alert("PocketPrint", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Remove everything from this print?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) {
                editing = nil
                design.blocks.removeAll()
            }
        }
        .overlay {
            if let busyMessage {
                ProgressView(busyMessage)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Rename", systemImage: "pencil") {
                    renameText = design.title
                    showRename = true
                }
                Button("Page Style", systemImage: "rectangle.dashed") { showPageStyle = true }
                if !design.blocks.isEmpty {
                    Button("Remove All", systemImage: "trash", role: .destructive) { confirmClear = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    private var actionBar: some View {
        EditorActionBar(onPrint: preparePrint) {
            addMenu
                .secondaryActionStyle()
                .controlSize(.large)
            Button {
                showPageStyle = true
            } label: {
                ToolBarButtonLabel(title: "Style", systemImage: "rectangle.dashed")
            }
            .secondaryActionStyle()
            .controlSize(.large)
        }
    }

    private var addMenu: some View {
        Menu {
            Section {
                Button("Text", systemImage: "textformat") { add(.text(TextBlock())) }
                Button("Photo", systemImage: "photo") { showPhotoPicker = true }
                if CameraPicker.isAvailable {
                    Button("Take Photo", systemImage: "camera") { showCamera = true }
                }
                Button("Paste", systemImage: "doc.on.clipboard") { pasteFromClipboard() }
                Button("Checklist", systemImage: "checklist") { add(.checklist(ChecklistBlock())) }
            }
            Section {
                Button("QR Code", systemImage: "qrcode") { add(.qr(QRBlock())) }
                Button("Barcode", systemImage: "barcode") { add(.barcode(BarcodeBlock())) }
                Button("Emoji & Icons", systemImage: "face.smiling") { add(.symbol(SymbolBlock())) }
                Button("Calendar", systemImage: "calendar") { add(.calendar(.currentMonth)) }
            }
            Section {
                Button("Date & Time", systemImage: "clock") {
                    add(.text(TextBlock(text: "{date} · {time}", style: TextStyle(size: 24, align: .center))), edit: false)
                }
                Button("Divider", systemImage: "minus") { add(.divider(DividerBlock())) }
                Button("Space", systemImage: "arrow.up.and.down") { add(.spacer(SpacerBlock())) }
                Button("Text from Photo", systemImage: "text.viewfinder") { showScanPicker = true }
            }
        } label: {
            ToolBarButtonLabel(title: "Add", systemImage: "plus")
        }
    }

    private var quickAdd: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                quickButton("Text", "textformat") { add(.text(TextBlock())) }
                quickButton("Photo", "photo") { showPhotoPicker = true }
                quickButton("List", "checklist") { add(.checklist(ChecklistBlock())) }
                quickButton("QR", "qrcode") { add(.qr(QRBlock())) }
            }
        }
        .padding(.horizontal, 20)
    }

    private func quickButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .secondaryActionStyle()
    }

    // MARK: Rendering

    private func renderPreview() async {
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return }
        let result = await renderer.render(design, purpose: .preview)
        guard !Task.isCancelled else { return }
        rendered = result
        preview = RasterPreview(result.bitmap)
        if pendingAutoEdit, let last = design.blocks.last {
            pendingAutoEdit = false
            editing = EditingBlock(id: last.id)
        }
    }

    private var highlightRange: Range<Int>? {
        editing.flatMap { rendered.blockRanges[$0.id] }
    }

    private var hints: [PreviewHint] {
        rendered.hints.compactMap { id, text in
            rendered.blockRanges[id].map { PreviewHint(id: id, range: $0, text: text) }
        }
    }

    private func handleTap(_ row: Int) {
        guard !design.blocks.isEmpty else { return }
        let ranges = design.blocks.compactMap { block in rendered.blockRanges[block.id].map { (block.id, $0) } }
        if let hit = ranges.first(where: { $0.1.contains(row) }) {
            editing = EditingBlock(id: hit.0)
        } else if let nearest = ranges.min(by: { distance($0.1, row) < distance($1.1, row) }) {
            editing = EditingBlock(id: nearest.0)
        }
    }

    private func distance(_ range: Range<Int>, _ row: Int) -> Int {
        row < range.lowerBound ? range.lowerBound - row : max(0, row - range.upperBound)
    }

    private func scrollTo(_ id: UUID) {
        guard let range = rendered.blockRanges[id], let preview, previewWidth > 0 else { return }
        let scale = previewWidth / CGFloat(preview.width)
        let top = 12 + 18 + CGFloat(range.lowerBound) * scale - 24
        withAnimation(.smooth) { scrollPosition.scrollTo(y: max(0, top)) }
    }

    // MARK: Editing

    private func index(of id: UUID) -> Int? {
        design.blocks.firstIndex { $0.id == id }
    }

    private func blockBinding(_ id: UUID) -> Binding<Block>? {
        guard index(of: id) != nil else { return nil }
        return Binding(
            get: { design.blocks.first { $0.id == id } ?? Block(.spacer(SpacerBlock(height: 0))) },
            set: { newValue in
                if let i = index(of: id) { design.blocks[i] = newValue }
            }
        )
    }

    private func add(_ content: BlockContent, edit: Bool = true) {
        insert([Block(content)], edit: edit)
    }

    /// Inserts after the block being edited (or at the end), keeping the given order.
    /// A single new block opens its editor straight away.
    private func insert(_ blocks: [Block], edit: Bool = true) {
        guard !blocks.isEmpty else { return }
        let position = editing.flatMap { index(of: $0.id) }.map { $0 + 1 } ?? design.blocks.count
        design.blocks.insert(contentsOf: blocks, at: position)
        guard edit else { return }
        editing = nil
        guard blocks.count == 1, let block = blocks.first else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            editing = EditingBlock(id: block.id)
        }
    }

    /// Adds copied pictures or text. Reading the clipboard from a menu may make iOS ask "Allow Paste".
    private func pasteFromClipboard() {
        switch ClipboardContent.current {
        case .images, .text:
            break
        case .document:
            alertMessage = "A copied PDF can't be added to a design. Use Paste on the Create screen to print it."
            return
        case .nothing:
            alertMessage = ClipboardReader.howToCopy
            return
        }
        let providers = UIPasteboard.general.itemProviders
        guard !providers.isEmpty else {
            alertMessage = ClipboardReader.notAllowed
            return
        }
        busyMessage = "Pasting…"
        Task {
            defer { busyMessage = nil }
            switch await ClipboardReader.load(providers, includeDocuments: false) {
            case .images(let ids):
                let style = settings.photoStyle
                insert(ids.map { Block(.image(ImageBlock(imageID: $0, adjustments: ImageAdjustments(style: style)))) })
            case .text(let text):
                insert([Block(.text(TextBlock(text: text, style: TextStyle(size: 28))))])
            case .document, nil:
                alertMessage = ClipboardReader.unreadable
            }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = index(of: id) else { return }
        let target = i + offset
        guard design.blocks.indices.contains(target) else { return }
        design.blocks.swapAt(i, target)
    }

    private func duplicate(_ id: UUID) {
        guard let i = index(of: id) else { return }
        var copy = design.blocks[i]
        copy.id = UUID()
        design.blocks.insert(copy, at: i + 1)
        editing = EditingBlock(id: copy.id)
    }

    private func delete(_ id: UUID) {
        editing = nil
        design.blocks.removeAll { $0.id == id }
    }

    private func addPhoto(_ image: UIImage) {
        busyMessage = "Adding photo…"
        Task {
            defer { busyMessage = nil }
            let id = await Task.detached(priority: .userInitiated) { ImageStore.shared.save(image) }.value
            guard let id else {
                alertMessage = "That photo couldn't be added."
                return
            }
            add(.image(ImageBlock(imageID: id, adjustments: ImageAdjustments(style: settings.photoStyle))))
        }
    }

    private func addScannedText(_ image: UIImage) async {
        busyMessage = "Reading text…"
        defer { busyMessage = nil }
        let text = (try? await TextRecognizer.recognizeText(in: image)) ?? ""
        guard !text.isEmpty else {
            alertMessage = "No text was found in that photo."
            return
        }
        add(.text(TextBlock(text: text, style: TextStyle(size: 26))))
    }

    private func preparePrint() {
        editing = nil
        Task {
            let result = await renderer.render(design, purpose: .print)
            guard !result.bitmap.isBlank else {
                alertMessage = "There's nothing to print yet. Add some text or a photo first."
                return
            }
            printJob = PrintJob(title: design.title, kind: .design, bitmap: result.bitmap,
                                isTextMode: result.isTextMode, design: design)
        }
    }
}

/// Frame, margins, spacing and label length for the whole print.
struct PageStyleSheet: View {
    @Binding var design: Design
    @Environment(\.dismiss) private var dismiss

    private let lengths = [0, 30, 40, 50, 60, 75, 100]

    var body: some View {
        NavigationStack {
            Form {
                Section("Border") {
                    ChipPicker(options: FrameStyle.allCases, selection: $design.frame) { Text($0.title) }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section {
                    ChipPicker(options: lengths, selection: $design.lengthMM) { length in
                        Text(length == 0 ? "Fit content" : "\(length) mm")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    Text("Length")
                } footer: {
                    Text("Use a fixed length for labels and stickers so every print is the same size.")
                }
                Section("Spacing") {
                    LabeledSlider(title: "Side margins", value: Binding(get: { Double(design.margin) }, set: { design.margin = Int($0) }),
                                  range: 0...48, step: 2, format: { String(format: "%.1f mm", $0 / 8) })
                    LabeledSlider(title: "Gap between items", value: Binding(get: { Double(design.spacing) }, set: { design.spacing = Int($0) }),
                                  range: 0...64, step: 2, format: { String(format: "%.1f mm", $0 / 8) })
                }
            }
            .navigationTitle("Page Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
