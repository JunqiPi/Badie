import Foundation

// MARK: - 匹配、球局、签到、互评

extension MockBackend {

    // MARK: Matching

    func findMatches(_ request: MatchRequest) async throws -> MatchSearchResult {
        let me = try requireUser()
        guard me.attendance.standing != .suspended else { throw BackendError.matchingSuspended }
        await networkDelay(0.5...1.0)
        var request = request
        request.excludedUserIds.formUnion(blockedIds())
        request.excludedUserIds.formUnion(db.bots.keys.filter { blockedIds(of: $0).contains(me.id) })
        let pool = availabilityPool(on: request.slot.date)
        let proposals = MatchingService.proposals(for: request, pool: pool)
        if proposals.isEmpty {
            return .none(suggestions: MatchingService.suggestions(for: request, pool: pool))
        }
        return .proposals(proposals)
    }

    func confirm(_ proposal: MatchProposal) async throws -> Game {
        let me = try requireUser()
        guard proposal.slot.endTime > Date() else { throw BackendError.invalidSlot("这个时间段已经过去了") }
        await networkDelay()
        let ids = [me.id] + proposal.others.map(\.user.id)
        let game = Game(
            id: UUID().uuidString,
            mode: proposal.mode,
            court: proposal.court,
            slot: proposal.slot,
            playerIds: ids,
            teams: proposal.teams,
            hostId: me.id,
            origin: .quickMatch,
            status: .confirmed,
            createdAt: Date(),
            checkIns: [:],
            paidPlayerIds: [],
            cost: proposal.cost,
            result: nil,
            cancelledBy: nil,
            cancelledLate: false,
            reminderEnabled: false
        )
        db.games[game.id] = game
        scheduleSave()
        emit(.gameCreated(game))
        emit(.gamesChanged)

        // 对手发来确认消息，自然开启聊天
        if let first = proposal.others.first?.user.id, isBot(first) {
            let threadId = MessageThread.id(for: me.id, first)
            let text = "收到约球！\(proposal.slot.formattedDate) \(DateText.time(proposal.slot.startTime)) \(proposal.court.name) 见～"
            simulate(after: Double.random(in: 2...4)) { [weak self] in
                guard let self else { return }
                self.appendMessage(Message(threadId: threadId, senderId: first, content: text, deliveredAt: Date()),
                                   participants: [me.id, first], countsAsUnread: true)
            }
        }
        return game
    }

    // MARK: Games

    func games() -> [Game] {
        guard let me = currentUserId else { return [] }
        return db.games.values.filter { $0.playerIds.contains(me) }
    }

    func game(id: String) -> Game? { db.games[id] }

    func cancelGame(id: String) async throws {
        var me = try requireUser()
        guard var game = db.games[id], game.playerIds.contains(me.id) else { throw BackendError.gameNotFound }
        guard game.status == .confirmed, game.slot.endTime > Date() else { throw BackendError.gameAlreadyFinished }
        await networkDelay()
        let late = game.isLateCancellation()
        game.status = .cancelled
        game.cancelledBy = me.id
        game.cancelledLate = late
        db.games[id] = game
        if late {
            me.attendance.lateCancellations += 1
            db.users[me.id] = me
            emit(.userUpdated(me))
        }
        for other in game.otherPlayerIds(excluding: me.id) {
            addInbox(InboxItem(kind: .gameCancelled, title: "\(me.nickname) 取消了球局",
                               body: "\(game.slot.formattedFull) · \(game.court.name)", relatedId: game.id), to: other)
            if isBot(other) {
                let threadId = MessageThread.id(for: me.id, other)
                simulate(after: Double.random(in: 2...5)) { [weak self] in
                    self?.appendMessage(Message(threadId: threadId, senderId: other, content: "好的，那下次再约～", deliveredAt: Date()),
                                        participants: [me.id, other], countsAsUnread: true)
                }
            }
        }
        scheduleSave()
        emit(.gamesChanged)
    }

    func checkIn(gameId: String) async throws -> Game {
        let me = try requireUser()
        guard var game = db.games[gameId], game.playerIds.contains(me.id) else { throw BackendError.gameNotFound }
        guard game.canCheckIn() else { throw BackendError.checkInNotOpen }
        await networkDelay()
        game.checkIns[me.id] = Date()
        db.games[gameId] = game
        scheduleSave()
        emit(.gamesChanged)
        // 其他球友陆续签到
        for (index, other) in game.otherPlayerIds(excluding: me.id).enumerated() where isBot(other) {
            simulate(after: Double(index + 1) * Double.random(in: 2...5)) { [weak self] in
                guard let self, var current = self.db.games[gameId], current.status == .confirmed,
                      current.checkIns[other] == nil else { return }
                current.checkIns[other] = Date()
                self.db.games[gameId] = current
                self.scheduleSave()
                self.emit(.gamesChanged)
            }
        }
        return game
    }

    /// 标记 AA 已付：本人可标记自己，发起人可标记所有人
    func togglePaid(gameId: String, userId: String) {
        guard let me = currentUserId, var game = db.games[gameId] else { return }
        guard userId == me || game.hostId == me else { return }
        if let index = game.paidPlayerIds.firstIndex(of: userId) {
            game.paidPlayerIds.remove(at: index)
        } else {
            game.paidPlayerIds.append(userId)
        }
        db.games[gameId] = game
        scheduleSave()
        emit(.gamesChanged)
    }

    func setReminder(gameId: String, enabled: Bool) {
        guard var game = db.games[gameId] else { return }
        game.reminderEnabled = enabled
        db.games[gameId] = game
        scheduleSave()
        emit(.gamesChanged)
    }

    /// 结束球局：记录结果，生成互评问卷
    func completeGame(id: String, didWin: Bool?, score: String) async throws {
        var me = try requireUser()
        guard var game = db.games[id], game.playerIds.contains(me.id) else { throw BackendError.gameNotFound }
        guard game.status == .confirmed else { throw BackendError.gameAlreadyFinished }
        guard game.canComplete() else { throw BackendError.invalidSlot("球局开始后才能标记完成") }
        await networkDelay()
        let now = Date()
        game.status = .completed
        confirmVenueFromCheckIns(game)
        game.result = GameResult(didWin: didWin, score: String(score.prefix(40)))
        db.games[id] = game

        me.totalGames += 1
        if didWin == true { me.wins += 1 }
        me.attendance.gamesPlayed += 1
        db.users[me.id] = me

        let expiresAt = max(now, game.slot.endTime).addingTimeInterval(PendingSurvey.validityDuration)
        for otherId in game.otherPlayerIds(excluding: me.id) {
            guard var other = db.users[otherId] else { continue }
            other.totalGames += 1
            db.users[otherId] = other
            if !db.pendingSurveys.contains(where: { $0.matchId == id && $0.evaluatorId == me.id && $0.opponentId == otherId }) {
                db.pendingSurveys.append(PendingSurvey(
                    id: UUID().uuidString, matchId: id, evaluatorId: me.id, opponentId: otherId,
                    opponentNickname: other.nickname, opponentLevel: other.displayLevel, opponentAvatar: other.avatar,
                    courtName: game.court.name, matchDate: game.slot.startTime, expiresAt: expiresAt
                ))
            }
            // 机器人对我的评价：到场是否准时以签到数据为准（客观），暂存等待双盲揭晓
            if isBot(otherId) {
                let checkIn = game.checkIns[me.id]
                let attendance: AttendanceAnswer
                if let checkIn {
                    attendance = checkIn <= game.slot.startTime.addingTimeInterval(5 * 60) ? .onTime : .late
                } else {
                    attendance = .onTime
                }
                var rng = SeededGenerator("\(id)-\(otherId)")
                let drift = [0, 0, 0, -1, 1].randomElement(using: &rng) ?? 0
                db.heldSurveys.append(MatchSurvey(
                    id: UUID().uuidString, matchId: id, evaluatorId: otherId, evaluatedUserId: me.id,
                    skillRating: SkillLevel.clamp(me.displayLevel + drift), wasPunctual: attendance.wasPunctual,
                    attendance: attendance, characterRating: [5, 5, 4].randomElement(using: &rng) ?? 5,
                    tags: [SurveyTag.friendly, .punctual, .fairPlay].shuffled(using: &rng).prefix(2).map { $0 },
                    submittedAt: now
                ))
            }
        }
        addInbox(InboxItem(kind: .surveyDue, title: "球局完成，给球友们评个分吧",
                           body: "48 小时内有效 · 评价匿名汇总，双方都提交后才计入", relatedId: id), to: me.id)
        scheduleSave()
        emit(.userUpdated(me))
        emit(.gamesChanged)
        emit(.surveysChanged)
    }

    // MARK: Surveys

    func pendingSurveys(now: Date = Date()) -> [PendingSurvey] {
        guard let me = currentUserId else { return [] }
        return db.pendingSurveys
            .filter { $0.evaluatorId == me && !$0.isExpired(now: now) }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    func hasSubmittedSurvey(matchId: String, evaluatorId: String, evaluatedUserId: String) -> Bool {
        db.surveys.contains { $0.matchId == matchId && $0.evaluatorId == evaluatorId && $0.evaluatedUserId == evaluatedUserId }
    }

    func submitSurvey(
        pendingId: String,
        skillRating: Int,
        attendance: AttendanceAnswer,
        characterRating: Int,
        tags: [SurveyTag]
    ) async throws {
        let me = try requireUser()
        guard let pending = db.pendingSurveys.first(where: { $0.id == pendingId && $0.evaluatorId == me.id }) else {
            throw BackendError.surveyExpired
        }
        if pending.isExpired() {
            db.pendingSurveys.removeAll { $0.id == pendingId }
            scheduleSave()
            emit(.surveysChanged)
            throw BackendError.surveyExpired
        }
        guard !hasSubmittedSurvey(matchId: pending.matchId, evaluatorId: me.id, evaluatedUserId: pending.opponentId) else {
            db.pendingSurveys.removeAll { $0.id == pendingId }
            throw BackendError.surveyDuplicate
        }
        let survey = MatchSurvey(
            id: UUID().uuidString,
            matchId: pending.matchId,
            evaluatorId: me.id,
            evaluatedUserId: pending.opponentId,
            skillRating: skillRating,
            wasPunctual: attendance.wasPunctual,
            attendance: attendance,
            characterRating: characterRating,
            tags: tags,
            submittedAt: Date()
        )
        guard survey.isValid else { throw BackendError.surveyInvalid }
        await networkDelay()

        db.surveys.append(survey)
        db.pendingSurveys.removeAll { $0.id == pendingId }
        apply(survey)

        // 双盲：我提交后，对方对我的评价随之生效
        let released = db.heldSurveys.filter { $0.matchId == pending.matchId && $0.evaluatedUserId == me.id && $0.evaluatorId == pending.opponentId }
        if !released.isEmpty {
            db.heldSurveys.removeAll { held in released.contains { $0.id == held.id } }
            for item in released {
                db.surveys.append(item)
                apply(item)
            }
            addInbox(InboxItem(kind: .reviewReceived, title: "你收到了新的球友评价",
                               body: "评价已匿名计入你的口碑与综合水平。", relatedId: me.id), to: me.id)
        }
        scheduleSave()
        emit(.surveysChanged)
        if let updated = currentUser { emit(.userUpdated(updated)) }
        if let opponent = db.users[pending.opponentId] { emit(.userUpdated(opponent)) }
    }

    /// 把一份评价计入被评价者的声誉与履约记录
    private func apply(_ survey: MatchSurvey) {
        guard var target = db.users[survey.evaluatedUserId] else { return }
        target.reputation = target.reputation.adding(survey, selfReportedLevel: target.selfReportedLevel)
        if survey.attendance == .noShow {
            target.attendance.noShows += 1
            target.attendance.gamesPlayed = max(0, target.attendance.gamesPlayed - 1)
        }
        db.users[target.id] = target
    }

    /// 处理过期：未在 48 小时内提交的问卷作废；暂存的评价在窗口结束后揭晓
    func processSurveyExpirations(now: Date = Date()) {
        let before = db.pendingSurveys.count
        db.pendingSurveys.removeAll { $0.isExpired(now: now) }
        var changed = before != db.pendingSurveys.count

        let due = db.heldSurveys.filter { held in
            guard let game = db.games[held.matchId] else { return true }
            return now > game.slot.endTime.addingTimeInterval(PendingSurvey.validityDuration)
        }
        if !due.isEmpty {
            db.heldSurveys.removeAll { held in due.contains { $0.id == held.id } }
            for item in due {
                db.surveys.append(item)
                apply(item)
            }
            changed = true
            if let me = currentUser { emit(.userUpdated(me)) }
        }
        if changed {
            scheduleSave()
            emit(.surveysChanged)
        }
    }
}
