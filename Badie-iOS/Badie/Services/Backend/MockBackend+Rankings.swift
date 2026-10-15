import Foundation

// MARK: - 赛果确认、胜率与排行榜

extension MockBackend {

    // MARK: 赛果申报

    func winningTeam(in game: Game, for userId: String, didWin: Bool?) -> Int? {
        guard let didWin, let mine = game.team(of: userId) else { return nil }
        return didWin ? mine : game.teams.indices.first { $0 != mine }
    }

    /// 对方先结束了球局时，我来申报 / 确认赛果
    func reportResult(gameId: String, didWin: Bool?, score: String) async throws {
        let me = try requireUser()
        guard let game = db.games[gameId], game.playerIds.contains(me.id) else { throw BackendError.gameNotFound }
        guard game.report(by: me.id) == nil else { throw BackendError.resultAlreadyReported }
        guard game.status == .completed, game.resultStatus() == .awaiting || game.resultStatus() == .disputed
        else { throw BackendError.resultWindowClosed }
        await networkDelay()
        addResultReport(ResultReport(reporterId: me.id, winningTeam: winningTeam(in: game, for: me.id, didWin: didWin),
                                     score: String(score.prefix(40)), reportedAt: Date()), to: gameId)
    }

    /// 记一份申报，并在双方确认后生成计入排行的对局
    func addResultReport(_ report: ResultReport, to gameId: String) {
        guard var game = db.games[gameId], game.team(of: report.reporterId) != nil,
              game.report(by: report.reporterId) == nil else { return }
        let before = game.resultStatus()
        game.resultReports.append(report)
        db.games[gameId] = game
        let after = game.resultStatus()
        guard after != before else { scheduleSave(); emit(.gamesChanged); return }

        switch after {
        case .verified(let winner):
            appendRecord(for: game, winningTeam: winner)
            notifyPlayers(of: game, title: String(localized: "赛果已确认"),
                          body: String(localized: "双方结果一致，已计入本月胜率和排行榜"))
        case .disputed:
            notifyPlayers(of: game, title: String(localized: "赛果有分歧"),
                          body: String(localized: "双方报的结果不一致，这场不计入胜率和排行榜"))
        default:
            break
        }
        scheduleSave()
        emit(.gamesChanged)
        if let me = currentUser { emit(.userUpdated(me)) }
    }

    private func appendRecord(for game: Game, winningTeam: Int) {
        guard !db.matchRecords.contains(where: { $0.id == game.id }) else { return }
        let ratings = Dictionary(uniqueKeysWithValues: game.playerIds.compactMap { id in
            db.users[id].map { (id, $0.displayTier.rating) }
        })
        db.matchRecords.append(MatchRecord(
            id: game.id, date: game.slot.startTime, venueId: game.court.id, countryCode: game.court.countryCode,
            mode: game.mode, teams: game.teams, winningTeam: winningTeam, ratings: ratings
        ))
        for userId in game.teams[winningTeam] { db.users[userId]?.wins += 1 }
    }

    private func notifyPlayers(of game: Game, title: String, body: String) {
        for userId in game.playerIds {
            addInbox(InboxItem(kind: .resultUpdate, title: title, body: body, relatedId: game.id), to: userId)
        }
    }

    /// 模拟球友会如实确认赛果（几秒后）
    func scheduleBotResultReports(gameId: String) {
        simulate(after: Double.random(in: 4...9)) { [weak self] in
            guard let self, let game = self.db.games[gameId], let claimed = game.resultReports.first else { return }
            for botId in game.playerIds where self.isBot(botId) && game.report(by: botId) == nil {
                self.addResultReport(ResultReport(reporterId: botId, winningTeam: claimed.winningTeam,
                                                  score: claimed.score, reportedAt: Date()), to: gameId)
            }
        }
    }

    // MARK: 对局记录

    /// 时间段内所有计入排行的对局：真实球员的 + 模拟球友之间的
    func matchRecords(in interval: DateInterval, now: Date = Date()) -> [MatchRecord] {
        let real = db.matchRecords.filter { interval.contains($0.date) }
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: interval.start)
        var simulated: [MatchRecord] = []
        while day < min(interval.end, now) {
            simulated += botRecords(on: day, now: now)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return real + simulated.filter { interval.contains($0.date) }
    }

    /// 模拟球友某一天在各自常去球馆打的球（按日期和世界中心固定，结果可复现）
    private func botRecords(on day: Date, now: Date) -> [MatchRecord] {
        let key = "\(Int(day.timeIntervalSince1970))-\(Int(db.worldCenter.latitude * 100))-\(Int(db.worldCenter.longitude * 100))"
        if let cached = botRecordCache[key] { return cached.filter { $0.date <= now } }
        var rng = SeededGenerator("records-\(key)")
        let bots = db.bots.keys.sorted().compactMap { db.users[$0] }
        var records: [MatchRecord] = []
        for index in 0..<Int.random(in: 5...9, using: &rng) {
            guard let anchor = bots.randomElement(using: &rng),
                  let venueId = db.favoriteCourtIds[anchor.id]?.first, let court = venue(id: venueId) else { continue }
            let regulars = bots.filter { $0.id != anchor.id && (db.favoriteCourtIds[$0.id] ?? []).contains(venueId) }
            let doubles = regulars.count >= 3 && Double.random(in: 0..<1, using: &rng) < 0.6
            let others = regulars
                .sorted { abs($0.displayTier.rating - anchor.displayTier.rating) < abs($1.displayTier.rating - anchor.displayTier.rating) }
                .prefix(doubles ? 5 : 3).shuffled(using: &rng).prefix(doubles ? 3 : 1)
            guard others.count == (doubles ? 3 : 1) else { continue }
            let players = [anchor] + others
            let teams = doubles
                ? MatchingService.balancedTeams(players: players.map { (id: $0.id, level: $0.displayTier.rating) })
                : players.map { [$0.id] }
            let ratings = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.displayTier.rating) })
            func strength(_ team: [String]) -> Double { team.compactMap { ratings[$0] }.reduce(0, +) / Double(max(team.count, 1)) }
            let chanceFirst = 1 / (1 + exp(-(strength(teams[0]) - strength(teams[1])) * 1.5))
            let hour = Double(Int.random(in: 9...21, using: &rng))
            records.append(MatchRecord(
                id: "bot-record-\(key)-\(index)", date: day.addingTimeInterval(hour * 3600), venueId: venueId,
                countryCode: court.countryCode, mode: doubles ? .doubles : .singles, teams: teams,
                winningTeam: Double.random(in: 0..<1, using: &rng) < chanceFirst ? 0 : 1, ratings: ratings
            ))
        }
        botRecordCache[key] = records
        return records.filter { $0.date <= now }
    }

    // MARK: 胜率

    func winRate(for userId: String, month: DateInterval, now: Date = Date()) -> Rankings.WinRate {
        Rankings.winRate(for: userId, records: matchRecords(in: month, now: now), month: month)
    }

    // MARK: 排行榜

    /// 能否出现在榜单上：本人愿意上榜、注册满 7 天、不在我的屏蔽 / 举报隐藏名单里
    func isListedOnBoards(_ userId: String, now: Date = Date()) -> Bool {
        guard let user = db.users[userId], user.privacy.showsOnLeaderboards else { return false }
        guard now.timeIntervalSince(user.joinDate) >= Double(Rankings.minimumAccountAgeDays) * 86400 else { return false }
        guard let me = currentUserId else { return true }
        return !isBlockedEitherWay(me, userId) && !(db.hiddenFromBoards[me] ?? []).contains(userId)
    }

    /// 我为什么不在榜上（在榜上时为 nil）
    func boardAbsenceReason(now: Date = Date()) -> String? {
        guard let me = currentUser else { return nil }
        if !me.privacy.showsOnLeaderboards { return String(localized: "你在设置里关闭了上榜") }
        let ready = me.joinDate.addingTimeInterval(Double(Rankings.minimumAccountAgeDays) * 86400)
        if now < ready { return String(localized: "注册满 \(Rankings.minimumAccountAgeDays) 天后上榜（\(DateText.shortDay(ready)) 起）") }
        return nil
    }

    /// 场馆月榜：按水平段分开，只返回有人上榜的段
    func venueLeaderboard(venueId: String, month: DateInterval, now: Date = Date()) -> [(bracket: LevelBracket, entries: [Rankings.Entry])] {
        let records = matchRecords(in: month, now: now)
        return LevelBracket.allCases.compactMap { bracket in
            let entries = Rankings.venueBoard(venueId: venueId, records: records, month: month) { userId in
                guard let user = self.db.users[userId] else { return false }
                return LevelBracket(rating: user.displayTier.rating) == bracket && self.isListedOnBoards(userId, now: now)
            }
            return entries.isEmpty ? nil : (bracket, entries)
        }
    }

    /// 全球周榜；传国家代码则只看该国家/地区的对局
    func weeklyLeaderboard(week: DateInterval, countryCode: String? = nil, now: Date = Date()) -> [Rankings.Entry] {
        Array(Rankings.weeklyBoard(records: matchRecords(in: week, now: now), week: week, countryCode: countryCode) {
            self.isListedOnBoards($0, now: now)
        }.prefix(Rankings.boardSize))
    }

    func weeklyScore(for userId: String, week: DateInterval, countryCode: String? = nil,
                     now: Date = Date()) -> (points: Int, games: Int, wins: Int, opponents: Int) {
        let records = matchRecords(in: week, now: now).filter { countryCode == nil || $0.countryCode == countryCode }
        return Rankings.weeklyScore(for: userId, records: records, week: week)
    }

    /// 我所在的国家/地区：离我最近的球馆所在地，其次是设备地区
    var currentCountryCode: String {
        countryCode(near: currentUser?.location ?? db.worldCenter)
            ?? Locale.current.region?.identifier ?? CountryInfo.defaultCountry.code
    }

    func countryCode(near coordinate: Coordinate) -> String? {
        worldVenues.min(by: { $0.distance(from: coordinate) < $1.distance(from: coordinate) })?.countryCode
    }

    /// 举报榜单上的人：先对我隐藏，进入人工复核
    func reportFromLeaderboard(_ userId: String, reason: ReportReason) {
        guard let me = currentUserId, userId != me else { return }
        db.reports.append(ReportRecord(reporterId: me, reportedUserId: userId, reason: reason,
                                       detail: String(localized: "来自排行榜"), createdAt: Date()))
        db.hiddenFromBoards[me, default: []].append(userId)
        scheduleSave()
        emit(.gamesChanged)
    }

    // MARK: 约战

    func challengeAvailability(for targetId: String, now: Date = Date()) -> ChallengeAvailability {
        guard let me = currentUser, let target = db.users[targetId], targetId != me.id,
              !isBlockedEitherWay(me.id, targetId) else { return .unavailable }
        // 只能挑战同一国家/地区的人（不跨国约球）
        if let mine = me.location.flatMap(countryCode(near:)), let theirs = target.location.flatMap(countryCode(near:)),
           mine != theirs { return .unavailable }
        let friends = isFriend(targetId)
        switch target.privacy.challengePolicy {
        case .nobody: return .notAccepting
        case .friends where !friends: return .friendsOnly
        case .similarLevel where !friends && abs(target.displayTier.rating - me.displayTier.rating) > Challenge.similarLevelRange:
            return .levelOutOfRange
        default: break
        }
        let all = challenges(now: now)
        if all.contains(where: { $0.status == .pending && $0.involves(targetId) }) { return .alreadyPending }
        if let last = all.filter({ $0.challengerId == me.id && $0.targetId == targetId && [.declined, .expired].contains($0.status) })
            .max(by: { $0.createdAt < $1.createdAt }) {
            let until = (last.respondedAt ?? last.expiresAt).addingTimeInterval(Challenge.cooldown)
            if now < until { return .cooldown(until: until) }
        }
        let mine = all.filter { $0.challengerId == me.id }
        if mine.filter({ $0.status == .pending }).count >= Challenge.maxOutgoingPending { return .tooManyOutgoing }
        if mine.filter({ Calendar.current.isDate($0.createdAt, inSameDayAs: now) }).count >= Challenge.dailyLimit { return .dailyLimitReached }
        let incoming = db.challenges.values.filter { $0.targetId == targetId && $0.status == .pending && !$0.isExpired(now: now) }
        if incoming.count >= Challenge.maxIncomingPending { return .targetBusy }
        return .available
    }

    /// 和我有关的挑战（新的在前）；过期的顺手标记
    func challenges(now: Date = Date()) -> [Challenge] {
        guard let me = currentUserId else { return [] }
        for (id, challenge) in db.challenges where challenge.isExpired(now: now) {
            db.challenges[id]?.status = .expired
        }
        return db.challenges.values.filter { $0.involves(me) }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func sendChallenge(to targetId: String, court: BadmintonCourt, slot: TimeSlot, message: String) async throws -> Challenge {
        let me = try requireUser()
        let availability = challengeAvailability(for: targetId)
        if let reason = availability.reason { throw BackendError.challengeUnavailable(reason) }
        if case .invalid(let reason) = slot.validate() { throw BackendError.invalidSlot(reason) }
        let note = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Challenge.messageLimit))
        guard !Self.advertises(note) else { throw BackendError.requestContainsContact }
        await networkDelay()
        let challenge = Challenge(id: UUID().uuidString, challengerId: me.id, targetId: targetId, court: court, slot: slot,
                                  message: note, createdAt: Date(), status: .pending)
        db.challenges[challenge.id] = challenge
        addInbox(InboxItem(kind: .challenge, title: String(localized: "\(me.nickname) 向你发起单打挑战"),
                           body: "\(slot.formattedFull) · \(court.name)", relatedId: challenge.id), to: targetId)
        if isBot(targetId) { scheduleBotChallengeResponse(challengeId: challenge.id) }
        scheduleSave()
        emit(.gamesChanged)
        return challenge
    }

    /// 接受：生成一场单打球局（计入排行）；拒绝：对方只会看到“未成行”
    @discardableResult
    func respondToChallenge(id: String, accept: Bool) async throws -> Game? {
        let me = try requireUser()
        guard var challenge = db.challenges[id], challenge.targetId == me.id,
              challenge.status == .pending, !challenge.isExpired() else { throw BackendError.challengeNotFound }
        await networkDelay()
        return settle(&challenge, accept: accept)
    }

    func withdrawChallenge(id: String) {
        guard let me = currentUserId, var challenge = db.challenges[id], challenge.challengerId == me,
              challenge.status == .pending else { return }
        challenge.status = .withdrawn
        challenge.respondedAt = Date()
        db.challenges[id] = challenge
        scheduleSave()
        emit(.gamesChanged)
    }

    @discardableResult
    private func settle(_ challenge: inout Challenge, accept: Bool) -> Game? {
        challenge.status = accept ? .accepted : .declined
        challenge.respondedAt = Date()
        var game: Game?
        if accept, let target = db.users[challenge.targetId] {
            let created = Game(
                id: UUID().uuidString, mode: .singles, court: challenge.court, slot: challenge.slot,
                playerIds: [challenge.challengerId, challenge.targetId],
                teams: [[challenge.challengerId], [challenge.targetId]], hostId: challenge.challengerId,
                origin: .challenge(id: challenge.id), status: .confirmed, createdAt: Date(), checkIns: [:], paidPlayerIds: [],
                cost: CostSplit.estimate(court: challenge.court, slot: challenge.slot, mode: .singles),
                result: nil, cancelledBy: nil, cancelledLate: false, reminderEnabled: false
            )
            db.games[created.id] = created
            ensureGameThread(for: created)
            challenge.gameId = created.id
            addInbox(InboxItem(kind: .challenge, title: String(localized: "\(target.nickname) 接受了你的挑战"),
                               body: "\(challenge.slot.formattedFull) · \(challenge.court.name)", relatedId: created.id),
                     to: challenge.challengerId)
            game = created
            emit(.gameCreated(created))
        }
        db.challenges[challenge.id] = challenge
        scheduleSave()
        emit(.gamesChanged)
        return game
    }

    private func scheduleBotChallengeResponse(challengeId: String) {
        simulate(after: Double.random(in: 6...15)) { [weak self] in
            guard let self, var challenge = self.db.challenges[challengeId], challenge.status == .pending,
                  let bot = self.db.bots[challenge.targetId] else { return }
            var rng = SeededGenerator(challengeId)
            self.settle(&challenge, accept: Double.random(in: 0..<1, using: &rng) < bot.friendliness * 0.85)
        }
    }
}
