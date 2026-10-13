import Foundation

// MARK: - 本地模拟后端
/// 应用目前没有真实服务端。MockBackend 在进程内扮演“服务器”：
/// - 持久化账户、好友、私信、房间、球局、评价（JSON 文件）
/// - 模拟附近的其他球友（机器人），会回复消息、通过好友申请、加入球局、签到和互评
/// - 通过事件（BackendEvent）把变化推送给各个 Manager，接口形态与真实后端保持一致，便于后续替换
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

    private var listeners: [UUID: BackendEventHandler] = [:]
    private var saveTask: Task<Void, Never>?
    /// 最近一次发送的验证码（手机号 -> (验证码, 过期时间)）
    var issuedCodes: [String: (code: String, expiresAt: Date)] = [:]

    init(store: DatabaseStore) {
        self.store = store
        if let saved = store.load() {
            db = saved
        } else {
            db = Database()
        }
        ensureWorld()
    }

    // MARK: Events

    @discardableResult
    func subscribe(_ handler: @escaping BackendEventHandler) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func unsubscribe(_ id: UUID) {
        listeners[id] = nil
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
        location: Coordinate?
    ) async throws -> User {
        guard Self.isValidPhone(phone) else { throw BackendError.invalidPhone }
        guard Self.isValidNickname(nickname) else { throw BackendError.invalidNickname }
        await networkDelay()
        return createAccount(
            phone: phone, nickname: nickname, gender: gender, avatar: avatar, level: level,
            preferredMode: preferredMode, recurringSlots: recurringSlots, location: location
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
        seedsDemoContent: Bool = true
    ) -> User {
        let id = "u-" + UUID().uuidString.prefix(8).lowercased()
        let user = User(
            id: id,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone,
            gender: gender,
            avatar: avatar,
            selfReportedLevel: min(SkillLevel.clamp(level), SkillLevel.maxSelfSelectable),
            location: location ?? db.worldCenter,
            preferredMode: preferredMode
        )
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
        db.currentUserId = nil
        saveNow()
        emit(.sessionChanged)
    }

    /// 注销账号：删除本人数据（个人信息保护法要求提供注销途径）
    func deleteAccount() {
        guard let user = currentUser else { return }
        db.accounts[user.phone] = nil
        db.users[user.id] = nil
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
        db.recurringSlots[user.id] = nil
        db.blocks[user.id] = nil
        db.currentUserId = nil
        saveNow()
        emit(.sessionChanged)
    }

    func updateProfile(_ updated: User) async throws -> User {
        guard var user = currentUser, user.id == updated.id else { throw BackendError.notSignedIn }
        guard Self.isValidNickname(updated.nickname) else { throw BackendError.invalidNickname }
        await networkDelay()
        user.nickname = updated.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        user.bio = String(updated.bio.prefix(60))
        user.gender = updated.gender
        user.avatar = updated.avatar
        user.preferredMode = updated.preferredMode
        // 自评只能在 1-7 之间修改，8-9 需要认证
        user.selfReportedLevel = min(SkillLevel.clamp(updated.selfReportedLevel), max(SkillLevel.maxSelfSelectable, user.verificationStatus.maxLevel))
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
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
        for index in items.indices where id == nil || items[index].id == id {
            items[index].isRead = true
        }
        db.inbox[userId] = items
        scheduleSave()
        emit(.inboxChanged)
    }

    func clearInbox() {
        guard let userId = currentUserId else { return }
        db.inbox[userId] = []
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
        guard slots.allSatisfy(\.isValidDuration) else { throw BackendError.invalidSlot("每个时间段需要 1-8 小时") }
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
    }
}
