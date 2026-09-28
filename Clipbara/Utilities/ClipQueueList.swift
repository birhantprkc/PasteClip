import Foundation

/// The ordered contents of a Clip Queue, kept free of AppKit so the ordering
/// rules can be tested on their own.
///
/// Items are stored in the order they were copied. By default the oldest is
/// pasted first; `pastesNewestFirst` flips that.
struct ClipQueueList<Item> {
    struct Entry: Identifiable {
        let id: UUID
        let item: Item
    }

    private(set) var entries: [Entry] = []
    var pastesNewestFirst = false

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// The entry the next ⌘V will paste.
    var next: Entry? {
        pastesNewestFirst ? entries.last : entries.first
    }

    /// Entries in the order they will be pasted.
    var pasteOrder: [Entry] {
        pastesNewestFirst ? entries.reversed() : entries
    }

    /// Adds a copy. The same content copied twice is two entries, since the
    /// user may want to paste it twice.
    @discardableResult
    mutating func append(_ item: Item) -> Entry {
        let entry = Entry(id: UUID(), item: item)
        entries.append(entry)
        return entry
    }

    /// Removes and returns the entry that was just pasted.
    @discardableResult
    mutating func consumeNext() -> Entry? {
        guard !entries.isEmpty else { return nil }
        return pastesNewestFirst ? entries.removeLast() : entries.removeFirst()
    }

    mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
