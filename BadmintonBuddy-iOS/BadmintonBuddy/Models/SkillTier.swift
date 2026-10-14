import Foundation

// MARK: - 细分档位：每级分 −、本级、+ 三档（1− … 9+，共 27 档）
//
// 等级之间差距太大时（尤其是高水平），同一级里的人也打不到一起。
// 和 NTRP（0.5 一档）、UTR / DUPR（小数）一样，我们用连续分值记录水平，
// 显示时取最近的三分之一档：4− = 3.67，4 = 4.00，4+ = 4.33。
// −：刚达到本级的标准，还不稳定；+：本级的动作很稳定，并开始具备下一级的部分能力。

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
            case .minus: return "刚达到这一级，部分动作还不稳定"
            case .base: return "这一级的动作都能稳定做到"
            case .plus: return "这一级很稳定，已经有下一级的部分能力"
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

    /// 档位名称：1–6 级用本级名称；7 级起每档差距大，单独命名
    var name: String {
        switch (level, modifier) {
        case (7, .base): return "地区高手"
        case (7, .plus): return "地区精英"
        case (8, .minus): return "州级精英"
        case (8, .base): return "国家级"
        case (8, .plus): return "国家顶尖"
        case (9, .minus): return "国际选手"
        case (9, .base): return "国际职业"
        case (9, .plus): return "世界顶尖"
        default: return SkillLevel.name(for: level)
        }
    }

    /// “Lv.4+ 中级”“Lv.9+ 世界顶尖”
    var displayText: String { "\(text) \(name)" }

    /// 读屏：“4 级加”
    var spokenText: String {
        switch modifier {
        case .minus: return "\(level) 级减"
        case .base: return "\(level) 级"
        case .plus: return "\(level) 级加"
        }
    }

    func offset(by steps: Int) -> SkillTier { SkillTier(index: index + steps) }

    /// “7 到 8+”（不用连字符，避免和 − 混在一起）
    static func rangeText(_ lower: SkillTier, _ upper: SkillTier) -> String {
        lower == upper ? lower.code : "\(lower.code) 到 \(upper.code)"
    }

    /// 差几档（对方 − 我）
    func steps(to other: SkillTier) -> Int { other.index - index }

    /// “同水平”“高 1 档”“低 1 级”“高 1 级 1 档”
    static func differenceText(_ steps: Int) -> String {
        guard steps != 0 else { return "同水平" }
        let direction = steps > 0 ? "高" : "低"
        let levels = abs(steps) / 3
        let rest = abs(steps) % 3
        switch (levels, rest) {
        case (0, _): return "\(direction) \(rest) 档"
        case (_, 0): return "\(direction) \(levels) 级"
        default: return "\(direction) \(levels) 级 \(rest) 档"
        }
    }

    static let all: [SkillTier] = (0..<count).map(SkillTier.init(index:))

    static func < (lhs: SkillTier, rhs: SkillTier) -> Bool { lhs.index < rhs.index }
}
