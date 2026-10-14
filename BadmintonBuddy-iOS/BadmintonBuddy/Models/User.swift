import Foundation

// MARK: - 技能等级（9 级，每级再分 −/本级/+，共 27 档，见 SkillTier）
//
// 业内没有通用的业余等级标准（中国羽协等级“九级最低”、方向和我们相反；美国赛事 A–E 组没有书面定义）。
// 1–2 级看基本动作；3–6 级每一级多一个维度：3 技术会不会 → 4 技术好不好 → 5 稳不稳、会不会用战术 → 6 在俱乐部里的位置。
// 新用户回答问卷自动算出 1− 到 6+，球友评价最多推到 7−；7 起只凭能查到的证据认证：
// 7 州级（二级运动员），8 国家级，9 国际级（只认 BWF 世界排名和赛果，只有 BWF ID 不够）。依据见 docs/DESIGN.md §13。

enum SkillLevel {
    static let range = 1...9
    static let selfSelectableRange = 1...6
    /// 问卷能给到的最高级（俱乐部高手）
    static let maxSelfSelectable = 6

    static func name(for level: Int) -> String {
        switch level {
        case 1: return "萌新"
        case 2: return "入门"
        case 3: return "初级"
        case 4: return "中级"
        case 5: return "中高级"
        case 6: return "俱乐部高手"
        case 7: return "州级"
        case 8: return "国家级"
        case 9: return "国际级"
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
        case 3: return ["学技术的阶段：发球、正反手高远、吊、杀、搓放网、挑球、接杀逐项学会", "质量时好时坏，对拉十几拍就容易断", "双打知道攻前后、守左右"]
        case 4: return ["全部技术都打得不错（包括反手）：正手高远到后场、反手能回到对方中后场、吊球贴网、杀球有角度", "双打会攻守轮转", "稳定性还在提升"]
        case 5: return ["技术早已熟练，这一级比的是稳定：多拍相持很少主动失误", "双打会封网、补位，攻守转换流畅", "开始把战术和技巧结合起来"]
        case 6: return ["俱乐部里的佼佼者，日常局很少输", "杀、吊、网前、防守没有明显短板", "会用假动作和节奏变化组织进攻"]
        case 7: return ["州级水平：州 / 地区公开赛最高组能打进 8 强", "中国：二级运动员（省级比赛前八）", "需要上传证据审核"]
        case 8: return ["USAB 认证赛最高组正赛能赢球，或有全国排名", "或一级运动员、运动健将", "需要上传证据审核"]
        case 9: return ["bwfbadminton.com 能查到本人的世界排名或国际赛赢球记录", "只有 BWF ID 不够（老将赛也要 BWF ID）", "需要上传证据审核"]
        default: return []
        }
    }

    /// 大致对应的美国赛事组别（各赛事分组不同，仅供参考）
    static func usFlight(for level: Int) -> String? {
        switch level {
        case 3: return "E 组"
        case 4: return "D 组"
        case 5: return "C 组"
        case 6: return "B / A 组"
        case 7: return "州 / 地区公开赛最高组"
        case 8: return "Open 组 / 全国排名"
        case 9: return "BWF 国际赛"
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
        case 7: return "体校 / 青训出身"
        case 8: return "体校 / 省队出身"
        default: return "职业 / 国家队背景"
        }
    }

    /// 每一档的具体标准。1–2 级看基本动作；3–6 级按“会不会 → 好不好 → 稳不稳 → 战术 → 俱乐部里的位置”；7 起看证据
    static func tierCriteria(for tier: SkillTier) -> [String] {
        switch (tier.level, tier.modifier) {
        case (1, .minus): return ["正手发球 10 个里 ≤3 个进区"]
        case (1, .base): return ["正手发球 10 个里 4–6 个进区"]
        case (1, .plus): return ["正手发球 ≥7 个进区，慢速对拉 ≥5 拍"]
        case (2, .minus): return ["中后场正手高远 10 个里 1–2 个过后场第一条线"]
        case (2, .base): return ["高远 10 个里 3–4 个到后场，慢速对拉 5–10 拍"]
        case (2, .plus): return ["高远 10 个里 ≥5 个到后场"]
        case (3, .minus): return ["主要技术学了大半，还有几项不会（比如反手、杀球）"]
        case (3, .base): return ["全部技术都会做，但质量一般、时好时坏"]
        case (3, .plus): return ["全部技术都会，一两项打得不错，但稳定性不足"]
        case (4, .minus): return ["全部技术都还行，能连续对拉十几拍，实战里失误还多"]
        case (4, .base): return ["全部技术都不错（包括反手能回到对方中后场）；双打会轮转"]
        case (4, .plus): return ["全部技术都不错，一两项精通（是得分手段），稳定性略有提升"]
        case (5, .minus): return ["稳定性明显提高：实战里很少送分，但高强度下还会乱"]
        case (5, .base): return ["技术全面且稳定，多拍相持很少主动失误"]
        case (5, .plus): return ["战术和技巧开始结合：用落点、节奏、假动作组织进攻，会随对手调整"]
        case (6, .minus): return ["和俱乐部里最强的几个人互有胜负"]
        case (6, .base): return ["俱乐部里的佼佼者：日常局很少输"]
        case (6, .plus): return ["俱乐部里基本没对手，常打比赛最高组"]
        case (7, .minus): return ["州 / 地区赛次高组冠军，或最高组正赛赢过 1 场", "或三级运动员（2025 新标准）、旧二级"]
        case (7, .base): return ["州 / 地区公开赛最高组（Open / A）8 强", "或二级运动员（2025 新标准）"]
        case (7, .plus): return ["州 / 地区公开赛最高组 4 强或冠军"]
        case (8, .minus): return ["USAB 认证赛最高组（Open）正赛赢过 1 场，进入 USAB 排名表", "或 2025 年前的一级证书"]
        case (8, .base): return ["USAB 全国排名有正式名次，或认证赛最高组 8 强", "或一级运动员"]
        case (8, .plus): return ["USAB 任一项目前 5，或全国成年锦标赛 4 强", "或运动健将"]
        case (9, .minus): return ["BWF 世界排名任一项目前 500", "或单站 ≥1,370 积分：International Series 8 强，或 IC / Super 100 正赛赢 1 场"]
        case (9, .base): return ["BWF 世界排名前 100", "或 Super 300 及以上赛事正赛赢过 1 场"]
        case (9, .plus): return ["BWF 世界排名前 20", "或奥运会 / 世锦赛 8 强、Super 750 及以上 4 强"]
        default: return [tier.modifier.meaning]
        }
    }

    /// 每类证据能认证的范围（认证页用）
    static func evidenceSummary(for kind: VerificationStatus) -> String {
        switch kind {
        case .unverified: return ""
        case .tournament: return "tournamentsoftware.com 上公开的签表和成绩（签位 ≥8，7 起 ≥16）：次高组冠军或最高组正赛赢球 → 7−，州 / 地区公开赛最高组 8 强 → 7，4 强 → 7+，USAB 认证赛最高组正赛赢球 → 8−，8 强 → 8"
        case .national: return "USAB 全国排名，或运动员技术等级电子证书：三级 → 7−，二级 → 7，一级 → 8，运动健将 → 8+（2025 年前的证书低一档）"
        case .bwf: return "bwfbadminton.com 上本人的球员页，看近 24 个月的世界排名和赛果。只有 BWF ID 不够"
        }
    }

    static func displayText(for level: Int) -> String {
        "Lv.\(level) \(name(for: level))"
    }

    static func clamp(_ level: Int) -> Int {
        min(max(level, range.lowerBound), range.upperBound)
    }
}

// MARK: - 高水平认证

/// 7+ 起的档位只凭能查到的证据认证（赛果、全国排名、BWF 球员资料），问卷和球友评价都到不了。
/// rawValue 沿用旧值，老数据可以直接解码。
enum VerificationStatus: String, Codable, Hashable, CaseIterable, Identifiable {
    case unverified
    /// 赛事成绩：tournamentsoftware.com 上公开的签表和成绩
    case tournament = "regionalChampion"
    /// 全国排名（USAB）或运动员技术等级证书
    case national = "nationalChampion"
    /// BWF 世界排名 / 国际赛赛果（bwfbadminton.com 球员页）
    case bwf = "bwfPlayer"

    var id: String { rawValue }

    /// 没有认证时最高显示的档位：问卷最高 6+，球友评价最多推到 7−
    static let unverifiedMaxTier = SkillTier(level: 7, modifier: .minus)

    /// 这类证据最多能认证到哪一档
    var maxTier: SkillTier {
        switch self {
        case .unverified: return Self.unverifiedMaxTier
        case .tournament: return SkillTier(level: 8)
        case .national: return SkillTier(level: 8, modifier: .plus)
        case .bwf: return SkillTier(level: 9, modifier: .plus)
        }
    }

    /// 这类证据最低从哪一档起认证
    var minTier: SkillTier {
        switch self {
        case .unverified: return SkillTier(level: 1, modifier: .minus)
        case .tournament, .national: return SkillTier(level: 7, modifier: .minus)
        case .bwf: return SkillTier(level: 9, modifier: .minus)
        }
    }

    var maxRating: Double { maxTier.rating }

    var title: String {
        switch self {
        case .unverified: return "未认证"
        case .tournament: return "赛事成绩"
        case .national: return "全国排名 / 运动员等级证书"
        case .bwf: return "BWF 世界排名"
        }
    }

    var badgeText: String? {
        switch self {
        case .unverified: return nil
        case .tournament: return "赛果认证"
        case .national: return "等级认证"
        case .bwf: return "BWF 认证"
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
    /// 问卷给出的细分分值（4+ = 4.33）；老数据为空时用整数等级
    var selfReportedRating: Double?
    /// 认证通过的档位分值（7+ 起）；认证后它代替问卷分值，也是显示的上限
    var verifiedRating: Double?

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
        // 问卷顶到 6+：要靠球友评价确认，同样加快校准
        let atQuestionnaireCap = verifiedRating == nil && selfRating >= SkillAssessment.maxTier.rating - 0.01
        let calibrating = assessment?.needsCalibration == true || assessment?.isReturning == true || atQuestionnaireCap
        return calibrating ? User.calibratingPeerWeight : User.peerEvaluationWeight
    }

    /// 问卷给出的分值（细分档位）
    var selfRating: Double { selfReportedRating ?? Double(selfReportedLevel) }

    /// 计算的起点：认证过用认证档位，否则用问卷分值
    var baseRating: Double { verifiedRating ?? selfRating }

    /// 综合分值：评价满 5 次后 = 30% 问卷（或认证）+ 70% 球友评价（待校准 / 回归球友为 15% + 85%）；否则为起点分值
    var calculatedLevel: Double {
        guard !reputation.isNewPlayer else { return baseRating }
        return (1 - peerWeight) * baseRating + peerWeight * reputation.peerLevelAverage
    }

    /// 显示的上限：没认证最高 7−；认证后最高就是认证的那一档
    var tierCap: SkillTier {
        if let verifiedRating { return SkillTier(rating: verifiedRating) }
        return VerificationStatus.unverifiedMaxTier
    }

    /// 显示的细分档位：认证过的人，球友评价最多往下拉 1 档（伤病、状态下滑），不会被一两场打低
    var displayTier: SkillTier {
        let tier = min(SkillTier(rating: calculatedLevel), tierCap)
        guard verifiedRating != nil else { return tier }
        return max(tier, tierCap.offset(by: -1))
    }

    /// 认证通过：记录证据类型和档位（档位限制在这类证据的范围内）
    mutating func applyVerification(_ status: VerificationStatus, tier: SkillTier) {
        guard status != .unverified else {
            verificationStatus = .unverified
            verifiedRating = nil
            return
        }
        verificationStatus = status
        verifiedRating = min(max(tier, status.minTier), status.maxTier).rating
    }

    /// 显示等级（整数，用于匹配的水平差）
    var displayLevel: Int { displayTier.level }

    /// “Lv.4+ 中级”
    var displayLevelText: String { displayTier.displayText }

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
