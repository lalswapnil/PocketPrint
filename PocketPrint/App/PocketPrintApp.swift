import SwiftUI

@main
struct PocketPrintApp: App {
    @State private var settings: AppSettings
    @State private var printer: PrinterService
    @State private var history: HistoryStore
    @State private var router = AppRouter()

    init() {
        let settings = AppSettings()
        let history = HistoryStore()
        _settings = State(initialValue: settings)
        _printer = State(initialValue: PrinterService(settings: settings))
        _history = State(initialValue: history)
        let referenced = history.referencedImageIDs()
        DispatchQueue.global(qos: .utility).async {
            ImageStore.shared.removeUnreferenced(keeping: referenced)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(printer)
                .environment(history)
                .environment(router)
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PrinterService.self) private var printer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Create", systemImage: "square.grid.2x2.fill", value: AppTab.create) {
                HomeView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Printer", systemImage: "printer.fill", value: AppTab.printer) {
                PrinterView()
            }
        }
        .onOpenURL { url in
            router.handleIncoming(url)
        }
        .onChange(of: scenePhase) { _, phase in
            // Battery and paper state may have changed while the app was in the background.
            if phase == .active { printer.requestStatus() }
        }
        .sheet(item: $router.pendingPrintJob) { PrintSheet(job: $0) }
        .alert("Can't open file", isPresented: Binding(get: { router.message != nil }, set: { if !$0 { router.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.message ?? "")
        }
        #if DEBUG
        .task { DebugLaunch.apply(router: router, printer: printer) }
        #endif
    }
}

#if DEBUG
/// Lets UI checks open a screen directly: `-uiRoute templates|note|label|banner|draw|web|printer|history|photo|pasted|document|printsheet|battery`.
enum DebugLaunch {
    @MainActor static func apply(router: AppRouter, printer: PrinterService) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiRoute"), index + 1 < arguments.count else { return }
        let route = arguments[index + 1]
        switch route {
        case "printer": router.tab = .printer
        case "history": router.tab = .history
        case "templates": router.open(.templates)
        case "note": router.open(.design(DesignRoute(design: .note(), autoEdit: true)))
        case "label": router.open(.design(DesignRoute(design: .label())))
        case "banner": router.open(.banner)
        case "draw": router.open(.draw)
        case "web": router.open(.web)
        case "photo":
            if let id = ImageStore.shared.save(sampleImage()) { router.open(.photo(id)) }
        case "pasted":
            let ids = [sampleImage(), sampleImage().withHorizontallyFlippedOrientation()].compactMap { ImageStore.shared.save($0) }
            router.open(.design(DesignRoute(design: .pastedImages(ids, style: .floydSteinberg))))
        case "document":
            if let url = samplePDF() { router.open(.document([url])) }
        case "printsheet":
            router.pendingPrintJob = TestPage.make(printerName: "P1-28F2", profile: PrinterCatalog.pocketPrinter, darkness: 3)
        case "battery":
            // Feeds a captured status reply so the battery badge can be checked without hardware.
            printer.settings.lastPrinterName = "P1-28F2"
            printer.handleNotification(Data([0x51, 0x78, 0xA3, 0x01, 0x03, 0x00, 0x00, 0x12, 0x27, 0x88, 0xFF]))
            router.pendingPrintJob = TestPage.make(printerName: "P1-28F2", profile: PrinterCatalog.pocketPrinter, darkness: 3)
        default:
            if route.hasPrefix("template:"), let template = Templates.all.first(where: { $0.id == route.dropFirst(9) }) {
                router.open(.design(DesignRoute(design: template.make())))
            }
        }
    }

    private static func sampleImage() -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemOrange.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 120, y: 160, width: 420, height: 420))
            UIColor.systemIndigo.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 600, y: 300, width: 380, height: 380))
            let text = NSAttributedString(string: "Hello!", attributes: [.font: UIFont.boldSystemFont(ofSize: 150), .foregroundColor: UIColor.black])
            text.draw(at: CGPoint(x: 360, y: 650))
        }
    }

    private static func samplePDF() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sample Ticket.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try? renderer.writePDF(to: url) { context in
            for page in 1...2 {
                context.beginPage()
                let title = NSAttributedString(string: "Boarding Pass \(page)", attributes: [.font: UIFont.boldSystemFont(ofSize: 40)])
                title.draw(at: CGPoint(x: 72, y: 90))
                let body = NSAttributedString(string: "Passenger: Alex Example\nFlight PP 123 · Gate 7\nSeat 14A · Boarding 18:40",
                                              attributes: [.font: UIFont.systemFont(ofSize: 24)])
                body.draw(in: CGRect(x: 72, y: 170, width: 460, height: 200))
                UIColor.black.setFill()
                UIRectFill(CGRect(x: 72, y: 400, width: 300, height: 8))
            }
        }
        return url
    }
}
#endif
