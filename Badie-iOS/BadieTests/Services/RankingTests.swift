import XCTest
@testable import Badie

/// 赛果双方确认、月度胜率、场馆榜 / 周榜计分与约战规则
@MainActor
final class RankingTests: XCTestCase {

    private var backend: MockBackend!

    override func setUp() async throws {
        try await super.setUp()
        backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false
    }

    private func signUp(level: Int = 4) -> User {
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: level,
                              location: Coordinate.fallbackCenter, seedsDemoContent: false)
    }

    private func finishedGame(id: String, players: [String], hoursAgo: Double = 3) -> Game {
        let start = Date().addingTimeInterval(-hoursAgo * 3600)
        let slot = TimeSlot(date: start, startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let court = BadmintonCourt.curatedUS[0]
        return Game(
            id: id, mode: .singles, court: court, slot: slot, playerIds: players, teams: players.map { [$0] },
            hostId: players[0], origin: .quickMatch, status: .confirmed, createdAt: Date(), checkIns: [:],
            paidPlayerIds: [], cost: CostSplit.estimate(court: court, slot: slot, mode: .singles), result: nil,
            cancelledBy: nil, cancelledLate: false, reminderEnabled: false
        )
    }

    private func record(_ id: String, _ me: String, vs opponent: String, won: Bool, at date: Date,
                        venue: String = "v1", ratings: [String: Double] = [:]) -> MatchRecord {
        MatchRecord(id: id, date: date, venueId: venue, countryCode: "US", mode: .singles,
                    teams: [[me], [opponent]], winningTeam: won ? 0 : 1, ratings: ratings)
    }

    // MARK: 赛果确认

    func testResultCountsOnlyWhenBothSidesAgree() async throws {
        let me = signUp()
        backend.db.games["g"] = finishedGame(id: "g", players: [me.id, "bot-0"])
        try await backend.completeGame(id: "g", didWin: true, score: "21:15")
        XCTAssertEqual(backend.db.games["g"]?.resultStatus(), .awaiting)
        XCTAssertTrue(backend.db.matchRecords.isEmpty)

        backend.addResultReport(ResultReport(reporterId: "bot-0", winningTeam: 0, score: "21:15", reportedAt: Date()), to: "g")
        XCTAssertEqual(backend.db.games["g"]?.resultStatus(), .verified(winningTeam: 0))
        XCTAssertEqual(backend.db.matchRecords.map(\.id), ["g"])
    }

    func testConflictingReportsAreDisputedAndNotCounted() async throws {
        let me = signUp()
        backend.db.games["g"] = finishedGame(id: "g", players: [me.id, "bot-0"])
        try await backend.completeGame(id: "g", didWin: true, score: "21:15")
        backend.addResultReport(ResultReport(reporterId: "bot-0", winningTeam: 1, score: "21:19", reportedAt: Date()), to: "g")
        XCTAssertEqual(backend.db.games["g"]?.resultStatus(), .disputed)
        XCTAssertTrue(backend.db.matchRecords.isEmpty)
        XCTAssertEqual(backend.currentUser?.wins, 0)
    }

    func testUnconfirmedResultExpiresInsteadOfAutoConfirming() {
        var game = finishedGame(id: "g", players: ["a", "b"], hoursAgo: 24 * 8)
        game.resultReports = [ResultReport(reporterId: "a", winningTeam: 0, score: "", reportedAt: Date())]
        XCTAssertEqual(game.resultStatus(), .expired)
    }

    func testFriendlyGameNeverCounts() {
        var game = finishedGame(id: "g", players: ["a", "b"])
        game.resultReports = ["a", "b"].map { ResultReport(reporterId: $0, winningTeam: nil, score: "", reportedAt: Date()) }
        XCTAssertEqual(game.resultStatus(), .friendly)
    }

    // MARK: 胜率

    func testMonthlyWinRateCapsSameOpponentAndNeedsFiveGames() {
        let month = Rankings.month(containing: Date())
        let day = month.start.addingTimeInterval(3600)
        var records = (0..<5).map { record("x\($0)", "me", vs: "friend", won: true, at: day.addingTimeInterval(Double($0) * 60)) }
        var rate = Rankings.winRate(for: "me", records: records, month: month)
        XCTAssertEqual(rate.games, Rankings.monthlySameOpponentCap, "同一对手每月最多计入 3 场")
        XCTAssertFalse(rate.isPublic)

        records += [record("y1", "me", vs: "b", won: false, at: day), record("y2", "me", vs: "c", won: true, at: day)]
        rate = Rankings.winRate(for: "me", records: records, month: month)
        XCTAssertEqual(rate.games, 5)
        XCTAssertEqual(rate.wins, 4)
        XCTAssertEqual(rate.opponents, 3)
        XCTAssertTrue(rate.isPublic)
        XCTAssertEqual(rate.percentage, 80)
    }

    // MARK: 周榜积分

    func testWeeklyPointsRewardStrongerOpponentsAndDecayOnRepeats() {
        let week = Rankings.week(containing: Date())
        let t = week.start.addingTimeInterval(3600)
        let strong = record("s", "me", vs: "pro", won: true, at: t, ratings: ["me": 4, "pro": 5])
        let weak = record("w", "me", vs: "rookie", won: true, at: t, ratings: ["me": 4, "rookie": 2])
        XCTAssertEqual(Rankings.points(for: strong, userId: "me", meetingIndex: 0), 22.5, accuracy: 0.01)
        XCTAssertEqual(Rankings.points(for: weak, userId: "me", meetingIndex: 0), 7.5, accuracy: 0.01)
        XCTAssertEqual(Rankings.points(for: strong, userId: "me", meetingIndex: 1), 11.25, accuracy: 0.01)
        XCTAssertEqual(Rankings.points(for: strong, userId: "me", meetingIndex: 2), 0)
    }

    func testWeeklyBoardRequiresVarietyAndRespectsEligibility() {
        let week = Rankings.week(containing: Date())
        let t = week.start.addingTimeInterval(3600)
        let farmer = (0..<6).map { record("f\($0)", "farmer", vs: "alt", won: true, at: t) }
        let regular = [record("r1", "reg", vs: "a", won: true, at: t), record("r2", "reg", vs: "b", won: false, at: t),
                       record("r3", "reg", vs: "c", won: true, at: t)]
        let board = Rankings.weeklyBoard(records: farmer + regular, week: week) { $0 != "hidden" }
        XCTAssertEqual(board.map(\.userId), ["reg"], "只和一个人反复打的不上榜")
        XCTAssertEqual(board.first?.score, 40)
    }

    func testVenueBoardRanksByConfirmedGamesAtVenue() {
        let month = Rankings.month(containing: Date())
        let t = month.start.addingTimeInterval(3600)
        let regular = ["a", "b", "c", "d"].enumerated().map {
            record("r\($0.offset)", "regular", vs: $0.element, won: false, at: t.addingTimeInterval(Double($0.offset) * 86400))
        }
        let visitor = [record("v1", "visitor", vs: "a", won: true, at: t), record("v2", "visitor", vs: "b", won: true, at: t),
                       record("v3", "visitor", vs: "c", won: true, at: t)]
        let elsewhere = (0..<5).map { record("e\($0)", "regular", vs: "z\($0)", won: true, at: t, venue: "v2") }
        let board = Rankings.venueBoard(venueId: "v1", records: regular + visitor + elsewhere, month: month) {
            ["regular", "visitor"].contains($0)
        }
        XCTAssertEqual(board.map(\.userId), ["regular", "visitor"], "比的是来得多，不是赢得多")
        XCTAssertEqual(board.first?.score, 4)
    }

    // MARK: 约战

    func testChallengePolicyAndLimits() async throws {
        let me = signUp(level: 4)
        let similar = try XCTUnwrap(backend.db.users.values.first {
            backend.isBot($0.id) && abs($0.displayTier.rating - me.displayTier.rating) <= 1
        })
        let far = try XCTUnwrap(backend.db.users.values.first {
            backend.isBot($0.id) && abs($0.displayTier.rating - me.displayTier.rating) > 1.5
        })
        XCTAssertEqual(backend.challengeAvailability(for: far.id), .levelOutOfRange)
        XCTAssertEqual(backend.challengeAvailability(for: similar.id), .available)

        backend.db.users[similar.id]?.privacy.challengePolicy = .nobody
        XCTAssertEqual(backend.challengeAvailability(for: similar.id), .notAccepting)
        backend.db.users[similar.id]?.privacy.challengePolicy = .everyone

        let slot = TimeSlot.suggestedDefault()
        let challenge = try await backend.sendChallenge(to: similar.id, court: BadmintonCourt.curatedUS[0], slot: slot, message: "来一场")
        XCTAssertEqual(backend.challengeAvailability(for: similar.id), .alreadyPending)

        do {
            try await backend.sendChallenge(to: far.id, court: BadmintonCourt.curatedUS[0], slot: slot, message: "加我微信")
            XCTFail("留言不能带联系方式")
        } catch {
            XCTAssertNotNil(error as? BackendError)
        }

        // 对方拒绝：发起人只看到未成行，并进入冷却
        backend.currentUserIdOverride(similar.id)
        _ = try await backend.respondToChallenge(id: challenge.id, accept: false)
        backend.currentUserIdOverride(me.id)
        if case .cooldown = backend.challengeAvailability(for: similar.id) {} else {
            XCTFail("被拒后 7 天内不能再挑战同一个人")
        }
    }

    func testAcceptedChallengeCreatesSinglesGame() async throws {
        let me = signUp()
        let rival = try XCTUnwrap(backend.db.users.values.first { backend.isBot($0.id) })
        backend.db.users[rival.id]?.privacy.challengePolicy = .everyone
        let challenge = try await backend.sendChallenge(to: rival.id, court: BadmintonCourt.curatedUS[0],
                                                        slot: TimeSlot.suggestedDefault(), message: "")
        backend.currentUserIdOverride(rival.id)
        let game = try XCTUnwrap(try await backend.respondToChallenge(id: challenge.id, accept: true))
        XCTAssertEqual(game.teams, [[me.id], [rival.id]])
        XCTAssertEqual(game.origin, .challenge(id: challenge.id))
    }

    func testProfileRejectsAdvertising() async throws {
        var me = signUp()
        me.bio = "加微信 abc123 约球"
        do {
            _ = try await backend.updateProfile(me)
            XCTFail("简介不能留联系方式")
        } catch {
            XCTAssertEqual(error as? BackendError, .profileContainsContact)
        }
    }
}
