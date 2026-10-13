import Foundation
import Combine

// MARK: - 好友

@MainActor
final class FriendManager: ObservableObject {
    @Published private(set) var friends: [User] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var outgoingRequests: [FriendRequest] = []
    @Published private(set) var isLoading = false

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

    func searchDirectory(query: String) -> [User] {
        backend.searchUsers(query: query)
    }

    func nearbyPlayers(radiusKm: Double, limit: Int = 20) -> [User] {
        backend.nearbyPlayers(radiusKm: radiusKm, limit: limit)
    }

    func user(id: String) -> User? { backend.user(id: id) }

    func distance(to userId: String) -> Double? { backend.distanceToCurrentUser(userId) }

    func isFriend(_ userId: String) -> Bool { friends.contains { $0.id == userId } }

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
    static let defaultMessageLimit = 50

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

    func clear() {
        backend.clearInbox()
        reload()
    }
}

// MARK: - 赛后评价

@MainActor
final class SurveyManager: ObservableObject {
    @Published private(set) var pendingSurveys: [PendingSurvey] = []

    private let backend: MockBackend

    static let surveyExpirationHours: TimeInterval = 48

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
        skillRating: Int,
        attendance: AttendanceAnswer,
        characterRating: Int,
        tags: [SurveyTag]
    ) async throws {
        try await backend.submitSurvey(
            pendingId: pending.id, skillRating: skillRating, attendance: attendance,
            characterRating: characterRating, tags: tags
        )
        reload()
    }
}
