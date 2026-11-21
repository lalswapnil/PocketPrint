import Foundation
import Observation
import UIKit

struct HistoryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let date: Date
    var title: String
    var kind: PrintKind
    var heightDots: Int
    var isTextMode: Bool
    var hasDesign: Bool

    var lengthMillimeters: Double { Double(heightDots) / PrinterCatalog.dotsPerMillimeter }
}

/// Locally stored record of printed jobs, so anything can be reprinted or edited later.
@MainActor
@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let thumbnails = NSCache<NSUUID, UIImage>()
    @ObservationIgnored private let limit = 200

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketPrint/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        load()
    }

    func add(_ job: PrintJob) {
        let entry = HistoryEntry(id: job.id, date: Date(), title: job.title, kind: job.kind, heightDots: job.bitmap.height,
                                 isTextMode: job.isTextMode, hasDesign: job.design != nil)
        guard !entries.contains(where: { $0.id == entry.id }) else {
            // Reprints move the entry to the top.
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                let existing = entries.remove(at: index)
                entries.insert(HistoryEntry(id: existing.id, date: Date(), title: existing.title, kind: existing.kind,
                                            heightDots: existing.heightDots, isTextMode: existing.isTextMode,
                                            hasDesign: existing.hasDesign), at: 0)
                save()
            }
            return
        }
        guard let png = job.bitmap.pngData() else { return }
        try? png.write(to: bitmapURL(entry.id), options: .atomic)
        if let design = job.design, let data = try? JSONEncoder().encode(design) {
            try? data.write(to: designURL(entry.id), options: .atomic)
        }
        entries.insert(entry, at: 0)
        while entries.count > limit, let last = entries.last {
            delete(last)
        }
        save()
    }

    func bitmap(for entry: HistoryEntry) -> MonoBitmap? {
        guard let data = try? Data(contentsOf: bitmapURL(entry.id)) else { return nil }
        return MonoBitmap(pngData: data)
    }

    func job(for entry: HistoryEntry) -> PrintJob? {
        guard let bitmap = bitmap(for: entry) else { return nil }
        var job = PrintJob(title: entry.title, kind: entry.kind, bitmap: bitmap, isTextMode: entry.isTextMode, design: design(for: entry))
        job.id = entry.id
        return job
    }

    func design(for entry: HistoryEntry) -> Design? {
        guard entry.hasDesign, let data = try? Data(contentsOf: designURL(entry.id)) else { return nil }
        return try? JSONDecoder().decode(Design.self, from: data)
    }

    func thumbnail(for entry: HistoryEntry) -> UIImage? {
        if let cached = thumbnails.object(forKey: entry.id as NSUUID) { return cached }
        guard let image = UIImage(contentsOfFile: bitmapURL(entry.id).path) else { return nil }
        thumbnails.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    func pngData(for entry: HistoryEntry) -> Data? {
        try? Data(contentsOf: bitmapURL(entry.id))
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        try? FileManager.default.removeItem(at: bitmapURL(entry.id))
        try? FileManager.default.removeItem(at: designURL(entry.id))
        thumbnails.removeObject(forKey: entry.id as NSUUID)
        save()
    }

    func deleteAll() {
        for entry in entries { delete(entry) }
    }

    /// Image IDs still referenced by saved designs (so the image store can drop the rest).
    func referencedImageIDs() -> Set<String> {
        var ids = Set<String>()
        for entry in entries where entry.hasDesign {
            if let design = design(for: entry) { ids.formUnion(design.imageIDs) }
        }
        return ids
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private func bitmapURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }
    private func designURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).design.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
