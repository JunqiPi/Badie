import Foundation

// MARK: - 正式后端：胜率、周榜、场馆月榜、挑战
/// 服务器只算本周、本月：查以前的周和月时返回空。榜单在后台按需拉取（60 秒内同一个只拉一次），
/// 拉完发 rankingsChanged，界面据此重新读取
extension MockBackend {

    struct RemoteWinRate: Decodable {
        let games: Int
        let wins: Int
        let opponents: Int
        let gap: Double
    }

    struct RemoteBoardEntry: Decodable {
        let id: String
        let nickname: String
        let rating: Double
        let rank: Int
        let points: Int?
        let games: Int
        let wins: Int
    }

    struct RemoteWeeklyBoard: Decodable {
        struct Mine: Decodable {
            let rank: Int
            let points: Int
        }

        struct Progress: Decodable {
            let games: Int
            let opponents: Int
            let points: Int
        }

        let entries: [RemoteBoardEntry]
        let me: Mine?
        let progress: Progress?
        let eligible: Bool
    }

    struct RemoteVenueBoard: Decodable {
        struct Band: Decodable {
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

    func remoteWeeklyBoard(countryCode: String?, week: DateInterval) -> RemoteWeeklyBoard? {
        guard week.contains(Date()) else { return nil }
        let scope = countryCode == nil ? "global" : "country"
        refreshRemoteBoard("weekly-\(scope)") {
            let board: RemoteWeeklyBoard = try await self.requireRemote().rpc("weekly_board", ["p_scope": scope])
            board.entries.forEach { self.cacheRemoteUser(id: $0.id, nickname: $0.nickname, rating: $0.rating) }
            self.remoteWeeklyBoards[scope] = board
        }
        return remoteWeeklyBoards[scope]
    }

    func remoteVenueBoard(venueId: String, month: DateInterval) -> [(bracket: LevelBracket, entries: [Rankings.Entry])] {
        guard month.contains(Date()) else { return [] }
        refreshRemoteBoard("venue-\(venueId)") {
            let board: RemoteVenueBoard = try await self.requireRemote().rpc("venue_board", ["p_venue": venueId])
            board.bands.flatMap(\.entries).forEach { self.cacheRemoteUser(id: $0.id, nickname: $0.nickname, rating: $0.rating) }
            self.remoteVenueBoards[venueId] = board
        }
        return (remoteVenueBoards[venueId]?.bands ?? []).compactMap { band in
            LevelBracket(rawValue: band.band).map { ($0, band.entries.map { Self.entry($0, score: $0.games) }) }
        }
    }

    static func entry(_ remote: RemoteBoardEntry, score: Int) -> Rankings.Entry {
        Rankings.Entry(userId: remote.id, rank: remote.rank, score: score, games: remote.games, wins: remote.wins)
    }

    /// 我在本周榜上的分数和场次（不在榜上时用进度）
    func remoteWeeklyScore(countryCode: String?, week: DateInterval) -> (points: Int, games: Int, wins: Int, opponents: Int) {
        guard let board = remoteWeeklyBoard(countryCode: countryCode, week: week) else { return (0, 0, 0, 0) }
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

    /// 同一个榜 60 秒内只拉一次；拉完通知界面
    private func refreshRemoteBoard(_ key: String, _ load: @escaping () async throws -> Void) {
        guard isRemote, Date().timeIntervalSince(remoteBoardLoadedAt[key] ?? .distantPast) > 60 else { return }
        remoteBoardLoadedAt[key] = Date()
        Task {
            do {
                try await load()
                emit(.rankingsChanged)
            } catch {
                remoteBoardLoadedAt[key] = nil
            }
        }
    }

    /// 我本月的胜率（my_record）
    func loadRemoteRecord() async throws {
        guard let remote, let me = currentUserId else { return }
        let record: RemoteWinRate = try await remote.rpc("my_record")
        remoteWinRates[me] = Rankings.WinRate(games: record.games, wins: record.wins, opponents: record.opponents, averageGap: record.gap)
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
        cacheRemoteUser(id: item.player.id, nickname: item.player.nickname, rating: item.player.rating)
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
        return challenge
    }

    // MARK: 操作

    func remoteSendChallenge(to targetId: String, court: BadmintonCourt, slot: TimeSlot, message: String) async throws -> Challenge {
        let remote = try requireRemote()
        let id: String = try await remote.rpc("send_challenge", [
            "p_target": targetId,
            "p_venue": court.id,
            "p_starts_at": Self.iso(slot.startTime),
            "p_ends_at": Self.iso(slot.endTime),
            "p_message": message.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        remoteChallengeStatus[targetId] = "already_pending"
        try await refreshRemoteChallenges()
        guard let challenge = db.challenges[id] else { throw BackendError.challengeNotFound }
        return challenge
    }

    func remoteRespondToChallenge(id: String, accept: Bool) async throws -> Game? {
        let remote = try requireRemote()
        let gameId = try await remote.rpc("respond_challenge", ["p_challenge": id, "p_accept": accept], as: String?.self)
        try await refreshRemoteChallenges()
        await refreshRemoteActivity()
        return gameId.flatMap { db.games[$0] }
    }
}
