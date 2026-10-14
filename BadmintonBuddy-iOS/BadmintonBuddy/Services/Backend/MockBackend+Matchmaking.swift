import Foundation

// MARK: - 约球请求与多方确认
//
// 1. 用户提交请求（MatchTicket）后挂在后台持续匹配，不需要一直盯着屏幕。
// 2. 找到合适的人生成提议（MatchOffer），每个人在期限内确认；全部确认才成局。
// 3. 有人拒绝或超时：双打在锁定前找人补位；单打或补不上就作废，已确认的人优先重新排队。
//    谁拒绝的不告诉其他人；拒绝和超时都不公开扣分（超时只会让本人的请求暂停）。
// 4. 普通局开赛前 2 小时锁定；开赛前 2.5 小时内的请求是临时局，只找附近此刻也在找人的球友。

extension MockBackend {

    // MARK: Queries

    /// 我的约球请求：进行中的 + 最近 24 小时结束的
    func myTickets(now: Date = Date()) -> [MatchTicket] {
        guard let me = currentUserId else { return [] }
        return db.tickets.values
            .filter { $0.userId == me && ($0.isActive || $0.status == .paused || now.timeIntervalSince($0.createdAt) < 24 * 3600) }
            .sorted { $0.slot.startTime < $1.slot.startTime }
    }

    func ticket(id: String) -> MatchTicket? { db.tickets[id] }

    func offer(id: String) -> MatchOffer? { db.offers[id] }

    func offer(forGameId gameId: String) -> MatchOffer? {
        db.offers.values.first { $0.gameId == gameId }
    }

    /// 这个请求现在的情况：附近那天有空的人数、其中符合全部条件（水平/时间/球馆）的人数
    func poolSummary(for ticketId: String, now: Date = Date()) -> (available: Int, compatible: Int) {
        guard let ticket = db.tickets[ticketId], let owner = db.users[ticket.userId] else { return (0, 0) }
        let pool = matchmakingPool(for: ticket, now: now)
        let nearby = pool.filter { !$0.slots.isEmpty && $0.location.distanceKm(to: ticket.origin) <= ticket.radiusKm }
        let compatible = MatchingService.candidates(for: matchRequest(for: ticket, owner: owner), pool: pool)
        return (nearby.count, compatible.count)
    }

    /// 没人时的放宽建议（只给真能找到人的）
    func suggestions(for ticketId: String, now: Date = Date()) -> [MatchRelaxation] {
        guard let ticket = db.tickets[ticketId], let owner = db.users[ticket.userId] else { return [] }
        return MatchingService.suggestions(for: matchRequest(for: ticket, owner: owner),
                                           pool: matchmakingPool(for: ticket, now: now), now: now)
            .filter { relaxation in
                // 临时局不建议改天，改天就是普通请求了，由用户重新发起
                if ticket.isLastMinute, case .otherDay = relaxation { return false }
                return true
            }
    }

    // MARK: Submit / cancel / resume

    /// 发起约球请求。会立刻尝试匹配一次；找不到就挂着，有人了再通知。
    @discardableResult
    func submitTicket(mode: GameMode, slot: TimeSlot, courtIds: [String], skillTolerance: Int, radiusKm: Double,
                      origin: Coordinate, autoAccept: Bool, now: Date = Date()) async throws -> MatchTicket {
        let me = try requireUser()
        guard me.attendance.standing != .suspended else { throw BackendError.matchingSuspended }
        guard slot.endTime > now else { throw BackendError.invalidSlot("这个时间段已经过去了") }
        guard MatchTiming.canRequest(start: slot.startTime, now: now) else { throw BackendError.tooLateToRequest }
        var resolved: [String] = []
        for id in courtIds {
            if let venue = venue(id: id), !resolved.contains(venue.id) { resolved.append(venue.id) }
        }
        guard !resolved.isEmpty else { throw BackendError.venueNotFound }
        let overlapping = db.tickets.values.contains { other in
            other.userId == me.id && other.isActive
                && other.slot.startTime < slot.endTime && slot.startTime < other.slot.endTime
        }
        guard !overlapping else { throw BackendError.ticketOverlap }
        await networkDelay()

        let lastMinute = MatchTiming.isLastMinute(start: slot.startTime, now: now)
        let ticket = MatchTicket(
            id: "t-" + UUID().uuidString.prefix(8).lowercased(),
            userId: me.id,
            mode: mode,
            slot: slot,
            courtIds: resolved,
            skillTolerance: skillTolerance,
            radiusKm: lastMinute ? min(radiusKm, MatchTiming.lastMinuteRadiusKm) : radiusKm,
            origin: origin,
            autoAccept: autoAccept,
            isLastMinute: lastMinute,
            status: .searching,
            createdAt: now,
            deadline: MatchTiming.lock(start: slot.startTime, lastMinute: lastMinute),
            hasPriority: false,
            excludedUserIds: []
        )
        db.tickets[ticket.id] = ticket
        runMatchmaking(ticketId: ticket.id, now: now)
        scheduleSave()
        emit(.matchmakingChanged)
        return db.tickets[ticket.id] ?? ticket
    }

    /// 修改条件后继续找（放宽建议）：保留请求 ID
    func updateTicket(_ ticketId: String, slot: TimeSlot, skillTolerance: Int, radiusKm: Double, now: Date = Date()) throws {
        guard var ticket = db.tickets[ticketId], ticket.userId == currentUserId else { throw BackendError.offerClosed }
        guard ticket.status == .searching || ticket.status == .paused else { throw BackendError.offerClosed }
        guard MatchTiming.canRequest(start: slot.startTime, now: now) else { throw BackendError.tooLateToRequest }
        let lastMinute = MatchTiming.isLastMinute(start: slot.startTime, now: now)
        ticket.slot = slot
        ticket.skillTolerance = skillTolerance
        ticket.radiusKm = lastMinute ? min(radiusKm, MatchTiming.lastMinuteRadiusKm) : radiusKm
        ticket.isLastMinute = lastMinute
        ticket.deadline = MatchTiming.lock(start: slot.startTime, lastMinute: lastMinute)
        ticket.status = .searching
        db.tickets[ticketId] = ticket
        runMatchmaking(ticketId: ticketId, now: now)
        scheduleSave()
        emit(.matchmakingChanged)
    }

    /// 取消请求：如果有进行中的提议，视为这次来不了（不扣分）
    func cancelTicket(_ ticketId: String, now: Date = Date()) {
        guard var ticket = db.tickets[ticketId], ticket.userId == currentUserId, ticket.isActive || ticket.status == .paused else { return }
        let offerId = ticket.offerId
        ticket.status = .cancelled
        db.tickets[ticketId] = ticket
        if let offerId, var offer = db.offers[offerId], offer.isOpen,
           let index = offer.seats.firstIndex(where: { $0.ticketId == ticketId }) {
            offer.seats[index].response = .declined
            offer.seats[index].respondedAt = now
            db.offers[offerId] = offer
            handleVacancy(offerId: offerId, now: now)
        }
        scheduleSave()
        emit(.matchmakingChanged)
    }

    /// 暂停的请求继续找
    func resumeTicket(_ ticketId: String, now: Date = Date()) throws {
        guard var ticket = db.tickets[ticketId], ticket.userId == currentUserId, ticket.status == .paused else { return }
        guard now < ticket.deadline else { throw BackendError.tooLateToRequest }
        ticket.status = .searching
        db.tickets[ticketId] = ticket
        runMatchmaking(ticketId: ticketId, now: now)
        scheduleSave()
        emit(.matchmakingChanged)
    }

    // MARK: Respond

    /// 接受或拒绝提议。拒绝不扣分，请求会排除这组人继续找。
    func respond(toOffer offerId: String, accept: Bool, now: Date = Date()) async throws {
        let me = try requireUser()
        guard let offer = db.offers[offerId], offer.isOpen,
              let seat = offer.seat(of: me.id), seat.response == .pending else { throw BackendError.offerClosed }
        guard now <= seat.respondBy else {
            processMatchmaking(now: now)
            throw BackendError.offerClosed
        }
        await networkDelay()
        // 等待期间状态可能已变化
        guard var current = db.offers[offerId], current.isOpen,
              let index = current.seats.firstIndex(where: { $0.userId == me.id }),
              current.seats[index].response == .pending else { throw BackendError.offerClosed }
        current.seats[index].response = accept ? .accepted : .declined
        current.seats[index].respondedAt = now
        db.offers[offerId] = current

        if accept {
            finalizeIfReady(offerId: offerId, now: now)
        } else {
            if let ticketId = current.seats[index].ticketId, var ticket = db.tickets[ticketId] {
                ticket.excludedUserIds = Array(Set(ticket.excludedUserIds + current.activePlayerIds.filter { $0 != me.id })).sorted()
                ticket.status = .searching
                db.tickets[ticketId] = ticket
            }
            handleVacancy(offerId: offerId, now: now)
            if let ticketId = current.seats[index].ticketId {
                runMatchmaking(ticketId: ticketId, now: now)
            }
        }
        scheduleSave()
        emit(.matchmakingChanged)
    }

    /// 模拟球友的回复（测试也直接调用）
    func botRespond(offerId: String, botId: String, accept: Bool, now: Date = Date()) {
        guard var offer = db.offers[offerId], offer.isOpen,
              let index = offer.seats.firstIndex(where: { $0.userId == botId }),
              offer.seats[index].response == .pending else { return }
        offer.seats[index].response = accept ? .accepted : .declined
        offer.seats[index].respondedAt = now
        db.offers[offerId] = offer
        if accept {
            finalizeIfReady(offerId: offerId, now: now)
        } else {
            handleVacancy(offerId: offerId, now: now)
        }
        scheduleSave()
        emit(.matchmakingChanged)
    }

    // MARK: Periodic processing

    /// 处理到期：确认超时、锁定、请求过期，并为在找的请求再匹配一次
    func processMatchmaking(now: Date = Date()) {
        var changed = false

        for offerId in db.offers.keys.sorted() {
            guard var offer = db.offers[offerId], offer.isOpen else { continue }
            var expiredSeat = false
            for index in offer.seats.indices where offer.seats[index].response == .pending && offer.seats[index].respondBy < now {
                offer.seats[index].response = .expired
                expiredSeat = true
                // 本人没回复：请求暂停，避免继续给不在线的人发提议
                if let ticketId = offer.seats[index].ticketId, var ticket = db.tickets[ticketId] {
                    ticket.status = .paused
                    db.tickets[ticketId] = ticket
                    addInbox(InboxItem(kind: .matchUpdate, title: "你错过了一个匹配",
                                       body: "\(offer.slot.formattedFull) · \(offer.court.name)。请求已暂停，点开可以继续找。",
                                       relatedId: ticketId), to: ticket.userId)
                }
            }
            guard expiredSeat || offer.vacantCount > 0 || now >= offer.lockAt else { continue }
            let before = offer
            db.offers[offerId] = offer
            handleVacancy(offerId: offerId, now: now)
            if expiredSeat || db.offers[offerId] != before { changed = true }
        }

        for ticketId in db.tickets.keys.sorted() {
            guard var ticket = db.tickets[ticketId] else { continue }
            switch ticket.status {
            case .searching where now >= ticket.deadline,
                 .paused where now >= ticket.deadline:
                ticket.status = .expired
                db.tickets[ticketId] = ticket
                let canGoLastMinute = !ticket.isLastMinute && MatchTiming.canRequest(start: ticket.slot.startTime, now: now)
                addInbox(InboxItem(kind: .matchUpdate, title: "这次没约到人",
                                   body: "\(ticket.slot.formattedFull) 的请求已结束，不计入任何记录。"
                                       + (canGoLastMinute ? "还想打的话，可以转成临时局找附近正在找人的球友。" : ""),
                                   relatedId: ticketId), to: ticket.userId)
                changed = true
            case .searching:
                if runMatchmaking(ticketId: ticketId, now: now) != nil { changed = true }
            default:
                break
            }
        }

        if changed {
            scheduleSave()
            emit(.matchmakingChanged)
        }
    }

    // MARK: Matching

    /// 为一个在找的请求寻找方案；找到就生成提议
    @discardableResult
    func runMatchmaking(ticketId: String, now: Date = Date()) -> MatchOffer? {
        guard var ticket = db.tickets[ticketId], ticket.status == .searching,
              let owner = db.users[ticket.userId], now < ticket.deadline else { return nil }
        let request = matchRequest(for: ticket, owner: owner)
        let pool = matchmakingPool(for: ticket, now: now)
        let window = MatchTiming.minimumResponseWindow(lastMinute: ticket.isLastMinute)
        guard let proposal = MatchingService.proposals(for: request, pool: pool, limit: 3).first(where: { proposal in
            MatchTiming.respondBy(start: proposal.slot.startTime, now: now).timeIntervalSince(now) >= window
        }) else { return nil }

        let respondBy = MatchTiming.respondBy(start: proposal.slot.startTime, now: now)
        let ownerSeat = MatchOffer.Seat(userId: owner.id, ticketId: ticket.id,
                                        response: ticket.autoAccept ? .accepted : .pending,
                                        respondBy: respondBy, respondedAt: ticket.autoAccept ? now : nil)
        let otherSeats = proposal.others.map {
            MatchOffer.Seat(userId: $0.user.id, ticketId: nil, response: .pending, respondBy: respondBy, respondedAt: nil)
        }
        let offer = MatchOffer(
            id: "o-" + UUID().uuidString.prefix(8).lowercased(),
            mode: proposal.mode,
            slot: proposal.slot,
            commonOverlap: proposal.commonOverlap,
            court: proposal.court,
            teams: proposal.teams,
            seats: [ownerSeat] + otherSeats,
            cost: proposal.cost,
            compatibility: proposal.compatibility,
            createdAt: now,
            lockAt: MatchTiming.lock(start: proposal.slot.startTime, lastMinute: ticket.isLastMinute),
            isLastMinute: ticket.isLastMinute,
            status: .open,
            backfillCount: 0
        )
        db.offers[offer.id] = offer
        ticket.status = .offered(offerId: offer.id)
        ticket.hasPriority = false
        db.tickets[ticket.id] = ticket

        let summary = "\(offer.slot.formattedFull) · \(offer.court.name)"
        if ticket.autoAccept {
            addInbox(InboxItem(kind: .matchOffer, title: "找到搭子了，已替你接受",
                               body: "\(summary)。等其他人确认后就约成了。", relatedId: ticket.id), to: owner.id)
        } else {
            addInbox(InboxItem(kind: .matchOffer, title: "找到搭子了，等你确认",
                               body: "\(summary)。请在\(DateText.deadline(respondBy, now: now))前确认。", relatedId: ticket.id), to: owner.id)
        }
        for seat in otherSeats { scheduleBotResponse(offerId: offer.id, botId: seat.userId) }
        return offer
    }

    func matchRequest(for ticket: MatchTicket, owner: User) -> MatchRequest {
        var excluded = Set(ticket.excludedUserIds)
        excluded.formUnion(blockedIds(of: owner.id))
        excluded.formUnion(db.bots.keys.filter { blockedIds(of: $0).contains(owner.id) })
        return MatchRequest(
            mode: ticket.mode,
            slot: ticket.slot,
            courts: ticket.courtIds.compactMap { venue(id: $0) },
            skillTolerance: ticket.skillTolerance,
            userId: owner.id,
            userLevel: owner.displayLevel,
            userLocation: ticket.origin,
            radiusKm: ticket.radiusKm,
            excludedUserIds: excluded,
            userRating: owner.displayTier.rating
        )
    }

    /// 匹配池：有空的模拟球友（排除已在别的提议或球局里的人）
    func matchmakingPool(for ticket: MatchTicket, now: Date) -> [PlayerAvailability] {
        let busy = busyUserIds(during: ticket.slot)
        return db.bots.keys.sorted().compactMap { id -> PlayerAvailability? in
            guard !busy.contains(id), let user = db.users[id], let location = user.location else { return nil }
            var slots: [TimeSlot]
            if ticket.isLastMinute {
                // 临时局：只找此刻也在找人的球友
                guard isLookingNow(id, now: now) else { return nil }
                slots = [ticket.slot]
            } else {
                slots = availability(for: id, on: ticket.slot.date)
                if let arrival = simulatedArrival(of: id, for: ticket), now >= arrival {
                    slots.append(ticket.slot)
                }
            }
            return PlayerAvailability(user: user, location: location, slots: slots, venues: acceptableVenues(for: id))
        }
    }

    /// 模拟球友能去的球馆：常去的 + 自己 10 公里内对外开放的
    func acceptableVenues(for botId: String) -> [BadmintonCourt] {
        guard let location = db.users[botId]?.location else { return [] }
        let favorites = (db.favoriteCourtIds[botId] ?? []).compactMap { venue(id: $0) }
        let nearby = worldVenues.filter { $0.distance(from: location) <= 10 }
        var seen = Set<String>()
        return (favorites + nearby).filter { seen.insert($0.id).inserted }
    }

    /// 某个时间段已被占用的人：在进行中的提议里，或已有重叠的球局
    func busyUserIds(during slot: TimeSlot) -> Set<String> {
        var busy = Set<String>()
        for offer in db.offers.values where offer.isOpen {
            busy.formUnion(offer.activePlayerIds)
        }
        for game in db.games.values where game.status == .confirmed
            && game.slot.startTime < slot.endTime && slot.startTime < game.slot.endTime {
            busy.formUnion(game.playerIds)
        }
        return busy
    }

    /// 模拟：此刻也在找临时局的球友（每半小时换一批，约三成）
    func isLookingNow(_ botId: String, now: Date) -> Bool {
        var rng = SeededGenerator("\(botId)-now-\(Int(now.timeIntervalSince1970 / 1800))")
        return Double.random(in: 0..<1, using: &rng) < 0.3
    }

    /// 模拟：请求挂出去以后，陆续有球友发布同一时段的空闲（仅在开启模拟时）
    private func simulatedArrival(of botId: String, for ticket: MatchTicket) -> Date? {
        guard simulationEnabled else { return nil }
        var rng = SeededGenerator("\(ticket.id)-\(botId)")
        guard Double.random(in: 0..<1, using: &rng) < 0.15 else { return nil }
        let delay = Double.random(in: 60...1800, using: &rng) / max(simulationSpeed, 0.01)
        return ticket.createdAt.addingTimeInterval(delay)
    }

    private func scheduleBotResponse(offerId: String, botId: String) {
        guard let bot = db.bots[botId] else { return }
        let accept = Double.random(in: 0..<1) < bot.friendliness
        simulate(after: Double.random(in: 4...15)) { [weak self] in
            self?.botRespond(offerId: offerId, botId: botId, accept: accept)
        }
    }

    // MARK: Vacancies, backfill, finalize

    /// 有人没来（拒绝/超时/取消）：双打在锁定前补位；补不上或到点了就作废并让大家重新排队
    func handleVacancy(offerId: String, now: Date) {
        guard var offer = db.offers[offerId], offer.isOpen else { return }
        // 真实用户都已离开（只剩模拟球友）：没有继续的意义
        guard offer.seats.contains(where: { $0.ticketId != nil && !$0.isVacant }) else {
            failOffer(offerId: offerId, now: now)
            return
        }
        if offer.vacantCount == 0 {
            if offer.isFullyAccepted {
                finalizeIfReady(offerId: offerId, now: now)
            } else if now >= offer.lockAt {
                failOffer(offerId: offerId, now: now)
            }
            return
        }
        // 单打：没有可补的位置，直接让双方重新排队（另找对手比等补位更快）
        guard offer.mode == .doubles, now < offer.lockAt else {
            failOffer(offerId: offerId, now: now)
            return
        }
        // 双打：逐个座位找人补
        while let vacant = offer.seats.firstIndex(where: \.isVacant) {
            guard offer.backfillCount < MatchOffer.maximumBackfills,
                  let replacement = backfillCandidate(for: offer, now: now) else { break }
            let leaving = offer.seats[vacant].userId
            let respondBy = MatchTiming.respondBy(start: offer.slot.startTime, now: now)
            guard respondBy.timeIntervalSince(now) >= MatchTiming.minimumResponseWindow(lastMinute: offer.isLastMinute) else { break }
            offer.seats[vacant] = MatchOffer.Seat(userId: replacement.id, ticketId: nil, response: .pending,
                                                  respondBy: respondBy, respondedAt: nil)
            offer.teams = offer.teams.map { $0.map { $0 == leaving ? replacement.id : $0 } }
            offer.teams = MatchingService.balancedTeams(players: offer.playerIds.compactMap { id in
                db.users[id].map { (id: id, level: $0.displayTier.rating) }
            })
            offer.backfillCount += 1
            db.offers[offerId] = offer
            scheduleBotResponse(offerId: offerId, botId: replacement.id)
            for seat in offer.seats where seat.ticketId != nil && seat.response == .accepted {
                addInbox(InboxItem(kind: .matchUpdate, title: "有位球友这次来不了，已找人补上",
                                   body: "\(offer.slot.formattedFull) · \(offer.court.name)。新球友确认后就约成了。",
                                   relatedId: seat.ticketId), to: seat.userId)
            }
        }
        db.offers[offerId] = offer
        // 还有空位：锁定前继续等补位（定时处理会再试），到点就作废
        if offer.vacantCount > 0 && now >= offer.lockAt {
            failOffer(offerId: offerId, now: now)
        }
    }

    /// 双打补位人选：与局中所有人的水平、时间、球馆都合得来
    private func backfillCandidate(for offer: MatchOffer, now: Date) -> User? {
        let inOffer = Set(offer.playerIds)
        let owners = offer.seats.compactMap { $0.ticketId.flatMap { db.tickets[$0] } }
        guard let anchor = owners.first, let owner = db.users[anchor.userId] else { return nil }
        var ticket = anchor
        ticket.slot = offer.slot
        var request = matchRequest(for: ticket, owner: owner)
        request.courts = [offer.court]
        request.excludedUserIds.formUnion(inOffer)
        for other in owners.dropFirst() { request.excludedUserIds.formUnion(other.excludedUserIds) }
        let pool = matchmakingPool(for: ticket, now: now)
        let levels = offer.activePlayerIds.compactMap { db.users[$0]?.displayLevel }
        return MatchingService.candidates(for: request, pool: pool)
            .first { candidate in levels.allSatisfy { abs($0 - candidate.user.displayLevel) <= max(2, anchor.skillTolerance) } }?
            .user
    }

    /// 作废提议：已确认的人优先重新排队；双打到点只剩 2 人确认时，改为问他们要不要打单打
    private func failOffer(offerId: String, now: Date) {
        guard var offer = db.offers[offerId], offer.isOpen else { return }
        offer.status = .failed
        db.offers[offerId] = offer

        let accepted = offer.seats.filter { $0.response == .accepted }
        if offer.mode == .doubles, accepted.count == 2, accepted.contains(where: { $0.ticketId != nil }),
           offerSinglesFallback(from: offer, players: accepted, now: now) {
            return
        }

        let vacated = offer.seats.filter(\.isVacant).map(\.userId)
        for seat in offer.seats {
            guard let ticketId = seat.ticketId, var ticket = db.tickets[ticketId], ticket.offerId == offerId else { continue }
            switch seat.response {
            case .accepted, .pending:
                ticket.status = .searching
                ticket.hasPriority = seat.response == .accepted
                ticket.excludedUserIds = Array(Set(ticket.excludedUserIds + vacated)).sorted()
                db.tickets[ticketId] = ticket
                if now < ticket.deadline {
                    addInbox(InboxItem(kind: .matchUpdate, title: "这次没凑成，继续帮你找",
                                       body: "\(offer.slot.formattedFull) · \(offer.court.name)。你会被优先安排，不计入任何记录。",
                                       relatedId: ticketId), to: ticket.userId)
                    runMatchmaking(ticketId: ticketId, now: now)
                }
            case .declined, .expired:
                break
            }
        }
    }

    /// 双打凑不齐时的备选：已确认的两人改打单打（需要两人重新确认）
    private func offerSinglesFallback(from offer: MatchOffer, players: [MatchOffer.Seat], now: Date) -> Bool {
        let start = offer.slot.startTime
        guard start.timeIntervalSince(now) > MatchTiming.lastMinuteConfirmBefore + MatchTiming.minimumResponseWindow(lastMinute: true) else {
            return false
        }
        let respondBy = min(now.addingTimeInterval(10 * 60), start.addingTimeInterval(-MatchTiming.lastMinuteConfirmBefore))
        let seats = players.map { MatchOffer.Seat(userId: $0.userId, ticketId: $0.ticketId, response: .pending,
                                                  respondBy: respondBy, respondedAt: nil) }
        let singles = MatchOffer(
            id: "o-" + UUID().uuidString.prefix(8).lowercased(),
            mode: .singles,
            slot: offer.slot,
            commonOverlap: offer.commonOverlap,
            court: offer.court,
            teams: players.map { [$0.userId] },
            seats: seats,
            cost: CostSplit.estimate(court: offer.court, slot: offer.slot, mode: .singles),
            compatibility: offer.compatibility,
            createdAt: now,
            lockAt: start.addingTimeInterval(-MatchTiming.lastMinuteConfirmBefore),
            isLastMinute: true,
            status: .open,
            backfillCount: 0
        )
        db.offers[singles.id] = singles
        for seat in seats {
            if let ticketId = seat.ticketId, var ticket = db.tickets[ticketId] {
                ticket.status = .offered(offerId: singles.id)
                db.tickets[ticketId] = ticket
                addInbox(InboxItem(kind: .matchOffer, title: "双打没凑齐，改打单打吗？",
                                   body: "\(offer.slot.formattedFull) · \(offer.court.name)。请在\(DateText.deadline(respondBy, now: now))前确认，不想打也不影响记录。",
                                   relatedId: ticketId), to: seat.userId)
            } else {
                scheduleBotResponse(offerId: singles.id, botId: seat.userId)
            }
        }
        return true
    }

    /// 全部确认 → 成局
    @discardableResult
    func finalizeIfReady(offerId: String, now: Date) -> Game? {
        guard var offer = db.offers[offerId], offer.isOpen, offer.isFullyAccepted else { return nil }
        let host = offer.seats.first { $0.ticketId != nil }?.userId ?? offer.seats[0].userId
        let game = Game(
            id: UUID().uuidString,
            mode: offer.mode,
            court: offer.court,
            slot: offer.slot,
            playerIds: offer.playerIds,
            teams: offer.teams,
            hostId: host,
            origin: .quickMatch,
            status: .confirmed,
            createdAt: now,
            checkIns: [:],
            paidPlayerIds: [],
            cost: offer.cost,
            result: nil,
            cancelledBy: nil,
            cancelledLate: false,
            reminderEnabled: false
        )
        db.games[game.id] = game
        offer.status = .confirmed(gameId: game.id)
        db.offers[offerId] = offer

        for seat in offer.seats {
            guard let ticketId = seat.ticketId, var ticket = db.tickets[ticketId] else { continue }
            ticket.status = .matched(gameId: game.id)
            db.tickets[ticketId] = ticket
            addInbox(InboxItem(kind: .gameConfirmed, title: "约成了！",
                               body: "\(offer.slot.formattedFull) · \(offer.court.name)。开赛前 2 小时内取消会计入履约记录。",
                               relatedId: game.id), to: seat.userId)
        }
        scheduleSave()
        emit(.gameCreated(game))
        emit(.gamesChanged)

        // 球局群聊：成局后所有人在这里沟通（不需要先加好友），赛后 48 小时关闭
        let thread = ensureGameThread(for: game)
        if let me = currentUserId, offer.playerIds.contains(me),
           let first = offer.playerIds.first(where: { $0 != me && isBot($0) }) {
            postBotMessage("约上了！\(offer.slot.formattedDate) \(DateText.time(offer.slot.startTime)) \(offer.court.name) 见～",
                           from: first, in: thread.id)
        }
        return game
    }
}
