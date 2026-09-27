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
        let name: String
        let colorIndex: Int
        let clipIDs: [UUID]
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
