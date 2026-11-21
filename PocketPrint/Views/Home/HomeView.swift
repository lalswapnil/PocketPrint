import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var photoItem: PhotosPickerItem?
    @State private var scanItem: PhotosPickerItem?
    @State private var showScanOptions = false
    @State private var showScanLibrary = false
    @State private var showScanCamera = false
    @State private var showDocumentPicker = false
    @State private var showPrinterPicker = false
    @State private var reprintJob: PrintJob?
    @State private var busyMessage: String?
    @State private var errorMessage: String?
    @State private var clipboard = ClipboardContent.nothing

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)]

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.createPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        PrinterStatusCard(compact: true, onChoose: { showPrinterPicker = true })
                        PasteCard(content: clipboard, onPaste: paste)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ToolTile(title: "Photo", systemImage: "photo.fill", color: .orange)
                        }
                        .buttonStyle(.plain)
                        tile("Note", "note.text", .yellow) { .design(DesignRoute(design: .note(), autoEdit: true)) }
                        tile("Checklist", "checklist", .green) { .design(DesignRoute(design: .checklistStarter(), autoEdit: true)) }
                        tile("Label", "tag.fill", .purple) { .design(DesignRoute(design: .label(), autoEdit: true)) }
                        tile("QR Code", "qrcode", .blue) { .design(DesignRoute(design: .qrStarter(), autoEdit: true)) }
                        tile("Banner", "textformat.size", .red) { .banner }
                        tile("Draw", "scribble.variable", .pink) { .draw }
                        tile("Calendar", "calendar", .teal) { .design(DesignRoute(design: .calendarStarter())) }
                        Button { showDocumentPicker = true } label: {
                            ToolTile(title: "Document", systemImage: "doc.richtext.fill", color: .indigo)
                        }
                        .buttonStyle(.plain)
                        tile("Web Page", "safari.fill", .cyan) { .web }
                        Button { showScanOptions = true } label: {
                            ToolTile(title: "Scan Text", systemImage: "text.viewfinder", color: .mint)
                        }
                        .buttonStyle(.plain)
                        tile("Templates", "square.grid.2x2.fill", .brown) { .templates }
                    }

                    if !history.entries.isEmpty {
                        recentSection
                    }

                    TemplateStrip()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PocketPrint")
            .navigationDestination(for: CreateRoute.self) { route in
                destination(for: route)
            }
            .overlay {
                if let busyMessage {
                    ProgressView(busyMessage)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            loadPhoto(item)
        }
        .onAppear { clipboard = .current }
        .onChange(of: scenePhase) { _, phase in
            // Something may have been copied in another app.
            if phase == .active { clipboard = .current }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboard = .current
        }
        .onChange(of: scanItem) { _, item in
            guard let item else { return }
            scanItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await scan(image)
            }
        }
        .photosPicker(isPresented: $showScanLibrary, selection: $scanItem, matching: .images)
        .confirmationDialog("Scan text", isPresented: $showScanOptions, titleVisibility: .visible) {
            if CameraPicker.isAvailable {
                Button("Take Photo") { showScanCamera = true }
            }
            Button("Choose from Library") { showScanLibrary = true }
        } message: {
            Text("Text is recognised on this iPhone and turned into an editable note.")
        }
        .fullScreenCover(isPresented: $showScanCamera) {
            CameraPicker { image in Task { await scan(image) } }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let local = urls.compactMap { url -> URL? in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return AppRouter.copyToTemporary(url)
            }
            if !local.isEmpty { router.open(.document(local)) }
        }
        .sheet(isPresented: $showPrinterPicker) { PrinterPickerSheet() }
        .sheet(item: $reprintJob) { PrintSheet(job: $0) }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func tile(_ title: String, _ systemImage: String, _ color: Color, route: @escaping () -> CreateRoute) -> some View {
        Button {
            router.open(route())
        } label: {
            ToolTile(title: title, systemImage: systemImage, color: color)
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Print Again")
                    .font(.title3.bold())
                Spacer()
                Button("History") { router.tab = .history }
                    .font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(history.entries.prefix(10)) { entry in
                        Button {
                            reprintJob = history.job(for: entry)
                        } label: {
                            HistoryThumbnail(entry: entry)
                                .frame(width: 96, height: 128)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Print \(entry.title) again")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: CreateRoute) -> some View {
        Group {
            switch route {
            case .design(let designRoute): DesignEditorView(design: designRoute.design, autoEdit: designRoute.autoEdit)
            case .templates: TemplateGalleryView()
            case .photo(let imageID): PhotoEditorView(imageID: imageID)
            case .banner: BannerView()
            case .draw: DrawView()
            case .document(let urls): DocumentPrintView(urls: urls)
            case .web: WebPrintView()
            }
        }
        // Editors use the bottom of the screen for their own tools.
        .toolbar(.hidden, for: .tabBar)
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        busyMessage = "Opening photo…"
        Task {
            defer { busyMessage = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let id = await Task.detached(priority: .userInitiated, operation: { ImageStore.shared.save(data: data) }).value else {
                errorMessage = "That photo couldn't be opened."
                return
            }
            router.open(.photo(id))
        }
    }

    /// Opens what was pasted in the matching editor: one picture in the photo editor,
    /// several pictures as one print, a PDF in the document tool and text as a note.
    private func paste(_ providers: [NSItemProvider]) {
        busyMessage = "Pasting…"
        Task {
            defer { busyMessage = nil }
            switch await ClipboardReader.load(providers) {
            case .images(let ids) where ids.count == 1:
                router.open(.photo(ids[0]))
            case .images(let ids):
                router.open(.design(DesignRoute(design: .pastedImages(ids, style: settings.photoStyle))))
            case .document(let url):
                router.open(.document([url]))
            case .text(let text):
                router.open(.design(DesignRoute(design: .pastedText(text))))
            case nil:
                errorMessage = ClipboardReader.unreadable
            }
        }
    }

    private func scan(_ image: UIImage) async {
        busyMessage = "Reading text…"
        defer { busyMessage = nil }
        do {
            let text = try await TextRecognizer.recognizeText(in: image)
            guard !text.isEmpty else {
                errorMessage = "No text was found in that photo. Try again with the text filling more of the frame."
                return
            }
            router.open(.design(DesignRoute(design: .scannedText(text), autoEdit: true)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ToolTile: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 13).fill(color.gradient))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Paste a copied picture, PDF or text and go straight to printing it.
/// Uses the system paste button, so iOS doesn't ask for permission to read the clipboard.
struct PasteCard: View {
    let content: ClipboardContent
    let onPaste: ([NSItemProvider]) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clipboard")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(content == .nothing ? Color.secondary : Color.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            PasteButton(supportedContentTypes: ClipboardReader.supportedTypes, payloadAction: onPaste)
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .tint(Color.accentColor)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var subtitle: String {
        switch content {
        case .images: return "Picture ready to print"
        case .document: return "PDF ready to print"
        case .text: return "Text ready to print"
        case .nothing: return "Nothing copied yet"
        }
    }
}

struct HistoryThumbnail: View {
    @Environment(HistoryStore.self) private var history
    let entry: HistoryEntry

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.white
                if let image = history.thumbnail(for: entry) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width - 12)
                        .padding(.top, 6)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}
