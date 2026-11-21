import UIKit
import UniformTypeIdentifiers

/// What the clipboard holds, found with type queries only (iOS doesn't ask the user for these).
enum ClipboardContent: Equatable {
    case images, document, text, nothing

    static var current: ClipboardContent {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasImages { return .images }
        if pasteboard.contains(pasteboardTypes: [UTType.pdf.identifier]) { return .document }
        if pasteboard.hasStrings || pasteboard.hasURLs { return .text }
        return .nothing
    }
}

/// Something the user pasted, ready to open in an editor.
enum PastedContent: Equatable {
    /// Image store identifiers, in clipboard order.
    case images([String])
    case document(URL)
    case text(String)
}

enum ClipboardReader {
    /// Pictures, PDF documents, text and links.
    static let supportedTypes: [UTType] = [.image, .pdf, .plainText, .url]
    static let maxImages = 12
    static let maxTextLength = 10_000

    static let howToCopy = "Copy a picture or some text in another app first — for example, touch and hold a photo and choose Copy."
    static let notAllowed = "PocketPrint wasn't allowed to paste. Tap Allow Paste when asked, or choose Allow in Settings › Apps › PocketPrint › Paste from Other Apps."
    static let unreadable = "What you copied couldn't be pasted. Try copying it again."

    /// Loads pictures first, then a PDF, then text. Returns nil when nothing usable was pasted.
    static func load(_ providers: [NSItemProvider], includeDocuments: Bool = true,
                     store: ImageStore = .shared) async -> PastedContent? {
        let imageProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        if !imageProviders.isEmpty {
            var ids: [String] = []
            for provider in imageProviders.prefix(maxImages) {
                if let id = await saveImage(from: provider, to: store) { ids.append(id) }
            }
            // Pictures that fail to load shouldn't fall back to, say, the link that came with them.
            return ids.isEmpty ? nil : .images(ids)
        }

        if includeDocuments,
           let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }),
           let data = await loadData(from: provider, type: .pdf),
           let url = writeTemporaryPDF(data, suggestedName: provider.suggestedName) {
            return .document(url)
        }

        var texts: [String] = []
        for provider in providers {
            if let text = await loadText(from: provider) {
                texts.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        var text = texts.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        if text.count > maxTextLength {
            text = String(text.prefix(maxTextLength)) + "…"
        }
        return .text(text)
    }

    private static func saveImage(from provider: NSItemProvider, to store: ImageStore) async -> String? {
        if let data = await loadData(from: provider, type: .image),
           let id = await Task.detached(priority: .userInitiated, operation: { store.save(data: data) }).value {
            return id
        }
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        let image: UIImage? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        guard let image else { return nil }
        return await Task.detached(priority: .userInitiated) { store.save(image) }.value
    }

    /// Loads the first registered representation that conforms to `type` (e.g. PNG or HEIC for `.image`).
    private static func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        let identifier = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: type) == true } ?? type.identifier
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: NSString.self) {
            let string: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    continuation.resume(returning: (object as? NSString) as String?)
                }
            }
            if let string, !string.hasPrefix("file://"),
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
        }
        if provider.canLoadObject(ofClass: NSURL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    continuation.resume(returning: (object as? NSURL) as URL?)
                }
            }
            if let url, !url.isFileURL { return url.absoluteString }
        }
        return nil
    }

    /// Writes into a fresh folder so the file keeps a readable name, used as the print's title.
    private static func writeTemporaryPDF(_ data: Data, suggestedName: String?) -> URL? {
        var name = (suggestedName ?? "").components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined()
        name = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Pasted Document" }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("pdf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
