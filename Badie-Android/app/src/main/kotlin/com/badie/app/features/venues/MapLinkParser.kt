package com.badie.app.features.venues

import com.badie.app.models.Coordinate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLDecoder

// MARK: - 地图分享链接解析
//
// 对应 iPhone 的 Services/Venues/MapLinkParser.swift。
// 群聊里常直接发 Google / Apple 地图链接。粘贴后从链接里取出坐标、名称或 Place ID，再去“添加球馆”核对。
// 短链（maps.app.goo.gl、goo.gl/maps、maps.apple/p/…）要先联网展开成长链（见 needsExpansion、expand）。

data class ParsedMapLink(
    val provider: Provider,
    val coordinate: Coordinate? = null,
    val name: String? = null,
    /** 搜索词或地址（没有坐标时用它去找地址） */
    val query: String? = null,
    val applePlaceId: String? = null,
    val googlePlaceId: String? = null,
) {
    enum class Provider { Apple, Google }
}

object MapLinkParser {
    private val urlPattern = Regex("""https?://[^\s<>"'，。（）()、]+""", RegexOption.IGNORE_CASE)

    /** 从一段文字里找出第一个地图链接（兼容“分享自微信”的前后缀文字） */
    fun firstMapURL(text: String): URI? = urlPattern.findAll(text)
        .mapNotNull { match -> runCatching { URI(match.value.trimEnd('.', ',', ';', '!', '?')) }.getOrNull() }
        .firstOrNull(::isMapURL)

    fun isMapURL(url: URI): Boolean {
        val host = url.host?.lowercase() ?: return false
        val path = url.rawPath.orEmpty()
        return host.endsWith("maps.apple.com") || host == "maps.apple" || host.endsWith("maps.app.goo.gl") ||
            host.endsWith("goo.gl") || (host.contains("google.") && (path.startsWith("/maps") || host.startsWith("maps.")))
    }

    /** 短链要联网展开 */
    fun needsExpansion(url: URI): Boolean {
        val host = url.host?.lowercase() ?: return false
        return host.endsWith("maps.app.goo.gl") || host == "goo.gl" || host == "maps.apple" ||
            (host.endsWith("maps.apple.com") && url.rawPath.orEmpty().startsWith("/p/"))
    }

    /** 展开短链：跟着跳转走，直到不再跳（最多 5 次）；打不开返回 null */
    suspend fun expand(url: URI): URI? = withContext(Dispatchers.IO) {
        var current = url
        repeat(5) {
            val connection = try {
                current.toURL().openConnection() as HttpURLConnection
            } catch (_: Exception) {
                return@withContext null
            }
            try {
                connection.instanceFollowRedirects = false
                connection.requestMethod = "GET"
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                val status = connection.responseCode
                val location = connection.getHeaderField("Location")
                if (status !in 300..399 || location == null) return@withContext current.takeIf { it != url }
                current = current.resolve(location)
            } catch (_: Exception) {
                return@withContext null
            } finally {
                connection.disconnect()
            }
        }
        current
    }

    fun parse(url: URI): ParsedMapLink? {
        val host = url.host?.lowercase() ?: return null
        if (host.endsWith("maps.apple.com")) return parseApple(url)
        if (host.contains("google.")) return parseGoogle(url)
        return null
    }

    // MARK: Apple

    private fun parseApple(url: URI): ParsedMapLink? {
        val items = queryItems(url)
        val q = items["q"]
        var point = coordinate(items["coordinate"] ?: items["ll"] ?: items["sll"])
        if (point == null && q != null) point = coordinate(q)
        val link = ParsedMapLink(
            provider = ParsedMapLink.Provider.Apple,
            coordinate = point,
            name = items["name"] ?: q?.takeIf { coordinate(it) == null },
            query = items["address"] ?: q,
            applePlaceId = items["place-id"],
        )
        if (link.coordinate == null && link.applePlaceId == null && link.query == null) return null
        return link
    }

    // MARK: Google

    private fun parseGoogle(url: URI): ParsedMapLink? {
        val items = queryItems(url)
        val path = decode(url.rawPath.orEmpty(), plus = false)
        val absolute = decode(url.toString(), plus = false)
        var point: Coordinate? = null
        var name: String? = null
        var query: String? = null

        // 地点精确坐标：data=…!3d34.0764!4d-118.0461（优先于 @ 后的视野中心）
        val lat = firstMatch("""!3d(-?\d+(?:\.\d+)?)""", absolute)?.toDoubleOrNull()
        val lng = firstMatch("""!4d(-?\d+(?:\.\d+)?)""", absolute)?.toDoubleOrNull()
        if (lat != null && lng != null) point = validCoordinate(lat, lng)
        // /maps/place/<名称>/@lat,lng,17z
        val placeIndex = path.indexOf("/maps/place/")
        if (placeIndex >= 0) {
            val first = path.substring(placeIndex + "/maps/place/".length).split('/').firstOrNull()?.replace('+', ' ')
            if (!first.isNullOrEmpty() && !first.startsWith("@")) name = first
        }
        if (point == null) {
            firstMatch("""@(-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?)""", path)?.let { point = coordinate(it) }
        }
        // ?q= / ?query= / ?destination=
        for (key in listOf("q", "query", "destination", "daddr")) {
            val value = items[key]?.takeIf { it.isNotEmpty() } ?: continue
            val parsed = coordinate(value)
            if (parsed != null) {
                if (point == null) point = parsed
            } else {
                query = value
                if (name == null) name = value.split(',').first()
            }
        }
        if (point == null && query == null && name == null) return null
        return ParsedMapLink(
            ParsedMapLink.Provider.Google, point, name, query,
            googlePlaceId = items["query_place_id"] ?: items["destination_place_id"],
        )
    }

    // MARK: Helpers

    private fun queryItems(url: URI): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        for (part in url.rawQuery.orEmpty().split('&')) {
            if (part.isEmpty()) continue
            val name = decode(part.substringBefore('='), plus = true)
            val value = decode(part.substringAfter('=', ""), plus = true).trim()
            if (name !in result) result[name] = value
        }
        return result
    }

    private fun decode(text: String, plus: Boolean): String = try {
        URLDecoder.decode(if (plus) text else text.replace("+", "%2B"), "UTF-8")
    } catch (_: IllegalArgumentException) {
        text
    }

    fun coordinate(text: String?): Coordinate? {
        val parts = text?.split(',')?.map { it.trim() } ?: return null
        if (parts.size != 2) return null
        val lat = parts[0].toDoubleOrNull() ?: return null
        val lng = parts[1].toDoubleOrNull() ?: return null
        return validCoordinate(lat, lng)
    }

    private fun validCoordinate(latitude: Double, longitude: Double): Coordinate? {
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0 || (latitude == 0.0 && longitude == 0.0)) return null
        return Coordinate(latitude, longitude)
    }

    private fun firstMatch(pattern: String, text: String): String? = Regex(pattern).find(text)?.groupValues?.getOrNull(1)
}
