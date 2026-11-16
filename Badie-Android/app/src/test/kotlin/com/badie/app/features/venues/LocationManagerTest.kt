package com.badie.app.features.venues

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.Backend
import com.badie.app.models.Coordinate
import com.badie.app.models.UserPreferences
import com.badie.app.models.VenueStatus
import com.badie.app.remote.FakeServer
import com.badie.app.shell.AppState
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 位置、附近的球馆、附近范围、常去球馆、确认地址。对应 iPhone 的 LocationManager */
class LocationManagerTest {
    private val server = FakeServer()
    private var clock = TestSupport.CLOCK
    private val here = Coordinate(34.07, -118.03)

    private class FakeSource(var location: Coordinate?, override var isAuthorized: Boolean = true) : LocationManager.LocationSource {
        var calls = 0
        override suspend fun current(): Coordinate? {
            calls++
            return location
        }
    }

    private fun manager(
        backend: Backend = TestSupport.backend(server, TestSupport.session()),
        settings: LocationManager.Settings = LocationManager.Settings.Memory(),
        source: LocationManager.LocationSource? = FakeSource(here),
    ): LocationManager {
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val context = ManagerContext(scope, backend, AppState(scope, backend), android = null)
        return LocationManager(context, settings, source) { clock }
    }

    private fun venueRow(id: String, lat: Double = 34.071, status: String = "verified") =
        """{"id":"$id","name":"Arena $id","aliases":[],"lat":$lat,"lon":-118.03,"street":"1 Main St","city":"El Monte","region":"CA",""" +
            """"postal_code":"91731","country_code":"US","status":"$status","source":"player","created_at":"2026-10-17T23:17:25+00:00",""" +
            """"amenities":["parking"],"operating_hours":{"open":"08:00","close":"22:00"},"location":"0101000020E6100000"}"""

    private fun serveNearby(vararg rows: String) {
        server.on("POST /rest/v1/rpc/venues_near", rows.joinToString(",", "[", "]") { """{"venue":$it,"distance_m":100}""" })
        server.on("GET /rest/v1/venue_regular_counts", """[{"venue_id":"v-1","regulars":4}]""")
    }

    private suspend fun signedIn(): Backend {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        server.requests.clear()
        return backend
    }

    @Test
    fun travelRadiusIsValidatedAndRemembered() {
        val settings = LocationManager.Settings.Memory()
        val first = manager(settings = settings, source = null)
        assertEquals(UserPreferences.DEFAULT_TRAVEL_RADIUS, first.preferences.travelRadiusKm, 0.0)
        assertFalse(first.updateTravelRadius(60.0))
        assertFalse(first.updateTravelRadius(0.5))
        assertTrue(first.updateTravelRadius(25.0))
        assertEquals(25.0, manager(settings = settings, source = null).preferences.travelRadiusKm, 0.0)
        // 存坏了的值不用
        settings.setDouble(LocationManager.KEY_RADIUS, 500.0)
        assertEquals(UserPreferences.DEFAULT_TRAVEL_RADIUS, manager(settings = settings, source = null).preferences.travelRadiusKm, 0.0)
    }

    @Test
    fun startLocatesAndLoadsNearbyVenuesOncePerArea() = runTest {
        val source = FakeSource(here)
        val manager = manager(source = source)
        serveNearby(venueRow("v-2", lat = 34.09), venueRow("v-1"))
        manager.start()
        assertEquals(here, manager.currentLocation)
        assertEquals(here, manager.coordinate)
        assertEquals(listOf("v-1", "v-2"), manager.nearbyCourts.map { it.id })
        val args = server.json(0)
        assertEquals(34.07, args.getValue("lat").jsonPrimitive.double, 0.0)
        assertEquals(10.0, args.getValue("radius_km").jsonPrimitive.double, 0.0)
        assertEquals(4, manager.regularsCount("v-1"))
        assertEquals(0, manager.regularsCount("v-2"))
        assertTrue("服务器上设施、营业时间的写法和本机不同，读不懂也不影响", manager.court("v-1") != null)

        // 同一片区域 10 分钟内不再拉，位置 5 分钟内不再取
        val requests = server.requests.size
        clock += 60_000
        manager.start()
        assertEquals(requests, server.requests.size)
        assertEquals(1, source.calls)

        // 下拉刷新：重新取位置、重新拉
        serveNearby(venueRow("v-1"))
        manager.refresh()
        assertEquals(2, source.calls)
        assertEquals(listOf("v-1"), manager.nearbyCourts.map { it.id })
    }

    @Test
    fun withoutPermissionUsesFallbackCenterAndNoNearest() = runTest {
        val source = FakeSource(here, isAuthorized = false)
        val manager = manager(source = source)
        serveNearby(venueRow("v-1"))
        manager.start()
        assertEquals(0, source.calls)
        assertEquals(Coordinate.fallbackCenter, manager.coordinate)
        assertNull("没定位时不按默认城市猜最近的球馆", manager.nearestCourtToUser)
        assertFalse(manager.isDenied)
        manager.permissionAnswered(false)
        assertTrue(manager.isDenied)
    }

    @Test
    fun nearestCourtUsesRealLocation() = runTest {
        val manager = manager()
        serveNearby(venueRow("v-pending", lat = 34.0705, status = "unconfirmed"), venueRow("v-1", lat = 34.09))
        manager.start()
        assertEquals("优先已确认的球馆", "v-1", manager.nearestCourtToUser?.id)
    }

    @Test
    fun togglingFavoriteWritesToServer() = runTest {
        val manager = manager(backend = signedIn())
        server.on("POST /rest/v1/favorite_venues", "")
        server.on("GET /rest/v1/venue_regular_counts", """[{"venue_id":"v-1","regulars":1}]""")
        manager.toggleFavorite("v-1")
        assertTrue(manager.isFavorite("v-1"))
        assertEquals(listOf("v-1"), manager.favoriteCourtIds)
        assertEquals("/rest/v1/favorite_venues", server.path(0))
        assertEquals("v-1", server.json(0).getValue("venue_id").jsonPrimitive.content)
        assertEquals(1, manager.regularsCount("v-1"))

        server.on("DELETE /rest/v1/favorite_venues", "")
        manager.toggleFavorite("v-1")
        assertFalse(manager.isFavorite("v-1"))
        assertTrue(server.query(2)!!.contains("venue_id=eq.v-1"))
    }

    @Test
    fun failedFavoriteShowsErrorAndRestores() = runTest {
        val backend = signedIn()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val appState = AppState(scope, backend)
        val manager = LocationManager(ManagerContext(scope, backend, appState, null), LocationManager.Settings.Memory(), null) { clock }
        server.on("POST /rest/v1/favorite_venues", """{"message":"boom"}""", status = 500)
        server.serveProfile("[${TestSupport.profile()}]")
        manager.toggleFavorite("v-1")
        assertFalse("按服务器的恢复", manager.isFavorite("v-1"))
        assertTrue(appState.toast != null)
    }

    @Test
    fun confirmingRemembersItLocally() = runTest {
        val settings = LocationManager.Settings.Memory()
        val manager = manager(backend = signedIn(), settings = settings)
        server.on("POST /rest/v1/rpc/confirm_venue", venueRow("v-1", status = "unconfirmed"))
        assertFalse(manager.hasConfirmed("v-1"))
        manager.confirmVenue("v-1")
        assertTrue(manager.hasConfirmed("v-1"))
        val venue = manager.court("v-1")!!
        assertEquals("状态以服务器为准", VenueStatus.Unconfirmed, venue.status)
        assertEquals(listOf(TestSupport.USER_ID), venue.confirmedBy)
        assertEquals("v-1", server.json(0).getValue("target").jsonPrimitive.content)
    }

    @Test
    fun searchCombinesServerResultsWithNearbyVenues() = runTest {
        val manager = manager()
        serveNearby(venueRow("v-1"))
        manager.start()
        server.on("GET /rest/v1/venues", "[${venueRow("v-9", lat = 34.2).replace("Arena v-9", "Rally Point")}]")
        server.on("GET /rest/v1/venue_regular_counts", "[]")
        val hits = manager.searchCourts("arena")
        assertEquals("附近的也能搜到", listOf("v-1"), hits.map { it.venue.id })
    }
}
