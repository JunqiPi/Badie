import Foundation

// MARK: - 正式后端：胜率、周榜、场馆月榜、挑战
/// 服务器的榜单有本期和上一期（上周、上月），胜率只有本月：更早的返回空。榜单在后台按需拉取
/// （60 秒内同一个只拉一次），拉完发 rankingsChanged，界面据此重新读取
extension MockBackend {

    struct RemoteWinRate: Decodable {
        let games: Int
        let wins: Int
        let opponents: Int
        let gap: Double
    }

    struct RemoteBoardEntry: Decodable, Equatable {
        let id: String
        let nickname: String
        let rating: Double
        let rank: Int
        let points: Int?
        let games: Int
        let wins: Int
    }

    struct RemoteWeeklyBoard: Decodable, Equatable {
        struct Mine: Decodable, Equatable {
            let rank: Int
            let points: Int
        }

        struct Progress: Decodable, Equatable {
            let games: Int
            let opponents: Int
            let points: Int
        }

        let entries: [RemoteBoardEntry]
        let me: Mine?
        let progress: Progress?
        let eligible: Bool
    }

    struct RemoteVenueBoard: Decodable, Equatable {
        struct Band: Decodable, Equatable {
            let band: Int
            let entries: [RemoteBoardEntry]
        }

        let bands: [Band]
    }

    struct RemoteChallenges: Decodable {
        struct Venue: Decodable {
            let name: String
            let tz: String?
        }

        struct Player: Decodable {
            let id: String
            let nickname: String
            let rating: Double
        }

        struct Item: Decodable {
            let id: String
            let startsAt: Date
            let endsAt: Date
            let message: String?
            let expiresAt: Date?
            let status: String?
            let gameId: String?
            let venue: Venue
            let player: Player
            /// 双打：发起人带的搭档
            let partner: Player?
        }

        let incoming: [Item]
        let outgoing: [Item]
    }

    // MARK: 读（同步，读缓存）

    func remoteWinRate(for userId: String, month: DateInterval) -> Rankings.WinRate {
        let empty = Rankings.WinRate(games: 0, wins: 0, opponents: 0, averageGap: 0)
        guard month.contains(Date()) else { return empty }
        if userId == currentUserId { refreshRemoteBoard("record") { try await self.loadRemoteRecord() } }
        return remoteWinRates[userId] ?? empty
    }

    /// 0 = 本期，1 = 上一期（紧挨着本期结束），更早的服务器不提供
    static func remoteOffset(of period: DateInterval, current: DateInterval) -> Int? {
        if period.start == current.start { return 0 }
        return period.end == current.start ? 1 : nil
    }

    func remoteWeeklyBoard(countryCode: String?, week: DateInterval, gender: Gender) -> RemoteWeeklyBoard? {
        guard let offset = Self.remoteOffset(of: week, current: Rankings.week(containing: Date())) else { return nil }
        let scope = countryCode == nil ? "global" : "country"
        let key = "\(scope)-\(offset)-\(gender.rawValue)"
        refreshRemoteBoard("weekly-\(key)") {
            let board: RemoteWeeklyBoard = try await self.requireRemote().rpc("weekly_board", [
                "p_scope": scope, "p_offset": offset, "p_gender": gender.rawValue,
            ])
            guard board != self.remoteWeeklyBoards[key] else { return false }
            board.entries.forEach { self.cacheRemoteUser(id: $0.id, nickname: $0.nickname, rating: $0.rating) }
            self.remoteWeeklyBoards[key] = board
            return true
        }
        return remoteWeeklyBoards[key]
    }

    func remoteVenueBoard(venueId: String, month: DateInterval, gender: Gender) -> [(bracket: LevelBracket, entries: [Rankings.Entry])] {
        guard let offset = Self.remoteOffset(of: month, current: Rankings.month(containing: Date())) else { return [] }
        let key = "\(venueId)-\(offset)-\(gender.rawValue)"
        refreshRemoteBoard("venue-\(key)") {
            let board: RemoteVenueBoard = try await self.requireRemote().rpc("venue_board", [
                "p_venue": venueId, "p_offset": offset, "p_gender": gender.rawValue,
            ])
            guard board != self.remoteVenueBoards[key] else { return false }
            board.bands.flatMap(\.entries).forEach { self.cacheRemoteUser(id: $0.id, nickname: $0.nickname, rating: $0.rating) }
            self.remoteVenueBoards[key] = board
            return true
        }
        return (remoteVenueBoards[key]?.bands ?? []).compactMap { band in
            LevelBracket(rawValue: band.band).map { ($0, band.entries.map { Self.entry($0, score: $0.games) }) }
        }
    }

    static func entry(_ remote: RemoteBoardEntry, score: Int) -> Rankings.Entry {
        Rankings.Entry(userId: remote.id, rank: remote.rank, score: score, games: remote.games, wins: remote.wins)
    }

    /// 我在这周榜上的分数和场次（不在榜上时用进度）
    func remoteWeeklyScore(countryCode: String?, week: DateInterval) -> (points: Int, games: Int, wins: Int, opponents: Int) {
        guard let board = remoteWeeklyBoard(countryCode: countryCode, week: week, gender: myBoard) else { return (0, 0, 0, 0) }
        if let mine = board.entries.first(where: { $0.id == currentUserId }) {
            return (mine.points ?? 0, mine.games, mine.wins, Rankings.weeklyMinimumOpponents)
        }
        if let progress = board.progress { return (progress.points, progress.games, 0, progress.opponents) }
        return (board.me?.points ?? 0, 0, 0, 0)
    }

    func remoteChallengeAvailability(for targetId: String) -> ChallengeAvailability {
        switch remoteChallengeStatus[targetId] {
        case "available": return .available
        case "friends_only": return .friendsOnly
        case "level_out_of_range": return .levelOutOfRange
        case "already_pending": return .alreadyPending
        case "too_many_outgoing": return .tooManyOutgoing
        case "daily_limit": return .dailyLimitReached
        case "target_busy": return .targetBusy
        default: return .unavailable
        }
    }

    // MARK: 拉取

    /// 同一个榜 60 秒内只拉一次；有变化才通知界面（load 返回是否变了）
    private func refreshRemoteBoard(_ key: String, _ load: @escaping () async throws -> Bool) {
        guard isRemote, Date().timeIntervalSince(remoteBoardLoadedAt[key] ?? .distantPast) > 60 else { return }
        remoteBoardLoadedAt[key] = Date()
        Task {
            do {
                if try await load() { emit(.rankingsChanged) }
            } catch {
                remoteBoardLoadedAt[key] = nil
                emit(.rankingsChanged)
            }
        }
    }

    /// 我本月的胜率（my_record）
    @discardableResult
    func loadRemoteRecord() async throws -> Bool {
        guard let remote, let me = currentUserId else { return false }
        let record: RemoteWinRate = try await remote.rpc("my_record")
        let rate = Rankings.WinRate(games: record.games, wins: record.wins, opponents: record.opponents, averageGap: record.gap)
        guard rate != remoteWinRates[me] else { return false }
        remoteWinRates[me] = rate
        return true
    }

    /// 榜正在拉、还没回来（界面显示占位，不显示“没人上榜”）；拉失败了不算
    func isWeeklyBoardLoading(countryCode: String?, week: DateInterval, gender: Gender) -> Bool {
        guard isRemote, let offset = Self.remoteOffset(of: week, current: Rankings.week(containing: Date())) else { return false }
        let key = "\(countryCode == nil ? "global" : "country")-\(offset)-\(gender.board.rawValue)"
        return remoteWeeklyBoards[key] == nil && remoteBoardLoadedAt["weekly-\(key)"] != nil
    }

    func isVenueBoardLoading(venueId: String, month: DateInterval, gender: Gender) -> Bool {
        guard isRemote, let offset = Self.remoteOffset(of: month, current: Rankings.month(containing: Date())) else { return false }
        let key = "\(venueId)-\(offset)-\(gender.board.rawValue)"
        return remoteVenueBoards[key] == nil && remoteBoardLoadedAt["venue-\(key)"] != nil
    }

    /// 打开排行榜时把常切的几个榜（全球 / 本国 × 本周 / 上周）一起拉，切换时不用等
    func prefetchWeeklyBoards(countryCode: String) {
        guard isRemote else { return }
        let current = Rankings.week(containing: Date())
        for week in [current, Rankings.week(containing: current.start.addingTimeInterval(-1))] {
            for scope in [nil, countryCode] { _ = remoteWeeklyBoard(countryCode: scope, week: week, gender: myBoard) }
        }
    }

    /// 和我有关的挑战：收到的（待回复）和发出的（14 天内）
    func refreshRemoteChallenges() async throws {
        guard let remote, let me = currentUserId else { return }
        let mine: RemoteChallenges = try await remote.rpc("my_challenges")
        var challenges: [String: Challenge] = [:]
        for item in mine.incoming {
            challenges[item.id] = challenge(item, challenger: item.player.id, target: me, status: .pending)
        }
        for item in mine.outgoing {
            let status: ChallengeStatus = item.status == "accepted" ? .accepted : item.status == "pending" ? .pending : .expired
            challenges[item.id] = challenge(item, challenger: me, target: item.player.id, status: status)
        }
        guard challenges != db.challenges else { return }
        db.challenges = challenges
        emit(.gamesChanged)
        emit(.rankingsChanged)
    }

    private func challenge(_ item: RemoteChallenges.Item, challenger: String, target: String, status: ChallengeStatus) -> Challenge {
        for player in [item.player, item.partner].compactMap({ $0 }) {
            cacheRemoteUser(id: player.id, nickname: player.nickname, rating: player.rating)
        }
        let court = db.challenges[item.id]?.court ?? BadmintonCourt(
            id: "challenge-\(item.id)", name: item.venue.name, location: Coordinate(latitude: 0, longitude: 0),
            address: PostalAddress(street: "", city: "", region: "", countryCode: CountryInfo.deviceCountry.code),
            timeZoneId: item.venue.tz, source: .player, status: .unconfirmed
        )
        // 有效期是发出后 48 小时：按服务器给的截止时间倒推发出时间
        let createdAt = item.expiresAt.map { $0.addingTimeInterval(-Challenge.responseWindow) } ?? db.challenges[item.id]?.createdAt ?? Date()
        var challenge = Challenge(id: item.id, challengerId: challenger, targetId: target, court: court,
                                  slot: TimeSlot(date: item.startsAt, startTime: item.startsAt, endTime: item.endsAt),
                                  message: item.message ?? "", createdAt: createdAt, status: status)
        challenge.gameId = item.gameId
        challenge.challengerPartnerId = item.partner?.id
        return challenge
    }

    // MARK: 操作

    func remoteSendChallenge(to targetId: String, court: BadmintonCourt, slot: TimeSlot, message: String,
                             partnerId: String?) async throws -> Challenge {
        let remote = try requireRemote()
        let id: String = try await remote.rpc("send_challenge", [
            "p_target": targetId,
            "p_venue": court.id,
            "p_starts_at": Self.iso(slot.startTime),
            "p_ends_at": Self.iso(slot.endTime),
            "p_message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_partner": partnerId ?? NSNull(),
        ])
        remoteChallengeStatus[targetId] = "already_pending"
        try await refreshRemoteChallenges()
        guard let challenge = db.challenges[id] else { throw BackendError.challengeNotFound }
        return challenge
    }

    func remoteRespondToChallenge(id: String, accept: Bool, partnerId: String?) async throws -> Game? {
        let remote = try requireRemote()
        let gameId = try await remote.rpc("respond_challenge", ["p_challenge": id, "p_accept": accept, "p_partner": partnerId ?? NSNull()],
                                          as: String?.self)
        try await refreshRemoteChallenges()
        await refreshRemoteActivity()
        return gameId.flatMap { db.games[$0] }
    }
}
