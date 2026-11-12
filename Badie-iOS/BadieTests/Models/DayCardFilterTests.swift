import XCTest
@testable import Badie

/// 按天看人的筛选也用在附近的人的卡片上：时间按 TA 的空闲时间，项目按 TA 常打的（没填的都算），混双算双打
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

    func testTimesUseUsualTimesForNearby() {
        var filter = DayCardFilter()
        filter.times = [.morning]
        XCTAssertTrue(filter.matches(player(mode: nil), user: nil), "没填空闲时间的都算")
        var evenings = player(mode: nil)
        evenings.usualTimes = [RecurringTimeSlot(dayOfWeek: 3, startHour: 19, endHour: 21)]
        XCTAssertFalse(filter.matches(evenings, user: nil))
        filter.times = [.morning, .evening]
        XCTAssertTrue(filter.matches(evenings, user: nil))
        var weekend = player(mode: nil)
        weekend.usualTimes = [RecurringTimeSlot(dayOfWeek: 7, startHour: 10, endHour: 14)]
        filter.times = [.afternoon]
        XCTAssertTrue(filter.matches(weekend, user: nil), "10:00–14:00 也算下午")
    }
}
