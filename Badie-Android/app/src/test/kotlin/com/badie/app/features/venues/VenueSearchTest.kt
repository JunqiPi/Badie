package com.badie.app.features.venues

import com.badie.app.models.Coordinate
import com.badie.app.models.Venue
import com.badie.app.models.VenueStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 球馆搜索：别名、缩写、拼音、地址、距离。对应 iPhone 的 VenueTests 里“Search”那几条（拼音要系统的 ICU，所以在模拟的 Android 里跑） */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class VenueSearchTest {
    private val la = Coordinate(34.0686, -118.0276)

    private fun venue(
        id: String, name: String, aliases: List<String> = emptyList(), at: Coordinate = la,
        street: String = "1 Main St", city: String = "El Monte", country: String = "US", status: VenueStatus = VenueStatus.Verified,
    ) = Venue(
        id, name, aliases = aliases, lat = at.latitude, lon = at.longitude, street = street, city = city,
        region = if (country == "US") "CA" else "北京市", postalCode = if (country == "US") "91731" else "", countryCode = country, status = status,
    )

    @Test
    fun acronymAndAliasSearch() {
        val labc = venue("labc", "Los Angeles Badminton Club", aliases = listOf("洛杉矶羽毛球俱乐部"))
        val other = venue("other", "Arena Badminton", at = la.offsetBy(2.0, 0.0))
        assertEquals("labc", VenueSearch.acronym("Los Angeles Badminton Club"))
        assertEquals("labc", VenueSearch.search(listOf(other, labc), "LABC", la).first().venue.id)
        assertEquals("labc", VenueSearch.search(listOf(other, labc), "洛杉矶", la).first().venue.id)
        assertEquals("labc", VenueSearch.search(listOf(other, labc), "angeles bad", la).first().venue.id)
        assertEquals("洛杉矶羽毛球俱乐部", VenueSearch.matchedAlias(labc, "洛杉矶"))
        assertNull("名字里就有，不显示又名", VenueSearch.matchedAlias(labc, "angeles"))
    }

    @Test
    fun addressAndZipSearch() {
        val elite = venue("elite", "Elite Rally Badminton Club", street = "4800 Rivergrade Rd", city = "Baldwin Park")
        assertEquals("elite", VenueSearch.search(listOf(elite), "rivergrade", la).first().venue.id)
        assertEquals("elite", VenueSearch.search(listOf(elite), "91731", la).first().venue.id)
        assertTrue(VenueSearch.search(listOf(elite), "pickleball", la).isEmpty())
    }

    @Test
    fun pinyinSearchForChineseNames() {
        val beijing = Coordinate.beijing
        val haidian = venue("v-cn-bj-haidian", "海淀体育馆", at = beijing, street = "中关村大街", city = "海淀区", country = "CN")
        val other = venue("v-cn-bj-other", "国家体育馆", at = beijing.offsetBy(3.0, 0.0), street = "天辰东路", city = "朝阳区", country = "CN")
        assertEquals("v-cn-bj-haidian", VenueSearch.search(listOf(other, haidian), "hdty", beijing).first().venue.id)
        assertEquals("v-cn-bj-haidian", VenueSearch.search(listOf(other, haidian), "haidian", beijing).first().venue.id)
    }

    @Test
    fun closerVenueRanksFirstForEqualMatches() {
        val near = venue("near", "Badminton Center", at = la.offsetBy(1.0, 0.0))
        val far = venue("far", "Badminton Center", at = la.offsetBy(60.0, 0.0))
        assertEquals(listOf("near", "far"), VenueSearch.search(listOf(far, near), "badminton center", la).map { it.venue.id })
    }

    @Test
    fun confirmedVenuesGetASmallBonus() {
        val pending = venue("pending", "Rally Point", status = VenueStatus.Unconfirmed)
        val listed = venue("listed", "Rally Point", at = la.offsetBy(1.0, 0.0))
        assertEquals("listed", VenueSearch.search(listOf(pending, listed), "rally point", la).first().venue.id)
    }

    @Test
    fun normalizeFoldsWidthAccentsAndPunctuation() {
        assertEquals("labc 2", VenueSearch.normalize("ＬＡＢＣ — 2!"))
        assertEquals("cafe badminton", VenueSearch.normalize("Café   Badminton"))
        assertEquals(0 until 4, VenueSearch.matchRange("Café Club", "cafe"))
        assertNull(VenueSearch.matchRange("Club", "arena"))
    }
}
