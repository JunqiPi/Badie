import Foundation

// MARK: - 私信

enum MessageKind: Codable, Hashable {
    case text
    /// 房间邀请卡片
    case roomInvite(code: String)
    /// 球局分享卡片
    case gameShare(gameId: String)
    /// 系统提示（如"你们已成为球友"）
    case system
}

struct Message: Identifiable, Codable, Hashable {
    let id: String
    let threadId: String
    let senderId: String
    let content: String
    let sentAt: Date
    var deliveredAt: Date?
    var readAt: Date?
    var kind: MessageKind

    static let maxContentLength = 1000

    var isDelivered: Bool { deliveredAt != nil }
    var isRead: Bool { readAt != nil }

    init(
        id: String = UUID().uuidString,
        threadId: String,
        senderId: String,
        content: String,
        sentAt: Date = Date(),
        deliveredAt: Date? = nil,
        readAt: Date? = nil,
        kind: MessageKind = .text
    ) {
        self.id = id
        self.threadId = threadId
        self.senderId = senderId
        self.content = content
        self.sentAt = sentAt
        self.deliveredAt = deliveredAt
        self.readAt = readAt
        self.kind = kind
    }

    /// 验证消息内容（1-1000 字）
    static func validate(_ content: String) -> MessageValidation {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if content.count > maxContentLength { return .tooLong }
        return .valid
    }
}

enum MessageValidation: Equatable {
    case valid, empty, tooLong
}

/// 两个用户之间的会话
struct MessageThread: Identifiable, Codable, Hashable {
    let id: String
    let participantIds: [String]
    var lastMessage: Message?
    var lastActivityAt: Date
    /// 每位参与者的未读数
    var unreadCounts: [String: Int]
    /// 每位参与者“删除会话”的时间：只隐藏该时间之前的消息，对方不受影响
    var clearedAt: [String: Date]

    static func id(for first: String, _ second: String) -> String {
        [first, second].sorted().joined(separator: "|")
    }

    func otherParticipantId(currentUserId: String) -> String? {
        participantIds.first { $0 != currentUserId }
    }

    func unreadCount(for userId: String) -> Int { unreadCounts[userId] ?? 0 }

    /// 对某个用户是否可见（删除后无新消息则隐藏）
    func isVisible(to userId: String) -> Bool {
        guard let last = lastMessage else { return false }
        guard let cleared = clearedAt[userId] else { return true }
        return last.sentAt > cleared
    }
}
