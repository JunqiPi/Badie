package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.ZoneId
import kotlin.math.abs

// MARK: - 邀请局的大概时间
// 附近的人里右滑约人：时间可以只说个大概（“周六下午”“这周末”“下周工作日晚上”），
// 对方说好以后再在群聊里定具体几点。和服务器一致：一场固定 2 小时，时间按半小时对齐，按球馆当地时间算。
// 按日历算的地方都带时区参数（iPhone 用 Calendar.current），默认用系统的。

/** 一天里的时段：上午 08–12、下午 14–18、晚上 18–22 */
@Serializable
enum class Daypart(val rawValue: String) {
    @SerialName("morning") Morning("morning"),
    @SerialName("afternoon") Afternoon("afternoon"),
    @SerialName("evening") Evening("evening");

    val title: String
        get() = when (this) {
            Morning -> tr("上午")
            Afternoon -> tr("下午")
            Evening -> tr("晚上")
        }

    /** 开始（从 0 点算的分钟） */
    val startMinutes: Int
        get() = when (this) {
            Morning -> 8 * 60
            Afternoon -> 14 * 60
            Evening -> 18 * 60
        }

    /** 结束（从 0 点算的分钟） */
    val endMinutes: Int
        get() = when (this) {
            Morning -> 12 * 60
            Afternoon -> 18 * 60
            Evening -> 22 * 60
        }

    companion object {
        fun of(rawValue: String?): Daypart? = entries.firstOrNull { it.rawValue == rawValue }

        /** 一段时间（同一天，分钟）整个落在哪个时段里 */
        fun containing(start: Int, end: Int): Daypart? = entries.firstOrNull { start >= it.startMinutes && end <= it.endMinutes }

        /** 和这段时间重叠最多的时段（“周六下午”这类标签用）；一点都不重叠是 null */
        fun best(start: Int, end: Int): Daypart? {
            var result: Daypart? = null
            var longest = 0
            for (part in entries) {
                val overlap = minOf(end, part.endMinutes) - maxOf(start, part.startMinutes)
                if (overlap > longest) {
                    longest = overlap
                    result = part
                }
            }
            return result
        }
    }
}

/** 一段可以打球的时间：start–end 之间打 durationMinutes（2 小时） */
@Serializable
data class PlayWindow(
    val start: Long,
    val end: Long,
    /** 整场都要在这个时段里（跨天的窗口每天都一样）；null = 什么时段都行 */
    val daypart: Daypart? = null,
    val durationMinutes: Int = 120,
) {
    /** 一场的时长，毫秒 */
    val duration: Long get() = durationMinutes * 60_000L

    /** 窗口正好一场球那么长：就是定好的时间 */
    val isExact: Boolean get() = abs(end - start - duration) < 1000

    /** 最晚什么时候要定下来：邀请到这时没人回就失效，球局到这时没定时间就自动取消 */
    val deadline: Long get() = end - duration

    val slot: TimeSlot get() = TimeSlot.of(start, start, end)

    fun isSingleDay(zone: ZoneId = ZoneId.systemDefault()): Boolean = isSameDay(start, end - 1000, zone)

    /** 显示用的时段：没指定时，同一天里整个落在某个时段的也算 */
    fun displayDaypart(zone: ZoneId = ZoneId.systemDefault()): Daypart? {
        if (daypart != null) return daypart
        if (!isSingleDay(zone)) return null
        // 结束在第二天 0 点算 24:00
        val endMinute = if (isSameDay(start, end, zone)) clockMinutes(end, zone) else 24 * 60 + clockMinutes(end, zone)
        return Daypart.containing(clockMinutes(start, zone), endMinute)
    }

    /** 能开始的时间：每半小时一个，整场都在窗口里、在时段里，不早于 earliestStart。没指定时段的，只给 06:00 后开始、当天打完的 */
    fun possibleStarts(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): List<Long> {
        val earliest = earliestStart(now, zone)
        val result = mutableListOf<Long>()
        var cursor = start.roundedUp(30, zone)
        var steps = 0
        while (cursor + duration <= end && steps < 400) {
            if (cursor >= earliest && fits(cursor, zone)) result += cursor
            cursor += 30 * 60_000L
            steps += 1
        }
        return result
    }

    /** 现在还能不能约（至少有一个开始时间） */
    fun isPossible(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Boolean =
        possibleStarts(now, zone).isNotEmpty()

    private fun fits(begin: Long, zone: ZoneId): Boolean {
        val startMinute = clockMinutes(begin, zone)
        val endMinute = startMinute + durationMinutes
        if (daypart != null) return startMinute >= daypart.startMinutes && endMinute <= daypart.endMinutes
        return startMinute >= 6 * 60 && endMinute <= 24 * 60
    }

    companion object {
        /** 当天的钟点（从 0 点算的分钟）：按钟面算，夏令时切换那天也对 */
        fun clockMinutes(date: Long, zone: ZoneId = ZoneId.systemDefault()): Int = date.zoned(zone).let { it.hour * 60 + it.minute }

        /** 某天的某个钟点（分钟，24:00 = 第二天 0 点）：按钟面设置，夏令时切换那天也对 */
        fun time(date: Long, minutes: Int, zone: ZoneId = ZoneId.systemDefault()): Long? {
            if (minutes < 0) return null
            if (minutes < 24 * 60) return settingTime(date, minutes / 60, minutes % 60, zone)
            val next = addingDays(startOfDay(date, zone), minutes / (24 * 60), zone)
            val rest = minutes % (24 * 60)
            return settingTime(next, rest / 60, rest % 60, zone)
        }

        /** 最早能开始的时间：现在过 30 分钟后的下一个整半点（和服务器一致） */
        fun earliestStart(now: Long, zone: ZoneId = ZoneId.systemDefault()): Long = (now + 30 * 60_000L).roundedUp(30, zone)

        // MARK: 常用的几种窗口

        /** 某一天里从 startMinutes 到 endMinutes（分钟） */
        fun on(date: Long, startMinutes: Int, endMinutes: Int, daypart: Daypart? = null, zone: ZoneId = ZoneId.systemDefault()): PlayWindow? {
            if (endMinutes <= startMinutes) return null
            val start = time(date, startMinutes, zone) ?: return null
            val end = time(date, endMinutes, zone) ?: return null
            if (end <= start) return null
            return PlayWindow(start, end, daypart)
        }

        /** 某一天的某个时段；null = 都行（08–22） */
        fun on(date: Long, daypart: Daypart?, zone: ZoneId = ZoneId.systemDefault()): PlayWindow? =
            on(date, daypart?.startMinutes ?: (8 * 60), daypart?.endMinutes ?: (22 * 60), daypart, zone)

        /** 从 firstDay 那天的时段开始到 lastDay 那天的时段结束（null = 08–22） */
        private fun span(firstDay: Long, lastDay: Long, daypart: Daypart?, zone: ZoneId): PlayWindow? {
            val startMinutes = daypart?.startMinutes ?: (8 * 60)
            val endMinutes = daypart?.endMinutes ?: (22 * 60)
            val first = on(firstDay, startMinutes, endMinutes, zone = zone) ?: return null
            val last = on(lastDay, startMinutes, endMinutes, zone = zone) ?: return null
            return PlayWindow(first.start, last.end, daypart)
        }

        /** 这周末：周六到周日（今天是周日也算这周末）；这周末来不及了就是下周末 */
        fun weekend(now: Long = System.currentTimeMillis(), daypart: Daypart?, zone: ZoneId = ZoneId.systemDefault()): PlayWindow? {
            val today = startOfDay(now, zone)
            val weekday = weekdayOf(today, zone)
            val toSaturday = if (weekday == 1) -1 else 7 - weekday
            for (extra in listOf(0, 7)) {
                val saturday = addingDays(today, toSaturday + extra, zone)
                val sunday = addingDays(saturday, 1, zone)
                val window = span(saturday, sunday, daypart, zone) ?: continue
                if (window.isPossible(now, zone)) return window
            }
            return null
        }

        /** 下周工作日：下周一到周五（今天是周日，下周一就是明天） */
        fun nextWeekdays(now: Long = System.currentTimeMillis(), daypart: Daypart?, zone: ZoneId = ZoneId.systemDefault()): PlayWindow? {
            val today = startOfDay(now, zone)
            val weekday = weekdayOf(today, zone)
            val toMonday = if ((9 - weekday) % 7 == 0) 7 else (9 - weekday) % 7
            val monday = addingDays(today, toMonday, zone)
            val friday = addingDays(monday, 4, zone)
            return span(monday, friday, daypart, zone)
        }

        /**
         * 一段常用时间最近的一次：按半小时取整，不够 2 小时的往后延到 2 小时；
         * 今天的已经开始了就从最早能开始的时间算，不够打一场就是下周的
         */
        fun nextOccurrence(slot: RecurringTimeSlot, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): PlayWindow? {
            val startMinutes = (slot.startMinutes + 29) / 30 * 30
            val endMinutes = minOf(24 * 60, maxOf(slot.endMinutes / 30 * 30, startMinutes + 120))
            if (endMinutes - startMinutes < 120) return null
            val earliest = earliestStart(now, zone)
            val today = startOfDay(now, zone)
            for (offset in 0 until 15) {
                val day = addingDays(today, offset, zone)
                if (weekdayOf(day, zone) != slot.dayOfWeek) continue
                var window = on(day, startMinutes, endMinutes, Daypart.containing(startMinutes, endMinutes), zone) ?: continue
                if (window.start < earliest) window = window.copy(start = earliest)
                if (window.end - window.start >= window.duration) return window
            }
            return null
        }

        /** 两人空闲时间的交集：接下来 7 天里第一段至少 2 小时的（演示模式用；正式后端由服务器算） */
        fun firstOverlap(
            mine: List<RecurringTimeSlot>, theirs: List<RecurringTimeSlot>,
            now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(),
        ): PlayWindow? {
            val today = startOfDay(now, zone)
            val earliest = earliestStart(now, zone)
            for (offset in 0 until 7) {
                val day = addingDays(today, offset, zone)
                val weekday = weekdayOf(day, zone)
                var best: PlayWindow? = null
                for (a in mine.filter { it.dayOfWeek == weekday }) {
                    for (b in theirs.filter { it.dayOfWeek == weekday }) {
                        val startMinutes = (maxOf(a.startMinutes, b.startMinutes) + 29) / 30 * 30
                        val endMinutes = minOf(a.endMinutes, b.endMinutes) / 30 * 30
                        if (endMinutes - startMinutes < 120) continue
                        var window = on(day, startMinutes, endMinutes, Daypart.containing(startMinutes, endMinutes), zone) ?: continue
                        if (window.start < earliest) window = window.copy(start = earliest)
                        if (window.end - window.start < window.duration) continue
                        if (best == null || window.start < best.start) best = window
                    }
                }
                if (best != null) return best
            }
            return null
        }
    }
}

// MARK: - 邀请

/** 附近的人里发的邀请：谁约谁、轮到谁回、换过几次时间 */
@Serializable
data class LobbyInvite(
    val fromId: String,
    val toId: String,
    /** 轮到谁回；说好、不了、过期以后没人要回（服务器给 null） */
    val awaitingId: String? = null,
    /** 换过几次时间 */
    val rounds: Int,
    /** 过了这个时间没人回就失效 */
    val answerBy: Long,
) {
    fun other(than: String?): String = if (fromId == than) toId else fromId
}

// MARK: - 常用时间：服务器的格式

/** profiles.usual_times 里的一项：{"weekday": 1-7（1 = 周日）, "start": "HH:MM", "end": "HH:MM"} */
@Serializable
data class ServerUsualTime(val weekday: Int, val start: String, val end: String)

/** 发给服务器的 JSON（换算见 TimeSlot.kt 的 RecurringTimeSlot.ofServer / serverValue） */
val RecurringTimeSlot.serverJSON: JsonObject
    get() = JsonObject(
        mapOf(
            "weekday" to JsonPrimitive(dayOfWeek),
            "start" to JsonPrimitive(RecurringTimeSlot.clock(startMinutes)),
            "end" to JsonPrimitive(RecurringTimeSlot.clock(endMinutes)),
        ),
    )

// MARK: - 显示

/** 窗口的说法：大字“周六 下午”“这周末 · 下午”“下周工作日 · 晚上”，小字“14:00–18:00 之间” */
object WindowText {
    /** 今天、明天、6 天内写星期，再远写日期和星期 */
    fun dayName(date: Long, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        if (isSameDay(date, now, zone)) return tr("今天")
        if (isSameDay(date, addingDays(now, 1, zone), zone)) return tr("明天")
        val days = daysBetween(now, date, zone)
        if (days in 1 until 7) return DateText.weekday(date, zone)
        return "${DateText.shortDay(date, zone)} ${DateText.weekday(date, zone)}"
    }

    /** 哪几天：“周六”“这周末”“下周工作日”“周六–周一” */
    fun days(window: PlayWindow, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        val first = startOfDay(window.start, zone)
        val last = startOfDay(window.end - 1000, zone)
        if (first == last) return dayName(window.start, now, zone)
        val span = daysBetween(first, last, zone)
        val ahead = daysBetween(now, first, zone)
        val firstWeekday = weekdayOf(first, zone)
        if (firstWeekday == 7 && span == 1) return if (ahead < 7) tr("这周末") else tr("下周末")
        if (firstWeekday == 2 && span == 4) return if (ahead > 0) tr("下周工作日") else tr("这周工作日")
        return "${dayName(first, now, zone)}–${dayName(last, now, zone)}"
    }

    /** 大字：“周六 下午”“这周末 · 下午”“这周末” */
    fun headline(window: PlayWindow, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        val dayText = days(window, now, zone)
        val part = window.displayDaypart(zone) ?: return dayText
        return if (window.isSingleDay(zone)) "$dayText ${part.title}" else "$dayText · ${part.title}"
    }

    /** 带日期的标题（收到的邀请）：“周六 11/15 · 下午”；跨天的同 headline */
    fun headlineWithDate(window: PlayWindow, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        if (!window.isSingleDay(zone)) return headline(window, now, zone)
        val day = "${DateText.weekday(window.start, zone)} ${DateText.shortDay(window.start, zone)}"
        val part = window.displayDaypart(zone) ?: return day
        return "$day · ${part.title}"
    }

    /** 时间范围：“14:00–18:00”；跨天：“11/15–11/16 14:00–18:00”，没有时段的写全：“11/15 08:00 – 11/16 22:00” */
    fun range(window: PlayWindow, zone: ZoneId = ZoneId.systemDefault()): String {
        if (window.isSingleDay(zone)) return "${DateText.time(window.start, zone)}–${DateText.time(window.end, zone)}"
        val lastDay = window.end - 1000
        val part = window.daypart
        if (part != null) {
            val firstDay = startOfDay(window.start, zone)
            val from = firstDay + part.startMinutes * 60_000L
            val to = firstDay + part.endMinutes * 60_000L
            return "${DateText.shortDay(window.start, zone)}–${DateText.shortDay(lastDay, zone)} ${DateText.time(from, zone)}–${DateText.time(to, zone)}"
        }
        return "${DateText.shortDay(window.start, zone)} ${DateText.time(window.start, zone)} – " +
            "${DateText.shortDay(lastDay, zone)} ${DateText.time(window.end, zone)}"
    }

    /** “14:00–18:00 之间” */
    fun between(window: PlayWindow, zone: ZoneId = ZoneId.systemDefault()): String = tr("%@ 之间", range(window, zone))

    /** 选时间时的小字：“14:00–18:00 之间打 2 小时”；正好 2 小时的就是“14:00–16:00” */
    fun caption(window: PlayWindow, zone: ZoneId = ZoneId.systemDefault()): String =
        if (window.isExact) range(window, zone) else tr("%@ 之间打 2 小时", range(window, zone))
}

/** 空闲时间的说法：卡片上的小标签“周六下午”，资料页上归纳成一行“工作日晚上 · 周末下午” */
object UsualTimeText {
    /** 周一排第一 */
    private fun order(weekday: Int): Int = (weekday + 5) % 7

    private fun daypart(slot: RecurringTimeSlot): Daypart? = Daypart.best(slot.startMinutes, slot.endMinutes)

    /** 小标签：“周六下午”；不在任何时段里的写开始时间：“周二 07:00” */
    fun chip(slot: RecurringTimeSlot): String {
        val day = slot.dayOfWeekName
        val part = daypart(slot) ?: return "$day ${RecurringTimeSlot.clock(slot.startMinutes)}"
        // 星期 + 时段，如“周六下午”
        return tr("%@%@", day, part.title)
    }

    /** 按最近的一次排：最先能约的在前 */
    fun sortedByNext(slots: List<RecurringTimeSlot>, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()) =
        slots.sortedBy { PlayWindow.nextOccurrence(it, now, zone)?.start ?: DISTANT_FUTURE }

    /** 一行：“工作日晚上 · 周末下午”，最多两段，多了加“等”。没有空闲时间是 null */
    fun summary(slots: List<RecurringTimeSlot>): String? {
        if (slots.isEmpty()) return null
        val keys = mutableListOf<String>()
        val days = HashMap<String, MutableSet<Int>>()
        val parts = HashMap<String, Daypart?>()
        val sorted = slots.sortedWith(compareBy<RecurringTimeSlot> { order(it.dayOfWeek) }.thenBy { it.startMinutes })
        for (slot in sorted) {
            val part = daypart(slot)
            val key = part?.rawValue ?: RecurringTimeSlot.clock(slot.startMinutes)
            if (key !in days) keys += key
            days.getOrPut(key) { mutableSetOf() } += slot.dayOfWeek
            parts[key] = part
        }
        val phrases = keys.map { key ->
            val dayText = daysText(days[key].orEmpty())
            val part = parts[key]
            // 星期 + 时段，如“周六下午”
            if (part != null) tr("%@%@", dayText, part.title) else "$dayText $key"
        }
        val shown = phrases.take(2).joinToString(" · ")
        return if (phrases.size > 2) tr("%@ 等", shown) else shown
    }

    /** 周一到周五全有：“工作日”；周六周日：“周末”；七天：“每天”；其他列出来 */
    fun daysText(days: Set<Int>): String {
        if (days == (1..7).toSet()) return tr("每天")
        if (days == (2..6).toSet()) return tr("工作日")
        if (days == setOf(1, 7)) return tr("周末")
        // “、”是名单分隔符
        return days.sortedBy { order(it) }.map { RecurringTimeSlot.weekdayNames[it - 1] }.joinToString(tr("、"))
    }
}
