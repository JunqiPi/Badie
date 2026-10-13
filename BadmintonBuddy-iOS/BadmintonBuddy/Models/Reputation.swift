import Foundation

// MARK: - 声誉评分

/// 由赛后评价聚合得到的声誉数据
struct ReputationScore: Codable, Hashable {
    /// 有效评价次数（过期问卷不计入）
    var evaluationCount: Int
    /// 球友评价的平均水平 (1-9)
    var peerLevelAverage: Double
    /// 球友评价与本人自评的平均偏差（越小越“如实”）
    var averageSkillDeviation: Double
    /// 准时率 0-100
    var punctualityPercentage: Double
    /// 球品平均分 1-5
    var averageCharacterRating: Double

    static let newPlayerThreshold = 5

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

    var characterText: String {
        evaluationCount == 0 ? "—" : String(format: "%.1f", averageCharacterRating)
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
            averageCharacterRating: (averageCharacterRating * n + Double(survey.characterRating)) / next
        )
    }

    /// 由一组问卷完整计算声誉
    static func aggregate(_ surveys: [MatchSurvey], selfReportedLevel: Int) -> ReputationScore {
        surveys.reduce(.empty) { $0.adding($1, selfReportedLevel: selfReportedLevel) }
    }
}
