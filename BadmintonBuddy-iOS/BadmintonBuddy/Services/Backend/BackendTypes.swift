import Foundation

// MARK: - 后端事件（模拟服务端推送）

enum BackendEvent {
    case sessionChanged
    case userUpdated(User)
    case friendsChanged
    case friendRequestsChanged
    case threadsChanged
    case messagesChanged(threadId: String)
    case typing(threadId: String, isTyping: Bool)
    case roomsChanged
    case kicked(roomCode: String)
    case roomClosed(roomCode: String, reason: RoomCloseReason)
    case gamesChanged
    case gameCreated(Game)
    case surveysChanged
    case inboxChanged
}

typealias BackendEventHandler = @MainActor (BackendEvent) -> Void

// MARK: - 错误

enum BackendError: LocalizedError, Equatable {
    case invalidPhone
    case invalidCode
    case codeExpired
    case consentRequired
    case notSignedIn
    case invalidNickname
    case userNotFound
    case alreadyFriends
    case requestAlreadySent
    case cannotFriendSelf
    case blocked
    case messageEmpty
    case messageTooLong
    case roomNotFound
    case roomFull
    case roomClosed
    case roomExpired
    case notRoomOwner
    case alreadyInRoom
    case levelOutOfRange(String)
    case notEnoughPlayers(required: Int, current: Int)
    case invalidSlot(String)
    case gameNotFound
    case gameAlreadyFinished
    case checkInNotOpen
    case surveyDuplicate
    case surveyExpired
    case surveyInvalid
    case tooManyRecurringSlots
    case matchingSuspended

    var errorDescription: String? {
        switch self {
        case .invalidPhone: return "请输入 11 位中国大陆手机号"
        case .invalidCode: return "验证码不正确，请重新输入"
        case .codeExpired: return "验证码已过期，请重新获取"
        case .consentRequired: return "请先阅读并同意用户协议与隐私政策"
        case .notSignedIn: return "请先登录"
        case .invalidNickname: return "昵称需为 2-12 个字符"
        case .userNotFound: return "没有找到这位球友"
        case .alreadyFriends: return "你们已经是球友了"
        case .requestAlreadySent: return "已经发送过申请，等待对方通过"
        case .cannotFriendSelf: return "不能添加自己为球友"
        case .blocked: return "无法与该用户互动"
        case .messageEmpty: return "消息不能为空"
        case .messageTooLong: return "消息不能超过 \(Message.maxContentLength) 字"
        case .roomNotFound: return "房间不存在，请检查房间码"
        case .roomFull: return "房间已满"
        case .roomClosed: return "房间已关闭"
        case .roomExpired: return "房间已过期"
        case .notRoomOwner: return "只有房主可以进行此操作"
        case .alreadyInRoom: return "你已经在一个房间中，请先退出"
        case .levelOutOfRange(let range): return "这个局要求 \(range)，与你的水平不符"
        case .notEnoughPlayers(let required, let current): return "还差 \(required - current) 人，需要 \(required) 人才能开始"
        case .invalidSlot(let reason): return reason
        case .gameNotFound: return "球局不存在"
        case .gameAlreadyFinished: return "球局已结束或已取消"
        case .checkInNotOpen: return "开赛前 30 分钟才能签到"
        case .surveyDuplicate: return "你已经评价过这场球了"
        case .surveyExpired: return "评价已超过 48 小时，无法提交"
        case .surveyInvalid: return "评价内容无效"
        case .tooManyRecurringSlots: return "最多保存 \(TimeSlotConstants.maximumRecurringSlots) 个常用时间"
        case .matchingSuspended: return "因多次爽约，快速匹配暂停中"
        }
    }
}

enum AuthOutcome: Equatable {
    case signedIn(User)
    case needsProfile(phone: String)
}

/// 创建房间的参数
struct RoomDraft: Hashable {
    var mode: GameMode = .doubles
    var visibility: RoomVisibility = .privateRoom
    var court: BadmintonCourt?
    var slot: TimeSlot?
    var levelRange: ClosedRange<Int> = 1...9
    var tags: [RoomTag] = []
    var note: String = ""
}

enum MatchSearchResult {
    case proposals([MatchProposal])
    case none(suggestions: [MatchRelaxation])
}

// MARK: - 模拟球友（机器人）画像

enum AvailabilityPattern: String, Codable, CaseIterable, Hashable {
    case weekdayEvenings
    case weekendDaytime
    case flexible
    case mornings
    case nightOwl
}

struct BotProfile: Codable, Hashable {
    let userId: String
    /// 相对世界中心的偏移（公里）
    var eastKm: Double
    var northKm: Double
    var pattern: AvailabilityPattern
    /// 通过好友申请/接受邀请的概率
    var friendliness: Double
}

/// 举报记录
struct ReportRecord: Codable, Hashable {
    let reporterId: String
    let reportedUserId: String
    let reason: ReportReason
    let detail: String
    let createdAt: Date
}

// MARK: - 数据库快照（JSON 持久化）

struct Database: Codable {
    var version: Int = 1
    var currentUserId: String?
    /// 手机号 -> 用户 ID
    var accounts: [String: String] = [:]
    var users: [String: User] = [:]
    var bots: [String: BotProfile] = [:]
    var worldCenter: Coordinate = .fallbackCenter
    var knownCourts: [BadmintonCourt] = BadmintonCourt.curatedBeijing
    var friendships: [Friendship] = []
    var friendRequests: [FriendRequest] = []
    var threads: [String: MessageThread] = [:]
    var messages: [String: [Message]] = [:]
    var blocks: [String: [BlockedUser]] = [:]
    var rooms: [String: Room] = [:]
    var games: [String: Game] = [:]
    var surveys: [MatchSurvey] = []
    /// 双盲评价：对方提交后暂存，等被评价者也提交或 48 小时后才计入
    var heldSurveys: [MatchSurvey] = []
    var pendingSurveys: [PendingSurvey] = []
    var inbox: [String: [InboxItem]] = [:]
    var recurringSlots: [String: [RecurringTimeSlot]] = [:]
    var favoriteCourtIds: [String: [String]] = [:]
    var reports: [ReportRecord] = []
    var seededUserIds: [String] = []
}

// MARK: - 可复现的伪随机数（保证模拟世界在每次启动时一致）

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    init(_ string: String) {
        self.init(seed: UInt64(string.stableHash))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
