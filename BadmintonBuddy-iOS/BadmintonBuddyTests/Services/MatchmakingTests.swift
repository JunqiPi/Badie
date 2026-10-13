import XCTest
@testable import BadmintonBuddy

/// 约球请求：后台排队、多方确认、补位、锁定与临时局
@MainActor
final class MatchmakingTests: XCTestCase {

    private var backend: MockBackend!

    override func setUp() async throws {
        try await super.setUp()
        backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false
    }

    @discardableResult
    private func signUp() -> User {
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4,
                              location: Coordinate.fallbackCenter, seedsDemoContent: false)
    }

    /// 下一个周二晚上 19-21 点（工作日晚上大部分模拟球友有空）
    private func tuesdayEvening() -> TimeSlot {
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: 1, to: Date())!
        while calendar.component(.weekday, from: day) != 3 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return TimeSlot.on(day, startHour: 19, endHour: 21)!
    }

    private func submit(_ mode: GameMode = .singles, slot: TimeSlot? = nil, courtIds: [String]? = nil,
                        autoAccept: Bool = false, now: Date = Date()) async throws -> MatchTicket {
        try await backend.submitTicket(
            mode: mode, slot: slot ?? tuesdayEvening(),
            courtIds: courtIds ?? backend.nearestVenues(to: .fallbackCenter, count: 3).map(\.id),
            skillTolerance: MatchRequest.anySkill, radiusKm: 30, origin: .fallbackCenter,
            autoAccept: autoAccept, now: now
        )
    }

    private func openOffer(of ticket: MatchTicket) throws -> MatchOffer {
        let offerId = try XCTUnwrap(backend.ticket(id: ticket.id)?.offerId, "工作日晚上应能找到人")
        return try XCTUnwrap(backend.offer(id: offerId))
    }

    // MARK: Timing rules

    func testConfirmationWindowScalesWithLeadTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(_ hours: Double) -> TimeInterval {
            MatchTiming.respondBy(start: now.addingTimeInterval(hours * 3600), now: now).timeIntervalSince(now)
        }
        XCTAssertEqual(window(48), 12 * 3600)
        XCTAssertEqual(window(26), 12 * 3600)
        XCTAssertEqual(window(10), 2 * 3600)
        XCTAssertEqual(window(6), 2 * 3600)
        XCTAssertEqual(window(4), 30 * 60)
        XCTAssertEqual(window(2.55), 30 * 60, accuracy: 1)
        // 临时局（2.5 小时内）：1 小时以上给 10 分钟，1 小时内给 5 分钟
        XCTAssertEqual(window(2), 10 * 60)
        XCTAssertEqual(window(0.75), 5 * 60)
    }

    func testConfirmationNeverRunsPastTheLock() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for quarter in 2...(72 * 4) {
            let start = now.addingTimeInterval(Double(quarter) * 900)
            let respondBy = MatchTiming.respondBy(start: start, now: now)
            let lock = MatchTiming.lock(start: start, lastMinute: MatchTiming.isLastMinute(start: start, now: now))
            XCTAssertLessThanOrEqual(respondBy, lock, "开赛前 \(Double(quarter) / 4) 小时")
            XCTAssertGreaterThan(respondBy, now)
        }
    }

    func testLastMinuteThresholds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(MatchTiming.isLastMinute(start: now.addingTimeInterval(2.4 * 3600), now: now))
        XCTAssertFalse(MatchTiming.isLastMinute(start: now.addingTimeInterval(2.6 * 3600), now: now))
        XCTAssertFalse(MatchTiming.canRequest(start: now.addingTimeInterval(29 * 60), now: now))
        XCTAssertTrue(MatchTiming.canRequest(start: now.addingTimeInterval(30 * 60), now: now))
        let start = now.addingTimeInterval(5 * 3600)
        XCTAssertEqual(MatchTiming.lock(start: start, lastMinute: false), start.addingTimeInterval(-2 * 3600))
        XCTAssertEqual(MatchTiming.lock(start: start, lastMinute: true), start.addingTimeInterval(-20 * 60))
    }

    // MARK: Multi-party confirmation

    func testGameIsCreatedOnlyAfterEveryoneConfirms() async throws {
        let me = signUp()
        let ticket = try await submit()
        var offer = try openOffer(of: ticket)
        XCTAssertEqual(offer.seat(of: me.id)?.response, .pending)
        XCTAssertTrue(backend.games().isEmpty, "确认前不生成球局")
        XCTAssertTrue(backend.inbox().contains { $0.kind == .matchOffer && $0.relatedId == ticket.id })

        try await backend.respond(toOffer: offer.id, accept: true)
        XCTAssertTrue(backend.games().isEmpty, "对方还没确认")

        let opponent = try XCTUnwrap(offer.playerIds.first { $0 != me.id })
        backend.botRespond(offerId: offer.id, botId: opponent, accept: true)
        offer = try XCTUnwrap(backend.offer(id: offer.id))
        let gameId = try XCTUnwrap(offer.gameId)
        XCTAssertEqual(backend.ticket(id: ticket.id)?.status, .matched(gameId: gameId))
        XCTAssertEqual(Set(backend.game(id: gameId)?.playerIds ?? []), [me.id, opponent])
    }

    func testOpponentDeclineRequeuesWithoutPenaltyOrRevealingWho() async throws {
        let me = signUp()
        let ticket = try await submit(autoAccept: true)
        let offer = try openOffer(of: ticket)
        XCTAssertEqual(offer.seat(of: me.id)?.response, .accepted, "开启了自动接受")
        let opponent = try XCTUnwrap(offer.playerIds.first { $0 != me.id })
        let attendanceBefore = backend.user(id: opponent)?.attendance

        backend.botRespond(offerId: offer.id, botId: opponent, accept: false)

        XCTAssertEqual(backend.offer(id: offer.id)?.status, .failed)
        let updated = try XCTUnwrap(backend.ticket(id: ticket.id))
        XCTAssertTrue(updated.excludedUserIds.contains(opponent), "不再推荐同一个人")
        if let next = updated.offerId {
            XCTAssertFalse(backend.offer(id: next)?.playerIds.contains(opponent) ?? true)
        } else {
            XCTAssertEqual(updated.status, .searching)
            XCTAssertTrue(updated.hasPriority, "被退回的人优先排队")
        }
        XCTAssertEqual(backend.user(id: opponent)?.attendance, attendanceBefore, "拒绝不扣分")
        let name = try XCTUnwrap(backend.user(id: opponent)?.nickname)
        XCTAssertFalse(backend.inbox().contains { $0.title.contains(name) || $0.body.contains(name) }, "不透露是谁没确认")
    }

    func testMissingMyConfirmationPausesTicket() async throws {
        let me = signUp()
        let ticket = try await submit()
        let offer = try openOffer(of: ticket)
        let mySeat = try XCTUnwrap(offer.seat(of: me.id))
        backend.processMatchmaking(now: mySeat.respondBy.addingTimeInterval(60))
        XCTAssertEqual(backend.ticket(id: ticket.id)?.status, .paused)
        XCTAssertEqual(backend.offer(id: offer.id)?.status, .failed)
        XCTAssertEqual(backend.currentUser?.attendance, me.attendance, "超时不计入履约记录")

        try backend.resumeTicket(ticket.id)
        XCTAssertEqual(backend.ticket(id: ticket.id)?.isActive, true)
    }

    func testDoublesBackfillsBeforeLock() async throws {
        let me = signUp()
        let ticket = try await submit(.doubles, autoAccept: true)
        let original = try openOffer(of: ticket)
        XCTAssertEqual(original.seats.count, 4)
        let bots = original.playerIds.filter { $0 != me.id }
        backend.botRespond(offerId: original.id, botId: bots[0], accept: true)
        backend.botRespond(offerId: original.id, botId: bots[1], accept: false)

        let offer = try XCTUnwrap(backend.offer(id: original.id))
        XCTAssertTrue(offer.isOpen, "锁定前找人补位，不作废")
        XCTAssertFalse(offer.playerIds.contains(bots[1]))
        XCTAssertEqual(offer.seats.count, 4)
        XCTAssertEqual(offer.backfillCount, 1)
        XCTAssertEqual(offer.seat(of: me.id)?.response, .accepted)
        XCTAssertEqual(offer.seat(of: bots[0])?.response, .accepted, "已确认的人不用重新确认")
        XCTAssertEqual(Set(offer.teams.flatMap { $0 }), Set(offer.playerIds))
    }

    func testUnfilledOfferEndsAtLockWithoutRecord() async throws {
        let me = signUp()
        let ticket = try await submit(autoAccept: true)
        let offer = try openOffer(of: ticket)
        backend.processMatchmaking(now: offer.lockAt.addingTimeInterval(60))
        XCTAssertEqual(backend.offer(id: offer.id)?.status, .failed)
        XCTAssertEqual(backend.ticket(id: ticket.id)?.status, .expired)
        XCTAssertTrue(backend.games().isEmpty)
        XCTAssertEqual(backend.currentUser?.attendance, me.attendance, "没约成不计入任何记录")
    }

    func testDoublesOffersSinglesWhenOnlyTwoConfirmedAtLock() async throws {
        let me = signUp()
        let ticket = try await submit(.doubles, autoAccept: true)
        let offer = try openOffer(of: ticket)
        let partner = try XCTUnwrap(offer.playerIds.first { $0 != me.id })
        backend.botRespond(offerId: offer.id, botId: partner, accept: true)

        backend.processMatchmaking(now: offer.lockAt.addingTimeInterval(60))

        XCTAssertEqual(backend.offer(id: offer.id)?.status, .failed)
        let fallback = try XCTUnwrap(backend.ticket(id: ticket.id)?.offerId.flatMap { backend.offer(id: $0) })
        XCTAssertEqual(fallback.mode, .singles)
        XCTAssertEqual(Set(fallback.playerIds), [me.id, partner])
        XCTAssertTrue(fallback.seats.allSatisfy { $0.response == .pending }, "改打单打需要两人重新确认")
    }

    func testCancelWhileOfferedIsFreeAndReleasesOthers() async throws {
        let me = signUp()
        let ticket = try await submit()
        let offer = try openOffer(of: ticket)
        backend.cancelTicket(ticket.id)
        XCTAssertEqual(backend.ticket(id: ticket.id)?.status, .cancelled)
        XCTAssertEqual(backend.offer(id: offer.id)?.status, .failed)
        XCTAssertEqual(backend.currentUser?.attendance, me.attendance)
        XCTAssertTrue(backend.busyUserIds(during: ticket.slot).isEmpty, "其他人被释放，可以匹配别人")
    }

    // MARK: Request rules

    func testRequestNeedsThirtyMinutesAndNoOverlap() async throws {
        signUp()
        let soon = Date().addingTimeInterval(20 * 60)
        do {
            _ = try await submit(slot: TimeSlot(date: soon, startTime: soon, endTime: soon.addingTimeInterval(7200)))
            XCTFail("开赛前 30 分钟内不能发起")
        } catch {
            XCTAssertEqual(error as? BackendError, .tooLateToRequest)
        }
        _ = try await submit()
        do {
            _ = try await submit()
            XCTFail("同一时段不能重复发起")
        } catch {
            XCTAssertEqual(error as? BackendError, .ticketOverlap)
        }
    }

    func testLastMinuteRequestOnlyMatchesNearbyPlayersLookingNow() async throws {
        let me = signUp()
        let now = Date()
        let start = now.addingTimeInterval(90 * 60)
        let slot = TimeSlot(date: start, startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let ticket = try await submit(slot: slot, autoAccept: true, now: now)
        XCTAssertTrue(ticket.isLastMinute)
        XCTAssertEqual(ticket.radiusKm, MatchTiming.lastMinuteRadiusKm)
        XCTAssertEqual(ticket.deadline, start.addingTimeInterval(-20 * 60))
        if let offerId = ticket.offerId, let offer = backend.offer(id: offerId) {
            XCTAssertTrue(offer.isLastMinute)
            for id in offer.playerIds where id != me.id {
                XCTAssertTrue(backend.isLookingNow(id, now: now))
                XCTAssertLessThanOrEqual(backend.user(id: id)?.location?.distanceKm(to: .fallbackCenter) ?? .infinity,
                                         MatchTiming.lastMinuteRadiusKm)
            }
            let respondBy = try XCTUnwrap(offer.seats.first { $0.userId != me.id }?.respondBy)
            XCTAssertLessThanOrEqual(respondBy.timeIntervalSince(now), 10 * 60 + 1)
        }
    }

    // MARK: Venue compatibility

    func testMatchingRequiresSharedVenue() async throws {
        signUp()
        let address = PostalAddress(street: "123 Test Ave", city: "Arcadia", region: "CA", postalCode: "91006", countryCode: "US")
        // 没人去的新球馆（离所有模拟球友都很远）：约不到人
        let remote = try backend.addVenue(VenueCandidate(name: "Desert Court", location: .fallbackCenter.offsetBy(eastKm: 25, northKm: 0),
                                                         address: address), source: .player)
        let lonely = try await submit(courtIds: [remote.id])
        XCTAssertNil(lonely.offerId, "球馆对不上就不应匹配")
        backend.cancelTicket(lonely.id)

        // 别人常去的球馆旁边 100 米新加的场地：视为同一处，可以匹配
        let anchor = try XCTUnwrap(backend.nearestVenues(to: .fallbackCenter, count: 1).first)
        let annex = try backend.addVenue(VenueCandidate(name: "Annex Courts", location: anchor.location.offsetBy(eastKm: 0.1, northKm: 0),
                                                        address: address), source: .player)
        let ticket = try await submit(courtIds: [annex.id])
        let offer = try openOffer(of: ticket)
        XCTAssertEqual(offer.court.id, annex.id)
    }
}
