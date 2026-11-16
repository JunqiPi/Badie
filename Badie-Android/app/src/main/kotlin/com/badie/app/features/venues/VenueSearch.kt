package com.badie.app.features.venues

import com.badie.app.models.Coordinate
import com.badie.app.models.Venue
import com.badie.app.models.VenueStatus
import java.text.Normalizer
import java.util.concurrent.ConcurrentHashMap

// MARK: - 球馆搜索（纯函数，便于测试）
//
// 对应 iPhone 的 Services/Venues/VenueSearch.swift 里搜索的部分。
// 搜索：名称、别名、英文首字母缩写（LABC）、中文拼音与首字母、地址（街道/城市/邮编）。
// 排序：匹配程度优先，其次距离。
// 查重 iPhone 在本机算，安卓直接问服务器（venue_duplicates，规则一样），所以这里没有查重。
// 安卓没有打包的球馆目录：要搜的球馆是服务器按名字和地址找到的，加上附近的、常去的（见 VenuePicker）

object VenueSearch {

    data class Hit(val venue: Venue, val score: Double, val distanceKm: Double)

    // MARK: 规范化

    /** 小写、去重音、全角转半角、去标点、压缩空白 */
    fun normalize(text: String): String {
        // NFKD：全角转半角、拆出重音符号，再去掉重音
        val folded = Normalizer.normalize(text, Normalizer.Form.NFKD)
            .replace(Regex("\\p{Mn}+"), "")
            .lowercase()
        val result = StringBuilder()
        var lastWasSpace = true
        var index = 0
        while (index < folded.length) {
            val codePoint = folded.codePointAt(index)
            if (Character.isLetterOrDigit(codePoint)) {
                result.appendCodePoint(codePoint)
                lastWasSpace = false
            } else if (!lastWasSpace) {
                result.append(' ')
                lastWasSpace = true
            }
            index += Character.charCount(codePoint)
        }
        return result.toString().trim()
    }

    fun tokens(text: String): List<String> = normalize(text).split(' ').filter { it.isNotEmpty() }

    private fun isAscii(text: String) = text.all { it.code < 128 }

    /** 英文名称首字母缩写："Los Angeles Badminton Club" → "labc" */
    fun acronym(name: String): String {
        val words = tokens(name).filter { isAscii(it) && it.first().isLetter() }
        if (words.size < 2) return ""
        return words.map { it.first() }.joinToString("")
    }

    /** 中文拼音（全拼, 首字母）："朝阳体育中心" → ("chaoyangtiyuzhongxin", "cytyzx")。系统没有拼音转换时返回空 */
    fun pinyin(text: String): Pair<String, String> {
        if (!text.any { Character.isIdeographic(it.code) }) return "" to ""
        if (android.os.Build.VERSION.SDK_INT < 29) return "" to ""
        val latin = toLatin(text) ?: return "" to ""
        val syllables = tokens(latin)
        return syllables.joinToString("") to syllables.map { it.first() }.joinToString("")
    }

    /** Android 10 起系统自带 ICU 的“汉字 → 拼音”转换；更老的系统不能按拼音搜 */
    @androidx.annotation.RequiresApi(29)
    private fun toLatin(text: String): String? = try {
        val transliterator = hanLatin as? android.icu.text.Transliterator
            ?: android.icu.text.Transliterator.getInstance("Han-Latin; Latin-ASCII").also { hanLatin = it }
        transliterator.transliterate(text)
    } catch (_: RuntimeException) {
        null
    }

    /** 建一次就够（建起来慢）；类型写 Any，老系统上不碰这个类 */
    @Volatile
    private var hanLatin: Any? = null

    // MARK: 搜索

    /** 单个球馆的匹配分（null = 不匹配） */
    fun matchScore(venue: Venue, query: String): Double? {
        val q = normalize(query)
        if (q.isEmpty()) return null
        val compactQuery = q.replace(" ", "")
        val queryTokens = q.split(' ').filter { it.isNotEmpty() }

        var best = 0.0
        for (name in listOf(venue.name) + venue.aliases.orEmpty()) {
            val key = nameKey(name)
            if (key.compact == compactQuery) best = maxOf(best, 100.0)
            if (key.acronym == compactQuery) best = maxOf(best, 95.0)
            if (key.compact.startsWith(compactQuery)) best = maxOf(best, 85.0)
            if (queryTokens.all { token -> key.tokens.any { it.startsWith(token) } }) best = maxOf(best, 75.0)
            if (key.compact.contains(compactQuery)) best = maxOf(best, 65.0)
            if (key.pinyin.isNotEmpty()) {
                if (key.pinyinInitials.startsWith(compactQuery)) best = maxOf(best, 70.0)
                if (key.pinyin.startsWith(compactQuery)) best = maxOf(best, 70.0)
                if (key.pinyin.contains(compactQuery) && compactQuery.length >= 4) best = maxOf(best, 55.0)
            }
        }
        if (best == 0.0) {
            // 地址：街道、城市、邮编
            val address = venue.postalAddress
            val key = addressKey(listOf(address.street, address.unit.orEmpty(), address.city, address.region, address.postalCode).joinToString(" "))
            if (queryTokens.all { token -> key.tokens.any { it.startsWith(token) } }) {
                best = 45.0
            } else if (key.compact.contains(compactQuery) && compactQuery.length >= 3) {
                best = 35.0
            }
        }
        return if (best > 0) best else null
    }

    /** 搜索并排序：匹配分减去距离惩罚（每公里 0.3 分，最多 60 分） */
    fun search(venues: List<Venue>, query: String, near: Coordinate, limit: Int = 20): List<Hit> =
        venues.distinctBy { it.id }.mapNotNull { venue ->
            val score = matchScore(venue, query) ?: return@mapNotNull null
            val distance = venue.distanceKm(near)
            val statusBonus = if (venue.status == VenueStatus.Unconfirmed) 0.0 else 3.0
            Hit(venue, score - minOf(distance * 0.3, 60.0) + statusBonus, distance)
        }
            .sortedWith(compareByDescending<Hit> { it.score }.thenBy { it.distanceKm })
            .take(limit)

    /** 名称没对上、别名对上时显示“又名 …” */
    fun matchedAlias(venue: Venue, query: String): String? {
        val trimmed = query.trim()
        if (trimmed.isEmpty() || foldedContains(venue.name, trimmed)) return null
        val normalized = normalize(trimmed)
        return venue.aliases.orEmpty().firstOrNull { normalize(it).startsWith(normalized) }
    }

    /** 不分大小写、不分重音地找 query 在 text 里的位置（高亮用）；找不到是 null */
    fun matchRange(text: String, query: String): IntRange? {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return null
        // 逐个字符比较去掉重音后的小写，长度不变时才能对回原文的位置
        val foldedText = text.map { fold(it) }.joinToString("")
        val foldedQuery = trimmed.map { fold(it) }.joinToString("")
        if (foldedText.length != text.length) return null
        val start = foldedText.indexOf(foldedQuery)
        return if (start < 0) null else start until start + foldedQuery.length
    }

    private fun foldedContains(text: String, query: String) = matchRange(text, query) != null

    private fun fold(char: Char): Char =
        Normalizer.normalize(char.toString(), Normalizer.Form.NFKD).replace(Regex("\\p{Mn}+"), "").lowercase().singleOrNull() ?: char.lowercaseChar()

    // 每个名字的写法只算一次（拼音转换慢，球馆多时每打一个字都重算会卡）
    private class NameKey(val compact: String, val tokens: List<String>, val acronym: String, val pinyin: String, val pinyinInitials: String)
    private class AddressKey(val compact: String, val tokens: List<String>)

    private val names = ConcurrentHashMap<String, NameKey>()
    private val addresses = ConcurrentHashMap<String, AddressKey>()

    private fun nameKey(text: String): NameKey = names.getOrPut(text) {
        val normalized = normalize(text)
        val (full, initials) = pinyin(text)
        NameKey(normalized.replace(" ", ""), normalized.split(' ').filter { it.isNotEmpty() }, acronym(text), full, initials)
    }

    private fun addressKey(text: String): AddressKey = addresses.getOrPut(text) {
        val normalized = normalize(text)
        AddressKey(normalized.replace(" ", ""), normalized.split(' ').filter { it.isNotEmpty() })
    }
}
