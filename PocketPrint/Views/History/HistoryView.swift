import SwiftUI

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(AppRouter.self) private var router

    @State private var reprintJob: PrintJob?
    @State private var confirmClear = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No prints yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Everything you print is kept here on your iPhone, so you can print it again or keep editing.")
                    } actions: {
                        Button("Create Something") { router.tab = .create }
                            .prominentActionStyle()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(history.entries) { entry in
                                NavigationLink(value: entry) {
                                    HistoryCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Print Again", systemImage: "printer") { reprintJob = history.job(for: entry) }
                                    if entry.hasDesign, let design = history.design(for: entry) {
                                        Button("Edit", systemImage: "square.and.pencil") { router.edit(design) }
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) { history.delete(entry) }
                                }
                            }
                        }
                        .padding(20)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: HistoryEntry.self) { entry in
                HistoryDetailView(entry: entry)
                    .toolbar(.hidden, for: .tabBar)
            }
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Clear History", systemImage: "trash", role: .destructive) { confirmClear = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .confirmationDialog("Delete all \(history.entries.count) prints from History?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { history.deleteAll() }
            }
            .sheet(item: $reprintJob) { PrintSheet(job: $0) }
        }
    }
}

struct HistoryCard: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HistoryThumbnail(entry: entry)
                .aspectRatio(0.8, contentMode: .fit)
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.title, systemImage: entry.kind.systemImage)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(entry.date, format: .relative(presentation: .named)) · \(PaperLength.describe(dots: entry.heightDots))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct HistoryDetailView: View {
    let entry: HistoryEntry

    @Environment(HistoryStore.self) private var history
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var preview: RasterPreview?
    @State private var printJob: PrintJob?
    @State private var shareURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                PaperPreview(preview: preview, emptyMessage: "Loading…")
                Text("\(entry.kind.title) · 48 mm × \(PaperLength.describe(dots: entry.heightDots)) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .bottomActionBar {
            EditorActionBar(printTitle: "Print Again") {
                printJob = history.job(for: entry)
            } tools: {
                if let shareURL {
                    ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share image")
                        .secondaryActionStyle()
                        .controlSize(.large)
                }
                if entry.hasDesign {
                    Button {
                        if let design = history.design(for: entry) { router.edit(design) }
                    } label: {
                        ToolBarButtonLabel(title: "Edit", systemImage: "square.and.pencil")
                    }
                    .secondaryActionStyle()
                    .controlSize(.large)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete")
            }
        }
        .sheet(item: $printJob) { PrintSheet(job: $0) }
        .confirmationDialog("Delete this print from History?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                history.delete(entry)
                dismiss()
            }
        }
        .task {
            if let bitmap = history.bitmap(for: entry) { preview = RasterPreview(bitmap) }
            if let data = history.pngData(for: entry) {
                let name = entry.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name.isEmpty ? "Print" : name).png")
                try? data.write(to: url, options: .atomic)
                shareURL = url
            }
        }
    }
}
