package com.badie.app.features.matching

import com.badie.app.models.Coordinate
import com.badie.app.models.GameMode
import com.badie.app.models.OperatingHours
import com.badie.app.models.ReputationScore
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.addingDays
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 对应 iPhone 的 MatchingServiceTests。iPhone 用打包的北京球馆，这里用两家同样位置的测试球馆 */
class MatchingServiceTest {
    private val center = Coordinate.beijing
    private val tomorrow = addingDays(System.currentTimeMillis(), 1)

    private val courts = listOf(
        venue("bj-1", center),
        venue("bj-2", center.offsetBy(eastKm = 3.0, northKm = 2.0)),
    )

    private fun venue(id: String, at: Coordinate, hours: OperatingHours? = null) = Venue(
        id, id, lat = at.latitude, lon = at.longitude, street = "测试路1号", city = "朝阳区", region = "北京市", countryCode = "CN", operatingHours = hours,
    )

    private fun player(id: String, level: Int, eastKm: Double, slots: List<TimeSlot>, venues: List<Venue> = emptyList()): PlayerAvailability {
        val location = center.offsetBy(eastKm = eastKm, northKm = 0.0)
        val user = User(id = id, nickname = id, phone = "", selfReportedLevel = level, location = location)
            .copy(reputation = ReputationScore(10, level.toDouble(), 0.2, 95.0, 4.6))
        return PlayerAvailability(user, location, slots, venues)
    }

    private fun slot(start: Int, end: Int): TimeSlot = TimeSlot.on(tomorrow, startHour = start, endHour = end)!!

    private fun request(
        mode: GameMode = GameMode.Singles, tolerance: Int = 1, radius: Double = 10.0, excluded: Set<String> = emptySet(), courts: List<Venue> = this.courts,
    ) = MatchRequest(mode, slot(19, 21), courts, tolerance, "me", 4, center, radius, excluded)

    @Test
    fun filtersByRadiusSkillAndTime() {
        val pool = listOf(
            player("near-same", 4, 1.0, listOf(slot(19, 22))),
            player("too-far", 4, 30.0, listOf(slot(19, 22))),
            player("too-strong", 7, 1.0, listOf(slot(19, 22))),
            player("no-time", 4, 1.0, listOf(slot(8, 10))),
            player("me", 4, 0.0, listOf(slot(19, 22))),
        )
        assertEquals(listOf("near-same"), MatchingService.candidates(request(), pool).map { it.id })
    }

    @Test
    fun ordersBySkillDifferenceThenDistance() {
        val pool = listOf(
            player("diff1-near", 5, 0.5, listOf(slot(19, 21))),
            player("same-far", 4, 8.0, listOf(slot(19, 21))),
            player("same-near", 4, 2.0, listOf(slot(19, 21))),
        )
        assertEquals(listOf("same-near", "same-far", "diff1-near"), MatchingService.candidates(request(), pool).map { it.id })
    }

    @Test
    fun excludedUsersAreSkipped() {
        val pool = listOf(player("blocked", 4, 1.0, listOf(slot(19, 21))))
        assertTrue(MatchingService.candidates(request(excluded = setOf("blocked")), pool).isEmpty())
    }

    @Test
    fun singlesProposalUsesOverlapAndCost() {
        val proposals = MatchingService.proposals(request(), listOf(player("a", 4, 1.0, listOf(slot(20, 23)))))
        assertEquals(1, proposals.size)
        val proposal = proposals[0]
        assertEquals(slot(20, 21).startTime, proposal.commonOverlap.startTime)
        assertEquals(3_600_000L, proposal.slot.duration)
        assertEquals(listOf(listOf("me"), listOf("a")), proposal.teams)
        assertEquals(2, proposal.cost.players)
        assertTrue(proposal.compatibility in 35..99)
    }

    @Test
    fun doublesNeedsThreeWithCommonOverlap() {
        val pool = listOf(
            player("a", 5, 1.0, listOf(slot(19, 21))),
            player("b", 3, 2.0, listOf(slot(19, 21))),
            player("c", 4, 3.0, listOf(slot(19, 21))),
            player("d", 4, 1.0, listOf(slot(8, 10))),
        )
        val proposals = MatchingService.proposals(request(GameMode.Doubles), pool)
        assertFalse(proposals.isEmpty())
        val first = proposals[0]
        assertEquals(setOf("a", "b", "c"), first.others.map { it.id }.toSet())
        assertEquals(2, first.teams.size)
        assertEquals(4, first.teams.flatten().size)
    }

    @Test
    fun candidatesMustShareAVenue() {
        val sameVenue = player("same-venue", 4, 1.0, listOf(slot(19, 21)), listOf(courts[0]))
        val elsewhere = player("elsewhere", 4, 1.0, listOf(slot(19, 21)), listOf(venue("far", courts[0].location.offsetBy(6.0, 6.0))))
        // 别人加的“隔壁馆”，离我选的球馆 100 米：算同一处
        val annex = player("annex", 4, 2.0, listOf(slot(19, 21)), listOf(venue("annex", courts[1].location.offsetBy(0.1, 0.0))))
        val candidates = MatchingService.candidates(request(), listOf(sameVenue, elsewhere, annex))
        assertEquals(setOf("same-venue", "annex"), candidates.map { it.id }.toSet())
        assertEquals(listOf(courts[1].id), candidates.first { it.id == "annex" }.courtIds)
        assertEquals("只在双方都能去的球馆约", courts[1].id, MatchingService.proposals(request(), listOf(annex)).firstOrNull()?.court?.id)
    }

    @Test
    fun doublesUsesVenueEveryoneCanReach() {
        val a = player("a", 4, 0.5, listOf(slot(19, 21)), courts)
        val b = player("b", 4, 0.5, listOf(slot(19, 21)), listOf(courts[1]))
        val c = player("c", 4, 0.5, listOf(slot(19, 21)))
        assertEquals(courts[1].id, MatchingService.proposals(request(GameMode.Doubles), listOf(a, b, c)).firstOrNull()?.court?.id)
    }

    @Test
    fun balancedTeams() {
        val teams = MatchingService.balancedTeams(listOf("a" to 7.0, "b" to 2.0, "c" to 5.0, "d" to 4.0))
        // 7+2 vs 5+4
        assertEquals(listOf(listOf("a", "b"), listOf("c", "d")), teams)
    }

    @Test
    fun suggestionsOnlyIncludeOptionsThatWork() {
        val pool = listOf(player("strong", 6, 1.0, listOf(slot(19, 21))))
        assertTrue(MatchingService.proposals(request(tolerance = 1), pool).isEmpty())
        val suggestions = MatchingService.suggestions(request(tolerance = 1), pool)
        assertEquals(MatchRelaxation.WidenSkill(2), suggestions.first())
        assertFalse("放宽时间并不能找到人，不应建议", MatchRelaxation.WidenTime(1) in suggestions)
    }

    @Test
    fun bestCourtPrefersOpenCourt() {
        val closed = venue("closed", center, OperatingHours(8, 0, 12, 0, (1..7).toList()))
        val open = venue("open", center.offsetBy(5.0, 0.0), OperatingHours.standard)
        assertEquals("open", MatchingService.bestCourt(request(courts = listOf(closed, open)), listOf(center), slot(19, 21))?.id)
    }

    @Test
    fun unknownHoursCountAsOpenButKnownClosedIsSkipped() {
        val closed = venue("closed", center, OperatingHours(8, 0, 12, 0, (1..7).toList()))
        val unknown = venue("unknown", center.offsetBy(8.0, 0.0))
        assertEquals("unknown", MatchingService.bestCourt(request(courts = listOf(closed, unknown)), listOf(center), slot(19, 21))?.id)
    }
}
