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
}
