import Foundation

// MARK: - 正式后端：球局（房间）
/// 我的房间随 15 秒刷新一起拉取（逐个拉详情：名单和房间码）；附近的公开局按位置拉取，房间页打开时按需刷新。
/// 界面读缓存；水平范围、候补递补、过期关闭都在服务器上
extension MockBackend {

    struct RemoteRoom: Decodable {
        struct Person: Decodable {
            let id: String
            let nickname: String
            let rating: Double
            let waitlisted: Bool?
        }

        let id: String
        let mode: String
        let visibility: String
        let status: String
        let closedReason: String?
        let gameId: String?
        let startsAt: Date?
        let endsAt: Date?
        let levelMin: Int
        let levelMax: Int
        let tags: [String]
        let note: String
        let going: Int
        let waitlist: Int
        let lastActivityAt: Date?
        let owner: Person
        let venue: RemotePlace?
        let myStatus: String?
        /// 只有房间里的人和受邀的人拿得到
        let code: String?
        let members: [Person]?
    }

    // MARK: 刷新

    /// 我在里面（或候补、受邀）的房间；不在列表里的旧房间再拉一次，看是开局了还是关了
    func refreshRemoteRooms() async throws {
        guard let remote, let me = currentUserId else { return }
        let mine: [RemoteRoom] = try await remote.rpc("my_rooms")
        let ids = Set(mine.map(\.id))
        let stale = db.rooms.values.filter { room in
            !ids.contains(room.id) && room.status.isOpen
                && (room.contains(me) || room.isWaitlisted(me) || room.invitedUserIds.contains(me))
        }
        for id in ids.union(stale.map(\.id)) {
            try await loadRemoteRoom(id)
        }
    }

    /// 拉一个房间的详情写进缓存；看不到了（私密局、被屏蔽）就从缓存删掉
    func loadRemoteRoom(_ roomId: String) async throws {
        guard let remote, let me = currentUserId else { return }
        remoteRoomLoadedAt[roomId] = Date()
        guard let detail = try await remote.rpc("room_page", ["p_room": roomId], as: RemoteRoom?.self) else {
            if db.rooms.removeValue(forKey: roomId) != nil { emit(.roomsChanged) }
            return
        }
        let before = db.rooms[roomId]
        cacheRoom(detail, me: me)
        guard db.rooms[roomId] != before else { return }
        // 我在里面的房间被别人关掉（或我被移出）时提示一下
        if let before, before.status.isOpen, before.ownerId != me, let after = db.rooms[roomId] {
            if case .closed(let reason) = after.status, before.contains(me) || before.isWaitlisted(me) {
                emit(.roomClosed(roomCode: before.code, reason: reason))
            } else if after.status.isOpen, before.contains(me) || before.isWaitlisted(me), !after.contains(me), !after.isWaitlisted(me) {
                emit(.kicked(roomCode: before.code))
            }
        }
        scheduleSave()
        emit(.roomsChanged)
    }

    /// 附近的公开局（同一位置 60 秒内只拉一次）
    func loadRemoteRoomsNear(_ center: Coordinate, radiusKm: Double) {
        guard let remote, let me = currentUserId else { return }
        if let last = remoteNearbyRooms, Date().timeIntervalSince(last.at) < 60, last.center.distanceKm(to: center) < 2 { return }
        remoteNearbyRooms = (center: center, ids: remoteNearbyRooms?.ids ?? [], at: Date())
        Task {
            guard let rooms = try? await remote.rpc(
                "rooms_near", ["lat": center.latitude, "lng": center.longitude, "radius_km": radiusKm], as: [RemoteRoom].self
            ) else { return }
            for room in rooms { cacheRoom(room, me: me) }
            remoteNearbyRooms = (center: center, ids: rooms.map(\.id), at: Date())
            emit(.roomsChanged)
        }
    }

    /// 缓存里没有或超过 15 秒的房间，在后台刷新
    func refreshRemoteRoomIfStale(_ roomId: String) {
        guard isRemote, Date().timeIntervalSince(remoteRoomLoadedAt[roomId] ?? .distantPast) > 15 else { return }
        remoteRoomLoadedAt[roomId] = Date()
        Task { try? await loadRemoteRoom(roomId) }
    }

    // MARK: 操作

    func remoteCreateRoom(_ draft: RoomDraft) async throws -> Room {
        var args: [String: Any] = [
            "p_mode": draft.mode.serverValue,
            "p_visibility": draft.visibility == .publicListing ? "public" : "private",
            "p_level_min": draft.levelRange.lowerBound,
            "p_level_max": draft.levelRange.upperBound,
            "p_tags": draft.tags.map(\.serverValue),
            "p_note": draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        // 私密局可以先不定时间和球馆（传 null）
        args["p_venue"] = draft.court?.id ?? NSNull()
        args["p_starts_at"] = draft.slot.map { Self.iso($0.startTime) } ?? NSNull()
        args["p_ends_at"] = draft.slot.map { Self.iso($0.endTime) } ?? NSNull()
        let id: String = try await requireRemote().rpc("create_room", args)
        return try await reloadedRoom(id)
    }

    /// 凭房间码加入；找不到时报 roomNotFound，界面再去找同号的球群
    func remoteJoinRoom(code: String) async throws -> Room {
        let id: String = try await requireRemote().rpc("join_room_code", ["p_code": code])
        return try await reloadedRoom(id)
    }

    func remoteJoinPublicRoom(id: String) async throws -> Room {
        try await requireRemote().call("join_room", ["p_room": id])
        return try await reloadedRoom(id)
    }

    func remoteLeaveRoom(id: String) async throws {
        try await requireRemote().call("leave_room", ["p_room": id])
        // 先在缓存里退出，刷新时就不会当成“被移出”
        if let me = currentUserId {
            db.rooms[id]?.participants.removeAll { $0.userId == me }
            db.rooms[id]?.waitlist.removeAll { $0.userId == me }
        }
        try await loadRemoteRoom(id)
    }

    func remoteKick(_ userId: String, from roomId: String) async throws {
        try await requireRemote().call("remove_room_member", ["p_room": roomId, "p_user": userId])
        try await loadRemoteRoom(roomId)
    }

    /// 只能邀请球友；服务器会通知对方（不发私信卡片）
    func remoteInvite(_ userIds: [String], to roomId: String) async throws {
        try await requireRemote().call("invite_to_room", ["p_room": roomId, "p_users": userIds])
        try await loadRemoteRoom(roomId)
    }

    func remoteUpdateRoomDetails(roomId: String, court: BadmintonCourt?, slot: TimeSlot?) async throws {
        try await requireRemote().call("update_room", [
            "p_room": roomId, "p_venue": court?.id ?? NSNull(),
            "p_starts_at": slot.map { Self.iso($0.startTime) } ?? NSNull(), "p_ends_at": slot.map { Self.iso($0.endTime) } ?? NSNull(),
        ])
        try await loadRemoteRoom(roomId)
    }

    /// 开局：服务器生成正式球局，拉一次球局列表再返回
    func remoteStartRoom(id: String) async throws -> Game {
        let gameId: String = try await requireRemote().rpc("start_room", ["p_room": id])
        try await loadRemoteRoom(id)
        await refreshRemoteActivity()
        guard let game = db.games[gameId] else { throw BackendError.roomNotFound }
        return game
    }

    private func reloadedRoom(_ id: String) async throws -> Room {
        try await loadRemoteRoom(id)
        guard let room = db.rooms[id] else { throw BackendError.roomNotFound }
        return room
    }

    // MARK: 服务器数据 → 本地模型

    private func cacheRoom(_ info: RemoteRoom, me: String) {
        let existing = db.rooms[info.id]
        let participant = { (person: RemoteRoom.Person) -> RoomParticipant in
            self.cacheRemoteUser(id: person.id, nickname: person.nickname, rating: person.rating)
            let joinedAt = existing.flatMap { room in (room.participants + room.waitlist).first { $0.userId == person.id }?.joinedAt }
            let user = person.id == me ? self.currentUser : self.db.users[person.id]
            return user.map { RoomParticipant(user: $0, joinedAt: joinedAt ?? Date()) } ?? .anonymous(id: person.id)
        }
        let participants: [RoomParticipant]
        let waitlist: [RoomParticipant]
        if let members = info.members {
            participants = members.filter { $0.waitlisted != true }.map(participant)
            waitlist = members.filter { $0.waitlisted == true }.map(participant)
        } else {
            // 看不到名单（公开局的外人）：只有房主是谁和人数
            participants = [participant(info.owner)] + (1..<max(1, info.going)).map { .anonymous(id: "spot-\(info.id)-\($0)") }
            waitlist = (0..<info.waitlist).map { .anonymous(id: "wait-\(info.id)-\($0)") }
        }
        let status: RoomStatus
        switch info.status {
        case "started": status = .started(gameId: info.gameId ?? "")
        case "closed": status = .closed(RoomCloseReason(server: info.closedReason))
        default: status = .open
        }
        let slot = info.startsAt.flatMap { start in info.endsAt.map { TimeSlot(date: start, startTime: start, endTime: $0) } }
        let lastActivity = info.lastActivityAt ?? existing?.lastActivityAt ?? Date()
        db.rooms[info.id] = Room(
            id: info.id, code: info.code ?? existing?.code ?? "", ownerId: info.owner.id, mode: GameMode(server: info.mode),
            visibility: info.visibility == "public" ? .publicListing : .privateRoom,
            participants: participants, invitedUserIds: info.myStatus == "invited" ? [me] : [], waitlist: waitlist,
            court: info.venue.map(court(for:)), slot: slot, levelRange: info.levelMin...max(info.levelMin, info.levelMax),
            tags: info.tags.compactMap(RoomTag.init(server:)), note: info.note,
            createdAt: existing?.createdAt ?? lastActivity, lastActivityAt: lastActivity, status: status
        )
    }
}

extension RoomParticipant {
    /// 看不到名单时占位：只表示“这里有人”
    static func anonymous(id: String) -> RoomParticipant {
        RoomParticipant(user: User(id: id, nickname: String(localized: "球友"), phone: "", selfReportedLevel: 3), joinedAt: .distantPast)
    }

    var isAnonymous: Bool { userId.hasPrefix("spot-") || userId.hasPrefix("wait-") }
}

extension RoomTag {
    init?(server value: String) {
        guard let tag = RoomTag.allCases.first(where: { $0.serverValue == value }) else { return nil }
        self = tag
    }

    var serverValue: String {
        switch self {
        case .beginnerFriendly: return "beginner_friendly"
        case .casual: return "casual"
        case .competitive: return "competitive"
        case .womenFriendly: return "women_friendly"
        case .coaching: return "coaching"
        }
    }
}

extension RoomCloseReason {
    init(server value: String?) {
        switch value {
        case "owner_closed": self = .ownerClosed
        case "start_time_passed": self = .startTimePassed
        default: self = .expired
        }
    }
}
