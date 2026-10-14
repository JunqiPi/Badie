import Foundation

// MARK: - 技能等级（9 级）
//
// 业内没有通用的业余等级标准（中国羽协等级“九级最低”、方向和我们相反；美国赛事 A–E 组没有书面定义）。
// 我们用“可观察的动作”定义每一级（参考打球吧“业余 1–9 级”的可数测试、中羽在线 0–9 级、USTA NTRP 的写法），
// 新用户回答问卷自动算出 1–7 级；8–9 级只凭赛果认证。依据见 docs/DESIGN.md §13。

enum SkillLevel {
    static let range = 1...9
    static let selfSelectableRange = 1...7
    static let maxSelfSelectable = 7

    static func name(for level: Int) -> String {
        switch level {
        case 1: return "萌新"
        case 2: return "入门"
        case 3: return "初级"
        case 4: return "中级"
        case 5: return "中高级"
        case 6: return "高级"
        case 7: return "业余高手"
        case 8: return "地区精英"
        case 9: return "竞技精英"
        default: return "初级"
        }
    }

    /// 一句话概括（列表、徽章说明）
    static func descriptor(for level: Int) -> String {
        anchors(for: level).first ?? ""
    }

    /// 可观察的行为锚点：对照这些动作判断自己在哪一级
    static func anchors(for level: Int) -> [String] {
        switch level {
        case 1: return ["对拉不到 5 拍", "高远球到不了中场"]
        case 2: return ["发球基本能进区", "慢速对拉 5–10 拍", "走着够球，还没有步法"]
        case 3: return ["正手高远 10 个里 3–6 个到后场", "会挑球、放网", "反手只能挡过网"]
        case 4: return ["正手高远 10 个里至少 7 个到后场", "会吊球，杀球有角度，打完能回中", "双打会攻守轮转"]
        case 5: return ["反手不被动时能回到对方中后场", "能连续杀球并跟进网前", "双打会封网、补位"]
        case 6: return ["杀球或吊球上网 5 个回合至少 4 次无失误", "接重杀能抽挡变线", "会用假动作"]
        case 7: return ["反手高远能从底线打到底线", "会起跳杀球", "高强度多拍下步法不乱"]
        case 8: return ["A 组比赛进前四，或在 Open 组赢过正赛", "需要上传赛果审核"]
        case 9: return ["Open 组获奖牌、有 USAB / BWF 排名，或前专业球员", "需要上传证明审核"]
        default: return []
        }
    }

    /// 大致对应的美国赛事组别（各赛事分组不同，仅供参考）
    static func usFlight(for level: Int) -> String? {
        switch level {
        case 3: return "E 组"
        case 4: return "D 组"
        case 5: return "C 组"
        case 6: return "B 组"
        case 7: return "B+ / A− 组"
        case 8: return "A 组"
        case 9: return "Open 组"
        default: return nil
        }
    }

    /// 球龄（弱参考：练得多的人进步快，不能只看年限）
    static func typicalExperience(for level: Int) -> String {
        switch level {
        case 1: return "通常不到 3 个月"
        case 2: return "通常不到 1 年"
        case 3: return "通常 1–2 年"
        case 4: return "通常 2–4 年"
        case 5: return "通常 3–6 年"
        case 6: return "通常 5 年以上且受过训练"
        case 7: return "多有青训背景"
        case 8: return "体校 / 青训出身"
        default: return "专业背景"
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
        case .regionalChampion: return "地区精英认证"
        case .nationalChampion: return "竞技精英认证"
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

// MARK: - 隐私设置

struct PrivacySettings: Codable, Hashable {
    /// 在常去球馆的“同馆常客”里显示我（默认关闭）
    var showsAsRegular = false
    /// 允许同球群的球友给我发消息请求（默认开启；关闭后只有好友能私信）
    var allowsMessageRequests = true
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
    /// 隐私设置（别人能看到 / 能联系到我的方式）
    var privacy = PrivacySettings()
    /// 定级问卷结果（老数据可能没有）
    var assessment: SkillAssessmentSummary?

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

    /// 待校准（经历和技术对不上）或回归球友：球友评价占 85%，更快校准到真实水平
    static let calibratingPeerWeight = 0.85

    /// 球友评价占的权重
    var peerWeight: Double {
        let calibrating = assessment?.needsCalibration == true || assessment?.isReturning == true
        return calibrating ? User.calibratingPeerWeight : User.peerEvaluationWeight
    }

    /// 综合等级：评价满 5 次后 = 30% 自评 + 70% 球友评价（待校准 / 回归球友为 15% + 85%）；否则为自评等级
    var calculatedLevel: Double {
        guard !reputation.isNewPlayer else { return Double(selfReportedLevel) }
        return (1 - peerWeight) * Double(selfReportedLevel) + peerWeight * reputation.peerLevelAverage
    }

    /// 显示等级（整数），未认证用户最高显示 7 级
    var displayLevel: Int {
        let rounded = Int(calculatedLevel.rounded())
        return min(SkillLevel.clamp(rounded), max(verificationStatus.maxLevel, selfReportedLevel))
    }

    var displayLevelText: String { SkillLevel.displayText(for: displayLevel) }

    var isNewPlayer: Bool { reputation.isNewPlayer }

    /// 打满几场才能给同球群的人发消息请求（防小号骚扰）
    static let gamesBeforeMessageRequests = 3

    /// “靠谱”徽章：打满 3 场、没有爽约、临时取消不超过 1 次（只看客观履约记录）
    var isReliable: Bool {
        attendance.gamesPlayed >= 3 && attendance.noShows == 0 && attendance.lateCancellations <= 1
    }

    /// 对别人显示的场次：分档（"20+ 场"），不给精确数字
    var gamesBand: String {
        switch totalGames {
        case 0: return "还没打过"
        case 1..<5: return "1–4 场"
        case 5..<20: return "5+ 场"
        case 20..<50: return "20+ 场"
        default: return "50+ 场"
        }
    }

    /// 列表里对别人展示的一句话：只有正面信息，没有分数（"靠谱 · 20+ 场"）
    var publicSummary: String {
        var parts: [String] = []
        if isNewPlayer { parts.append("新球友") } else if isReliable { parts.append("靠谱") }
        parts.append(gamesBand)
        if let tag = reputation.publicTags.first { parts.append(tag.rawValue) }
        return parts.joined(separator: " · ")
    }

    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames) * 100
    }

    var maskedPhone: String {
        PhoneNumber.parse(phone)?.masked ?? phone
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
