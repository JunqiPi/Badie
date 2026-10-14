import Foundation

// MARK: - 技能等级（9 级，每级再分 −/本级/+，共 27 档，见 SkillTier）
//
// 1–2 级看基本动作；3 技术会不会 → 4 主动球好不好 → 5 被动球能否摆脱 → 6 俱乐部里的位置。
// 问卷最高 6+，球友评价最多推到 7−；7 州级、8 国家级、9 国际级只凭证据认证。见 docs/DESIGN.md §13。

enum SkillLevel {
    static let range = 1...9
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
        case 4: return ["主动球（舒服位置）全部打得不错，包括反手不被动时能回到对方中后场", "双打会攻守轮转", "但被动球、极限球基本做不到，一被压就丢分"]
        case 5: return ["被动球、极限球有机会摆脱：被压到底线、调到死角也能过渡出来", "技术特点开始明显：有自己的得分手段和打法", "战术开始明显，会用落点和节奏调动对手"]
        case 6: return ["俱乐部里的佼佼者，日常局很少输", "杀、吊、网前、防守没有明显短板", "会用假动作和节奏变化组织进攻"]
        case 7: return ["州级水平：州 / 地区公开赛最高组能打进 8 强", "中国：二级运动员（省级比赛前八）", "需要上传证据审核"]
        case 8: return ["USAB 认证赛最高组正赛能赢球，或有全国排名", "或一级运动员、运动健将", "需要上传证据审核"]
        case 9: return ["bwfbadminton.com 能查到本人的世界排名或国际赛赢球记录", "只有 BWF ID 不够（老将赛也要 BWF ID）", "需要上传证据审核"]
        default: return []
        }
    }

    /// 每级各技术分项的标准
    static func dimensionNotes(for level: Int) -> [(name: String, text: String)] {
        switch level {
        case 1: return [("握拍", "苍蝇拍式握法"), ("意识", "知道要把球打到对方难接的地方，但多数时候还做不到")]
        case 2: return [("握拍", "正反手握拍基本正确，但转换不顺"),
                        ("发球", "会发正手高远和反手网前，质量不高"),
                        ("网前", "基本是轻放过去，时高时远，常不过网"),
                        ("正手后场", "挥拍对了，但发力、时机、击球点还不对，多靠挥手臂"),
                        ("反手后场", "基本不会，只能绕头打或者放弃"),
                        ("进攻", "杀球多半下网、出界")]
        case 3: return [("握拍、发球", "基本没问题"),
                        ("步法", "能区分垫步、跨步，全场六个点能走到但不流畅"),
                        ("发力", "能区分手臂和手腕发力，对内旋、外旋有基本概念"),
                        ("正手后场", "高远能底线到底线但球速慢；吊、杀质量有限"),
                        ("反手后场", "能正确挥拍但常出错，回球只到中场或略偏后"),
                        ("网前", "放网基本能控制，搓球、勾对角刚开始用，失误多")]
        case 4: return [("步法", "全场步法正确并能用在打球中，但启动和移动速度不够"),
                        ("发力", "能用上手腕和内外旋，但力量有限"),
                        ("正手后场", "拉、吊、杀都能轻松完成，球速一般，落点凭感觉"),
                        ("反手后场", "能回到对方中后场，但不能底线到底线；反手吊不稳"),
                        ("网前", "挑球能到底线，正反手搓球正确，勾对角常用但质量一般"),
                        ("进攻", "能组织进攻，但速度和角度一般，很难一拍致命"),
                        ("防守", "只能挡直线网前或挑高，不能变线（被动球做不到）"),
                        ("双打", "发接发、移动补位、封网有基本意识")]
        case 5: return [("步法", "全场多点步法轻松，启动和移动速度中上"),
                        ("发力", "前臂内外旋和手腕发力熟练，开始体会手指发力"),
                        ("后场", "平高、高远、各种吊杀熟练，落点基本到位；反手直线斜线吊都会，后场回后场轻松"),
                        ("网前", "挑、搓熟练，开始会展搓和推球"),
                        ("中场", "平抽挡比较好"),
                        ("进攻", "直线、斜线进攻规范，力量速度中上，有一定威胁"),
                        ("防守", "防守熟练，回球基本到位（被动球多数能摆脱）")]
        case 6: return [("步法", "像本能一样自然，全场没有盲点"),
                        ("发力", "手指发力熟练：网前精细控制、杀球额外爆发都靠它"),
                        ("动作一致性", "拉吊杀动作一致，对手很难提前判断"),
                        ("反手", "底线到底线轻松，反手劈吊熟练，机会好时反手杀有威力"),
                        ("网前", "搓、勾、推、扑都熟练并用在实战里"),
                        ("中后场", "快速平抽挡；被动低位也能把球抽到底线"),
                        ("进攻", "杀球有暴击音，按对方站位用重杀、劈杀、点杀"),
                        ("防守", "防住不是绝对机会的杀球并控制落点，对方杀得一般时能反抽"),
                        ("战术", "单打主动控制、找弱点；双打抢网、保持主动，找配合盲区")]
        case 7: return [("技术", "没有明显缺陷，而且至少有一两项绝活：杀球凌厉、防守杀不死、假动作逼真或网前炉火纯青"),
                        ("战术", "单双打战术熟练，但限制与反限制的对抗中，关键时刻还不够冷静"),
                        ("稳定性", "在业余里很高，和专业选手比失误还多"),
                        ("自测参考", "和全国性业余赛的冠军对打，21 分制输分不超过 10 分")]
        case 8: return [("技术", "任何单项技术都不是问题"),
                        ("战术", "所有战术都能熟练运用，遇到战术大师时应变还不够"),
                        ("稳定性", "业余球友看来稳得可怕，和顶尖高手只差毫厘"),
                        ("背景", "多为前省队、在全国比赛有成绩")]
        case 9: return [("背景", "国际赛选手、前国家队"),
                        ("技战术", "和更顶尖选手的差距主要在体能和手感")]
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

    /// 每一档的具体标准
    static func tierCriteria(for tier: SkillTier) -> [String] {
        switch (tier.level, tier.modifier) {
        case (1, .minus): return ["正手发球 10 个里 ≤3 个进区"]
        case (1, .base): return ["正手发球 10 个里 4–6 个进区"]
        case (1, .plus): return ["正手发球 ≥7 个进区，慢速对拉 ≥5 拍"]
        case (2, .minus): return ["中后场正手高远 10 个里 1–2 个过后场第一条线"]
        case (2, .base): return ["高远 10 个里 3–4 个到后场，慢速对拉 5–10 拍"]
        case (2, .plus): return ["高远 10 个里 ≥5 个到后场"]
        case (3, .minus): return ["技术学了大半，还有一两项不会（常见是反手、发力）"]
        case (3, .base): return ["全部技术都会做（所有分项到 3 级），但质量一般、时好时坏"]
        case (3, .plus): return ["全部技术都会，一两项打得不错（到 4 级），但稳定性不足"]
        case (4, .minus): return ["多数分项到 4 级，个别还在 3 级；实战失误还多"]
        case (4, .base): return ["主动球全部不错（所有分项到 4 级，包括反手），双打有基本意识；但被动球、极限球做不到"]
        case (4, .plus): return ["主动球全部不错，一两项精通（到 5 级），稳定性略有提升；被动球仍是短板"]
        case (5, .minus): return ["被动球、极限球有时能过渡出来：回到对方后场或网前，让自己回位"]
        case (5, .base): return ["被动球多数能摆脱；技术特点和战术开始明显（有自己的得分手段，会用落点和节奏调动对手）"]
        case (5, .plus): return ["战术和技巧明显结合：用落点、节奏、假动作组织进攻，会随对手调整"]
        case (6, .minus): return ["和俱乐部里最强的几个人互有胜负；多数分项到 5 级，多拍很稳"]
        case (6, .base): return ["俱乐部准霸主：日常局很少输，常有人请教；有一两项到 6 级的绝活"]
        case (6, .plus): return ["俱乐部霸主：俱乐部对抗的主力，开始打业余 / 半专业比赛"]
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

/// 7 级起只凭能查到的证据认证，问卷和球友评价都到不了。
/// rawValue 与 case 名不同，已存数据按 rawValue 解码，不能改。
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
    /// 上传过照片时的版本号（每次重新上传 +1，用于刷新缓存）；为空表示没有照片
    var photoVersion: Int?

    static func `default`(for seed: String) -> Avatar {
        Avatar(symbol: "", paletteIndex: abs(seed.stableHash) % 6)
    }

    func text(nickname: String) -> String {
        symbol.isEmpty ? (nickname.first.map { String($0) } ?? "🏸") : symbol
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
    var privacy = PrivacySettings()
    /// 定级问卷结果；跳过定级时为空
    var assessment: SkillAssessmentSummary?
    /// 问卷给出的细分分值（4+ = 4.33）；为空时按整数等级
    var selfReportedRating: Double?
    /// 认证通过的档位分值（7+ 起）；认证后它代替问卷分值，也是显示的上限
    var verifiedRating: Double?
    /// 注册时跳过了定级问卷（暂按 Lv.3 匹配，之后在资料页补测）
    var assessmentSkippedAt: Date?

    /// 跳过了定级、还没补测
    var needsAssessment: Bool { assessment == nil && assessmentSkippedAt != nil }

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

    static let peerEvaluationWeight = 0.7

    /// 待校准（经历和技术对不上）或回归球友：球友评价占 85%，更快校准到真实水平
    static let calibratingPeerWeight = 0.85

    /// 球友评价占的权重
    var peerWeight: Double {
        // 问卷顶到 6+：要靠球友评价确认，同样加快校准
        let atQuestionnaireCap = verifiedRating == nil && selfRating >= SkillAssessment.maxTier.rating - 0.01
        let calibrating = assessment?.needsCalibration == true || assessment?.isReturning == true || atQuestionnaireCap
            || needsAssessment
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

    var avatarText: String { avatar.text(nickname: nickname) }

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
