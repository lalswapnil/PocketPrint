import Combine
import SwiftUI
import WebKit

/// Owns the web view and publishes its navigation state.
final class WebPageModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var hasPage = false
    @Published var errorMessage: String?
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] view, _ in self?.progress = view.estimatedProgress },
            webView.observe(\.isLoading) { [weak self] view, _ in self?.isLoading = view.isLoading },
            webView.observe(\.title) { [weak self] view, _ in self?.title = view.title ?? "" },
            webView.observe(\.canGoBack) { [weak self] view, _ in self?.canGoBack = view.canGoBack },
            webView.observe(\.canGoForward) { [weak self] view, _ in self?.canGoForward = view.canGoForward },
        ]
    }

    /// Accepts "example.com" or full URLs. No search engine is involved.
    @discardableResult
    func load(_ text: String) -> Bool {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return false }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), let host = url.host, host.contains(".") || host == "localhost" else { return false }
        errorMessage = nil
        hasPage = true
        webView.load(URLRequest(url: url))
        return true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        errorMessage = error.localizedDescription
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebPrintView: View {
    @StateObject private var model = WebPageModel()
    @State private var address = ""
    @State private var capture: WebCapture?
    @State private var isCapturing = false
    @State private var invalidAddress = false
    @FocusState private var addressFocused: Bool

    /// The page is laid out at this width so text prints at a readable size on 48 mm.
    private let pageWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("Web address, e.g. example.com", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .onSubmit(go)
                if !address.isEmpty {
                    Button { address = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear address")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if model.isLoading {
                ProgressView(value: model.progress)
                    .padding(.horizontal, 16)
            }

            ZStack {
                Color(.systemGroupedBackground)
                if model.hasPage {
                    WebViewContainer(webView: model.webView)
                        .frame(width: pageWidth)
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                } else {
                    ContentUnavailableView {
                        Label("Print a web page", systemImage: "safari")
                    } description: {
                        Text("Type an address above. The page is shown at paper width, so what you see is what prints. Close pop-ups before printing.")
                    }
                }
                if let error = model.errorMessage {
                    VStack {
                        Spacer()
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(model.title.isEmpty ? "Web Page" : model.title)
        .navigationBarTitleDisplayMode(.inline)
        .bottomActionBar {
            EditorActionBar(isPrintDisabled: !model.hasPage || model.isLoading || isCapturing) {
                Task { await capturePage() }
            } tools: {
                HStack(spacing: 18) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!model.canGoBack)
                        .accessibilityLabel("Back")
                    Button { model.webView.goForward() } label: { Image(systemName: "chevron.forward") }
                        .disabled(!model.canGoForward)
                        .accessibilityLabel("Forward")
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(!model.hasPage)
                        .accessibilityLabel("Reload")
                    if isCapturing { ProgressView() }
                }
                .font(.title3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .modifier(GlassCapsule())
            }
        }
        .alert("Enter a web address", isPresented: $invalidAddress) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("For example: example.com or https://example.com/page")
        }
        .sheet(item: $capture) { WebCaptureSheet(capture: $0) }
        .onAppear { if !model.hasPage { addressFocused = true } }
    }

    private func go() {
        if !model.load(address) { invalidAddress = true }
    }

    private func capturePage() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            let data = try await model.webView.pdf(configuration: WKPDFConfiguration())
            let source = await Task.detached(priority: .userInitiated) { DocumentSource(pdfData: data) }.value
            guard !source.pages.isEmpty else {
                model.errorMessage = "This page couldn't be captured."
                return
            }
            capture = WebCapture(source: source, title: model.title.isEmpty ? "Web Page" : model.title)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

struct WebCapture: Identifiable {
    let id = UUID()
    let source: DocumentSource
    let title: String
}

/// Options and preview for a captured web page.
struct WebCaptureSheet: View {
    let capture: WebCapture
    @Environment(\.dismiss) private var dismiss
    @State private var options = DocumentOptions(pages: [], adjustments: ImageAdjustments(style: .threshold, sharpness: 0, threshold: 0.6, autoLevels: false),
                                                 rotateLandscape: false, trimMargins: true, separatePages: false)
    @State private var fullLength = 0
    @State private var limitCM: Double = 30
    @State private var limitEnabled = true
    @State private var preview: RasterPreview?
    @State private var bitmap: MonoBitmap?
    @State private var printJob: PrintJob?

    private let styles: [DitherStyle] = [.threshold, .floydSteinberg, .halftone]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    PaperPreview(preview: preview, emptyMessage: "Preparing…")
                        .padding(20)
                }
                .background(Color(.systemGroupedBackground))
                Form {
                    Section("Style") {
                        ChipPicker(options: styles, selection: $options.adjustments.style) { style in
                            Label(style.title, systemImage: style.systemImage)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        Toggle("Trim white margins", isOn: $options.trimMargins)
                    }
                    Section {
                        Toggle("Limit length", isOn: $limitEnabled)
                        if limitEnabled {
                            LabeledSlider(title: "Print the first", value: $limitCM, range: 5...max(6, maxCM), step: 1,
                                          format: { "\(Int($0)) cm" })
                        }
                    } header: {
                        Text("Length")
                    } footer: {
                        Text("Full page: \(PaperLength.describe(dots: fullLength)).")
                    }
                }
                .frame(height: 300)
            }
            .navigationTitle("Print Web Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") {
                        guard let bitmap else { return }
                        printJob = PrintJob(title: capture.title, kind: .web, bitmap: bitmap,
                                            isTextMode: options.adjustments.style == .threshold, design: nil)
                    }
                    .fontWeight(.semibold)
                    .disabled(bitmap == nil)
                }
            }
            .sheet(item: $printJob) { PrintSheet(job: $0) }
        }
        .task(id: renderKey) {
            var current = options
            current.pages = Array(capture.source.pages.indices)
            current.maxLength = 0
            let source = capture.source
            let full = await Task.detached(priority: .userInitiated) { DocumentComposer.compose(source, options: current) }.value
            guard !Task.isCancelled else { return }
            fullLength = full.height
            let limit = limitEnabled ? Int(limitCM * 10 * PrinterCatalog.dotsPerMillimeter) : 0
            let result = limit > 0 && full.height > limit ? full.cropped(x: 0, y: 0, width: full.width, height: limit) : full
            bitmap = result
            preview = RasterPreview(result)
        }
    }

    private var maxCM: Double {
        max(5, (Double(fullLength) / PrinterCatalog.dotsPerMillimeter / 10).rounded(.up))
    }

    private var renderKey: String {
        "\(options.adjustments.style.rawValue)-\(options.trimMargins)-\(limitEnabled)-\(Int(limitCM))"
    }
}
