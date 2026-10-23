import Foundation
import Combine

// MARK: - 好友

@MainActor
final class FriendManager: ObservableObject {
    @Published private(set) var friends: [User] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var outgoingRequests: [FriendRequest] = []

    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
        reload()
        backend.subscribe { [weak self] event in
            switch event {
            case .friendsChanged, .friendRequestsChanged, .sessionChanged, .userUpdated:
                self?.reload()
            default:
                break
            }
        }
    }

    func reload() {
        friends = backend.friends()
        incomingRequests = backend.incomingRequests()
        outgoingRequests = backend.outgoingRequests()
    }

    func searchFriends(query: String) -> [User] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return friends }
        return friends.filter { $0.nickname.localizedCaseInsensitiveContains(text) }
    }

    /// 按昵称搜球友：正式后端去服务器搜（只搜得到允许被搜到的人），演示模式搜本机
    func findPlayers(query: String) async throws -> [User] {
        backend.isRemote ? try await backend.remoteFindPlayers(query) : backend.searchUsers(query: query)
    }

    /// 打开别人的加球友链接：返回对方的 ID；链接失效返回 nil。演示模式没有链接
    func openFriendLink(_ code: String) async throws -> String? {
        backend.isRemote ? try await backend.remoteOpenFriendLink(code) : nil
    }

    /// 换一个加球友链接，旧链接失效
    func resetFriendLink() async throws {
        _ = try await backend.remoteResetFriendCode()
    }

    /// 同馆常客（对方开启了才显示）
    func venueRegulars(limit: Int = 20) -> [VenueRegular] {
        backend.venueRegulars(limit: limit)
    }

    /// 正式后端：从服务器拉最新的常客（5 分钟内不重复拉）
    func refreshRegulars() async {
        try? await backend.refreshRemoteRegulars()
    }

    func recentCoPlayers(limit: Int = 20) -> [User] {
        backend.recentCoPlayers(limit: limit)
    }

    func user(id: String) -> User? { backend.user(id: id) }

    func distance(to userId: String) -> Double? { backend.distanceToCurrentUser(userId) }

    func isFriend(_ userId: String) -> Bool { friends.contains { $0.id == userId } }

    /// 我和 TA 共同的球友
    func mutualFriends(with userId: String) -> [User] {
        let theirs = Set(backend.friendIds(of: userId))
        return friends.filter { theirs.contains($0.id) }
    }

    /// 我和 TA 一起打完的球局（最近的在前）
    func gamesTogether(with userId: String) -> [Game] {
        backend.games()
            .filter { $0.status == .completed && $0.playerIds.contains(userId) }
            .sorted { $0.slot.startTime > $1.slot.startTime }
    }

    func hasPendingRequest(to userId: String) -> Bool {
        outgoingRequests.contains { $0.toUserId == userId }
    }

    func incomingRequest(from userId: String) -> FriendRequest? {
        incomingRequests.first { $0.fromUserId == userId }
    }

    func sendRequest(to userId: String, note: String = "") async throws {
        try await backend.sendFriendRequest(to: userId, note: note)
        reload()
    }

    func respond(_ request: FriendRequest, accept: Bool) async throws {
        try await backend.respond(to: request.id, accept: accept)
        reload()
    }

    func remove(_ userId: String) async throws {
        try await backend.removeFriend(userId)
        reload()
    }
}

// MARK: - 私信

@MainActor
final class MessageManager: ObservableObject {
    @Published private(set) var threads: [MessageThread] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var blockedUsers: [BlockedUser] = []
    @Published private(set) var messagesByThread: [String: [Message]] = [:]
    @Published private(set) var typingThreads: Set<String> = []
    /// 当前打开的会话（打开期间新消息自动已读）
    var activeThreadId: String?

    private let backend: MockBackend

    static let maxMessageLength = Message.maxContentLength
    nonisolated static let defaultMessageLimit = 50

    init(backend: MockBackend) {
        self.backend = backend
        reload()
        backend.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case .threadsChanged, .sessionChanged, .friendsChanged:
                self.reload()
            case .messagesChanged(let threadId):
                if threadId == self.activeThreadId {
                    self.backend.markThreadRead(threadId)
                }
                if self.messagesByThread[threadId] != nil || threadId == self.activeThreadId {
                    self.loadMessages(threadId: threadId)
                }
                self.reload()
            case .typing(let threadId, let isTyping):
                if isTyping { self.typingThreads.insert(threadId) } else { self.typingThreads.remove(threadId) }
            default:
                break
            }
        }
    }

    var currentUserId: String? { backend.currentUserId }

    func reload() {
        threads = backend.threads()
        unreadCount = backend.totalUnread()
        blockedUsers = backend.blockedUsers()
    }

    func threadId(with userId: String) -> String? {
        guard let me = backend.currentUserId else { return nil }
        return MessageThread.id(for: me, userId)
    }

    /// 加载最近 50 条消息
    func loadMessages(threadId: String, limit: Int = defaultMessageLimit) {
        messagesByThread[threadId] = backend.messages(threadId: threadId, limit: limit)
    }

    func messages(with userId: String) -> [Message] {
        guard let id = threadId(with: userId) else { return [] }
        return messagesByThread[id] ?? []
    }

    func open(with userId: String) {
        guard let id = threadId(with: userId) else { return }
        activeThreadId = id
        backend.markThreadRead(id)
        loadMessages(threadId: id)
        reload()
    }

    /// 推送到了或回到前台：马上重拉会话列表；正开着的会话连消息一起拉，不等定时刷新
    func refreshNow() {
        backend.refreshMessagesNow(activeThreadId: activeThreadId)
    }

    func close(with userId: String) {
        if activeThreadId == threadId(with: userId) {
            activeThreadId = nil
        }
    }

    func isTyping(_ userId: String) -> Bool {
        guard let id = threadId(with: userId) else { return false }
        return typingThreads.contains(id)
    }

    func send(_ text: String, to userId: String, kind: MessageKind = .text) async throws {
        _ = try await backend.sendMessage(text, to: userId, kind: kind)
        if let id = threadId(with: userId) { loadMessages(threadId: id) }
        reload()
    }

    // MARK: 私信规则与消息请求

    func permission(with userId: String) -> MessagePermission { backend.messagePermission(with: userId) }

    /// 我和对方的私信会话（可能还不存在）
    func thread(with userId: String) -> MessageThread? {
        threadId(with: userId).flatMap { backend.thread(id: $0) }
    }

    /// 别人发来、我还没处理的消息请求
    var incomingRequests: [MessageThread] {
        threads.filter { $0.isPendingRequest && $0.requestFrom != currentUserId }
    }

    /// 普通会话（不含待处理的请求）
    var conversations: [MessageThread] {
        threads.filter { !($0.isPendingRequest && $0.requestFrom != currentUserId) }
    }

    func acceptRequest(from userId: String) {
        guard let id = threadId(with: userId) else { return }
        backend.acceptMessageRequest(threadId: id)
        reload()
    }

    func declineRequest(from userId: String) {
        guard let id = threadId(with: userId) else { return }
        backend.declineMessageRequest(threadId: id)
        messagesByThread[id] = nil
        reload()
    }

    // MARK: 群聊（球局群 / 球群）

    func thread(id: String) -> MessageThread? { backend.thread(id: id) }

    func messages(threadId: String) -> [Message] { messagesByThread[threadId] ?? [] }

    func openThread(_ threadId: String) {
        activeThreadId = threadId
        backend.markThreadRead(threadId)
        loadMessages(threadId: threadId)
        reload()
    }

    func closeThread(_ threadId: String) {
        if activeThreadId == threadId { activeThreadId = nil }
    }

    func canPost(in threadId: String) -> Bool {
        guard let thread = backend.thread(id: threadId) else { return false }
        return backend.canPost(in: thread)
    }

    func sendGroup(_ text: String, threadId: String) async throws {
        _ = try await backend.sendGroupMessage(text, threadId: threadId)
        loadMessages(threadId: threadId)
        reload()
    }

    /// 打开球局群聊（没有就创建），返回会话 ID
    func gameChatId(for gameId: String) -> String? {
        guard let game = backend.game(id: gameId) else { return nil }
        let thread = backend.ensureGameThread(for: game)
        reload()
        return thread.id
    }

    func groupChatId(for groupId: String) -> String? {
        guard let group = backend.group(id: groupId), let me = currentUserId, group.isMember(me) else { return nil }
        let thread = backend.ensureGroupThread(for: group)
        reload()
        return thread.id
    }

    func user(_ id: String) -> User? { backend.user(id: id) }

    func deleteThread(_ thread: MessageThread) {
        backend.deleteThread(thread.id)
        messagesByThread[thread.id] = nil
        reload()
    }

    func block(_ userId: String) {
        backend.block(userId)
        reload()
    }

    func unblock(_ userId: String) {
        backend.unblock(userId)
        reload()
    }

    func isBlocked(_ userId: String) -> Bool {
        blockedUsers.contains { $0.blockedUserId == userId }
    }

    func report(_ userId: String, reason: ReportReason, detail: String, alsoBlock: Bool) async {
        await backend.report(userId, reason: reason, detail: detail)
        if alsoBlock { block(userId) }
    }

    func user(id: String) -> User? { backend.user(id: id) }
}

// MARK: - 站内通知

@MainActor
final class InboxManager: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var unreadCount = 0

    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
        reload()
        backend.subscribe { [weak self] event in
            switch event {
            case .inboxChanged, .sessionChanged:
                self?.reload()
            default:
                break
            }
        }
    }

    func reload() {
        items = backend.inbox()
        unreadCount = items.filter { !$0.isRead }.count
    }

    func markRead(_ item: InboxItem? = nil) {
        backend.markInboxRead(id: item?.id)
        reload()
    }
}

// MARK: - 赛后评价

@MainActor
final class SurveyManager: ObservableObject {
    @Published private(set) var pendingSurveys: [PendingSurvey] = []

    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
        refresh()
        backend.subscribe { [weak self] event in
            switch event {
            case .surveysChanged, .sessionChanged, .gamesChanged:
                self?.reload()
            default:
                break
            }
        }
    }

    /// 处理过期并重新加载
    func refresh() {
        backend.processSurveyExpirations()
        reload()
    }

    func reload() {
        pendingSurveys = backend.pendingSurveys()
    }

    func survey(id: String) -> PendingSurvey? {
        pendingSurveys.first { $0.id == id }
    }

    func pending(forGame gameId: String) -> [PendingSurvey] {
        pendingSurveys.filter { $0.matchId == gameId }
    }

    func submit(
        _ pending: PendingSurvey,
        skillRating: SkillTier,
        attendance: AttendanceAnswer,
        characterRating: Int,
        tags: [SurveyTag],
        issues: [SurveyIssue] = [],
        wantsRematch: Bool = false
    ) async throws {
        try await backend.submitSurvey(
            pendingId: pending.id, skillRating: skillRating.rating, attendance: attendance,
            characterRating: characterRating, tags: tags, issues: issues, wantsRematch: wantsRematch
        )
        reload()
    }
}

// MARK: - 球群（固定局）

@MainActor
final class GroupManager: ObservableObject {
    @Published private(set) var myGroups: [PlayGroup] = []
    /// 我报名或候补的未来场次
    @Published private(set) var mySessions: [GroupSession] = []
    /// 变化计数（球群详情等页面据此刷新）
    @Published private(set) var revision = 0

    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
        reload()
        backend.subscribe { [weak self] event in
            switch event {
            case .groupsChanged, .sessionChanged, .venuesChanged:
                self?.reload()
            default:
                break
            }
        }
    }

    var currentUserId: String? { backend.currentUserId }

    func reload() {
        myGroups = backend.myGroups()
        mySessions = backend.mySessions()
        revision += 1
    }

    func group(id: String) -> PlayGroup? { backend.group(id: id) }

    func group(code: String) -> PlayGroup? { backend.group(code: code) }

    func groups(near center: Coordinate, radiusKm: Double) -> [PlayGroup] { backend.groups(near: center, radiusKm: radiusKm) }

    func groups(atVenue venueId: String) -> [PlayGroup] { backend.groups(atVenue: venueId) }

    func activity(of groupId: String) -> GroupActivity { backend.activity(of: groupId) }

    func sessions(groupId: String) -> [GroupSession] { backend.upcomingSessions(groupId: groupId) }

    func session(id: String) -> GroupSession? { backend.session(id: id) }

    func venue(of group: PlayGroup) -> BadmintonCourt? { backend.venue(id: group.venueId) }

    func user(_ id: String) -> User? { backend.user(id: id) }

    // 正式后端的操作要等服务器，所以都是 async；演示环境直接在本地完成

    @discardableResult
    func create(name: String, venueId: String, schedules: [GroupSchedule], levelRange: ClosedRange<Int>,
                joinPolicy: PlayGroup.JoinPolicy, summary: String, audience: Gender? = nil) async throws -> PlayGroup {
        let group = backend.isRemote
            ? try await backend.remoteCreateGroup(name: name, venueId: venueId, schedules: schedules, levelRange: levelRange,
                                                  joinPolicy: joinPolicy, summary: summary, audience: audience)
            : try backend.createGroup(name: name, venueId: venueId, schedules: schedules, levelRange: levelRange,
                                      joinPolicy: joinPolicy, summary: summary)
        reload()
        return group
    }

    /// 输群号找球群（正式后端要问服务器）
    func find(code: String) async -> PlayGroup? {
        guard backend.isRemote else { return backend.group(code: code) }
        return try? await backend.remoteFindGroup(code: code)
    }

    @discardableResult
    func join(_ groupId: String) async throws -> PlayGroup {
        let group = backend.isRemote ? try await backend.remoteJoinGroup(groupId) : try backend.joinGroup(id: groupId)
        reload()
        return group
    }

    func leave(_ groupId: String) async throws {
        if backend.isRemote { try await backend.remoteLeaveGroup(groupId) } else { try backend.leaveGroup(id: groupId) }
        reload()
    }

    func approve(_ userId: String, in groupId: String) async throws {
        if backend.isRemote { try await backend.remoteApprove(userId, groupId: groupId) } else { try backend.approveMember(userId, groupId: groupId) }
        reload()
    }

    @discardableResult
    func signUp(_ sessionId: String) async throws -> MockBackend.SignupResult {
        let result = backend.isRemote ? try await backend.remoteSignUp(sessionId: sessionId) : try backend.signUp(sessionId: sessionId)
        reload()
        return result
    }

    func cancelSignup(_ sessionId: String) async throws {
        if backend.isRemote { try await backend.remoteCancelSignup(sessionId: sessionId) } else { try backend.cancelSignup(sessionId: sessionId) }
        reload()
    }

    func cancelSession(_ sessionId: String) async throws {
        if backend.isRemote { try await backend.remoteCancelSession(sessionId) } else { try backend.cancelSession(sessionId) }
        reload()
    }
}
