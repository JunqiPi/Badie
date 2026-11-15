package com.badie.app.models

import java.util.Locale
import kotlin.math.abs

// MARK: - 声誉评分

/**
 * 由赛后评价聚合得到的声誉数据。分数只在内部用于排序和审核，不对任何人展示；
 * 对外只显示正面标签（月度快照，避免从变化反推出是谁评的）。
 */
data class ReputationScore(
    /** 有效评价次数（过期问卷不计入） */
    val evaluationCount: Int,
    /** 球友评价的平均水平（1–9） */
    val peerLevelAverage: Double,
    /** 球友评价和本人自评的平均偏差（越小越“如实”） */
    val averageSkillDeviation: Double,
    /** 准时率 0–100 */
    val punctualityPercentage: Double,
    /** 球品平均分 1–5（只在内部用，不展示） */
    val averageCharacterRating: Double,
    /** 对外展示的正面标签（月度快照） */
    val publicTags: List<SurveyTag> = emptyList(),
    val publishedAt: Long? = null,
) {
    /** 评价少于 5 次算新球友 */
    val isNewPlayer: Boolean get() = evaluationCount < NEW_PLAYER_THRESHOLD

    /** 水平准确度 0–100（偏差 0 级 = 100，偏差 ≥3 级 = 0） */
    val skillAccuracyPercentage: Double
        get() = if (evaluationCount > 0) maxOf(0.0, 1 - averageSkillDeviation / 3) * 100 else 100.0

    /** 综合信誉分 0–100：准时 40% + 球品 35% + 水平准确 25% */
    val compositeScore: Int
        get() {
            if (evaluationCount == 0) return 0
            val character = averageCharacterRating / 5 * 100
            return roundHalfAway(0.40 * punctualityPercentage + 0.35 * character + 0.25 * skillAccuracyPercentage).toInt()
        }

    val punctualityText: String get() = if (evaluationCount == 0) "—" else "${roundHalfAway(punctualityPercentage).toInt()}%"

    val deviationText: String get() = if (evaluationCount == 0) "—" else String.format(Locale.ROOT, "±%.1f", averageSkillDeviation)

    /** 增量平均加入一次评价；selfRating 是被评价者当时的问卷分值 */
    fun adding(survey: MatchSurvey, selfRating: Double): ReputationScore {
        val n = evaluationCount.toDouble()
        val next = n + 1
        val deviation = abs(survey.ratingValue - selfRating)
        return copy(
            evaluationCount = evaluationCount + 1,
            peerLevelAverage = (peerLevelAverage * n + survey.ratingValue) / next,
            averageSkillDeviation = (averageSkillDeviation * n + deviation) / next,
            punctualityPercentage = (punctualityPercentage * n + (if (survey.wasPunctual) 100 else 0)) / next,
            averageCharacterRating = (averageCharacterRating * n + survey.characterRating) / next,
        )
    }

    companion object {
        const val NEW_PLAYER_THRESHOLD = 5
        /** 正面标签对外展示的门槛：不同评价人数、场次 */
        const val PUBLIC_MINIMUM_RATERS = 5
        const val PUBLIC_MINIMUM_SESSIONS = 3
        /** 一个标签至少要有几位不同球友给过才展示 */
        const val TAG_MINIMUM_RATERS = 2

        val empty = ReputationScore(0, 0.0, 0.0, 100.0, 0.0)

        /** 由一组问卷完整计算声誉 */
        fun aggregate(surveys: List<MatchSurvey>, selfRating: Double): ReputationScore =
            surveys.fold(empty) { score, survey -> score.adding(survey, selfRating) }

        /** 对外展示的正面标签：满足人数、场次门槛后，取至少 2 位不同球友给过的前 3 个 */
        fun publicTags(surveys: List<MatchSurvey>): List<SurveyTag> {
            val raters = surveys.map { it.evaluatorId }.toSet()
            val sessions = surveys.map { it.matchId }.toSet()
            if (raters.size < PUBLIC_MINIMUM_RATERS || sessions.size < PUBLIC_MINIMUM_SESSIONS) return emptyList()
            val ratersByTag = HashMap<SurveyTag, MutableSet<String>>()
            for (survey in surveys) for (tag in survey.tags) ratersByTag.getOrPut(tag) { HashSet() }.add(survey.evaluatorId)
            return ratersByTag.filterValues { it.size >= TAG_MINIMUM_RATERS }.entries
                .sortedWith(compareByDescending<Map.Entry<SurveyTag, Set<String>>> { it.value.size }.thenBy { it.key.ordinal })
                .take(3).map { it.key }
        }

        /** 60 天内 ≥3 位不同球友提到的问题（只私下提醒本人） */
        fun recurringIssues(surveys: List<MatchSurvey>, now: Long): List<SurveyIssue> {
            val ratersByIssue = HashMap<SurveyIssue, MutableSet<String>>()
            for (survey in surveys) {
                if (now - survey.submittedAt > 60L * 86_400_000) continue
                for (issue in survey.issues) ratersByIssue.getOrPut(issue) { HashSet() }.add(survey.evaluatorId)
            }
            return SurveyIssue.entries.filter { (ratersByIssue[it]?.size ?: 0) >= 3 }
        }
    }
}
