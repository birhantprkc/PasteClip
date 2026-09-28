import XCTest

final class ClipQueueListTests: XCTestCase {
    private func queue(_ items: [String], newestFirst: Bool = false) -> ClipQueueList<String> {
        var queue = ClipQueueList<String>()
        queue.pastesNewestFirst = newestFirst
        items.forEach { queue.append($0) }
        return queue
    }

    func testPastesInCopyOrderByDefault() {
        var list = queue(["a", "b", "c"])
        XCTAssertEqual(list.next?.item, "a")
        XCTAssertEqual(list.consumeNext()?.item, "a")
        XCTAssertEqual(list.consumeNext()?.item, "b")
        XCTAssertEqual(list.next?.item, "c")
    }

    func testNewestFirstPastesFromTheEnd() {
        var list = queue(["a", "b", "c"], newestFirst: true)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["c", "b", "a"])
        XCTAssertEqual(list.consumeNext()?.item, "c")
        XCTAssertEqual(list.next?.item, "b")
    }

    func testFlippingTheOrderChangesTheNextItem() {
        var list = queue(["a", "b"])
        list.pastesNewestFirst = true
        XCTAssertEqual(list.next?.item, "b")
        list.pastesNewestFirst = false
        XCTAssertEqual(list.next?.item, "a")
    }

    func testTheSameContentCanBeQueuedTwice() {
        let list = queue(["a", "a"])
        XCTAssertEqual(list.count, 2)
        XCTAssertNotEqual(list.entries[0].id, list.entries[1].id)
    }

    func testRemovingAnEntryKeepsTheRestInOrder() {
        var list = queue(["a", "b", "c"])
        list.remove(id: list.entries[1].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["a", "c"])
    }

    func testConsumingAnEmptyQueueReturnsNothing() {
        var list = queue([])
        XCTAssertNil(list.consumeNext())
        XCTAssertNil(list.next)
        XCTAssertTrue(list.isEmpty)
    }
}
