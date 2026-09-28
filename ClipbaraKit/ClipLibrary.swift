import CryptoKit
import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Content captured from the pasteboard, a PasteButton, or the share sheet.
struct CapturedClip: Sendable {
    enum Kind: Sendable {
        case text(String)
        case url(URL)
        case image(Data)
    }

    let kind: Kind
}

/// All writes to the clip store go through here so the Mac rules (pinned items survive
/// the history limit, deleting a clip removes its pinboard entries) stay in one place.
@MainActor
struct ClipLibrary {
    let context: ModelContext

    static let historyLimitKey = "historyLimit"
    static let defaultHistoryLimit = 500

    // MARK: - Capture

    @discardableResult
    func save(_ clip: CapturedClip) -> ClipboardItem? {
        guard let classified = classify(clip) else { return nil }
        let hash = SHA256.hash(data: classified.rawData)
            .map { String(format: "%02x", $0) }
            .joined()

        // Same content again: move the existing clip to the top instead of duplicating it.
        if let existing = existingClip(hash: hash, text: classified.type == .image ? nil : classified.text) {
            existing.copiedAt = Date()
            try? context.save()
            return existing
        }

        let item = ClipboardItem(
            contentType: classified.type,
            rawData: classified.rawData,
            textContent: classified.text,
            thumbnailData: classified.thumbnail,
            sourceAppName: nil,
            sourceAppBundleId: nil,
            contentHash: hash
        )
        context.insert(item)
        try? context.save()
        trimHistory()
        return item
    }

    /// Text is also matched by its text: a clip synced from the Mac may be the same copy
    /// saved from HTML or rich text, which hashes differently.
    private func existingClip(hash: String, text: String?) -> ClipboardItem? {
        let byHash = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.contentHash == hash })
        if let match = try? context.fetch(byHash).first { return match }
        guard let text else { return nil }
        let target: String? = text
        let byText = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.textContent == target })
        return ((try? context.fetch(byText)) ?? []).first { $0.contentType != .image && $0.contentType != .fileURL }
    }

    private struct Classified {
        let type: ContentType
        let rawData: Data
        let text: String?
        var thumbnail: Data? = nil
    }

    private func classify(_ clip: CapturedClip) -> Classified? {
        switch clip.kind {
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = text.data(using: .utf8) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains(where: \.isWhitespace),
               let url = URL(string: trimmed), url.scheme != nil, url.host() != nil {
                return Classified(type: .url, rawData: Data(trimmed.utf8), text: trimmed)
            }
            return Classified(type: .plainText, rawData: data, text: text)
        case .url(let url):
            if url.isFileURL {
                let string = url.absoluteString
                return Classified(type: .fileURL, rawData: Data(string.utf8), text: url.lastPathComponent)
            }
            let string = url.absoluteString
            return Classified(type: .url, rawData: Data(string.utf8), text: string)
        case .image(let data):
            guard let image = UIImage(data: data) else { return nil }
            let png = image.pngData() ?? data
            return Classified(type: .image, rawData: png, text: nil, thumbnail: Self.thumbnail(for: image))
        }
    }

    static func thumbnail(for image: UIImage, maxSide: CGFloat = 480) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxSide / size.width, maxSide / size.height, 1)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    /// Reads the general pasteboard directly. This shows the system paste prompt unless
    /// the person allowed pasting from other apps in Settings.
    static func readGeneralPasteboard() -> CapturedClip? {
        let pasteboard = UIPasteboard.general
        guard !PasteboardWatcher.isPrivate(pasteboard) else { return nil }
        if pasteboard.hasImages, let image = pasteboard.image, let data = image.pngData() {
            return CapturedClip(kind: .image(data))
        }
        if pasteboard.hasURLs, let url = pasteboard.url {
            return CapturedClip(kind: .url(url))
        }
        if pasteboard.hasStrings, let string = pasteboard.string {
            return CapturedClip(kind: .text(string))
        }
        return nil
    }

    // MARK: - Copy

    /// Copies without reordering, like pasting from the Mac panel.
    func copy(_ item: ClipboardItem, asPlainText: Bool = false) {
        ClipLibrary.writeToPasteboard(item, asPlainText: asPlainText)
    }

    static func writeToPasteboard(_ item: ClipboardItem, asPlainText: Bool = false) {
        let pasteboard = UIPasteboard.general
        let text = item.displayText
        switch item.contentType {
        case .image:
            if let image = item.fullImage() {
                pasteboard.image = image
            }
        case .url:
            if let url = item.linkURL {
                pasteboard.items = [[
                    UTType.url.identifier: url,
                    UTType.utf8PlainText.identifier: text,
                ]]
            } else {
                pasteboard.string = text
            }
        case .richText where !asPlainText:
            pasteboard.items = [[
                UTType.rtf.identifier: item.rawData,
                UTType.utf8PlainText.identifier: text,
            ]]
        case .html where !asPlainText:
            pasteboard.items = [[
                UTType.html.identifier: item.rawData,
                UTType.utf8PlainText.identifier: text,
            ]]
        default:
            pasteboard.string = text
        }
        PasteboardWatcher.markOwnChange()
    }

    // MARK: - Edit

    func rename(_ item: ClipboardItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.userTitle = trimmed.isEmpty ? nil : trimmed
        try? context.save()
    }

    func delete(_ items: [ClipboardItem]) {
        for item in items {
            let itemID = item.id
            let entries = FetchDescriptor<PinboardEntry>(predicate: #Predicate { $0.clipboardItem?.id == itemID })
            for entry in (try? context.fetch(entries)) ?? [] {
                context.delete(entry)
            }
            context.delete(item)
        }
        try? context.save()
    }

    /// Deletes history that is not on any pinboard.
    func clearHistory() {
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { !$0.isPinned })
        delete((try? context.fetch(descriptor)) ?? [])
    }

    func trimHistory() {
        let limit = ClipStore.defaults.object(forKey: Self.historyLimitKey) as? Int ?? Self.defaultHistoryLimit
        guard limit > 0 else { return }
        let countDescriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { !$0.isPinned })
        let count = (try? context.fetchCount(countDescriptor)) ?? 0
        guard count > limit else { return }
        var oldest = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.copiedAt, order: .forward)]
        )
        oldest.fetchLimit = count - limit
        delete((try? context.fetch(oldest)) ?? [])
    }

    // MARK: - Pinboards

    func isItem(_ item: ClipboardItem, in pinboard: Pinboard) -> Bool {
        pinboard.entries.contains { $0.clipboardItem?.id == item.id }
    }

    func add(_ items: [ClipboardItem], to pinboard: Pinboard) {
        var nextOrder = (pinboard.entries.map(\.displayOrder).max() ?? -1) + 1
        for item in items where !isItem(item, in: pinboard) {
            let entry = PinboardEntry(clipboardItem: item, pinboard: pinboard, displayOrder: nextOrder)
            context.insert(entry)
            item.isPinned = true
            nextOrder += 1
        }
        try? context.save()
    }

    func remove(_ items: [ClipboardItem], from pinboard: Pinboard) {
        let ids = Set(items.map(\.id))
        for entry in pinboard.entries where ids.contains(entry.clipboardItem?.id ?? UUID()) {
            context.delete(entry)
        }
        try? context.save()
        for item in items {
            refreshPinnedFlag(item)
        }
        try? context.save()
    }

    func toggle(_ item: ClipboardItem, in pinboard: Pinboard) {
        if isItem(item, in: pinboard) {
            remove([item], from: pinboard)
        } else {
            add([item], to: pinboard)
        }
    }

    private func refreshPinnedFlag(_ item: ClipboardItem) {
        let itemID = item.id
        let descriptor = FetchDescriptor<PinboardEntry>(predicate: #Predicate { $0.clipboardItem?.id == itemID })
        let remaining = (try? context.fetchCount(descriptor)) ?? 0
        item.isPinned = remaining > 0
    }

    @discardableResult
    func createPinboard(named name: String, existing: [Pinboard]) -> Pinboard {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? String(localized: "Pinboard") : trimmed
        let names = Set(existing.map(\.name))
        var candidate = base
        var index = 2
        while names.contains(candidate) {
            candidate = "\(base) \(index)"
            index += 1
        }
        let order = (existing.map(\.displayOrder).max() ?? -1) + 1
        let pinboard = Pinboard(name: candidate, displayOrder: order)
        context.insert(pinboard)
        try? context.save()
        return pinboard
    }

    func rename(_ pinboard: Pinboard, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pinboard.name = trimmed
        try? context.save()
    }

    func delete(_ pinboard: Pinboard) {
        let items = pinboard.entries.compactMap(\.clipboardItem)
        context.delete(pinboard)
        try? context.save()
        for item in items {
            refreshPinnedFlag(item)
        }
        try? context.save()
    }

    func reorder(_ pinboards: [Pinboard]) {
        for (index, pinboard) in pinboards.enumerated() {
            pinboard.displayOrder = index
        }
        try? context.save()
    }
}

/// Tracks pasteboard changes without reading contents, so no paste prompt appears.
enum PasteboardWatcher {
    private static let lastSeenKey = "lastSeenPasteboardChangeCount"

    static var hasUnseenContent: Bool {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != ClipStore.defaults.integer(forKey: lastSeenKey) else { return false }
        guard !isPrivate(pasteboard) else { return false }
        return pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages
    }

    /// Password managers mark what they copy as concealed or transient (the
    /// nspasteboard.org convention the Mac app also honors), and such copies can arrive
    /// here through Universal Clipboard. They are never saved automatically.
    static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    static func isPrivate(_ pasteboard: UIPasteboard) -> Bool {
        pasteboard.types.contains(where: privateTypes.contains)
    }

    static func markSeen() {
        ClipStore.defaults.set(UIPasteboard.general.changeCount, forKey: lastSeenKey)
    }

    static func markOwnChange() {
        markSeen()
    }
}
