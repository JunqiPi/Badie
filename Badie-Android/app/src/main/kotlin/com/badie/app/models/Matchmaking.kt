package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.ZoneId

// MARK: - 匹配时间规则
//
// 普通局：开赛前 2 小时锁定（与“开赛前 2 小时内取消算临时取消”一致），确认期限随距开赛的时间放宽。
// 临时局：开赛不到 2.5 小时，只匹配附近此刻也在找人的球友，确认期限 5–10 分钟，最晚开赛前 20 分钟确认完。
// 时间都是毫秒。

object MatchTiming {
    /** 普通局锁定：开赛前 2 小时必须全部确认 */
    const val LOCK_LEAD = 2 * 3_600_000L
    /** 开赛时间在这之内的请求按临时局处理 */
    const val LAST_MINUTE_THRESHOLD = 9_000_000L
    /** 发起请求最晚要在开赛前 30 分钟 */
    const val MINIMUM_LEAD = 30 * 60_000L
    /** 临时局最晚在开赛前 20 分钟确认完（留出路上时间） */
    const val LAST_MINUTE_CONFIRM_BEFORE = 20 * 60_000L
    /** 临时局只找附近的人（约 5 英里） */
    const val LAST_MINUTE_RADIUS_KM = 8.0

    /** 夜里（23:00–8:00）到期的确认顺延到早上 9 点，不让人半夜被催（仍不晚于锁定时间） */
    const val QUIET_HOURS_START = 23
    const val QUIET_HOURS_END = 8
    const val QUIET_HOURS_RESUME = 9

    fun isLastMinute(start: Long, now: Long = System.currentTimeMillis()): Boolean = start - now < LAST_MINUTE_THRESHOLD

    fun canRequest(start: Long, now: Long = System.currentTimeMillis()): Boolean = start - now >= MINIMUM_LEAD

    /** 锁定时间：到点必须全部确认，没约成就结束 */
    fun lock(start: Long, lastMinute: Boolean): Long = start - (if (lastMinute) LAST_MINUTE_CONFIRM_BEFORE else LOCK_LEAD)

    /** 少于这个确认时间就不再发出新提议（来不及回复） */
    fun minimumResponseWindow(lastMinute: Boolean): Long = if (lastMinute) 3 * 60_000L else 10 * 60_000L

    /** 确认期限：开赛越远给得越长，但不晚于锁定时间 */
    fun respondBy(start: Long, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Long {
        val lead = start - now
        if (isLastMinute(start, now)) {
            val window = if (lead < 3_600_000L) 5 * 60_000L else 10 * 60_000L
            return minOf(now + window, start - LAST_MINUTE_CONFIRM_BEFORE)
        }
        val window = when {
            lead >= 26 * 3_600_000L -> 12 * 3_600_000L
            lead >= 6 * 3_600_000L -> 2 * 3_600_000L
            else -> 30 * 60_000L
        }
        val lock = start - LOCK_LEAD
        return minOf(skippingQuietHours(now + window, zone), lock)
    }

    /** 落在夜里的时间顺延到早上 9 点 */
    fun skippingQuietHours(date: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val hour = date.zoned(zone).hour
        if (hour < QUIET_HOURS_START && hour >= QUIET_HOURS_END) return date
        val day = if (hour >= QUIET_HOURS_START) addingDays(date, 1, zone) else date
        return settingTime(day, QUIET_HOURS_RESUME, 0, zone)
    }

    /** 剩余时间文案："还剩 1 小时 52 分" / "还剩 4 分钟" */
    fun remainingText(until: Long, now: Long = System.currentTimeMillis()): String {
        val seconds = maxOf(0L, (until - now) / 1000)
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        if (hours > 0) return if (minutes > 0) tr("还剩 %lld 小时 %lld 分", hours, minutes) else tr("还剩 %lld 小时", hours)
        return tr("还剩 %lld 分钟", maxOf(1L, minutes))
    }
}

// MARK: - 约球请求（挂在后台，找到人就通知）

@Serializable
data class MatchTicket(
    val id: String,
    val userId: String,
    val mode: GameMode,
    val slot: TimeSlot,
    /** 可接受的球馆 */
    val courtIds: List<String>,
    val skillTolerance: Int,
    val radiusKm: Double,
    /** 发起时的位置 */
    val origin: Coordinate,
    /** 符合条件的提议直接视为接受 */
    val autoAccept: Boolean,
    val isLastMinute: Boolean,
    val status: Status,
    val createdAt: Long,
    /** 锁定时间（普通局开赛前 2 小时，临时局开赛前 20 分钟） */
    val deadline: Long,
    /** 因为别人没确认被退回：下一轮优先 */
    val hasPriority: Boolean,
    /** 不再推荐的人（我拒绝过的、没确认的） */
    val excludedUserIds: List<String>,
    /** 项目：男单女单男双女双、混双；null = 不限 */
    val event: PlayEvent? = null,
) {
    @Serializable
    sealed interface Status {
        /** 在找 */
        @Serializable @SerialName("searching") data object Searching : Status
        /** 有了提议，等大家确认 */
        @Serializable @SerialName("offered") data class Offered(val offerId: String) : Status
        /** 已成局 */
        @Serializable @SerialName("matched") data class Matched(val gameId: String) : Status
        /** 错过确认，暂停，等用户说“继续找” */
        @Serializable @SerialName("paused") data object Paused : Status
        /** 到锁定时间还没约成 */
        @Serializable @SerialName("expired") data object Expired : Status
        @Serializable @SerialName("cancelled") data object Cancelled : Status
    }

    val isActive: Boolean get() = status == Status.Searching || status is Status.Offered

    val offerId: String? get() = (status as? Status.Offered)?.offerId

    val gameId: String? get() = (status as? Status.Matched)?.gameId
}

// MARK: - 匹配提议（所有人都确认才成局）

@Serializable
data class MatchOffer(
    val id: String,
    val mode: GameMode,
    val slot: TimeSlot,
    val commonOverlap: TimeSlot,
    val court: Venue,
    val teams: List<List<String>>,
    val seats: List<Seat>,
    val cost: CostSplit,
    val compatibility: Int,
    val createdAt: Long,
    /** 锁定时间：到点没全部确认就作废 */
    val lockAt: Long,
    val isLastMinute: Boolean,
    val status: Status,
    /** 已补位次数 */
    val backfillCount: Int,
) {
    @Serializable
    enum class Response {
        @SerialName("pending") Pending,
        @SerialName("accepted") Accepted,
        @SerialName("declined") Declined,
        @SerialName("expired") Expired,
    }

    @Serializable
    sealed interface Status {
        @Serializable @SerialName("open") data object Open : Status
        @Serializable @SerialName("confirmed") data class Confirmed(val gameId: String) : Status
        /** 没凑成（有人没确认且补不上） */
        @Serializable @SerialName("failed") data object Failed : Status
    }

    @Serializable
    data class Seat(
        val userId: String,
        /** 真实用户的请求（模拟球友为 null） */
        val ticketId: String?,
        val response: Response,
        /** 这个座位的确认期限（补位进来的人有自己的期限） */
        val respondBy: Long,
        val respondedAt: Long? = null,
    ) {
        /** 没来（拒绝或超时），等待补位 */
        val isVacant: Boolean get() = response == Response.Declined || response == Response.Expired
    }

    val playerIds: List<String> get() = seats.map { it.userId }

    /** 仍在局中的人（不含拒绝/超时的座位） */
    val activePlayerIds: List<String> get() = seats.filter { !it.isVacant }.map { it.userId }

    val vacantCount: Int get() = seats.count { it.isVacant }

    fun seat(userId: String): Seat? = seats.firstOrNull { it.userId == userId }

    val acceptedCount: Int get() = seats.count { it.response == Response.Accepted }

    val isFullyAccepted: Boolean get() = seats.all { it.response == Response.Accepted }

    val isOpen: Boolean get() = status == Status.Open

    val gameId: String? get() = (status as? Status.Confirmed)?.gameId

    companion object {
        const val MAXIMUM_BACKFILLS = 3
    }
}
