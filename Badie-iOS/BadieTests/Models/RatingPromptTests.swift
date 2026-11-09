import XCTest
@testable import Badie

final class RatingPromptTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "RatingPromptTests")
        defaults.removePersistentDomain(forName: "RatingPromptTests")
    }

    func testOnlyAfterTwoGamesAndAGoodReview() {
        XCTAssertFalse(RatingPrompt.shouldAsk(totalGames: 1, positive: true, defaults: defaults))
        XCTAssertFalse(RatingPrompt.shouldAsk(totalGames: 5, positive: false, defaults: defaults))
        XCTAssertTrue(RatingPrompt.shouldAsk(totalGames: 2, positive: true, defaults: defaults))
    }

    func testAtMostOnceEvery120Days() {
        let now = Date()
        RatingPrompt.markAsked(now: now, defaults: defaults)
        XCTAssertFalse(RatingPrompt.shouldAsk(totalGames: 3, positive: true, now: now.addingTimeInterval(100 * 86_400), defaults: defaults))
        XCTAssertTrue(RatingPrompt.shouldAsk(totalGames: 3, positive: true, now: now.addingTimeInterval(121 * 86_400), defaults: defaults))
    }
}
