package com.badie.app.backend

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.models.Coordinate
import com.badie.app.models.PostalAddress
import com.badie.app.models.VenueSource
import com.badie.app.models.VenueStatus
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** 球馆的读写：添加、查重、确认、报错、球馆里的人。对应 iPhone 的 MockBackend+RemoteVenues.swift */
class VenueApiTest {
    private val server = FakeServer()
    private val backend = TestSupport.backend(server, TestSupport.session())

    private fun venueRow(id: String, name: String = "Arena", mergedInto: String? = null) =
        """{"id":"$id","name":"$name","aliases":["AB"],"lat":34.07,"lon":-118.03,"street":"1 Main St","city":"El Monte","region":"CA",""" +
            """"postal_code":"91731","country_code":"US","status":"unconfirmed","source":"player","created_at":"2026-10-17T23:17:25+00:00",""" +
            """"merged_into":${mergedInto?.let { "\"$it\"" } ?: "null"},"amenities":["parking"],"checked_on":"2026-10-01"}"""

    private val candidate = VenueCandidate(
        "Rally Point", Coordinate(34.07, -118.03),
        PostalAddress.create("1 Main St", null, "El Monte", "CA", "91731", "us"), timeZoneId = "America/Los_Angeles",
    )

    @Test
    fun searchUsesTheServerSearch() = runTest {
        server.on("POST /rest/v1/rpc/search_venues", "[${venueRow("v-a", "Rally Point")}]")
        val found = backend.searchVenues(" rally ", Coordinate(34.0, -118.0))
        assertEquals(listOf("v-a"), found.map { it.id })
        assertEquals("/rest/v1/rpc/search_venues", server.path(0))
        val args = server.json(0)
        assertEquals("rally", args.getValue("q").jsonPrimitive.content)
        assertEquals("34.0", args.getValue("lat").jsonPrimitive.content)
        assertNotNull("搜到的放进缓存", backend.venue("v-a"))

        // 服务器没找到（或者还没有这个函数）：按名字、地址、城市直接查表
        server.requests.clear()
        server.on("POST /rest/v1/rpc/search_venues", "[]")
        server.on("GET /rest/v1/venues", """[{"id":"v-b","name":"Other","lat":34.07,"lon":-118.03,"street":"1 Main St","country_code":"US"}]""")
        assertEquals(listOf("v-b"), backend.searchVenues("Main St").map { it.id })
        val query = server.query(1)!!
        assertTrue(query, query.contains("street.ilike.*Main St*") || query.contains("street.ilike.*Main+St*"))
        assertEquals("没给位置就不传", "null", server.json(0).getValue("lat").toString())
        assertTrue("空的不搜", backend.searchVenues("  ").isEmpty())
    }

    @Test
    fun addVenueSendsOnlyWhatIsFilledIn() = runTest {
        server.on("POST /rest/v1/rpc/add_venue", venueRow("v-new", "Rally Point"))
        val venue = backend.addVenue(candidate, listOf(" RP ", ""), courtCount = null, entranceNote = "  ")
        assertEquals("v-new", venue.id)
        assertEquals(VenueSource.Player, venue.source)
        assertNotNull("加好的球馆放进缓存", backend.venue("v-new"))
        val args = server.json(0)
        assertEquals("player", args.getValue("source").jsonPrimitive.content)
        assertEquals("wgs84", args.getValue("datum").jsonPrimitive.content)
        assertEquals("US", args.getValue("country_code").jsonPrimitive.content)
        assertEquals(listOf("RP"), args.getValue("aliases").jsonArray.map { it.jsonPrimitive.content })
        assertEquals("America/Los_Angeles", args.getValue("time_zone_id").jsonPrimitive.content)
        assertFalse("没填的不传", "court_count" in args || "entrance_note" in args || "unit" in args || "phone" in args)
    }

    @Test
    fun chineseVenuesUseGcj02() = runTest {
        server.on("POST /rest/v1/rpc/add_venue", venueRow("v-cn"))
        val cn = candidate.copy(address = PostalAddress.create("工体北路4号", null, "朝阳区", "北京市", "", "CN"))
        backend.addVenue(cn, emptyList(), courtCount = 6, entranceNote = "后门进")
        val args = server.json(0)
        assertEquals("gcj02", args.getValue("datum").jsonPrimitive.content)
        assertEquals("6", args.getValue("court_count").jsonPrimitive.content)
        assertEquals("后门进", args.getValue("entrance_note").jsonPrimitive.content)
    }

    @Test
    fun serverErrorsComeBackAsMessages() = runTest {
        server.on("POST /rest/v1/rpc/add_venue", """{"message":"venue_rate_limited"}""", status = 400)
        try {
            backend.addVenue(candidate, emptyList(), null, null)
            fail()
        } catch (error: RemoteError) {
            assertEquals("今天添加的球馆已达上限，明天再试。", error.message)
        }
    }

    @Test
    fun duplicatesLoadTheVenuesTheyPointTo() = runTest {
        server.on(
            "POST /rest/v1/rpc/venue_duplicates",
            """[{"venue_id":"v-a","venue_name":"Rally Point","kind":"likely","distance_m":35.5},""" +
                """{"venue_id":"v-b","venue_name":"Other","kind":"same_building","distance_m":12}]""",
        )
        server.on("GET /rest/v1/venues", "[${venueRow("v-a", "Rally Point")},${venueRow("v-b", "Other")}]")
        val duplicates = backend.venueDuplicates(candidate)
        assertEquals(listOf("v-a", "v-b"), duplicates.map { it.venue.id })
        assertEquals(listOf(DuplicateKind.Likely, DuplicateKind.SameBuilding), duplicates.map { it.kind })
        assertTrue(duplicates[0].kind.blocksAdding)
        assertFalse(duplicates[1].kind.blocksAdding)
        assertEquals(35.5, duplicates[0].distanceMeters, 0.0)
        assertEquals("Rally Point", server.json(0).getValue("name").jsonPrimitive.content)
        assertTrue(server.query(1)!!.contains("id=in."))
    }

    @Test
    fun noDuplicatesNeedsNoSecondRequest() = runTest {
        server.on("POST /rest/v1/rpc/venue_duplicates", "[]")
        assertTrue(backend.venueDuplicates(candidate).isEmpty())
        assertEquals(1, server.requests.size)
    }

    @Test
    fun fetchVenueFollowsMerges() = runTest {
        server.on("GET /rest/v1/venues", "[${venueRow("v-old", mergedInto = "v-kept")}]")
        server.on("GET /rest/v1/venues", "[${venueRow("v-kept", "Kept")}]")
        assertEquals("v-kept", backend.fetchVenue("v-old")?.id)
        assertTrue(server.query(1)!!.contains("id=eq.v-kept"))
        server.on("GET /rest/v1/venues", "[]")
        assertNull(backend.fetchVenue("v-gone"))
    }

    @Test
    fun confirmAndReport() = runTest {
        server.on("POST /rest/v1/rpc/confirm_venue", venueRow("v-1").replace("unconfirmed", "confirmed"))
        assertEquals(VenueStatus.Confirmed, backend.confirmVenue("v-1").status)
        server.on("POST /rest/v1/rpc/report_venue", "")
        backend.reportVenue("v-1", VenueIssue.NotBadminton, "x".repeat(300))
        val args = server.json(1)
        assertEquals("not_badminton", args.getValue("issue").jsonPrimitive.content)
        assertEquals(200, args.getValue("detail").jsonPrimitive.content.length)
    }

    @Test
    fun venuePeopleSkipsMe() = runTest {
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        val me = TestSupport.USER_ID
        server.on(
            "POST /rest/v1/rpc/venue_people",
            """{"recent":[{"id":"u-1","nickname":"欣然","tag":42,"rating":4.33,"gender":"female","card_color":"mint"},""" +
                """{"id":"$me","nickname":"Alex","rating":4.0}],"regulars":[{"id":"u-2","nickname":"阿杰","rating":3.0,"preferred_mode":"singles"}]}""",
        )
        val people = backend.venuePeople("v-1")
        assertEquals(listOf("u-1"), people.recent.map { it.id })
        assertEquals(listOf("u-2"), people.regulars.map { it.id })
        val xinran = people.recent.first()
        assertEquals(42, xinran.tag)
        assertEquals(4.33, xinran.selfReportedRating!!, 0.0)
        assertEquals("v-1", server.json(server.requests.size - 1).getValue("p_venue").jsonPrimitive.content)
    }

    @Test
    fun regularCountsDefaultToZero() = runTest {
        server.on("GET /rest/v1/venue_regular_counts", """[{"venue_id":"v-1","regulars":3}]""")
        assertEquals(mapOf("v-1" to 3, "v-2" to 0), backend.regularCounts(listOf("v-1", "v-2", "v-1")))
        assertTrue(backend.regularCounts(emptyList()).isEmpty())
    }
}
