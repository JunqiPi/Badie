import XCTest
@testable import Badie

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
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4,
                              location: Coordinate.fallbackCenter, seedsDemoContent: seed)
    }

    // MARK: Auth

    func testPhoneValidation() {
        XCTAssertTrue(MockBackend.isValidPhone("+16265550123"))
        XCTAssertTrue(MockBackend.isValidPhone("+8613800001234"))
        XCTAssertFalse(MockBackend.isValidPhone("+11265550123"), "北美区号不能以 1 开头")
        XCTAssertFalse(MockBackend.isValidPhone("+1626555012"))
        XCTAssertFalse(MockBackend.isValidPhone("+8612800001234"))
        XCTAssertFalse(MockBackend.isValidPhone("6265550123"), "存储必须是 E.164")
    }

    func testCodeLoginCreatesThenRestoresAccount() async throws {
        let code = try await backend.requestCode(phone: "+14155550188")
        do {
            _ = try await backend.verify(phone: "+14155550188", code: "000000" == code ? "111111" : "000000")
            XCTFail("错误验证码应失败")
        } catch {
            XCTAssertEqual(error as? BackendError, .invalidCode)
        }
        let outcome = try await backend.verify(phone: "+14155550188", code: code)
        XCTAssertEqual(outcome, .needsProfile(phone: "+14155550188"))

        let user = try await backend.register(phone: "+14155550188", nickname: "新球友", gender: .female,
                                              avatar: Avatar(symbol: "", paletteIndex: 1), level: 9,
                                              preferredMode: .singles, recurringSlots: [], location: nil)
        XCTAssertEqual(user.selfReportedLevel, SkillLevel.maxSelfSelectable, "问卷最高 6 级")
        XCTAssertEqual(backend.currentUserId, user.id)

        backend.signOut()
        XCTAssertNil(backend.currentUser)
        let again = try await backend.requestCode(phone: "+14155550188")
        let restored = try await backend.verify(phone: "+14155550188", code: again)
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
        backend.makeFriends(me.id, "bot-0")
        do {
            _ = try await backend.sendMessage(String(repeating: "a", count: 1001), to: "bot-0")
            XCTFail("超长消息应失败")
        } catch {
            XCTAssertEqual(error as? BackendError, .messageTooLong)
        }
        let message = try await backend.sendMessage("周末打球吗", to: "bot-0")
        XCTAssertTrue(message.isDelivered)
        let threadId = MessageThread.id(for: me.id, "bot-0")
        // 成为球友时的系统提示 + 我发的一条
        XCTAssertEqual(backend.messages(threadId: threadId).filter { $0.kind == .text }.count, 1)
        XCTAssertEqual(backend.db.threads[threadId]?.unreadCount(for: "bot-0"), 1)
    }

    func testBlockPreventsSendingAndHidesThread() async throws {
        let me = signUp()
        backend.makeFriends(me.id, "bot-0")
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
        backend.makeFriends(me.id, "bot-0")
        backend.db.blocks["bot-0"] = [BlockedUser(blockedUserId: me.id, blockedAt: Date())]
        let message = try await backend.sendMessage("你好", to: "bot-0")
        XCTAssertFalse(message.isDelivered, "被对方屏蔽时消息不送达，但也不提示")
    }

    func testDeleteThreadIsSoftDelete() async throws {
        let me = signUp()
        backend.makeFriends(me.id, "bot-0")
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
        draft.court = BadmintonCourt.mock
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
            court: BadmintonCourt.mock, slot: TimeSlot.on(tomorrow, startHour: 19, endHour: 21),
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
            court: BadmintonCourt.mock, slot: TimeSlot.on(tomorrow, startHour: 19, endHour: 21),
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
        XCTAssertEqual(backend.currentUser?.wins, 0, "对方确认前不计胜场")
        backend.addResultReport(ResultReport(reporterId: "bot-0", winningTeam: 0, score: "21:15", reportedAt: Date()), to: "done")
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

    // MARK: Venues

    private func candidate(_ name: String, at location: Coordinate, placeId: String? = nil) -> VenueCandidate {
        VenueCandidate(name: name, location: location,
                       address: PostalAddress(street: "123 Test Ave", city: "Arcadia", region: "CA", postalCode: "91006", countryCode: "US"),
                       applePlaceId: placeId, timeZoneId: "America/Los_Angeles")
    }

    func testAddVenueStartsUnconfirmedAndIsSearchable() throws {
        let me = signUp()
        let spot = Coordinate.fallbackCenter.offsetBy(eastKm: 12, northKm: 9)
        let venue = try backend.addVenue(candidate("Shuttle Garage", at: spot), source: .player, aliases: ["SG"], courtCount: 6,
                                         entranceNote: "从后门进")
        XCTAssertEqual(venue.status, .unconfirmed)
        XCTAssertEqual(venue.addedBy, me.id)
        XCTAssertEqual(venue.confirmedBy, [me.id])
        XCTAssertEqual(venue.currencyCode, "USD")
        XCTAssertEqual(venue.entranceNote, "从后门进")
        XCTAssertEqual(backend.searchVenues("shuttle garage", near: spot).first?.venue.id, venue.id)
        XCTAssertEqual(backend.searchVenues("SG", near: spot).first?.venue.id, venue.id)
    }

    func testAddVenueValidatesNameAndAddress() {
        _ = signUp()
        XCTAssertThrowsError(try backend.addVenue(candidate("A", at: .fallbackCenter), source: .player)) {
            XCTAssertEqual($0 as? BackendError, .venueNameInvalid)
        }
        var noStreet = candidate("No Street Gym", at: .fallbackCenter)
        noStreet.address.street = ""
        XCTAssertThrowsError(try backend.addVenue(noStreet, source: .player)) {
            XCTAssertEqual($0 as? BackendError, .venueAddressIncomplete)
        }
    }

    func testSamePlaceIdReturnsExistingVenue() throws {
        _ = signUp()
        let spot = Coordinate.fallbackCenter.offsetBy(eastKm: 20, northKm: 0)
        let first = try backend.addVenue(candidate("Rally Hall", at: spot, placeId: "IABC"), source: .appleMaps)
        let count = backend.allVenues.count
        let second = try backend.addVenue(candidate("Rally Hall (dup)", at: spot.offsetBy(eastKm: 0.5, northKm: 0), placeId: "IABC"),
                                          source: .appleMaps)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(backend.allVenues.count, count)
        XCTAssertEqual(first.id, "v-ap-IABC")
    }

    func testThreeConfirmationsPromoteAndCheckInsCount() async throws {
        let me = signUp()
        let venue = try backend.addVenue(candidate("Community Gym", at: .fallbackCenter.offsetBy(eastKm: 3, northKm: 3)), source: .player)
        backend.currentUserIdOverride("bot-0")
        try backend.confirmVenue(venue.id)
        XCTAssertEqual(backend.venue(id: venue.id)?.status, .unconfirmed)
        backend.currentUserIdOverride(me.id)

        // 在这里签到打过球的人自动算作确认
        let start = Date().addingTimeInterval(-3 * 3600)
        var game = makeGame(id: "g-venue", players: [me.id, "bot-1"], start: start)
        game.court = try XCTUnwrap(backend.venue(id: venue.id))
        game.checkIns = [me.id: start, "bot-1": start]
        backend.db.games[game.id] = game
        try await backend.completeGame(id: game.id, didWin: true, score: "21:10")
        XCTAssertEqual(backend.venue(id: venue.id)?.status, .confirmed)
        XCTAssertEqual(Set(backend.venue(id: venue.id)?.confirmedBy ?? []), [me.id, "bot-0", "bot-1"])
    }

    func testReportsHideUnconfirmedVenueOnlyAfterTwoReporters() throws {
        let me = signUp()
        let spot = Coordinate.fallbackCenter.offsetBy(eastKm: 30, northKm: 0)
        let venue = try backend.addVenue(candidate("Somebody's Garage", at: spot), source: .player)
        backend.currentUserIdOverride("bot-0")
        try backend.reportVenue(venue.id, issue: .notBadminton)
        XCTAssertFalse(backend.searchVenues("garage", near: spot).isEmpty, "一个人的报告不会下架")
        backend.currentUserIdOverride("bot-1")
        try backend.reportVenue(venue.id, issue: .notBadminton)
        XCTAssertTrue(backend.searchVenues("garage", near: spot).isEmpty, "两人报告后进入人工核实")
        backend.currentUserIdOverride(me.id)
        XCTAssertFalse(backend.searchVenues("garage", near: spot).isEmpty, "添加者本人仍能看到")
    }

    func testLikelyDuplicateIsBlocked() throws {
        _ = signUp()
        let labc = try XCTUnwrap(backend.venue(id: "v-us-ca-labc"))
        XCTAssertThrowsError(try backend.addVenue(candidate("LA Badminton Club", at: labc.location.offsetBy(eastKm: 0.05, northKm: 0)),
                                                  source: .player)) {
            XCTAssertEqual($0 as? BackendError, .venueDuplicate(existingName: labc.name))
        }
    }

    func testSameBuildingDifferentNameIsAllowedButFlagged() throws {
        _ = signUp()
        let labc = try XCTUnwrap(backend.venue(id: "v-us-ca-labc"))
        let neighbor = try backend.addVenue(candidate("Pacific Table Tennis", at: labc.location.offsetBy(eastKm: 0.02, northKm: 0)),
                                            source: .player)
        XCTAssertNotEqual(neighbor.id, labc.id)
        XCTAssertEqual(neighbor.reviewFlag, "同一栋楼已有：\(labc.name)")
    }

    func testDailyVenueAddLimit() throws {
        _ = signUp()
        for index in 0..<MockBackend.dailyVenueAddLimit {
            try backend.addVenue(candidate("Garage Court \(index)", at: .fallbackCenter.offsetBy(eastKm: 40 + Double(index) * 5, northKm: 0)),
                                 source: .player)
        }
        XCTAssertThrowsError(try backend.addVenue(candidate("One More Gym", at: .fallbackCenter.offsetBy(eastKm: 70, northKm: 0)),
                                                  source: .player)) {
            XCTAssertEqual($0 as? BackendError, .venueRateLimited)
        }
        // 24 小时后恢复
        XCTAssertNoThrow(try backend.addVenue(candidate("One More Gym", at: .fallbackCenter.offsetBy(eastKm: 70, northKm: 0)),
                                              source: .player, now: Date().addingTimeInterval(25 * 3600)))
    }

    func testMergeRedirectsOldIdFavoritesAndSearch() throws {
        _ = signUp()
        let labc = try XCTUnwrap(backend.venue(id: "v-us-ca-labc"))
        let duplicate = try backend.addVenue(candidate("Shuttle Barn", at: .fallbackCenter.offsetBy(eastKm: 33, northKm: 0)),
                                             source: .player)
        backend.toggleFavoriteCourt(duplicate.id)
        try backend.mergeVenue(duplicate.id, into: labc.id)
        XCTAssertEqual(backend.venue(id: duplicate.id)?.id, labc.id, "旧 ID 跳到保留的球馆")
        XCTAssertEqual(backend.favoriteCourtIds(), [labc.id])
        XCTAssertFalse(backend.allVenues.contains { $0.id == duplicate.id })
        XCTAssertEqual(backend.searchVenues("shuttle barn", near: labc.location).first?.venue.id, labc.id, "旧名称成为别名")
    }

    func testVenuesNearbyAreSortedByDistance() {
        let near = backend.venues(near: .beijing, radiusKm: 50)
        XCTAssertFalse(near.isEmpty)
        let distances = near.map { $0.distance(from: .beijing) }
        XCTAssertEqual(distances, distances.sorted())
    }

    // MARK: Helpers

    private func makeGame(id: String, players: [String], start: Date) -> Game {
        let slot = TimeSlot(date: start, startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let court = BadmintonCourt.mock
        return Game(
            id: id, mode: .singles, court: court, slot: slot, playerIds: players, teams: players.map { [$0] },
            hostId: players[0], origin: .quickMatch, status: .confirmed, createdAt: Date(), checkIns: [:],
            paidPlayerIds: [], cost: CostSplit.estimate(court: court, slot: slot, mode: .singles), result: nil,
            cancelledBy: nil, cancelledLate: false, reminderEnabled: false
        )
    }
}

extension MockBackend {
    /// 测试辅助：切换当前身份，模拟其他用户操作
    func currentUserIdOverride(_ id: String) {
        db.currentUserId = id
    }
}
