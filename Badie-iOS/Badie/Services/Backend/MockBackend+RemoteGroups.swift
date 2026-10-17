import Foundation

// MARK: - 正式后端：球群
/// 我的球群和场次随 15 秒刷新一起拉取；别的球群在打开、搜附近、输群号时按需拉取。
/// 界面读缓存（同步），过期的会在后台刷新，刷新完通过 groupsChanged 通知界面
extension MockBackend {

    struct RemoteSchedule: Decodable {
        let weekday: Int
        let start: Int
        let end: Int
        let capacity: Int
        let fee: String?
    }

    struct RemoteGroupSummary: Decodable {
        struct Venue: Decodable {
            let id: String
            let name: String
            let city: String?
            let tz: String?
        }

        struct Activity: Decodable {
            let sessions: Int
            let average: Double
        }

        let id: String
        let name: String
        let summary: String?
        let levelMin: Int
        let levelMax: Int
        let joinPolicy: String
        let venue: Venue
        let schedules: [RemoteSchedule]?
        let activity: Activity
        let myRole: String?
    }

    struct RemoteGroupDetail: Decodable {
        struct Session: Decodable {
            struct Player: Decodable {
                let id: String
                let nickname: String
                let waitlisted: Bool
            }

            let id: String
            let startsAt: Date
            let endsAt: Date
            let capacity: Int
            let cancelled: Bool
            let confirmed: Int
            let waitlist: Int
            let myStatus: String?
            let players: [Player]?
        }

        struct Member: Decodable {
            let id: String
            let nickname: String
            let rating: Double
            let role: String?
        }

        let id: String
        let name: String
        let summary: String?
        let levelMin: Int
        let levelMax: Int
        let joinPolicy: String
        let venue: RemoteGroupSummary.Venue
        let schedules: [RemoteSchedule]?
        let activity: RemoteGroupSummary.Activity
        let myRole: String?
        let inviteCode: String?
        let sessions: [Session]?
        let members: [Member]?
        let pending: [Member]?
    }

    private struct RemoteMyGroups: Decodable {
        let groups: [RemoteGroupSummary]
    }

    // MARK: 刷新

    /// 我加入（含待审核）的球群：逐个拉详情（场次、成员、群号）
    func refreshRemoteGroups() async throws {
        guard let remote, let me = currentUserId else { return }
        let mine: RemoteMyGroups = try await remote.rpc("my_groups")
        for summary in mine.groups {
            try await loadRemoteGroup(summary.id)
        }
        // 已经不在的群：从缓存里去掉成员身份
        let ids = Set(mine.groups.map(\.id))
        for (id, group) in db.groups where !ids.contains(id) && (group.isMember(me) || group.isPending(me)) {
            db.groups[id]?.memberIds.removeAll { $0 == me }
            db.groups[id]?.organizerIds.removeAll { $0 == me }
            db.groups[id]?.pendingIds.removeAll { $0 == me }
            emit(.groupsChanged)
        }
    }

    /// 拉一个球群的详情写进缓存；不存在（或被屏蔽）时从缓存删掉
    func loadRemoteGroup(_ groupId: String) async throws {
        guard let remote, let me = currentUserId else { return }
        remoteGroupLoadedAt[groupId] = Date()
        let detail = try await remote.rpc("group_page", ["p_group": groupId], as: RemoteGroupDetail?.self)
        guard let detail else {
            db.groups[groupId] = nil
            emit(.groupsChanged)
            return
        }
        cacheGroup(detail, me: me)
        scheduleSave()
        emit(.groupsChanged)
    }

    /// 附近的球群（同一位置 60 秒内只拉一次）
    func loadRemoteGroupsNear(_ center: Coordinate, radiusKm: Double) {
        guard let remote, currentUserId != nil else { return }
        if let last = remoteNearbyGroups, Date().timeIntervalSince(last.at) < 60, last.center.distanceKm(to: center) < 2 { return }
        remoteNearbyGroups = (center: center, ids: remoteNearbyGroups?.ids ?? [], at: Date())
        Task {
            guard let groups = try? await remote.rpc(
                "groups_near", ["lat": center.latitude, "lng": center.longitude, "radius_km": radiusKm], as: [RemoteGroupSummary].self
            ), let me = currentUserId else { return }
            for summary in groups { cacheGroup(summary, me: me) }
            remoteNearbyGroups = (center: center, ids: groups.map(\.id), at: Date())
            emit(.groupsChanged)
        }
    }

    /// 缓存里没有或超过 60 秒的球群，在后台刷新
    func refreshRemoteGroupIfStale(_ groupId: String) {
        guard isRemote, Date().timeIntervalSince(remoteGroupLoadedAt[groupId] ?? .distantPast) > 60 else { return }
        remoteGroupLoadedAt[groupId] = Date()
        Task { try? await loadRemoteGroup(groupId) }
    }

    // MARK: 操作

    func remoteCreateGroup(name: String, venueId: String, schedules: [GroupSchedule], levelRange: ClosedRange<Int>,
                           joinPolicy: PlayGroup.JoinPolicy, summary: String) async throws -> PlayGroup {
        let remote = try requireRemote()
        let id: String = try await remote.rpc("create_group", [
            "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_venue": venueId,
            "p_summary": summary.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_level_min": levelRange.lowerBound,
            "p_level_max": levelRange.upperBound,
            "p_policy": joinPolicy.rawValue,
            "p_schedules": schedules.map { schedule -> [String: Any] in
                ["weekday": schedule.weekday - 1, "start": schedule.startMinutes, "end": schedule.endMinutes,
                 "capacity": schedule.capacity, "fee": schedule.feeNote ?? ""]
            },
        ])
        try await loadRemoteGroup(id)
        guard let group = db.groups[id] else { throw BackendError.groupNotFound }
        return group
    }

    /// 输群号找球群
    func remoteFindGroup(code: String) async throws -> PlayGroup? {
        let remote = try requireRemote()
        guard let id = try await remote.rpc("find_group", ["p_code": code], as: String?.self) else { return nil }
        try await loadRemoteGroup(id)
        return db.groups[id]
    }

    func remoteJoinGroup(_ groupId: String) async throws -> PlayGroup {
        try await requireRemote().call("join_group", ["p_group": groupId])
        try await loadRemoteGroup(groupId)
        guard let group = db.groups[groupId] else { throw BackendError.groupNotFound }
        return group
    }

    func remoteLeaveGroup(_ groupId: String) async throws {
        try await requireRemote().call("leave_group", ["p_group": groupId])
        try await loadRemoteGroup(groupId)
        try await refreshRemoteSocial()
    }

    func remoteApprove(_ userId: String, groupId: String) async throws {
        try await requireRemote().call("respond_join_request", ["p_group": groupId, "p_user": userId, "p_accept": true])
        try await loadRemoteGroup(groupId)
    }

    func remoteSignUp(sessionId: String) async throws -> SignupResult {
        guard let groupId = db.groupSessions[sessionId]?.groupId else { throw BackendError.sessionClosed }
        try await requireRemote().call("sign_up_session", ["p_session": sessionId])
        try await loadRemoteGroup(groupId)
        guard let me = currentUserId, let session = db.groupSessions[sessionId] else { throw BackendError.sessionClosed }
        if case .waitlisted(let position) = session.status(of: me) { return .waitlisted(position: position) }
        return .confirmed
    }

    func remoteCancelSignup(sessionId: String) async throws {
        guard let groupId = db.groupSessions[sessionId]?.groupId else { throw BackendError.sessionClosed }
        try await requireRemote().call("cancel_signup", ["p_session": sessionId])
        try await loadRemoteGroup(groupId)
    }

    func remoteCancelSession(_ sessionId: String) async throws {
        guard let groupId = db.groupSessions[sessionId]?.groupId else { throw BackendError.sessionClosed }
        try await requireRemote().call("cancel_session", ["p_session": sessionId])
        try await loadRemoteGroup(groupId)
    }

    // MARK: 服务器数据 → 本地模型

    private func cacheGroup(_ summary: RemoteGroupSummary, me: String) {
        cacheGroup(id: summary.id, name: summary.name, summary: summary.summary, levels: summary.levelMin...max(summary.levelMin, summary.levelMax),
                   joinPolicy: summary.joinPolicy, venue: summary.venue, schedules: summary.schedules ?? [], activity: summary.activity,
                   myRole: summary.myRole, inviteCode: nil, members: nil, pending: nil, me: me)
    }

    private func cacheGroup(_ detail: RemoteGroupDetail, me: String) {
        cacheGroup(id: detail.id, name: detail.name, summary: detail.summary, levels: detail.levelMin...max(detail.levelMin, detail.levelMax),
                   joinPolicy: detail.joinPolicy, venue: detail.venue, schedules: detail.schedules ?? [], activity: detail.activity,
                   myRole: detail.myRole, inviteCode: detail.inviteCode, members: detail.members, pending: detail.pending, me: me)
        guard let group = db.groups[detail.id] else { return }
        let calendar = venue(id: group.venueId)?.calendar ?? .current
        // 这个群的场次以服务器为准
        db.groupSessions = db.groupSessions.filter { $0.value.groupId != detail.id }
        for session in detail.sessions ?? [] {
            for player in session.players ?? [] { cacheRemoteUser(id: player.id, nickname: player.nickname, rating: nil) }
            var signedUp = session.players.map { $0.filter { !$0.waitlisted }.map(\.id) }
                ?? (0..<session.confirmed).map { "spot-\(session.id)-\($0)" }
            var waitlist = session.players.map { $0.filter(\.waitlisted).map(\.id) }
                ?? (0..<session.waitlist).map { "wait-\(session.id)-\($0)" }
            // 看不到名单时（非成员）用占位，只保证人数和我的位置对
            if session.myStatus == "confirmed", !signedUp.contains(me) {
                if signedUp.isEmpty { signedUp.append(me) } else { signedUp[signedUp.count - 1] = me }
            }
            if let status = session.myStatus, status.hasPrefix("waitlisted"), !waitlist.contains(me) {
                let position = Int(status.split(separator: ":").last ?? "") ?? waitlist.count
                let index = min(max(position - 1, 0), waitlist.count)
                if index < waitlist.count { waitlist[index] = me } else { waitlist.append(me) }
            }
            let weekday = calendar.component(.weekday, from: session.startsAt)
            let start = calendar.component(.hour, from: session.startsAt) * 60 + calendar.component(.minute, from: session.startsAt)
            let schedule = group.schedules.first { $0.weekday == weekday && $0.startMinutes == start }
            db.groupSessions[session.id] = GroupSession(
                id: session.id, groupId: detail.id, scheduleId: schedule?.id ?? "",
                slot: TimeSlot(date: session.startsAt, startTime: session.startsAt, endTime: session.endsAt),
                capacity: session.capacity, signedUp: signedUp, waitlist: waitlist, isCancelled: session.cancelled
            )
        }
    }

    private func cacheGroup(id: String, name: String, summary: String?, levels: ClosedRange<Int>, joinPolicy: String,
                            venue place: RemoteGroupSummary.Venue, schedules: [RemoteSchedule], activity: RemoteGroupSummary.Activity,
                            myRole: String?, inviteCode: String?, members: [RemoteGroupDetail.Member]?,
                            pending: [RemoteGroupDetail.Member]?, me: String) {
        let existing = db.groups[id]
        for member in (members ?? []) + (pending ?? []) {
            cacheRemoteUser(id: member.id, nickname: member.nickname, rating: member.rating)
        }
        if venue(id: place.id) == nil {
            db.venues[place.id] = BadmintonCourt(
                id: place.id, name: place.name, location: Coordinate(latitude: 0, longitude: 0),
                address: PostalAddress(street: "", city: place.city ?? "", region: "", countryCode: CountryInfo.deviceCountry.code),
                timeZoneId: place.tz, source: .player, status: .unconfirmed
            )
        }
        let joined = ["owner", "organizer", "member"].contains(myRole ?? "")
        let organizers = members.map { $0.filter { $0.role == "owner" || $0.role == "organizer" }.map(\.id) }
            ?? (myRole == "owner" || myRole == "organizer" ? [me] : existing?.organizerIds ?? [])
        var memberIds = members.map { $0.map(\.id) } ?? existing?.memberIds ?? []
        if joined, !memberIds.contains(me) { memberIds.append(me) }
        if !joined { memberIds.removeAll { $0 == me } }
        var pendingIds = pending.map { $0.map(\.id) } ?? existing?.pendingIds.filter { $0 != me } ?? []
        if myRole == "pending" { pendingIds.append(me) }
        db.groups[id] = PlayGroup(
            id: id, name: name, venueId: place.id,
            ownerId: members?.first { $0.role == "owner" }?.id ?? (myRole == "owner" ? me : existing?.ownerId ?? ""),
            organizerIds: organizers, memberIds: memberIds, pendingIds: pendingIds, summary: summary ?? "",
            levelRange: levels,
            schedules: schedules.enumerated().map { index, schedule in
                GroupSchedule(id: "\(id)-\(index)", weekday: schedule.weekday + 1, startMinutes: schedule.start, endMinutes: schedule.end,
                              capacity: schedule.capacity, feeNote: schedule.fee?.isEmpty == false ? schedule.fee : nil)
            },
            joinPolicy: joinPolicy == "approval" ? .approval : .open,
            inviteCode: inviteCode ?? existing?.inviteCode ?? "", createdAt: existing?.createdAt ?? Date()
        )
        remoteGroupActivity[id] = GroupActivity(sessionsLast30Days: activity.sessions, averageTurnout: activity.average)
    }
}
