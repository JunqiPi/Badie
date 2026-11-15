package com.badie.app.models

import com.badie.app.l10n.L10n.tr

// MARK: - 赛后评价

/** 到场情况（客观履约记录的主要来源）。rawValue 是存下来的值，不能改；显示用 title */
enum class AttendanceAnswer(val rawValue: String) {
    OnTime("准时到"), Late("迟到了"), NoShow("没来");

    val title: String
        get() = when (this) {
            OnTime -> tr("准时到")
            Late -> tr("迟到了")
            NoShow -> tr("没来")
        }

    val wasPunctual: Boolean get() = this == OnTime
}

/** 对“水平是否如实”的三选一校准：高低各移动一档（1/3 级） */
enum class LevelCalibration(val rawValue: String) {
    Lower("比标的低"), Accurate("差不多"), Higher("比标的高");

    val title: String
        get() = when (this) {
            Lower -> tr("比标的低")
            Accurate -> tr("差不多")
            Higher -> tr("比标的高")
        }

    fun rating(displayed: SkillTier): SkillTier = when (this) {
        Lower -> displayed.offset(-1)
        Accurate -> displayed
        Higher -> displayed.offset(1)
    }
}

/** 预设评价标签（只做匿名汇总，不展示单条评价） */
enum class SurveyTag(val rawValue: String) {
    Friendly("友善好相处"), Punctual("守时靠谱"), Skilled("球技扎实"), Patient("愿意带新手"), FairPlay("不抢球"), GreatPartner("默契搭档");

    val title: String
        get() = when (this) {
            Friendly -> tr("友善好相处")
            Punctual -> tr("守时靠谱")
            Skilled -> tr("球技扎实")
            Patient -> tr("愿意带新手")
            FairPlay -> tr("不抢球")
            GreatPartner -> tr("默契搭档")
        }
}

/**
 * 需要对方注意的地方：不公开、不计分。
 * 60 天内有 ≥3 位不同球友提到同一点时，只私下提醒本人（不告诉是谁说的）。
 */
enum class SurveyIssue(val rawValue: String) {
    UnsafePlay("动作危险/不注意安全"), Rude("言语不友善"), Hogging("抢球/不轮换"), Unpaid("AA 没结清");

    val title: String
        get() = when (this) {
            UnsafePlay -> tr("动作危险/不注意安全")
            Rude -> tr("言语不友善")
            Hogging -> tr("抢球/不轮换")
            Unpaid -> tr("AA 没结清")
        }

    /** 私下提醒的措辞（建议式，不指责） */
    val nudge: String
        get() = when (this) {
            UnsafePlay -> tr("打球时多留意身边的人，动作幅度注意安全。")
            Rude -> tr("场上沟通可以再温和一点，大家都是来开心打球的。")
            Hogging -> tr("双打时注意轮换和分工，让搭档也有球打。")
            Unpaid -> tr("打完记得及时结清 AA，可以在球局里标记已付。")
        }
}

data class MatchSurvey(
    val id: String,
    val matchId: String,
    val evaluatorId: String,
    val evaluatedUserId: String,
    /** 评价者认为对方的水平（1–9，整数级） */
    val skillRating: Int,
    val wasPunctual: Boolean,
    val attendance: AttendanceAnswer,
    /** 球品（1–5） */
    val characterRating: Int,
    val tags: List<SurveyTag>,
    /** 提交时间，毫秒 */
    val submittedAt: Long,
    /** 需要对方注意的地方（只用于私下提醒） */
    val issues: List<SurveyIssue> = emptyList(),
    /** 还想再约 TA（双方都选了才告诉双方） */
    val wantsRematch: Boolean = false,
    /** 精确到档的分值（4+ = 4.33）；为空时按整数级 */
    val skillRatingValue: Double? = null,
) {
    val ratingValue: Double get() = skillRatingValue ?: skillRating.toDouble()

    val isValid: Boolean get() = skillRating in SKILL_RATING_RANGE && characterRating in CHARACTER_RATING_RANGE

    companion object {
        val SKILL_RATING_RANGE = 1..9
        val CHARACTER_RATING_RANGE = 1..5
    }
}

/** 待填写的问卷（每位对手一份，48 小时内有效） */
data class PendingSurvey(
    val id: String,
    val matchId: String,
    val evaluatorId: String,
    val opponentId: String,
    val opponentNickname: String,
    val opponentLevel: Int,
    val opponentAvatar: Avatar,
    val courtName: String,
    val matchDate: Long,
    val expiresAt: Long,
    /** 对方当时显示的细分档位分值 */
    val opponentRating: Double? = null,
) {
    val opponentTier: SkillTier get() = SkillTier.ofRating(opponentRating ?: opponentLevel.toDouble())

    fun isExpired(now: Long): Boolean = now > expiresAt

    val opponentAvatarText: String get() = opponentAvatar.text(opponentNickname)

    companion object {
        const val VALIDITY_MILLIS = 48L * 3_600_000
    }
}

// MARK: - 履约档案（客观数据：签到 / 爽约 / 临时取消）

data class AttendanceRecord(val gamesPlayed: Int, val noShows: Int, val lateCancellations: Int) {
    /** 履约率：完成场次 / (完成 + 爽约 + 临时取消) */
    val reliabilityPercentage: Int
        get() {
            val total = gamesPlayed + noShows + lateCancellations
            return if (total > 0) roundHalfAway(gamesPlayed.toDouble() / total * 100).toInt() else 100
        }

    /** 分级处理（爽约记 2 分，临时取消记 1 分）：0–1 正常；2–3 提醒；4–5 需预付；≥6 暂停匹配 */
    val standing: Standing
        get() = when (noShows * 2 + lateCancellations) {
            in 0..1 -> Standing.Good
            in 2..3 -> Standing.Warned
            in 4..5 -> Standing.PrepayRequired
            else -> Standing.Suspended
        }

    enum class Standing {
        Good, Warned, PrepayRequired, Suspended;

        val title: String
            get() = when (this) {
                Good -> tr("履约良好")
                Warned -> tr("已提醒")
                PrepayRequired -> tr("需预付")
                Suspended -> tr("暂停匹配")
            }

        val message: String
            get() = when (this) {
                Good -> tr("保持准时到场，你的履约记录会让更多球友愿意和你约球。")
                Warned -> tr("近期有爽约或临时取消记录，请尽量提前 2 小时取消。")
                PrepayRequired -> tr("爽约次数较多，之后约球需先付 AA 才能确认。")
                Suspended -> tr("爽约次数过多，快速匹配已暂停 7 天。")
            }
    }

    companion object {
        val empty = AttendanceRecord(0, 0, 0)
    }
}
