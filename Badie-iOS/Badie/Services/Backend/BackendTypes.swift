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
    case venuesChanged
    /// 约球请求或匹配提议有变化
    case matchmakingChanged
    /// 球群、场次报名有变化
    case groupsChanged
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
    case venueNameInvalid
    case venueAddressIncomplete
    case venueNotFound
    case ticketOverlap
    case tooLateToRequest
    case offerClosed
    case venueDuplicate(existingName: String)
    case venueRateLimited
    case notFriends
    case newAccountMessageLimit
    case messageRequestPending
    case useGameChat
    case requestContainsContact
    case chatClosed
    case groupNotFound
    case notGroupMember
    case groupNameInvalid
    case groupScheduleInvalid
    case sessionClosed
    case ownerCannotLeave
    case assessmentTooSoon(Date)
    case verificationInvalid(String)
    case challengeUnavailable(String)
    case challengeNotFound
    case resultWindowClosed
    case profileContainsContact

    var errorDescription: String? {
        switch self {
        case .invalidPhone: return String(localized: "手机号格式不正确，请检查国家/地区和号码")
        case .invalidCode: return String(localized: "验证码不正确，请重新输入")
        case .codeExpired: return String(localized: "验证码已过期，请重新获取")
        case .consentRequired: return String(localized: "请先阅读并同意用户协议与隐私政策")
        case .notSignedIn: return String(localized: "请先登录")
        case .invalidNickname: return String(localized: "昵称需为 2-12 个字符")
        case .userNotFound: return String(localized: "没有找到这位球友")
        case .alreadyFriends: return String(localized: "你们已经是球友了")
        case .requestAlreadySent: return String(localized: "已经发送过申请，等待对方通过")
        case .cannotFriendSelf: return String(localized: "不能添加自己为球友")
        case .blocked: return String(localized: "无法与该用户互动")
        case .messageEmpty: return String(localized: "消息不能为空")
        case .messageTooLong: return String(localized: "消息不能超过 \(Message.maxContentLength) 字")
        case .roomNotFound: return String(localized: "房间不存在，请检查房间码")
        case .roomFull: return String(localized: "房间已满")
        case .roomClosed: return String(localized: "房间已关闭")
        case .roomExpired: return String(localized: "房间已过期")
        case .notRoomOwner: return String(localized: "只有房主可以进行此操作")
        case .alreadyInRoom: return String(localized: "你已经在一个房间中，请先退出")
        case .levelOutOfRange(let range): return String(localized: "这个局要求 \(range)，与你的水平不符")
        case .notEnoughPlayers(let required, let current): return String(localized: "还差 \(required - current) 人，需要 \(required) 人才能开始")
        case .invalidSlot(let reason): return reason
        case .gameNotFound: return String(localized: "球局不存在")
        case .gameAlreadyFinished: return String(localized: "球局已结束或已取消")
        case .checkInNotOpen: return String(localized: "开赛前 30 分钟才能签到")
        case .surveyDuplicate: return String(localized: "你已经评价过这场球了")
        case .surveyExpired: return String(localized: "评价已超过 48 小时，无法提交")
        case .surveyInvalid: return String(localized: "评价内容无效")
        case .tooManyRecurringSlots: return String(localized: "最多保存 \(TimeSlotConstants.maximumRecurringSlots) 个常用时间")
        case .matchingSuspended: return String(localized: "因多次爽约，快速匹配暂停中")
        case .venueNameInvalid: return String(localized: "球馆名称需为 2–60 个字符")
        case .venueAddressIncomplete: return String(localized: "请补全街道和城市，方便其他球友确认位置")
        case .venueNotFound: return String(localized: "没有找到这个球馆")
        case .ticketOverlap: return String(localized: "这个时间段你已经在找人了，可以先修改或取消那个请求")
        case .tooLateToRequest: return String(localized: "离开赛不到 30 分钟，来不及凑人了，换个时间试试")
        case .offerClosed: return String(localized: "这个匹配已经结束了")
        case .venueDuplicate(let name): return String(localized: "球馆库里已有“\(name)”，请直接选择它")
        case .venueRateLimited: return String(localized: "今天添加的球馆有点多，明天再来吧")
        case .notFriends: return String(localized: "加为球友后才能私信。可以先发好友申请，或在球局、球群里聊")
        case .newAccountMessageLimit: return String(localized: "打满 \(User.gamesBeforeMessageRequests) 场后才能给球群里的人发消息请求")
        case .messageRequestPending: return String(localized: "已发出消息请求，对方接受后才能继续聊")
        case .useGameChat: return String(localized: "你们在同一场球局里，请在球局群聊里沟通")
        case .requestContainsContact: return String(localized: "消息请求里不能留链接或站外联系方式（手机号、微信等），对方接受后再聊")
        case .chatClosed: return String(localized: "这个群聊已经结束了")
        case .challengeUnavailable(let reason): return reason
        case .challengeNotFound: return String(localized: "这个挑战已经结束了")
        case .resultWindowClosed: return String(localized: "赛后 7 天内才能提交赛果")
        case .profileContainsContact: return String(localized: "昵称和简介里不能留联系方式或链接")
        case .groupNotFound: return String(localized: "没有找到这个球群")
        case .notGroupMember: return String(localized: "加入球群后才能报名和聊天")
        case .groupNameInvalid: return String(localized: "球群名称需要 2–20 个字")
        case .groupScheduleInvalid: return String(localized: "固定场次需要 1–8 小时，名额 4–40 人")
        case .sessionClosed: return String(localized: "这一场已经结束或取消了")
        case .ownerCannotLeave: return String(localized: "群主不能直接退出，可以先把群交给其他组织者")
        case .assessmentTooSoon(let date): return String(localized: "每 90 天可以重测一次，下次：\(DateText.shortDay(date))")
        case .verificationInvalid(let reason): return reason
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

/// 球馆信息问题
enum VenueIssue: String, Codable, CaseIterable, Identifiable {
    case wrongLocation = "位置或地址不对"
    case closed = "已关门/不再开放"
    case duplicate = "和另一个球馆重复"
    case notBadminton = "不是羽毛球场地"
    case other = "其他"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongLocation: String(localized: "位置或地址不对")
        case .closed: String(localized: "已关门/不再开放")
        case .duplicate: String(localized: "和另一个球馆重复")
        case .notBadminton: String(localized: "不是羽毛球场地")
        case .other: String(localized: "其他")
        }
    }
}

struct VenueReport: Codable, Hashable {
    let venueId: String
    let reporterId: String
    let issue: VenueIssue
    let detail: String
    let createdAt: Date
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
    /// 结构变更时递增；版本不符的本地数据直接丢弃
    static let currentVersion = 10
    var version: Int = Database.currentVersion
    var currentUserId: String?
    /// 手机号 -> 用户 ID
    var accounts: [String: String] = [:]
    var users: [String: User] = [:]
    var bots: [String: BotProfile] = [:]
    var worldCenter: Coordinate = .fallbackCenter
    /// 平台球馆库：ID -> 球馆（收录 + 球友添加）
    var venues: [String: BadmintonCourt] = Dictionary(uniqueKeysWithValues: BadmintonCourt.curated.map { ($0.id, $0) })
    var venueReports: [VenueReport] = []
    /// 约球请求与匹配提议
    var tickets: [String: MatchTicket] = [:]
    var offers: [String: MatchOffer] = [:]
    /// 上次统一刷新对外口碑的月份（"2026-10"）
    var reputationPublishedMonth = ""
    /// 私下提醒记录：用户 ID → 问题 → 上次提醒时间（60 天内不重复提醒）
    var nudges: [String: [String: Date]] = [:]
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
    /// 球群与场次
    var groups: [String: PlayGroup] = [:]
    var groupSessions: [String: GroupSession] = [:]
    /// 高水平认证申请
    var verificationRequests: [VerificationRequest] = []
    /// 头像照片（JPEG）：用户 ID → 数据
    var avatarPhotos: [String: Data] = [:]
    /// 双方确认过的对局（真实球员；模拟球友之间的对局按日期即时生成，不存）
    var matchRecords: [MatchRecord] = []
    var challenges: [String: Challenge] = [:]
    /// 举报后对举报人隐藏的榜单条目：举报人 → 被隐藏的用户
    var hiddenFromBoards: [String: [String]] = [:]
    /// 用 Apple 地图核对位置没找到的开放数据场馆：ID → 上次尝试时间
    var locationChecks: [String: Date] = [:]
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
