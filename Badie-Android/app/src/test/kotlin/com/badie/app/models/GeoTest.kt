package com.badie.app.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class GeoTest {
    @Test
    fun haversineDistanceBeijingToShanghai() {
        val beijing = Coordinate(39.9042, 116.4074)
        val shanghai = Coordinate(31.2304, 121.4737)
        // 实际大圆距离约 1067 公里
        assertEquals(1067.0, beijing.distanceKm(shanghai), 10.0)
        assertEquals(663.0, beijing.distance(shanghai), 7.0)
        assertEquals(0.0, beijing.distanceKm(beijing), 0.0001)
    }

    @Test
    fun offsetByKilometersRoundTrips() {
        val origin = Coordinate.fallbackCenter
        assertEquals(5.0, origin.distanceKm(origin.offsetBy(eastKm = 3.0, northKm = 4.0)), 0.05)
    }

    @Test
    fun distanceFormatter() {
        assertEquals("460 米", DistanceFormatter.string(0.456, DistanceUnit.Kilometers))
        assertEquals("2.3 公里", DistanceFormatter.string(2.34, DistanceUnit.Kilometers))
        assertEquals("2.0 英里", DistanceFormatter.string(3.2187, DistanceUnit.Miles))
        assertEquals("150 英尺", DistanceFormatter.string(0.05, DistanceUnit.Miles))
        assertEquals("10 英里", DistanceFormatter.radius(16.09344, DistanceUnit.Miles))
        assertEquals("10 公里", DistanceFormatter.radius(10.0, DistanceUnit.Kilometers))
        assertEquals("5 公里内", DistanceFormatter.approximate(3.0, DistanceUnit.Kilometers))
        assertEquals("40 公里外", DistanceFormatter.approximate(60.0, DistanceUnit.Kilometers))
        assertEquals(DistanceUnit.Miles, DistanceUnit.of("GB"))
        assertEquals(DistanceUnit.Kilometers, DistanceUnit.of("SG"))
    }

    @Test
    fun stableHashIsTheSameEverywhere() {
        // 和 iPhone、网站同一个算法：djb2，取低 31 位
        assertEquals(5381, "".stableHash)
        assertEquals(177670, "a".stableHash)
        assertNotEquals("u1".stableHash, "u2".stableHash)
        assertEquals(CardColor.default("u1"), CardColor.default("u1"))
        assertNotEquals(CardColor.Ink, CardColor.default("anyone"))
    }
}
