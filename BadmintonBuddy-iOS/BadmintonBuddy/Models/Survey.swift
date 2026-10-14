import Foundation

// MARK: - 赛后评价

/// 到场情况（客观履约记录的主要来源）
enum AttendanceAnswer: String, Codable, CaseIterable, Identifiable, Hashable {
    case onTime = "准时到"
    case late = "迟到了"
    case noShow = "没来"

    var id: String { rawValue }

    var wasPunctual: Bool { self == .onTime }
}

/// 对“水平是否如实”的三选一校准（参考 Playtomic 对手校准）：高低各一档（1/3 级），差得多可以精确调
enum LevelCalibration: String, CaseIterable, Identifiable, Hashable {
    case lower = "比标的低"
    case accurate = "差不多"
    case higher = "比标的高"

    var id: String { rawValue }

    func rating(from displayed: SkillTier) -> SkillTier {
        switch self {
        case .lower: return displayed.offset(by: -1)
        case .accurate: return displayed
        case .higher: return displayed.offset(by: 1)
        }
    }
}

/// 预设评价标签（只做匿名汇总，不展示单条评价）
enum SurveyTag: String, CaseIterable, Identifiable, Codable, Hashable {
    case friendly = "友善好相处"
    case punctual = "守时靠谱"
    case skilled = "球技扎实"
    case patient = "愿意带新手"
    case fairPlay = "不抢球"
    case greatPartner = "默契搭档"

    var id: String { rawValue }
}

/// 需要对方注意的地方：不公开、不计分。
/// 60 天内有 ≥3 位不同球友提到同一点时，只私下提醒本人（不告诉是谁说的）。
enum SurveyIssue: String, CaseIterable, Identifiable, Codable, Hashable {
    case unsafePlay = "动作危险/不注意安全"
    case rude = "言语不友善"
    case hogging = "抢球/不轮换"
    case unpaid = "AA 没结清"

    var id: String { rawValue }

    /// 私下提醒的措辞（建议式，不指责）
    var nudge: String {
        switch self {
        case .unsafePlay: return "打球时多留意身边的人，动作幅度注意安全。"
        case .rude: return "场上沟通可以再温和一点，大家都是来开心打球的。"
        case .hogging: return "双打时注意轮换和分工，让搭档也有球打。"
        case .unpaid: return "打完记得及时结清 AA，可以在球局里标记已付。"
        }
    }
}

struct MatchSurvey: Identifiable, Codable, Hashable {
    let id: String
    /// 对应的球局 ID
    let matchId: String
    let evaluatorId: String
    let evaluatedUserId: String
    /// 评价者认为对方的水平 (1-9，整数级)
    let skillRating: Int
    let wasPunctual: Bool
    let attendance: AttendanceAnswer
    /// 球品 (1-5)
    let characterRating: Int
    let tags: [SurveyTag]
    let submittedAt: Date
    /// 需要对方注意的地方（只用于私下提醒）
    var issues: [SurveyIssue] = []
    /// 还想再约 TA（双方都选了才告诉双方）
    var wantsRematch = false
    /// 精确到档的分值（4+ = 4.33）；老数据为空时用整数级
    var skillRatingValue: Double?

    var ratingValue: Double { skillRatingValue ?? Double(skillRating) }

    static let skillRatingRange = 1...9
    static let characterRatingRange = 1...5

    var isValid: Bool {
        Self.skillRatingRange.contains(skillRating) && Self.characterRatingRange.contains(characterRating)
    }
}

/// 待填写的问卷（每位对手一份，48 小时内有效）
struct PendingSurvey: Identifiable, Codable, Hashable {
    let id: String
    let matchId: String
    let evaluatorId: String
    let opponentId: String
    let opponentNickname: String
    let opponentLevel: Int
    let opponentAvatar: Avatar
    let courtName: String
    let matchDate: Date
    let expiresAt: Date
    /// 对方当时显示的细分档位分值
    var opponentRating: Double?

    var opponentTier: SkillTier { SkillTier(rating: opponentRating ?? Double(opponentLevel)) }

    static let validityDuration: TimeInterval = 48 * 3600

    func isExpired(now: Date = Date()) -> Bool { now > expiresAt }

    var opponentAvatarText: String {
        opponentAvatar.symbol.isEmpty ? (opponentNickname.first.map { String($0) } ?? "🏸") : opponentAvatar.symbol
    }
}

// MARK: - 履约档案（客观数据：签到 / 爽约 / 临时取消）

struct AttendanceRecord: Codable, Hashable {
    var gamesPlayed: Int
    var noShows: Int
    var lateCancellations: Int

    static let empty = AttendanceRecord(gamesPlayed: 0, noShows: 0, lateCancellations: 0)

    /// 履约率：完成场次 / (完成 + 爽约 + 临时取消)
    var reliabilityPercentage: Int {
        let total = gamesPlayed + noShows + lateCancellations
        guard total > 0 else { return 100 }
        return Int((Double(gamesPlayed) / Double(total) * 100).rounded())
    }

    /// 分级处理（爽约记 2 分，临时取消记 1 分）：0-1 正常；2-3 提醒；4-5 需预付；≥6 暂停匹配
    var standing: Standing {
        let strikes = noShows * 2 + lateCancellations
        switch strikes {
        case 0...1: return .good
        case 2...3: return .warned
        case 4...5: return .prepayRequired
        default: return .suspended
        }
    }

    enum Standing: String, Codable, Hashable {
        case good, warned, prepayRequired, suspended

        var title: String {
            switch self {
            case .good: return "履约良好"
            case .warned: return "已提醒"
            case .prepayRequired: return "需预付"
            case .suspended: return "暂停匹配"
            }
        }

        var message: String {
            switch self {
            case .good: return "保持准时到场，你的履约记录会让更多球友愿意和你约球。"
            case .warned: return "近期有爽约或临时取消记录，请尽量提前 2 小时取消。"
            case .prepayRequired: return "爽约次数较多，之后约球需先付 AA 才能确认。"
            case .suspended: return "爽约次数过多，快速匹配已暂停 7 天。"
            }
        }
    }
}
