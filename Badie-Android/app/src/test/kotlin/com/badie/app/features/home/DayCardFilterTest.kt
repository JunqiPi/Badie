package com.badie.app.features.home

import com.badie.app.backend.DayCandidate
import com.badie.app.backend.NearbyPlayer
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.User
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** 按天看人的筛选也用在附近的人的卡片上：时间按 TA 的空闲时间，项目按 TA 常打的（没填的都算），混双算双打。对应 iPhone 的 DayCardFilterTests */
class DayCardFilterTest {
    private val lenient = Json { ignoreUnknownKeys = true }
    private val zone = ZoneId.of("America/Los_Angeles")

    private fun player(mode: GameMode?, venues: List<String> = listOf("v1"), noShows: Int = 0, times: List<RecurringTimeSlot> = emptyList()) =
        NearbyPlayer("u1", noShows, mode, venues.map { DayCandidate.Place(it, it) }, 0, times)

    private fun card(mode: GameMode = GameMode.Singles, mixed: Boolean = false, hour: Int = 19, venues: List<Pair<String, Double?>> = listOf("v1" to 2.0), noShows: Int = 0): DayCandidate {
        val start = ZonedDateTime.of(2026, 11, 21, hour, 0, 0, 0, zone).toInstant().toEpochMilli()
        return DayCandidate("t1", "u1", mode, mixed, start, start + 7_200_000L, noShows, venues.map { (id, km) -> DayCandidate.Place(id, id, km) })
    }

    @Test
    fun eventMatchesPreferredMode() {
        var filter = DayCardFilter(event = DayCardFilter.Event.Singles)
        assertTrue(filter.matches(player(GameMode.Singles), null))
        assertFalse(filter.matches(player(GameMode.Doubles), null))
        assertTrue("没填常打项目的都算", filter.matches(player(null), null))
        filter = filter.copy(event = DayCardFilter.Event.Mixed)
        assertTrue("混双算双打", filter.matches(player(GameMode.Doubles), null))
        assertFalse(filter.matches(player(GameMode.Singles), null))
    }

    @Test
    fun venuesLevelGenderAndReliability() {
        var filter = DayCardFilter(venueIds = setOf("v2"))
        assertFalse(filter.matches(player(null, listOf("v1")), null))
        assertTrue(filter.matches(player(null, listOf("v1", "v2")), null))

        filter = DayCardFilter(minLevel = 5)
        val user = User(id = "u1", nickname = "测试", phone = "", gender = Gender.Female, selfReportedLevel = 4)
        assertFalse(filter.matches(player(null), user))
        filter = filter.copy(minLevel = 1, gender = Gender.Male)
        assertFalse(filter.matches(player(null), user))

        filter = DayCardFilter(reliableOnly = true)
        assertFalse(filter.matches(player(null, noShows = 1), null))
        assertTrue(filter.matches(player(null), null))
    }

    @Test
    fun timesUseUsualTimesForNearby() {
        var filter = DayCardFilter(times = setOf(DayCardFilter.TimeOfDay.Morning))
        assertTrue("没填空闲时间的都算", filter.matches(player(null), null))
        val evenings = player(null, times = listOf(RecurringTimeSlot.create(dayOfWeek = 3, startHour = 19, endHour = 21)))
        assertFalse(filter.matches(evenings, null))
        filter = filter.copy(times = setOf(DayCardFilter.TimeOfDay.Morning, DayCardFilter.TimeOfDay.Evening))
        assertTrue(filter.matches(evenings, null))
        val weekend = player(null, times = listOf(RecurringTimeSlot.create(dayOfWeek = 7, startHour = 10, endHour = 14)))
        filter = filter.copy(times = setOf(DayCardFilter.TimeOfDay.Afternoon))
        assertTrue("10:00–14:00 也算下午", filter.matches(weekend, null))
    }

    // 下面是安卓补的：iPhone 的这些规则写在 DayCardFilter.swift 里，没有单独的测试

    @Test
    fun dayCardsFilterByEventAndStartTime() {
        val doubles = DayCardFilter(event = DayCardFilter.Event.Doubles)
        assertTrue(doubles.matches(card(GameMode.Doubles), null, zone))
        assertFalse("混双不算双打", doubles.matches(card(GameMode.Doubles, mixed = true), null, zone))
        assertTrue(DayCardFilter(event = DayCardFilter.Event.Mixed).matches(card(GameMode.Doubles, mixed = true), null, zone))
        val afternoon = DayCardFilter(times = setOf(DayCardFilter.TimeOfDay.Afternoon))
        assertTrue(afternoon.matches(card(hour = 14), null, zone))
        assertFalse("18 点开始算晚上", afternoon.matches(card(hour = 18), null, zone))
        assertFalse(DayCardFilter(reliableOnly = true).matches(card(noShows = 2), null, zone))
    }

    @Test
    fun venuePrefersPickedThenNearest() {
        val candidate = card(venues = listOf("far" to 8.0, "near" to 1.0, "unknown" to null))
        assertEquals("near", DayCardFilter().venue(candidate)?.id)
        assertEquals("far", DayCardFilter(venueIds = setOf("far")).venue(candidate)?.id)
    }

    @Test
    fun activeCountAndSavedFormat() {
        val filter = DayCardFilter(event = DayCardFilter.Event.Singles, minLevel = 3, gender = Gender.Female, reliableOnly = true)
        assertEquals(4, filter.activeCount)
        assertEquals(0, DayCardFilter().activeCount)
        val text = Json.encodeToString(DayCardFilter.serializer(), filter)
        assertEquals(filter, Json.decodeFromString(DayCardFilter.serializer(), text))
        // 老的存档少了字段也能读
        assertEquals(DayCardFilter(minLevel = 2), lenient.decodeFromString(DayCardFilter.serializer(), """{"minLevel":2,"future":1}"""))
    }
}
