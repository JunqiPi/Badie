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

// MARK: - 防骗：站外联系方式与链接

enum ContactInfoDetector {
    private static let keywords = [
        "微信", "wechat", "weixin", "vx", "v信", "加v", "whatsapp", "telegram", "电报", "line id",
        "手机号", "电话号", "venmo", "zelle", "paypal", "cash app", "cashapp", "验证码"
    ]

    /// 是否提到站外联系方式或转账方式（手机号、微信、WhatsApp、Venmo…）
    static func mentionsOffPlatformContact(_ text: String) -> Bool {
        let lower = text.lowercased()
        if keywords.contains(where: { lower.contains($0) }) { return true }
        return text.range(of: #"(?:\d[\s\-\.]?){7,}"#, options: .regularExpression) != nil
    }

    /// 是否包含链接
    static func containsLink(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return false }
        return detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// 群聊的来源
enum ThreadContext: Codable, Hashable {
    /// 球局群：确认后开放，赛后 48 小时关闭
    case game(gameId: String)
    /// 球群：成员都在
    case group(groupId: String)
}

/// 会话：两人私信，或球局 / 球群的群聊
struct MessageThread: Identifiable, Codable, Hashable {
    let id: String
    var participantIds: [String]
    var lastMessage: Message?
    var lastActivityAt: Date
    /// 每位参与者的未读数
    var unreadCounts: [String: Int]
    /// 每位参与者“删除会话”的时间：只隐藏该时间之前的消息，对方不受影响
    var clearedAt: [String: Date]
    /// nil = 两人私信
    var context: ThreadContext?
    /// 群聊标题
    var title: String?
    /// 消息请求的发起人：对方接受前只能发这一条
    var requestFrom: String?
    var isPendingRequest = false

    /// 赛后多久关闭球局群聊
    static let gameChatOpenAfterEnd: TimeInterval = 48 * 3600

    var isGroup: Bool { context != nil }

    static func id(for first: String, _ second: String) -> String {
        [first, second].sorted().joined(separator: "|")
    }

    static func gameThreadId(_ gameId: String) -> String { "game-\(gameId)" }

    static func groupThreadId(_ groupId: String) -> String { "group-\(groupId)" }

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
