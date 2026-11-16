package com.badie.app.features.venues

import com.badie.app.models.Coordinate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URI

/** 地图链接解析。对应 iPhone 的 VenueTests 里“Map links”那几条 */
class MapLinkParserTest {
    @Test
    fun googleMapsPlaceLinkUsesPinCoordinate() {
        val url = URI(
            "https://www.google.com/maps/place/Los+Angeles+Badminton+Club/@34.0760,-118.0500,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d34.0764690!4d-118.0461160",
        )
        val link = MapLinkParser.parse(url)!!
        assertEquals(ParsedMapLink.Provider.Google, link.provider)
        assertEquals("Los Angeles Badminton Club", link.name)
        assertEquals(34.076469, link.coordinate!!.latitude, 0.000001)
        assertEquals(-118.046116, link.coordinate!!.longitude, 0.000001)
    }

    @Test
    fun googleSearchAndQueryLinks() {
        val search = MapLinkParser.parse(URI("https://www.google.com/maps/search/?api=1&query=Elite+Rally+Badminton&query_place_id=ChIJabc"))!!
        assertEquals("Elite Rally Badminton", search.query)
        assertEquals("ChIJabc", search.googlePlaceId)
        val coordinate = MapLinkParser.parse(URI("https://maps.google.com/?q=34.07,-118.04"))!!
        assertEquals(Coordinate(34.07, -118.04), coordinate.coordinate)
    }

    @Test
    fun appleMapsLinks() {
        val ll = MapLinkParser.parse(URI("https://maps.apple.com/?ll=34.0765,-118.0461&q=LABC"))!!
        assertEquals(ParsedMapLink.Provider.Apple, ll.provider)
        assertEquals("LABC", ll.name)
        assertEquals(Coordinate(34.0765, -118.0461), ll.coordinate)
        val place = MapLinkParser.parse(URI("https://maps.apple.com/place?place-id=I8BD5B9976F940FB5&_provider=9902"))!!
        assertEquals("I8BD5B9976F940FB5", place.applePlaceId)
    }

    @Test
    fun findsMapLinkInsideSharedText() {
        val url = MapLinkParser.firstMapURL("周六去这里打 👉 https://maps.app.goo.gl/AbCdEf123 （停车在后面）")
        assertEquals("maps.app.goo.gl", url?.host)
        assertTrue(MapLinkParser.needsExpansion(url!!))
        assertNull(MapLinkParser.firstMapURL("https://example.com/not-a-map"))
        assertFalse(MapLinkParser.needsExpansion(URI("https://www.google.com/maps/place/X/@1,2,17z")))
    }

    @Test
    fun rejectsInvalidCoordinates() {
        assertNull(MapLinkParser.coordinate("0,0"))
        assertNull(MapLinkParser.coordinate("123,45"))
        assertNotNull(MapLinkParser.coordinate("-33.86, 151.21"))
    }

    @Test
    fun pastedTextBecomesSearchOrAddDraft() = runTest {
        assertEquals(PastedLink.Search("LABC"), handlePastedLink("  LABC \n"))
        val add = handlePastedLink("https://maps.google.com/?q=34.07,-118.04") as PastedLink.Add
        assertEquals(Coordinate(34.07, -118.04), add.draft.coordinate)
        assertTrue(add.draft.fromLink)
        assertEquals(PastedLink.Search("Elite Rally Badminton"), handlePastedLink("https://www.google.com/maps/search/?api=1&query=Elite+Rally+Badminton"))
    }
}
