import Foundation

// MARK: - 房间 / 球局招募

/// 球局氛围标签
enum RoomTag: String, CaseIterable, Identifiable, Codable, Hashable {
    case beginnerFriendly = "新手友好"
    case casual = "欢乐局"
    case competitive = "竞技局"
    case womenFriendly = "女生友好"
    case coaching = "可指导"

    var id: String { rawValue }

    /// 显示文字（rawValue 已持久化，不能改；显示走这里以便本地化）
    var title: String {
        switch self {
        case .beginnerFriendly: return String(localized: "新手友好")
        case .casual: return String(localized: "欢乐局")
        case .competitive: return String(localized: "竞技局")
        case .womenFriendly: return String(localized: "女生友好")
        case .coaching: return String(localized: "可指导")
        }
    }

    var icon: String {
        switch self {
        case .beginnerFriendly: return "leaf.fill"
        case .casual: return "face.smiling.inverse"
        case .competitive: return "flame.fill"
        case .womenFriendly: return "heart.fill"
        case .coaching: return "graduationcap.fill"
        }
    }
}

enum RoomVisibility: String, Codable, Hashable {
    /// 仅凭房间码 / 好友邀请加入
    case privateRoom
    /// 公开到“附近球局”，任何符合水平的人可加入
    case publicListing
}

enum RoomCloseReason: String, Codable, Hashable {
    case expired
    case ownerClosed
    case startTimePassed

    var message: String {
        switch self {
        case .expired: return String(localized: "房间 30 分钟无活动，已自动关闭")
        case .ownerClosed: return String(localized: "房主已解散房间")
        case .startTimePassed: return String(localized: "已过开始时间，房间已关闭")
        }
    }
}

enum RoomStatus: Codable, Hashable {
    case open
    case started(gameId: String)
    case closed(RoomCloseReason)

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}

struct RoomParticipant: Identifiable, Codable, Hashable {
    var id: String { userId }
    let userId: String
    var nickname: String
    var skillLevel: Int
    /// 加入时的细分档位分值；为空时按整数等级
    var skillRating: Double?
    var avatar: Avatar
    let joinedAt: Date

    init(user: User, joinedAt: Date = Date()) {
        self.userId = user.id
        self.nickname = user.nickname
        self.skillLevel = user.displayLevel
        self.skillRating = user.displayTier.rating
        self.avatar = user.avatar
        self.joinedAt = joinedAt
    }

    var tier: SkillTier { SkillTier(rating: skillRating ?? Double(skillLevel)) }

    var avatarText: String { avatar.text(nickname: nickname) }
}

struct Room: Identifiable, Codable, Hashable {
    let id: String
    let code: String
    var ownerId: String
    var mode: GameMode
    var visibility: RoomVisibility
    var participants: [RoomParticipant]
    /// 已邀请但尚未加入的用户
    var invitedUserIds: [String]
    /// 候补名单（公开局满员后排队，有人退出自动递补）
    var waitlist: [RoomParticipant]
    var court: BadmintonCourt?
    var slot: TimeSlot?
    var levelRange: ClosedRange<Int>
    var tags: [RoomTag]
    var note: String
    let createdAt: Date
    var lastActivityAt: Date
    var status: RoomStatus
    /// 只限女生 / 男生；nil = 不限
    var audience: Gender? = nil

    static let expirationDuration: TimeInterval = 30 * 60
    static let codeLength = 6
    /// 去掉易混淆字符 0 O 1 I L
    static let codeCharacters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let maxWaitlist = 4

    var requiredPlayerCount: Int { mode.requiredPlayers }
    var isFull: Bool { participants.count >= requiredPlayerCount }
    var isReady: Bool { participants.count == requiredPlayerCount }
    var openSeats: Int { max(0, requiredPlayerCount - participants.count) }

    /// 和服务器一致：定了时间的到开始时间还没开局就关闭；没定时间的 30 分钟没有动静就关闭
    func isExpired(now: Date = Date()) -> Bool { now >= expiresAt() }

    func expiresAt() -> Date {
        slot?.startTime ?? lastActivityAt.addingTimeInterval(Self.expirationDuration)
    }

    func contains(_ userId: String) -> Bool {
        participants.contains { $0.userId == userId }
    }

    func isWaitlisted(_ userId: String) -> Bool {
        waitlist.contains { $0.userId == userId }
    }

    func accepts(level: Int) -> Bool { levelRange.contains(level) }

    var levelRangeText: String {
        if levelRange.lowerBound <= 1 && levelRange.upperBound >= 9 { return String(localized: "不限水平") }
        if levelRange.lowerBound == levelRange.upperBound { return "Lv.\(levelRange.lowerBound)" }
        return "Lv.\(levelRange.lowerBound)–\(levelRange.upperBound)"
    }

    var costEstimate: CostSplit? {
        guard let court, let slot else { return nil }
        return CostSplit.estimate(court: court, slot: slot, mode: mode)
    }

    static func generateCode(excluding existing: Set<String> = []) -> String {
        var code: String
        repeat {
            code = String((0..<codeLength).map { _ in codeCharacters.randomElement()! })
        } while existing.contains(code)
        return code
    }

    /// 校验房间码格式（6 位、仅含合法字符）
    static func isValidCode(_ code: String) -> Bool {
        let upper = code.uppercased()
        return upper.count == codeLength && upper.allSatisfy { codeCharacters.contains($0) }
    }

    /// 规范化用户输入：转大写、去掉空格与连字符、最多 6 位
    static func normalize(_ input: String) -> String {
        let cleaned = input.uppercased().filter { $0 != " " && $0 != "-" }
        return String(cleaned.prefix(codeLength))
    }

    var inviteText: String {
        var text = String(localized: "来 Badie 一起打\(mode.title)！房间码：\(code)")
        if let slot { text += "\n🕖 \(slot.formattedFull)" }
        if let court { text += "\n📍 \(court.name)" }
        return text
    }
}
