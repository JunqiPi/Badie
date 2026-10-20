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
    /// 防止冒充进女生局
    case wrongGender = "资料里的性别不实"
    /// 昵称、头像、消息不当（审核规则 1.2）
    case inappropriate = "不当内容（昵称、头像、消息）"
    case other = "其他"

    var id: String { rawValue }

    /// 显示文字（rawValue 已持久化，不能改；显示走这里以便本地化）
    var title: String {
        switch self {
        case .noShow: return String(localized: "爽约 / 临时放鸽子")
        case .harassment: return String(localized: "骚扰或不当言论")
        case .fakeLevel: return String(localized: "严重虚报水平")
        case .scam: return String(localized: "推销、诈骗或引流")
        case .unsafe: return String(localized: "球场上危险或不文明行为")
        case .wrongGender: return String(localized: "资料里的性别不实")
        case .inappropriate: return String(localized: "不当内容（昵称、头像、消息）")
        case .other: return String(localized: "其他")
        }
    }
}

// MARK: - 同馆常客

/// 和我常去同一家球馆、并且本人开启了展示的球友
struct VenueRegular: Identifiable, Hashable {
    let user: User
    /// 我们共同常去的球馆（之一）
    let venue: BadmintonCourt

    var id: String { user.id }
}

// MARK: - 站内通知

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
        /// 收到挑战 / 挑战有了回应
        case challenge
        /// 赛果确认、有分歧
        case resultUpdate
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
