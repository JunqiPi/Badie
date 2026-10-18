import Foundation

// MARK: - 正式后端：球友、私信、通知、球友资料
/// 和约球一样：操作调数据库函数，然后重新拉取写进缓存。私信规则在服务器上（球友、同球群的消息请求），
/// 球局和球群群聊照常
extension MockBackend {

    struct RemoteFriend: Decodable {
        let id: String
        let nickname: String
        let rating: Double
        let createdAt: Date?
    }

    struct RemoteFriends: Decodable {
        let friends: [RemoteFriend]
        let requests: [RemoteFriend]
    }

    struct RemoteThreadSummary: Decodable {
        struct Last: Decodable {
            let body: String
            let createdAt: Date
            let mine: Bool
        }

        let kind: String
        let id: String
        let startsAt: Date?
        let venue: String?
        let name: String?
        let access: String
        /// 还没接受的消息请求：incoming = 对方发给我的，outgoing = 我发的
        let request: String?
        let last: Last?
        let unread: Int
    }

    struct RemoteThread: Decodable {
        struct Member: Decodable {
            let id: String
            let nickname: String
            let me: Bool
        }

        struct Item: Decodable {
            let id: Int
            let body: String
            let createdAt: Date
            let sender: String
            let mine: Bool
        }

        let access: String
        let members: [Member]?
        let messages: [Item]
    }

    struct RemoteNotification: Decodable {
        let id: Int
        let kind: String
        let title: String
        let body: String
        let link: String?
        let createdAt: Date
        let readAt: Date?
    }

    struct RemotePlayerCard: Decodable {
        let id: String
        let nickname: String
        let rating: Double
        let tags: [String]
        let winRate: RemoteWinRate?
        /// 'available'、'hidden' 或不能挑战的原因
        let challenge: String?
        let message: RemoteMessageOption?
    }

    // MARK: 刷新

    /// 球友、会话列表、通知
    func refreshRemoteSocial() async throws {
        guard let remote, let me = currentUserId else { return }
        let friends: RemoteFriends = try await remote.rpc("my_friends")
        let threads: [RemoteThreadSummary] = try await remote.rpc("my_threads")
        let notes: [RemoteNotification] = try await remote.select(
            "notifications", query: "select=id,kind,title,body,link,created_at,read_at&order=id.desc&limit=50")
        apply(friends: friends, me: me)
        apply(threads: threads, me: me)
        apply(notifications: notes, me: me)
        try? await refreshRemoteRegulars()
        scheduleSave()
    }

    private func apply(friends: RemoteFriends, me: String) {
        for friend in friends.friends + friends.requests {
            cacheRemoteUser(id: friend.id, nickname: friend.nickname, rating: friend.rating)
        }
        let friendIds = Set(friends.friends.map(\.id))
        let friendships = friends.friends.map { friend in
            db.friendships.first { $0.involves(me) && $0.involves(friend.id) } ?? Friendship(between: me, and: friend.id)
        }
        // 服务器只列别人发给我的申请；我发出的申请保留本地记录，直到成为球友
        let outgoing = db.friendRequests.filter { $0.fromUserId == me && $0.status == .pending && !friendIds.contains($0.toUserId) }
        let incoming = friends.requests.map {
            FriendRequest(id: "request-\($0.id)", fromUserId: $0.id, toUserId: me, note: "", sentAt: $0.createdAt ?? Date(), status: .pending)
        }
        guard Set(friendships.map(\.userIds)) != Set(db.friendships.map(\.userIds)) || incoming + outgoing != db.friendRequests else { return }
        db.friendships = friendships
        db.friendRequests = incoming + outgoing
        emit(.friendsChanged)
        emit(.friendRequestsChanged)
    }

    private func apply(threads summaries: [RemoteThreadSummary], me: String) {
        var threads: [String: MessageThread] = [:]
        for summary in summaries {
            let id = Self.threadId(kind: summary.kind, id: summary.id, me: me)
            let existing = db.threads[id]
            var participants = [me]
            var context: ThreadContext?
            switch summary.kind {
            case "dm":
                participants.append(summary.id)
                if let name = summary.name { cacheRemoteUser(id: summary.id, nickname: name, rating: nil) }
            case "game":
                context = .game(gameId: summary.id)
                participants = db.games[summary.id]?.playerIds ?? participants
            default:
                context = .group(groupId: summary.id)
            }
            let last = summary.last.map { last in
                // 别人发的最后一条：私信是对方，群聊不知道是谁（列表只显示内容）
                Message(id: "last-\(id)", threadId: id, senderId: last.mine ? me : summary.kind == "dm" ? summary.id : "",
                        content: last.body, sentAt: last.createdAt, deliveredAt: last.createdAt)
            }
            threads[id] = MessageThread(
                id: id, participantIds: participants, lastMessage: last,
                lastActivityAt: last?.sentAt ?? summary.startsAt ?? existing?.lastActivityAt ?? Date(),
                unreadCounts: [me: summary.unread], clearedAt: existing?.clearedAt ?? [:], context: context,
                title: summary.kind == "dm" ? nil : summary.name ?? summary.venue,
                requestFrom: summary.request == "incoming" ? summary.id : summary.request == "outgoing" ? me : nil,
                isPendingRequest: summary.request != nil
            )
            if let last, existing?.lastMessage?.sentAt != last.sentAt || existing?.lastMessage?.content != last.content {
                emit(.messagesChanged(threadId: id))
            }
        }
        guard threads != db.threads else { return }
        db.threads = threads
        emit(.threadsChanged)
    }

    private func apply(notifications: [RemoteNotification], me: String) {
        let items = notifications.map { note in
            InboxItem(id: "note-\(note.id)", kind: Self.inboxKind(note.kind), title: note.title, body: note.body,
                      createdAt: note.createdAt, isRead: note.readAt != nil, relatedId: relatedId(for: note))
        }
        guard items != db.inbox[me] ?? [] else { return }
        db.inbox[me] = items
        emit(.inboxChanged)
    }

    /// 通知点开去哪：链接里的 ID（球局、球友、球群）；找到球友了就打开有提议的那个请求
    private func relatedId(for note: RemoteNotification) -> String? {
        if note.kind == "offer" || note.kind == "offer_auto" {
            return db.tickets.values.first { $0.offerId != nil }?.id
        }
        // 消息请求的链接是 /app/messages/dm/<对方 id>/
        if note.kind == "message_request" { return note.link?.split(separator: "/").last.map(String.init) }
        let parts = (note.link ?? "").split(separator: "/")
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    static func inboxKind(_ kind: String) -> InboxItem.Kind {
        switch kind {
        case "matched": return .gameConfirmed
        case "offer", "offer_auto": return .matchOffer
        case "requeued", "missed", "expired": return .matchUpdate
        case "cancelled": return .gameCancelled
        case "friend": return .friendAccepted
        case "friend_request": return .friendRequest
        case "review": return .surveyDue
        case "group": return .groupUpdate
        case "room": return .roomJoined
        case "room_promoted": return .waitlistPromoted
        case "room_removed": return .kicked
        case "room_closed": return .roomClosed
        case "challenge": return .challenge
        case "message_request": return .messageRequest
        default: return .system
        }
    }

    // MARK: 会话

    /// 本地会话 ID ↔ 服务器的 (kind, id)
    static func threadId(kind: String, id: String, me: String) -> String {
        switch kind {
        case "dm": return MessageThread.id(for: me, id)
        case "game": return MessageThread.gameThreadId(id)
        default: return MessageThread.groupThreadId(id)
        }
    }

    func serverThread(_ threadId: String) -> (kind: String, id: String)? {
        if threadId.hasPrefix("game-") { return ("game", String(threadId.dropFirst(5))) }
        if threadId.hasPrefix("group-") { return ("group", String(threadId.dropFirst(6))) }
        let ids = threadId.split(separator: "|").map(String.init)
        guard ids.count == 2, let me = currentUserId, let other = ids.first(where: { $0 != me }) else { return nil }
        return ("dm", other)
    }

    /// 拉取一个会话的消息（服务器同时记为已读）
    func loadRemoteThread(_ threadId: String) async throws {
        guard let remote, let me = currentUserId, let target = serverThread(threadId) else { return }
        remoteThreadLoadedAt[threadId] = Date()
        let thread: RemoteThread = try await remote.rpc("open_thread", ["p_kind": target.kind, "p_id": target.id])
        for member in thread.members ?? [] where !member.me {
            cacheRemoteUser(id: member.id, nickname: member.nickname, rating: nil)
        }
        db.messages[threadId] = thread.messages.map { item in
            Message(id: "message-\(item.id)", threadId: threadId, senderId: item.mine ? me : item.sender, content: item.body,
                    sentAt: item.createdAt, deliveredAt: item.createdAt)
        }
        if var cached = db.threads[threadId] {
            cached.unreadCounts[me] = 0
            if let members = thread.members, cached.isGroup { cached.participantIds = members.map(\.id) }
            db.threads[threadId] = cached
        }
        scheduleSave()
        emit(.messagesChanged(threadId: threadId))
        emit(.threadsChanged)
    }

    func remoteSendMessage(_ content: String, threadId: String) async throws -> Message {
        guard let remote, let target = serverThread(threadId) else { throw RemoteError.notSignedIn }
        let wasRequest = target.kind == "dm" && remoteMessageOptions[target.id]?.status == "request"
            && db.threads[threadId]?.isPendingRequest != true
        try await remote.call("send_message", ["p_kind": target.kind, "p_id": target.id, "p_body": content])
        try await loadRemoteThread(threadId)
        if wasRequest {
            // 发出的是消息请求：之后等对方接受（会话列表会标出来）
            remoteMessageOptions[target.id] = RemoteMessageOption(status: "requested", group: nil)
            try? await refreshRemoteSocial()
        }
        return db.messages[threadId]?.last ?? Message(threadId: threadId, senderId: currentUserId ?? "", content: content)
    }

    // MARK: 球友

    func remoteSendFriendRequest(to userId: String) async throws {
        let remote = try requireRemote()
        guard let me = currentUserId else { throw RemoteError.notSignedIn }
        let result: String = try await remote.rpc("send_friend_request", ["p_user": userId])
        if result == "requested", !db.friendRequests.contains(where: { $0.fromUserId == me && $0.toUserId == userId }) {
            db.friendRequests.append(FriendRequest(id: "request-\(me)-\(userId)", fromUserId: me, toUserId: userId, note: "",
                                                   sentAt: Date(), status: .pending))
            emit(.friendRequestsChanged)
        }
        try await refreshRemoteSocial()
    }

    private struct FoundPlayer: Decodable {
        let id: String
        let nickname: String
        let rating: Double
        let relationship: String
    }

    /// 按昵称搜球友：服务器只返回允许被搜到的人（不含屏蔽关系），并限速
    func remoteFindPlayers(_ query: String) async throws -> [User] {
        guard let me = currentUserId else { throw RemoteError.notSignedIn }
        let found: [FoundPlayer] = try await requireRemote().rpc("find_players", ["p_query": query])
        for player in found {
            cacheRemoteUser(id: player.id, nickname: player.nickname, rating: player.rating)
            // 在别的设备上申请过的，也显示“等待通过”
            if player.relationship == "requested", !db.friendRequests.contains(where: { $0.fromUserId == me && $0.toUserId == player.id }) {
                db.friendRequests.append(FriendRequest(id: "request-\(me)-\(player.id)", fromUserId: me, toUserId: player.id, note: "",
                                                       sentAt: Date(), status: .pending))
                emit(.friendRequestsChanged)
            }
        }
        return found.compactMap { db.users[$0.id] }
    }

    func remoteReport(_ userId: String, reason: ReportReason, detail: String) async throws {
        let remote = try requireRemote()
        let serverReason: String
        switch reason {
        case .harassment: serverReason = "harassment"
        case .scam: serverReason = "scam"
        case .unsafe: serverReason = "unsafe"
        case .fakeLevel: serverReason = "fake"
        case .noShow, .other: serverReason = "other"
        }
        // 爽约没有对应的分类：写进说明里
        let details = reason == .noShow ? [reason.title, detail].filter { !$0.isEmpty }.joined(separator: "：") : detail
        try await remote.call("report_user", ["p_user": userId, "p_reason": serverReason, "p_details": String(details.prefix(500))])
    }

    /// 打开球友资料前拉取最新的昵称、等级和印象标签（只有打过交道的人才拉得到）
    @discardableResult
    func refreshRemotePlayer(_ userId: String) async -> User? {
        guard let remote else { return db.users[userId] }
        let card = (try? await remote.rpc("player_card", ["p_user": userId], as: RemotePlayerCard?.self)) ?? nil
        guard let card else { return db.users[userId] }
        cacheRemoteUser(id: card.id, nickname: card.nickname, rating: card.rating)
        remoteChallengeStatus[card.id] = card.challenge
        remoteMessageOptions[card.id] = card.message
        if let rate = card.winRate {
            remoteWinRates[card.id] = Rankings.WinRate(games: rate.games, wins: rate.wins, opponents: rate.opponents, averageGap: rate.gap)
        }
        emit(.rankingsChanged)
        emit(.friendsChanged)
        if var user = db.users[card.id] {
            user.reputation.publicTags = card.tags.compactMap { SurveyTag(server: $0) }
            user.reputation.publishedAt = card.tags.isEmpty ? nil : Date()
            db.users[card.id] = user
            emit(.userUpdated(user))
        }
        return db.users[userId]
    }

    /// 别的球友：服务器只给昵称和等级，存进缓存让界面能显示
    func cacheRemoteUser(id: String, nickname: String, rating: Double?) {
        guard id != currentUserId else { return }
        var user = db.users[id] ?? User(id: id, nickname: nickname, phone: "", selfReportedLevel: SkillTier(rating: rating ?? 3).level)
        user.nickname = nickname
        if let rating { user.selfReportedRating = rating }
        db.users[id] = user
    }
}

extension SurveyTag {
    init?(server value: String) {
        guard let tag = SurveyTag.allCases.first(where: { $0.serverValue == value }) else { return nil }
        self = tag
    }
}
