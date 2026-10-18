import Foundation

// MARK: - 正式后端：约球请求、提议、球局、赛果、评价
/// 服务器是唯一的数据来源：每次操作后重新拉取 my_matchmaking 和 my_games 写进缓存，
/// 界面照旧读缓存；MatchManager 每 15 秒调一次 processMatchmaking，在这个模式下就是刷新
extension MockBackend {

    struct RemotePlace: Decodable {
        struct Pricing: Decodable {
            let perPerson: Double?
            let perCourtHour: Double?
        }

        let id: String
        let name: String
        let city: String?
        let street: String?
        let tz: String?
        let lat: Double?
        let lon: Double?
        let country: String?
        let pricing: Pricing?
    }

    struct RemotePlayer: Decodable {
        let id: String
        let nickname: String
        let rating: Double
        let team: Int
        let me: Bool
        let checkedIn: Bool?
        let reviewed: Bool?
    }

    struct RemoteOffer: Decodable {
        let id: String
        let startsAt: Date
        let endsAt: Date
        let respondBy: Date
        let myResponse: String
        let lockAt: Date?
        let venue: RemotePlace
        let accepted: Int
        let players: [RemotePlayer]?
    }

    struct RemoteTicket: Decodable {
        let id: String
        let mode: String
        let startsAt: Date
        let endsAt: Date
        let status: String
        let skillTolerance: Int
        let autoAccept: Bool
        let lockAt: Date
        let lastMinute: Bool?
        let gameId: String?
        let venues: [RemotePlace]?
        let offer: RemoteOffer?
    }

    struct RemoteGame: Decodable {
        struct Report: Decodable {
            let outcome: String?
        }

        struct Result: Decodable {
            let status: String
            let outcome: String?
        }

        let id: String
        let mode: String
        let startsAt: Date
        let endsAt: Date
        let status: String
        let venue: RemotePlace
        let myTeam: Int
        let checkedIn: Bool
        let myReport: Report?
        let result: Result?
        let reviewUntil: Date
        let players: [RemotePlayer]?
    }

    // MARK: 刷新

    /// 拉取我的请求、提议、球局、球友、会话、通知写进缓存。force 为 false 时 10 秒内只刷新一次
    func refreshRemoteActivity(force: Bool = true) async {
        guard let remote, let me = currentUser else { return }
        if !force, let last = remoteRefreshedAt, Date().timeIntervalSince(last) < 10 { return }
        remoteRefreshedAt = Date()
        do {
            let tickets: [RemoteTicket] = try await remote.rpc("my_matchmaking")
            let games: [RemoteGame] = try await remote.rpc("my_games")
            apply(tickets: tickets, games: games, me: me)
            try await refreshRemoteSocial()
            try await refreshRemoteGroups()
            try await refreshRemoteRooms()
            try await refreshRemoteChallenges()
        } catch RemoteError.notSignedIn {
            signOutLocally()
        } catch {
            // 网络问题：保留缓存，下次再刷新
        }
    }

    private func apply(tickets: [RemoteTicket], games: [RemoteGame], me: User) {
        var ticketCache: [String: MatchTicket] = [:]
        var offerCache: [String: MatchOffer] = [:]
        for remoteTicket in tickets {
            let ticket = ticket(from: remoteTicket, me: me)
            ticketCache[ticket.id] = ticket
            if let remoteOffer = remoteTicket.offer {
                offerCache[remoteOffer.id] = offer(from: remoteOffer, mode: ticket.mode, lastMinute: ticket.isLastMinute)
            }
        }
        var gameCache: [String: Game] = [:]
        for remoteGame in games {
            gameCache[remoteGame.id] = game(from: remoteGame, me: me)
        }
        let changed = ticketCache != db.tickets || offerCache != db.offers
        let gamesChanged = gameCache != db.games
        db.tickets = ticketCache
        db.offers = offerCache
        db.games = gameCache
        db.pendingSurveys = pendingSurveys(from: games, me: me)
        scheduleSave()
        if changed { emit(.matchmakingChanged) }
        if gamesChanged { emit(.gamesChanged) }
        emit(.surveysChanged)
    }

    // MARK: 操作

    func remoteSubmitTicket(mode: GameMode, slot: TimeSlot, courtIds: [String], skillTolerance: Int, autoAccept: Bool) async throws -> MatchTicket {
        let remote = try requireRemote()
        let id: String = try await remote.rpc("submit_ticket", [
            "p_mode": mode.serverValue,
            "p_starts_at": Self.iso(slot.startTime),
            "p_ends_at": Self.iso(slot.endTime),
            "p_venue_ids": courtIds,
            "p_skill_tolerance": skillTolerance,
            "p_auto_accept": autoAccept,
        ])
        await refreshRemoteActivity()
        guard let ticket = db.tickets[id] else { throw RemoteError.server("bad_response") }
        return ticket
    }

    /// 同步接口里的服务器操作：先改本地（界面马上有反应），再让服务器处理；失败就提示并按服务器的数据恢复
    func runRemote(_ update: () -> Void = {}, _ operation: @escaping (SupabaseClient) async throws -> Void) {
        guard let remote else { return }
        update()
        Task {
            do {
                try await operation(remote)
            } catch {
                emit(.remoteFailed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
            await refreshRemoteActivity()
        }
    }

    /// 赛果：didWin 为 nil 表示友谊局（不计胜负），unsure 表示记不清
    func remoteReportResult(gameId: String, didWin: Bool?, unsure: Bool = false) async throws {
        let remote = try requireRemote()
        guard let game = db.games[gameId], let me = currentUserId, let mine = game.team(of: me) else { throw BackendError.gameNotFound }
        let outcome: Any
        if unsure {
            outcome = NSNull()
        } else if let didWin {
            outcome = "team\((didWin ? mine : 1 - mine) + 1)"
        } else {
            outcome = "friendly"
        }
        try await remote.call("report_result", ["p_game": gameId, "p_outcome": outcome])
        await refreshRemoteActivity()
    }

    /// 赛后评价。等级按“比对方显示的档位高 / 低 / 差不多”换算
    func remoteSubmitSurvey(_ pending: PendingSurvey, skillRating: Double, attendance: AttendanceAnswer,
                            tags: [SurveyTag], issues: [SurveyIssue], wantsRematch: Bool) async throws {
        let remote = try requireRemote()
        let difference = SkillTier(rating: skillRating).rating - pending.opponentTier.rating
        let level = difference < -0.01 ? "lower" : difference > 0.01 ? "higher" : "accurate"
        try await remote.call("review_player", [
            "p_game": pending.matchId,
            "p_user": pending.opponentId,
            "p_attendance": attendance.serverValue,
            "p_level": level,
            "p_tags": tags.map(\.serverValue),
            "p_issues": issues.map(\.serverValue),
            "p_play_again": wantsRematch,
        ])
        db.pendingSurveys.removeAll { $0.id == pending.id }
        emit(.surveysChanged)
        await refreshRemoteActivity()
    }

    // MARK: 服务器数据 → 本地模型

    private func ticket(from remote: RemoteTicket, me: User) -> MatchTicket {
        let status: MatchTicket.Status
        switch remote.status {
        case "offered": status = remote.offer.map { .offered(offerId: $0.id) } ?? .searching
        case "matched": status = remote.gameId.map { .matched(gameId: $0) } ?? .expired
        case "paused": status = .paused
        case "expired": status = .expired
        case "cancelled": status = .cancelled
        default: status = .searching
        }
        return MatchTicket(
            id: remote.id, userId: me.id, mode: GameMode(server: remote.mode),
            slot: TimeSlot(date: remote.startsAt, startTime: remote.startsAt, endTime: remote.endsAt),
            courtIds: (remote.venues ?? []).map(\.id), skillTolerance: remote.skillTolerance, radiusKm: 0,
            origin: me.location ?? db.worldCenter, autoAccept: remote.autoAccept, isLastMinute: remote.lastMinute ?? false, status: status,
            createdAt: db.tickets[remote.id]?.createdAt ?? Date(), deadline: remote.lockAt, hasPriority: false, excludedUserIds: []
        )
    }

    private func offer(from remote: RemoteOffer, mode: GameMode, lastMinute: Bool) -> MatchOffer {
        let players = remote.players ?? []
        players.forEach { cachePlayer($0) }
        let slot = TimeSlot(date: remote.startsAt, startTime: remote.startsAt, endTime: remote.endsAt)
        let court = court(for: remote.venue)
        // 服务器不告诉别人谁确认了，只给人数：自己按实际，其他人按人数依次标记（界面只显示人数）
        var othersAccepted = remote.accepted - (remote.myResponse == "accepted" ? 1 : 0)
        let seats = players.map { player -> MatchOffer.Seat in
            let accepted: Bool
            if player.me {
                accepted = remote.myResponse == "accepted"
            } else {
                accepted = othersAccepted > 0
                othersAccepted -= 1
            }
            return MatchOffer.Seat(userId: player.id, ticketId: nil, response: accepted ? .accepted : .pending,
                                   respondBy: remote.respondBy, respondedAt: nil)
        }
        return MatchOffer(
            id: remote.id, mode: mode, slot: slot, commonOverlap: slot, court: court,
            teams: [1, 2].map { team in players.filter { $0.team == team }.map(\.id) },
            seats: seats, cost: CostSplit.estimate(court: court, slot: slot, mode: mode), compatibility: 0,
            createdAt: db.offers[remote.id]?.createdAt ?? Date(),
            lockAt: remote.lockAt ?? MatchTiming.lock(start: remote.startsAt, lastMinute: lastMinute),
            isLastMinute: lastMinute, status: .open, backfillCount: 0
        )
    }

    private func game(from remote: RemoteGame, me: User) -> Game {
        let players = remote.players ?? []
        players.forEach { cachePlayer($0) }
        let mode = GameMode(server: remote.mode)
        let slot = TimeSlot(date: remote.startsAt, startTime: remote.startsAt, endTime: remote.endsAt)
        let court = court(for: remote.venue)
        let teams = [1, 2].map { team in players.filter { $0.team == team }.map(\.id) }
        let cached = db.games[remote.id]
        var checkIns: [String: Date] = [:]
        for player in players where player.checkedIn == true {
            checkIns[player.id] = cached?.checkIns[player.id] ?? Date()
        }
        let reports = resultReports(for: remote, teams: teams, me: me.id)
        let status: GameStatus = remote.status == "cancelled" ? .cancelled : remote.myReport == nil ? .confirmed : .completed
        let mine = reports.first { $0.reporterId == me.id }
        let myTeam = remote.myTeam - 1
        return Game(
            id: remote.id, mode: mode, court: court, slot: slot, playerIds: players.map(\.id), teams: teams,
            hostId: players.first?.id ?? me.id, origin: .quickMatch, status: status, createdAt: cached?.createdAt ?? remote.startsAt,
            checkIns: checkIns, paidPlayerIds: [], cost: CostSplit.estimate(court: court, slot: slot, mode: mode),
            result: mine.map { report in GameResult(didWin: report.unsure ? nil : report.winningTeam.map { $0 == myTeam }, score: "") },
            cancelledBy: nil, cancelledLate: false, reminderEnabled: cached?.reminderEnabled ?? true, resultReports: reports
        )
    }

    /// 服务器只给我报的结果和总体状态；按状态补上对方那一方的申报，让本地的赛果状态和服务器一致
    private func resultReports(for remote: RemoteGame, teams: [[String]], me: String) -> [ResultReport] {
        let index = { (outcome: String?) -> Int? in outcome == "team1" ? 0 : outcome == "team2" ? 1 : nil }
        let myTeam = remote.myTeam - 1
        guard teams.count == 2, teams.indices.contains(myTeam) else { return [] }
        let opponents = teams[1 - myTeam]
        var reports: [ResultReport] = []
        if let report = remote.myReport {
            reports.append(ResultReport(reporterId: me, winningTeam: index(report.outcome), score: "", reportedAt: Date(),
                                        unsure: report.outcome == nil))
        }
        guard let result = remote.result, let opponent = opponents.first else { return reports }
        switch result.status {
        case "verified":
            reports.append(ResultReport(reporterId: opponent, winningTeam: index(result.outcome), score: "", reportedAt: Date()))
        case "disputed":
            let mine = reports.first?.winningTeam
            reports.append(ResultReport(reporterId: opponent, winningTeam: mine == 0 ? 1 : 0, score: "", reportedAt: Date()))
        case "unsure" where remote.myReport?.outcome != nil:
            reports += opponents.map { ResultReport(reporterId: $0, winningTeam: nil, score: "", reportedAt: Date(), unsure: true) }
        default:
            break
        }
        return reports
    }

    /// 结束 48 小时内、还没评的球友
    private func pendingSurveys(from games: [RemoteGame], me: User, now: Date = Date()) -> [PendingSurvey] {
        games.filter { $0.status != "cancelled" && $0.endsAt <= now && now < $0.reviewUntil }.flatMap { game in
            (game.players ?? []).filter { !$0.me && $0.reviewed != true }.map { player in
                PendingSurvey(
                    id: "\(game.id)|\(player.id)", matchId: game.id, evaluatorId: me.id, opponentId: player.id,
                    opponentNickname: player.nickname, opponentLevel: SkillTier(rating: player.rating).level,
                    opponentAvatar: db.users[player.id]?.avatar ?? .default(for: player.id), courtName: game.venue.name,
                    matchDate: game.startsAt, expiresAt: game.reviewUntil, opponentRating: player.rating
                )
            }
        }
    }

    /// 同局球友：服务器只给昵称和等级，存进缓存让界面能显示
    private func cachePlayer(_ player: RemotePlayer) {
        guard !player.me else { return }
        var user = db.users[player.id] ?? User(id: player.id, nickname: player.nickname, phone: "",
                                               selfReportedLevel: SkillTier(rating: player.rating).level)
        user.nickname = player.nickname
        user.selfReportedRating = player.rating
        db.users[player.id] = user
    }

    /// 球馆：优先用本地球馆库（信息更全），库里没有就用服务器给的基本信息
    func court(for place: RemotePlace) -> BadmintonCourt {
        if let venue = venue(id: place.id), venue.location.latitude != 0 || place.lat == nil { return venue }
        let pricing: VenuePricing
        if let perPerson = place.pricing?.perPerson {
            pricing = .dropIn(perPerson: Int(perPerson.rounded()))
        } else if let perCourtHour = place.pricing?.perCourtHour {
            pricing = .perCourtHour(Int(perCourtHour.rounded()))
        } else {
            pricing = .unknown
        }
        // 存进本地球馆库，其他页面也能按 ID 找到
        let court = BadmintonCourt(
            id: place.id, name: place.name, location: Coordinate(latitude: place.lat ?? 0, longitude: place.lon ?? 0),
            address: PostalAddress(street: place.street ?? "", city: place.city ?? "", region: "", countryCode: place.country ?? "US"),
            timeZoneId: place.tz, pricing: pricing, source: .player, status: .unconfirmed
        )
        db.venues[place.id] = court
        return court
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - 服务器的写法

extension GameMode {
    init(server value: String) {
        self = value == "singles" ? .singles : .doubles
    }

    var serverValue: String { self == .singles ? "singles" : "doubles" }
}

extension AttendanceAnswer {
    var serverValue: String {
        switch self {
        case .onTime: return "on_time"
        case .late: return "late"
        case .noShow: return "no_show"
        }
    }
}

extension SurveyTag {
    var serverValue: String {
        switch self {
        case .friendly: return "friendly"
        case .punctual: return "punctual"
        case .skilled: return "skilled"
        case .patient: return "patient"
        case .fairPlay: return "fair_play"
        case .greatPartner: return "great_partner"
        }
    }
}

extension SurveyIssue {
    var serverValue: String {
        switch self {
        case .unsafePlay: return "unsafe_play"
        case .rude: return "rude"
        case .hogging: return "hogging"
        case .unpaid: return "unpaid"
        }
    }
}
