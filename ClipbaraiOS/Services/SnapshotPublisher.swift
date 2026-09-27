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
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let publisher = Unmanaged<SnapshotPublisher>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in publisher.importInbox() }
            },
            ShareInbox.changedNotification as CFString,
            nil,
            .deliverImmediately
        )
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
        ShareInbox.log.info("importing \(entries.count) shared items")
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
            let entries = pinboard.entries
                .sorted { $0.displayOrder < $1.displayOrder }
                .filter { $0.clipboardItem.map { KeyboardSnapshot.insertableTypes.contains($0.contentType) } ?? false }
            let items = entries.compactMap(\.clipboardItem)
            for item in items where clips[item.id] == nil {
                clips[item.id] = snapshotClip(item)
            }
            return KeyboardSnapshot.Board(
                id: pinboard.id,
                name: pinboard.name,
                colorIndex: PinboardPalette.index(for: pinboard, among: pinboards),
                clipIDs: items.map(\.id),
                entryIDs: entries.map(\.id)
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
