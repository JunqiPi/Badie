import Foundation

// MARK: - 定级问卷：回答动作题，自动算出 1–7 级
//
// 为什么不让人直接挑等级：自评和实际表现的相关只有 r≈0.29（Mabe & West 1982），
// 水平越低的人越容易高估（Heck 等 2025，棋手平均高估 89 Elo 分）；
// 题目越具体、越“可数”（10 个高远球有几个到后场），自评越准（Zell & Krizan 2014）。
// 所以每道题都问能不能做到某个动作，不问“你觉得自己多厉害”。
//
// 计分：
// 1. 正手高远和步法都选最低项 → 1 级
// 2. 前 6 道技术题分值取中位数，向下取整（拿不准取低）
// 3. 门槛封顶：4 级要正手高远 ≥7/10 到后场；5 级要反手能回中后场且双打会轮转；
//    6 级要杀上网稳定且接杀能变线；7 级要反手底线到底线且有比赛/青训经历
// 4. 比赛、训练经历给保底；保底比技术结果高 2 级以上时标记“待校准”
// 5. 最近一年不常打（回归球友）：保底减 1，并让球友评价更快校准
// 6. 问卷最多到 7 级；8–9 级只凭赛果认证

struct AssessmentOption: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 技术题：这个答案对应的等级；经历题：保底等级（nil = 不保底）
    let value: Int?
}

struct AssessmentQuestion: Identifiable, Hashable {
    enum Kind: Hashable {
        /// 技术动作（计入中位数）
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
    let level: Int
    /// 经历和技术对不上（保底比技术结果高 2 级以上）
    let needsCalibration: Bool
    /// 最近一年不常打
    let isReturning: Bool
    /// 选了参加过 A / Open 组：提示申请 8–9 级认证
    let suggestsVerification: Bool
    /// 哪一项把等级限制住了（用于提示“再进一步需要什么”）
    let limitingGate: String?
}

/// 定级结果的摘要（存到用户资料里）
struct SkillAssessmentSummary: Codable, Hashable {
    var level: Int
    var needsCalibration: Bool
    var isReturning: Bool
    var assessedAt: Date

    /// 多久可以重测一次（避免反复刷等级）
    static let retakeInterval: TimeInterval = 90 * 86400

    func canRetake(now: Date = Date()) -> Bool {
        now.timeIntervalSince(assessedAt) >= Self.retakeInterval
    }

    func nextRetakeDate() -> Date { assessedAt.addingTimeInterval(Self.retakeInterval) }
}

enum SkillAssessment {

    // MARK: Questions

    static let questions: [AssessmentQuestion] = [
        AssessmentQuestion(id: "clear", kind: .skill, title: "正手高远球",
                           hint: "站在后场打 10 个高远球，有几个能落到对方后场（双打后发球线以后）？",
                           options: [
                            AssessmentOption(id: 0, text: "到不了中场", value: 1),
                            AssessmentOption(id: 1, text: "大多落在中场", value: 2),
                            AssessmentOption(id: 2, text: "3–6 个能到后场", value: 3),
                            AssessmentOption(id: 3, text: "至少 7 个能到后场", value: 4),
                            AssessmentOption(id: 4, text: "跑动中也至少 7 个能到后场", value: 5)
                           ]),
        AssessmentQuestion(id: "backhand", kind: .skill, title: "反手后场",
                           hint: "球被打到你的反手后场时，你一般怎么处理？",
                           options: [
                            AssessmentOption(id: 0, text: "只能绕头打，或者放弃", value: 2),
                            AssessmentOption(id: 1, text: "只能挡过网", value: 3),
                            AssessmentOption(id: 2, text: "能回到对方中后场", value: 5),
                            AssessmentOption(id: 3, text: "反手直线后场、吊球都有质量", value: 6),
                            AssessmentOption(id: 4, text: "反手高远能从底线打到底线", value: 7)
                           ]),
        AssessmentQuestion(id: "smash", kind: .skill, title: "杀球",
                           hint: "你的杀球和进攻是什么样的？",
                           options: [
                            AssessmentOption(id: 0, text: "不会杀，或者杀球多半下网", value: 2),
                            AssessmentOption(id: 1, text: "只能在中场往下压", value: 3),
                            AssessmentOption(id: 2, text: "后场能连续杀，并跟进网前", value: 5),
                            AssessmentOption(id: 3, text: "杀球上网 5 个回合至少 4 次无失误", value: 6),
                            AssessmentOption(id: 4, text: "起跳杀、点杀、劈杀都会", value: 7)
                           ]),
        AssessmentQuestion(id: "defense", kind: .skill, title: "接杀",
                           hint: "对方用力杀球时，你能怎么接？",
                           options: [
                            AssessmentOption(id: 0, text: "基本接不到", value: 2),
                            AssessmentOption(id: 1, text: "能挡过网", value: 3),
                            AssessmentOption(id: 2, text: "能挑到对方后场", value: 4),
                            AssessmentOption(id: 3, text: "接重杀能抽挡、变线", value: 6),
                            AssessmentOption(id: 4, text: "能把防守转成进攻", value: 7)
                           ]),
        AssessmentQuestion(id: "footwork", kind: .skill, title: "步法",
                           hint: "你在场上的移动是什么样的？",
                           options: [
                            AssessmentOption(id: 0, text: "走着够球", value: 1),
                            AssessmentOption(id: 1, text: "能跑到位，但回位慢", value: 3),
                            AssessmentOption(id: 2, text: "四个角都能到位，打完回中", value: 4),
                            AssessmentOption(id: 3, text: "连续被调动 20 拍步法不乱", value: 5),
                            AssessmentOption(id: 4, text: "打到第三局仍然稳定", value: 7)
                           ]),
        AssessmentQuestion(id: "doubles", kind: .skill, title: "双打",
                           hint: "打双打时，你对站位和配合的掌握？",
                           options: [
                            AssessmentOption(id: 0, text: "不清楚该站哪", value: 1),
                            AssessmentOption(id: 1, text: "知道进攻前后站、防守左右站", value: 3),
                            AssessmentOption(id: 2, text: "攻守转换时会自动轮转", value: 4),
                            AssessmentOption(id: 3, text: "会封网、补位", value: 5),
                            AssessmentOption(id: 4, text: "常用推腰、变线，能带搭档", value: 6)
                           ]),
        AssessmentQuestion(id: "experience", kind: .experience, title: "比赛和训练经历",
                           hint: "选最高的一项",
                           options: [
                            AssessmentOption(id: 0, text: "都没有", value: nil),
                            AssessmentOption(id: 1, text: "上过 20 节以上的课", value: 2),
                            AssessmentOption(id: 2, text: "打过 E 组或 D 组比赛", value: 3),
                            AssessmentOption(id: 3, text: "C / B 组进过前四，或青训 2 年以上", value: 5),
                            AssessmentOption(id: 4, text: "参加过 A 组或 Open 组", value: 6)
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

    /// 根据答案（题目 ID → 选项 ID）计算等级；没答完返回 nil
    static func evaluate(_ answers: [String: Int]) -> SkillAssessmentResult? {
        guard questions.allSatisfy({ answers[$0.id] != nil }) else { return nil }
        func option(_ id: String) -> Int { answers[id] ?? 0 }
        func value(_ id: String) -> Int? {
            guard let question = question(id), question.options.indices.contains(option(id)) else { return nil }
            return question.options[option(id)].value
        }

        let isReturning = option("recency") == 1
        let suggestsVerification = option("experience") == 4

        // 1. 完全的新手
        if option("clear") == 0 && option("footwork") == 0 {
            return SkillAssessmentResult(level: 1, needsCalibration: false, isReturning: isReturning,
                                         suggestsVerification: false, limitingGate: nil)
        }

        // 2. 技术题中位数（向下取整）
        let skillValues = questions.filter { $0.kind == .skill }.compactMap { value($0.id) }.sorted()
        let middle = skillValues.count / 2
        let median = skillValues.count % 2 == 0
            ? (skillValues[middle - 1] + skillValues[middle]) / 2
            : skillValues[middle]

        // 3. 门槛：逐级检查，过不了的那一级就是上限
        let gates: [(level: Int, passed: Bool, need: String)] = [
            (4, option("clear") >= 3, "正手高远 10 个里至少 7 个到后场"),
            (5, option("backhand") >= 2 && option("doubles") >= 2, "反手能回到中后场，双打会轮转"),
            (6, option("smash") >= 3 && option("defense") >= 3, "杀球上网稳定，接重杀能变线"),
            (7, option("backhand") == 4 && option("experience") >= 3, "反手底线到底线，并有比赛或青训经历")
        ]
        var cap = 3
        var limitingGate: String?
        for gate in gates {
            if gate.passed {
                cap = gate.level
            } else {
                limitingGate = gate.need
                break
            }
        }
        let gated = min(median, cap)

        // 4. 经历保底（回归球友减 1）
        var floor = value("experience") ?? 1
        if isReturning { floor -= 1 }
        let level = min(SkillLevel.maxSelfSelectable, max(1, max(gated, floor)))
        let needsCalibration = floor - gated >= 2

        return SkillAssessmentResult(level: level, needsCalibration: needsCalibration, isReturning: isReturning,
                                     suggestsVerification: suggestsVerification,
                                     limitingGate: level < cap ? nil : limitingGate)
    }

    #if DEBUG
    /// 演示：典型的中级球友（截图用）
    static let demoAnswers: [String: Int] = [
        "clear": 3, "backhand": 1, "smash": 2, "defense": 2, "footwork": 2, "doubles": 2, "experience": 2, "recency": 0
    ]
    #endif
}
