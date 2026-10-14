import Foundation

// MARK: - 模拟世界：附近球友、空闲时间、公开球局、演示内容

extension MockBackend {

    /// 机器人球友名单（昵称、等级、空闲模式、性别、简介）；8 级以上的按认证档位处理
    private static let botRoster: [(String, Int, AvailabilityPattern, Gender, String)] = [
        ("小明", 6, .weekdayEvenings, .male, "反手还在练，求虐"),
        ("小红", 7, .flexible, .female, "前校队，双打找固定搭档"),
        ("大伟", 2, .weekendDaytime, .male, "刚入坑三个月，欢迎带带我"),
        ("小李", 5, .weekdayEvenings, .male, "下班就想出出汗"),
        ("琳琳", 4, .weekdayEvenings, .female, "混双爱好者 🏸"),
        ("老周", 5, .mornings, .male, "晨练党，七点场常驻"),
        ("阿飞", 6, .nightOwl, .male, "杀球爱好者"),
        ("思思", 3, .flexible, .female, "欢乐局优先，打完一起吃饭"),
        ("浩然", 4, .weekdayEvenings, .male, "公司羽毛球社社长"),
        ("子轩", 5, .nightOwl, .male, "晚上十点后也能打"),
        ("雨桐", 3, .weekendDaytime, .female, "周末下午有空"),
        ("一帆", 7, .weekdayEvenings, .male, "业余比赛常客"),
        ("小鹿", 2, .flexible, .female, "新手友好局求带"),
        ("嘉怡", 4, .weekendDaytime, .female, "双打轮转练习中"),
        ("宇航", 6, .weekdayEvenings, .male, "单打对抗为主"),
        ("欣然", 5, .flexible, .female, "能打能聊"),
        ("晓峰", 3, .weekdayEvenings, .male, "体能一般但很准时"),
        ("陈陈", 4, .nightOwl, .unspecified, "夜猫子球友"),
        ("王教练", 8, .mornings, .male, "前省队，周末带训练"),
        ("Leo", 5, .weekdayEvenings, .male, "Happy to play in English too"),
        ("Coco", 3, .flexible, .female, "刚搬来这边，找固定球友"),
        ("汤圆", 2, .weekendDaytime, .unspecified, "欢乐第一，比赛第二"),
        ("大鹏", 6, .weekdayEvenings, .male, "喜欢多拍拉吊"),
        ("叶子", 4, .mornings, .female, "早起打球一天都精神"),
        ("球球", 5, .nightOwl, .female, "有固定场地，常缺人"),
        ("方块", 3, .weekdayEvenings, .male, "网前小能手"),
        ("阿May", 6, .flexible, .female, "女双找搭档"),
        ("铁柱", 4, .weekdayEvenings, .male, "从不迟到")
    ]

    /// 首次启动时生成机器人球友
    func ensureWorld() {
        guard db.bots.isEmpty else { return }
        for (index, entry) in Self.botRoster.enumerated() {
            let id = "bot-\(index)"
            var rng = SeededGenerator(id)
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let radius = Double.random(in: 0.6...8.5, using: &rng)
            let evaluations = index == 2 ? 3 : Int.random(in: 5...40, using: &rng)
            let level = entry.1
            let peerAverage = min(9, max(1, Double(level) + Double.random(in: -0.6...0.4, using: &rng)))
            var reputation = ReputationScore(
                evaluationCount: evaluations,
                peerLevelAverage: peerAverage,
                averageSkillDeviation: Double.random(in: 0.1...1.0, using: &rng),
                punctualityPercentage: Double(Int.random(in: 78...100, using: &rng)),
                averageCharacterRating: Double.random(in: 3.8...4.9, using: &rng)
            )
            // 正面标签用独立随机源，不影响其他属性的生成
            var tagRng = SeededGenerator("\(id)-tags")
            if evaluations >= ReputationScore.publicMinimumRaters {
                reputation.publicTags = Array(SurveyTag.allCases.shuffled(using: &tagRng).prefix(Int.random(in: 1...3, using: &tagRng)))
                reputation.publishedAt = Date()
            }
            let games = evaluations + Int.random(in: 2...30, using: &rng)
            let noShows = index % 9 == 4 ? 1 : 0
            let user = User(
                id: id,
                nickname: entry.0,
                phone: "+1626555" + String(format: "%04d", Int.random(in: 0...9999, using: &rng)),
                gender: entry.3,
                bio: entry.4,
                avatar: Avatar(symbol: "", paletteIndex: index % 6),
                selfReportedLevel: min(level, SkillLevel.maxSelfSelectable),
                totalGames: games,
                wins: Int(Double(games) * Double.random(in: 0.35...0.7, using: &rng)),
                joinDate: Date().addingTimeInterval(-Double(Int.random(in: 20...600, using: &rng)) * 86400),
                lastActiveAt: Date().addingTimeInterval(-Double(Int.random(in: 1...300, using: &rng)) * 60),
                reputation: reputation,
                attendance: AttendanceRecord(gamesPlayed: games, noShows: noShows, lateCancellations: index % 7 == 3 ? 1 : 0),
                preferredMode: index % 3 == 0 ? .singles : .doubles
            )
            db.users[id] = user
            // 细分档位：同一级里有 −/本级/+（独立随机源，不影响其他属性）
            var tierRng = SeededGenerator("\(id)-tier")
            let shift = Double(Int.random(in: -1...1, using: &tierRng)) / 3
            let selfRating = min(Double(level) + shift, SkillAssessment.maxTier.rating)
            db.users[id]?.selfReportedRating = selfRating
            db.users[id]?.reputation.peerLevelAverage = min(9.33, max(0.67, peerAverage + shift))
            // 有证据的模拟球友：前省队（一级运动员 → 8），业余比赛常客（次高组冠军 → 7−）
            if level >= 8 {
                db.users[id]?.applyVerification(.national, tier: SkillTier(level: level))
            } else if entry.4.contains("比赛常客") {
                db.users[id]?.applyVerification(.tournament, tier: SkillTier(level: 7, modifier: .minus))
            }
            // 约六成模拟球友愿意出现在“同馆常客”里（真实用户默认关闭）
            db.users[id]?.privacy.showsAsRegular = index % 5 != 1 && index % 5 != 3
            db.bots[id] = BotProfile(
                userId: id,
                eastKm: cos(angle) * radius,
                northKm: sin(angle) * radius,
                pattern: entry.2,
                friendliness: Double.random(in: 0.7...0.97, using: &rng)
            )
        }
        relocateBots()
        scheduleSave()
    }

    /// 用户换城市时，把模拟世界搬到用户附近
    func moveWorldIfNeeded(to coordinate: Coordinate) {
        guard coordinate.distanceKm(to: db.worldCenter) > 25 else { return }
        db.worldCenter = coordinate
        relocateBots()
        refreshPublicRooms(force: true)
    }

    /// 根据世界中心更新机器人坐标，并重新分配它们的常去球馆
    func relocateBots() {
        for (id, bot) in db.bots {
            guard var user = db.users[id] else { continue }
            user.location = db.worldCenter.offsetBy(eastKm: bot.eastKm, northKm: bot.northKm)
            db.users[id] = user
        }
        assignBotHomeVenues()
        ensureGroups()
    }

    func isBot(_ userId: String) -> Bool { db.bots[userId] != nil }

    // MARK: 空闲时间

    /// 机器人在某天的空闲时间（按模式 + 日期确定性生成）
    func availability(for botId: String, on day: Date) -> [TimeSlot] {
        guard let bot = db.bots[botId] else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let dayIndex = Int(start.timeIntervalSince1970 / 86400)
        var rng = SeededGenerator(seed: UInt64(abs(botId.stableHash &* 31 &+ dayIndex)))
        let weekday = calendar.component(.weekday, from: start)
        let weekend = weekday == 1 || weekday == 7

        func slot(_ fromHalfHours: Int, _ toHalfHours: Int) -> TimeSlot? {
            TimeSlot.on(start, startHour: fromHalfHours / 2, startMinute: (fromHalfHours % 2) * 30,
                        endHour: toHalfHours / 2, endMinute: (toHalfHours % 2) * 30)
        }
        func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

        var result: [TimeSlot?] = []
        switch bot.pattern {
        case .weekdayEvenings:
            if !weekend, chance(0.85) {
                let begin = Int.random(in: 36...39, using: &rng)
                result.append(slot(begin, min(45, begin + Int.random(in: 5...7, using: &rng))))
            } else if weekend, chance(0.5) {
                result.append(slot(28, 34))
            }
        case .weekendDaytime:
            if weekend {
                if chance(0.8) { result.append(slot(18, 24)) }
                if chance(0.7) { result.append(slot(28, 36)) }
            } else if chance(0.25) {
                result.append(slot(38, 42))
            }
        case .flexible:
            if chance(0.75) {
                let begin = Int.random(in: 20...38, using: &rng)
                result.append(slot(begin, min(45, begin + Int.random(in: 4...8, using: &rng))))
            }
            if chance(0.4) { result.append(slot(38, 43)) }
        case .mornings:
            if chance(0.8) { result.append(slot(13, 19)) }
            if weekend, chance(0.6) { result.append(slot(18, 24)) }
        case .nightOwl:
            if chance(0.8) { result.append(slot(40, 46)) }
            if weekend, chance(0.4) { result.append(slot(30, 36)) }
        }
        return result.compactMap { $0 }
    }

    /// 某天有空的附近球友数量（用于首页日期条）
    func availableCount(on day: Date, radiusKm: Double) -> Int {
        let center = currentUser?.location ?? db.worldCenter
        let blocked = blockedIds()
        return db.bots.keys.filter { id in
            guard !blocked.contains(id), let location = db.users[id]?.location else { return false }
            return location.distanceKm(to: center) <= radiusKm && !availability(for: id, on: day).isEmpty
        }.count
    }

    /// 同馆常客：和我有相同常去球馆、并且本人开启了“显示在常客里”的球友。
    /// 不按距离、不显示在线状态（防定位与骚扰，见 docs/DESIGN.md §12）
    func venueRegulars(limit: Int = 20) -> [VenueRegular] {
        guard let me = currentUserId else { return [] }
        let mine = favoriteCourtIds().compactMap { venue(id: $0) }
        guard !mine.isEmpty else { return [] }
        let blocked = blockedIds().union(db.bots.keys.filter { blockedIds(of: $0).contains(me) })
        var results: [(user: User, venue: BadmintonCourt, shared: Int)] = []
        for (userId, favorites) in db.favoriteCourtIds where userId != me && !blocked.contains(userId) {
            guard let user = db.users[userId], user.privacy.showsAsRegular else { continue }
            let theirs = favorites.compactMap { venue(id: $0) }
            let shared = mine.filter { court in theirs.contains { VenueCluster.same($0, court) } }
            guard let first = shared.first else { continue }
            results.append((user, first, shared.count))
        }
        return results
            .sorted { $0.shared != $1.shared ? $0.shared > $1.shared : $0.user.nickname < $1.user.nickname }
            .prefix(limit)
            .map { VenueRegular(user: $0.user, venue: $0.venue) }
    }

    /// 最近一起打过球、但还不是好友的人（加好友最自然的来源）
    func recentCoPlayers(limit: Int = 20) -> [User] {
        guard let me = currentUserId else { return [] }
        let blocked = blockedIds()
        var seen = Set<String>()
        return games()
            .filter { $0.status == .completed }
            .sorted { $0.slot.startTime > $1.slot.startTime }
            .flatMap { $0.otherPlayerIds(excluding: me) }
            .filter { !blocked.contains($0) && !isFriend($0) && seen.insert($0).inserted }
            .prefix(limit)
            .compactMap { db.users[$0] }
    }

    func distanceToCurrentUser(_ userId: String) -> Double? {
        guard let other = db.users[userId]?.location else { return nil }
        let center = currentUser?.location ?? db.worldCenter
        return other.distanceKm(to: center)
    }

    // MARK: 公开球局（机器人发起的“我有场地缺人”）

    func refreshPublicRooms(force: Bool) {
        let botRooms = db.rooms.values.filter { isBot($0.ownerId) && $0.visibility == .publicListing }
        let pool = worldVenues
        let knownIds = Set(pool.map(\.id))
        let stale = botRooms.filter { room in
            guard room.status.isOpen else { return true }
            if room.isExpired() { return true }
            return force || !(room.court.map { knownIds.contains($0.id) } ?? false)
        }
        for room in stale where !(room.contains(currentUserId ?? "") || room.isWaitlisted(currentUserId ?? "")) {
            db.rooms[room.id] = nil
        }
        let openCount = db.rooms.values.filter { isBot($0.ownerId) && $0.visibility == .publicListing && $0.status.isOpen }.count
        guard openCount < 4, !pool.isEmpty else { return }
        let templates: [(hostIndex: Int, mode: GameMode, dayOffset: Int, start: Int, end: Int, range: ClosedRange<Int>, tags: [RoomTag], note: String, filled: Int)] = [
            (24, .doubles, 0, 20, 22, 3...6, [.casual], "订好了 2 小时，还差 1 人，打完 AA", 3),
            (1, .doubles, 1, 19, 21, 4...7, [.competitive, .womenFriendly], "女双/混双都可以，节奏稍快", 2),
            (5, .doubles, 2, 7, 9, 2...6, [.beginnerFriendly, .coaching], "晨练局，可以帮新手纠正动作", 2),
            (3, .singles, 1, 20, 22, 4...6, [.competitive], "想找单打对抗，打三局两胜", 1),
            (7, .doubles, 5, 15, 17, 1...4, [.beginnerFriendly, .casual], "周末欢乐局，新手放心来", 1)
        ]
        let calendar = Calendar.current
        let existingCodes = Set(db.rooms.values.map(\.code))
        var created = 0
        for (offset, template) in templates.enumerated() where openCount + created < 4 {
            let hostId = "bot-\(template.hostIndex)"
            guard let host = db.users[hostId],
                  !db.rooms.values.contains(where: { $0.ownerId == hostId && $0.status.isOpen }),
                  let day = calendar.date(byAdding: .day, value: template.dayOffset, to: Date()),
                  let slot = TimeSlot.on(day, startHour: template.start, endHour: template.end),
                  slot.startTime > Date().addingTimeInterval(30 * 60) else { continue }
            let court = pool[offset % pool.count]
            var participants = [RoomParticipant(user: host)]
            let others = db.bots.keys.sorted()
                .filter { $0 != hostId }
                .compactMap { db.users[$0] }
                .filter { template.range.contains($0.displayLevel) }
            for other in others.prefix(template.filled - 1) {
                participants.append(RoomParticipant(user: other))
            }
            let room = Room(
                id: UUID().uuidString,
                code: Room.generateCode(excluding: existingCodes),
                ownerId: hostId,
                mode: template.mode,
                visibility: .publicListing,
                participants: participants,
                invitedUserIds: [],
                waitlist: [],
                court: court,
                slot: slot,
                levelRange: template.range,
                tags: template.tags,
                note: template.note,
                createdAt: Date().addingTimeInterval(-Double(offset + 1) * 1800),
                lastActivityAt: Date(),
                status: .open
            )
            db.rooms[room.id] = room
            created += 1
        }
        if created > 0 || !stale.isEmpty { emit(.roomsChanged) }
    }

    // MARK: 演示内容（新用户首次进入时，让模拟世界“有人气”）

    func seedDemoContent(for userId: String) {
        guard !db.seededUserIds.contains(userId), var me = db.users[userId] else { return }
        db.seededUserIds.append(userId)
        let now = Date()
        let calendar = Calendar.current
        let seedVenues = nearestVenues(to: me.location ?? db.worldCenter, count: 2)

        // 已有球友
        for botId in ["bot-0", "bot-1", "bot-3"] {
            db.friendships.append(Friendship(between: userId, and: botId, createdAt: now.addingTimeInterval(-6 * 86400)))
        }
        // 待处理的好友申请
        db.friendRequests.append(FriendRequest(
            id: UUID().uuidString, fromUserId: "bot-4", toUserId: userId,
            note: "上周在朝阳馆一起打过双打～", sentAt: now.addingTimeInterval(-3 * 3600), status: .pending
        ))

        // 加入附近的一个球群，并报名下一场
        if let group = groups(near: me.location ?? db.worldCenter, radiusKm: 40).first(where: { $0.joinPolicy == .open }),
           var joined = db.groups[group.id] {
            if !joined.memberIds.contains(userId) { joined.memberIds.append(userId) }
            db.groups[group.id] = joined
            ensureGroupThread(for: joined, at: now)
            materializeSessions(for: joined, from: now, days: GroupSession.daysAhead)
            if let next = db.groupSessions.values
                .filter({ $0.groupId == joined.id && $0.slot.startTime > now.addingTimeInterval(3 * 3600) })
                .min(by: { $0.slot.startTime < $1.slot.startTime }), !next.signedUp.contains(userId) {
                var session = next
                if session.isFull { session.capacity += 1 }
                session.signedUp.append(userId)
                db.groupSessions[session.id] = session
            }
        }

        // 私信
        let threadA = MessageThread.id(for: userId, "bot-0")
        appendSeedMessage(threadA, participants: [userId, "bot-0"], from: userId, text: "上次打得太爽了，下周再约？", at: now.addingTimeInterval(-26 * 3600), read: true)
        appendSeedMessage(threadA, participants: [userId, "bot-0"], from: "bot-0", text: "必须的！我最近在练反手，周末有空吗？", at: now.addingTimeInterval(-2 * 3600), read: false)

        refreshPublicRooms(force: false)
        if let hostedByHong = db.rooms.values.first(where: { $0.ownerId == "bot-1" && $0.status.isOpen }) {
            let threadB = MessageThread.id(for: userId, "bot-1")
            appendSeedMessage(threadB, participants: [userId, "bot-1"], from: "bot-1",
                              text: "来打双打吗？还差人～", at: now.addingTimeInterval(-50 * 60),
                              read: false, kind: .roomInvite(code: hostedByHong.code))
        }

        // 一场昨天打完、等待互评的球局 + 一场更早的已完成球局
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           let slot = TimeSlot.on(yesterday, startHour: 19, endHour: 21) {
            let court = seedVenues.first ?? BadmintonCourt.mock
            let game = Game(
                id: "seed-game-1-\(userId)", mode: .singles, court: court, slot: slot,
                playerIds: [userId, "bot-2"], teams: [[userId], ["bot-2"]], hostId: userId,
                origin: .quickMatch, status: .completed, createdAt: yesterday.addingTimeInterval(-86400),
                checkIns: [userId: slot.startTime.addingTimeInterval(-300), "bot-2": slot.startTime.addingTimeInterval(120)],
                paidPlayerIds: [userId, "bot-2"], cost: CostSplit.estimate(court: court, slot: slot, mode: .singles),
                result: GameResult(didWin: true, score: "21:15 18:21 21:17"), cancelledBy: nil, cancelledLate: false,
                reminderEnabled: false
            )
            db.games[game.id] = game
            if let opponent = db.users["bot-2"] {
                db.pendingSurveys.append(PendingSurvey(
                    id: UUID().uuidString, matchId: game.id, evaluatorId: userId, opponentId: opponent.id,
                    opponentNickname: opponent.nickname, opponentLevel: opponent.displayLevel, opponentAvatar: opponent.avatar,
                    courtName: court.name, matchDate: slot.startTime, expiresAt: slot.endTime.addingTimeInterval(PendingSurvey.validityDuration)
                ))
                // 对方已评价我（双盲，等我提交后才计入）
                db.heldSurveys.append(MatchSurvey(
                    id: UUID().uuidString, matchId: game.id, evaluatorId: opponent.id, evaluatedUserId: userId,
                    skillRating: me.selfReportedLevel, wasPunctual: true, attendance: .onTime, characterRating: 5,
                    tags: [.friendly, .punctual], submittedAt: slot.endTime.addingTimeInterval(1800), wantsRematch: true
                ))
            }
        }
        if let older = calendar.date(byAdding: .day, value: -5, to: now),
           let slot = TimeSlot.on(older, startHour: 20, endHour: 22) {
            let court = seedVenues.dropFirst().first ?? seedVenues.first ?? BadmintonCourt.mock
            let players = [userId, "bot-3", "bot-4", "bot-8"]
            let game = Game(
                id: "seed-game-2-\(userId)", mode: .doubles, court: court, slot: slot,
                playerIds: players, teams: [[userId, "bot-8"], ["bot-3", "bot-4"]], hostId: "bot-3",
                origin: .quickMatch, status: .completed, createdAt: older.addingTimeInterval(-2 * 86400),
                checkIns: Dictionary(uniqueKeysWithValues: players.map { ($0, slot.startTime) }),
                paidPlayerIds: players, cost: CostSplit.estimate(court: court, slot: slot, mode: .doubles),
                result: GameResult(didWin: false, score: "19:21 21:23"), cancelledBy: nil, cancelledLate: false,
                reminderEnabled: false
            )
            db.games[game.id] = game
            // 历史评价：3 次（仍是“待校准”的新球友）
            let past = [
                MatchSurvey(id: UUID().uuidString, matchId: game.id, evaluatorId: "bot-3", evaluatedUserId: userId,
                            skillRating: me.selfReportedLevel, wasPunctual: true, attendance: .onTime, characterRating: 5,
                            tags: [.friendly], submittedAt: slot.endTime.addingTimeInterval(3600)),
                MatchSurvey(id: UUID().uuidString, matchId: game.id, evaluatorId: "bot-4", evaluatedUserId: userId,
                            skillRating: max(1, me.selfReportedLevel - 1), wasPunctual: true, attendance: .onTime, characterRating: 4,
                            tags: [.punctual], submittedAt: slot.endTime.addingTimeInterval(5400)),
                MatchSurvey(id: UUID().uuidString, matchId: game.id, evaluatorId: "bot-8", evaluatedUserId: userId,
                            skillRating: me.selfReportedLevel, wasPunctual: true, attendance: .onTime, characterRating: 5,
                            tags: [.greatPartner], submittedAt: slot.endTime.addingTimeInterval(7200))
            ]
            db.surveys.append(contentsOf: past)
            me.reputation = ReputationScore.aggregate(past, selfRating: me.selfRating)
        }
        me.totalGames = 2
        me.wins = 1
        me.attendance = AttendanceRecord(gamesPlayed: 2, noShows: 0, lateCancellations: 0)
        db.users[userId] = me

        // 站内通知
        addInbox(InboxItem(kind: .system, title: "欢迎来到羽毛球搭子 🏸",
                           body: "附近的球友、球局都在首页。点中间的「+」可以快速匹配或发起球局。",
                           createdAt: now.addingTimeInterval(-60)), to: userId)
        addInbox(InboxItem(kind: .friendRequest, title: "琳琳 想加你为球友",
                           body: "上周在朝阳馆一起打过双打～", createdAt: now.addingTimeInterval(-3 * 3600),
                           relatedId: "bot-4"), to: userId)
        if let survey = db.pendingSurveys.first(where: { $0.evaluatorId == userId }) {
            addInbox(InboxItem(kind: .surveyDue, title: "给 \(survey.opponentNickname) 的球局打个分",
                               body: "评价匿名汇总，双方都提交后才会计入。", createdAt: now.addingTimeInterval(-10 * 3600),
                               relatedId: survey.id), to: userId)
        }
    }

    private func appendSeedMessage(
        _ threadId: String,
        participants: [String],
        from senderId: String,
        text: String,
        at date: Date,
        read: Bool,
        kind: MessageKind = .text
    ) {
        let message = Message(
            threadId: threadId, senderId: senderId, content: text, sentAt: date,
            deliveredAt: date, readAt: read ? date.addingTimeInterval(60) : nil, kind: kind
        )
        var messages = db.messages[threadId] ?? []
        messages.append(message)
        db.messages[threadId] = messages
        var thread = db.threads[threadId] ?? MessageThread(
            id: threadId, participantIds: participants.sorted(), lastMessage: nil,
            lastActivityAt: date, unreadCounts: [:], clearedAt: [:]
        )
        thread.lastMessage = message
        thread.lastActivityAt = date
        if !read {
            for participant in participants where participant != senderId {
                thread.unreadCounts[participant, default: 0] += 1
            }
        }
        db.threads[threadId] = thread
    }
}
