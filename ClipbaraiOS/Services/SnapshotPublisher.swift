import Foundation
import SwiftData

/// Keeps the keyboard's JSON snapshot in step with the store and pulls in clips that
/// the share extension dropped into the inbox.
@MainActor
final class SnapshotPublisher {
    private let container: ModelContainer
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        importInbox()
        publish()
    }

    /// Call when the app becomes active.
    func refresh() {
        importInbox()
        publish()
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    func importInbox() {
        let entries = ShareInbox.drain()
        guard !entries.isEmpty else { return }
        let library = ClipLibrary(context: container.mainContext)
        for entry in entries {
            if let clip = entry.capturedClip() {
                library.save(clip)
            }
        }
        ShareInbox.removeImagePayloads(for: entries)
    }

    func publish() {
        let context = container.mainContext
        var recent = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.copiedAt, order: .reverse)])
        recent.fetchLimit = KeyboardSnapshot.recentLimit * 2
        let recentItems = ((try? context.fetch(recent)) ?? [])
            .filter { KeyboardSnapshot.insertableTypes.contains($0.contentType) }
            .prefix(KeyboardSnapshot.recentLimit)
        let pinboards = (try? context.fetch(FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.displayOrder)]))) ?? []

        var clips: [UUID: KeyboardSnapshot.Clip] = [:]
        func snapshotClip(_ item: ClipboardItem) -> KeyboardSnapshot.Clip {
            KeyboardSnapshot.Clip(
                id: item.id,
                contentTypeRaw: item.contentTypeRaw,
                text: String(item.displayText.prefix(KeyboardSnapshot.textLimit)),
                userTitle: item.userTitle,
                copiedAt: item.copiedAt
            )
        }

        for item in recentItems {
            clips[item.id] = snapshotClip(item)
        }
        let boards = pinboards.map { pinboard in
            let items = pinboard.entries
                .sorted { $0.displayOrder < $1.displayOrder }
                .compactMap(\.clipboardItem)
                .filter { KeyboardSnapshot.insertableTypes.contains($0.contentType) }
            for item in items where clips[item.id] == nil {
                clips[item.id] = snapshotClip(item)
            }
            return KeyboardSnapshot.Board(
                id: pinboard.id,
                name: pinboard.name,
                colorIndex: PinboardPalette.index(for: pinboard, among: pinboards),
                clipIDs: items.map(\.id)
            )
        }

        let snapshot = KeyboardSnapshot(
            generatedAt: Date(),
            clips: Array(clips.values),
            historyIDs: recentItems.map(\.id),
            boards: boards
        )
        try? snapshot.write()
    }
}
