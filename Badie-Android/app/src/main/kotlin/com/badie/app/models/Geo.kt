package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.Serializable
import java.util.Locale
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// MARK: - 坐标

/** 地理坐标（WGS-84），用来算距离 */
@Serializable
data class Coordinate(val latitude: Double, val longitude: Double) {
    /** Haversine 距离（公里） */
    fun distanceKm(to: Coordinate): Double {
        val lat1 = Math.toRadians(latitude)
        val lat2 = Math.toRadians(to.latitude)
        val deltaLat = Math.toRadians(to.latitude - latitude)
        val deltaLon = Math.toRadians(to.longitude - longitude)
        val a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return EARTH_RADIUS_KM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /** Haversine 距离（英里） */
    fun distance(to: Coordinate): Double = distanceKm(to) / KILOMETERS_PER_MILE

    /** 在当前坐标基础上按公里偏移（东为正 x，北为正 y），用于生成附近的演示数据 */
    fun offsetBy(eastKm: Double, northKm: Double): Coordinate {
        val deltaLat = northKm / 110.574
        val deltaLon = eastKm / (111.320 * cos(Math.toRadians(latitude)))
        return Coordinate(latitude + deltaLat, longitude + deltaLon)
    }

    companion object {
        const val EARTH_RADIUS_KM = 6371.0088
        const val KILOMETERS_PER_MILE = 1.609344

        /** 默认城市中心（首发市场：洛杉矶圣盖博谷），没有定位权限时用 */
        val fallbackCenter = Coordinate(34.0686, -118.0276)
        /** 北京（演示和测试用） */
        val beijing = Coordinate(39.9219, 116.4433)
    }
}

// MARK: - 距离单位：跟着设备的地区走（美国、英国用英里，其他用公里）

enum class DistanceUnit {
    Kilometers, Miles;

    val title: String get() = if (this == Miles) tr("英里") else tr("公里")

    fun value(fromKm: Double): Double = if (this == Miles) fromKm / Coordinate.KILOMETERS_PER_MILE else fromKm

    fun km(from: Double): Double = if (this == Miles) from * Coordinate.KILOMETERS_PER_MILE else from

    companion object {
        val current: DistanceUnit get() = of(Locale.getDefault().country)

        fun of(region: String): DistanceUnit = if (region == "US" || region == "GB") Miles else Kilometers
    }
}

object DistanceFormatter {
    private fun oneDecimal(value: Double) = String.format(Locale.ROOT, "%.1f", value)

    /** 公里制：1 公里以内显示米；英里制：0.1 英里以内显示英尺，其余一位小数 */
    fun string(km: Double, unit: DistanceUnit = DistanceUnit.current): String = when (unit) {
        DistanceUnit.Kilometers ->
            if (km < 1) {
                tr("%lld 米", maxOf(10, roundHalfAway(km * 1000 / 10).toInt() * 10))
            } else {
                tr("%@ 公里", oneDecimal(km))
            }
        DistanceUnit.Miles -> {
            val miles = km / Coordinate.KILOMETERS_PER_MILE
            if (miles < 0.1) {
                tr("%lld 英尺", maxOf(50, roundHalfAway(miles * 5280 / 50).toInt() * 50))
            } else {
                tr("%@ 英里", oneDecimal(miles))
            }
        }
    }

    /** 别人离我多远：只给大概范围（“5 英里内”），防止多点定位出对方的住址 */
    fun approximate(km: Double, unit: DistanceUnit = DistanceUnit.current): String {
        val bands = if (unit == DistanceUnit.Miles) listOf(3, 5, 10, 25) else listOf(5, 10, 20, 40)
        val value = unit.value(km)
        val band = bands.firstOrNull { value <= it }
        return if (band != null) tr("%lld %@内", band, unit.title) else tr("%lld %@外", bands.last(), unit.title)
    }

    /** 出行范围这类整数距离：“10 公里” / “6 英里” */
    fun radius(km: Double, unit: DistanceUnit = DistanceUnit.current): String =
        "${roundHalfAway(unit.value(km)).toInt()} ${unit.title}"
}
