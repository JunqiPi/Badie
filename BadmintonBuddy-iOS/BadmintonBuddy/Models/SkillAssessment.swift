import Foundation

// MARK: - 定级问卷：技术分项 + 台阶，自动算出 1− 到 6+
//
// 两层结合：
// 1. 技术分项（参考中羽在线论坛流传的 1–9 级分项描述）：正手后场、反手后场、网前、步法、发力、进攻，
//    每题的选项就是该分项在某一级的样子（比如发力：挥大臂 → 手腕 → 前臂内外旋 → 手指）。
// 2. 我们的台阶：
//    3：技术会不会（3 = 所有分项到 3 级；3+ = 再有一两项到 4 级，但稳定性不足）
//    4：主动球好不好（4 = 所有分项到 4 级，但被动球、极限球做不到；4+ = 一两项到 5 级（精通），稳定性略有提升）
//    5：被动球能不能摆脱（5− 有时能过渡；5 多数能摆脱，并会用落点和节奏；5+ 战术和技巧明显结合）
//    6：在俱乐部里的位置 + 6 级技术（6− 崭露头角且多数分项到 5 级；6 准霸主且一两项到 6 级；6+ 霸主、有比赛经历）
// 7 起是州级、全国、国际水平，只凭证据认证（见 VerificationStatus）。
//
// 为什么问分项而不是“你觉得自己几级”：自评和实际表现相关只有 r≈0.29（Mabe & West 1982），
// 水平越低越容易高估（Heck 等 2025）；题目越具体、越可核验，自评越准（Zell & Krizan 2014）。
// 所以每个选项都是能对照的具体表现，“全部”看最弱的分项，“一两项精通”看最强的两项。
//
// 比赛、训练经历给保底；保底比结果高 2 级以上时标记“待校准”；最近一年不常打：保底减 1 级。
// 问卷最高 6+；球友评价最多推到 7−；7 起凭赛果、排名、证书认证。

struct AssessmentOption: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 技术分项：这个答案对应的等级；经历题：保底分值；俱乐部位置：对应的 6 级档位；其余台阶题按选项序号走（nil）
    let value: Double?
}

struct AssessmentQuestion: Identifiable, Hashable {
    enum Kind: Hashable {
        /// 技术分项（每个选项对应一个等级）
        case technique
        /// 台阶：被动球、双打、稳定性、战术、俱乐部里的位置
        case ladder
        /// 比赛 / 训练经历（给保底）
        case experience
        /// 最近一年是否常打
        case recency
    }

    let id: String
    let kind: Kind
    let title: String
    let hint: String
    let options: [AssessmentOption]
}

/// 一个技术分项的结果（“反手后场 3 级”）
struct AssessmentDimension: Identifiable, Hashable {
    let id: String
    let name: String
    let level: Int
}

struct SkillAssessmentResult: Equatable {
    let tier: SkillTier
    var level: Int { tier.level }
    /// 经历和技术对不上（保底比结果高 2 级以上）
    let needsCalibration: Bool
    /// 最近一年不常打
    let isReturning: Bool
    /// 选了参加过 A / Open 组：提示申请认证
    let suggestsVerification: Bool
    /// 卡在哪里（比如“想到 4 级先补短板：反手后场、发力”）；没被卡住时为 nil，结果页提示下一档的标准
    let limitingGate: String?
    /// 各技术分项的等级
    var dimensions: [AssessmentDimension] = []

    /// 技术特点：最强的分项（比整体高时才算）
    var strengths: [AssessmentDimension] {
        guard let top = dimensions.map(\.level).max(), let low = dimensions.map(\.level).min(), top > low else { return [] }
        return dimensions.filter { $0.level == top }
    }
}

/// 定级结果的摘要（存到用户资料里）
struct SkillAssessmentSummary: Codable, Hashable {
    var level: Int
    var needsCalibration: Bool
    var isReturning: Bool
    var assessedAt: Date
    /// 细分档位分值（老数据为空）
    var rating: Double?

    var tier: SkillTier { SkillTier(rating: rating ?? Double(level)) }

    /// 多久可以重测一次（避免反复刷等级）
    static let retakeInterval: TimeInterval = 90 * 86400

    func canRetake(now: Date = Date()) -> Bool {
        now.timeIntervalSince(assessedAt) >= Self.retakeInterval
    }

    func nextRetakeDate() -> Date { assessedAt.addingTimeInterval(Self.retakeInterval) }
}

enum SkillAssessment {

    /// 问卷能给到的最高档（俱乐部霸主）
    static let maxTier = SkillTier(level: SkillLevel.maxSelfSelectable, modifier: .plus)

    private static let third = 1.0 / 3

    /// 技术分项（问卷题目 ID）
    static let techniqueIds = ["forehand", "backhand", "net", "footwork", "power", "attack"]

    // MARK: Questions

    static let questions: [AssessmentQuestion] = [
        AssessmentQuestion(id: "forehand", kind: .technique, title: "正手后场",
                           hint: "高远、吊球、杀球，你现在打得怎么样？",
                           options: [
                            AssessmentOption(id: 0, text: "挥拍还不对，高远到不了中场", value: 1),
                            AssessmentOption(id: 1, text: "挥拍对了，但发力、时机、击球点还不对，多靠挥手臂", value: 2),
                            AssessmentOption(id: 2, text: "高远能底线到底线但球速慢；吊、杀能做出来，质量有限", value: 3),
                            AssessmentOption(id: 3, text: "拉、吊、杀在打球中都能轻松完成，球速一般，落点凭感觉", value: 4),
                            AssessmentOption(id: 4, text: "平高、高远、直线斜线吊、劈吊、劈杀都熟练，落点基本到位", value: 5),
                            AssessmentOption(id: 5, text: "拉吊杀动作一致，对手很难提前判断你打什么", value: 6)
                           ]),
        AssessmentQuestion(id: "backhand", kind: .technique, title: "反手后场",
                           hint: "球被打到你的反手后场时：",
                           options: [
                            AssessmentOption(id: 0, text: "基本不会，只能绕头打或者放弃", value: 2),
                            AssessmentOption(id: 1, text: "能正确挥拍但常出错，回球只到中场或略偏后", value: 3),
                            AssessmentOption(id: 2, text: "能回到对方中后场，但不能底线到底线；反手吊不稳", value: 4),
                            AssessmentOption(id: 3, text: "反手直线、斜线吊都会，后场回后场比较轻松", value: 5),
                            AssessmentOption(id: 4, text: "底线到底线轻松，反手劈吊熟练，机会好时反手杀也有威力", value: 6)
                           ]),
        AssessmentQuestion(id: "net", kind: .technique, title: "网前",
                           hint: "放网、搓球、勾对角、挑球、推扑：",
                           options: [
                            AssessmentOption(id: 0, text: "基本是轻放过去，时高时远，常不过网", value: 2),
                            AssessmentOption(id: 1, text: "放网质量基本能控制，搓球、勾对角刚开始用，失误多", value: 3),
                            AssessmentOption(id: 2, text: "挑球能到底线，正反手搓球正确，勾对角常用但质量一般", value: 4),
                            AssessmentOption(id: 3, text: "挑、搓都熟练，开始会展搓和推球", value: 5),
                            AssessmentOption(id: 4, text: "搓、勾、推、扑都熟练并用在实战里，动作一致", value: 6)
                           ]),
        AssessmentQuestion(id: "footwork", kind: .technique, title: "步法",
                           hint: "你在场上的移动：",
                           options: [
                            AssessmentOption(id: 0, text: "走着够球，还没有步法", value: 1),
                            AssessmentOption(id: 1, text: "知道要移动，但没有固定的步法", value: 2),
                            AssessmentOption(id: 2, text: "能区分垫步、跨步，全场六个点能走到但不流畅", value: 3),
                            AssessmentOption(id: 3, text: "全场步法正确并能用在打球中，但启动和移动速度不够", value: 4),
                            AssessmentOption(id: 4, text: "全场多点步法轻松，启动和移动速度中上", value: 5),
                            AssessmentOption(id: 5, text: "步法像本能一样自然，全场没有盲点", value: 6)
                           ]),
        AssessmentQuestion(id: "power", kind: .technique, title: "发力",
                           hint: "击球时主要靠哪里发力？",
                           options: [
                            AssessmentOption(id: 0, text: "主要靠挥大臂", value: 2),
                            AssessmentOption(id: 1, text: "能区分手臂和手腕发力，对内旋、外旋有基本概念", value: 3),
                            AssessmentOption(id: 2, text: "打球中能用上手腕和内外旋，但力量有限", value: 4),
                            AssessmentOption(id: 3, text: "前臂内外旋和手腕发力熟练，开始体会手指发力", value: 5),
                            AssessmentOption(id: 4, text: "手指发力熟练：网前精细控制、杀球的额外爆发都靠它", value: 6)
                           ]),
        AssessmentQuestion(id: "attack", kind: .technique, title: "进攻",
                           hint: "杀球和组织进攻：",
                           options: [
                            AssessmentOption(id: 0, text: "不会杀，或者一杀就下网、出界", value: 2),
                            AssessmentOption(id: 1, text: "能往下压，但力量和落点都不够", value: 3),
                            AssessmentOption(id: 2, text: "能根据对方回球组织进攻，但速度和角度一般，很难一拍致命", value: 4),
                            AssessmentOption(id: 3, text: "直线、斜线进攻规范，力量速度中上，有一定威胁", value: 5),
                            AssessmentOption(id: 4, text: "杀球有暴击音，能按对方站位用重杀、劈杀、点杀", value: 6)
                           ]),
        AssessmentQuestion(id: "passive", kind: .ladder, title: "被动球、防守",
                           hint: "被压到底线、被调到网前或后场死角、接对方重杀时，你通常：",
                           options: [
                            AssessmentOption(id: 0, text: "基本接不到，或者直接失误", value: nil),
                            AssessmentOption(id: 1, text: "只能挡直线网前或挑高，不能变线，对方很容易得分", value: nil),
                            AssessmentOption(id: 2, text: "有时能过渡出来：回到对方后场或网前，让自己回位", value: nil),
                            AssessmentOption(id: 3, text: "防守熟练，回球基本到位，多数能摆脱被动", value: nil),
                            AssessmentOption(id: 4, text: "能防住不是绝对机会的杀球并控制落点，对方杀得一般时能反抽", value: nil)
                           ]),
        AssessmentQuestion(id: "doubles", kind: .ladder, title: "双打",
                           hint: "打双打时，你对站位和配合的掌握？",
                           options: [
                            AssessmentOption(id: 0, text: "不清楚该站哪", value: nil),
                            AssessmentOption(id: 1, text: "知道进攻前后站、防守左右站", value: nil),
                            AssessmentOption(id: 2, text: "发接发、移动补位、封网都有基本意识", value: nil),
                            AssessmentOption(id: 3, text: "会主动抢网，后场注意保持进攻", value: nil),
                            AssessmentOption(id: 4, text: "能找对手的空档和配合盲区", value: nil)
                           ]),
        AssessmentQuestion(id: "stability", kind: .ladder, title: "稳定性",
                           hint: "对拉和实战里，你的失误多不多？",
                           options: [
                            AssessmentOption(id: 0, text: "对拉不到 5 拍就断", value: nil),
                            AssessmentOption(id: 1, text: "慢速能对拉 5–10 拍", value: nil),
                            AssessmentOption(id: 2, text: "能连续对拉十几拍，但实战一快就失误多", value: nil),
                            AssessmentOption(id: 3, text: "实战失误比以前少了，但关键分还会紧", value: nil),
                            AssessmentOption(id: 4, text: "多拍相持很稳，很少主动失误", value: nil),
                            AssessmentOption(id: 5, text: "高强度打到第三局也很稳", value: nil)
                           ]),
        AssessmentQuestion(id: "tactics", kind: .ladder, title: "战术",
                           hint: "比赛时你主要怎么得分？",
                           options: [
                            AssessmentOption(id: 0, text: "主要是把球打过去，等对方失误", value: nil),
                            AssessmentOption(id: 1, text: "会找对方的弱点打（比如反手）", value: nil),
                            AssessmentOption(id: 2, text: "会用落点和节奏调动对手：压后场、吊前场", value: nil),
                            AssessmentOption(id: 3, text: "战术和技巧结合：用假动作、变线组织连续进攻，随对手调整", value: nil),
                            AssessmentOption(id: 4, text: "能针对不同对手提前定打法，并在场上执行", value: nil)
                           ]),
        AssessmentQuestion(id: "standing", kind: .ladder, title: "在俱乐部里的位置",
                           hint: "和你常一起打的俱乐部或固定局比，你大概在什么位置？",
                           options: [
                            AssessmentOption(id: 0, text: "还在中下游", value: nil),
                            AssessmentOption(id: 1, text: "中游，和大多数人有来有回", value: nil),
                            AssessmentOption(id: 2, text: "中上游，能赢大多数人", value: nil),
                            AssessmentOption(id: 3, text: "崭露头角：和最强的几个人互有胜负", value: 6 - third),
                            AssessmentOption(id: 4, text: "准霸主：日常局很少输，常有人找你请教", value: 6),
                            AssessmentOption(id: 5, text: "霸主：俱乐部对抗的主力，开始打业余 / 半专业比赛", value: 6 + third)
                           ]),
        AssessmentQuestion(id: "experience", kind: .experience, title: "比赛和训练经历",
                           hint: "选最高的一项",
                           options: [
                            AssessmentOption(id: 0, text: "都没有", value: nil),
                            AssessmentOption(id: 1, text: "上过 20 节以上的课", value: 2),
                            AssessmentOption(id: 2, text: "打过 E 组或 D 组比赛", value: 3),
                            AssessmentOption(id: 3, text: "C / B 组进过前四，或青训 2 年以上", value: 5 - third),
                            AssessmentOption(id: 4, text: "参加过 A 组或 Open 组", value: 6 - third)
                           ]),
        AssessmentQuestion(id: "recency", kind: .recency, title: "最近一年",
                           hint: "最近一年，你平均每月打球至少 2 次吗？",
                           options: [
                            AssessmentOption(id: 0, text: "是，一直在打", value: 1),
                            AssessmentOption(id: 1, text: "没有，最近打得少（以前打得多）", value: 0)
                           ])
    ]

    static func question(_ id: String) -> AssessmentQuestion? { questions.first { $0.id == id } }

    // MARK: Scoring

    /// 根据答案（题目 ID → 选项 ID）计算细分档位；没答完返回 nil
    static func evaluate(_ answers: [String: Int]) -> SkillAssessmentResult? {
        guard questions.allSatisfy({ answers[$0.id] != nil }) else { return nil }
        func option(_ id: String) -> Int { answers[id] ?? 0 }
        func value(_ id: String) -> Double? {
            guard let question = question(id), question.options.indices.contains(option(id)) else { return nil }
            return question.options[option(id)].value
        }

        let isReturning = option("recency") == 1
        let suggestsVerification = option("experience") == 4
        let dimensions = techniqueIds.compactMap { id -> AssessmentDimension? in
            guard let question = question(id), let level = value(id) else { return nil }
            return AssessmentDimension(id: id, name: question.title, level: Int(level))
        }

        // 0. 完全的新手：正手挥拍不对、还没有步法
        if option("forehand") == 0 && option("footwork") == 0 {
            let untouched = option("net") == 0 && option("doubles") == 0
            return SkillAssessmentResult(tier: SkillTier(level: 1, modifier: untouched ? .minus : .base),
                                         needsCalibration: false, isReturning: isReturning,
                                         suggestsVerification: false, limitingGate: nil, dimensions: dimensions)
        }

        // 1. 技术分项：“全部”看最弱的，“多数”看第 3 弱的（6 项里至少 4 项），“一两项”看第 2 强的
        let levels = dimensions.map(\.level).sorted()
        let all = levels.first ?? 1
        let most = levels.count >= 3 ? levels[2] : all
        let topTwo = levels.count >= 2 ? levels[levels.count - 2] : all
        func below(_ level: Int) -> [String] { dimensions.filter { $0.level < level }.map(\.name) }

        var rating: Double
        var limitingGate: String?
        switch all {
        case 4...:
            // 所有分项到 4 级：主动球全部不错；一两项到 5 级且稳定性有提升 → 4+
            rating = topTwo >= 5 && option("stability") >= 3 ? 4 + third : 4
        case 3:
            // 所有分项都会；多数到 4 级 → 4−，一两项到 4 级 → 3+
            rating = most >= 4 ? 4 - third : (topTwo >= 4 ? 3 + third : 3)
            limitingGate = "想到 4 级先补短板：" + below(4).joined(separator: "、")
        default:
            if most >= 3 {
                rating = 3 - third
            } else if most >= 2 {
                rating = topTwo >= 3 ? 2 + third : 2
            } else {
                rating = topTwo >= 2 ? 2 - third : 1 + third
            }
            limitingGate = "想到 3 级先补短板：" + below(3).joined(separator: "、")
        }
        // 4 级还要有双打的基本意识
        if rating >= 4 - 0.01 && option("doubles") < 2 {
            rating = 4 - third
            limitingGate = "想到 4 级：双打要有发接发、移动补位、封网的基本意识"
        }

        // 2. 被动球：4+ 之后，有时能过渡出来 → 5−；多数能摆脱、并会用落点和节奏 → 5
        if rating >= 4 + third - 0.01, option("passive") >= 2 {
            rating = 5 - third
            if option("passive") >= 3 && option("tactics") >= 2 { rating = 5 }
        }
        // 3. 战术和技巧明显结合 → 5+
        if rating >= 5 - 0.01, option("tactics") >= 3 {
            rating = 5 + third
        }
        // 4. 6 级：俱乐部位置 + 技术（多数分项到 5 级、多拍很稳；6 要有一两项到 6 级；6+ 要有比赛经历）
        if rating >= 5 + third - 0.01, let standing = value("standing") {
            if most >= 5 && option("stability") >= 4 {
                var reached = min(standing, 6 - third)
                if standing >= 6 - 0.01 {
                    if topTwo >= 6 { reached = 6 } else { limitingGate = "想到 6 级：要有一两项技术到 6 级（绝活）" }
                }
                if standing >= 6 + third - 0.01 && reached >= 6 - 0.01 {
                    if option("experience") >= 3 { reached = 6 + third } else { limitingGate = "想到 6+：要有比赛或青训经历" }
                }
                rating = reached
            } else {
                limitingGate = "想到 6−：多数技术分项到 5 级，多拍很稳"
            }
        }

        // 5. 经历保底（回归球友减 1 级）
        var floor = value("experience") ?? 1
        if isReturning { floor -= 1 }
        let final = min(max(rating, floor, 1 - third), maxTier.rating)
        let needsCalibration = floor - rating >= 2 - 0.01

        return SkillAssessmentResult(tier: min(SkillTier(rating: final), maxTier), needsCalibration: needsCalibration,
                                     isReturning: isReturning, suggestsVerification: suggestsVerification,
                                     limitingGate: floor > rating ? nil : limitingGate, dimensions: dimensions)
    }

    #if DEBUG
    /// 演示：典型的中级球友（所有分项到 4 级，被动球还处理不了，截图用）
    static let demoAnswers: [String: Int] = [
        "forehand": 3, "backhand": 2, "net": 2, "footwork": 3, "power": 2, "attack": 2,
        "passive": 1, "doubles": 2, "stability": 2, "tactics": 1, "standing": 1, "experience": 2, "recency": 0
    ]
    #endif
}
