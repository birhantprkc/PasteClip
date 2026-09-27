import Foundation
import UIKit

/// A small, read-only copy of recent clips and pinboards for the keyboard extension.
///
/// The keyboard runs without Full Access by default. Without it the app group container
/// is read-only, which SQLite (and so SwiftData) cannot open, so the app writes this JSON
/// file instead. It also keeps the keyboard well under its memory limit.
struct KeyboardSnapshot: Codable, Sendable {
    struct Clip: Codable, Sendable, Identifiable, ClipPresentable {
        let id: UUID
        let contentTypeRaw: String
        let text: String
        let userTitle: String?
        let copiedAt: Date

        var contentType: ContentType { ContentType(rawValue: contentTypeRaw) ?? .unknown }
        var displayText: String { text }
        var headerTitle: String { ClipHeuristics.headerTitle(userTitle: userTitle, type: contentType, text: text) }
        var linkHost: String? { contentType == .url ? ClipHeuristics.host(of: text) : nil }
        var colorHex: String? { contentType == .color ? text : nil }
        var looksLikeCode: Bool { ClipHeuristics.looksLikeCode(text, type: contentType) }
        func thumbnailImage() -> UIImage? { nil }
    }

    struct Board: Codable, Sendable, Identifiable {
        let id: UUID
        var name: String
        var colorIndex: Int
        var clipIDs: [UUID]
        /// Pinboard entry IDs, parallel to `clipIDs`, so a synced entry deletion can be
        /// matched. Optional for snapshots written before it existed.
        var entryIDs: [UUID]?
    }

    var generatedAt: Date
    /// Every clip referenced below: recent history plus anything on a pinboard.
    var clips: [Clip]
    /// Recent history, newest first.
    var historyIDs: [UUID]
    var boards: [Board]

    static let empty = KeyboardSnapshot(generatedAt: .distantPast, clips: [], historyIDs: [], boards: [])

    /// Keyboard-insertable kinds only. Images need Full Access to reach the pasteboard,
    /// and `insertText` cannot insert them at all.
    static let insertableTypes: Set<ContentType> = [.plainText, .richText, .html, .url, .color, .fileURL, .unknown]
    static let recentLimit = 200
    static let textLimit = 20_000

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ClipStore.appGroupID)?
            .appendingPathComponent("keyboard-snapshot.json")
    }

    static func load() -> KeyboardSnapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(KeyboardSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func write() throws {
        guard let url = Self.fileURL else { return }
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clips(in boardID: UUID?) -> [Clip] {
        let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let boardID else { return historyIDs.compactMap { byID[$0] } }
        guard let board = boards.first(where: { $0.id == boardID }) else { return [] }
        return board.clipIDs.compactMap { byID[$0] }
    }
}

// MARK: - Live changes from iCloud (keyboard with Full Access)

/// Changes the keyboard fetched from iCloud since the app's last check.
struct KeyboardDelta: Sendable {
    struct Entry: Sendable {
        let id: UUID
        let clipID: UUID
        let pinboardID: UUID
        let order: Int
    }

    struct Pinboard: Sendable {
        let id: UUID
        let name: String
        let createdAt: Date
    }

    var clips: [KeyboardSnapshot.Clip] = []
    var pinboards: [Pinboard] = []
    var entries: [Entry] = []
    var deletedClipIDs: Set<UUID> = []
    var deletedPinboardIDs: Set<UUID> = []
    var deletedEntryIDs: Set<UUID> = []

    var isEmpty: Bool {
        clips.isEmpty && pinboards.isEmpty && entries.isEmpty
            && deletedClipIDs.isEmpty && deletedPinboardIDs.isEmpty && deletedEntryIDs.isEmpty
    }
}

extension KeyboardSnapshot {
    /// Applies fetched changes on top of the app's snapshot. Applying the same change
    /// twice gives the same result, so overlapping fetches are harmless.
    func merged(with delta: KeyboardDelta) -> KeyboardSnapshot {
        guard !delta.isEmpty else { return self }
        var byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for clip in delta.clips { byID[clip.id] = clip }
        for id in delta.deletedClipIDs { byID.removeValue(forKey: id) }

        // History: everything known, newest first, capped like the app's snapshot.
        let pinnedIDs = Set(boards.flatMap(\.clipIDs)).union(delta.entries.map(\.clipID))
        var history = Set(historyIDs).union(delta.clips.map(\.id))
        history.subtract(delta.deletedClipIDs)
        let orderedHistory = history
            .compactMap { byID[$0] }
            .sorted { $0.copiedAt > $1.copiedAt }
            .prefix(Self.recentLimit)
            .map(\.id)

        var boards = self.boards.filter { !delta.deletedPinboardIDs.contains($0.id) }
        for pinboard in delta.pinboards {
            if let index = boards.firstIndex(where: { $0.id == pinboard.id }) {
                boards[index].name = pinboard.name
            } else {
                boards.append(Board(id: pinboard.id, name: pinboard.name, colorIndex: boards.count, clipIDs: [], entryIDs: []))
            }
        }
        for index in boards.indices {
            var pairs = zip(boards[index].entryIDs ?? Array(repeating: UUID(), count: boards[index].clipIDs.count), boards[index].clipIDs)
                .map { (entry: $0, clip: $1) }
            pairs.removeAll { delta.deletedEntryIDs.contains($0.entry) || delta.deletedClipIDs.contains($0.clip) }
            for entry in delta.entries where entry.pinboardID == boards[index].id && !pairs.contains(where: { $0.entry == entry.id }) {
                pairs.append((entry: entry.id, clip: entry.clipID))
            }
            boards[index].clipIDs = pairs.map(\.clip)
            boards[index].entryIDs = pairs.map(\.entry)
        }

        let keep = Set(orderedHistory).union(boards.flatMap(\.clipIDs)).union(pinnedIDs)
        return KeyboardSnapshot(
            generatedAt: Date(),
            clips: byID.values.filter { keep.contains($0.id) },
            historyIDs: Array(orderedHistory),
            boards: boards
        )
    }
}
