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

/// 对“水平是否如实”的三选一校准（参考 Playtomic 对手校准）
enum LevelCalibration: String, CaseIterable, Identifiable, Hashable {
    case lower = "比标的低"
    case accurate = "差不多"
    case higher = "比标的高"

    var id: String { rawValue }

    func rating(from displayed: Int) -> Int {
        switch self {
        case .lower: return SkillLevel.clamp(displayed - 1)
        case .accurate: return SkillLevel.clamp(displayed)
        case .higher: return SkillLevel.clamp(displayed + 1)
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

struct MatchSurvey: Identifiable, Codable, Hashable {
    let id: String
    /// 对应的球局 ID
    let matchId: String
    let evaluatorId: String
    let evaluatedUserId: String
    /// 评价者认为对方的水平 (1-9)
    let skillRating: Int
    let wasPunctual: Bool
    let attendance: AttendanceAnswer
    /// 球品 (1-5)
    let characterRating: Int
    let tags: [SurveyTag]
    let submittedAt: Date

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
