import Foundation

// MARK: - 细分档位：每级分 −、本级、+ 三档（1− … 9+，共 27 档）
//
// 水平用连续分值记录，显示时取最近的三分之一档：4− = 3.67，4 = 4.00，4+ = 4.33。

struct SkillTier: Hashable, Comparable, Codable, Identifiable {
    enum Modifier: Int, Codable, Hashable {
        case minus = -1
        case base = 0
        case plus = 1

        var symbol: String {
            switch self {
            case .minus: return "−"
            case .base: return ""
            case .plus: return "+"
            }
        }

        /// 1–7 级里 −/本级/+ 的通用含义
        var meaning: String {
            switch self {
            case .minus: return String(localized: "刚达到这一级，部分动作还不稳定")
            case .base: return String(localized: "这一级的动作都能稳定做到")
            case .plus: return String(localized: "这一级很稳定，已经有下一级的部分能力")
            }
        }
    }

    let level: Int
    let modifier: Modifier

    static let count = 27

    init(level: Int, modifier: Modifier = .base) {
        self.level = SkillLevel.clamp(level)
        self.modifier = modifier
    }

    /// 第几档（0 = 1−，26 = 9+）
    init(index: Int) {
        let clamped = min(max(index, 0), Self.count - 1)
        level = clamped / 3 + 1
        modifier = Modifier(rawValue: clamped % 3 - 1) ?? .base
    }

    /// 由连续分值取最近的一档
    init(rating: Double) {
        self.init(index: Int((rating * 3).rounded()) - 2)
    }

    var index: Int { (level - 1) * 3 + modifier.rawValue + 1 }

    var id: Int { index }

    /// 连续分值：4− = 3.67，4 = 4.00，4+ = 4.33
    var rating: Double { Double(level) + Double(modifier.rawValue) / 3 }

    /// “4+”
    var code: String { "\(level)\(modifier.symbol)" }

    /// “Lv.4+”
    var text: String { "Lv.\(code)" }

    /// 档位名称：1–5 级用本级名称；6 级起每档差距大，单独命名
    var name: String {
        switch (level, modifier) {
        case (6, .minus): return String(localized: "崭露头角")
        case (6, .plus): return String(localized: "俱乐部顶尖")
        case (7, .minus): return String(localized: "准州级")
        case (7, .base): return String(localized: "州级选手")
        case (7, .plus): return String(localized: "州级精英")
        case (8, .minus): return String(localized: "准国家级")
        case (8, .base): return String(localized: "国家级")
        case (8, .plus): return String(localized: "国家顶尖")
        case (9, .minus): return String(localized: "国际选手")
        case (9, .base): return String(localized: "国际职业")
        case (9, .plus): return String(localized: "世界顶尖")
        default: return SkillLevel.name(for: level)
        }
    }

    /// “Lv.4+ 中级”“Lv.9+ 世界顶尖”
    var displayText: String { "\(text) \(name)" }

    /// 读屏：“4 级加”
    var spokenText: String {
        switch modifier {
        case .minus: return String(localized: "\(level) 级减")
        case .base: return String(localized: "\(level) 级")
        case .plus: return String(localized: "\(level) 级加")
        }
    }

    func offset(by steps: Int) -> SkillTier { SkillTier(index: index + steps) }

    /// “7 到 8+”（不用连字符，避免和 − 混在一起）
    static func rangeText(_ lower: SkillTier, _ upper: SkillTier) -> String {
        lower == upper ? lower.code : String(localized: "\(lower.code) 到 \(upper.code)")
    }

    /// 差几档（对方 − 我）
    func steps(to other: SkillTier) -> Int { other.index - index }

    /// “同水平”“高 1 档”“低 1 级”“高 1 级 1 档”
    static func differenceText(_ steps: Int) -> String {
        guard steps != 0 else { return String(localized: "同水平") }
        let direction = steps > 0
            ? String(localized: "高", comment: "水平差：对方比我高")
            : String(localized: "低", comment: "水平差：对方比我低")
        let levels = abs(steps) / 3
        let rest = abs(steps) % 3
        switch (levels, rest) {
        case (0, _): return String(localized: "\(direction) \(rest) 档")
        case (_, 0): return String(localized: "\(direction) \(levels) 级")
        default: return String(localized: "\(direction) \(levels) 级 \(rest) 档")
        }
    }

    static let all: [SkillTier] = (0..<count).map(SkillTier.init(index:))

    static func < (lhs: SkillTier, rhs: SkillTier) -> Bool { lhs.index < rhs.index }
}
