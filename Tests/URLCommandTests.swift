import XCTest

final class URLCommandTests: XCTestCase {
    private func command(_ string: String) -> URLCommand? {
        URL(string: string).flatMap(URLCommand.init(url:))
    }

    func testKnownCommands() {
        XCTAssertEqual(command("clipbara://open"), .open)
        XCTAssertEqual(command("clipbara://toggle"), .toggle)
        XCTAssertEqual(command("clipbara://queue"), .queue)
    }

    func testCaseAndFormVariants() {
        XCTAssertEqual(command("CLIPBARA://Open"), .open)
        XCTAssertEqual(command("clipbara:open"), .open)
        XCTAssertEqual(command("clipbara:///toggle"), .toggle)
    }

    func testUnknownOrForeignLinksAreIgnored() {
        XCTAssertNil(command("clipbara://delete-everything"))
        XCTAssertNil(command("clipbara://"))
        XCTAssertNil(command("https://open"))
    }
}
