import Foundation

// MARK: - 本地模拟后端
/// 进程内的模拟服务器：持久化全部数据（JSON 文件），模拟附近的机器人球友，
/// 并通过 BackendEvent 把变化推送给各个 Manager
@MainActor
final class MockBackend {

    static let shared = MockBackend(store: .live)

    // MARK: State

    var db: Database
    let store: DatabaseStore
    /// 是否模拟网络延迟
    var latencyEnabled = true
    /// 是否启用机器人行为（测试中关闭以保证确定性）
    var simulationEnabled = true
    /// 机器人行为时间倍率（演示截图时可加速）
    var simulationSpeed: Double = 1
    /// 正式后端：设置后登录和已接入的功能走服务器，本地 db 只当缓存（见 MockBackend+Remote）
    var remote: SupabaseClient?
    var isRemote: Bool { remote != nil }
    /// 上次从服务器拉取约球、球局、会话的时间（避免刷新太频繁）
    var remoteRefreshedAt: Date?
    /// 每个会话上次拉取消息的时间
    var remoteThreadLoadedAt: [String: Date] = [:]
    /// 球群：上次拉取详情的时间、近 30 天活跃度、附近的球群
    var remoteGroupLoadedAt: [String: Date] = [:]
    var remoteGroupActivity: [String: GroupActivity] = [:]
    var remoteNearbyGroups: (center: Coordinate, ids: [String], at: Date)?
    /// 球局（房间）：上次拉取详情的时间、附近的公开局
    var remoteRoomLoadedAt: [String: Date] = [:]
    var remoteNearbyRooms: (center: Coordinate, ids: [String], at: Date)?
    /// 榜单与胜率：服务器给的本周 / 本月数据，以及对每位球友能否发起挑战
    var remoteBoardLoadedAt: [String: Date] = [:]
    var remoteWeeklyBoards: [String: RemoteWeeklyBoard] = [:]
    var remoteVenueBoards: [String: RemoteVenueBoard] = [:]
    var remoteWinRates: [String: Rankings.WinRate] = [:]
    var remoteChallengeStatus: [String: String] = [:]
    /// 服务器上的管理员（只用来显示演示模式开关；审核权限在服务器上另外检查）
    var remoteIsAdmin = false
    /// 上次按位置拉取球馆的地点、半径和时间
    var remoteVenuesLoaded: (center: Coordinate, radiusKm: Double, at: Date)?

    private var listeners: [UUID: BackendEventHandler] = [:]
    private var saveTask: Task<Void, Never>?
    /// 最近一次发送的验证码（手机号 -> (验证码, 过期时间)）
    var issuedCodes: [String: (code: String, expiresAt: Date)] = [:]
    /// 模拟球友之间的对局按天生成（同一天、同一世界中心结果固定）
    var botRecordCache: [String: [MatchRecord]] = [:]

    /// seedsWorld：生成附近的模拟球友（正式后端模式下不需要）
    init(store: DatabaseStore, seedsWorld: Bool = true) {
        self.store = store
        db = store.load() ?? Database()
        if seedsWorld { ensureWorld() }
        AvatarPhotos.source = { [weak self] userId in self?.db.avatarPhotos[userId] }
    }

    // MARK: Events

    @discardableResult
    func subscribe(_ handler: @escaping BackendEventHandler) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func emit(_ event: BackendEvent) {
        for handler in listeners.values {
            handler(event)
        }
    }

    // MARK: Persistence

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = db
        let store = store
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            store.save(snapshot)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        store.save(db)
    }

    /// 清空所有数据（设置 - 重置演示数据）
    func resetAll() {
        store.erase()
        db = Database()
        issuedCodes = [:]
        ensureWorld()
        saveNow()
        emit(.sessionChanged)
    }

    // MARK: Latency & scheduling

    func networkDelay(_ range: ClosedRange<Double> = 0.15...0.45) async {
        guard latencyEnabled else { return }
        let seconds = Double.random(in: range)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// 在若干秒后执行机器人行为（会话切换后自动作废）
    func simulate(after seconds: Double, _ work: @escaping @MainActor () -> Void) {
        guard simulationEnabled else { return }
        let session = db.currentUserId
        let delay = max(0.05, seconds / max(simulationSpeed, 0.01))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.db.currentUserId == session else { return }
            work()
        }
    }

    // MARK: Session

    var currentUserId: String? { db.currentUserId }

    var currentUser: User? {
        guard let id = db.currentUserId else { return nil }
        return db.users[id]
    }

    func requireUser() throws -> User {
        guard let user = currentUser else { throw BackendError.notSignedIn }
        return user
    }

    func user(id: String) -> User? { db.users[id] }

    /// 手机号以 E.164 存储（"+16265550123"），按国家规则校验
    static func isValidPhone(_ phone: String) -> Bool {
        phone.hasPrefix("+") && PhoneNumber.parse(phone)?.isValid == true
    }

    /// 昵称、简介会出现在排行榜上：不允许留联系方式或链接（防广告）
    static func advertises(_ text: String) -> Bool {
        ContactInfoDetector.mentionsOffPlatformContact(text) || ContactInfoDetector.containsLink(text)
    }

    static func isValidNickname(_ nickname: String) -> Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...12).contains(trimmed.count)
    }

    /// 发送验证码（演示环境直接返回验证码用于展示）
    func requestCode(phone: String) async throws -> String {
        guard Self.isValidPhone(phone) else { throw BackendError.invalidPhone }
        await networkDelay(0.4...0.8)
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        issuedCodes[phone] = (code, Date().addingTimeInterval(5 * 60))
        return code
    }

    func verify(phone: String, code: String) async throws -> AuthOutcome {
        guard Self.isValidPhone(phone) else { throw BackendError.invalidPhone }
        await networkDelay()
        guard let issued = issuedCodes[phone] else { throw BackendError.codeExpired }
        guard issued.expiresAt > Date() else { throw BackendError.codeExpired }
        guard issued.code == code else { throw BackendError.invalidCode }
        issuedCodes[phone] = nil
        if let userId = db.accounts[phone], db.users[userId] != nil {
            db.currentUserId = userId
            touchCurrentUser()
            saveNow()
            emit(.sessionChanged)
            return .signedIn(db.users[userId]!)
        }
        return .needsProfile(phone: phone)
    }

    /// 注册新用户
    func register(
        phone: String,
        nickname: String,
        gender: Gender,
        avatar: Avatar,
        level: Int,
        preferredMode: GameMode?,
        recurringSlots: [RecurringTimeSlot],
        location: Coordinate?,
        assessment: SkillAssessmentSummary? = nil
    ) async throws -> User {
        guard Self.isValidPhone(phone) else { throw BackendError.invalidPhone }
        guard Self.isValidNickname(nickname) else { throw BackendError.invalidNickname }
        guard !Self.advertises(nickname) else { throw BackendError.profileContainsContact }
        await networkDelay()
        return createAccount(
            phone: phone, nickname: nickname, gender: gender, avatar: avatar, level: assessment?.level ?? level,
            preferredMode: preferredMode, recurringSlots: recurringSlots, location: location, assessment: assessment
        )
    }

    /// 同步创建账户并登录（注册、演示模式与测试共用）
    @discardableResult
    func createAccount(
        phone: String,
        nickname: String,
        gender: Gender = .unspecified,
        avatar: Avatar? = nil,
        level: Int,
        preferredMode: GameMode? = nil,
        recurringSlots: [RecurringTimeSlot] = [],
        location: Coordinate? = nil,
        seedsDemoContent: Bool = true,
        assessment: SkillAssessmentSummary? = nil
    ) -> User {
        let id = "u-" + UUID().uuidString.prefix(8).lowercased()
        var user = User(
            id: id,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone,
            gender: gender,
            avatar: avatar,
            selfReportedLevel: min(SkillLevel.clamp(level), SkillLevel.maxSelfSelectable),
            location: location ?? db.worldCenter,
            preferredMode: preferredMode
        )
        user.assessment = assessment
        // 问卷等级上限 6+，直接传整数等级时同样封顶
        user.selfReportedRating = min(assessment?.tier ?? SkillTier(level: level), SkillAssessment.maxTier).rating
        db.users[id] = user
        db.accounts[phone] = id
        db.currentUserId = id
        db.recurringSlots[id] = Array(recurringSlots.prefix(TimeSlotConstants.maximumRecurringSlots))
        if let location { moveWorldIfNeeded(to: location) }
        if seedsDemoContent { seedDemoContent(for: id) }
        saveNow()
        emit(.sessionChanged)
        return db.users[id] ?? user
    }

    func signOut() {
        if let remote { Task { await remote.signOut() } }
        remoteIsAdmin = false
        db.currentUserId = nil
        saveNow()
        emit(.sessionChanged)
    }

    /// 注销账号：删除本人数据（个人信息保护法要求提供注销途径）
    func deleteAccount() {
        guard let user = currentUser else { return }
        db.accounts[user.phone] = nil
        db.users[user.id] = nil
        db.avatarPhotos[user.id] = nil
        db.friendships.removeAll { $0.involves(user.id) }
        db.friendRequests.removeAll { $0.fromUserId == user.id || $0.toUserId == user.id }
        for (threadId, thread) in db.threads where thread.participantIds.contains(user.id) {
            db.threads[threadId] = nil
            db.messages[threadId] = nil
        }
        db.rooms = db.rooms.filter { !$0.value.contains(user.id) && $0.value.ownerId != user.id }
        db.games = db.games.filter { !$0.value.playerIds.contains(user.id) }
        db.pendingSurveys.removeAll { $0.evaluatorId == user.id }
        db.inbox[user.id] = nil
        db.verificationRequests.removeAll { $0.userId == user.id }
        db.recurringSlots[user.id] = nil
        db.blocks[user.id] = nil
        for (id, group) in db.groups where group.isMember(user.id) || group.pendingIds.contains(user.id) {
            var updated = group
            updated.memberIds.removeAll { $0 == user.id }
            updated.organizerIds.removeAll { $0 == user.id }
            updated.pendingIds.removeAll { $0 == user.id }
            db.groups[id] = updated.memberIds.isEmpty ? nil : updated
        }
        for (id, session) in db.groupSessions where session.status(of: user.id) != .none {
            var updated = session
            updated.signedUp.removeAll { $0 == user.id }
            updated.waitlist.removeAll { $0 == user.id }
            db.groupSessions[id] = updated
        }
        db.currentUserId = nil
        saveNow()
        emit(.sessionChanged)
    }

    /// 注册时跳过了定级：暂按 Lv.3 匹配，资料页提示补测
    func markAssessmentSkipped(now: Date = Date()) {
        guard var user = currentUser, user.assessment == nil else { return }
        user.assessmentSkippedAt = now
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
    }

    /// 重新测评：更新问卷等级（每 90 天一次）
    @discardableResult
    func updateAssessment(_ result: SkillAssessmentResult, now: Date = Date()) throws -> User {
        guard var user = currentUser else { throw BackendError.notSignedIn }
        if let previous = user.assessment, !previous.canRetake(now: now) {
            throw BackendError.assessmentTooSoon(previous.nextRetakeDate())
        }
        let tier = min(result.tier, SkillAssessment.maxTier)
        user.selfReportedLevel = tier.level
        user.selfReportedRating = tier.rating
        user.assessment = SkillAssessmentSummary(level: tier.level, needsCalibration: result.needsCalibration,
                                                 isReturning: result.isReturning, assessedAt: now, rating: tier.rating)
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }

    func updatePrivacy(_ privacy: PrivacySettings) {
        guard var user = currentUser else { return }
        user.privacy = privacy
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        pushRemote(["show_on_boards": privacy.showsOnLeaderboards, "challenge_policy": privacy.challengePolicy.serverValue])
    }

    func updateProfile(_ updated: User) async throws -> User {
        guard var user = currentUser, user.id == updated.id else { throw BackendError.notSignedIn }
        guard Self.isValidNickname(updated.nickname) else { throw BackendError.invalidNickname }
        guard !Self.advertises(updated.nickname), !Self.advertises(updated.bio) else { throw BackendError.profileContainsContact }
        await networkDelay()
        if let remote, updated.nickname != user.nickname {
            try await remote.update("profiles", query: "id=eq.\(user.id)",
                                    ["nickname": updated.nickname.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        user.nickname = updated.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        user.bio = String(updated.bio.prefix(60))
        user.gender = updated.gender
        user.avatar.symbol = updated.avatar.symbol
        user.avatar.paletteIndex = updated.avatar.paletteIndex
        user.preferredMode = updated.preferredMode
        // 等级不能在这里直接改：只能通过定级问卷（每 90 天一次）或球友评价校准
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }

    /// 上传头像照片：其他球友在列表、资料页、聊天里都能看到
    @discardableResult
    func uploadAvatarPhoto(_ jpeg: Data) async throws -> User {
        guard var user = currentUser else { throw BackendError.notSignedIn }
        await networkDelay()
        db.avatarPhotos[user.id] = jpeg
        user.avatar.photoVersion = (user.avatar.photoVersion ?? 0) + 1
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }

    func removeAvatarPhoto() {
        guard var user = currentUser else { return }
        db.avatarPhotos[user.id] = nil
        user.avatar.photoVersion = nil
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
    }

    func updateCurrentUserLocation(_ coordinate: Coordinate) {
        guard var user = currentUser else { return }
        user.location = coordinate
        db.users[user.id] = user
        moveWorldIfNeeded(to: coordinate)
        scheduleSave()
    }

    func touchCurrentUser() {
        guard var user = currentUser else { return }
        user.lastActiveAt = Date()
        db.users[user.id] = user
    }

    // MARK: Inbox

    func inbox() -> [InboxItem] {
        guard let id = currentUserId else { return [] }
        return (db.inbox[id] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func addInbox(_ item: InboxItem, to userId: String) {
        guard db.users[userId] != nil, db.bots[userId] == nil else { return }
        var items = db.inbox[userId] ?? []
        items.insert(item, at: 0)
        db.inbox[userId] = Array(items.prefix(100))
        if userId == currentUserId { emit(.inboxChanged) }
    }

    func markInboxRead(id: String? = nil) {
        guard let userId = currentUserId, var items = db.inbox[userId] else { return }
        // 服务器一次把通知全部记为已读
        if isRemote, items.contains(where: { !$0.isRead }) { runRemote { try await $0.call("mark_notifications_read") } }
        for index in items.indices where isRemote || id == nil || items[index].id == id {
            items[index].isRead = true
        }
        db.inbox[userId] = items
        scheduleSave()
        emit(.inboxChanged)
    }

    // MARK: Preferences stored per user

    func recurringSlots() -> [RecurringTimeSlot] {
        guard let id = currentUserId else { return [] }
        return db.recurringSlots[id] ?? []
    }

    func saveRecurringSlots(_ slots: [RecurringTimeSlot]) throws {
        guard let id = currentUserId else { throw BackendError.notSignedIn }
        guard slots.count <= TimeSlotConstants.maximumRecurringSlots else { throw BackendError.tooManyRecurringSlots }
        guard slots.allSatisfy(\.isValidDuration) else { throw BackendError.invalidSlot(String(localized: "每个时间段需要 1-8 小时")) }
        db.recurringSlots[id] = slots
        scheduleSave()
    }

    func favoriteCourtIds() -> [String] {
        guard let id = currentUserId else { return [] }
        return db.favoriteCourtIds[id] ?? []
    }

    func toggleFavoriteCourt(_ courtId: String) {
        guard let id = currentUserId else { return }
        var favorites = db.favoriteCourtIds[id] ?? []
        if let index = favorites.firstIndex(of: courtId) {
            favorites.remove(at: index)
        } else {
            favorites.append(courtId)
        }
        db.favoriteCourtIds[id] = favorites
        scheduleSave()
        pushRemoteFavorite(courtId, isFavorite: favorites.contains(courtId))
    }
}
