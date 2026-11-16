package com.badie.app.shell

import com.badie.app.features.social.SocialTestSupport.BLAKE
import com.badie.app.features.social.SocialTestSupport.CASEY
import com.badie.app.features.social.SocialTestSupport.ME
import com.badie.app.features.social.SocialTestSupport.environment
import com.badie.app.models.Coordinate
import com.badie.app.models.Venue
import com.badie.app.remote.FakeServer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** 各块之间接起来的地方：位置和附近范围只有 LocationManager 一份，球局只有 GameBook 一份 */
@OptIn(ExperimentalCoroutinesApi::class)
class WiringTest {
    private val server = FakeServer()

    @Test
    fun everyoneReadsTheSameLocationAndRadius() = runTest {
        val env = environment(server, backgroundScope)
        val location = env.locationManager
        assertSame(location, env.matchManager.location)
        assertSame(location, env.roomManager.location)
        assertSame(location, env.groupManager.location)

        assertTrue(location.updateTravelRadius(25.0))
        assertEquals(25.0, env.roomManager.radiusKm, 0.0)
        assertEquals(25.0, env.groupManager.radiusKm, 0.0)

        // 找附近的局：有定位用定位，按现在的范围找
        val here = Coordinate(34.07, -118.03)
        location.currentLocation = here
        assertEquals(here, env.roomManager.center())
        assertEquals(here, env.groupManager.currentCenter())
        server.on("POST /rest/v1/rpc/rooms_near", "[]")
        server.requests.clear()
        env.roomManager.loadNearby()
        val args = server.json(0)
        assertEquals(25.0, args.getValue("radius_km").jsonPrimitive.double, 0.0)
        assertEquals(34.07, args.getValue("lat").jsonPrimitive.double, 0.0)
    }

    @Test
    fun changingTheRadiusReloadsNearbyGroups() = runTest {
        val env = environment(server, backgroundScope)
        repeat(2) { server.on("POST /rest/v1/rpc/groups_near", "[]") }
        val center = Coordinate(34.0, -118.0)
        env.groupManager.loadNearby(center, 10.0)
        env.groupManager.loadNearby(center, 10.0)
        assertEquals("同一个地方、同样的范围 60 秒内不重拉", 1, server.requests.size)
        env.groupManager.loadNearby(center, 20.0)
        assertEquals("范围变了就重拉", 2, server.requests.size)
    }

    @Test
    fun socialUsesTheGamesTab() = runTest {
        val env = environment(server, backgroundScope)
        val player = { id: String, name: String, team: Int -> """{"id":"$id","nickname":"$name","rating":4,"team":$team,"me":${id == ME}}""" }
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g1","mode":"singles","starts_at":"2026-10-10T18:00:00+00:00","ends_at":"2026-10-10T20:00:00+00:00","status":"scheduled",""" +
                """"venue":{"id":"v1","name":"Test Court"},"my_team":1,"review_until":"2026-10-12T20:00:00+00:00","my_report":{"outcome":"team1"},""" +
                """"players":[${player(ME, "Alex", 1)},${player(BLAKE, "Blake", 2)}]}]""",
        )
        // 球局页拉过一次：资料卡的“一起打过”直接用，不再自己拉
        env.roomManager.book.refresh()
        val requests = server.requests.size
        assertEquals(listOf("g1"), env.friendManager.gamesTogether(BLAKE).map { it.id })
        assertEquals("Test Court", env.friendManager.gamesTogether(BLAKE).single().venueName)
        env.friendManager.refreshGames()
        assertEquals("60 秒内拉过就不再拉", requests, server.requests.size)
        assertEquals("同局的人记进球友的缓存", "Blake", env.friendManager.user(BLAKE)?.nickname)
    }

    @Test
    fun venueRegularsCarryTheirVenue() = runTest {
        val env = environment(server, backgroundScope)
        server.on(
            "POST /rest/v1/rpc/venue_regulars",
            """[{"id":"$BLAKE","nickname":"Blake","rating":4.33,"venue":{"id":"v1"}},{"id":"$CASEY","nickname":"Casey","rating":3,"venue":{"id":"v-unknown"}}]""",
        )
        env.friendManager.refreshRegulars(force = true)
        val court = Venue("v1", "Los Angeles Badminton Club", lat = 34.07, lon = -118.03, street = "1 Main St", city = "El Monte", region = "CA", countryCode = "US")
        val regulars = env.friendManager.venueRegulars { if (it == "v1") court else null }
        assertEquals("球馆读不到的不列", listOf(BLAKE), regulars.map { it.first.id })
        assertEquals("Los Angeles Badminton Club", regulars.single().second.name)
    }

    @Test
    fun venuePageListsItsGroups() = runTest {
        val env = environment(server, backgroundScope)
        val summary = { id: String, venue: String, sessions: Int ->
            """{"id":"$id","name":"Group $id","level_min":2,"level_max":6,"join_policy":"open","venue":{"id":"$venue","name":"Court"},"schedules":[],"activity":{"sessions":$sessions,"average":6}}"""
        }
        server.on("POST /rest/v1/rpc/groups_near", "[${summary("a", "v1", 1)},${summary("b", "v1", 8)},${summary("c", "v2", 9)}]")
        val court = Venue("v1", "Court", lat = 34.07, lon = -118.03, street = "1 Main St", city = "El Monte", region = "CA", countryCode = "US")
        env.groupManager.loadAtVenue(court)
        assertEquals("只列这家，按活跃度排", listOf("b", "a"), env.groupManager.groups(atVenue = "v1").map { it.id })
        assertEquals("5.0", server.json(0).getValue("radius_km").jsonPrimitive.content)
        assertTrue("不动附近的球群那份列表", env.groupManager.nearbyGroups().isEmpty())
    }
}
