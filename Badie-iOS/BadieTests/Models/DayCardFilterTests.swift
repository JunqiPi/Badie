import XCTest
@testable import Badie

/// 按天看人的筛选也用在“常在附近”的卡片上：不看时间，项目按 TA 常打的（没填的都算），混双算双打
final class DayCardFilterTests: XCTestCase {

    private func player(mode: GameMode?, venues: [String] = ["v1"], noShows: Int = 0) -> MockBackend.NearbyPlayer {
        MockBackend.NearbyPlayer(userId: "u1", recentNoShows: noShows, preferredMode: mode,
                                 venues: venues.map { MockBackend.DayCandidate.Venue(id: $0, name: $0) }, sharedVenues: 0)
    }

    func testEventMatchesPreferredMode() {
        var filter = DayCardFilter()
        filter.event = .singles
        XCTAssertTrue(filter.matches(player(mode: .singles), user: nil))
        XCTAssertFalse(filter.matches(player(mode: .doubles), user: nil))
        XCTAssertTrue(filter.matches(player(mode: nil), user: nil), "没填常打项目的都算")
        filter.event = .mixed
        XCTAssertTrue(filter.matches(player(mode: .doubles), user: nil), "混双算双打")
        XCTAssertFalse(filter.matches(player(mode: .singles), user: nil))
    }

    func testVenuesLevelGenderAndReliability() {
        var filter = DayCardFilter()
        filter.venueIds = ["v2"]
        XCTAssertFalse(filter.matches(player(mode: nil, venues: ["v1"]), user: nil))
        XCTAssertTrue(filter.matches(player(mode: nil, venues: ["v1", "v2"]), user: nil))

        filter = DayCardFilter()
        filter.minLevel = 5
        let user = User(id: "u1", nickname: "测试", phone: "", gender: .female, selfReportedLevel: 4)
        XCTAssertFalse(filter.matches(player(mode: nil), user: user))
        filter.minLevel = 1
        filter.gender = .male
        XCTAssertFalse(filter.matches(player(mode: nil), user: user))

        filter = DayCardFilter()
        filter.reliableOnly = true
        XCTAssertFalse(filter.matches(player(mode: nil, noShows: 1), user: nil))
        XCTAssertTrue(filter.matches(player(mode: nil), user: nil))
    }

    func testTimesAreIgnoredForNearby() {
        var filter = DayCardFilter()
        filter.times = [.morning]
        XCTAssertTrue(filter.matches(player(mode: nil), user: nil))
    }
}
