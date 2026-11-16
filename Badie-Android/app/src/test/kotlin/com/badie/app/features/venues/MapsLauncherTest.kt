package com.badie.app.features.venues

import com.badie.app.models.CoordinateDatum
import com.badie.app.models.NavigationApp
import com.badie.app.models.Venue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 导航：按国家给的地图 App（去掉 Apple 地图）和打开的地址 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class MapsLauncherTest {
    private fun venue(country: String, datum: CoordinateDatum = CoordinateDatum.Wgs84) =
        Venue("v-1", "朝阳体育中心", lat = 39.9219, lon = 116.4433, street = "工体北路4号", city = "朝阳区", countryCode = country, datum = datum)

    @Test
    fun appleMapsIsLeftOut() {
        assertEquals(listOf(NavigationApp.GoogleMaps, NavigationApp.Waze), MapsLauncher.apps(venue("US")))
        assertEquals(listOf(NavigationApp.Amap, NavigationApp.Baidu), MapsLauncher.apps(venue("CN")))
        assertFalse(MapsLauncher.apps(venue("KR")).contains(NavigationApp.AppleMaps))
        assertNull(MapsLauncher.uri(venue("US"), NavigationApp.AppleMaps))
    }

    @Test
    fun universalLinksAndSchemes() {
        assertEquals(
            "https://www.google.com/maps/dir/?api=1&destination=39.921900%2C116.443300",
            MapsLauncher.uri(venue("US"), NavigationApp.GoogleMaps).toString(),
        )
        val amap = MapsLauncher.uri(venue("CN"), NavigationApp.Amap)!!
        assertEquals("amapuri", amap.scheme)
        assertEquals("1", amap.getQueryParameter("dev"))
        assertEquals("0", MapsLauncher.uri(venue("CN", CoordinateDatum.Gcj02), NavigationApp.Amap)!!.getQueryParameter("dev"))
        assertEquals("gcj02", MapsLauncher.uri(venue("CN", CoordinateDatum.Gcj02), NavigationApp.Baidu)!!.getQueryParameter("coord_type"))
        assertEquals("39.921900,116.443300", MapsLauncher.uri(venue("KR"), NavigationApp.Kakao)!!.getQueryParameter("ep"))
    }
}
