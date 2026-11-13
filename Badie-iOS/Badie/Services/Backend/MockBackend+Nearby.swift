import Foundation

// MARK: - 附近的人、邀请局
/// 附近的人：有等级、打开了“在同馆常客里显示我”、常去附近球馆的人（球友也在里面）。
/// 右滑是约 TA：选单打或双打、哪天几点和球馆，发一个只邀请 TA 的局。TA 可以说好、换个时间或不了；
/// 单打说好就成局；双打说好后是一个 4 人的房间，另外两个位置别人可以加入。每 24 小时最多发 10 个。
/// （以前的版本发的是一段大概的时间，说好以后再定几点，这种邀请服务器还认）
/// 正式后端：服务器的 nearby_players / invite_player 等。演示模式：用示例球友
extension MockBackend {

    enum FriendRequestState: String {
        /// 我申请了加 TA
        case sent
        /// TA 申请了加我
        case received
    }

    struct NearbyPlayer: Identifiable, Equatable {
        let userId: String
        let recentNoShows: Int
        /// 常打单打还是双打（没填是 nil）
        let preferredMode: GameMode?
        /// TA 常去、在我半径内的球馆，近的在前
        let venues: [DayCandidate.Venue]
        /// 和我共同常去的球馆有几家
        let sharedVenues: Int
        /// TA 的空闲时间
        var usualTimes: [RecurringTimeSlot] = []
        var isFriend = false
        var friendRequest: FriendRequestState? = nil

        var id: String { userId }
    }

    /// 约 TA 时默认的时间和球馆：两人空闲时间的交集（没有交集就只有球馆）
    struct InviteSuggestion: Equatable {
        var window: PlayWindow?
        var venueId: String?
        var venueName: String?
    }

    struct InviteResult: Equatable {
        let roomId: String
        /// 今天还能约几个
        let remaining: Int
    }

    /// 每 24 小时最多发几个邀请（换个时间、加球友不算）
    static let inviteLimit = 10

    // MARK: 服务器的格式

    struct RemoteLobbyUser: Decodable {
        let id: String
        let nickname: String
        let tag: Int?
        let rating: Double
        let gender: String?
        let recentNoShows: Int?
        let avatar: String?
        let cardColor: String?
        let cardPhoto: String?
        let preferredMode: String?
        let usualTimes: [ServerUsualTime]?
    }

    private struct RemoteNearbyPlace: Decodable {
        let id: String
        let name: String
        let km: Double?
    }

    private struct RemoteNearbyPlayer: Decodable {
        let user: RemoteLobbyUser
        let venues: [RemoteNearbyPlace]?
        let sharedVenues: Int?
        let isFriend: Bool?
        let friendRequest: String?
    }

    private struct RemoteSuggestion: Decodable {
        let windowStart: Date?
        let windowEnd: Date?
        let daypart: String?
        let venueId: String?
        let venueName: String?
    }

    private struct RemoteInviteResult: Decodable {
        let roomId: String
        let remaining: Int
    }

    private struct RemoteRespondResult: Decodable {
        let status: String
        let gameId: String?
    }

    /// 服务器给的球友资料存进缓存（头像、卡片背景、性别、常打的项目、空闲时间），界面从缓存读
    func cacheLobbyUser(_ person: RemoteLobbyUser) {
        guard person.id != currentUserId else { return }
        cacheRemoteUser(id: person.id, nickname: person.nickname, rating: person.rating, tag: person.tag)
        applyCardColor(person.cardColor, to: person.id)
        if var user = db.users[person.id] {
            if person.gender != nil { user.gender = Gender(server: person.gender) }
            user.preferredMode = person.preferredMode.map { GameMode(server: $0) }
            db.users[person.id] = user
        }
        if let times = person.usualTimes { cacheUsualTimes(times, for: person.id) }
    }

    // MARK: 空闲时间

    /// 别人的空闲时间存进缓存（自己的以本机为准）
    func cacheUsualTimes(_ times: [ServerUsualTime], for userId: String) {
        guard userId != currentUserId else { return }
        db.recurringSlots[userId] = times.compactMap(RecurringTimeSlot.init(server:))
    }

    /// 某人的空闲时间：自己的是打开的那几段；别人的是服务器给的（演示模式按示例球友的习惯）
    func usualTimes(of userId: String) -> [RecurringTimeSlot] {
        if userId == currentUserId { return recurringSlots().filter(\.isActive) }
        if !isRemote, isBot(userId) { return demoUsualTimes(for: userId) }
        return db.recurringSlots[userId] ?? []
    }

    /// 登录时对一下空闲时间：服务器有就用服务器的（网站上也能改，本机关掉的几段留着）；
    /// 服务器上还没有、本机有（以前只存在本机），补传一次
    func syncUsualTimes(_ server: [ServerUsualTime], userId: String, client: SupabaseClient) {
        let local = db.recurringSlots[userId] ?? []
        let key = "BadieUsualTimesUploaded-\(userId)"
        if server.isEmpty {
            let active = local.filter(\.isActive)
            guard !active.isEmpty, !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            let times = active.map(\.serverJSON)
            Task { try? await client.update("profiles", query: "id=eq.\(userId)", ["usual_times": times]) }
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        guard Set(server) != Set(local.filter(\.isActive).map(\.serverValue)) else { return }
        let fromServer = server.compactMap(RecurringTimeSlot.init(server:))
        let inactive = local.filter { !$0.isActive && !server.contains($0.serverValue) }
        db.recurringSlots[userId] = Array((fromServer + inactive).prefix(TimeSlotConstants.maximumRecurringSlots))
        scheduleSave()
    }

    // MARK: 附近的人

    func nearbyPlayers(center: Coordinate, radiusKm: Double) async throws -> [NearbyPlayer] {
        guard let remote else { return demoNearbyPlayers(center: center, radiusKm: radiusKm) }
        let items: [RemoteNearbyPlayer] = try await remote.rpc("nearby_players", [
            "p_lat": center.latitude, "p_lon": center.longitude, "p_radius_km": radiusKm,
        ])
        for item in items { cacheLobbyUser(item.user) }
        // 前两张的照片先下好再显示，后面的边刷边下
        for item in items.prefix(2) {
            await applyAvatar(item.user.avatar, to: item.user.id)
            await applyCardPhoto(item.user.cardPhoto, to: item.user.id)
        }
        let rest = Array(items.dropFirst(2))
        Task {
            for item in rest {
                await applyAvatar(item.user.avatar, to: item.user.id)
                await applyCardPhoto(item.user.cardPhoto, to: item.user.id)
            }
            emit(.friendsChanged)
        }
        return items.map { item in
            NearbyPlayer(userId: item.user.id, recentNoShows: item.user.recentNoShows ?? 0,
                         preferredMode: item.user.preferredMode.map { GameMode(server: $0) },
                         venues: (item.venues ?? []).map { DayCandidate.Venue(id: $0.id, name: $0.name, km: $0.km) },
                         sharedVenues: item.sharedVenues ?? 0,
                         usualTimes: (item.user.usualTimes ?? []).compactMap(RecurringTimeSlot.init(server:)),
                         isFriend: item.isFriend ?? false,
                         friendRequest: item.friendRequest.flatMap(FriendRequestState.init(rawValue:)))
        }
    }

    /// 左滑：30 天内不再出现
    func skipNearby(_ userId: String) async {
        guard let remote else {
            demoNearbySkipped.insert(userId)
            return
        }
        try? await remote.call("skip_nearby", ["p_user": userId])
    }

    /// 打开“在同馆常客里显示我”（等服务器存好再返回：接着要发邀请）
    func enableShowsAsRegular() async throws {
        guard var user = currentUser else { throw BackendError.notSignedIn }
        if let remote {
            try await remote.update("profiles", query: "id=eq.\(user.id)", ["show_as_regular": true])
        }
        user.privacy.showsAsRegular = true
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
    }

    // MARK: 邀请

    /// 约 TA 时默认填的时间和球馆
    func suggestInvite(with userId: String, venueId: String? = nil) async -> InviteSuggestion? {
        guard let remote else { return demoSuggestion(with: userId, venueId: venueId) }
        let raw = (try? await remote.rpc("suggest_invite_window", ["p_user": userId, "p_venue": venueId ?? NSNull()],
                                         as: RemoteSuggestion?.self)) ?? nil
        guard let raw else { return nil }
        let window = raw.windowStart.flatMap { start in
            raw.windowEnd.map { PlayWindow(start: start, end: $0, daypart: raw.daypart.flatMap(Daypart.init(rawValue:))) }
        }
        return InviteSuggestion(window: window, venueId: raw.venueId, venueName: raw.venueName)
    }

    /// 发邀请：一个只邀请 TA 的局。窗口正好一场那么长（durationMinutes）就是定好的时间
    func invitePlayer(_ userId: String, venueId: String, window: PlayWindow, mode: GameMode = .singles) async throws -> InviteResult {
        guard let remote else { return try demoInvite(userId, venueId: venueId, window: window, mode: mode) }
        let raw: RemoteInviteResult = try await remote.rpc("invite_player", [
            "p_user": userId, "p_venue": venueId,
            "p_window_start": Self.iso(window.start), "p_window_end": Self.iso(window.end),
            "p_daypart": window.daypart?.rawValue ?? NSNull(),
            "p_duration": window.durationMinutes, "p_mode": mode.serverValue,
        ])
        try? await loadRemoteRoom(raw.roomId)
        return InviteResult(roomId: raw.roomId, remaining: raw.remaining)
    }

    /// 我发出的、收到的还没结束的邀请（轮到我回的在前）
    func nearbyInvites() async throws -> [Room] {
        guard let remote else { return demoNearbyInvites() }
        let rooms: [RemoteRoom] = try await remote.rpc("nearby_invites")
        cacheRemoteRooms(rooms)
        for room in rooms {
            for person in [room.invite?.from, room.invite?.to].compactMap({ $0 }) where person.id != currentUserId {
                await applyAvatar(person.avatar, to: person.id)
            }
        }
        return rooms.compactMap { db.rooms[$0.id] }
    }

    /// 好 / 不了。说好返回球局 ID
    @discardableResult
    func respondInvite(_ roomId: String, accept: Bool) async throws -> String? {
        guard let remote else {
            let me = try requireUser()
            return try demoAnswer(roomId, by: me.id, accept: accept)
        }
        let raw: RemoteRespondResult = try await remote.rpc("respond_invite", ["p_room": roomId, "p_accept": accept])
        try? await loadRemoteRoom(roomId)
        if raw.gameId != nil { await refreshRemoteActivity() }
        return raw.gameId
    }

    /// 换个时间：venueId 为 nil 时球馆不变
    func counterInvite(_ roomId: String, venueId: String?, window: PlayWindow, mode: GameMode = .singles) async throws {
        guard let remote else { return try demoCounter(roomId, venueId: venueId, window: window, mode: mode) }
        try await remote.call("counter_invite", [
            "p_room": roomId, "p_venue": venueId ?? NSNull(),
            "p_window_start": Self.iso(window.start), "p_window_end": Self.iso(window.end),
            "p_daypart": window.daypart?.rawValue ?? NSNull(),
            "p_duration": window.durationMinutes, "p_mode": mode.serverValue,
        ])
        try? await loadRemoteRoom(roomId)
    }

    /// 发出的邀请撤回（对方不会收到通知）；受邀的人在等对方回时退出 = 不了
    func withdrawInvite(_ roomId: String) async throws {
        guard let remote else {
            guard var room = db.rooms[roomId], room.status.isOpen, let me = currentUserId,
                  room.ownerId == me || room.invite?.toId == me else { return }
            room.status = .closed(room.ownerId == me ? .ownerClosed : .declined)
            room.invite?.awaitingId = nil
            db.rooms[roomId] = room
            scheduleSave()
            emit(.roomsChanged)
            return
        }
        try await remote.call("leave_room", ["p_room": roomId])
        try? await loadRemoteRoom(roomId)
    }

    /// 定时间：在窗口里选一个开始时间（打 2 小时）
    func setGameTime(_ gameId: String, startsAt: Date) async throws {
        guard let remote else { return try demoSetGameTime(gameId, startsAt: startsAt) }
        try await remote.call("set_game_time", ["p_game": gameId, "p_starts_at": Self.iso(startsAt)])
        await refreshRemoteActivity()
    }

    // MARK: 球馆里的人

    /// 球馆页的两排头像：最近 30 天在这打完过一场的人、常客（都是在大厅里能看到的人，最多各 20 个）
    struct VenuePeople: Equatable {
        var recent: [String] = []
        var regulars: [String] = []
    }

    private struct RemoteVenuePeople: Decodable {
        let recent: [RemoteLobbyUser]?
        let regulars: [RemoteLobbyUser]?
    }

    func venuePeople(_ venueId: String) async throws -> VenuePeople {
        guard let remote else { return demoVenuePeople(venueId) }
        let raw: RemoteVenuePeople = try await remote.rpc("venue_people", ["p_venue": venueId])
        let people = (raw.recent ?? []) + (raw.regulars ?? [])
        for person in people { cacheLobbyUser(person) }
        // 头像边显示边下
        Task {
            for person in people { await applyAvatar(person.avatar, to: person.id) }
            emit(.friendsChanged)
        }
        let me = currentUserId
        return VenuePeople(recent: (raw.recent ?? []).map(\.id).filter { $0 != me },
                           regulars: (raw.regulars ?? []).map(\.id).filter { $0 != me })
    }

    /// 演示：常客是把这里设为常去的示例球友；示例球友之间没有打球记录，“最近在这打过”取我在这打完的球局里的人，再加一半常客
    private func demoVenuePeople(_ venueId: String, now: Date = Date()) -> VenuePeople {
        guard let me = currentUserId else { return VenuePeople() }
        let blocked = blockedIds()
        let regulars = db.bots.keys.sorted().filter {
            demoEligible($0, me: me, blocked: blocked) && (db.favoriteCourtIds[$0] ?? []).contains(venueId)
        }
        let played = db.games.values
            .filter { $0.court.id == venueId && $0.status == .completed && now.timeIntervalSince($0.slot.startTime) < 30 * 86400 }
            .flatMap(\.playerIds)
            .filter { demoEligible($0, me: me, blocked: blocked) }
        var seen = Set<String>()
        let recent = (played + regulars.filter { $0.stableHash % 2 == 0 }).filter { seen.insert($0).inserted }
        return VenuePeople(recent: Array(recent.prefix(20)), regulars: Array(regulars.prefix(20)))
    }

    // MARK: 演示模式

    /// 示例球友的空闲时间：按 TA 的打球习惯
    func demoUsualTimes(for botId: String) -> [RecurringTimeSlot] {
        guard let bot = db.bots[botId] else { return [] }
        // 固定的 id：同一个人每次一样
        func slot(_ day: Int, _ start: Int, _ end: Int) -> RecurringTimeSlot {
            RecurringTimeSlot(id: "\(botId)-\(day)-\(start)", dayOfWeek: day, startHour: start / 60, startMinute: start % 60,
                              endHour: end / 60, endMinute: end % 60)
        }
        switch bot.pattern {
        case .weekdayEvenings: return [slot(3, 19 * 60, 21 * 60 + 30), slot(5, 19 * 60, 21 * 60 + 30), slot(7, 14 * 60, 17 * 60)]
        case .weekendDaytime: return [slot(7, 9 * 60, 12 * 60), slot(7, 14 * 60, 18 * 60), slot(1, 14 * 60, 18 * 60)]
        case .flexible: return [slot(4, 19 * 60, 21 * 60), slot(7, 10 * 60, 12 * 60), slot(1, 15 * 60, 18 * 60)]
        case .mornings: return [slot(2, 7 * 60, 9 * 60), slot(4, 7 * 60, 9 * 60), slot(7, 9 * 60, 12 * 60)]
        case .nightOwl: return [slot(6, 20 * 60, 22 * 60), slot(7, 15 * 60, 18 * 60)]
        }
    }

    private func demoEligible(_ id: String, me: String, blocked: Set<String>) -> Bool {
        guard id != me, !blocked.contains(id), !blockedIds(of: id).contains(me),
              let user = db.users[id], user.privacy.showsAsRegular else { return false }
        return true
    }

    /// 我们之间有没有还没结束的邀请（哪边发的都算）
    private func demoHasOpenInvite(_ me: String, _ other: String) -> Bool {
        db.rooms.values.contains { room in
            guard let invite = room.invite, room.status.isOpen, !room.isExpired() else { return false }
            return Set([invite.fromId, invite.toId]) == Set([me, other])
        }
    }

    private func demoNearbyPlayers(center: Coordinate, radiusKm: Double) -> [NearbyPlayer] {
        guard let me = currentUserId else { return [] }
        let blocked = blockedIds()
        let mine = Set(favoriteCourtIds())
        let myLevel = currentUser?.displayLevel ?? 4
        let outgoing = Set(outgoingRequests().map(\.toUserId))
        let incoming = Set(incomingRequests().map(\.fromUserId))
        let people = db.bots.keys.sorted().compactMap { id -> NearbyPlayer? in
            guard demoEligible(id, me: me, blocked: blocked), !demoNearbySkipped.contains(id), !demoDeclined.contains(id),
                  !demoHasOpenInvite(me, id), let user = db.users[id] else { return nil }
            let venues = (db.favoriteCourtIds[id] ?? []).compactMap { venue(id: $0) }
                .filter { $0.location.distanceKm(to: center) <= radiusKm }
                .sorted { $0.location.distanceKm(to: center) < $1.location.distanceKm(to: center) }
            guard !venues.isEmpty else { return nil }
            return NearbyPlayer(userId: id, recentNoShows: user.attendance.noShows,
                                preferredMode: user.preferredMode,
                                venues: venues.map { DayCandidate.Venue(id: $0.id, name: $0.name, km: $0.location.distanceKm(to: center)) },
                                sharedVenues: venues.filter { mine.contains($0.id) }.count,
                                usualTimes: demoUsualTimes(for: id),
                                isFriend: isFriend(id),
                                friendRequest: outgoing.contains(id) ? .sent : incoming.contains(id) ? .received : nil)
        }
        let featured = demoFeaturedIds
        let sorted = people.sorted { a, b in
            let fa = featured.firstIndex(of: a.userId) ?? featured.count
            let fb = featured.firstIndex(of: b.userId) ?? featured.count
            if fa != fb { return fa < fb }
            if a.sharedVenues != b.sharedVenues { return a.sharedVenues > b.sharedVenues }
            let la = abs((db.users[a.userId]?.displayLevel ?? myLevel) - myLevel)
            let lb = abs((db.users[b.userId]?.displayLevel ?? myLevel) - myLevel)
            if la != lb { return la < lb }
            return (a.venues.first?.km ?? .infinity) < (b.venues.first?.km ?? .infinity)
        }
        return Array(sorted.prefix(30))
    }

    /// 演示：两人都常去的球馆（没有就 TA 常去的、我常去的）+ 两人空闲时间的交集
    private func demoSuggestion(with userId: String, venueId: String?, now: Date = Date()) -> InviteSuggestion? {
        let court = demoInviteVenue(with: userId, preferred: venueId)
        let window = PlayWindow.firstOverlap(usualTimes(of: currentUserId ?? ""), usualTimes(of: userId), now: now)
        guard court != nil || window != nil else { return nil }
        return InviteSuggestion(window: window, venueId: court?.id, venueName: court?.name)
    }

    private func demoInviteVenue(with userId: String, preferred: String? = nil) -> BadmintonCourt? {
        if let preferred, let court = venue(id: preferred) { return court }
        let mine = favoriteCourtIds()
        let theirs = db.favoriteCourtIds[userId] ?? []
        let id = theirs.first { mine.contains($0) } ?? mine.first ?? theirs.first
        return id.flatMap { venue(id: $0) }
    }

    /// 窗口开始得太早就往后挪到最早能开始的时间（和服务器一致）
    private func demoChecked(_ window: PlayWindow, now: Date) throws -> PlayWindow {
        var window = window
        let earliest = PlayWindow.earliestStart(now: now)
        if window.start < earliest { window.start = earliest }
        guard window.end.timeIntervalSince(window.start) <= 7 * 86400, window.isPossible(now: now) else {
            throw RemoteError.server("invalid_window")
        }
        guard window.start.timeIntervalSince(now) <= 30 * 86400 else { throw RemoteError.server("too_far") }
        return window
    }

    private func demoInviteRoom(from: String, to: String, court: BadmintonCourt, window: PlayWindow, now: Date,
                                mode: GameMode = .singles, awaiting: String? = nil, rounds: Int = 0) -> Room {
        let participants = db.users[from].map { [RoomParticipant(user: $0, joinedAt: now)] } ?? []
        // 双打说好后要让别人加入，要有房间码
        let code = mode == .doubles ? Room.generateCode(excluding: Set(db.rooms.values.map(\.code))) : ""
        return Room(id: UUID().uuidString, code: code, ownerId: from, mode: mode, visibility: .privateRoom,
                    participants: participants, invitedUserIds: [to], waitlist: [], court: court, slot: window.slot,
                    levelRange: 1...9, tags: [], note: "", createdAt: now, lastActivityAt: now, status: .open,
                    window: window.isExact ? nil : window,
                    invite: LobbyInvite(fromId: from, toId: to, awaitingId: awaiting ?? to, rounds: rounds, answerBy: window.deadline))
    }

    private func demoInvite(_ userId: String, venueId: String, window: PlayWindow, mode: GameMode,
                            now: Date = Date()) throws -> InviteResult {
        let me = try requireUser()
        guard me.privacy.showsAsRegular else { throw RemoteError.server("not_visible") }
        guard demoEligible(userId, me: me.id, blocked: blockedIds()), !demoDeclined.contains(userId) else {
            throw RemoteError.server("not_available")
        }
        guard !demoHasOpenInvite(me.id, userId) else { throw RemoteError.server("already_invited") }
        demoInvitesSent = demoInvitesSent.filter { now.timeIntervalSince($0) < 24 * 3600 }
        guard demoInvitesSent.count < Self.inviteLimit else { throw RemoteError.server("invite_limit") }
        guard let court = venue(id: venueId) else { throw RemoteError.server("invalid_venues") }
        let checked = try demoChecked(window, now: now)
        let room = demoInviteRoom(from: me.id, to: userId, court: court, window: checked, now: now, mode: mode)
        demoInvitesSent.append(now)
        db.rooms[room.id] = room
        scheduleSave()
        emit(.roomsChanged)
        demoBotAnswers(room.id, botId: userId)
        return InviteResult(roomId: room.id, remaining: max(0, Self.inviteLimit - demoInvitesSent.count))
    }

    /// 示例球友过一会儿回：多半说好
    private func demoBotAnswers(_ roomId: String, botId: String) {
        guard let bot = db.bots[botId] else { return }
        let accepts = Double.random(in: 0..<1) < bot.friendliness
        simulate(after: Double.random(in: 4...10)) { [weak self] in
            guard let self, self.db.rooms[roomId]?.status.isOpen == true else { return }
            _ = try? self.demoAnswer(roomId, by: botId, accept: accepts)
        }
    }

    /// 演示：第一次打开时放两个示例邀请：一位附近的球友约我周六下午；我约过的一位想换个时间
    private func demoNearbyInvites(now: Date = Date()) -> [Room] {
        guard let me = currentUserId else { return [] }
        if !demoInvitesSeeded {
            demoInvitesSeeded = true
            demoSeedInvites(me: me, now: now)
        }
        return db.rooms.values
            .filter { room in
                guard let invite = room.invite, room.status.isOpen, !room.isExpired(now: now) else { return false }
                return invite.fromId == me || invite.toId == me
            }
            .sorted { a, b in
                let x = a.invite?.awaitingId == me, y = b.invite?.awaitingId == me
                if x != y { return x }
                return a.lastActivityAt > b.lastActivityAt
            }
    }

    private func demoSeedInvites(me: String, now: Date) {
        let blocked = blockedIds()
        let center = currentUser?.location ?? db.worldCenter
        let nearby = db.bots.keys.sorted().filter { id in
            guard demoEligible(id, me: me, blocked: blocked), !demoHasOpenInvite(me, id),
                  let location = db.users[id]?.location else { return false }
            return location.distanceKm(to: center) <= 15 && !(db.favoriteCourtIds[id] ?? []).isEmpty
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // 最近的一个周六下午
        let saturday = (1...8).lazy.compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .first { calendar.component(.weekday, from: $0) == 7 }
        if let first = nearby.first, let saturday, let window = PlayWindow.on(saturday, daypart: .afternoon),
           let court = demoInviteVenue(with: first) {
            var room = demoInviteRoom(from: first, to: me, court: court, window: window, now: now)
            room.lastActivityAt = now.addingTimeInterval(-40 * 60)
            db.rooms[room.id] = room
        }
        // 我约过 TA，TA 想换成下周工作日晚上
        if nearby.count > 1, let window = PlayWindow.nextWeekdays(now: now, daypart: .evening),
           let court = demoInviteVenue(with: nearby[1]) {
            var room = demoInviteRoom(from: me, to: nearby[1], court: court, window: window, now: now, awaiting: me, rounds: 1)
            room.lastActivityAt = now.addingTimeInterval(-2 * 3600)
            db.rooms[room.id] = room
        }
        scheduleSave()
    }

    /// 好 / 不了（我回，或者示例球友回我）。说好返回球局 ID
    @discardableResult
    private func demoAnswer(_ roomId: String, by userId: String, accept: Bool, now: Date = Date()) throws -> String? {
        guard var room = db.rooms[roomId], room.status.isOpen, let invite = room.invite,
              let court = room.court, let slot = room.slot else { throw RemoteError.server("not_available") }
        guard invite.awaitingId == userId else { throw RemoteError.server("not_your_turn") }
        guard now < invite.answerBy else { throw RemoteError.server("invite_expired") }
        let other = invite.other(than: userId)
        let name = db.users[userId]?.nickname ?? ""
        let when = room.window.map { WindowText.headline($0, now: now) } ?? slot.formattedFull
        guard accept else {
            room.status = .closed(.declined)
            db.rooms[roomId] = room
            // 30 天内互相不再出现
            demoDeclined.insert(userId == currentUserId ? other : userId)
            addInbox(InboxItem(kind: .inviteDeclined, title: String(localized: "\(name)这次来不了"),
                               body: "\(when) · \(court.name)"), to: other)
            scheduleSave()
            emit(.roomsChanged)
            return nil
        }
        let ids = [invite.fromId, invite.toId]
        room.participants = ids.compactMap { db.users[$0].map { RoomParticipant(user: $0, joinedAt: now) } }
        room.invitedUserIds = []
        if room.mode == .doubles {
            // 双打：两个人先占两个位置，房间公开，附近的人可以加入补齐
            room.invite = nil
            room.visibility = .publicListing
            room.lastActivityAt = now
            db.rooms[roomId] = room
            addInbox(InboxItem(kind: .roomJoined, title: String(localized: "\(name)答应了"), body: "\(when) · \(court.name)",
                               relatedId: roomId), to: other)
            scheduleSave()
            emit(.roomsChanged)
            return nil
        }
        // 费用按一场 2 小时算（还没定时间时 slot 是整个窗口）
        let duration = room.window?.duration ?? slot.duration
        let costSlot = TimeSlot(date: slot.startTime, startTime: slot.startTime, endTime: slot.startTime.addingTimeInterval(duration))
        var game = Game(
            id: UUID().uuidString, mode: .singles, court: court, slot: slot, playerIds: ids, teams: ids.map { [$0] },
            hostId: invite.fromId, origin: .room(code: room.code), status: .confirmed, createdAt: now, checkIns: [:],
            paidPlayerIds: [], cost: CostSplit.estimate(court: court, slot: costSlot, mode: .singles), result: nil,
            cancelledBy: nil, cancelledLate: false, reminderEnabled: false
        )
        game.window = room.window
        room.status = .started(gameId: game.id)
        db.rooms[roomId] = room
        db.games[game.id] = game
        ensureGameThread(for: game)
        addInbox(InboxItem(kind: .gameConfirmed, title: String(localized: "约成了"), body: "\(when) · \(court.name)",
                           relatedId: game.id), to: other)
        scheduleSave()
        emit(.roomsChanged)
        emit(.gamesChanged)
        return game.id
    }

    private func demoCounter(_ roomId: String, venueId: String?, window: PlayWindow, mode: GameMode, now: Date = Date()) throws {
        let me = try requireUser()
        guard var room = db.rooms[roomId], room.status.isOpen, var invite = room.invite else {
            throw RemoteError.server("not_available")
        }
        guard invite.awaitingId == me.id else { throw RemoteError.server("not_your_turn") }
        let checked = try demoChecked(window, now: now)
        if let venueId {
            guard let court = venue(id: venueId) else { throw RemoteError.server("invalid_venues") }
            room.court = court
        }
        let other = invite.other(than: me.id)
        invite.awaitingId = other
        invite.rounds += 1
        invite.answerBy = checked.deadline
        room.invite = invite
        room.mode = mode
        room.slot = checked.slot
        room.window = checked.isExact ? nil : checked
        room.lastActivityAt = now
        db.rooms[roomId] = room
        addInbox(InboxItem(kind: .inviteCounter, title: String(localized: "\(me.nickname)想换个时间"),
                           body: "\(WindowText.headline(checked, now: now)) · \(room.court?.name ?? "")", relatedId: roomId), to: other)
        scheduleSave()
        emit(.roomsChanged)
        demoBotAnswers(roomId, botId: other)
    }

    private func demoSetGameTime(_ gameId: String, startsAt: Date) throws {
        let me = try requireUser()
        guard var game = db.games[gameId], game.playerIds.contains(me.id), game.status == .confirmed else {
            throw RemoteError.server("not_available")
        }
        guard let window = game.window else { throw RemoteError.server("time_already_set") }
        guard window.possibleStarts().contains(startsAt) else { throw RemoteError.server("invalid_slot") }
        let slot = TimeSlot(date: startsAt, startTime: startsAt, endTime: startsAt.addingTimeInterval(window.duration))
        game.slot = slot
        game.window = nil
        db.games[gameId] = game
        for (id, room) in db.rooms {
            if case .started(let started) = room.status, started == gameId {
                db.rooms[id]?.slot = slot
                db.rooms[id]?.window = nil
            }
        }
        for other in game.otherPlayerIds(excluding: me.id) {
            addInbox(InboxItem(kind: .gameTimeSet, title: String(localized: "\(me.nickname)定了时间"),
                               body: "\(slot.formattedFull) · \(game.court.name)", relatedId: gameId), to: other)
        }
        scheduleSave()
        emit(.gamesChanged)
    }
}
