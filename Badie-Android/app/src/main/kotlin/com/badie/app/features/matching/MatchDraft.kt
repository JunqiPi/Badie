package com.badie.app.features.matching

import com.badie.app.l10n.L10n.tr
import com.badie.app.models.GameMode
import com.badie.app.models.PlayEvent
import com.badie.app.models.TimeSlot
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.TimeSlotValidationResult
import com.badie.app.models.isSameDay
import com.badie.app.models.startOfDay
import com.badie.app.models.zoned
import java.time.ZoneId

/** 匹配草稿（快速匹配设置），对应 iPhone MatchManager.swift 里的 MatchDraft。改的时候整份换掉（copy） */
data class MatchDraft(
    val mode: GameMode = GameMode.Singles,
    val day: Long = startOfDay(System.currentTimeMillis()),
    /** 从 0 点起的分钟数 */
    val startMinutes: Int = 19 * 60,
    val endMinutes: Int = 21 * 60,
    val courtIds: List<String> = emptyList(),
    /** 1、2 或 8(不限)；默认不限水平 */
    val skillTolerance: Int = MatchRequest.ANY_SKILL,
    /** 符合条件的提议直接替我接受（默认关闭） */
    val autoAccept: Boolean = false,
    /** 项目：男单女单男双女双、混双；null = 不限 */
    val event: PlayEvent? = null,
    /** 修改已有的请求：提交时换掉这个请求 */
    val replacingTicketId: String? = null,
) {
    fun slot(zone: ZoneId = ZoneId.systemDefault()): TimeSlot? =
        TimeSlot.on(day, startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60, zone)

    fun validation(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): TimeSlotValidationResult {
        val slot = slot(zone) ?: return TimeSlotValidationResult.Invalid(tr("时间无效"))
        return slot.validate(now, TimeSlotConstants.MAXIMUM_MATCH_DURATION, zone)
    }

    /** 任何时间：当天 7 点到 23 点；今天的话从现在起至少 30 分钟后、按半小时开始 */
    fun withAnyTime(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): MatchDraft {
        var start = ANY_TIME_START
        if (isSameDay(day, now, zone)) {
            val clock = now.zoned(zone)
            val minutes = clock.hour * 60 + clock.minute + 30
            start = maxOf(start, (minutes + 29) / 30 * 30)
        }
        return copy(startMinutes = minOf(start, ANY_TIME_END - 60), endMinutes = ANY_TIME_END)
    }

    val isAnyTime: Boolean get() = endMinutes == ANY_TIME_END && endMinutes - startMinutes > 8 * 60

    fun canSearch(now: Long = System.currentTimeMillis()): Boolean = validation(now).isValid && courtIds.isNotEmpty()

    /** 加上或去掉一家球馆；已经选满 3 家时加不进去（返回 null） */
    fun togglingCourt(id: String): MatchDraft? {
        if (id in courtIds) return copy(courtIds = courtIds - id)
        if (courtIds.size >= MAX_COURTS) return null
        return copy(courtIds = courtIds + id)
    }

    /** 按一个时间段填日期和起止时间（结束在第二天 0 点算 24:00） */
    fun applying(slot: TimeSlot, zone: ZoneId = ZoneId.systemDefault()): MatchDraft {
        val start = slot.startTime.zoned(zone)
        val end = slot.endTime.zoned(zone)
        val newDay = startOfDay(slot.startTime, zone)
        val endDay = startOfDay(slot.endTime, zone)
        return copy(
            day = newDay,
            startMinutes = start.hour * 60 + start.minute,
            endMinutes = if (endDay > newDay) 24 * 60 else end.hour * 60 + end.minute,
        )
    }

    companion object {
        const val ANY_TIME_START = 7 * 60
        const val ANY_TIME_END = 23 * 60
        const val MAX_COURTS = 3
    }
}
