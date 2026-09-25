import XCTest

final class ReviewPromptPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func day(_ n: Double) -> TimeInterval { n * 24 * 60 * 60 }

    /// Starts from empty defaults each time, so one test can build several policies.
    private func policy(installedDaysAgo days: Double, pastes: Int, now: Date) -> ReviewPromptPolicy {
        defaults.removePersistentDomain(forName: suiteName)
        let policy = ReviewPromptPolicy(defaults: defaults)
        policy.noteLaunch(now: now.addingTimeInterval(-day(days)))
        for _ in 0..<pastes { policy.recordPaste() }
        return policy
    }

    func testNotEligibleWithoutALaunchDate() {
        let policy = ReviewPromptPolicy(defaults: defaults)
        for _ in 0..<50 { policy.recordPaste() }
        XCTAssertFalse(policy.isEligible(version: "1.3.3"))
    }

    func testFirstLaunchIsRecordedOnlyOnce() {
        let policy = ReviewPromptPolicy(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_000_000)
        policy.noteLaunch(now: first)
        policy.noteLaunch(now: first.addingTimeInterval(day(30)))
        XCTAssertEqual(policy.firstLaunchDate, first)
    }

    func testNeedsSevenDaysOfUse() {
        let now = Date()
        XCTAssertFalse(policy(installedDaysAgo: 6.9, pastes: 100, now: now).isEligible(now: now, version: "1.3.3"))
        XCTAssertTrue(policy(installedDaysAgo: 7, pastes: 100, now: now).isEligible(now: now, version: "1.3.3"))
    }

    func testNeedsTwentyPastes() {
        let now = Date()
        XCTAssertFalse(policy(installedDaysAgo: 30, pastes: 19, now: now).isEligible(now: now, version: "1.3.3"))
        XCTAssertTrue(policy(installedDaysAgo: 30, pastes: 20, now: now).isEligible(now: now, version: "1.3.3"))
    }

    func testAsksOncePerVersion() {
        let now = Date()
        let policy = policy(installedDaysAgo: 30, pastes: 40, now: now)
        policy.markPrompted(version: "1.3.3")
        XCTAssertFalse(policy.isEligible(now: now, version: "1.3.3"))
        XCTAssertTrue(policy.isEligible(now: now, version: "1.3.4"))
    }

    func testRecentPasteWindow() {
        let now = Date()
        XCTAssertFalse(ReviewPromptPolicy.isRecentPaste(nil, now: now))
        XCTAssertTrue(ReviewPromptPolicy.isRecentPaste(now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(ReviewPromptPolicy.isRecentPaste(now.addingTimeInterval(-6), now: now))
        XCTAssertFalse(ReviewPromptPolicy.isRecentPaste(now.addingTimeInterval(5), now: now))
    }
}
