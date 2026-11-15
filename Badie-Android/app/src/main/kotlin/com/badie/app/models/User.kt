package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import java.util.Locale
import kotlin.math.abs

/** 头像：照片，或“首字 / 表情 + 马卡龙底色” */
data class Avatar(
    /** 表情或单字；为空时用昵称的第一个字 */
    val symbol: String,
    val paletteIndex: Int,
    /** 上传过照片时的版本号（每次重新上传 +1，用来刷新缓存）；为空表示没有照片 */
    val photoVersion: Int? = null,
    /** 卡片：没传背景照片时用的颜色（为空 = 按用户 ID 给的默认色） */
    val cardColor: CardColor? = null,
    /** 卡片背景照片的版本号；为空表示没有 */
    val cardPhotoVersion: Int? = null,
) {
    fun text(nickname: String): String = symbol.ifEmpty {
        if (nickname.isEmpty()) "🏸" else nickname.substring(0, nickname.offsetByCodePoints(0, 1))
    }

    companion object {
        fun default(seed: String): Avatar = Avatar("", abs(seed.stableHash) % 6)
    }
}

// MARK: - 隐私设置

data class PrivacySettings(
    /** 在常去球馆的“同馆常客”里显示我（默认开） */
    val showsAsRegular: Boolean = true,
    /** 允许同球群的球友给我发消息请求（默认开；关了以后只有好友能私信） */
    val allowsMessageRequests: Boolean = true,
    /** 谁可以向我发起挑战（默认所有人） */
    val challengePolicy: ChallengePolicy = ChallengePolicy.Everyone,
    /** 出现在场馆榜和周榜上（关了仍能看榜，但自己不上榜） */
    val showsOnLeaderboards: Boolean = true,
    /** 别人可以按昵称搜到我（默认开） */
    val findableByNickname: Boolean = true,
    /** 约球消息也发邮件（默认关，主要靠推送） */
    val emailAlerts: Boolean = false,
    /** 发了约球请求时，附近的人在发现页能看到我（默认开） */
    val showsWhenSearching: Boolean = true,
)

// MARK: - 用户

data class User(
    val id: String,
    val nickname: String,
    val phone: String,
    val gender: Gender = Gender.Unspecified,
    val bio: String = "",
    val avatar: Avatar = Avatar.default(id),
    /** 自评等级（1–9）。用 [User.create] 建的会夹在范围里 */
    val selfReportedLevel: Int,
    val totalGames: Int = 0,
    val wins: Int = 0,
    val joinDate: Long = 0,
    val location: Coordinate? = null,
    val lastActiveAt: Long = 0,
    val verificationStatus: VerificationStatus = VerificationStatus.Unverified,
    val reputation: ReputationScore = ReputationScore.empty,
    /** 客观履约记录（签到 / 爽约 / 临时取消） */
    val attendance: AttendanceRecord = AttendanceRecord.empty,
    val preferredMode: GameMode? = null,
    val privacy: PrivacySettings = PrivacySettings(),
    /** 定级问卷结果；跳过定级时为空 */
    val assessment: SkillAssessmentSummary? = null,
    /** 问卷给出的细分分值（4+ = 4.33）；为空时按整数等级 */
    val selfReportedRating: Double? = null,
    /** 认证通过的档位分值（7− 起）；认证后它代替问卷分值，也是显示的上限 */
    val verifiedRating: Double? = null,
    /** 注册时跳过了定级问卷（暂按 Lv.3 匹配，之后在资料页补测） */
    val assessmentSkippedAt: Long? = null,
    /** 昵称后面的编号（昵称#0042）：昵称可以重名，昵称 + 编号不会 */
    val tag: Int? = null,
    /** 我的加球友链接里的码（只有自己的有） */
    val friendCode: String? = null,
) {
    /** 跳过了定级、还没补测 */
    val needsAssessment: Boolean get() = assessment == null && assessmentSkippedAt != null

    // MARK: 等级计算

    /** 球友评价占的权重 */
    val peerWeight: Double
        get() {
            // 问卷顶到 6+：要靠球友评价确认，同样加快校准
            val atQuestionnaireCap = verifiedRating == null && selfRating >= SkillAssessment.maxTier.rating - 0.01
            val calibrating = assessment?.needsCalibration == true || assessment?.isReturning == true || atQuestionnaireCap || needsAssessment
            return if (calibrating) CALIBRATING_PEER_WEIGHT else PEER_EVALUATION_WEIGHT
        }

    /** 问卷给出的分值（细分档位） */
    val selfRating: Double get() = selfReportedRating ?: selfReportedLevel.toDouble()

    /** 计算的起点：认证过用认证档位，否则用问卷分值 */
    val baseRating: Double get() = verifiedRating ?: selfRating

    /** 综合分值：评价满 5 次后 = 30% 问卷（或认证）+ 70% 球友评价（待校准、回归球友是 15% + 85%）；否则是起点分值 */
    val calculatedLevel: Double
        get() = if (reputation.isNewPlayer) baseRating else (1 - peerWeight) * baseRating + peerWeight * reputation.peerLevelAverage

    /** 显示的上限：没认证最高 7−；认证后最高就是认证的那一档 */
    val tierCap: SkillTier get() = verifiedRating?.let(SkillTier::ofRating) ?: VerificationStatus.unverifiedMaxTier

    /** 显示的细分档位：认证过的人，球友评价最多往下拉 1 档（伤病、状态下滑），不会被一两场打低 */
    val displayTier: SkillTier
        get() {
            val tier = minOf(SkillTier.ofRating(calculatedLevel), tierCap)
            return if (verifiedRating == null) tier else maxOf(tier, tierCap.offset(-1))
        }

    /** 认证通过：记下证据类型和档位（档位限制在这类证据的范围内） */
    fun applyingVerification(status: VerificationStatus, tier: SkillTier): User =
        if (status == VerificationStatus.Unverified) {
            copy(verificationStatus = VerificationStatus.Unverified, verifiedRating = null)
        } else {
            copy(verificationStatus = status, verifiedRating = tier.coerceIn(status.minTier, status.maxTier).rating)
        }

    /** 显示等级（整数，用于匹配的水平差） */
    val displayLevel: Int get() = displayTier.level

    /** “Lv.4+ 中级” */
    val displayLevelText: String get() = displayTier.displayText

    val isNewPlayer: Boolean get() = reputation.isNewPlayer

    /** “靠谱”徽章：打满 3 场、没有爽约、临时取消不超过 1 次（只看客观履约记录） */
    val isReliable: Boolean get() = attendance.gamesPlayed >= 3 && attendance.noShows == 0 && attendance.lateCancellations <= 1

    /** 对别人显示的场次：分档（“20+ 场”），不给精确数字 */
    val gamesBand: String
        get() = when {
            totalGames <= 0 -> tr("还没打过")
            totalGames < 5 -> tr("1–4 场")
            totalGames < 20 -> tr("5+ 场")
            totalGames < 50 -> tr("20+ 场")
            else -> tr("50+ 场")
        }

    /** 列表里对别人展示的一句话：只有正面信息，没有分数（“靠谱 · 20+ 场”） */
    val publicSummary: String
        get() = buildList {
            if (isNewPlayer) add(tr("新球友")) else if (isReliable) add(tr("靠谱"))
            add(gamesBand)
            reputation.publicTags.firstOrNull()?.let { add(it.title) }
        }.joinToString(" · ")

    val winRate: Double get() = if (totalGames > 0) wins.toDouble() / totalGames * 100 else 0.0

    val avatarText: String get() = avatar.text(nickname)

    /** 昵称后面显示的编号：#0042（演示数据没有编号，按 ID 算一个） */
    val tagText: String get() = String.format(Locale.ROOT, "#%04d", tag ?: (abs(id.stableHash) % 9999 + 1))

    /** 我的加球友链接 */
    val friendLink: String? get() = friendCode?.let { "https://badie.rsvp/add/$it/" }

    /** 卡片背景的颜色：自己选的，没选就按 ID 给一个 */
    val cardColor: CardColor get() = avatar.cardColor ?: CardColor.default(id)

    companion object {
        const val PEER_EVALUATION_WEIGHT = 0.7
        /** 待校准（经历和技术对不上）或回归球友：球友评价占 85%，更快校准到真实水平 */
        const val CALIBRATING_PEER_WEIGHT = 0.85
        /** 打满几场才能给同球群的人发消息请求（防小号骚扰） */
        const val GAMES_BEFORE_MESSAGE_REQUESTS = 3

        /** 自评等级夹在 1–9 里 */
        fun create(id: String, nickname: String, phone: String = "", selfReportedLevel: Int): User =
            User(id = id, nickname = nickname, phone = phone, selfReportedLevel = SkillLevel.clamp(selfReportedLevel))
    }
}
