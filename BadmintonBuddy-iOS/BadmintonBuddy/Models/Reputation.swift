import Foundation

// MARK: - 声誉评分

/// 由赛后评价聚合得到的声誉数据。
///
/// 展示规则（见 docs/DESIGN.md §12）：
/// - 球品分、信誉分只在内部用于排序和审核，任何人（包括本人）都看不到数字；
/// - 本人看到自己的客观记录：准时率、爽约、临时取消、水平校准；
/// - 别人只看到正面标签和“靠谱”徽章；标签要 ≥5 位不同球友、≥3 场后才出现，每月统一刷新一次，
///   避免从变化反推出是谁评的。
struct ReputationScore: Codable, Hashable {
    /// 有效评价次数（过期问卷不计入）
    var evaluationCount: Int
    /// 球友评价的平均水平 (1-9)
    var peerLevelAverage: Double
    /// 球友评价与本人自评的平均偏差（越小越“如实”）
    var averageSkillDeviation: Double
    /// 准时率 0-100
    var punctualityPercentage: Double
    /// 球品平均分 1-5（仅内部使用，不展示）
    var averageCharacterRating: Double
    /// 对外展示的正面标签（月度快照）
    var publicTags: [SurveyTag] = []
    var publishedAt: Date?

    static let newPlayerThreshold = 5
    /// 正面标签对外展示的门槛：不同评价人数、场次
    static let publicMinimumRaters = 5
    static let publicMinimumSessions = 3
    /// 一个标签至少要有几位不同球友给过才展示
    static let tagMinimumRaters = 2

    static let empty = ReputationScore(
        evaluationCount: 0,
        peerLevelAverage: 0,
        averageSkillDeviation: 0,
        punctualityPercentage: 100,
        averageCharacterRating: 0
    )

    /// 评价少于 5 次视为新球友
    var isNewPlayer: Bool { evaluationCount < Self.newPlayerThreshold }

    /// 水平准确度 0-100（偏差 0 级 = 100，偏差 ≥3 级 = 0）
    var skillAccuracyPercentage: Double {
        guard evaluationCount > 0 else { return 100 }
        return max(0, 1 - averageSkillDeviation / 3) * 100
    }

    /// 综合信誉分 0-100：准时 40% + 球品 35% + 水平准确 25%
    var compositeScore: Int {
        guard evaluationCount > 0 else { return 0 }
        let character = averageCharacterRating / 5 * 100
        let value = 0.40 * punctualityPercentage + 0.35 * character + 0.25 * skillAccuracyPercentage
        return Int(value.rounded())
    }

    var punctualityText: String {
        evaluationCount == 0 ? "—" : "\(Int(punctualityPercentage.rounded()))%"
    }

    var deviationText: String {
        evaluationCount == 0 ? "—" : String(format: "±%.1f", averageSkillDeviation)
    }

    /// 加入一次新的评价（增量平均）
    /// - Parameters:
    ///   - survey: 新问卷
    ///   - selfReportedLevel: 被评价者当时的自评等级
    func adding(_ survey: MatchSurvey, selfReportedLevel: Int) -> ReputationScore {
        let n = Double(evaluationCount)
        let next = n + 1
        let deviation = abs(Double(survey.skillRating - selfReportedLevel))
        return ReputationScore(
            evaluationCount: evaluationCount + 1,
            peerLevelAverage: (peerLevelAverage * n + Double(survey.skillRating)) / next,
            averageSkillDeviation: (averageSkillDeviation * n + deviation) / next,
            punctualityPercentage: (punctualityPercentage * n + (survey.wasPunctual ? 100 : 0)) / next,
            averageCharacterRating: (averageCharacterRating * n + Double(survey.characterRating)) / next,
            publicTags: publicTags,
            publishedAt: publishedAt
        )
    }

    /// 由一组问卷完整计算声誉
    static func aggregate(_ surveys: [MatchSurvey], selfReportedLevel: Int) -> ReputationScore {
        surveys.reduce(.empty) { $0.adding($1, selfReportedLevel: selfReportedLevel) }
    }

    /// 计算对外展示的正面标签：满足人数/场次门槛后，取至少 2 位不同球友给过的前 3 个
    static func publicTags(from surveys: [MatchSurvey]) -> [SurveyTag] {
        let raters = Set(surveys.map(\.evaluatorId))
        let sessions = Set(surveys.map(\.matchId))
        guard raters.count >= publicMinimumRaters, sessions.count >= publicMinimumSessions else { return [] }
        var ratersByTag: [SurveyTag: Set<String>] = [:]
        for survey in surveys {
            for tag in survey.tags { ratersByTag[tag, default: []].insert(survey.evaluatorId) }
        }
        return ratersByTag
            .filter { $0.value.count >= tagMinimumRaters }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return (SurveyTag.allCases.firstIndex(of: lhs.key) ?? 0) < (SurveyTag.allCases.firstIndex(of: rhs.key) ?? 0)
            }
            .prefix(3)
            .map(\.key)
    }

    /// 60 天内 ≥3 位不同球友提到的问题（只私下提醒本人）
    static func recurringIssues(in surveys: [MatchSurvey], now: Date = Date()) -> [SurveyIssue] {
        let recent = surveys.filter { now.timeIntervalSince($0.submittedAt) <= 60 * 86400 }
        var ratersByIssue: [SurveyIssue: Set<String>] = [:]
        for survey in recent {
            for issue in survey.issues { ratersByIssue[issue, default: []].insert(survey.evaluatorId) }
        }
        return SurveyIssue.allCases.filter { (ratersByIssue[$0]?.count ?? 0) >= 3 }
    }
}
