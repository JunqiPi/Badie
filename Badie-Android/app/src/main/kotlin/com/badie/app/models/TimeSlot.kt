package com.badie.app.models

import com.badie.app.l10n.AppLanguage
import com.badie.app.l10n.L10n
import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

// MARK: - 日历（对应 iPhone 的 Calendar.current）
//
// 时间都是毫秒。按当地日历算的地方都带一个时区参数，默认用系统的，测试可以指定。
// 星期和 iPhone 一样：1 = 周日 … 7 = 周六。

/** iPhone 的 Date.distantFuture（4001 年）：永久暂停这类“没有尽头”的时间 */
const val DISTANT_FUTURE: Long = 64_092_211_200_000L

/** iPhone 的 Date.distantPast（公元 1 年） */
const val DISTANT_PAST: Long = -62_135_769_600_000L

fun Long.zoned(zone: ZoneId = ZoneId.systemDefault()): ZonedDateTime = Instant.ofEpochMilli(this).atZone(zone)

private fun ZonedDateTime.millis(): Long = toInstant().toEpochMilli()

/** 当天 0 点 */
fun startOfDay(millis: Long, zone: ZoneId = ZoneId.systemDefault()): Long =
    millis.zoned(zone).toLocalDate().atStartOfDay(zone).millis()

/** 星期几：1 = 周日 … 7 = 周六 */
fun weekdayOf(millis: Long, zone: ZoneId = ZoneId.systemDefault()): Int = millis.zoned(zone).dayOfWeek.value % 7 + 1

fun isSameDay(a: Long, b: Long, zone: ZoneId = ZoneId.systemDefault()): Boolean =
    a.zoned(zone).toLocalDate() == b.zoned(zone).toLocalDate()

/** 加几天（钟点不变，夏令时切换那天也对） */
fun addingDays(millis: Long, days: Int, zone: ZoneId = ZoneId.systemDefault()): Long = millis.zoned(zone).plusDays(days.toLong()).millis()

/** 同一天的某个钟点 */
fun settingTime(millis: Long, hour: Int, minute: Int, zone: ZoneId = ZoneId.systemDefault()): Long =
    ZonedDateTime.of(millis.zoned(zone).toLocalDate(), LocalTime.of(hour, minute), zone).millis()

/** 两天之间差几天（按日期算） */
fun daysBetween(from: Long, to: Long, zone: ZoneId = ZoneId.systemDefault()): Int =
    ChronoUnit.DAYS.between(from.zoned(zone).toLocalDate(), to.zoned(zone).toLocalDate()).toInt()

/** 向上取整到指定分钟粒度（和 iPhone 一样只看分和秒） */
fun Long.roundedUp(toMinutes: Int, zone: ZoneId = ZoneId.systemDefault()): Long {
    val time = zoned(zone)
    val remainder = time.minute % toMinutes
    if (remainder == 0 && time.second == 0) return this
    val add = (toMinutes - remainder) * 60 - time.second
    return this + add * 1000L
}

// MARK: - 时间段常量（毫秒）

object TimeSlotConstants {
    /** 最短 1 小时 */
    const val MINIMUM_DURATION = 3_600_000L
    /** 最长 8 小时（开局、球群） */
    const val MAXIMUM_DURATION = 8 * 3_600_000L
    /** 约球可以选“任何时间”：最长 16 小时 */
    const val MAXIMUM_MATCH_DURATION = 16 * 3_600_000L
    /** 匹配所需最小重叠 30 分钟 */
    const val MINIMUM_OVERLAP_DURATION = 1_800_000L
    /** 可选择未来 30 天 */
    const val MAXIMUM_DAYS_AHEAD = 30
    /** 最多保存 5 个常用时间 */
    const val MAXIMUM_RECURRING_SLOTS = 5
    /** 一场球的默认时长上限（匹配结果截取） */
    const val DEFAULT_GAME_DURATION = 2 * 3_600_000L
}

// MARK: - 时间段

/** 一段时间。date 是所在日期的 0 点：新建时用 [TimeSlot.of]，它会把 date 换成当天 0 点 */
@Serializable
data class TimeSlot(val date: Long, val startTime: Long, val endTime: Long) {
    /** 时长，毫秒 */
    val duration: Long get() = endTime - startTime

    val isValidDuration: Boolean
        get() = duration >= TimeSlotConstants.MINIMUM_DURATION && duration <= TimeSlotConstants.MAXIMUM_DURATION

    val formattedDuration: String
        get() {
            val totalMinutes = duration / 60_000
            val hours = totalMinutes / 60
            val minutes = totalMinutes % 60
            if (minutes == 0L) return tr("%lld 小时", hours)
            if (hours == 0L) return tr("%lld 分钟", minutes)
            return tr("%lld 小时 %lld 分", hours, minutes)
        }

    fun formattedTimeRange(zone: ZoneId = ZoneId.systemDefault()): String =
        "${DateText.time(startTime, zone)}–${DateText.time(endTime, zone)}"

    /** 例："今天 · 周三" / "10月15日周三"（按当前语言格式化） */
    fun formattedDate(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String =
        DateText.relativeDay(date, now, zone)

    fun formattedFull(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String =
        "${formattedDate(now, zone)} ${formattedTimeRange(zone)}"

    /** 计算与另一时间段的重叠；重叠不足 30 分钟返回 null */
    fun overlaps(other: TimeSlot, zone: ZoneId = ZoneId.systemDefault()): TimeSlot? {
        val start = maxOf(startTime, other.startTime)
        val end = minOf(endTime, other.endTime)
        if (end <= start || end - start < TimeSlotConstants.MINIMUM_OVERLAP_DURATION) return null
        return of(start, start, end, zone)
    }

    fun contains(moment: Long): Boolean = moment >= startTime && moment < endTime

    /** 截取为一场球的时长（默认最多 2 小时），并对齐到整半小时 */
    fun trimmedForGame(maxDuration: Long = TimeSlotConstants.DEFAULT_GAME_DURATION, zone: ZoneId = ZoneId.systemDefault()): TimeSlot {
        val alignedStart = startTime.roundedUp(30, zone)
        val start = if (alignedStart < endTime) alignedStart else startTime
        val end = minOf(endTime, start + maxDuration)
        return of(start, start, end, zone)
    }

    /** 向前/向后扩展（用于“放宽时间”建议） */
    fun expanded(byHours: Double, zone: ZoneId = ZoneId.systemDefault()): TimeSlot {
        val dayStart = startOfDay(startTime, zone)
        val dayEnd = addingDays(dayStart, 1, zone)
        val newStart = maxOf(dayStart + 6 * 3_600_000L, startTime - (byHours * 3_600_000).toLong())
        val newEnd = minOf(dayEnd, endTime + (byHours * 3_600_000).toLong())
        var slot = of(date, newStart, newEnd, zone)
        if (slot.duration > TimeSlotConstants.MAXIMUM_DURATION) {
            slot = of(date, newStart, newStart + TimeSlotConstants.MAXIMUM_DURATION, zone)
        }
        return slot
    }

    fun validate(
        now: Long = System.currentTimeMillis(),
        maxDuration: Long = TimeSlotConstants.MAXIMUM_DURATION,
        zone: ZoneId = ZoneId.systemDefault(),
    ): TimeSlotValidationResult {
        if (endTime <= startTime) return TimeSlotValidationResult.Invalid(tr("结束时间需要晚于开始时间"))
        if (duration < TimeSlotConstants.MINIMUM_DURATION) return TimeSlotValidationResult.Invalid(tr("至少需要 1 小时"))
        if (duration > maxDuration) {
            return TimeSlotValidationResult.Invalid(
                if (maxDuration > TimeSlotConstants.MAXIMUM_DURATION) tr("最长 16 小时") else tr("最长 8 小时"),
            )
        }
        val today = startOfDay(now, zone)
        val day = startOfDay(date, zone)
        if (day < today) return TimeSlotValidationResult.Invalid(tr("不能选择过去的日期"))
        if (day > addingDays(today, TimeSlotConstants.MAXIMUM_DAYS_AHEAD, zone)) {
            return TimeSlotValidationResult.Invalid(tr("只能选择未来 30 天内"))
        }
        if (endTime <= now) return TimeSlotValidationResult.Invalid(tr("这个时间段已经过去了"))
        return TimeSlotValidationResult.Valid
    }

    companion object {
        /** 新建：date 换成当天 0 点 */
        fun of(date: Long, startTime: Long, endTime: Long, zone: ZoneId = ZoneId.systemDefault()): TimeSlot =
            TimeSlot(startOfDay(date, zone), startTime, endTime)

        /** 指定日期的时间段（结束 24 点 = 第二天 0 点） */
        fun on(
            date: Long, startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0,
            zone: ZoneId = ZoneId.systemDefault(),
        ): TimeSlot? {
            if (startHour !in 0..23 || startMinute !in 0..59 || endMinute !in 0..59 || endHour < 0) return null
            val day = startOfDay(date, zone)
            val start = settingTime(day, startHour, startMinute, zone)
            val end = if (endHour >= 24) addingDays(day, 1, zone) else settingTime(day, endHour, endMinute, zone)
            return TimeSlot(day, start, end)
        }

        /** 默认推荐：18 点前为今晚 19–21 点；20 点前从下个整半点再过 30 分钟开始，最多 2 小时、不晚于 23:30；否则明晚 19–21 点 */
        fun suggestedDefault(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): TimeSlot {
            val hour = now.zoned(zone).hour
            if (hour < 18) on(now, startHour = 19, endHour = 21, zone = zone)?.let { return it }
            if (hour < 20) {
                val start = now.roundedUp(30, zone) + 30 * 60_000L
                val end = minOf(start + 2 * 3_600_000L, startOfDay(now, zone) + 23 * 3_600_000L + 1_800_000L)
                if (end - start >= TimeSlotConstants.MINIMUM_DURATION) return of(now, start, end, zone)
            }
            val tomorrow = addingDays(now, 1, zone)
            return on(tomorrow, startHour = 19, endHour = 21, zone = zone) ?: of(tomorrow, tomorrow, tomorrow + 7_200_000L, zone)
        }
    }
}

sealed interface TimeSlotValidationResult {
    data object Valid : TimeSlotValidationResult
    data class Invalid(val reason: String) : TimeSlotValidationResult

    val isValid: Boolean get() = this is Valid

    val errorMessage: String? get() = (this as? Invalid)?.reason
}

// MARK: - 常用时间（周期性）

@Serializable
data class RecurringTimeSlot(
    val id: String,
    /** 1 = 周日 … 7 = 周六 */
    val dayOfWeek: Int,
    val startHour: Int,
    val startMinute: Int = 0,
    val endHour: Int,
    val endMinute: Int = 0,
    val isActive: Boolean = true,
) {
    val dayOfWeekName: String get() = if (dayOfWeek in 1..7) weekdayNames[dayOfWeek - 1] else tr("未知")

    val formattedTimeRange: String
        get() = String.format(Locale.ROOT, "%02d:%02d–%02d:%02d", startHour, startMinute, endHour, endMinute)

    val displayText: String get() = "$dayOfWeekName $formattedTimeRange"

    val durationMinutes: Int get() = (endHour * 60 + endMinute) - (startHour * 60 + startMinute)

    val isValidDuration: Boolean
        get() {
            val millis = durationMinutes * 60_000L
            return millis >= TimeSlotConstants.MINIMUM_DURATION && millis <= TimeSlotConstants.MAXIMUM_DURATION
        }

    /** 从 now 起（含当天）30 天内下一次还没结束的具体时间段 */
    fun nextOccurrence(from: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): TimeSlot? {
        for (offset in 0 until TimeSlotConstants.MAXIMUM_DAYS_AHEAD) {
            val day = addingDays(startOfDay(from, zone), offset, zone)
            if (weekdayOf(day, zone) != dayOfWeek) continue
            val slot = TimeSlot.on(day, startHour, startMinute, endHour, endMinute, zone) ?: continue
            if (slot.endTime > from) return slot
        }
        return null
    }

    // MARK: 和 PlayWindow 一起用的分钟数、服务器的格式（iPhone 在 PlayWindow.swift 里）

    val startMinutes: Int get() = startHour * 60 + startMinute
    val endMinutes: Int get() = endHour * 60 + endMinute

    val serverValue: ServerUsualTime get() = ServerUsualTime(dayOfWeek, clock(startMinutes), clock(endMinutes))

    companion object {
        /** 星期几超出 1–7 的夹到范围里 */
        fun create(
            dayOfWeek: Int, startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0,
            isActive: Boolean = true, id: String = UUID.randomUUID().toString().uppercase(),
        ): RecurringTimeSlot = RecurringTimeSlot(id, dayOfWeek.coerceIn(1, 7), startHour, startMinute, endHour, endMinute, isActive)

        val weekdayNames: List<String>
            get() = listOf(tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六"))

        /** 服务器的一项：星期不在 1–7、时间不对或开始不早于结束的不要 */
        fun ofServer(server: ServerUsualTime): RecurringTimeSlot? {
            if (server.weekday !in 1..7) return null
            val start = minutes(server.start) ?: return null
            val end = minutes(server.end) ?: return null
            if (start >= end) return null
            return create(server.weekday, start / 60, start % 60, end / 60, end % 60)
        }

        /** "HH:MM" → 分钟（最多 24:00） */
        fun minutes(text: String): Int? {
            val parts = text.split(":")
            if (parts.size != 2) return null
            val hour = parts[0].toIntOrNull() ?: return null
            val minute = parts[1].toIntOrNull() ?: return null
            if (hour !in 0..24 || minute !in 0 until 60 || hour * 60 + minute > 24 * 60) return null
            return hour * 60 + minute
        }

        fun clock(minutes: Int): String = String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)
    }
}

val List<RecurringTimeSlot>.canAddMore: Boolean get() = size < TimeSlotConstants.MAXIMUM_RECURRING_SLOTS
val List<RecurringTimeSlot>.remainingSlots: Int get() = maxOf(0, TimeSlotConstants.MAXIMUM_RECURRING_SLOTS - size)
val List<RecurringTimeSlot>.activeSlots: List<RecurringTimeSlot> get() = filter { it.isActive }

// MARK: - 日期文本

object DateText {
    /** 语言和界面文字一样（App 里选的，或跟随系统），地区（12/24 小时制等）沿用系统的 */
    @Volatile
    private var locale: Locale = appLocale()

    /** 换了语言（界面重建时 L10n.attach 会调）：日期按新语言重新排 */
    fun reset() {
        locale = appLocale()
    }

    private fun appLocale(): Locale = try {
        Locale.Builder().setLanguageTag(L10n.language ?: AppLanguage.current).setRegion(Locale.getDefault().country).build()
    } catch (_: Throwable) {
        Locale.getDefault()
    }

    /**
     * 按模板排日期（和 iPhone 的 setLocalizedDateFormatFromTemplate 一样）。
     * 没有系统的时候（单元测试）按简体中文的写法
     */
    private fun format(millis: Long, skeleton: String, fallback: String, zone: ZoneId): String = try {
        val formatter = android.icu.text.DateFormat.getInstanceForSkeleton(skeleton, locale)
        formatter.timeZone = android.icu.util.TimeZone.getTimeZone(zone.id)
        formatter.format(java.util.Date(millis))
    } catch (_: Throwable) {
        DateTimeFormatter.ofPattern(fallback, Locale.SIMPLIFIED_CHINESE).format(millis.zoned(zone))
    }

    /** 时刻，12/24 小时制随系统地区 */
    fun time(date: Long, zone: ZoneId = ZoneId.systemDefault()): String = format(date, "jmm", "HH:mm", zone)

    /** 月日 + 星期，如中文 "10月15日周三"、英文 "Wed, Oct 15" */
    private fun dayText(date: Long, zone: ZoneId): String = format(date, "MMMdEEE", "M月d日EEE", zone)

    /** 月日 + 时刻，如 "11月2日 19:00" */
    fun dayAndTime(date: Long, zone: ZoneId = ZoneId.systemDefault()): String = format(date, "MMMdjmm", "M月d日 HH:mm", zone)

    fun relativeDay(date: Long, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        val day = weekday(date, zone)
        if (isSameDay(date, now, zone)) return tr("今天 · %@", day)
        if (isSameDay(date, addingDays(now, 1, zone), zone)) return tr("明天 · %@", day)
        if (isSameDay(date, addingDays(now, -1, zone), zone)) return tr("昨天 · %@", day)
        return dayText(date, zone)
    }

    /** 月日，如中文 "11月18日"、英文 "Nov 18"（付款备注、你还没付的卡片） */
    fun monthDay(date: Long, zone: ZoneId = ZoneId.systemDefault()): String = format(date, "MMMd", "M月d日", zone)

    /** 数字月日，如 "10/15" */
    fun shortDay(date: Long, zone: ZoneId = ZoneId.systemDefault()): String = format(date, "Md", "M/d", zone)

    /** 截止时间：“今天 17:00” / “明天 09:00” / “周五 09:00” */
    fun deadline(date: Long, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        val clock = time(date, zone)
        if (isSameDay(date, now, zone)) return tr("今天 %@", clock)
        if (isSameDay(date, addingDays(now, 1, zone), zone)) return tr("明天 %@", clock)
        return "${weekday(date, zone)} ${time(date, zone)}"
    }

    /** 星期几加几点（周三 下午7时、Wed 7 PM）：付款备注里用 */
    fun weekdayHour(date: Long, zone: ZoneId = ZoneId.systemDefault()): String = format(date, "EEEj", "EEE HH", zone)

    fun weekday(date: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        RecurringTimeSlot.weekdayNames[weekdayOf(date, zone) - 1]

    /** 消息列表等使用的简短时间：今天显示时刻，否则显示日期 */
    fun compact(date: Long, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        if (isSameDay(date, now, zone)) return time(date, zone)
        if (isSameDay(date, addingDays(now, -1, zone), zone)) return tr("昨天")
        return shortDay(date, zone)
    }

    /** 过去时间的相对描述："刚刚" / "3 小时前" / "5 天前" / "2 个月前" */
    fun relative(date: Long, now: Long = System.currentTimeMillis()): String {
        val seconds = maxOf(0L, (now - date) / 1000)
        return when {
            seconds < 3600 -> tr("刚刚")
            seconds < 86400 -> tr("%lld 小时前", seconds / 3600)
            seconds < 30 * 86400 -> tr("%lld 天前", seconds / 86400)
            seconds < 365 * 86400 -> tr("%lld 个月前", seconds / (30 * 86400))
            else -> tr("%lld 年前", seconds / (365 * 86400))
        }
    }

    /** 倒计时描述，例如 "还有 2 小时 15 分" */
    fun countdown(date: Long, now: Long = System.currentTimeMillis()): String {
        val seconds = (date - now) / 1000
        if (seconds <= 0) return tr("已开始")
        val days = seconds / 86400
        val hours = (seconds % 86400) / 3600
        val minutes = (seconds % 3600) / 60
        if (days > 0) return if (hours > 0) tr("还有 %lld 天 %lld 小时", days, hours) else tr("还有 %lld 天", days)
        if (hours > 0) return if (minutes > 0) tr("还有 %lld 小时 %lld 分", hours, minutes) else tr("还有 %lld 小时", hours)
        return tr("还有 %lld 分钟", maxOf(1L, minutes))
    }

    /** 剩余时间（用于问卷截止等） */
    fun remaining(date: Long, now: Long = System.currentTimeMillis()): String {
        val seconds = (date - now) / 1000
        if (seconds <= 0) return tr("已截止")
        val hours = seconds / 3600
        if (hours >= 1) return tr("剩 %lld 小时", hours)
        return tr("剩 %lld 分钟", maxOf(1L, seconds / 60))
    }
}
