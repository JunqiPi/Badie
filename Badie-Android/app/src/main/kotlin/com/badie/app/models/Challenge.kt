package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.ZoneId

// MARK: - 约战
//
// 点头像向某人发起一场单打挑战。对方可以接受或不理会：拒绝和超时对发起人显示的都是“未成行”，
// 不会让人尴尬。谁能挑战我由我自己决定（默认只接受水平相近的人）。
// 谁可以向我发起挑战（ChallengePolicy）在 Basics.kt。

@Serializable
enum class ChallengeStatus {
    @SerialName("pending") Pending,
    @SerialName("accepted") Accepted,
    @SerialName("declined") Declined,
    @SerialName("expired") Expired,
    @SerialName("withdrawn") Withdrawn,
}

@Serializable
data class Challenge(
    val id: String,
    val challengerId: String,
    val targetId: String,
    val court: Venue,
    val slot: TimeSlot,
    val message: String,
    val createdAt: Long,
    val status: ChallengeStatus,
    val respondedAt: Long? = null,
    val gameId: String? = null,
    /** 双打：发起人带的搭档；对方接受时再选自己的搭档 */
    val challengerPartnerId: String? = null,
    val targetPartnerId: String? = null,
) {
    val mode: GameMode get() = if (challengerPartnerId == null) GameMode.Singles else GameMode.Doubles

    val expiresAt: Long get() = minOf(createdAt + RESPONSE_WINDOW, slot.startTime)

    fun isExpired(now: Long = System.currentTimeMillis()): Boolean = status == ChallengeStatus.Pending && now >= expiresAt

    fun involves(userId: String): Boolean = userId in listOf(challengerId, targetId, challengerPartnerId, targetPartnerId)

    fun other(than: String): String = if (challengerId == than) targetId else challengerId

    companion object {
        /** 对方 48 小时内不回应就自动过期（毫秒） */
        const val RESPONSE_WINDOW = 48 * 3_600_000L
        const val MAX_OUTGOING_PENDING = 3
        const val MAX_INCOMING_PENDING = 3
        const val DAILY_LIMIT = 5
        /** 被拒或过期后，多久内不能再挑战同一个人 */
        const val COOLDOWN = 7 * 86_400_000L
        /** “水平相近”：相差不超过 1 级 */
        const val SIMILAR_LEVEL_RANGE = 1.0
        const val MESSAGE_LIMIT = 60
    }
}

/** 能不能向某人发起挑战；不能时给出原因 */
sealed interface ChallengeAvailability {
    data object Available : ChallengeAvailability
    data object NotAccepting : ChallengeAvailability
    data object FriendsOnly : ChallengeAvailability
    data object LevelOutOfRange : ChallengeAvailability
    data object TargetBusy : ChallengeAvailability
    data object AlreadyPending : ChallengeAvailability
    data class Cooldown(val until: Long) : ChallengeAvailability
    data object TooManyOutgoing : ChallengeAvailability
    data object DailyLimitReached : ChallengeAvailability
    data object Unavailable : ChallengeAvailability

    fun reason(zone: ZoneId = ZoneId.systemDefault()): String? = when (this) {
        Available -> null
        NotAccepting -> tr("TA 暂不接受挑战")
        FriendsOnly -> tr("TA 只接受球友的挑战")
        LevelOutOfRange -> tr("TA 只接受水平相近的挑战")
        TargetBusy -> tr("TA 待处理的挑战已满，晚点再来")
        AlreadyPending -> tr("已经向 TA 发出挑战，等回应中")
        is Cooldown -> tr("%@ 之后才能再次挑战 TA", DateText.shortDay(until, zone))
        TooManyOutgoing -> tr("你同时最多发出 %lld 个挑战", Challenge.MAX_OUTGOING_PENDING)
        DailyLimitReached -> tr("今天的挑战次数用完了")
        Unavailable -> tr("暂时无法挑战 TA")
    }
}
