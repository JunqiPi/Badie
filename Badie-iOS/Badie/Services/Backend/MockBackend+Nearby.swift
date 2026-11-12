import Foundation

// MARK: - 常在附近打的人、想一起打
/// 按天的卡片刷完后，接着看常去附近球馆、打开了“在同馆常客里显示我”的人（不分日期）。
/// 右滑是“想一起打”：对方同意（或也右滑了我）就加为球友。
/// 正式后端：服务器的 nearby_players / wish_to_play 等。演示模式：用示例球友
extension MockBackend {

    struct NearbyPlayer: Identifiable, Equatable {
        let userId: String
        let recentNoShows: Int
        /// 常打单打还是双打（没填是 nil）
        let preferredMode: GameMode?
        /// TA 常去、在我半径内的球馆，近的在前
        let venues: [DayCandidate.Venue]
        /// 和我共同常去的球馆有几家
        let sharedVenues: Int

        var id: String { userId }
    }

    /// 推荐一起打的时间和地方：都常去的球馆 + 接下来 7 天两人都常有空的时间（可能只有球馆）
    struct PlaySuggestion: Equatable {
        var venueId: String?
        var venueName: String?
        var startsAt: Date?
        var endsAt: Date?
    }

    struct PlayWishResult: Equatable {
        /// 对方也想和我打：已经加为球友
        let mutual: Bool
        /// 今天还能约几个
        let remaining: Int
        let suggestion: PlaySuggestion?
    }

    /// 别人想和我打球（还没回）
    struct PlayWish: Identifiable, Equatable {
        let userId: String
        let recentNoShows: Int
        let sharedVenue: String?
        let createdAt: Date

        var id: String { userId }
    }

    /// 每 24 小时最多发几个
    static let playWishLimit = 10

    // MARK: 服务器的格式

    private struct RemoteNearbyPerson: Decodable {
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
    }

    private struct RemoteNearbyPlace: Decodable {
        let id: String
        let name: String
        let km: Double?
    }

    private struct RemoteNearbyPlayer: Decodable {
        let user: RemoteNearbyPerson
        let venues: [RemoteNearbyPlace]?
        let sharedVenues: Int?
    }

    private struct RemoteSuggestion: Decodable {
        let venueId: String?
        let venueName: String?
        let startsAt: Date?
        let endsAt: Date?

        var value: PlaySuggestion? {
            guard venueId != nil || venueName != nil || startsAt != nil else { return nil }
            return PlaySuggestion(venueId: venueId, venueName: venueName, startsAt: startsAt, endsAt: endsAt)
        }
    }

    private struct RemoteWishResult: Decodable {
        let mutual: Bool
        let remaining: Int
        let suggestion: RemoteSuggestion?
    }

    private struct RemotePendingWish: Decodable {
        let from: RemoteNearbyPerson
        let sharedVenue: String?
        let createdAt: Date
    }

    private struct RemoteRespondResult: Decodable {
        let suggestion: RemoteSuggestion?
    }

    /// 服务器给的球友资料存进缓存（头像、卡片背景、性别、常打的项目），界面从缓存读
    private func cacheNearbyPerson(_ person: RemoteNearbyPerson) {
        cacheRemoteUser(id: person.id, nickname: person.nickname, rating: person.rating, tag: person.tag)
        applyCardColor(person.cardColor, to: person.id)
        if var user = db.users[person.id] {
            if person.gender != nil { user.gender = Gender(server: person.gender) }
            user.preferredMode = person.preferredMode.map { GameMode(server: $0) }
            db.users[person.id] = user
        }
    }

    // MARK: 常在附近

    func nearbyPlayers(center: Coordinate, radiusKm: Double) async throws -> [NearbyPlayer] {
        guard let remote else { return demoNearbyPlayers(center: center, radiusKm: radiusKm) }
        let items: [RemoteNearbyPlayer] = try await remote.rpc("nearby_players", [
            "p_lat": center.latitude, "p_lon": center.longitude, "p_radius_km": radiusKm,
        ])
        for item in items { cacheNearbyPerson(item.user) }
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
                         sharedVenues: item.sharedVenues ?? 0)
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

    /// 右滑：想一起打。对方也想和我打就直接加为球友（mutual）
    func wishToPlay(_ userId: String) async throws -> PlayWishResult {
        guard let remote else { return try demoWishToPlay(userId) }
        let raw: RemoteWishResult = try await remote.rpc("wish_to_play", ["p_user": userId])
        if raw.mutual { await refreshAfterNewFriend() }
        return PlayWishResult(mutual: raw.mutual, remaining: raw.remaining, suggestion: withMyUsualTime(raw.suggestion?.value))
    }

    /// 别人发给我的、还没回的
    func pendingPlayWishes() async throws -> [PlayWish] {
        guard let remote else { return demoPendingWishes() }
        let items: [RemotePendingWish] = try await remote.rpc("pending_play_wishes")
        for item in items { cacheNearbyPerson(item.from) }
        for item in items {
            await applyAvatar(item.from.avatar, to: item.from.id)
        }
        return items.map {
            PlayWish(userId: $0.from.id, recentNoShows: $0.from.recentNoShows ?? 0, sharedVenue: $0.sharedVenue, createdAt: $0.createdAt)
        }
    }

    /// 好：加为球友，返回推荐的时间地点；不了：对方不会收到通知，30 天内互相不再出现
    @discardableResult
    func respondPlayWish(from userId: String, accept: Bool) async throws -> PlaySuggestion? {
        guard let remote else { return demoRespond(from: userId, accept: accept) }
        guard accept else {
            try await remote.call("respond_play_wish", ["p_from": userId, "p_accept": false])
            return nil
        }
        let raw: RemoteRespondResult = try await remote.rpc("respond_play_wish", ["p_from": userId, "p_accept": true])
        await refreshAfterNewFriend()
        return withMyUsualTime(raw.suggestion?.value)
    }

    /// 服务器只给球馆（常用时间只存在本机）：用我自己接下来 7 天里最近的一段常用时间补上
    func withMyUsualTime(_ suggestion: PlaySuggestion?, now: Date = Date()) -> PlaySuggestion? {
        guard var suggestion, suggestion.startsAt == nil else { return suggestion }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let slots = recurringSlots().filter(\.isActive)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let starts = slots.filter { $0.dayOfWeek == weekday }.compactMap { slot -> (Date, Date)? in
                guard let start = calendar.date(bySettingHour: slot.startHour, minute: slot.startMinute, second: 0, of: day),
                      let end = calendar.date(bySettingHour: min(slot.endHour, 23), minute: slot.endHour >= 24 ? 59 : slot.endMinute, second: 0, of: day),
                      start > now.addingTimeInterval(3600), end > start else { return nil }
                return (start, min(end, start.addingTimeInterval(2 * 3600)))
            }
            if let first = starts.min(by: { $0.0 < $1.0 }) {
                suggestion.startsAt = first.0
                suggestion.endsAt = first.1
                return suggestion
            }
        }
        return suggestion
    }

    /// 打开“在同馆常客里显示我”（等服务器存好再返回：接着要发“想一起打”）
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

    private func refreshAfterNewFriend() async {
        try? await refreshRemoteSocial()
        emit(.friendsChanged)
        emit(.threadsChanged)
    }

    // MARK: 演示模式

    private func demoEligible(_ id: String, me: String, blocked: Set<String>) -> Bool {
        guard id != me, !blocked.contains(id), !blockedIds(of: id).contains(me), !isFriend(id),
              let user = db.users[id], user.privacy.showsAsRegular else { return false }
        return true
    }

    private func demoNearbyPlayers(center: Coordinate, radiusKm: Double) -> [NearbyPlayer] {
        guard let me = currentUserId else { return [] }
        let blocked = blockedIds()
        let mine = Set(favoriteCourtIds())
        let myLevel = currentUser?.displayLevel ?? 4
        let people = db.bots.keys.sorted().compactMap { id -> NearbyPlayer? in
            guard demoEligible(id, me: me, blocked: blocked), demoWishesSent[id] == nil, !demoNearbySkipped.contains(id),
                  !demoWishesClosed.contains(id), let user = db.users[id] else { return nil }
            let venues = (db.favoriteCourtIds[id] ?? []).compactMap { venue(id: $0) }
                .filter { $0.location.distanceKm(to: center) <= radiusKm }
                .sorted { $0.location.distanceKm(to: center) < $1.location.distanceKm(to: center) }
            guard !venues.isEmpty else { return nil }
            return NearbyPlayer(userId: id, recentNoShows: user.attendance.noShows,
                                preferredMode: user.preferredMode,
                                venues: venues.map { DayCandidate.Venue(id: $0.id, name: $0.name, km: $0.location.distanceKm(to: center)) },
                                sharedVenues: venues.filter { mine.contains($0.id) }.count)
        }
        let sorted = people.sorted { a, b in
            if a.sharedVenues != b.sharedVenues { return a.sharedVenues > b.sharedVenues }
            let la = abs((db.users[a.userId]?.displayLevel ?? myLevel) - myLevel)
            let lb = abs((db.users[b.userId]?.displayLevel ?? myLevel) - myLevel)
            if la != lb { return la < lb }
            return (a.venues.first?.km ?? .infinity) < (b.venues.first?.km ?? .infinity)
        }
        return Array(sorted.prefix(30))
    }

    /// 演示：附近一位常客已经想和我打（右滑 TA 就是双方都想）
    private func demoIncomingIds() -> [String] {
        if let ids = demoWishesIncoming { return ids }
        guard let me = currentUserId else { return [] }
        let blocked = blockedIds()
        let center = currentUser?.location ?? db.worldCenter
        let first = db.bots.keys.sorted().first { id in
            guard demoEligible(id, me: me, blocked: blocked), let location = db.users[id]?.location else { return false }
            return location.distanceKm(to: center) <= 15 && !(db.favoriteCourtIds[id] ?? []).isEmpty
        }
        let ids = first.map { [$0] } ?? []
        demoWishesIncoming = ids
        return ids
    }

    private func demoPendingWishes() -> [PlayWish] {
        let mine = Set(favoriteCourtIds())
        return demoIncomingIds().filter { !demoWishesClosed.contains($0) && !isFriend($0) }.compactMap { id in
            guard let user = db.users[id] else { return nil }
            let shared = (db.favoriteCourtIds[id] ?? []).first { mine.contains($0) } ?? db.favoriteCourtIds[id]?.first
            return PlayWish(userId: id, recentNoShows: user.attendance.noShows, sharedVenue: shared.flatMap { venue(id: $0)?.name },
                            createdAt: Date().addingTimeInterval(-40 * 60))
        }
    }

    private func demoWishToPlay(_ userId: String, now: Date = Date()) throws -> PlayWishResult {
        guard let me = currentUserId else { throw BackendError.notSignedIn }
        guard currentUser?.privacy.showsAsRegular == true else { throw RemoteError.server("not_visible") }
        guard demoEligible(userId, me: me, blocked: blockedIds()) else { throw RemoteError.server("not_available") }
        demoWishesSent = demoWishesSent.filter { now.timeIntervalSince($0.value) < 24 * 3600 }
        if demoWishesSent[userId] == nil {
            guard demoWishesSent.count < Self.playWishLimit else { throw RemoteError.server("wish_limit") }
            demoWishesSent[userId] = now
        }
        let remaining = max(0, Self.playWishLimit - demoWishesSent.count)
        guard demoIncomingIds().contains(userId), !demoWishesClosed.contains(userId) else {
            return PlayWishResult(mutual: false, remaining: remaining, suggestion: nil)
        }
        demoWishesClosed.insert(userId)
        demoBecomeFriends(userId)
        return PlayWishResult(mutual: true, remaining: remaining, suggestion: demoSuggestion(with: userId))
    }

    private func demoRespond(from userId: String, accept: Bool) -> PlaySuggestion? {
        demoWishesClosed.insert(userId)
        guard accept else { return nil }
        demoBecomeFriends(userId)
        return demoSuggestion(with: userId)
    }

    private func demoBecomeFriends(_ userId: String) {
        guard let me = currentUserId else { return }
        makeFriends(me, userId)
        scheduleSave()
        emit(.friendsChanged)
        emit(.threadsChanged)
    }

    /// 演示：都常去的球馆（没有就 TA 常去的第一家）+ 接下来 7 天里 TA 有空的第一段（最多 2 小时）
    private func demoSuggestion(with userId: String, now: Date = Date()) -> PlaySuggestion? {
        let mine = Set(favoriteCourtIds())
        let theirs = db.favoriteCourtIds[userId] ?? []
        let court = (theirs.first { mine.contains($0) } ?? theirs.first).flatMap { venue(id: $0) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var slot: TimeSlot?
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if let found = availability(for: userId, on: day).first(where: { $0.startTime > now.addingTimeInterval(3600) }) {
                slot = found
                break
            }
        }
        guard court != nil || slot != nil else { return nil }
        return PlaySuggestion(venueId: court?.id, venueName: court?.name, startsAt: slot?.startTime,
                              endsAt: slot.map { min($0.endTime, $0.startTime.addingTimeInterval(2 * 3600)) })
    }
}
