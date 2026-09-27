import Foundation

/// Hand-off folder between the share extension and the app.
///
/// The extension never opens the SwiftData store: a second process writing the same
/// SQLite file would not show up in the app's live queries. It drops one file per shared
/// item here, and the app imports and deletes them when it becomes active.
enum ShareInbox {
    struct Entry: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case text, url, image
        }

        let kind: Kind
        let text: String?
        let imageFileName: String?
        let createdAt: Date

        func capturedClip() -> CapturedClip? {
            switch kind {
            case .text:
                return text.map { CapturedClip(kind: .text($0)) }
            case .url:
                return text.flatMap(URL.init(string:)).map { CapturedClip(kind: .url($0)) }
            case .image:
                guard let name = imageFileName, let folder = ShareInbox.folder,
                      let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
                return CapturedClip(kind: .image(data))
            }
        }
    }

    static var folder: URL? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ClipStore.appGroupID) else {
            return nil
        }
        let url = group.appendingPathComponent("ShareInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func add(text: String) throws {
        try write(Entry(kind: .text, text: text, imageFileName: nil, createdAt: Date()))
    }

    static func add(url: URL) throws {
        try write(Entry(kind: .url, text: url.absoluteString, imageFileName: nil, createdAt: Date()))
    }

    static func add(imageData: Data) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        let name = "\(UUID().uuidString).image"
        try imageData.write(to: folder.appendingPathComponent(name), options: .atomic)
        try write(Entry(kind: .image, text: nil, imageFileName: name, createdAt: Date()))
    }

    private static func write(_ entry: Entry) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(entry)
        let name = "\(Int(entry.createdAt.timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    /// Returns queued entries oldest first and removes them from disk.
    static func drain() -> [Entry] {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let jsonNames = names.filter { $0.hasSuffix(".json") }.sorted()
        var entries: [Entry] = []
        for name in jsonNames {
            let url = folder.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: data) {
                entries.append(entry)
            }
            try? FileManager.default.removeItem(at: url)
        }
        return entries
    }

    /// Deletes image payloads once their clips have been saved.
    static func removeImagePayloads(for entries: [Entry]) {
        guard let folder else { return }
        for name in entries.compactMap(\.imageFileName) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
