import Foundation

// MARK: - 定级问卷：按台阶往上走，自动算出 1− 到 6+
//
// 3–6 级每一级多了一个维度：
//   3：技术会不会（3+ = 全部都会，一两项不错，但不稳定）
//   4：技术好不好（4+ = 全部不错，一两项精通，稳定性略有提升）
//   5：稳不稳、会不会用战术（5 = 多拍很稳；5+ = 战术和技巧开始结合）
//   6：在俱乐部里的位置（6− 崭露头角，6 佼佼者，6+ 顶尖）
// 7 起是州级、全国、国际水平，只凭证据认证（见 VerificationStatus）。
//
// 技术在 4 级就该全部熟练（包括反手），5 级以上不再按“会不会某个技术”分，只看稳定、战术和在俱乐部里的位置。
//
// 为什么还要问具体动作：自评和实际表现相关只有 r≈0.29（Mabe & West 1982），水平越低越容易高估（Heck 等 2025）；
// 题目越具体、越“可数”，自评越准（Zell & Krizan 2014）。所以“技术都不错”“很稳”这类说法，
// 要用高远、反手、杀球、接杀、双打这几道动作题核对，做不到就按动作题封顶。
//
// 计分：
// 1. 台阶：技术掌握面给起点；全部不错且一两项精通后看稳定性；稳了再看战术；会用战术再看俱乐部里的位置
// 2. 动作核对：5 道动作题的中位数 + 1 级是上限；4 级的硬门槛是正手高远 ≥7/10 到后场、反手能回到中后场、双打会轮转
// 3. 比赛、训练经历给保底；保底比结果高 2 级以上时标记“待校准”；最近一年不常打：保底减 1 级
// 4. 问卷最高 6+；球友评价最多推到 7−；7 起凭赛果、排名、证书认证

struct AssessmentOption: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 这个答案对应的分值（4+ = 4.33）；经历题是保底分值（nil = 不保底）
    let value: Double?
}

struct AssessmentQuestion: Identifiable, Hashable {
    enum Kind: Hashable {
        /// 定义等级的维度：技术掌握面、稳定性、战术、俱乐部里的位置（按台阶计分）
        case ladder
        /// 具体动作（用来核对，取中位数封顶）
        case skill
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

struct SkillAssessmentResult: Equatable {
    let tier: SkillTier
    var level: Int { tier.level }
    /// 经历和技术对不上（保底比结果高 2 级以上）
    let needsCalibration: Bool
    /// 最近一年不常打
    let isReturning: Bool
    /// 选了参加过 A / Open 组：提示申请认证
    let suggestsVerification: Bool
    /// 被哪一道动作题卡住了（用于提示“再进一步需要什么”）；没被卡住时为 nil
    let limitingGate: String?
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

    /// 问卷能给到的最高档（俱乐部顶尖）
    static let maxTier = SkillTier(level: SkillLevel.maxSelfSelectable, modifier: .plus)

    private static let third = 1.0 / 3

    // MARK: Questions

    static let questions: [AssessmentQuestion] = [
        AssessmentQuestion(id: "breadth", kind: .ladder, title: "技术掌握",
                           hint: "发球、高远、吊球、杀球、搓放网、挑球、推扑、接杀、平抽挡——你现在：",
                           options: [
                            AssessmentOption(id: 0, text: "只会其中几项（比如发球、高远）", value: 2),
                            AssessmentOption(id: 1, text: "大部分会做，还有几项不会", value: 3 - third),
                            AssessmentOption(id: 2, text: "全部会做，但质量一般", value: 3),
                            AssessmentOption(id: 3, text: "全部会，一两项打得不错，但不稳定", value: 3 + third),
                            AssessmentOption(id: 4, text: "全部都打得不错", value: 4),
                            AssessmentOption(id: 5, text: "全部不错，一两项精通（是我的得分手段）", value: 4 + third)
                           ]),
        AssessmentQuestion(id: "clear", kind: .skill, title: "正手高远球",
                           hint: "站在后场打 10 个高远球，有几个能落到对方后场（双打后发球线以后）？",
                           options: [
                            AssessmentOption(id: 0, text: "到不了中场", value: 1),
                            AssessmentOption(id: 1, text: "大多落在中场", value: 2),
                            AssessmentOption(id: 2, text: "3–6 个能到后场", value: 3),
                            AssessmentOption(id: 3, text: "至少 7 个能到后场", value: 4),
                            AssessmentOption(id: 4, text: "跑动中也至少 7 个能到后场", value: 5 - third)
                           ]),
        AssessmentQuestion(id: "backhand", kind: .skill, title: "反手后场",
                           hint: "球被打到你的反手后场时，你一般怎么处理？",
                           options: [
                            AssessmentOption(id: 0, text: "只能绕头打，或者放弃", value: 2),
                            AssessmentOption(id: 1, text: "只能挡过网", value: 3),
                            AssessmentOption(id: 2, text: "能回到对方中后场", value: 4),
                            AssessmentOption(id: 3, text: "反手直线后场、吊球都有质量", value: 5 - third),
                            AssessmentOption(id: 4, text: "反手高远能从底线打到底线", value: 5 + third)
                           ]),
        AssessmentQuestion(id: "smash", kind: .skill, title: "杀球",
                           hint: "你的杀球和进攻是什么样的？",
                           options: [
                            AssessmentOption(id: 0, text: "不会杀，或者杀球多半下网", value: 2),
                            AssessmentOption(id: 1, text: "只能在中场往下压", value: 3),
                            AssessmentOption(id: 2, text: "后场能连续杀，并跟进网前", value: 4),
                            AssessmentOption(id: 3, text: "杀球上网 5 个回合至少 4 次无失误", value: 5),
                            AssessmentOption(id: 4, text: "起跳杀、点杀、劈杀都会", value: 6 - third)
                           ]),
        AssessmentQuestion(id: "defense", kind: .skill, title: "接杀",
                           hint: "对方用力杀球时，你能怎么接？",
                           options: [
                            AssessmentOption(id: 0, text: "基本接不到", value: 2),
                            AssessmentOption(id: 1, text: "能挡过网", value: 3),
                            AssessmentOption(id: 2, text: "能挑到对方后场", value: 4),
                            AssessmentOption(id: 3, text: "接重杀能抽挡、变线", value: 5),
                            AssessmentOption(id: 4, text: "能把防守转成进攻", value: 6 - third)
                           ]),
        AssessmentQuestion(id: "doubles", kind: .skill, title: "双打",
                           hint: "打双打时，你对站位和配合的掌握？",
                           options: [
                            AssessmentOption(id: 0, text: "不清楚该站哪", value: 1),
                            AssessmentOption(id: 1, text: "知道进攻前后站、防守左右站", value: 3),
                            AssessmentOption(id: 2, text: "攻守转换时会自动轮转", value: 4),
                            AssessmentOption(id: 3, text: "会封网、补位", value: 5),
                            AssessmentOption(id: 4, text: "常用推腰、变线，能带搭档", value: 6 - third)
                           ]),
        AssessmentQuestion(id: "stability", kind: .ladder, title: "稳定性",
                           hint: "对拉和实战里，你的失误多不多？",
                           options: [
                            AssessmentOption(id: 0, text: "对拉不到 5 拍就断", value: 1),
                            AssessmentOption(id: 1, text: "慢速能对拉 5–10 拍", value: 2),
                            AssessmentOption(id: 2, text: "能连续对拉十几拍，但实战一快就失误多", value: 3 + third),
                            AssessmentOption(id: 3, text: "实战失误比以前少了，但关键分还会紧", value: 4 + third),
                            AssessmentOption(id: 4, text: "多拍相持很稳，很少主动失误", value: 5),
                            AssessmentOption(id: 5, text: "高强度打到第三局也很稳", value: 5)
                           ]),
        AssessmentQuestion(id: "tactics", kind: .ladder, title: "战术",
                           hint: "比赛时你主要怎么得分？",
                           options: [
                            AssessmentOption(id: 0, text: "主要是把球打过去，等对方失误", value: 3 - third),
                            AssessmentOption(id: 1, text: "会找对方的弱点打（比如反手）", value: 4),
                            AssessmentOption(id: 2, text: "会用落点和节奏调动对手", value: 5 - third),
                            AssessmentOption(id: 3, text: "战术和技巧结合：用假动作、变线组织连续进攻，随对手调整", value: 5 + third),
                            AssessmentOption(id: 4, text: "能针对不同对手提前定打法，并在场上执行", value: 5 + third)
                           ]),
        AssessmentQuestion(id: "standing", kind: .ladder, title: "在俱乐部里的位置",
                           hint: "和你常一起打的俱乐部或固定局比，你大概在什么位置？",
                           options: [
                            AssessmentOption(id: 0, text: "还在中下游", value: nil),
                            AssessmentOption(id: 1, text: "中游，和大多数人有来有回", value: nil),
                            AssessmentOption(id: 2, text: "中上游，能赢大多数人", value: nil),
                            AssessmentOption(id: 3, text: "开始崭露头角：和最强的几个人互有胜负", value: 6 - third),
                            AssessmentOption(id: 4, text: "佼佼者：日常局很少输", value: 6),
                            AssessmentOption(id: 5, text: "顶尖：俱乐部里基本没对手，常打比赛最高组", value: 6 + third)
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

        // 0. 完全的新手：高远到不了中场、对拉不到 5 拍
        if option("clear") == 0 && option("stability") == 0 {
            let untouched = option("breadth") == 0 && option("doubles") == 0
            return SkillAssessmentResult(tier: SkillTier(level: 1, modifier: untouched ? .minus : .base),
                                         needsCalibration: false, isReturning: isReturning,
                                         suggestsVerification: false, limitingGate: nil)
        }

        // 1. 台阶：逐个维度往上走，前一个维度没到就不看后面的
        var claimed: Double
        if option("breadth") == 0 {
            // 只会几项：1+ 到 2+，看对拉和高远
            switch (option("stability"), option("clear")) {
            case (0, _): claimed = 1 + third
            case (_, 0): claimed = 2 - third
            case (_, 1): claimed = 2
            default: claimed = 2 + third
            }
        } else {
            claimed = value("breadth") ?? 2
        }
        // 全部不错、一两项精通：稳定性有提升才是 4+，很稳才到 5
        if option("breadth") == 5 {
            claimed = option("stability") >= 3 ? max(claimed, value("stability") ?? claimed) : 4
        }
        // 多拍很稳（5）后，战术决定 5+
        if claimed >= 5 - 0.01, option("tactics") >= 3, let tactics = value("tactics") {
            claimed = max(claimed, tactics)
        }
        // 战术和技巧结合（5+）后，俱乐部里的位置决定 6 级
        if claimed >= 5 + third - 0.01, let standing = value("standing") {
            claimed = max(claimed, standing)
        }

        // 2. 动作核对：中位数 + 1 级为上限（技术题最高在 5 级左右，再往上靠稳定、战术、俱乐部位置区分）
        let skillValues = questions.filter { $0.kind == .skill }.compactMap { value($0.id) }.sorted()
        let middle = skillValues.count / 2
        let median = skillValues.count % 2 == 0
            ? (skillValues[middle - 1] + skillValues[middle]) / 2
            : skillValues[middle]
        var cap = median + 1
        var limitingGate: String?
        if claimed > cap + 0.01 { limitingGate = "高远、反手、杀球、接杀、双打这几项动作还要跟上" }

        // 硬门槛：到某一档必须做到的具体动作
        let gates: [(rating: Double, passed: Bool, need: String)] = [
            // 4 级：全部技术都要到位，包括反手
            (4, option("clear") >= 3 && option("backhand") >= 2 && option("doubles") >= 2,
             "全部技术到位：正手高远 ≥7/10 到后场，反手能回到对方中后场，双打会轮转"),
            (6 - third, option("smash") >= 3 && option("defense") >= 3, "高强度下也稳：杀球上网不失误，接重杀能抽挡变线"),
            (6 + third, option("experience") >= 3, "有比赛或青训经历")
        ]
        for gate in gates where !gate.passed && gate.rating - third < cap - 0.01 {
            cap = gate.rating - third
            if claimed > cap + 0.01 { limitingGate = gate.need }
            break
        }
        let gated = min(claimed, cap)

        // 3. 经历保底（回归球友减 1 级）
        var floor = value("experience") ?? 1
        if isReturning { floor -= 1 }
        let rating = min(max(gated, floor, 1 - third), maxTier.rating)
        let needsCalibration = floor - gated >= 2 - 0.01

        return SkillAssessmentResult(tier: min(SkillTier(rating: rating), maxTier), needsCalibration: needsCalibration,
                                     isReturning: isReturning, suggestsVerification: suggestsVerification,
                                     limitingGate: floor > gated ? nil : limitingGate)
    }

    #if DEBUG
    /// 演示：典型的中级球友（技术都不错，还没有精通的，截图用）
    static let demoAnswers: [String: Int] = [
        "breadth": 4, "clear": 3, "backhand": 2, "smash": 2, "defense": 2, "doubles": 2,
        "stability": 2, "tactics": 1, "standing": 1, "experience": 2, "recency": 0
    ]
    #endif
}
