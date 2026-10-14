import XCTest
@testable import Badie

/// 社交规则：谁能私信谁、球局群聊、消息请求、球群报名与候补、同馆常客、想再约
@MainActor
final class SocialRulesTests: XCTestCase {

    private var backend: MockBackend!

    override func setUp() async throws {
        try await super.setUp()
        backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false
    }

    @discardableResult
    private func signUp(gamesPlayed: Int = 0) -> User {
        let user = backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4,
                                         location: Coordinate.fallbackCenter, seedsDemoContent: false)
        backend.db.users[user.id]?.attendance.gamesPlayed = gamesPlayed
        return backend.db.users[user.id] ?? user
    }

    private func game(_ id: String, players: [String], start: Date) -> Game {
        let slot = TimeSlot(date: start, startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let court = BadmintonCourt.curatedUS[0]
        return Game(id: id, mode: .singles, court: court, slot: slot, playerIds: players, teams: players.map { [$0] },
                    hostId: players[0], origin: .quickMatch, status: .confirmed, createdAt: Date(), checkIns: [:],
                    paidPlayerIds: [], cost: CostSplit.estimate(court: court, slot: slot, mode: .singles), result: nil,
                    cancelledBy: nil, cancelledLate: false, reminderEnabled: false)
    }

    /// 附近的“直接加入”球群（模拟世界自带）
    private func openGroup() throws -> PlayGroup {
        try XCTUnwrap(backend.groups(near: .fallbackCenter, radiusKm: 40).first { $0.joinPolicy == .open })
    }

    // MARK: Who can message whom

    func testStrangersCannotMessageDirectly() async throws {
        signUp()
        XCTAssertEqual(backend.messagePermission(with: "bot-20"), .friendsOnly)
        do {
            _ = try await backend.sendMessage("你好", to: "bot-20")
            XCTFail("陌生人不能直接私信")
        } catch {
            XCTAssertEqual(error as? BackendError, .notFriends)
        }
    }

    func testGameChatOpensForPlayersAndClosesAfter48Hours() async throws {
        let me = signUp()
        let start = Date().addingTimeInterval(3600)
        let match = game("g-chat", players: [me.id, "bot-20"], start: start)
        backend.db.games[match.id] = match
        XCTAssertEqual(backend.messagePermission(with: "bot-20"), .gameChat(gameId: match.id))
        do {
            _ = try await backend.sendMessage("你好", to: "bot-20")
            XCTFail("同一场球局应使用球局群聊")
        } catch {
            XCTAssertEqual(error as? BackendError, .useGameChat)
        }
        let thread = backend.ensureGameThread(for: match)
        XCTAssertEqual(Set(thread.participantIds), [me.id, "bot-20"])
        _ = try await backend.sendGroupMessage("我带球", threadId: thread.id)
        XCTAssertEqual(backend.messages(threadId: thread.id).filter { $0.kind == .text }.count, 1)

        let afterWindow = match.slot.endTime.addingTimeInterval(MessageThread.gameChatOpenAfterEnd + 60)
        do {
            _ = try await backend.sendGroupMessage("还在吗", threadId: thread.id, now: afterWindow)
            XCTFail("赛后 48 小时群聊关闭")
        } catch {
            XCTAssertEqual(error as? BackendError, .chatClosed)
        }
        XCTAssertEqual(backend.messagePermission(with: "bot-20", now: afterWindow), .friendsOnly)
    }

    func testGroupMessageRequestIsOneTextOnlyMessageUntilAccepted() async throws {
        let me = signUp(gamesPlayed: 5)
        let group = try openGroup()
        try backend.joinGroup(id: group.id)
        let target = try XCTUnwrap(group.memberIds.first { $0 != me.id && !backend.isFriend($0) })
        XCTAssertEqual(backend.messagePermission(with: target), .request(groupName: group.name))

        do {
            _ = try await backend.sendMessage("加我微信 abc123 聊", to: target)
            XCTFail("消息请求里不能留联系方式")
        } catch {
            XCTAssertEqual(error as? BackendError, .requestContainsContact)
        }
        _ = try await backend.sendMessage("周四我也去，第一次来请多关照", to: target)
        XCTAssertEqual(backend.messagePermission(with: target), .pendingRequest)
        do {
            _ = try await backend.sendMessage("在吗？", to: target)
            XCTFail("对方接受前不能继续发")
        } catch {
            XCTAssertEqual(error as? BackendError, .messageRequestPending)
        }

        // 对方接受
        backend.currentUserIdOverride(target)
        XCTAssertEqual(backend.incomingMessageRequests().count, 1)
        backend.acceptMessageRequest(threadId: MessageThread.id(for: me.id, target))
        backend.currentUserIdOverride(me.id)
        XCTAssertEqual(backend.messagePermission(with: target), .allowed)
    }

    func testNewAccountsAndOptedOutUsersCannotReceiveRequests() throws {
        let me = signUp(gamesPlayed: 0)
        let group = try openGroup()
        try backend.joinGroup(id: group.id)
        let target = try XCTUnwrap(group.memberIds.first { $0 != me.id && !backend.isFriend($0) })
        XCTAssertEqual(backend.messagePermission(with: target), .newAccount, "打满 3 场前不能发消息请求")

        backend.db.users[me.id]?.attendance.gamesPlayed = 3
        backend.db.users[target]?.privacy.allowsMessageRequests = false
        XCTAssertEqual(backend.messagePermission(with: target), .friendsOnly, "对方关闭了消息请求")
    }

    func testContactInfoDetection() {
        XCTAssertTrue(ContactInfoDetector.mentionsOffPlatformContact("我电话 626 555 0123"))
        XCTAssertTrue(ContactInfoDetector.mentionsOffPlatformContact("加我微信聊"))
        XCTAssertTrue(ContactInfoDetector.mentionsOffPlatformContact("先 Venmo 我 $20 占位"))
        XCTAssertFalse(ContactInfoDetector.mentionsOffPlatformContact("周四 19:30 LABC 见"))
        XCTAssertTrue(ContactInfoDetector.containsLink("看这个 https://example.com/x"))
        XCTAssertFalse(ContactInfoDetector.containsLink("周四见"))
    }

    // MARK: Groups

    func testWorldHasActiveGroupsShowingTurnoutNotMemberCount() throws {
        signUp()
        let group = try openGroup()
        let activity = backend.activity(of: group.id)
        XCTAssertGreaterThan(activity.sessionsLast30Days, 0)
        XCTAssertTrue(activity.text.contains("近 30 天"))
        XCTAssertEqual(backend.group(code: group.inviteCode.lowercased())?.id, group.id, "群号不区分大小写")
    }

    func testSignupWaitlistAndAutomaticPromotion() throws {
        let me = signUp()
        let group = try openGroup()
        try backend.joinGroup(id: group.id)
        let session = try XCTUnwrap(backend.upcomingSessions(groupId: group.id)
            .first { $0.slot.startTime > Date().addingTimeInterval(3 * 3600) && !$0.signedUp.isEmpty })
        // 让这一场正好满员
        backend.db.groupSessions[session.id]?.capacity = session.signedUp.count
        XCTAssertEqual(try backend.signUp(sessionId: session.id), .waitlisted(position: 1))

        // 有人退出 → 我自动递补
        let leaving = try XCTUnwrap(session.signedUp.first)
        backend.currentUserIdOverride(leaving)
        try backend.cancelSignup(sessionId: session.id)
        backend.currentUserIdOverride(me.id)
        XCTAssertEqual(backend.session(id: session.id)?.status(of: me.id), .signedUp)
        XCTAssertTrue(backend.inbox().contains { $0.kind == .groupUpdate }, "候补转正会通知")
    }

    func testLateWithdrawalCountsAsLateCancellation() throws {
        let me = signUp()
        let group = try backend.createGroup(
            name: "测试群", venueId: BadmintonCourt.curatedUS[0].id,
            schedules: [GroupSchedule(id: "s", weekday: Calendar.current.component(.weekday, from: Date().addingTimeInterval(86400)),
                                      startMinutes: 19 * 60, endMinutes: 21 * 60, capacity: 8)],
            levelRange: 1...9, joinPolicy: .open, summary: "")
        let session = try XCTUnwrap(backend.upcomingSessions(groupId: group.id).first)
        try backend.signUp(sessionId: session.id)
        try backend.cancelSignup(sessionId: session.id, now: session.slot.startTime.addingTimeInterval(-3600))
        XCTAssertEqual(backend.currentUser?.attendance.lateCancellations, 1)
        XCTAssertEqual(me.attendance.lateCancellations, 0)
    }

    func testApprovalGroupsAndLevelRange() throws {
        let me = signUp()
        let strict = try XCTUnwrap(backend.groups(near: .fallbackCenter, radiusKm: 40).first { $0.joinPolicy == .approval })
        XCTAssertThrowsError(try backend.joinGroup(id: strict.id), "水平不在范围内") {
            guard case .levelOutOfRange = $0 as? BackendError else { return XCTFail("应提示水平不符") }
        }
        // 和重新测评一样，整数等级和细分分值一起更新
        backend.db.users[me.id]?.selfReportedLevel = strict.levelRange.lowerBound
        backend.db.users[me.id]?.selfReportedRating = Double(strict.levelRange.lowerBound)
        try backend.joinGroup(id: strict.id)
        XCTAssertEqual(backend.group(id: strict.id)?.pendingIds, [me.id])
        try backend.approveMember(me.id, groupId: strict.id, asOrganizer: strict.ownerId)
        XCTAssertTrue(backend.group(id: strict.id)?.isMember(me.id) ?? false)
        XCTAssertEqual(backend.thread(id: MessageThread.groupThreadId(strict.id))?.participantIds.contains(me.id), true,
                       "加入后进入球群群聊")
    }

    // MARK: Venue regulars

    func testVenueRegularsAreOptInAndShareAVenue() throws {
        let me = signUp()
        let venueId = try XCTUnwrap(backend.db.favoriteCourtIds.first { entry in
            backend.isBot(entry.key) && !entry.value.isEmpty && backend.db.users[entry.key]?.privacy.showsAsRegular == true
        }?.value.first)
        backend.toggleFavoriteCourt(venueId)
        let regulars = backend.venueRegulars()
        XCTAssertFalse(regulars.isEmpty)
        XCTAssertTrue(regulars.allSatisfy { $0.user.privacy.showsAsRegular })
        XCTAssertFalse(regulars.contains { $0.user.id == me.id })

        let first = try XCTUnwrap(regulars.first)
        backend.db.users[first.user.id]?.privacy.showsAsRegular = false
        XCTAssertFalse(backend.venueRegulars().contains { $0.user.id == first.user.id }, "关闭后不再出现")
    }

    // MARK: Rematch

    func testRematchIsRevealedOnlyWhenBothChoseIt() async throws {
        let me = signUp()
        for (index, botWants) in [true, false].enumerated() {
            let start = Date().addingTimeInterval(-Double(index + 3) * 3600)
            let opponent = index == 0 ? "bot-20" : "bot-21"
            var match = game("g-rematch-\(index)", players: [me.id, opponent], start: start)
            match.checkIns = [me.id: start, opponent: start]
            backend.db.games[match.id] = match
            try await backend.completeGame(id: match.id, didWin: true, score: "21:15")
            for heldIndex in backend.db.heldSurveys.indices where backend.db.heldSurveys[heldIndex].matchId == match.id {
                backend.db.heldSurveys[heldIndex].wantsRematch = botWants
            }
            let pending = try XCTUnwrap(backend.pendingSurveys().first { $0.matchId == match.id })
            try await backend.submitSurvey(pendingId: pending.id, skillRating: 4, attendance: .onTime, characterRating: 5,
                                           tags: [.friendly], wantsRematch: true)
        }
        let rematches = backend.inbox().filter { $0.kind == .rematch }
        XCTAssertEqual(rematches.map(\.relatedId), ["bot-20"], "只有双方都想再约才通知")
    }
}
