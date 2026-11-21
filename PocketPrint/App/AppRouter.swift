import Observation
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case create, history, printer
}

struct DesignRoute: Hashable {
    var design: Design
    /// Open the editor for the first block straight away (e.g. a new note starts typing).
    var autoEdit = false
}

enum CreateRoute: Hashable {
    case design(DesignRoute)
    case templates
    case photo(String)
    case banner
    case draw
    case document([URL])
    case web
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .create
    var createPath: [CreateRoute] = []
    var message: String?
    /// A finished job waiting to be shown in the print sheet.
    var pendingPrintJob: PrintJob?

    func open(_ route: CreateRoute, replacingStack: Bool = false) {
        tab = .create
        if replacingStack {
            createPath = [route]
        } else {
            createPath.append(route)
        }
    }

    func edit(_ design: Design) {
        var copy = design
        copy.id = UUID()
        open(.design(DesignRoute(design: copy)), replacingStack: true)
    }

    /// Files shared to the app ("Open in PocketPrint") or picked in the Files app.
    func handleIncoming(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .pdf) {
            guard let local = Self.copyToTemporary(url) else { return fail() }
            open(.document([local]), replacingStack: true)
        } else if type.conforms(to: .image) {
            guard let data = try? Data(contentsOf: url), let id = ImageStore.shared.save(data: data) else { return fail() }
            open(.photo(id), replacingStack: true)
        } else if type.conforms(to: .text), let text = try? String(contentsOf: url, encoding: .utf8) {
            let design = Design(title: url.deletingPathExtension().lastPathComponent,
                                blocks: [Block(.text(TextBlock(text: text, style: TextStyle(size: 26))))])
            open(.design(DesignRoute(design: design)), replacingStack: true)
        } else {
            fail()
        }
    }

    private func fail() {
        message = "PocketPrint can print photos, PDF documents and text files."
    }

    static func copyToTemporary(_ url: URL) -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
