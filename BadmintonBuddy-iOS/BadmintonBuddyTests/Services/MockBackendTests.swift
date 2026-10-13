import XCTest
@testable import BadmintonBuddy

/// 模拟后端的端到端业务规则测试（内存数据库、无延迟、关闭机器人行为）
@MainActor
final class MockBackendTests: XCTestCase {

    private var backend: MockBackend!

    override func setUp() async throws {
        try await super.setUp()
        backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false
    }

    private func signUp(seed: Bool = false) -> User {
        backend.createAccount(phone: "13800001234", nickname: "阿杰", level: 4,
                              location: Coordinate.fallbackCenter, seedsDemoContent: seed)
    }

    // MARK: Auth

    func testPhoneValidation() {
        XCTAssertTrue(MockBackend.isValidPhone("13800001234"))
        XCTAssertFalse(MockBackend.isValidPhone("12800001234"))
        XCTAssertFalse(MockBackend.isValidPhone("1380000123"))
        XCTAssertFalse(MockBackend.isValidPhone("1380000123a"))
    }

    func testCodeLoginCreatesThenRestoresAccount() async throws {
        let code = try await backend.requestCode(phone: "13912345678")
        do {
            _ = try await backend.verify(phone: "13912345678", code: "000000" == code ? "111111" : "000000")
            XCTFail("错误验证码应失败")
        } catch {
            XCTAssertEqual(error as? BackendError, .invalidCode)
        }
        let outcome = try await backend.verify(phone: "13912345678", code: code)
        XCTAssertEqual(outcome, .needsProfile(phone: "13912345678"))

        let user = try await backend.register(phone: "13912345678", nickname: "新球友", gender: .female,
                                              avatar: Avatar(symbol: "", paletteIndex: 1), level: 9,
                                              preferredMode: .singles, recurringSlots: [], location: nil)
        XCTAssertEqual(user.selfReportedLevel, 7, "自评最高 7 级")
        XCTAssertEqual(backend.currentUserId, user.id)

        backend.signOut()
        XCTAssertNil(backend.currentUser)
        let again = try await backend.requestCode(phone: "13912345678")
        let restored = try await backend.verify(phone: "13912345678", code: again)
        guard case .signedIn(let restoredUser) = restored else { return XCTFail("应直接登录") }
        XCTAssertEqual(restoredUser.id, user.id)
    }

    func testDemoSeedProvidesSocialContent() {
        _ = signUp(seed: true)
        XCTAssertEqual(backend.friends().count, 3)
        XCTAssertEqual(backend.incomingRequests().count, 1)
        XCTAssertFalse(backend.threads().isEmpty)
        XCTAssertEqual(backend.pendingSurveys().count, 1)
        XCTAssertFalse(backend.publicRooms(radiusKm: 50).isEmpty)
    }

    // MARK: Friends

    func testFriendRequestAcceptIsBidirectional() async throws {
        let me = signUp()
        try await backend.sendFriendRequest(to: "bot-5", note: "一起打球")
        XCTAssertTrue(backend.hasPendingRequest(to: "bot-5"))
        do {
            try await backend.sendFriendRequest(to: "bot-5", note: "")
            XCTFail("重复申请应失败")
        } catch {
            XCTAssertEqual(error as? BackendError, .requestAlreadySent)
        }
        // 对方通过
        backend.makeFriends(me.id, "bot-5")
        XCTAssertTrue(backend.friendIds(of: me.id).contains("bot-5"))
        XCTAssertTrue(backend.friendIds(of: "bot-5").contains(me.id))
    }

    func testRespondingToIncomingRequest() async throws {
        _ = signUp(seed: true)
        let request = try XCTUnwrap(backend.incomingRequests().first)
        try await backend.respond(to: request.id, accept: true)
        XCTAssertTrue(backend.isFriend(request.fromUserId))
        XCTAssertTrue(backend.incomingRequests().isEmpty)
    }

    // MARK: Messages & blocking

    func testMessagingLimitsAndReceipts() async throws {
        let me = signUp()
        do {
            _ = try await backend.sendMessage(String(repeating: "a", count: 1001), to: "bot-0")
            XCTFail("超长消息应失败")
        } catch {
            XCTAssertEqual(error as? BackendError, .messageTooLong)
        }
        let message = try await backend.sendMessage("周末打球吗", to: "bot-0")
        XCTAssertTrue(message.isDelivered)
        let threadId = MessageThread.id(for: me.id, "bot-0")
        XCTAssertEqual(backend.messages(threadId: threadId).count, 1)
        XCTAssertEqual(backend.db.threads[threadId]?.unreadCount(for: "bot-0"), 1)
    }

    func testBlockPreventsSendingAndHidesThread() async throws {
        _ = signUp()
        _ = try await backend.sendMessage("你好", to: "bot-0")
        XCTAssertEqual(backend.threads().count, 1)
        backend.block("bot-0")
        XCTAssertTrue(backend.threads().isEmpty)
        do {
            _ = try await backend.sendMessage("还在吗", to: "bot-0")
            XCTFail("屏蔽后不能发消息")
        } catch {
            XCTAssertEqual(error as? BackendError, .blocked)
        }
        backend.unblock("bot-0")
        XCTAssertEqual(backend.threads().count, 1)
    }

    func testMessageFromBlockedUserIsNotDelivered() async throws {
        let me = signUp()
        backend.db.blocks["bot-0"] = [BlockedUser(blockedUserId: me.id, blockedAt: Date())]
        let message = try await backend.sendMessage("你好", to: "bot-0")
        XCTAssertFalse(message.isDelivered, "被对方屏蔽时消息不送达，但也不提示")
    }

    func testDeleteThreadIsSoftDelete() async throws {
        let me = signUp()
        _ = try await backend.sendMessage("你好", to: "bot-0")
        let threadId = MessageThread.id(for: me.id, "bot-0")
        backend.deleteThread(threadId)
        XCTAssertTrue(backend.threads().isEmpty)
        XCTAssertTrue(backend.messages(threadId: threadId).isEmpty)
        XCTAssertNotNil(backend.db.threads[threadId], "对方的会话仍保留")
        XCTAssertTrue(backend.db.threads[threadId]?.isVisible(to: "bot-0") ?? false)
    }

    // MARK: Rooms

    func testPrivateRoomLifecycle() async throws {
        let me = signUp()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        var draft = RoomDraft()
        draft.mode = .singles
        draft.court = BadmintonCourt.curatedBeijing[0]
        draft.slot = TimeSlot.on(tomorrow, startHour: 19, endHour: 21)
        let room = try await backend.createRoom(draft)
        XCTAssertEqual(room.participants.map(\.userId), [me.id])
        XCTAssertTrue(Room.isValidCode(room.code))

        do {
            _ = try await backend.startRoom(id: room.id)
            XCTFail("人数不足不能开始")
        } catch {
            XCTAssertEqual(error as? BackendError, .notEnoughPlayers(required: 2, current: 1))
        }

        // 好友加入后房主可踢人
        var stored = try XCTUnwrap(backend.db.rooms[room.id])
        stored.participants.append(RoomParticipant(user: try XCTUnwrap(backend.user(id: "bot-3"))))
        backend.db.rooms[room.id] = stored
        try await backend.kick("bot-3", from: room.id)
        XCTAssertEqual(backend.room(id: room.id)?.participants.count, 1)

        stored = try XCTUnwrap(backend.db.rooms[room.id])
        stored.participants.append(RoomParticipant(user: try XCTUnwrap(backend.user(id: "bot-3"))))
        backend.db.rooms[room.id] = stored
        let game = try await backend.startRoom(id: room.id)
        XCTAssertEqual(game.playerIds.count, 2)
        XCTAssertEqual(game.status, .confirmed)
        XCTAssertEqual(backend.room(id: room.id)?.status, .started(gameId: game.id))
    }

    func testJoinByCodeAndWaitlistPromotion() async throws {
        let me = signUp()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let host = try XCTUnwrap(backend.user(id: "bot-1"))
        let other = try XCTUnwrap(backend.user(id: "bot-3"))
        let room = Room(
            id: "r1", code: "QWERTY", ownerId: host.id, mode: .singles, visibility: .publicListing,
            participants: [RoomParticipant(user: host), RoomParticipant(user: other)], invitedUserIds: [], waitlist: [],
            court: BadmintonCourt.curatedBeijing[0], slot: TimeSlot.on(tomorrow, startHour: 19, endHour: 21),
            levelRange: 1...9, tags: [], note: "", createdAt: Date(), lastActivityAt: Date(), status: .open
        )
        backend.db.rooms[room.id] = room

        let joined = try await backend.joinRoom(code: "qwerty")
        XCTAssertTrue(joined.isWaitlisted(me.id), "满员的公开局进入候补")

        // 有人退出，候补自动递补
        var stored = try XCTUnwrap(backend.db.rooms[room.id])
        stored.participants.removeAll { $0.userId == other.id }
        backend.db.rooms[room.id] = stored
        backend.currentUserIdOverride(host.id)
        try await backend.kick(other.id, from: room.id)
        backend.currentUserIdOverride(me.id)
        XCTAssertTrue(backend.room(id: room.id)?.contains(me.id) ?? false)
    }

    func testJoinRejectsOutOfRangeLevelAndUnknownCode() async throws {
        _ = signUp()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let host = try XCTUnwrap(backend.user(id: "bot-1"))
        backend.db.rooms["r2"] = Room(
            id: "r2", code: "ZXCVBN", ownerId: host.id, mode: .doubles, visibility: .publicListing,
            participants: [RoomParticipant(user: host)], invitedUserIds: [], waitlist: [],
            court: BadmintonCourt.curatedBeijing[0], slot: TimeSlot.on(tomorrow, startHour: 19, endHour: 21),
            levelRange: 6...9, tags: [], note: "", createdAt: Date(), lastActivityAt: Date(), status: .open
        )
        do {
            _ = try await backend.joinPublicRoom(id: "r2")
            XCTFail("水平不符不能加入")
        } catch {
            XCTAssertEqual(error as? BackendError, .levelOutOfRange("Lv.6–9"))
        }
        do {
            _ = try await backend.joinRoom(code: "ABCDEF")
            XCTFail("不存在的房间码")
        } catch {
            XCTAssertEqual(error as? BackendError, .roomNotFound)
        }
    }

    func testPrivateRoomExpires() async throws {
        _ = signUp()
        let room = try await backend.createRoom(RoomDraft())
        backend.expireRooms(now: Date().addingTimeInterval(31 * 60))
        XCTAssertEqual(backend.room(id: room.id)?.status, .closed(.expired))
    }

    // MARK: Matching & games

    func testFindMatchesReturnsProposalsForWeekdayEvening() async throws {
        let me = signUp()
        let request = MatchRequest(
            mode: .singles,
            slot: try XCTUnwrap(TimeSlot.on(nextWeekday(), startHour: 19, endHour: 21)),
            courts: Array(BadmintonCourt.curatedBeijing.prefix(3)),
            skillTolerance: MatchRequest.anySkill, userId: me.id, userLevel: me.displayLevel,
            userLocation: Coordinate.fallbackCenter, radiusKm: 50, excludedUserIds: []
        )
        let result = try await backend.findMatches(request)
        guard case .proposals(let proposals) = result else { return XCTFail("工作日晚上应能匹配到人") }
        let game = try await backend.confirm(try XCTUnwrap(proposals.first))
        XCTAssertTrue(backend.games().contains { $0.id == game.id })
    }

    func testLateCancellationCountsAgainstAttendance() async throws {
        let me = signUp()
        let start = Date().addingTimeInterval(3600)
        let game = makeGame(id: "g1", players: [me.id, "bot-0"], start: start)
        backend.db.games[game.id] = game
        try await backend.cancelGame(id: game.id)
        XCTAssertEqual(backend.game(id: "g1")?.status, .cancelled)
        XCTAssertEqual(backend.game(id: "g1")?.cancelledLate, true)
        XCTAssertEqual(backend.currentUser?.attendance.lateCancellations, 1)
    }

    func testCheckInWindow() async throws {
        let me = signUp()
        backend.db.games["far"] = makeGame(id: "far", players: [me.id, "bot-0"], start: Date().addingTimeInterval(3 * 3600))
        do {
            _ = try await backend.checkIn(gameId: "far")
            XCTFail("开赛前 30 分钟才能签到")
        } catch {
            XCTAssertEqual(error as? BackendError, .checkInNotOpen)
        }
        backend.db.games["soon"] = makeGame(id: "soon", players: [me.id, "bot-0"], start: Date().addingTimeInterval(10 * 60))
        let checked = try await backend.checkIn(gameId: "soon")
        XCTAssertNotNil(checked.checkIns[me.id])
    }

    // MARK: Surveys (double-blind)

    func testCompletingGameCreatesSurveysAndDoubleBlindRelease() async throws {
        let me = signUp()
        backend.db.games["done"] = makeGame(id: "done", players: [me.id, "bot-0"], start: Date().addingTimeInterval(-3 * 3600))
        try await backend.completeGame(id: "done", didWin: true, score: "21:15")
        XCTAssertEqual(backend.currentUser?.totalGames, 1)
        XCTAssertEqual(backend.currentUser?.wins, 1)

        let pending = try XCTUnwrap(backend.pendingSurveys().first)
        XCTAssertEqual(pending.opponentId, "bot-0")
        XCTAssertEqual(backend.db.heldSurveys.count, 1, "对方的评价先暂存")
        XCTAssertEqual(backend.currentUser?.reputation.evaluationCount, 0)

        let before = try XCTUnwrap(backend.user(id: "bot-0")).reputation.evaluationCount
        try await backend.submitSurvey(pendingId: pending.id, skillRating: 6, attendance: .onTime, characterRating: 5, tags: [.friendly])
        XCTAssertEqual(backend.user(id: "bot-0")?.reputation.evaluationCount, before + 1)
        XCTAssertEqual(backend.currentUser?.reputation.evaluationCount, 1, "我提交后对方的评价随之生效")
        XCTAssertTrue(backend.db.heldSurveys.isEmpty)

        do {
            try await backend.submitSurvey(pendingId: pending.id, skillRating: 6, attendance: .onTime, characterRating: 5, tags: [])
            XCTFail("不能重复提交")
        } catch {
            XCTAssertEqual(error as? BackendError, .surveyExpired)
        }
        XCTAssertTrue(backend.hasSubmittedSurvey(matchId: "done", evaluatorId: me.id, evaluatedUserId: "bot-0"))
    }

    func testExpiredSurveysAreExcluded() async throws {
        let me = signUp()
        backend.db.games["old"] = makeGame(id: "old", players: [me.id, "bot-0"], start: Date().addingTimeInterval(-3 * 3600))
        try await backend.completeGame(id: "old", didWin: nil, score: "")
        let pending = try XCTUnwrap(backend.pendingSurveys().first)
        backend.processSurveyExpirations(now: pending.expiresAt.addingTimeInterval(60))
        XCTAssertTrue(backend.pendingSurveys(now: pending.expiresAt.addingTimeInterval(60)).isEmpty)
        // 窗口结束后对方的暂存评价公开
        XCTAssertEqual(backend.currentUser?.reputation.evaluationCount, 1)
    }

    func testNoShowAnswerUpdatesAttendance() async throws {
        let me = signUp()
        backend.db.games["ns"] = makeGame(id: "ns", players: [me.id, "bot-6"], start: Date().addingTimeInterval(-3 * 3600))
        try await backend.completeGame(id: "ns", didWin: nil, score: "")
        let before = try XCTUnwrap(backend.user(id: "bot-6")).attendance.noShows
        let pending = try XCTUnwrap(backend.pendingSurveys().first)
        try await backend.submitSurvey(pendingId: pending.id, skillRating: 6, attendance: .noShow, characterRating: 2, tags: [])
        XCTAssertEqual(backend.user(id: "bot-6")?.attendance.noShows, before + 1)
    }

    func testRecurringSlotLimit() throws {
        _ = signUp()
        let six = (1...6).map { RecurringTimeSlot(dayOfWeek: ($0 % 7) + 1, startHour: 19, endHour: 21) }
        XCTAssertThrowsError(try backend.saveRecurringSlots(six))
        XCTAssertNoThrow(try backend.saveRecurringSlots(Array(six.prefix(5))))
        XCTAssertEqual(backend.recurringSlots().count, 5)
    }

    // MARK: Helpers

    private func makeGame(id: String, players: [String], start: Date) -> Game {
        let slot = TimeSlot(date: start, startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let court = BadmintonCourt.curatedBeijing[0]
        return Game(
            id: id, mode: .singles, court: court, slot: slot, playerIds: players, teams: players.map { [$0] },
            hostId: players[0], origin: .quickMatch, status: .confirmed, createdAt: Date(), checkIns: [:],
            paidPlayerIds: [], cost: CostSplit.estimate(court: court, slot: slot, mode: .singles), result: nil,
            cancelledBy: nil, cancelledLate: false, reminderEnabled: false
        )
    }

    /// 下一个周二（工作日晚上大部分模拟球友有空）
    private func nextWeekday() -> Date {
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: 1, to: Date())!
        while calendar.component(.weekday, from: day) != 3 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return day
    }
}

extension MockBackend {
    /// 测试辅助：切换当前身份（模拟房主操作）
    func currentUserIdOverride(_ id: String) {
        db.currentUserId = id
    }
}
