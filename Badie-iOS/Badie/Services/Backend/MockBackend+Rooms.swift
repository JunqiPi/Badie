import Foundation

// MARK: - 房间与公开球局

extension MockBackend {

    func room(id: String) -> Room? { db.rooms[id] }

    func room(code: String) -> Room? {
        let normalized = Room.normalize(code)
        return db.rooms.values.first { $0.code == normalized }
    }

    /// 我参与（或在候补中）的开放房间
    func myOpenRooms() -> [Room] {
        guard let me = currentUserId else { return [] }
        return db.rooms.values
            .filter { $0.status.isOpen && ($0.contains(me) || $0.isWaitlisted(me)) }
            .sorted { ($0.slot?.startTime ?? $0.createdAt) < ($1.slot?.startTime ?? $1.createdAt) }
    }

    /// 附近的公开球局（排除屏蔽关系、已满且候补满的局）
    func publicRooms(radiusKm: Double) -> [Room] {
        guard !isRemote else { return [] }
        let me = currentUserId ?? ""
        let center = currentUser?.location ?? db.worldCenter
        let blocked = blockedIds()
        return db.rooms.values
            .filter { $0.visibility == .publicListing && $0.status.isOpen && !$0.isExpired() }
            .filter { !blocked.contains($0.ownerId) && !blockedIds(of: $0.ownerId).contains(me) }
            .filter { room in
                guard let court = room.court else { return true }
                return court.location.distanceKm(to: center) <= max(radiusKm, 3)
            }
            .sorted { ($0.slot?.startTime ?? .distantFuture) < ($1.slot?.startTime ?? .distantFuture) }
    }

    // MARK: Create

    func createRoom(_ draft: RoomDraft) async throws -> Room {
        let me = try requireUser()
        if let slot = draft.slot, case .invalid(let reason) = slot.validate() { throw BackendError.invalidSlot(reason) }
        if draft.visibility == .publicListing, draft.court == nil || draft.slot == nil {
            throw BackendError.invalidSlot(String(localized: "公开球局需要设置球馆和时间"))
        }
        await networkDelay()
        // 房主自己的水平必须在范围内
        let lower = min(draft.levelRange.lowerBound, me.displayLevel)
        let upper = max(draft.levelRange.upperBound, me.displayLevel)
        let room = Room(
            id: UUID().uuidString,
            code: Room.generateCode(excluding: Set(db.rooms.values.map(\.code))),
            ownerId: me.id,
            mode: draft.mode,
            visibility: draft.visibility,
            participants: [RoomParticipant(user: me)],
            invitedUserIds: [],
            waitlist: [],
            court: draft.court,
            slot: draft.slot,
            levelRange: lower...upper,
            tags: draft.tags,
            note: String(draft.note.prefix(80)),
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .open
        )
        db.rooms[room.id] = room
        scheduleSave()
        emit(.roomsChanged)

        // 公开球局：附近符合水平的球友陆续报名
        if room.visibility == .publicListing {
            scheduleBotInterest(roomId: room.id, delay: Double.random(in: 6...12))
            scheduleBotInterest(roomId: room.id, delay: Double.random(in: 16...28))
        }
        return room
    }

    /// 房主修改时间/球馆
    func updateRoomDetails(roomId: String, court: BadmintonCourt?, slot: TimeSlot?) async throws -> Room {
        let me = try requireUser()
        guard var room = db.rooms[roomId], room.status.isOpen else { throw BackendError.roomNotFound }
        guard room.ownerId == me.id else { throw BackendError.notRoomOwner }
        if let slot, case .invalid(let reason) = slot.validate() { throw BackendError.invalidSlot(reason) }
        await networkDelay()
        room.court = court
        room.slot = slot
        room.lastActivityAt = Date()
        db.rooms[roomId] = room
        scheduleSave()
        emit(.roomsChanged)
        return room
    }

    // MARK: Join / leave

    func joinRoom(code: String) async throws -> Room {
        let normalized = Room.normalize(code)
        guard Room.isValidCode(normalized) else { throw BackendError.roomNotFound }
        await networkDelay()
        guard let room = room(code: normalized) else { throw BackendError.roomNotFound }
        return try join(roomId: room.id, viaInvite: true)
    }

    func joinPublicRoom(id: String) async throws -> Room {
        await networkDelay()
        return try join(roomId: id, viaInvite: false)
    }

    private func join(roomId: String, viaInvite: Bool) throws -> Room {
        let me = try requireUser()
        guard var room = db.rooms[roomId] else { throw BackendError.roomNotFound }
        // 被房主屏蔽时表现为“房间不存在”，不暴露屏蔽关系
        guard !isBlockedEitherWay(me.id, room.ownerId) else { throw BackendError.roomNotFound }
        switch room.status {
        case .open: break
        case .started, .closed: throw BackendError.roomClosed
        }
        if room.isExpired() {
            closeRoom(&room, reason: room.visibility == .privateRoom ? .expired : .startTimePassed)
            throw BackendError.roomExpired
        }
        if room.contains(me.id) || room.isWaitlisted(me.id) { return room }
        // 私密房间只能通过房间码/邀请进入
        guard viaInvite || room.visibility == .publicListing else { throw BackendError.roomNotFound }

        let invited = room.invitedUserIds.contains(me.id)
        if room.visibility == .publicListing, !invited, !room.accepts(level: me.displayLevel) {
            throw BackendError.levelOutOfRange(room.levelRangeText)
        }
        if room.isFull {
            guard room.visibility == .publicListing, room.waitlist.count < Room.maxWaitlist else { throw BackendError.roomFull }
            room.waitlist.append(RoomParticipant(user: me))
        } else {
            room.participants.append(RoomParticipant(user: me))
        }
        room.invitedUserIds.removeAll { $0 == me.id }
        room.lastActivityAt = Date()
        db.rooms[room.id] = room
        scheduleSave()
        emit(.roomsChanged)

        if room.isFull, isBot(room.ownerId) {
            // 机器人房主满员后会开局
            simulate(after: Double.random(in: 2.5...4)) { [weak self] in
                self?.botStartRoom(roomId: room.id)
            }
        }
        return room
    }

    func leaveRoom(id: String) async throws {
        let me = try requireUser()
        guard var room = db.rooms[id] else { throw BackendError.roomNotFound }
        await networkDelay()
        if room.ownerId == me.id {
            closeRoom(&room, reason: .ownerClosed)
            return
        }
        room.waitlist.removeAll { $0.userId == me.id }
        if room.contains(me.id) {
            room.participants.removeAll { $0.userId == me.id }
            promoteFromWaitlist(&room)
        }
        room.lastActivityAt = Date()
        db.rooms[id] = room
        scheduleSave()
        emit(.roomsChanged)
    }

    /// 房主踢人（开局前）
    func kick(_ userId: String, from roomId: String) async throws {
        let me = try requireUser()
        guard var room = db.rooms[roomId], room.status.isOpen else { throw BackendError.roomNotFound }
        guard room.ownerId == me.id else { throw BackendError.notRoomOwner }
        guard userId != me.id else { return }
        await networkDelay()
        room.participants.removeAll { $0.userId == userId }
        room.waitlist.removeAll { $0.userId == userId }
        room.invitedUserIds.removeAll { $0 == userId }
        promoteFromWaitlist(&room)
        room.lastActivityAt = Date()
        db.rooms[roomId] = room
        notifyKicked(userId: userId, room: room)
        scheduleSave()
        emit(.roomsChanged)
    }

    private func notifyKicked(userId: String, room: Room) {
        addInbox(InboxItem(kind: .kicked, title: String(localized: "你已被移出房间 \(room.code)"),
                           body: String(localized: "房主调整了人员，去看看其他球局吧。"), relatedId: room.code), to: userId)
        if userId == currentUserId { emit(.kicked(roomCode: room.code)) }
    }

    private func promoteFromWaitlist(_ room: inout Room) {
        while !room.isFull, !room.waitlist.isEmpty {
            let next = room.waitlist.removeFirst()
            room.participants.append(next)
            addInbox(InboxItem(kind: .waitlistPromoted, title: String(localized: "候补成功，你已加入球局"),
                               body: room.court.map { "\($0.name) · \(room.slot?.formattedFull ?? "")" } ?? String(localized: "房间 \(room.code)"),
                               relatedId: room.code), to: next.userId)
        }
    }

    // MARK: Invite

    /// 邀请好友：发送房间邀请卡片，好友会陆续回应
    func invite(_ userIds: [String], to roomId: String) async throws {
        let me = try requireUser()
        guard var room = db.rooms[roomId], room.status.isOpen else { throw BackendError.roomNotFound }
        guard room.contains(me.id) else { throw BackendError.roomNotFound }
        await networkDelay()
        for userId in userIds where !room.contains(userId) && !room.invitedUserIds.contains(userId) {
            room.invitedUserIds.append(userId)
            let threadId = MessageThread.id(for: me.id, userId)
            let text = String(localized: "邀请你加入\(room.mode.title)房间") + (room.slot.map { " · \($0.formattedFull)" } ?? "")
            let message = Message(threadId: threadId, senderId: me.id, content: text, deliveredAt: Date(),
                                  kind: .roomInvite(code: room.code))
            appendMessage(message, participants: [me.id, userId], countsAsUnread: true)
            if let bot = db.bots[userId] {
                let accepts = Double.random(in: 0..<1) < bot.friendliness
                simulate(after: Double.random(in: 3...8)) { [weak self] in
                    self?.botRespondToInvite(botId: userId, roomId: roomId, accepts: accepts)
                }
            }
        }
        room.lastActivityAt = Date()
        db.rooms[roomId] = room
        scheduleSave()
        emit(.roomsChanged)
    }

    // MARK: Start / close

    func startRoom(id: String) async throws -> Game {
        let me = try requireUser()
        guard var room = db.rooms[id], room.status.isOpen else { throw BackendError.roomNotFound }
        guard room.ownerId == me.id else { throw BackendError.notRoomOwner }
        guard room.isReady else {
            throw BackendError.notEnoughPlayers(required: room.requiredPlayerCount, current: room.participants.count)
        }
        guard let court = room.court, let slot = room.slot else {
            throw BackendError.invalidSlot(String(localized: "开始前请先设置时间和球馆"))
        }
        await networkDelay()
        let game = makeGame(from: room, court: court, slot: slot)
        room.status = .started(gameId: game.id)
        db.rooms[id] = room
        db.games[game.id] = game
        ensureGameThread(for: game)
        scheduleSave()
        emit(.roomsChanged)
        emit(.gameCreated(game))
        emit(.gamesChanged)
        return game
    }

    func closeRoom(_ room: inout Room, reason: RoomCloseReason) {
        room.status = .closed(reason)
        db.rooms[room.id] = room
        let everyone = room.participants.map(\.userId) + room.waitlist.map(\.userId)
        for userId in everyone where userId != room.ownerId || reason != .ownerClosed {
            addInbox(InboxItem(kind: .roomClosed, title: String(localized: "房间 \(room.code) 已关闭"),
                               body: reason.message, relatedId: room.code), to: userId)
        }
        if let me = currentUserId, everyone.contains(me) {
            emit(.roomClosed(roomCode: room.code, reason: reason))
        }
        scheduleSave()
        emit(.roomsChanged)
    }

    /// 定期检查：私密房间 30 分钟无活动关闭，公开局过开始时间关闭
    func expireRooms(now: Date = Date()) {
        for var room in db.rooms.values where room.status.isOpen && room.isExpired(now: now) {
            closeRoom(&room, reason: room.visibility == .privateRoom ? .expired : .startTimePassed)
        }
        refreshPublicRooms(force: false)
    }

    func makeGame(from room: Room, court: BadmintonCourt, slot: TimeSlot) -> Game {
        let ids = room.participants.map(\.userId)
        let teams: [[String]]
        if room.mode == .doubles {
            teams = MatchingService.balancedTeams(players: room.participants.map { (id: $0.userId, level: $0.tier.rating) })
        } else {
            teams = ids.map { [$0] }
        }
        let game = Game(
            id: UUID().uuidString,
            mode: room.mode,
            court: court,
            slot: slot,
            playerIds: ids,
            teams: teams,
            hostId: room.ownerId,
            origin: .room(code: room.code),
            status: .confirmed,
            createdAt: Date(),
            checkIns: [:],
            paidPlayerIds: [],
            cost: CostSplit.estimate(court: court, slot: slot, mode: room.mode),
            result: nil,
            cancelledBy: nil,
            cancelledLate: false,
            reminderEnabled: false
        )
        for userId in ids where userId != room.ownerId {
            addInbox(InboxItem(kind: .gameConfirmed, title: String(localized: "球局已确认"),
                               body: "\(slot.formattedFull) · \(court.name)", relatedId: game.id), to: userId)
        }
        return game
    }

    // MARK: Bot behaviour

    private func scheduleBotInterest(roomId: String, delay: Double) {
        simulate(after: delay) { [weak self] in
            guard let self, var room = self.db.rooms[roomId], room.status.isOpen, !room.isFull else { return }
            let candidates = self.db.bots.keys.sorted()
                .compactMap { self.db.users[$0] }
                .filter { room.accepts(level: $0.displayLevel) && !room.contains($0.id) }
                .filter { !self.isBlockedEitherWay(room.ownerId, $0.id) }
            guard let joiner = candidates.randomElement() else { return }
            room.participants.append(RoomParticipant(user: joiner))
            room.lastActivityAt = Date()
            self.db.rooms[roomId] = room
            self.addInbox(InboxItem(kind: .roomJoined, title: String(localized: "\(joiner.nickname) 加入了你的球局"),
                                    body: String(localized: "\(joiner.displayLevelText) · 准时率 \(joiner.reputation.punctualityText)"),
                                    relatedId: room.code), to: room.ownerId)
            self.scheduleSave()
            self.emit(.roomsChanged)
        }
    }

    private func botRespondToInvite(botId: String, roomId: String, accepts: Bool) {
        guard var room = db.rooms[roomId], room.status.isOpen, let bot = db.users[botId], let me = currentUserId else { return }
        room.invitedUserIds.removeAll { $0 == botId }
        let threadId = MessageThread.id(for: me, botId)
        if accepts, !room.isFull, !room.contains(botId) {
            room.participants.append(RoomParticipant(user: bot))
            room.lastActivityAt = Date()
            db.rooms[roomId] = room
            appendMessage(Message(threadId: threadId, senderId: botId, content: "来了来了，已进房间 👋", deliveredAt: Date()),
                          participants: [me, botId], countsAsUnread: true)
            addInbox(InboxItem(kind: .roomJoined, title: String(localized: "\(bot.nickname) 接受了邀请"),
                               body: String(localized: "房间 \(room.code) · \(room.participants.count)/\(room.requiredPlayerCount) 人"),
                               relatedId: room.code), to: room.ownerId)
        } else {
            db.rooms[roomId] = room
            appendMessage(Message(threadId: threadId, senderId: botId,
                                  content: room.isFull ? "好像满员了，下次一定！" : "这次时间不太合适，下次约 🙏",
                                  deliveredAt: Date()),
                          participants: [me, botId], countsAsUnread: true)
        }
        scheduleSave()
        emit(.roomsChanged)
    }

    private func botStartRoom(roomId: String) {
        guard var room = db.rooms[roomId], room.status.isOpen, room.isReady,
              let court = room.court, let slot = room.slot else { return }
        let game = makeGame(from: room, court: court, slot: slot)
        room.status = .started(gameId: game.id)
        db.rooms[roomId] = room
        db.games[game.id] = game
        ensureGameThread(for: game)
        scheduleSave()
        emit(.roomsChanged)
        if let me = currentUserId, game.playerIds.contains(me) {
            emit(.gameCreated(game))
        }
        emit(.gamesChanged)
    }
}
