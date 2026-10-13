import Foundation

// MARK: - 好友、私信、屏蔽与举报

extension MockBackend {

    // MARK: Directory

    /// 按昵称或 4 位 ID 搜索球友
    func searchUsers(query: String) -> [User] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let me = currentUserId else { return [] }
        let blocked = blockedIds()
        return db.users.values
            .filter { $0.id != me && !blocked.contains($0.id) }
            .filter { $0.nickname.localizedCaseInsensitiveContains(text) || $0.shortId == text }
            .sorted { $0.nickname < $1.nickname }
    }

    // MARK: Friends

    func friendIds(of userId: String? = nil) -> [String] {
        guard let id = userId ?? currentUserId else { return [] }
        return db.friendships.filter { $0.involves(id) }.compactMap { $0.other(than: id) }
    }

    func friends() -> [User] {
        let blocked = blockedIds()
        return friendIds().compactMap { db.users[$0] }
            .filter { !blocked.contains($0.id) }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    func isFriend(_ userId: String) -> Bool {
        friendIds().contains(userId)
    }

    func incomingRequests() -> [FriendRequest] {
        guard let id = currentUserId else { return [] }
        let blocked = blockedIds()
        return db.friendRequests
            .filter { $0.toUserId == id && $0.status == .pending && !blocked.contains($0.fromUserId) }
            .sorted { $0.sentAt > $1.sentAt }
    }

    func outgoingRequests() -> [FriendRequest] {
        guard let id = currentUserId else { return [] }
        return db.friendRequests.filter { $0.fromUserId == id && $0.status == .pending }
    }

    func hasPendingRequest(to userId: String) -> Bool {
        outgoingRequests().contains { $0.toUserId == userId }
    }

    func sendFriendRequest(to userId: String, note: String) async throws {
        let me = try requireUser()
        guard userId != me.id else { throw BackendError.cannotFriendSelf }
        guard db.users[userId] != nil else { throw BackendError.userNotFound }
        guard !isFriend(userId) else { throw BackendError.alreadyFriends }
        guard !hasPendingRequest(to: userId) else { throw BackendError.requestAlreadySent }
        guard !isBlockedEitherWay(me.id, userId) else { throw BackendError.blocked }
        await networkDelay()

        // 对方已经向我发过申请：直接成为好友
        if let reverse = db.friendRequests.firstIndex(where: { $0.fromUserId == userId && $0.toUserId == me.id && $0.status == .pending }) {
            db.friendRequests[reverse].status = .accepted
            makeFriends(me.id, userId)
            scheduleSave()
            emit(.friendRequestsChanged)
            emit(.friendsChanged)
            return
        }

        let request = FriendRequest(
            id: UUID().uuidString, fromUserId: me.id, toUserId: userId,
            note: String(note.prefix(40)), sentAt: Date(), status: .pending
        )
        db.friendRequests.append(request)
        scheduleSave()
        emit(.friendRequestsChanged)

        // 模拟对方处理申请
        if let bot = db.bots[userId] {
            let accept = Double.random(in: 0..<1) < bot.friendliness
            simulate(after: Double.random(in: 2...6)) { [weak self] in
                self?.botAnswerFriendRequest(requestId: request.id, accept: accept)
            }
        }
    }

    func respond(to requestId: String, accept: Bool) async throws {
        guard let me = currentUserId else { throw BackendError.notSignedIn }
        guard let index = db.friendRequests.firstIndex(where: { $0.id == requestId && $0.toUserId == me }) else {
            throw BackendError.userNotFound
        }
        await networkDelay()
        db.friendRequests[index].status = accept ? .accepted : .declined
        let from = db.friendRequests[index].fromUserId
        if accept {
            makeFriends(me, from)
        }
        // 已处理的申请对应的通知标记为已读
        if var items = db.inbox[me] {
            for i in items.indices where items[i].kind == .friendRequest && items[i].relatedId == from {
                items[i].isRead = true
            }
            db.inbox[me] = items
        }
        scheduleSave()
        emit(.friendRequestsChanged)
        emit(.friendsChanged)
        emit(.inboxChanged)
    }

    func removeFriend(_ userId: String) async throws {
        guard let me = currentUserId else { throw BackendError.notSignedIn }
        await networkDelay()
        db.friendships.removeAll { $0.involves(me) && $0.involves(userId) }
        scheduleSave()
        emit(.friendsChanged)
    }

    func makeFriends(_ first: String, _ second: String) {
        guard !db.friendships.contains(where: { $0.involves(first) && $0.involves(second) }) else { return }
        db.friendships.append(Friendship(between: first, and: second))
        let threadId = MessageThread.id(for: first, second)
        appendMessage(Message(threadId: threadId, senderId: "system", content: "你们已经成为球友，打个招呼约一场吧 🏸",
                              deliveredAt: Date(), readAt: Date(), kind: .system),
                      participants: [first, second], countsAsUnread: false)
    }

    private func botAnswerFriendRequest(requestId: String, accept: Bool) {
        guard let index = db.friendRequests.firstIndex(where: { $0.id == requestId && $0.status == .pending }) else { return }
        let request = db.friendRequests[index]
        db.friendRequests[index].status = accept ? .accepted : .declined
        guard accept, let bot = db.users[request.toUserId] else {
            scheduleSave()
            emit(.friendRequestsChanged)
            return
        }
        makeFriends(request.fromUserId, request.toUserId)
        addInbox(InboxItem(kind: .friendAccepted, title: "\(bot.nickname) 通过了你的好友申请",
                           body: "现在可以私信、邀请 TA 进房间了。", relatedId: bot.id), to: request.fromUserId)
        scheduleSave()
        emit(.friendRequestsChanged)
        emit(.friendsChanged)
        emit(.threadsChanged)
    }

    // MARK: Blocking & reporting

    func blockedIds(of userId: String? = nil) -> Set<String> {
        guard let id = userId ?? currentUserId else { return [] }
        return Set((db.blocks[id] ?? []).map(\.blockedUserId))
    }

    func blockedUsers() -> [BlockedUser] {
        guard let id = currentUserId else { return [] }
        return db.blocks[id] ?? []
    }

    func isBlockedEitherWay(_ first: String, _ second: String) -> Bool {
        blockedIds(of: first).contains(second) || blockedIds(of: second).contains(first)
    }

    /// 屏蔽：对方无法再给你发消息、加好友或进入你的房间；不会通知对方
    func block(_ userId: String) {
        guard let me = currentUserId, userId != me else { return }
        var list = db.blocks[me] ?? []
        guard !list.contains(where: { $0.blockedUserId == userId }) else { return }
        list.append(BlockedUser(blockedUserId: userId, blockedAt: Date()))
        db.blocks[me] = list
        db.friendships.removeAll { $0.involves(me) && $0.involves(userId) }
        db.friendRequests.removeAll { ($0.fromUserId == userId && $0.toUserId == me) || ($0.fromUserId == me && $0.toUserId == userId) }
        scheduleSave()
        emit(.friendsChanged)
        emit(.friendRequestsChanged)
        emit(.threadsChanged)
    }

    func unblock(_ userId: String) {
        guard let me = currentUserId else { return }
        db.blocks[me]?.removeAll { $0.blockedUserId == userId }
        scheduleSave()
        emit(.friendsChanged)
        emit(.threadsChanged)
    }

    func report(_ userId: String, reason: ReportReason, detail: String) async {
        guard let me = currentUserId else { return }
        await networkDelay()
        db.reports.append(ReportRecord(reporterId: me, reportedUserId: userId, reason: reason,
                                       detail: String(detail.prefix(200)), createdAt: Date()))
        scheduleSave()
    }

    // MARK: Threads

    func threads() -> [MessageThread] {
        guard let me = currentUserId else { return [] }
        let blocked = blockedIds()
        return db.threads.values
            .filter { $0.participantIds.contains(me) && $0.isVisible(to: me) }
            .filter { thread in
                guard let other = thread.otherParticipantId(currentUserId: me) else { return false }
                return !blocked.contains(other)
            }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func totalUnread() -> Int {
        guard let me = currentUserId else { return 0 }
        return threads().reduce(0) { $0 + $1.unreadCount(for: me) }
    }

    /// 加载最近的消息（默认 50 条），删除会话前的消息不可见
    func messages(threadId: String, limit: Int = 50) -> [Message] {
        guard let me = currentUserId else { return [] }
        let all = db.messages[threadId] ?? []
        let cleared = db.threads[threadId]?.clearedAt[me]
        let visible = all.filter { message in
            guard let cleared else { return true }
            return message.sentAt > cleared
        }
        return Array(visible.suffix(limit))
    }

    func sendMessage(_ content: String, to userId: String, kind: MessageKind = .text) async throws -> Message {
        let me = try requireUser()
        switch Message.validate(content) {
        case .empty: throw BackendError.messageEmpty
        case .tooLong: throw BackendError.messageTooLong
        case .valid: break
        }
        guard !blockedIds(of: me.id).contains(userId) else { throw BackendError.blocked }
        await networkDelay(0.1...0.3)

        let threadId = MessageThread.id(for: me.id, userId)
        var message = Message(threadId: threadId, senderId: me.id,
                              content: content.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
        // 被对方屏蔽：消息对自己显示为已发送，但不会送达（不暴露屏蔽状态）
        let blockedByOther = blockedIds(of: userId).contains(me.id)
        if !blockedByOther {
            message.deliveredAt = Date()
        }
        appendMessage(message, participants: [me.id, userId], countsAsUnread: !blockedByOther)

        if !blockedByOther, isBot(userId) {
            simulateBotConversation(botId: userId, threadId: threadId, incoming: message)
        }
        return message
    }

    func appendMessage(_ message: Message, participants: [String], countsAsUnread: Bool) {
        let threadId = message.threadId
        var list = db.messages[threadId] ?? []
        list.append(message)
        db.messages[threadId] = Array(list.suffix(500))
        var thread = db.threads[threadId] ?? MessageThread(
            id: threadId, participantIds: participants.sorted(), lastMessage: nil,
            lastActivityAt: message.sentAt, unreadCounts: [:], clearedAt: [:]
        )
        thread.lastMessage = message
        thread.lastActivityAt = message.sentAt
        if countsAsUnread {
            for participant in thread.participantIds where participant != message.senderId {
                thread.unreadCounts[participant, default: 0] += 1
            }
        }
        db.threads[threadId] = thread
        scheduleSave()
        emit(.messagesChanged(threadId: threadId))
        emit(.threadsChanged)
    }

    /// 标记已读（产生已读回执）
    func markThreadRead(_ threadId: String) {
        guard let me = currentUserId, var thread = db.threads[threadId] else { return }
        let hadUnread = thread.unreadCount(for: me) > 0
        thread.unreadCounts[me] = 0
        db.threads[threadId] = thread
        if var list = db.messages[threadId] {
            var changed = false
            for index in list.indices where list[index].senderId != me && list[index].readAt == nil {
                list[index].readAt = Date()
                if list[index].deliveredAt == nil { list[index].deliveredAt = Date() }
                changed = true
            }
            if changed { db.messages[threadId] = list }
        }
        if hadUnread {
            scheduleSave()
            emit(.threadsChanged)
        }
    }

    /// 删除会话：仅对自己隐藏，对方仍保留
    func deleteThread(_ threadId: String) {
        guard let me = currentUserId, var thread = db.threads[threadId] else { return }
        thread.clearedAt[me] = Date()
        thread.unreadCounts[me] = 0
        db.threads[threadId] = thread
        scheduleSave()
        emit(.threadsChanged)
    }

    // MARK: Bot conversation

    private func simulateBotConversation(botId: String, threadId: String, incoming: Message) {
        // 已读回执
        simulate(after: Double.random(in: 1.0...2.5)) { [weak self] in
            guard let self, var list = self.db.messages[threadId] else { return }
            if let index = list.firstIndex(where: { $0.id == incoming.id }) {
                list[index].readAt = Date()
                self.db.messages[threadId] = list
                self.emit(.messagesChanged(threadId: threadId))
            }
            self.emit(.typing(threadId: threadId, isTyping: true))
        }
        // 回复
        let reply = botReply(to: incoming.content, botId: botId)
        simulate(after: Double.random(in: 3.0...5.5)) { [weak self] in
            guard let self, let me = self.currentUserId, !self.blockedIds(of: me).contains(botId) else { return }
            self.emit(.typing(threadId: threadId, isTyping: false))
            let message = Message(threadId: threadId, senderId: botId, content: reply, deliveredAt: Date())
            self.appendMessage(message, participants: [me, botId], countsAsUnread: true)
        }
    }

    func botReply(to text: String, botId: String) -> String {
        let center = currentUser?.location ?? db.worldCenter
        let courtName = nearestVenues(to: center, count: 1).first?.name ?? "附近的球馆"
        let rules: [([String], String)] = [
            (["几点", "时间", "什么时候", "啥时候"], "我工作日晚上 7 点后都可以，周末更灵活，你定～"),
            (["哪", "球馆", "地方", "在哪"], "去\(courtName)吧，交通方便，场地也不错"),
            (["带球", "球拍", "带拍"], "我带一筒球，你带水就行 😄"),
            (["到了", "到啦", "门口"], "好嘞，我两分钟到，在前台等你"),
            (["谢谢", "辛苦", "感谢"], "客气啦，下次再约！"),
            (["双打"], "双打可以呀，我再叫个朋友凑一桌？"),
            (["单打"], "单打来！不过我体能一般，手下留情哈哈"),
            (["多少钱", "费用", "AA", "aa"], "老规矩 AA，场地费加球钱平摊"),
            (["你好", "嗨", "hi", "hello", "在吗"], "在的在的～最近想打球吗？"),
            (["房间", "房间码"], "收到，我看看能不能赶上")
        ]
        let lower = text.lowercased()
        for (keywords, reply) in rules where keywords.contains(where: { lower.contains($0.lowercased()) }) {
            return reply
        }
        if text.contains("?") || text.contains("？") {
            return "可以呀，你定就行 👌"
        }
        let fallback = ["好呀！", "没问题 👌", "收到～", "哈哈可以", "那就这么定了", "期待一起打球！"]
        var rng = SeededGenerator("\(botId)-\(text)")
        return fallback.randomElement(using: &rng) ?? "好呀！"
    }
}
