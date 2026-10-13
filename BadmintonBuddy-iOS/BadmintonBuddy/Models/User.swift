import Foundation

// MARK: - 技能等级（9 级）

/// 9 级技能体系：1-7 级可自评，8-9 级需要赛事认证
enum SkillLevel {
    static let range = 1...9
    static let selfSelectableRange = 1...7
    static let maxSelfSelectable = 7

    static func name(for level: Int) -> String {
        switch level {
        case 1: return "入门"
        case 2: return "初学"
        case 3: return "业余"
        case 4: return "进阶"
        case 5: return "中级"
        case 6: return "高级"
        case 7: return "专业"
        case 8: return "地区冠军"
        case 9: return "全国冠军"
        default: return "业余"
        }
    }

    /// 可观察的行为描述，帮助用户如实自评（减少“水平虚报”）
    static func descriptor(for level: Int) -> String {
        switch level {
        case 1: return "刚接触羽毛球，能把球打过网"
        case 2: return "能和球友连续对拉高远球 5 拍以上"
        case 3: return "会高远、吊球、搓球，步法初步成型"
        case 4: return "能稳定打到底线，开始有杀球和网前意识"
        case 5: return "技术较全面，双打轮转熟练，常打业余赛"
        case 6: return "杀球有威胁，业余比赛常进前八"
        case 7: return "校队或业余顶尖水平，受过系统训练"
        case 8: return "省市级比赛冠军，需上传证明审核"
        case 9: return "全国级比赛冠军，需上传证明审核"
        default: return ""
        }
    }

    static func displayText(for level: Int) -> String {
        "Lv.\(level) \(name(for: level))"
    }

    static func clamp(_ level: Int) -> Int {
        min(max(level, range.lowerBound), range.upperBound)
    }
}

// MARK: - 验证状态

/// 8-9 级需要的赛事认证状态
enum VerificationStatus: String, Codable, Hashable {
    case unverified
    case regionalChampion
    case nationalChampion

    var maxLevel: Int {
        switch self {
        case .unverified: return SkillLevel.maxSelfSelectable
        case .regionalChampion: return 8
        case .nationalChampion: return 9
        }
    }

    var badgeText: String? {
        switch self {
        case .unverified: return nil
        case .regionalChampion: return "地区冠军认证"
        case .nationalChampion: return "全国冠军认证"
        }
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable, Hashable {
    case unspecified, male, female

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: return "不透露"
        case .male: return "男"
        case .female: return "女"
        }
    }
}

/// 头像：图片（仅本人，本地存储）或“首字/表情 + 马卡龙底色”
struct Avatar: Codable, Hashable {
    /// 表情或单字；为空时使用昵称首字
    var symbol: String
    var paletteIndex: Int

    static func `default`(for seed: String) -> Avatar {
        Avatar(symbol: "", paletteIndex: abs(seed.stableHash) % 6)
    }
}

// MARK: - 用户

struct User: Identifiable, Codable, Hashable {
    let id: String
    var nickname: String
    var phone: String
    var gender: Gender
    var bio: String
    var avatar: Avatar
    /// 自评等级 (1-9)
    var selfReportedLevel: Int
    var totalGames: Int
    var wins: Int
    var joinDate: Date
    var location: Coordinate?
    var lastActiveAt: Date
    var verificationStatus: VerificationStatus
    var reputation: ReputationScore
    /// 客观履约记录（签到/爽约/临时取消）
    var attendance: AttendanceRecord
    var preferredMode: GameMode?

    init(
        id: String,
        nickname: String,
        phone: String,
        gender: Gender = .unspecified,
        bio: String = "",
        avatar: Avatar? = nil,
        selfReportedLevel: Int,
        totalGames: Int = 0,
        wins: Int = 0,
        joinDate: Date = Date(),
        location: Coordinate? = nil,
        lastActiveAt: Date = Date(),
        verificationStatus: VerificationStatus = .unverified,
        reputation: ReputationScore = .empty,
        attendance: AttendanceRecord = .empty,
        preferredMode: GameMode? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.phone = phone
        self.gender = gender
        self.bio = bio
        self.avatar = avatar ?? .default(for: id)
        self.selfReportedLevel = SkillLevel.clamp(selfReportedLevel)
        self.totalGames = totalGames
        self.wins = wins
        self.joinDate = joinDate
        self.location = location
        self.lastActiveAt = lastActiveAt
        self.verificationStatus = verificationStatus
        self.reputation = reputation
        self.attendance = attendance
        self.preferredMode = preferredMode
    }

    // MARK: 等级计算

    static let selfReportedWeight = 0.3
    static let peerEvaluationWeight = 0.7
    static let minimumEvaluationsForWeightedLevel = ReputationScore.newPlayerThreshold

    /// 综合等级：评价满 5 次后 = 30% 自评 + 70% 球友评价；否则为自评等级
    var calculatedLevel: Double {
        guard !reputation.isNewPlayer else { return Double(selfReportedLevel) }
        return User.selfReportedWeight * Double(selfReportedLevel) +
            User.peerEvaluationWeight * reputation.peerLevelAverage
    }

    /// 显示等级（整数），未认证用户最高显示 7 级
    var displayLevel: Int {
        let rounded = Int(calculatedLevel.rounded())
        return min(SkillLevel.clamp(rounded), max(verificationStatus.maxLevel, selfReportedLevel))
    }

    var displayLevelText: String { SkillLevel.displayText(for: displayLevel) }

    var isNewPlayer: Bool { reputation.isNewPlayer }

    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames) * 100
    }

    var maskedPhone: String {
        guard phone.count == 11 else { return phone }
        return String(phone.prefix(3)) + "****" + String(phone.suffix(4))
    }

    /// 头像显示文字
    var avatarText: String {
        if !avatar.symbol.isEmpty { return avatar.symbol }
        return nickname.first.map { String($0) } ?? "🏸"
    }

    /// 短 ID（展示用）
    var shortId: String {
        String(abs(id.stableHash) % 9000 + 1000)
    }
}

// MARK: - 稳定哈希（跨启动一致，用于取色等）

extension String {
    var stableHash: Int {
        var hash: UInt64 = 5381
        for byte in utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
}
