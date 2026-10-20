import Foundation

// MARK: - 定级问卷：每个选项对应一个等级，自动算出 1− 到 6+
//
// 技术、比赛能力各取平均，但不能比自己最弱的一项高出 1 级以上；两者以弱的为准，强的那边最多再加 2/3 级。
// 5+ 往上看在俱乐部里的位置，6+ 还要有比赛或青训经历。经历给保底。见 docs/DESIGN.md §13.3。
// 网页 web/src/app/assessment.ts 是同一套题和算法。

struct AssessmentOption: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 技术、比赛能力：这个答案对应的等级（可以是 2.5 这样的半级）；经历题：保底分值；俱乐部位置：对应的 6 级档位
    let value: Double?
}

struct AssessmentQuestion: Identifiable, Hashable {
    enum Kind: Hashable {
        /// 技术分项
        case technique
        /// 比赛能力：被动球、双打、稳定性、战术
        case game
        /// 在俱乐部里的位置（只看 5+ 往上）
        case standing
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

/// 一个技术分项的结果（“反手后场 3−”）
struct AssessmentDimension: Identifiable, Hashable {
    let id: String
    let name: String
    let rating: Double
    /// 按档位显示：2.5 → “3−”
    var code: String { SkillTier(rating: max(rating, 1 - 1.0 / 3)).code }
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
    /// 卡在哪里（比如“想到 4 级先补短板：反手后场、平抽挡”）；没被卡住时为 nil，结果页提示下一档的标准
    let limitingGate: String?
    /// 各技术分项的等级
    var dimensions: [AssessmentDimension] = []

    /// 技术特点：最强的分项（比整体高时才算）
    var strengths: [AssessmentDimension] {
        guard let top = dimensions.map(\.rating).max(), let low = dimensions.map(\.rating).min(), top > low else { return [] }
        return dimensions.filter { $0.rating == top }
    }
}

/// 定级结果的摘要（存到用户资料里）
struct SkillAssessmentSummary: Codable, Hashable {
    var level: Int
    var needsCalibration: Bool
    var isReturning: Bool
    var assessedAt: Date
    /// 细分档位分值；为空时按整数等级
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

    /// 跳过定级时暂用的等级（之后在资料页补测）
    static let provisionalLevel = 3

    // MARK: Questions

    static let questions: [AssessmentQuestion] = [
        AssessmentQuestion(id: "clear", kind: .technique, title: String(localized: "正手高远球"),
                           hint: String(localized: "站在后场打高远球："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "到不了中场"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "大多落在中场"), value: 2),
                            AssessmentOption(id: 2, text: String(localized: "能到后场，但到不了底线、球速慢"), value: 2.5),
                            AssessmentOption(id: 3, text: String(localized: "打球中能稳定底线到底线"), value: 3),
                            AssessmentOption(id: 4, text: String(localized: "知道平高球和高远球的区别，知道什么时候打哪种，能控制弧度和落点"), value: 4),
                            AssessmentOption(id: 5, text: String(localized: "和吊球、杀球动作一致，对手判断不出你打什么"), value: 6)
                           ]),
        AssessmentQuestion(id: "smash", kind: .technique, title: String(localized: "正手杀球"),
                           hint: String(localized: "后场有机会时杀球："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "不会杀，或者一杀就下网、出界，经常打杆"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "知道怎么往下压，但力量打不透"), value: 1.5),
                            AssessmentOption(id: 2, text: String(localized: "能杀下去、有一定球速，但对方不难接"), value: 2.5),
                            AssessmentOption(id: 3, text: String(localized: "机会好的时候偶尔能把力量打透，开始有角度、有威胁"), value: 3),
                            AssessmentOption(id: 4, text: String(localized: "开始懂得重杀、轻杀、点杀的妙用，杀完能跟上网前"), value: 4),
                            AssessmentOption(id: 5, text: String(localized: "重杀、劈杀、点杀用得轻车熟路，按对方站位选用"), value: 6)
                           ]),
        AssessmentQuestion(id: "drop", kind: .technique, title: String(localized: "正手吊球"),
                           hint: String(localized: "会不会吊球？会不会劈吊、滑板？"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "还不会吊"), value: 0),
                            AssessmentOption(id: 1, text: String(localized: "能吊过网，但常偏高、偏远"), value: 1),
                            AssessmentOption(id: 2, text: String(localized: "直线、斜线能吊到前发球线附近"), value: 2),
                            AssessmentOption(id: 3, text: String(localized: "会劈吊或滑板其中一种，但不稳定，角度掌握不好，常高于网带，会被抓"), value: 3),
                            AssessmentOption(id: 4, text: String(localized: "劈吊、滑板都会，但稳定性不足，球速也不够，偶尔反而陷入被动"), value: 4),
                            AssessmentOption(id: 5, text: String(localized: "劈吊、滑板都熟练，和高远、杀球动作一致，球速快、过网就落"), value: 6)
                           ]),
        AssessmentQuestion(id: "backhand", kind: .technique, title: String(localized: "反手后场"),
                           hint: String(localized: "球到了反手后场："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "只能绕头打，或者放弃"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "能用反手打，但只能到中场或中前场；对手一打你的反手你就被动"), value: 2),
                            AssessmentOption(id: 2, text: String(localized: "不被动时，能从己方中后场回到对方后场"), value: 3),
                            AssessmentOption(id: 3, text: String(localized: "会反手吊直线、斜线，有一定球速不会被抓；后场回后场的高远球很轻松"), value: 5),
                            AssessmentOption(id: 4, text: String(localized: "反手高远底线到底线；被动时反手过渡依然非常熟练"), value: 6)
                           ]),
        AssessmentQuestion(id: "net", kind: .technique, title: String(localized: "网前搓放"),
                           hint: String(localized: "放网、搓球、勾对角："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "轻放过去，时高时远，常不过网"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "放网能贴网，搓球、勾对角刚开始用"), value: 2),
                            AssessmentOption(id: 2, text: String(localized: "正反手都会搓，勾对角常用但不够贴网"), value: 3),
                            AssessmentOption(id: 3, text: String(localized: "搓球熟练，会展搓和推后场"), value: 4),
                            AssessmentOption(id: 4, text: String(localized: "搓、勾、推、扑都熟练，动作一致"), value: 6)
                           ]),
        AssessmentQuestion(id: "drive", kind: .technique, title: String(localized: "平抽挡"),
                           hint: String(localized: "中场来了快的平球："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "基本接不住"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "能挡回去，但没有速度"), value: 2),
                            AssessmentOption(id: 2, text: String(localized: "能平抽对攻几拍"), value: 2.5),
                            AssessmentOption(id: 3, text: String(localized: "平抽挡比较好，能主动加速"), value: 4),
                            AssessmentOption(id: 4, text: String(localized: "快速平抽对抗不吃亏，被动低位也能抽到底线"), value: 6)
                           ]),
        AssessmentQuestion(id: "footwork", kind: .technique, title: String(localized: "步法"),
                           hint: String(localized: "你在场上的移动："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "走着够球"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "会跑去接，但没有固定步法"), value: 1.5),
                            AssessmentOption(id: 2, text: String(localized: "会垫步、跨步，六个点能走到但不流畅"), value: 2.5),
                            AssessmentOption(id: 3, text: String(localized: "全场步法正确，但启动和移动不够快"), value: 3),
                            AssessmentOption(id: 4, text: String(localized: "全场步法轻松，启动和移动速度中上"), value: 4),
                            AssessmentOption(id: 5, text: String(localized: "步法像本能一样，全场没有盲点"), value: 6)
                           ]),
        AssessmentQuestion(id: "passive", kind: .game, title: String(localized: "接杀和被动球"),
                           hint: String(localized: "接对方重杀，或被压到底线、调到死角时："),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "基本接不到，或者直接失误"), value: 2),
                            AssessmentOption(id: 1, text: String(localized: "只能挡直线网前或挑高，不能变线，对方很容易得分"), value: 3),
                            AssessmentOption(id: 2, text: String(localized: "有时能过渡出来：回到对方后场或网前，让自己回位"), value: 4),
                            AssessmentOption(id: 3, text: String(localized: "防守熟练，回球基本到位，多数能摆脱被动"), value: 5),
                            AssessmentOption(id: 4, text: String(localized: "能防住不是绝对机会的杀球并控制落点，对方杀得一般时能反抽"), value: 6)
                           ]),
        AssessmentQuestion(id: "doubles", kind: .game, title: String(localized: "双打"),
                           hint: String(localized: "打双打时，你对站位和配合的掌握？"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "不清楚该站哪"), value: 1.5),
                            AssessmentOption(id: 1, text: String(localized: "知道进攻前后站、防守左右站"), value: 2.5),
                            AssessmentOption(id: 2, text: String(localized: "发接发、移动补位、封网都有基本意识"), value: 3.5),
                            AssessmentOption(id: 3, text: String(localized: "会主动抢网，后场注意保持进攻"), value: 4.5),
                            AssessmentOption(id: 4, text: String(localized: "能找对手的空档和配合盲区"), value: 6)
                           ]),
        AssessmentQuestion(id: "stability", kind: .game, title: String(localized: "稳定性"),
                           hint: String(localized: "对拉和实战里，你的失误多不多？"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "对拉不到 5 拍就断"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "慢速能对拉 5–10 拍"), value: 2),
                            AssessmentOption(id: 2, text: String(localized: "能连续对拉十几拍，但实战一快就失误多"), value: 3),
                            AssessmentOption(id: 3, text: String(localized: "实战失误比以前少了，但关键分还会紧"), value: 4),
                            AssessmentOption(id: 4, text: String(localized: "多拍相持很稳，很少主动失误"), value: 5),
                            AssessmentOption(id: 5, text: String(localized: "高强度打到第三局也很稳"), value: 6)
                           ]),
        AssessmentQuestion(id: "tactics", kind: .game, title: String(localized: "战术"),
                           hint: String(localized: "比赛时你主要怎么得分？"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "主要是把球打过去，等对方失误"), value: 2),
                            AssessmentOption(id: 1, text: String(localized: "会找对方的弱点打（比如反手）"), value: 3),
                            AssessmentOption(id: 2, text: String(localized: "会用落点和节奏调动对手：压后场、吊前场"), value: 4),
                            AssessmentOption(id: 3, text: String(localized: "战术和技巧结合：用假动作、变线组织连续进攻，随对手调整"), value: 5),
                            AssessmentOption(id: 4, text: String(localized: "能针对不同对手提前定打法，并在场上执行"), value: 6)
                           ]),
        AssessmentQuestion(id: "standing", kind: .standing, title: String(localized: "在俱乐部里的位置"),
                           hint: String(localized: "和你常一起打的俱乐部或固定局比，你大概在什么位置？"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "还在中下游"), value: nil),
                            AssessmentOption(id: 1, text: String(localized: "中游，和大多数人有来有回"), value: nil),
                            AssessmentOption(id: 2, text: String(localized: "中上游，能赢大多数人"), value: nil),
                            AssessmentOption(id: 3, text: String(localized: "崭露头角：和最强的几个人互有胜负"), value: 6 - third),
                            AssessmentOption(id: 4, text: String(localized: "准霸主：日常局很少输，常有人找你请教"), value: 6),
                            AssessmentOption(id: 5, text: String(localized: "霸主：俱乐部对抗的主力，开始打业余 / 半专业比赛"), value: 6 + third)
                           ]),
        AssessmentQuestion(id: "experience", kind: .experience, title: String(localized: "比赛和训练经历"),
                           hint: String(localized: "选最高的一项"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "都没有"), value: nil),
                            AssessmentOption(id: 1, text: String(localized: "上过 20 节以上的课"), value: 2),
                            AssessmentOption(id: 2, text: String(localized: "打过 E 组或 D 组比赛"), value: 3),
                            AssessmentOption(id: 3, text: String(localized: "C / B 组进过前四，或青训 2 年以上"), value: 5 - third),
                            AssessmentOption(id: 4, text: String(localized: "参加过 A 组或 Open 组"), value: 6 - third)
                           ]),
        AssessmentQuestion(id: "recency", kind: .recency, title: String(localized: "最近一年"),
                           hint: String(localized: "最近一年，你平均每月打球至少 2 次吗？"),
                           options: [
                            AssessmentOption(id: 0, text: String(localized: "是，一直在打"), value: 1),
                            AssessmentOption(id: 1, text: String(localized: "没有，最近打得少（以前打得多）"), value: 0)
                           ])
    ]

    static func question(_ id: String) -> AssessmentQuestion? { questions.first { $0.id == id } }

    // MARK: Scoring

    /// 按 1/3 级取整（3.4 → 3+）
    private static func toThirds(_ rating: Double) -> Double { (rating * 3).rounded() / 3 }

    /// 一组题的水平：取平均，但不能比最弱的一项高出 1 级以上（短板限制等级）
    private static func pillar(_ levels: [Double]) -> Double {
        guard let weakest = levels.min() else { return 1 }
        return min(levels.reduce(0, +) / Double(levels.count), weakest + 1)
    }

    /// 根据答案（题目 ID → 选项 ID）计算细分档位；没答完返回 nil
    static func evaluate(_ answers: [String: Int]) -> SkillAssessmentResult? {
        guard questions.allSatisfy({ answers[$0.id] != nil }) else { return nil }
        func option(_ id: String) -> Int { answers[id] ?? 0 }
        func value(_ question: AssessmentQuestion) -> Double? {
            question.options.indices.contains(option(question.id)) ? question.options[option(question.id)].value : nil
        }
        func scored(_ kind: AssessmentQuestion.Kind) -> [AssessmentDimension] {
            questions.filter { $0.kind == kind }.compactMap { question in
                value(question).map { AssessmentDimension(id: question.id, name: question.title, rating: $0) }
            }
        }

        let isReturning = option("recency") == 1
        let suggestsVerification = option("experience") == 4
        let technique = scored(.technique)
        let game = scored(.game)

        // 0. 完全的新手：高远到不了中场、还没有步法
        if option("clear") == 0 && option("footwork") == 0 {
            let untouched = option("net") == 0 && option("doubles") == 0
            return SkillAssessmentResult(tier: SkillTier(level: 1, modifier: untouched ? .minus : .base),
                                         needsCalibration: false, isReturning: isReturning,
                                         suggestsVerification: false, limitingGate: nil, dimensions: technique)
        }

        // 1. 技术和比赛能力：各自取平均、受最弱一项限制；两者以弱的为准，强的那边最多加 2/3 级
        let pillars = [pillar(technique.map(\.rating)), pillar(game.map(\.rating))].sorted()
        var rating = toThirds(pillars[0] + min(2 * third, (pillars[1] - pillars[0]) / 2))

        // 2. 下一档要补什么：最弱的几项（最多 3 项）。3− 的下一档是 3，3 和 3+ 的下一档是 4
        let target = rating - rating.rounded(.down) > 0.5 ? Int(rating.rounded(.up)) : Int(rating.rounded(.down)) + 1
        let weakest = (technique + game).filter { $0.rating < Double(target) }.sorted { $0.rating < $1.rating }.prefix(3)
        var limitingGate: String? = weakest.isEmpty ? nil
            : String(localized: "想到 \(target) 级先补短板：\(weakest.map(\.name).formatted(.list(type: .and)))")

        // 3. 6 级看俱乐部里的位置：没到“崭露头角”最高 5+；6+ 还要有比赛或青训经历
        if rating >= 6 - third - 0.01, let standingQuestion = question("standing") {
            if let standing = value(standingQuestion) {
                rating = min(standing, rating + third)
                limitingGate = nil
                if rating >= 6 + third - 0.01 && option("experience") < 3 {
                    rating = 6
                    limitingGate = String(localized: "想到 6+：要有比赛或青训经历")
                }
            } else {
                rating = 5 + third
                limitingGate = String(localized: "想到 6−：要在你常打的俱乐部里排进最强的那几个")
            }
        }

        // 4. 经历保底（回归球友减 1 级）
        var floor = question("experience").flatMap(value) ?? 1
        if isReturning { floor -= 1 }
        let final = toThirds(min(max(rating, floor, 1 - third), maxTier.rating))
        let needsCalibration = floor - rating >= 2 - 0.01

        return SkillAssessmentResult(tier: min(SkillTier(rating: final), maxTier), needsCalibration: needsCalibration,
                                     isReturning: isReturning, suggestsVerification: suggestsVerification,
                                     limitingGate: floor > rating ? nil : limitingGate, dimensions: technique)
    }

    #if DEBUG
    /// 演示：典型的中级球友（主动球不错、反手和网前还差一点，定出 4，截图用）
    static let demoAnswers: [String: Int] = [
        "clear": 4, "smash": 4, "drop": 4, "backhand": 2, "net": 3, "drive": 3, "footwork": 4,
        "passive": 2, "doubles": 2, "stability": 3, "tactics": 2, "standing": 1, "experience": 2, "recency": 0
    ]
    #endif
}
