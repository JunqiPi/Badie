import Foundation

// MARK: - 约战
//
// 点头像向某人发起一场单打挑战。对方可以接受或不理会：拒绝和超时对发起人显示的都是“未成行”，
// 不会让人尴尬。谁能挑战我由我自己决定（默认只接受水平相近的人）。

enum ChallengePolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    case everyone
    case similarLevel
    case friends
    case nobody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: return String(localized: "所有人")
        case .similarLevel: return String(localized: "水平相近的人")
        case .friends: return String(localized: "仅球友")
        case .nobody: return String(localized: "不接受")
        }
    }

    var detail: String {
        switch self {
        case .everyone: return String(localized: "任何同一国家/地区的球友都能向你发起挑战")
        case .similarLevel: return String(localized: "只接受和你相差 1 级以内的挑战")
        case .friends: return String(localized: "只有加了球友的人能挑战你")
        case .nobody: return String(localized: "别人看不到“发起挑战”")
        }
    }
}

enum ChallengeStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
    case expired
    case withdrawn
}

struct Challenge: Identifiable, Codable, Hashable {
    let id: String
    let challengerId: String
    let targetId: String
    let court: BadmintonCourt
    let slot: TimeSlot
    let message: String
    let createdAt: Date
    var status: ChallengeStatus
    var respondedAt: Date?
    var gameId: String?

    /// 对方 48 小时内不回应就自动过期
    static let responseWindow: TimeInterval = 48 * 3600
    static let maxOutgoingPending = 3
    static let maxIncomingPending = 3
    static let dailyLimit = 5
    /// 被拒或过期后，多久内不能再挑战同一个人
    static let cooldown: TimeInterval = 7 * 86400
    /// “水平相近”：相差不超过 1 级
    static let similarLevelRange = 1.0
    static let messageLimit = 60

    var expiresAt: Date {
        min(createdAt.addingTimeInterval(Self.responseWindow), slot.startTime)
    }

    func isExpired(now: Date = Date()) -> Bool {
        status == .pending && now >= expiresAt
    }

    func involves(_ userId: String) -> Bool { challengerId == userId || targetId == userId }

    func other(than userId: String) -> String { challengerId == userId ? targetId : challengerId }
}

/// 能不能向某人发起挑战；不能时给出原因
enum ChallengeAvailability: Equatable {
    case available
    case notAccepting
    case friendsOnly
    case levelOutOfRange
    case targetBusy
    case alreadyPending
    case cooldown(until: Date)
    case tooManyOutgoing
    case dailyLimitReached
    case unavailable

    var reason: String? {
        switch self {
        case .available: return nil
        case .notAccepting: return String(localized: "TA 暂不接受挑战")
        case .friendsOnly: return String(localized: "TA 只接受球友的挑战")
        case .levelOutOfRange: return String(localized: "TA 只接受水平相近的挑战")
        case .targetBusy: return String(localized: "TA 待处理的挑战已满，晚点再来")
        case .alreadyPending: return String(localized: "已经向 TA 发出挑战，等回应中")
        case .cooldown(let until): return String(localized: "\(DateText.shortDay(until)) 之后才能再次挑战 TA")
        case .tooManyOutgoing: return String(localized: "你同时最多发出 \(Challenge.maxOutgoingPending) 个挑战")
        case .dailyLimitReached: return String(localized: "今天的挑战次数用完了")
        case .unavailable: return String(localized: "暂时无法挑战 TA")
        }
    }
}
