import XCTest
@testable import Badie

/// 演示模式的附近的人：约人、每天 10 个、收到的邀请说好、定时间
@MainActor
final class NearbyInviteTests: XCTestCase {

    private var backend: MockBackend!

    override func setUp() async throws {
        try await super.setUp()
        backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4,
                              recurringSlots: [RecurringTimeSlot(dayOfWeek: 7, startHour: 9, endHour: 18)],
                              location: Coordinate.fallbackCenter, seedsDemoContent: false)
    }

    private func lobby() async throws -> [MockBackend.NearbyPlayer] {
        try await backend.nearbyPlayers(center: Coordinate.fallbackCenter, radiusKm: 30)
    }

    func testLobbyCardsHaveUsualTimesAndFriendsAreIncluded() async throws {
        let players = try await lobby()
        try XCTSkipIf(players.isEmpty, "附近没有示例球友")
        XCTAssertTrue(players.allSatisfy { !$0.usualTimes.isEmpty }, "示例球友都有空闲时间")
        XCTAssertFalse(players.contains { $0.userId == backend.currentUserId })
        // 球友也在里面
        let first = players[0].userId
        backend.makeFriends(backend.currentUserId!, first)
        let again = try await lobby()
        XCTAssertEqual(again.first { $0.userId == first }?.isFriend, true)
    }

    func testInviteRemovesCardAndBlocksSecondInvite() async throws {
        let players = try await lobby()
        try XCTSkipIf(players.isEmpty, "附近没有示例球友")
        let target = players[0]
        let window = try XCTUnwrap(PlayWindow.weekend(daypart: nil))
        let result = try await backend.invitePlayer(target.userId, venueId: target.venues[0].id, window: window)
        XCTAssertEqual(result.remaining, MockBackend.inviteLimit - 1)
        let room = try XCTUnwrap(backend.db.rooms[result.roomId])
        XCTAssertEqual(room.invite?.toId, target.userId)
        XCTAssertEqual(room.invite?.awaitingId, target.userId)
        XCTAssertEqual(room.window?.end, window.end)
        XCTAssertEqual(room.mode, .singles)

        let after = try await lobby()
        XCTAssertFalse(after.contains { $0.userId == target.userId }, "有邀请没结束的人不在附近的人里")
        do {
            _ = try await backend.invitePlayer(target.userId, venueId: target.venues[0].id, window: window)
            XCTFail("已经约过了")
        } catch {
            XCTAssertEqual(error as? RemoteError, .server("already_invited"))
        }
    }

    /// 新的约 TA：定好的时间（窗口正好一场，1.5 小时）、双打
    func testExactDoublesInvite() async throws {
        let players = try await lobby()
        try XCTSkipIf(players.isEmpty, "附近没有示例球友")
        let target = players[0]
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
        var window = try XCTUnwrap(PlayWindow.on(tomorrow, startMinutes: 19 * 60, endMinutes: 20 * 60 + 30))
        window.durationMinutes = 90
        XCTAssertTrue(window.isExact)
        let result = try await backend.invitePlayer(target.userId, venueId: target.venues[0].id, window: window, mode: .doubles)
        let room = try XCTUnwrap(backend.db.rooms[result.roomId])
        XCTAssertEqual(room.mode, .doubles)
        XCTAssertNil(room.window, "定好的时间不是窗口")
        XCTAssertEqual(room.slot?.startTime, window.start)
        XCTAssertEqual(room.slot?.endTime, window.end)
    }

    func testDailyLimit() async throws {
        backend.demoInvitesSent = Array(repeating: Date(), count: MockBackend.inviteLimit)
        let players = try await lobby()
        try XCTSkipIf(players.isEmpty, "附近没有示例球友")
        let window = try XCTUnwrap(PlayWindow.weekend(daypart: nil))
        do {
            _ = try await backend.invitePlayer(players[0].userId, venueId: players[0].venues[0].id, window: window)
            XCTFail("今天的 10 个用完了")
        } catch {
            XCTAssertEqual(error as? RemoteError, .server("invite_limit"))
            XCTAssertEqual(InviteText.error(error), String(localized: "今天的 10 个用完了，明天再来"))
        }
    }

    func testAcceptIncomingInviteThenSetTime() async throws {
        let invites = try await backend.nearbyInvites()
        let me = try XCTUnwrap(backend.currentUserId)
        let incoming = try XCTUnwrap(invites.first { $0.invite?.toId == me && $0.invite?.rounds == 0 }, "演示有一个别人约我的")
        XCTAssertEqual(invites.first?.invite?.awaitingId, me, "轮到我回的在前")

        let answer = try await backend.respondInvite(incoming.id, accept: true)
        let gameId = try XCTUnwrap(answer)
        let game = try XCTUnwrap(backend.db.games[gameId])
        XCTAssertFalse(game.isTimeSet)
        XCTAssertFalse(game.isLateCancellation(), "没定时间的不算临时取消")
        XCTAssertEqual(Set(game.playerIds), Set([me, incoming.ownerId]))

        let start = try XCTUnwrap(game.window?.possibleStarts().first)
        try await backend.setGameTime(gameId, startsAt: start)
        let set = try XCTUnwrap(backend.db.games[gameId])
        XCTAssertTrue(set.isTimeSet)
        XCTAssertEqual(set.slot.startTime, start)
        XCTAssertEqual(set.slot.duration, 2 * 3600)
    }

    func testCounterPassesTurnAndDeclineHidesFromLobby() async throws {
        let invites = try await backend.nearbyInvites()
        let me = try XCTUnwrap(backend.currentUserId)
        let incoming = try XCTUnwrap(invites.first { $0.invite?.toId == me && $0.invite?.awaitingId == me })
        let window = try XCTUnwrap(PlayWindow.nextWeekdays(daypart: .evening))
        try await backend.counterInvite(incoming.id, venueId: nil, window: window)
        let countered = try XCTUnwrap(backend.db.rooms[incoming.id])
        XCTAssertEqual(countered.invite?.awaitingId, incoming.ownerId)
        XCTAssertEqual(countered.invite?.rounds, 1)
        XCTAssertEqual(countered.window, window)
        XCTAssertEqual(InviteText.title(countered, me: incoming.ownerId) { _ in "阿杰" }, String(localized: "\("阿杰")想换个时间"))
        do {
            _ = try await backend.respondInvite(incoming.id, accept: true)
            XCTFail("轮到对方回")
        } catch {
            XCTAssertEqual(error as? RemoteError, .server("not_your_turn"))
        }

        // 另一个（我发的、对方换了时间）：不了 → 30 天内不再出现
        guard let mine = invites.first(where: { $0.invite?.fromId == me && $0.invite?.awaitingId == me }) else { return }
        let other = try XCTUnwrap(mine.invite?.toId)
        try await backend.respondInvite(mine.id, accept: false)
        XCTAssertEqual(backend.db.rooms[mine.id]?.status, .closed(.declined))
        let players = try await lobby()
        XCTAssertFalse(players.contains { $0.userId == other })
    }
}
