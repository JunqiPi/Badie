import Foundation

// MARK: - 好友

enum FriendRequestStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
}

struct FriendRequest: Identifiable, Codable, Hashable {
    let id: String
    let fromUserId: String
    let toUserId: String
    var note: String
    let sentAt: Date
    var status: FriendRequestStatus
}

/// 双向好友关系
struct Friendship: Identifiable, Codable, Hashable {
    let id: String
    let userIds: [String]
    let createdAt: Date

    init(id: String = UUID().uuidString, between first: String, and second: String, createdAt: Date = Date()) {
        self.id = id
        self.userIds = [first, second].sorted()
        self.createdAt = createdAt
    }

    func involves(_ userId: String) -> Bool { userIds.contains(userId) }

    func other(than userId: String) -> String? { userIds.first { $0 != userId } }
}

// MARK: - 屏蔽与举报

struct BlockedUser: Identifiable, Codable, Hashable {
    var id: String { blockedUserId }
    let blockedUserId: String
    let blockedAt: Date
}

enum ReportReason: String, CaseIterable, Identifiable, Codable, Hashable {
    case noShow = "爽约 / 临时放鸽子"
    case harassment = "骚扰或不当言论"
    case fakeLevel = "严重虚报水平"
    case scam = "推销、诈骗或引流"
    case unsafe = "球场上危险或不文明行为"
    case other = "其他"

    var id: String { rawValue }
}

// MARK: - 站内通知

/// 同馆常客：和我常去同一家球馆、并且本人开启了展示的球友
struct VenueRegular: Identifiable, Hashable {
    let user: User
    /// 我们共同常去的球馆（之一）
    let venue: BadmintonCourt

    var id: String { user.id }
}

struct InboxItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case friendRequest
        case friendAccepted
        case roomInvite
        case roomJoined
        case kicked
        case roomClosed
        case waitlistPromoted
        case surveyDue
        case gameConfirmed
        case gameCancelled
        case gameReminder
        case reviewReceived
        /// 找到搭子，等待确认
        case matchOffer
        /// 匹配进展（补位、没凑成、请求结束）
        case matchUpdate
        /// 有人想和你聊天（同球群的消息请求）
        case messageRequest
        /// 球群动态（候补转正、加入申请通过、场次取消）
        case groupUpdate
        /// 你们都想再约一场
        case rematch
        case system
    }

    let id: String
    let kind: Kind
    var title: String
    var body: String
    let createdAt: Date
    var isRead: Bool
    /// 关联对象 ID（用户、房间码、球局、问卷）
    var relatedId: String?

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        body: String,
        createdAt: Date = Date(),
        isRead: Bool = false,
        relatedId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.relatedId = relatedId
    }
}
