import XCTest
@testable import BadmintonBuddy

final class MatchingServiceTests: XCTestCase {

    private let center = Coordinate.fallbackCenter
    private lazy var tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

    private func player(_ id: String, level: Int, eastKm: Double, slots: [TimeSlot], evaluations: Int = 10) -> PlayerAvailability {
        let location = center.offsetBy(eastKm: eastKm, northKm: 0)
        var user = User(id: id, nickname: id, phone: "", selfReportedLevel: level, location: location)
        user.reputation = ReputationScore(evaluationCount: evaluations, peerLevelAverage: Double(level), averageSkillDeviation: 0.2,
                                          punctualityPercentage: 95, averageCharacterRating: 4.6)
        return PlayerAvailability(user: user, location: location, slots: slots)
    }

    private func slot(_ start: Int, _ end: Int) -> TimeSlot {
        TimeSlot.on(tomorrow, startHour: start, endHour: end)!
    }

    private func request(mode: GameMode = .singles, tolerance: Int = 1, radius: Double = 10, excluded: Set<String> = []) -> MatchRequest {
        MatchRequest(
            mode: mode, slot: slot(19, 21), courts: Array(BadmintonCourt.curatedBeijing.prefix(2)),
            skillTolerance: tolerance, userId: "me", userLevel: 4, userLocation: center,
            radiusKm: radius, excludedUserIds: excluded
        )
    }

    func testFiltersByRadiusSkillAndTime() {
        let pool = [
            player("near-same", level: 4, eastKm: 1, slots: [slot(19, 22)]),
            player("too-far", level: 4, eastKm: 30, slots: [slot(19, 22)]),
            player("too-strong", level: 7, eastKm: 1, slots: [slot(19, 22)]),
            player("no-time", level: 4, eastKm: 1, slots: [slot(8, 10)]),
            player("me", level: 4, eastKm: 0, slots: [slot(19, 22)])
        ]
        let ids = MatchingService.candidates(for: request(), pool: pool).map(\.id)
        XCTAssertEqual(ids, ["near-same"])
    }

    func testOrdersBySkillDifferenceThenDistance() {
        let pool = [
            player("diff1-near", level: 5, eastKm: 0.5, slots: [slot(19, 21)]),
            player("same-far", level: 4, eastKm: 8, slots: [slot(19, 21)]),
            player("same-near", level: 4, eastKm: 2, slots: [slot(19, 21)])
        ]
        let ids = MatchingService.candidates(for: request(), pool: pool).map(\.id)
        XCTAssertEqual(ids, ["same-near", "same-far", "diff1-near"])
    }

    func testExcludedUsersAreSkipped() {
        let pool = [player("blocked", level: 4, eastKm: 1, slots: [slot(19, 21)])]
        XCTAssertTrue(MatchingService.candidates(for: request(excluded: ["blocked"]), pool: pool).isEmpty)
    }

    func testSinglesProposalUsesOverlapAndCost() {
        let pool = [player("a", level: 4, eastKm: 1, slots: [slot(20, 23)])]
        let proposals = MatchingService.proposals(for: request(), pool: pool)
        XCTAssertEqual(proposals.count, 1)
        let proposal = proposals[0]
        XCTAssertEqual(proposal.commonOverlap.startTime, slot(20, 21).startTime)
        XCTAssertEqual(proposal.slot.duration, 3600)
        XCTAssertEqual(proposal.teams, [["me"], ["a"]])
        XCTAssertEqual(proposal.cost.players, 2)
        XCTAssertTrue((35...99).contains(proposal.compatibility))
    }

    func testDoublesNeedsThreeWithCommonOverlap() {
        let pool = [
            player("a", level: 5, eastKm: 1, slots: [slot(19, 21)]),
            player("b", level: 3, eastKm: 2, slots: [slot(19, 21)]),
            player("c", level: 4, eastKm: 3, slots: [slot(19, 21)]),
            player("d", level: 4, eastKm: 1, slots: [slot(8, 10)])
        ]
        let proposals = MatchingService.proposals(for: request(mode: .doubles), pool: pool)
        XCTAssertFalse(proposals.isEmpty)
        let first = proposals[0]
        XCTAssertEqual(Set(first.others.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(first.teams.count, 2)
        XCTAssertEqual(first.teams.flatMap { $0 }.count, 4)
    }

    func testBalancedTeams() {
        let teams = MatchingService.balancedTeams(players: [(id: "a", level: 7), (id: "b", level: 2), (id: "c", level: 5), (id: "d", level: 4)])
        // 7+2 vs 5+4
        XCTAssertEqual(teams, [["a", "b"], ["c", "d"]])
    }

    func testSuggestionsOnlyIncludeOptionsThatWork() {
        let pool = [player("strong", level: 6, eastKm: 1, slots: [slot(19, 21)])]
        XCTAssertTrue(MatchingService.proposals(for: request(tolerance: 1), pool: pool).isEmpty)
        let suggestions = MatchingService.suggestions(for: request(tolerance: 1), pool: pool)
        XCTAssertEqual(suggestions.first, .widenSkill(2))
        XCTAssertFalse(suggestions.contains(.widenTime(hours: 1)), "放宽时间并不能找到人，不应建议")
    }

    func testBestCourtPrefersOpenCourt() {
        var request = request()
        let closed = BadmintonCourt(id: "closed", name: "闭馆", location: center, address: "",
                                    operatingHours: OperatingHours(openHour: 8, openMinute: 0, closeHour: 12, closeMinute: 0, daysOpen: Array(1...7)))
        let open = BadmintonCourt(id: "open", name: "营业", location: center.offsetBy(eastKm: 5, northKm: 0), address: "")
        request.courts = [closed, open]
        let court = MatchingService.bestCourt(for: request, locations: [center], slot: slot(19, 21))
        XCTAssertEqual(court?.id, "open")
    }
}
