package com.badie.app.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** 附近的人里约人：大概的时间窗口、最近的一次空闲时间、两人空闲时间的交集、显示的说法。对应 iPhone 的 PlayWindowTests */
class PlayWindowTest {
    private val zone = ZoneId.of("America/Los_Angeles")

    /** 2026-11-11 是周三 */
    private fun date(day: Int, hour: Int, minute: Int = 0): Long =
        ZonedDateTime.of(2026, 11, day, hour, minute, 0, 0, zone).toInstant().toEpochMilli()

    private fun slot(day: Int, startHour: Int, startMinute: Int = 0, endHour: Int) =
        RecurringTimeSlot.create(day, startHour = startHour, startMinute = startMinute, endHour = endHour)

    // MARK: 最近的一次

    @Test
    fun nextOccurrenceLaterThisWeek() {
        // 周三上午看“周六 14:00–18:00”：就是 11/14 那天
        val window = PlayWindow.nextOccurrence(slot(7, 14, endHour = 18), date(11, 10), zone)
        assertEquals(date(14, 14), window?.start)
        assertEquals(date(14, 18), window?.end)
        assertEquals(Daypart.Afternoon, window?.daypart)
    }

    @Test
    fun nextOccurrenceTodayMovesStartOrSkipsToNextWeek() {
        val wednesday = slot(4, 18, endHour = 22)
        // 19:10：最早 19:40 → 20:00 开始，还够打 2 小时
        val tonight = PlayWindow.nextOccurrence(wednesday, date(11, 19, 10), zone)
        assertEquals(date(11, 20), tonight?.start)
        assertEquals(date(11, 22), tonight?.end)
        // 20:10：不够 2 小时了，就是下周三
        assertEquals(date(18, 18), PlayWindow.nextOccurrence(wednesday, date(11, 20, 10), zone)?.start)
    }

    @Test
    fun shortSlotIsExtendedToTwoHoursAndAligned() {
        // 07:15–08:00：开始取整到 07:30，延到 2 小时
        val window = PlayWindow.nextOccurrence(slot(5, 7, 15, endHour = 8), date(11, 10), zone)
        assertEquals(date(12, 7, 30), window?.start)
        assertEquals(date(12, 9, 30), window?.end)
        assertTrue("正好 2 小时就是定好的时间", window?.isExact ?: false)
    }

    // MARK: 粗一点的时间

    @Test
    fun weekendAndNextWeekdays() {
        val weekend = PlayWindow.weekend(date(11, 10), Daypart.Afternoon, zone)
        assertEquals(date(14, 14), weekend?.start)
        assertEquals(date(15, 18), weekend?.end)
        val any = PlayWindow.weekend(date(11, 10), null, zone)
        assertEquals(date(14, 8), any?.start)
        assertEquals(date(15, 22), any?.end)
        // 周日晚上 21:00：这周末来不及了，就是下周末
        assertEquals(date(21, 8), PlayWindow.weekend(date(15, 21), null, zone)?.start)

        val weekdays = PlayWindow.nextWeekdays(date(11, 10), Daypart.Evening, zone)
        assertEquals(date(16, 18), weekdays?.start)
        assertEquals(date(20, 22), weekdays?.end)
    }

    @Test
    fun possibleStartsStayInsideDaypartEachDay() {
        val window = PlayWindow(date(14, 14), date(15, 18), Daypart.Afternoon)
        val starts = window.possibleStarts(date(11, 10), zone)
        // 每天 14:00、14:30 … 16:00 共 5 个，两天 10 个
        assertEquals(10, starts.size)
        assertEquals(date(14, 14), starts.first())
        assertEquals(date(15, 16), starts.last())
        assertFalse("17:00 开始就打到 19:00 了", date(14, 17) in starts)
        // 快开始了：最早是现在过 30 分钟后的整半点
        val soon = PlayWindow(date(11, 14), date(11, 18)).possibleStarts(date(11, 14, 50), zone)
        assertEquals(date(11, 15, 30), soon.first())
        assertEquals(date(11, 16), soon.last())
        assertFalse(PlayWindow(date(11, 14), date(11, 18)).isPossible(date(11, 16, 10), zone))
    }

    @Test
    fun deadlineAndExact() {
        val window = PlayWindow(date(14, 14), date(14, 18), Daypart.Afternoon)
        assertEquals(date(14, 16), window.deadline)
        assertFalse(window.isExact)
        assertTrue(PlayWindow(date(14, 14), date(14, 16)).isExact)
    }

    // MARK: 两人空闲时间的交集

    @Test
    fun firstOverlapNeedsTwoHours() {
        val mine = listOf(slot(5, 19, endHour = 20), slot(7, 13, endHour = 18))
        val theirs = listOf(slot(5, 18, endHour = 21), slot(7, 14, endHour = 20))
        // 周四只重叠 1 小时，不算；周六 14:00–18:00
        val window = PlayWindow.firstOverlap(mine, theirs, date(11, 10), zone)
        assertEquals(date(14, 14), window?.start)
        assertEquals(date(14, 18), window?.end)
        assertEquals(Daypart.Afternoon, window?.daypart)
        assertNull(PlayWindow.firstOverlap(mine, listOf(slot(2, 7, endHour = 9)), date(11, 10), zone))
    }

    // MARK: 时段

    @Test
    fun daypartContainingAndBest() {
        assertEquals(Daypart.Afternoon, Daypart.containing(14 * 60, 18 * 60))
        assertNull(Daypart.containing(11 * 60, 15 * 60))
        assertEquals(Daypart.Evening, Daypart.best(17 * 60, 21 * 60))
        assertEquals(Daypart.Morning, Daypart.best(7 * 60, 9 * 60))
        assertNull(Daypart.best(5 * 60, 7 * 60))
    }

    // MARK: 显示

    @Test
    fun windowText() {
        val now = date(11, 10)
        val saturday = PlayWindow(date(14, 14), date(14, 18), Daypart.Afternoon)
        assertEquals("周六 下午", WindowText.headline(saturday, now, zone))
        assertEquals("14:00–18:00", WindowText.range(saturday, zone))
        assertEquals("14:00–18:00 之间打 2 小时", WindowText.caption(saturday, zone))
        assertEquals("周六 11/14 · 下午", WindowText.headlineWithDate(saturday, now, zone))

        val weekend = PlayWindow(date(14, 14), date(15, 18), Daypart.Afternoon)
        assertEquals("这周末", WindowText.days(weekend, now, zone))
        assertEquals("这周末 · 下午", WindowText.headline(weekend, now, zone))
        assertEquals("下周末", WindowText.days(weekend, date(7, 10), zone))
        assertEquals("11/14–11/15 14:00–18:00", WindowText.range(weekend, zone))

        val weekdays = PlayWindow(date(16, 18), date(20, 22), Daypart.Evening)
        assertEquals("下周工作日", WindowText.days(weekdays, now, zone))

        // 正好 2 小时：只写时间
        val exact = PlayWindow(date(14, 14), date(14, 16))
        assertEquals(WindowText.range(exact, zone), WindowText.caption(exact, zone))
        assertEquals("今天", WindowText.dayName(date(11, 20), now, zone))
        assertEquals("明天", WindowText.dayName(date(12, 20), now, zone))
        assertEquals("11/20 周五", WindowText.dayName(date(20, 20), now, zone))
    }

    @Test
    fun usualTimeSummary() {
        val weekdays = (2..6).map { slot(it, 19, endHour = 21) }
        val weekend = listOf(slot(7, 14, endHour = 17), slot(1, 14, endHour = 17))
        assertEquals("工作日晚上 · 周末下午", UsualTimeText.summary(weekdays + weekend))
        assertNull(UsualTimeText.summary(emptyList()))
        // 三段以上只写两段，加“等”：按第一次出现排（周一开始），周末下午被省掉
        val morning = slot(3, 8, endHour = 10)
        assertEquals("工作日晚上 · 周二上午 等", UsualTimeText.summary(weekdays + weekend + morning))
        assertEquals("周六下午", UsualTimeText.chip(slot(7, 14, endHour = 17)))
        assertEquals("周二 05:00", UsualTimeText.chip(slot(3, 5, endHour = 7)))
        assertEquals("周一、周三", UsualTimeText.daysText(setOf(4, 2)))
    }

    @Test
    fun serverUsualTimeRoundTrip() {
        val slot = RecurringTimeSlot.create(7, startHour = 14, startMinute = 30, endHour = 24)
        assertEquals(ServerUsualTime(7, "14:30", "24:00"), slot.serverValue)
        val back = RecurringTimeSlot.ofServer(slot.serverValue)
        assertEquals(7, back?.dayOfWeek)
        assertEquals(14 * 60 + 30, back?.startMinutes)
        assertEquals(24 * 60, back?.endMinutes)
        assertNull(RecurringTimeSlot.ofServer(ServerUsualTime(8, "10:00", "12:00")))
        assertNull(RecurringTimeSlot.ofServer(ServerUsualTime(2, "12:00", "10:00")))
        assertNull(RecurringTimeSlot.ofServer(ServerUsualTime(2, "24:30", "25:00")))
        assertEquals("""{"weekday":7,"start":"14:30","end":"24:00"}""", slot.serverJSON.toString())
    }
}
