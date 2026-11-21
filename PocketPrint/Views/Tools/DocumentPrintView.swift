import SwiftUI

struct DocumentPrintView: View {
    let urls: [URL]

    @State private var source: DocumentSource?
    @State private var options = DocumentOptions(pages: [])
    @State private var preview: RasterPreview?
    @State private var bitmap: MonoBitmap?
    @State private var isRendering = false
    @State private var printJob: PrintJob?

    private let styles: [DitherStyle] = [.threshold, .document, .floydSteinberg, .halftone]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    PaperPreview(preview: preview, emptyMessage: emptyMessage)
                        .overlay(alignment: .topTrailing) {
                            if isRendering { ProgressView().padding(12) }
                        }
                    if let bitmap, !bitmap.isEmpty {
                        Text("48 mm × \(PaperLength.describe(dots: bitmap.height))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))

            Form {
                if let source, source.pages.count > 1 {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(source.pages.indices, id: \.self) { index in
                                    pageChip(index)
                                }
                            }
                        }
                        HStack {
                            Button("All") { options.pages = Array(source.pages.indices) }
                            Spacer()
                            Button("First only") { options.pages = [0] }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        if source.truncated {
                            Text("Only the first \(DocumentSource.maxPages) pages are shown.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Pages")
                    }
                }
                Section("Style") {
                    ChipPicker(options: styles, selection: $options.adjustments.style) { style in
                        Label(style.title, systemImage: style.systemImage)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    if options.adjustments.style == .threshold {
                        LabeledSlider(title: "Ink level", value: $options.adjustments.threshold, range: 0.3...0.85,
                                      format: { String(Int(($0 * 100).rounded())) })
                    } else {
                        LabeledSlider(title: "Brightness", value: $options.adjustments.brightness, range: -0.5...0.5,
                                      format: { String(Int(($0 * 100).rounded())) })
                    }
                }
                Section("Layout") {
                    Toggle("Trim white margins", isOn: $options.trimMargins)
                    Toggle("Turn wide pages sideways", isOn: $options.rotateLandscape)
                    Toggle("Cut line between pages", isOn: $options.separatePages)
                }
            }
            .frame(height: 320)
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
        .bottomActionBar {
            EditorActionBar(isPrintDisabled: bitmap?.isBlank ?? true) {
                guard let bitmap, !bitmap.isBlank else { return }
                printJob = PrintJob(title: urls.first?.deletingPathExtension().lastPathComponent ?? "Document",
                                    kind: .document, bitmap: bitmap,
                                    isTextMode: options.adjustments.style == .threshold || options.adjustments.style == .document,
                                    design: nil)
            }
        }
        .sheet(item: $printJob) { PrintSheet(job: $0) }
        .task {
            guard source == nil else { return }
            let files = urls
            let loaded = await Task.detached(priority: .userInitiated) { DocumentSource(urls: files) }.value
            source = loaded
            options.pages = Array(loaded.pages.indices.prefix(loaded.pages.count > 6 ? 1 : loaded.pages.count))
        }
        .task(id: options) {
            guard let source, !options.pages.isEmpty else {
                preview = nil
                bitmap = nil
                return
            }
            isRendering = true
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let current = options
            let result = await Task.detached(priority: .userInitiated) { DocumentComposer.compose(source, options: current) }.value
            guard !Task.isCancelled else { return }
            bitmap = result
            preview = RasterPreview(result)
            isRendering = false
        }
    }

    private var emptyMessage: String {
        guard let source else { return "Opening document…" }
        return source.pages.isEmpty ? "This file couldn't be read." : "Select at least one page."
    }

    private func pageChip(_ index: Int) -> some View {
        let selected = options.pages.contains(index)
        return Button {
            if selected {
                options.pages.removeAll { $0 == index }
            } else {
                options.pages.append(index)
                options.pages.sort()
            }
        } label: {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(index + 1)\(selected ? ", selected" : "")")
    }
}
