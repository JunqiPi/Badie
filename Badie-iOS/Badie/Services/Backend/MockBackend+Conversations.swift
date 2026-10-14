import Foundation

// MARK: - 谁能给谁发消息（依据见 docs/DESIGN.md §12）
//
// - 好友：随便聊
// - 同一场已确认的球局：用球局群聊（确认后开放，赛后 48 小时关闭）
// - 同一个球群：可以发一条纯文字的“消息请求”，对方接受后才能继续；新账号打满 3 场前不能发
// - 陌生人：只能发好友申请

enum MessagePermission: Equatable {
    case allowed
    /// 可以发一条消息请求（同球群）
    case request(groupName: String)
    /// 已经发过请求，等对方接受
    case pendingRequest
    /// 在同一场球局里：去球局群聊
    case gameChat(gameId: String)
    /// 陌生人：先加好友
    case friendsOnly
    /// 新账号还不能发消息请求
    case newAccount
    /// 我屏蔽了对方
    case blocked
}

extension MockBackend {

    // MARK: Permission

    func messagePermission(with userId: String, now: Date = Date()) -> MessagePermission {
        guard let me = currentUser, userId != me.id else { return .friendsOnly }
        if blockedIds(of: me.id).contains(userId) { return .blocked }
        if isFriend(userId) { return .allowed }
        if let thread = db.threads[MessageThread.id(for: me.id, userId)] {
            if thread.isPendingRequest {
                // 对方发来的请求：回复即接受
                return thread.requestFrom == me.id ? .pendingRequest : .allowed
            }
            if thread.lastMessage != nil { return .allowed }
        }
        if let game = sharedOpenGame(with: userId, now: now) { return .gameChat(gameId: game.id) }
        if let group = sharedGroups(with: userId).first {
            guard db.users[userId]?.privacy.allowsMessageRequests ?? true else { return .friendsOnly }
            guard me.attendance.gamesPlayed >= User.gamesBeforeMessageRequests else { return .newAccount }
            return .request(groupName: group.name)
        }
        return .friendsOnly
    }

    /// 和对方共同的、群聊仍开放的球局
    func sharedOpenGame(with userId: String, now: Date = Date()) -> Game? {
        guard let me = currentUserId else { return nil }
        return db.games.values
            .filter { $0.playerIds.contains(me) && $0.playerIds.contains(userId) && isGameChatOpen($0, now: now) }
            .min { $0.slot.startTime < $1.slot.startTime }
    }

    func sharedGroups(with userId: String) -> [PlayGroup] {
        guard let me = currentUserId else { return [] }
        return db.groups.values.filter { $0.isMember(me) && $0.isMember(userId) }.sorted { $0.name < $1.name }
    }

    func isGameChatOpen(_ game: Game, now: Date = Date()) -> Bool {
        guard game.status != .cancelled else { return false }
        return now <= game.slot.endTime.addingTimeInterval(MessageThread.gameChatOpenAfterEnd)
    }

    // MARK: Message requests

    /// 接受对方的消息请求
    func acceptMessageRequest(threadId: String) {
        guard let me = currentUserId, var thread = db.threads[threadId], thread.isPendingRequest,
              thread.requestFrom != me, thread.participantIds.contains(me) else { return }
        thread.isPendingRequest = false
        db.threads[threadId] = thread
        scheduleSave()
        emit(.threadsChanged)
        emit(.messagesChanged(threadId: threadId))
    }

    /// 忽略：只对自己隐藏，对方不会知道被忽略（仍显示“等待接受”）
    func declineMessageRequest(threadId: String) {
        deleteThread(threadId)
    }

    /// 别人发给我的、还没处理的消息请求
    func incomingMessageRequests() -> [MessageThread] {
        guard let me = currentUserId else { return [] }
        return threads().filter { $0.isPendingRequest && $0.requestFrom != me }
    }

    // MARK: Group threads (球局群 / 球群)

    func thread(id: String) -> MessageThread? { db.threads[id] }

    /// 球局群聊：没有就创建（参与者 = 球局所有人）
    @discardableResult
    func ensureGameThread(for game: Game) -> MessageThread {
        let threadId = MessageThread.gameThreadId(game.id)
        if var existing = db.threads[threadId] {
            if Set(existing.participantIds) != Set(game.playerIds) {
                existing.participantIds = game.playerIds.sorted()
                db.threads[threadId] = existing
            }
            return existing
        }
        let title = "\(game.slot.formattedDate) \(DateText.time(game.slot.startTime)) · \(game.court.name)"
        let welcome = Message(threadId: threadId, senderId: "system",
                              content: "球局已确认。这个群聊在赛后 48 小时关闭；开赛前 2 小时内取消会计入履约记录。",
                              sentAt: game.createdAt, deliveredAt: game.createdAt, kind: .system)
        db.messages[threadId] = [welcome]
        let thread = MessageThread(id: threadId, participantIds: game.playerIds.sorted(), lastMessage: welcome,
                                   lastActivityAt: game.createdAt, unreadCounts: [:], clearedAt: [:],
                                   context: .game(gameId: game.id), title: title)
        db.threads[threadId] = thread
        scheduleSave()
        emit(.threadsChanged)
        return thread
    }

    /// 球群群聊：没有就创建（参与者 = 成员）
    @discardableResult
    func ensureGroupThread(for group: PlayGroup, at date: Date = Date()) -> MessageThread {
        let threadId = MessageThread.groupThreadId(group.id)
        if var existing = db.threads[threadId] {
            if Set(existing.participantIds) != Set(group.memberIds) || existing.title != group.name {
                existing.participantIds = group.memberIds.sorted()
                existing.title = group.name
                db.threads[threadId] = existing
            }
            return existing
        }
        let welcome = Message(threadId: threadId, senderId: "system",
                              content: "「\(group.name)」群聊。报名、候补在球群页面里，不用在群里接龙。",
                              sentAt: date, deliveredAt: date, kind: .system)
        db.messages[threadId] = [welcome]
        let thread = MessageThread(id: threadId, participantIds: group.memberIds.sorted(), lastMessage: welcome,
                                   lastActivityAt: date, unreadCounts: [:], clearedAt: [:],
                                   context: .group(groupId: group.id), title: group.name)
        db.threads[threadId] = thread
        return thread
    }

    /// 群聊是否还能发消息
    func canPost(in thread: MessageThread, now: Date = Date()) -> Bool {
        guard let me = currentUserId, thread.participantIds.contains(me) else { return false }
        switch thread.context {
        case .game(let gameId):
            guard let game = db.games[gameId] else { return false }
            return isGameChatOpen(game, now: now)
        case .group(let groupId):
            return db.groups[groupId]?.isMember(me) ?? false
        case nil:
            return true
        }
    }

    /// 在群聊里发消息
    @discardableResult
    func sendGroupMessage(_ content: String, threadId: String, now: Date = Date()) async throws -> Message {
        let me = try requireUser()
        switch Message.validate(content) {
        case .empty: throw BackendError.messageEmpty
        case .tooLong: throw BackendError.messageTooLong
        case .valid: break
        }
        guard let thread = db.threads[threadId], thread.isGroup else { throw BackendError.chatClosed }
        guard canPost(in: thread, now: now) else { throw BackendError.chatClosed }
        await networkDelay(0.1...0.3)
        let message = Message(threadId: threadId, senderId: me.id,
                              content: content.trimmingCharacters(in: .whitespacesAndNewlines), deliveredAt: Date())
        appendMessage(message, participants: thread.participantIds, countsAsUnread: true)
        // 群里有人回应
        let blocked = blockedIds(of: me.id)
        if let responder = thread.participantIds.filter({ isBot($0) && !blocked.contains($0) })
            .min(by: { "\($0)\(content)".stableHash < "\($1)\(content)".stableHash }) {
            let reply = botReply(to: content, botId: responder)
            simulate(after: Double.random(in: 3...7)) { [weak self] in
                guard let self, let current = self.db.threads[threadId] else { return }
                self.appendMessage(Message(threadId: threadId, senderId: responder, content: reply, deliveredAt: Date()),
                                   participants: current.participantIds, countsAsUnread: true)
            }
        }
        return message
    }

    /// 模拟球友在群聊里说一句（成局、取消等场景）
    func postBotMessage(_ text: String, from botId: String, in threadId: String, after delay: ClosedRange<Double> = 2...4) {
        simulate(after: Double.random(in: delay)) { [weak self] in
            guard let self, let thread = self.db.threads[threadId], thread.participantIds.contains(botId) else { return }
            self.appendMessage(Message(threadId: threadId, senderId: botId, content: text, deliveredAt: Date()),
                               participants: thread.participantIds, countsAsUnread: true)
        }
    }
}
