import Foundation

// MARK: - 球群（固定局）：建群、加入、每周场次、报名 / 候补 / 递补、群聊

extension MockBackend {

    // MARK: Queries

    func group(id: String) -> PlayGroup? { db.groups[id] }

    func group(code: String) -> PlayGroup? {
        let normalized = Room.normalize(code)
        return db.groups.values.first { $0.inviteCode == normalized }
    }

    /// 我加入的球群
    func myGroups() -> [PlayGroup] {
        guard let me = currentUserId else { return [] }
        return db.groups.values.filter { $0.isMember(me) }.sorted { $0.name < $1.name }
    }

    /// 某个球馆的球群
    func groups(atVenue venueId: String) -> [PlayGroup] {
        guard let target = venue(id: venueId) else { return [] }
        return sortedByActivity(db.groups.values.filter { venue(id: $0.venueId).map { VenueCluster.same($0, target) } ?? false })
    }

    /// 附近的球群（按真实活跃度排序）
    func groups(near center: Coordinate, radiusKm: Double) -> [PlayGroup] {
        let blocked = blockedIds()
        return sortedByActivity(db.groups.values.filter { group in
            guard !blocked.contains(group.ownerId), let venue = venue(id: group.venueId) else { return false }
            return venue.distance(from: center) <= radiusKm
        })
    }

    /// 按近 30 天场次数降序（每个群只统计一次）
    private func sortedByActivity(_ groups: [PlayGroup]) -> [PlayGroup] {
        groups
            .map { (group: $0, sessions: activity(of: $0.id).sessionsLast30Days) }
            .sorted { $0.sessions > $1.sessions }
            .map { $0.group }
    }

    /// 近 30 天开了几场、平均每场几人（对外只显示这个，不显示成员总数）
    func activity(of groupId: String, now: Date = Date()) -> GroupActivity {
        let recent = db.groupSessions.values.filter { session in
            session.groupId == groupId && !session.isCancelled
                && session.slot.endTime <= now && now.timeIntervalSince(session.slot.endTime) <= 30 * 86400
        }
        guard !recent.isEmpty else { return GroupActivity(sessionsLast30Days: 0, averageTurnout: 0) }
        let turnout = Double(recent.reduce(0) { $0 + $1.signedUp.count }) / Double(recent.count)
        return GroupActivity(sessionsLast30Days: recent.count, averageTurnout: turnout)
    }

    /// 未来 14 天的场次（按需生成）
    func upcomingSessions(groupId: String, now: Date = Date()) -> [GroupSession] {
        guard let group = db.groups[groupId] else { return [] }
        materializeSessions(for: group, from: now, days: GroupSession.daysAhead)
        return db.groupSessions.values
            .filter { $0.groupId == groupId && $0.isUpcoming(now: now) }
            .sorted { $0.slot.startTime < $1.slot.startTime }
    }

    /// 我报名（或候补）的未来场次
    func mySessions(now: Date = Date()) -> [GroupSession] {
        guard let me = currentUserId else { return [] }
        for group in myGroups() { materializeSessions(for: group, from: now, days: GroupSession.daysAhead) }
        return db.groupSessions.values
            .filter { $0.isUpcoming(now: now) && $0.status(of: me) != .none }
            .sorted { $0.slot.startTime < $1.slot.startTime }
    }

    func session(id: String) -> GroupSession? { db.groupSessions[id] }

    // MARK: Create / join / leave

    @discardableResult
    func createGroup(name: String, venueId: String, schedules: [GroupSchedule], levelRange: ClosedRange<Int>,
                     joinPolicy: PlayGroup.JoinPolicy, summary: String, now: Date = Date()) throws -> PlayGroup {
        let me = try requireUser()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlayGroup.nameLimit.contains(trimmed.count) else { throw BackendError.groupNameInvalid }
        guard let venue = venue(id: venueId) else { throw BackendError.venueNotFound }
        guard !schedules.isEmpty, schedules.count <= PlayGroup.maxSchedules,
              schedules.allSatisfy({ schedule in
                  let minutes = schedule.endMinutes - schedule.startMinutes
                  return (60...480).contains(minutes) && GroupSchedule.capacityRange.contains(schedule.capacity)
                      && (1...7).contains(schedule.weekday)
              }) else { throw BackendError.groupScheduleInvalid }
        let existingCodes = Set(db.groups.values.map(\.inviteCode)).union(db.rooms.values.map(\.code))
        let group = PlayGroup(
            id: "grp-" + UUID().uuidString.prefix(8).lowercased(),
            name: trimmed,
            venueId: venue.id,
            ownerId: me.id,
            organizerIds: [me.id],
            memberIds: [me.id],
            pendingIds: [],
            summary: String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
            levelRange: levelRange,
            schedules: schedules,
            joinPolicy: joinPolicy,
            inviteCode: Room.generateCode(excluding: existingCodes),
            createdAt: now
        )
        db.groups[group.id] = group
        ensureGroupThread(for: group, at: now)
        materializeSessions(for: group, from: now, days: GroupSession.daysAhead)
        scheduleSave()
        emit(.groupsChanged)
        emit(.threadsChanged)
        return group
    }

    /// 加入：直接加入的群立即成为成员；需要同意的群进入待审批
    @discardableResult
    func joinGroup(id: String) throws -> PlayGroup {
        let me = try requireUser()
        guard var group = db.groups[id] else { throw BackendError.groupNotFound }
        guard !isBlockedEitherWay(me.id, group.ownerId) else { throw BackendError.groupNotFound }
        guard !group.isMember(me.id) else { return group }
        guard group.levelRange.contains(me.displayLevel) else {
            throw BackendError.levelOutOfRange(String(localized: "这个球群适合 \(group.levelText)，你目前是 \(me.displayTier.text)"))
        }
        switch group.joinPolicy {
        case .open:
            group.memberIds.append(me.id)
            group.pendingIds.removeAll { $0 == me.id }
            db.groups[id] = group
            ensureGroupThread(for: group)
        case .approval:
            guard !group.pendingIds.contains(me.id) else { return group }
            group.pendingIds.append(me.id)
            db.groups[id] = group
            // 模拟：组织者稍后同意
            if isBot(group.ownerId) {
                simulate(after: Double.random(in: 5...12)) { [weak self] in
                    try? self?.approveMember(me.id, groupId: id, asOrganizer: group.ownerId)
                }
            }
        }
        scheduleSave()
        emit(.groupsChanged)
        emit(.threadsChanged)
        return group
    }

    func joinGroup(code: String) throws -> PlayGroup {
        guard let group = group(code: code) else { throw BackendError.groupNotFound }
        return try joinGroup(id: group.id)
    }

    /// 组织者同意加入申请
    func approveMember(_ userId: String, groupId: String, asOrganizer organizerId: String? = nil) throws {
        guard var group = db.groups[groupId] else { throw BackendError.groupNotFound }
        let approver = organizerId ?? currentUserId ?? ""
        guard group.isOrganizer(approver) else { throw BackendError.notRoomOwner }
        guard group.pendingIds.contains(userId) else { return }
        group.pendingIds.removeAll { $0 == userId }
        group.memberIds.append(userId)
        db.groups[groupId] = group
        ensureGroupThread(for: group)
        addInbox(InboxItem(kind: .groupUpdate, title: String(localized: "已加入「\(group.name)」"),
                           body: String(localized: "组织者同意了你的申请，现在可以报名固定场次了。"), relatedId: groupId), to: userId)
        scheduleSave()
        emit(.groupsChanged)
        emit(.threadsChanged)
    }

    func leaveGroup(id: String, now: Date = Date()) throws {
        let me = try requireUser()
        guard var group = db.groups[id] else { throw BackendError.groupNotFound }
        guard group.ownerId != me.id else { throw BackendError.ownerCannotLeave }
        group.memberIds.removeAll { $0 == me.id }
        group.organizerIds.removeAll { $0 == me.id }
        group.pendingIds.removeAll { $0 == me.id }
        db.groups[id] = group
        // 退出未来场次（不算临时取消：退群不该被惩罚，但会让出名额）
        for session in db.groupSessions.values where session.groupId == id && session.isUpcoming(now: now) {
            removeFromSession(session.id, userId: me.id, now: now, countsAsLate: false)
        }
        ensureGroupThread(for: group)
        scheduleSave()
        emit(.groupsChanged)
        emit(.threadsChanged)
    }

    // MARK: Sign up

    enum SignupResult: Equatable {
        case confirmed
        case waitlisted(position: Int)
    }

    /// 报名一场：有名额直接报上，满了进候补
    @discardableResult
    func signUp(sessionId: String, now: Date = Date()) throws -> SignupResult {
        let me = try requireUser()
        guard var session = db.groupSessions[sessionId], session.isUpcoming(now: now),
              session.slot.startTime > now else { throw BackendError.sessionClosed }
        guard let group = db.groups[session.groupId], group.isMember(me.id) else { throw BackendError.notGroupMember }
        guard me.attendance.standing != .suspended else { throw BackendError.matchingSuspended }
        switch session.status(of: me.id) {
        case .signedUp: return .confirmed
        case .waitlisted(let position): return .waitlisted(position: position)
        case .none: break
        }
        let result: SignupResult
        if session.isFull {
            session.waitlist.append(me.id)
            result = .waitlisted(position: session.waitlist.count)
        } else {
            session.signedUp.append(me.id)
            result = .confirmed
        }
        db.groupSessions[sessionId] = session
        scheduleSave()
        emit(.groupsChanged)
        return result
    }

    /// 取消报名：开场前 2 小时内退出算临时取消；候补第一位自动递补
    func cancelSignup(sessionId: String, now: Date = Date()) throws {
        let me = try requireUser()
        guard let session = db.groupSessions[sessionId], session.isUpcoming(now: now) else { throw BackendError.sessionClosed }
        guard session.status(of: me.id) != .none else { return }
        removeFromSession(sessionId, userId: me.id, now: now, countsAsLate: true)
        scheduleSave()
        emit(.groupsChanged)
    }

    private func removeFromSession(_ sessionId: String, userId: String, now: Date, countsAsLate: Bool) {
        guard var session = db.groupSessions[sessionId] else { return }
        if let index = session.signedUp.firstIndex(of: userId) {
            session.signedUp.remove(at: index)
            if countsAsLate, session.slot.startTime.timeIntervalSince(now) < GroupSession.lateCancellationWindow,
               var user = db.users[userId] {
                user.attendance.lateCancellations += 1
                db.users[userId] = user
                emit(.userUpdated(user))
            }
            // 候补递补
            if !session.waitlist.isEmpty {
                let promoted = session.waitlist.removeFirst()
                session.signedUp.append(promoted)
                if let group = db.groups[session.groupId] {
                    addInbox(InboxItem(kind: .groupUpdate, title: String(localized: "候补转正：\(group.name)"),
                                       body: String(localized: "\(session.slot.formattedFull) 有人退出，你已自动报上。去不了记得提前取消。"),
                                       relatedId: group.id), to: promoted)
                }
            }
        } else {
            session.waitlist.removeAll { $0 == userId }
        }
        db.groupSessions[sessionId] = session
    }

    /// 组织者取消某一场
    func cancelSession(_ sessionId: String) throws {
        let me = try requireUser()
        guard var session = db.groupSessions[sessionId], let group = db.groups[session.groupId] else {
            throw BackendError.sessionClosed
        }
        guard group.isOrganizer(me.id) else { throw BackendError.notRoomOwner }
        session.isCancelled = true
        db.groupSessions[sessionId] = session
        for userId in session.signedUp + session.waitlist where userId != me.id {
            addInbox(InboxItem(kind: .groupUpdate, title: String(localized: "「\(group.name)」这场取消了"),
                               body: String(localized: "\(session.slot.formattedFull) 由组织者取消，不影响你的记录。"), relatedId: group.id), to: userId)
        }
        let thread = ensureGroupThread(for: group)
        appendMessage(Message(threadId: thread.id, senderId: "system", content: String(localized: "\(session.slot.formattedFull) 这场取消了"),
                              deliveredAt: Date(), kind: .system),
                      participants: thread.participantIds, countsAsUnread: false)
        scheduleSave()
        emit(.groupsChanged)
    }

    // MARK: Sessions

    /// 生成某段时间内的场次（已有的不重复生成）；模拟球友按确定性规则报名
    func materializeSessions(for group: PlayGroup, from start: Date, days: Int) {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: start)
        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            for schedule in group.schedules {
                guard let slot = schedule.slot(on: day, calendar: calendar) else { continue }
                let id = GroupSession.makeId(groupId: group.id, scheduleId: schedule.id, day: day, calendar: calendar)
                guard db.groupSessions[id] == nil else { continue }
                // 模拟球友：每人每场约六成概率报名
                var rng = SeededGenerator(id)
                let bots = group.memberIds.filter { isBot($0) }.filter { _ in Double.random(in: 0..<1, using: &rng) < 0.6 }
                let signed = Array(bots.prefix(schedule.capacity))
                let waitlist = Array(bots.dropFirst(schedule.capacity))
                db.groupSessions[id] = GroupSession(id: id, groupId: group.id, scheduleId: schedule.id, slot: slot,
                                                    capacity: schedule.capacity, signedUp: signed, waitlist: waitlist)
            }
        }
    }

    // MARK: World seeding

    /// 模拟世界里的球群：在离世界中心最近的两家球馆各有一个，由模拟球友组织，附带过去 30 天的场次
    func ensureGroups(now: Date = Date()) {
        let venues = worldVenues.sorted { $0.distance(from: db.worldCenter) < $1.distance(from: db.worldCenter) }
        guard venues.count >= 2 else { return }
        let hasNearby = db.groups.values.contains { group in
            venue(id: group.venueId).map { $0.distance(from: db.worldCenter) <= 30 } ?? false
        }
        guard !hasNearby else { return }
        let templates: [(name: String, owner: String, members: [String], venue: BadmintonCourt, range: ClosedRange<Int>,
                         policy: PlayGroup.JoinPolicy, summary: String, schedules: [GroupSchedule])] = [
            ("周四晚双打群", "bot-1", ["bot-1", "bot-2", "bot-5", "bot-6", "bot-7", "bot-9", "bot-11", "bot-12", "bot-14", "bot-16"],
             venues[0], 3...6, .open, "下班后来打双打，轮换上场，新手友好。球馆按人头收费，自己在前台付。",
             [GroupSchedule(id: "thu", weekday: 5, startMinutes: 19 * 60 + 30, endMinutes: 22 * 60, capacity: 12, feeNote: "场地按人头收费"),
              GroupSchedule(id: "sun", weekday: 1, startMinutes: 14 * 60, endMinutes: 17 * 60, capacity: 16, feeNote: "场地按人头收费")]),
            ("周末早场·中高级", "bot-5", ["bot-5", "bot-3", "bot-8", "bot-10", "bot-13", "bot-15", "bot-17"],
             venues[1], 5...8, .approval, "节奏偏快，适合 Lv.5 以上。第一次来请先在群里打个招呼。",
             [GroupSchedule(id: "sat", weekday: 7, startMinutes: 9 * 60, endMinutes: 12 * 60, capacity: 12, feeNote: "AA 场地费")])
        ]
        for (index, template) in templates.enumerated() {
            let members = template.members.filter { db.bots[$0] != nil }
            guard let owner = members.first else { continue }
            let group = PlayGroup(
                id: "grp-world-\(index)-\(template.venue.id)",
                name: template.name,
                venueId: template.venue.id,
                ownerId: owner,
                organizerIds: [owner],
                memberIds: members,
                pendingIds: [],
                summary: template.summary,
                levelRange: template.range,
                schedules: template.schedules,
                joinPolicy: template.policy,
                inviteCode: Room.generateCode(excluding: Set(db.groups.values.map(\.inviteCode))),
                createdAt: now.addingTimeInterval(-90 * 86400)
            )
            db.groups[group.id] = group
            // 过去 30 天的场次（用于展示真实活跃度）
            if let past = Calendar.current.date(byAdding: .day, value: -30, to: now) {
                materializeSessions(for: group, from: past, days: 30 + GroupSession.daysAhead)
            }
            let thread = ensureGroupThread(for: group, at: now.addingTimeInterval(-3 * 86400))
            seedGroupChat(thread: thread, group: group, now: now)
        }
    }

    private func seedGroupChat(thread: MessageThread, group: PlayGroup, now: Date) {
        let lines: [(Int, String, TimeInterval)] = [
            (0, "这周照常，名额在 App 里报，满了自动候补～", -26 * 3600),
            (1, "我这周能来，带一筒球", -20 * 3600),
            (2, "新人第一次来，在哪个场地集合？", -5 * 3600),
            (0, "进门右手边，找穿黄衣服的我就行 👋", -4 * 3600)
        ]
        var messages = db.messages[thread.id] ?? []
        var last = thread.lastMessage
        for (index, text, offset) in lines {
            guard group.memberIds.indices.contains(index) else { continue }
            let date = now.addingTimeInterval(offset)
            let message = Message(threadId: thread.id, senderId: group.memberIds[index], content: text,
                                  sentAt: date, deliveredAt: date, readAt: date)
            messages.append(message)
            last = message
        }
        db.messages[thread.id] = messages
        var updated = thread
        updated.lastMessage = last
        updated.lastActivityAt = last?.sentAt ?? thread.lastActivityAt
        db.threads[thread.id] = updated
    }
}
