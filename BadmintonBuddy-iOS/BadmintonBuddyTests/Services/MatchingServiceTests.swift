import XCTest
@testable import BadmintonBuddy

final class MatchingServiceTests: XCTestCase {

    private let center = Coordinate.beijing
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

    func testCandidatesMustShareAVenue() {
        let courts = Array(BadmintonCourt.curatedBeijing.prefix(2))
        let address = PostalAddress(street: "测试路1号", city: "朝阳区", region: "北京市", countryCode: "CN")
        var sameVenue = player("same-venue", level: 4, eastKm: 1, slots: [slot(19, 21)])
        sameVenue.venues = [courts[0]]
        var elsewhere = player("elsewhere", level: 4, eastKm: 1, slots: [slot(19, 21)])
        elsewhere.venues = [BadmintonCourt(id: "far", name: "远处球馆", location: courts[0].location.offsetBy(eastKm: 6, northKm: 6),
                                           address: address)]
        var annex = player("annex", level: 4, eastKm: 2, slots: [slot(19, 21)])
        // 别人加的“隔壁馆”，离我选的球馆 100 米：算同一处
        annex.venues = [BadmintonCourt(id: "annex", name: "隔壁馆", location: courts[1].location.offsetBy(eastKm: 0.1, northKm: 0),
                                       address: address)]
        let candidates = MatchingService.candidates(for: request(), pool: [sameVenue, elsewhere, annex])
        XCTAssertEqual(Set(candidates.map(\.id)), ["same-venue", "annex"])
        XCTAssertEqual(candidates.first { $0.id == "annex" }?.courtIds, [courts[1].id])
        let proposal = MatchingService.proposals(for: request(), pool: [annex]).first
        XCTAssertEqual(proposal?.court.id, courts[1].id, "只在双方都能去的球馆约")
    }

    func testDoublesUsesVenueEveryoneCanReach() {
        let courts = Array(BadmintonCourt.curatedBeijing.prefix(2))
        var a = player("a", level: 4, eastKm: 0.5, slots: [slot(19, 21)])
        a.venues = courts
        var b = player("b", level: 4, eastKm: 0.5, slots: [slot(19, 21)])
        b.venues = [courts[1]]
        let c = player("c", level: 4, eastKm: 0.5, slots: [slot(19, 21)])
        let proposal = MatchingService.proposals(for: request(mode: .doubles), pool: [a, b, c]).first
        XCTAssertEqual(proposal?.court.id, courts[1].id)
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
        let address = PostalAddress(street: "测试路1号", city: "朝阳区", region: "北京市", countryCode: "CN")
        let closed = BadmintonCourt(id: "closed", name: "闭馆", location: center, address: address,
                                    operatingHours: OperatingHours(openHour: 8, openMinute: 0, closeHour: 12, closeMinute: 0, daysOpen: Array(1...7)))
        let open = BadmintonCourt(id: "open", name: "营业", location: center.offsetBy(eastKm: 5, northKm: 0), address: address,
                                  operatingHours: .standard)
        request.courts = [closed, open]
        let court = MatchingService.bestCourt(for: request, locations: [center], slot: slot(19, 21))
        XCTAssertEqual(court?.id, "open")
    }

    func testUnknownHoursCountAsOpenButKnownClosedIsSkipped() {
        var request = request()
        let address = PostalAddress(street: "测试路1号", city: "朝阳区", region: "北京市", countryCode: "CN")
        let closed = BadmintonCourt(id: "closed", name: "闭馆", location: center, address: address,
                                    operatingHours: OperatingHours(openHour: 8, openMinute: 0, closeHour: 12, closeMinute: 0, daysOpen: Array(1...7)))
        let unknown = BadmintonCourt(id: "unknown", name: "未知", location: center.offsetBy(eastKm: 8, northKm: 0), address: address)
        request.courts = [closed, unknown]
        XCTAssertEqual(MatchingService.bestCourt(for: request, locations: [center], slot: slot(19, 21))?.id, "unknown")
    }
}
