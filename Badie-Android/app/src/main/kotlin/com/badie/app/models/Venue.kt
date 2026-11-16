package com.badie.app.models

import kotlinx.serialization.Serializable

/** 地址的写法：美国这类“街道, 城市, 州”从小到大；中日韩台从大到小、不加逗号 */
enum class AddressStyle {
    SmallToLarge, LargeToSmall;

    companion object {
        fun of(countryCode: String): AddressStyle =
            if (countryCode.uppercase() in setOf("CN", "TW", "JP", "KR")) LargeToSmall else SmallToLarge
    }
}

/**
 * 球馆（服务器 venues 表的一行，只取列表和选球馆要用的几列）。
 * 对应 iPhone 的 BadmintonCourt；营业时间、价格这些到球馆那一步再加
 */
@Serializable
data class Venue(
    val id: String,
    val name: String,
    val aliases: List<String>? = null,
    val lat: Double,
    val lon: Double,
    val street: String? = null,
    val unit: String? = null,
    val city: String? = null,
    val region: String? = null,
    val countryCode: String,
    /** confirmed / unconfirmed / … */
    val status: String = "confirmed",
    /** 坐标只是大概（目录里有些球馆只知道在哪个区），不拿来算“离我最近” */
    val locationApproximate: Boolean? = null,
) {
    val location: Coordinate get() = Coordinate(lat, lon)

    fun distanceKm(from: Coordinate): Double = location.distanceKm(from)

    private val style: AddressStyle get() = AddressStyle.of(countryCode)

    private val streetLine: String
        get() {
            val street = street.orEmpty().trim()
            val unit = unit.orEmpty().trim()
            return when (style) {
                AddressStyle.SmallToLarge -> listOf(street, unit).filter { it.isNotEmpty() }.joinToString(", ")
                AddressStyle.LargeToSmall -> street + unit
            }
        }

    /** 列表用的紧凑地址：街道 + 城市 + 州（省略邮编和国家），够分辨同名球馆 */
    val compactAddress: String
        get() {
            val city = city.orEmpty().trim()
            val region = region.orEmpty().trim()
            return when (style) {
                AddressStyle.SmallToLarge -> listOf(streetLine, city, region).filter { it.isNotEmpty() }.joinToString(", ")
                AddressStyle.LargeToSmall -> (if (region == city) "" else city) + streetLine
            }
        }

    companion object {
        /** 附近范围（公里）：默认 10，和 iPhone 一样 */
        const val DEFAULT_TRAVEL_RADIUS_KM = 10.0

        /** 范围内离我最近的球馆；有核实过的就只在核实过的里面挑 */
        fun nearest(venues: List<Venue>, to: Coordinate, withinKm: Double): Venue? {
            val inRange = venues.filter { it.distanceKm(to) <= withinKm }
            val listed = inRange.filter { it.status != "unconfirmed" }
            return (listed.ifEmpty { inRange }).minByOrNull { it.distanceKm(to) }
        }
    }
}
