import SwiftData
import XCTest

@MainActor
final class ClipUndoStackTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: ClipboardItem.self, Pinboard.self, PinboardEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func clip(_ text: String, copiedAt: Date) -> ClipboardItem {
        let item = ClipboardItem(contentType: .plainText, rawData: Data(text.utf8), textContent: text, contentHash: text)
        item.copiedAt = copiedAt
        context.insert(item)
        return item
    }

    private func pinboard(_ items: [ClipboardItem]) -> Pinboard {
        let board = Pinboard(name: "Board")
        context.insert(board)
        for (index, item) in items.enumerated() {
            context.insert(PinboardEntry(clipboardItem: item, pinboard: board, displayOrder: index))
        }
        try? context.save()
        return board
    }

    private func order(of board: Pinboard) -> [String] {
        board.entries.sorted { $0.displayOrder < $1.displayOrder }.compactMap { $0.clipboardItem?.textContent }
    }

    private func allClips() -> [ClipboardItem] {
        (try? context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]))) ?? []
    }

    func testDeletingAClipAndUndoingRestoresItAndItsPinboardPlace() {
        let a = clip("a", copiedAt: Date(timeIntervalSince1970: 3))
        let b = clip("b", copiedAt: Date(timeIntervalSince1970: 2))
        let c = clip("c", copiedAt: Date(timeIntervalSince1970: 1))
        let board = pinboard([a, b, c])
        let bID = b.id
        let stack = ClipUndoStack()

        stack.deleteClip(b, in: context)
        XCTAssertEqual(allClips().compactMap(\.textContent), ["a", "c"])
        XCTAssertEqual(order(of: board), ["a", "c"])
        XCTAssertEqual(board.entries.map(\.displayOrder).sorted(), [0, 1])

        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(allClips().compactMap(\.textContent), ["a", "b", "c"])
        XCTAssertEqual(allClips()[1].id, bID)
        XCTAssertEqual(order(of: board), ["a", "b", "c"])
    }

    func testRemovingFromAPinboardKeepsTheClipAndUndoPutsItBack() {
        let a = clip("a", copiedAt: Date(timeIntervalSince1970: 2))
        let b = clip("b", copiedAt: Date(timeIntervalSince1970: 1))
        let board = pinboard([a, b])
        let stack = ClipUndoStack()

        let entryA = board.entries.first { $0.clipboardItem?.id == a.id }!
        stack.removeEntry(entryA, in: context)
        XCTAssertEqual(order(of: board), ["b"])
        XCTAssertEqual(allClips().count, 2)

        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(order(of: board), ["a", "b"])
    }

    func testUndoRestoresTheMostRecentDeletionFirst() {
        let a = clip("a", copiedAt: Date(timeIntervalSince1970: 2))
        let b = clip("b", copiedAt: Date(timeIntervalSince1970: 1))
        try? context.save()
        let stack = ClipUndoStack()

        stack.deleteClip(a, in: context)
        stack.deleteClip(b, in: context)
        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(allClips().compactMap(\.textContent), ["b"])
        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(allClips().compactMap(\.textContent), ["a", "b"])
        XCTAssertFalse(stack.undo(in: context))
    }

    private func board(_ name: String, _ items: [ClipboardItem]) -> Pinboard {
        let board = Pinboard(name: name)
        context.insert(board)
        for (index, item) in items.enumerated() {
            context.insert(PinboardEntry(clipboardItem: item, pinboard: board, displayOrder: index))
        }
        try? context.save()
        return board
    }

    func testMovingToAnotherPinboardAndUndoing() {
        let a = clip("a", copiedAt: Date(timeIntervalSince1970: 3))
        let b = clip("b", copiedAt: Date(timeIntervalSince1970: 2))
        let c = clip("c", copiedAt: Date(timeIntervalSince1970: 1))
        let source = board("Source", [a, b])
        let destination = board("Destination", [c])
        let stack = ClipUndoStack()

        stack.moveEntry(source.entries.first { $0.clipboardItem?.id == a.id }!, to: destination, in: context)
        XCTAssertEqual(order(of: source), ["b"])
        XCTAssertEqual(order(of: destination), ["c", "a"])
        XCTAssertEqual(source.entries.map(\.displayOrder), [0])
        XCTAssertEqual(allClips().count, 3)

        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(order(of: source), ["a", "b"])
        XCTAssertEqual(order(of: destination), ["c"])
    }

    func testMovingIntoAPinboardThatHasTheClipOnlyRemovesItFromTheSource() {
        let a = clip("a", copiedAt: Date(timeIntervalSince1970: 1))
        let source = board("Source", [a])
        let destination = board("Destination", [a])
        let stack = ClipUndoStack()

        stack.moveEntry(source.entries[0], to: destination, in: context)
        XCTAssertEqual(order(of: source), [])
        XCTAssertEqual(order(of: destination), ["a"])

        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(order(of: source), ["a"])
        XCTAssertEqual(order(of: destination), ["a"])
    }

    func testMovingPersistsOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("move-\(UUID()).store")
        let schema = Schema([ClipboardItem.self, Pinboard.self, PinboardEntry.self])
        var disk: ModelContainer? = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        let ctx = disk!.mainContext
        let a = ClipboardItem(contentType: .plainText, rawData: Data("a".utf8), textContent: "a", contentHash: "a")
        ctx.insert(a)
        let source = Pinboard(name: "Source"); ctx.insert(source)
        let destination = Pinboard(name: "Destination"); ctx.insert(destination)
        ctx.insert(PinboardEntry(clipboardItem: a, pinboard: source, displayOrder: 0))
        try ctx.save()

        // Fetch the way the panel does: pinboards from a query, entries via the relationship.
        let boards = try ctx.fetch(FetchDescriptor<Pinboard>())
        let src = boards.first { $0.name == "Source" }!
        let dst = boards.first { $0.name == "Destination" }!
        ClipUndoStack().moveEntry(src.entries[0], to: dst, in: ctx)
        disk = nil

        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        let rows = try reopened.mainContext.fetch(FetchDescriptor<PinboardEntry>())
        XCTAssertEqual(rows.compactMap { $0.pinboard?.name }.sorted(), ["Destination"])
    }

    func testEditingTextAndUndoing() {
        let a = clip("before", copiedAt: Date(timeIntervalSince1970: 1))
        let board = board("Board", [a])
        let originalHash = a.contentHash
        let stack = ClipUndoStack()

        stack.editText(of: a, to: "after", in: context)
        XCTAssertEqual(a.textContent, "after")
        XCTAssertEqual(a.rawData, Data("after".utf8))
        XCTAssertNotEqual(a.contentHash, originalHash)
        XCTAssertEqual(order(of: board), ["after"])

        XCTAssertTrue(stack.undo(in: context))
        XCTAssertEqual(a.textContent, "before")
        XCTAssertEqual(a.rawData, Data("before".utf8))
        XCTAssertEqual(a.contentHash, originalHash)
    }
}
