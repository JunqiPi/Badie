package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.Serializable
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

// MARK: - 国家/地区信息
//
// 每个国家的币种、手机号规则、地址书写顺序和常用导航 App；新增国家在 `CountryInfo.all` 里加一行。

@Serializable
enum class AddressStyle(val rawValue: String) {
    /** 由小到大：门牌 街道, 城市, 州 邮编（美、加、英、澳、新、马…） */
    SmallToLarge("smallToLarge"),
    /** 由大到小：省/市 区 街道门牌（中国大陆、台湾、日本、韩国） */
    LargeToSmall("largeToSmall");

    companion object {
        fun of(countryCode: String?): AddressStyle = CountryInfo.info(countryCode).addressStyle
    }
}

enum class NavigationApp(val rawValue: String) {
    AppleMaps("appleMaps"), GoogleMaps("googleMaps"), Waze("waze"), Amap("amap"), Baidu("baidu"), Naver("naver"), Kakao("kakao");

    val title: String
        get() = when (this) {
            AppleMaps -> tr("Apple 地图")
            GoogleMaps -> tr("Google 地图")
            Waze -> "Waze"
            Amap -> tr("高德地图")
            Baidu -> tr("百度地图")
            Naver -> tr("Naver 地图")
            Kakao -> "KakaoMap"
        }
}

data class PhoneRule(
    /** 国内号码（不含国家码、不含开头的 0）允许的位数 */
    val lengths: IntRange,
    /** 国内号码的正则（不含国家码）；null 表示只校验位数 */
    val pattern: String?,
    /** 输入框占位示例 */
    val example: String,
) {
    fun isValid(national: String): Boolean {
        if (national.length !in lengths || !national.all { it in '0'..'9' }) return false
        val pattern = pattern ?: return true
        return Regex(pattern).matches(national)
    }
}

data class CountryInfo(
    /** ISO 3166-1 alpha-2 */
    val code: String,
    val callingCode: String,
    val currencyCode: String,
    val currencySymbol: String,
    val addressStyle: AddressStyle,
    val phone: PhoneRule,
    /** 按当地习惯排序的导航 App */
    val navigationApps: List<NavigationApp>,
) {
    /** 名称（按当前语言） */
    val nameZh: String
        get() = when (code) {
            "US" -> tr("美国")
            "CA" -> tr("加拿大")
            "CN" -> tr("中国大陆")
            "HK" -> tr("中国香港")
            "TW" -> tr("中国台湾")
            "SG" -> tr("新加坡")
            "MY" -> tr("马来西亚")
            "JP" -> tr("日本")
            "KR" -> tr("韩国")
            "GB" -> tr("英国")
            "AU" -> tr("澳大利亚")
            "IN" -> tr("印度")
            "ID" -> tr("印度尼西亚")
            "TH" -> tr("泰国")
            "VN" -> tr("越南")
            "PH" -> tr("菲律宾")
            "DK" -> tr("丹麦")
            "NZ" -> tr("新西兰")
            "DE" -> tr("德国")
            "FR" -> tr("法国")
            else -> Locale("", code).getDisplayCountry(Locale.getDefault()).ifEmpty { code }
        }

    /** 国旗 emoji：地区码字母映射到区域指示符号 */
    val flag: String
        get() = buildString { code.uppercase().forEach { appendCodePoint(127_397 + it.code) } }

    /** 估算用球费（当地货币，整数）；0 表示通常自带球、不计入 */
    fun shuttleFee(mode: GameMode): Int = when (currencyCode) {
        "CNY" -> if (mode == GameMode.Doubles) 15 else 10
        "USD", "CAD", "AUD", "SGD", "NZD" -> if (mode == GameMode.Doubles) 8 else 5
        else -> 0
    }

    companion object {
        private val northAmerica = PhoneRule(10..10, "[2-9][0-9]{2}[2-9][0-9]{6}", "626 555 0123")

        val all: List<CountryInfo> = listOf(
            CountryInfo("US", "1", "USD", "$", AddressStyle.SmallToLarge, northAmerica,
                listOf(NavigationApp.AppleMaps, NavigationApp.GoogleMaps, NavigationApp.Waze)),
            CountryInfo("CA", "1", "CAD", "C$", AddressStyle.SmallToLarge, northAmerica.copy(example = "604 555 0123"),
                listOf(NavigationApp.AppleMaps, NavigationApp.GoogleMaps, NavigationApp.Waze)),
            CountryInfo("CN", "86", "CNY", "¥", AddressStyle.LargeToSmall, PhoneRule(11..11, "1[3-9][0-9]{9}", "138 0013 8000"),
                listOf(NavigationApp.Amap, NavigationApp.Baidu, NavigationApp.AppleMaps)),
            CountryInfo("HK", "852", "HKD", "HK$", AddressStyle.SmallToLarge, PhoneRule(8..8, "[4-9][0-9]{7}", "5123 4567"),
                listOf(NavigationApp.AppleMaps, NavigationApp.GoogleMaps)),
            CountryInfo("TW", "886", "TWD", "NT$", AddressStyle.LargeToSmall, PhoneRule(9..9, "9[0-9]{8}", "912 345 678"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("SG", "65", "SGD", "S$", AddressStyle.SmallToLarge, PhoneRule(8..8, "[3689][0-9]{7}", "8123 4567"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps, NavigationApp.Waze)),
            CountryInfo("MY", "60", "MYR", "RM", AddressStyle.SmallToLarge, PhoneRule(9..10, "1[0-9]{8,9}", "12 345 6789"),
                listOf(NavigationApp.Waze, NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("JP", "81", "JPY", "¥", AddressStyle.LargeToSmall, PhoneRule(10..10, "[789]0[0-9]{8}", "90 1234 5678"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("KR", "82", "KRW", "₩", AddressStyle.LargeToSmall, PhoneRule(9..10, "1[0-9]{8,9}", "10 1234 5678"),
                listOf(NavigationApp.Naver, NavigationApp.Kakao, NavigationApp.AppleMaps)),
            CountryInfo("GB", "44", "GBP", "£", AddressStyle.SmallToLarge, PhoneRule(10..10, "7[0-9]{9}", "7400 123456"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps, NavigationApp.Waze)),
            CountryInfo("AU", "61", "AUD", "A$", AddressStyle.SmallToLarge, PhoneRule(9..9, "4[0-9]{8}", "412 345 678"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps, NavigationApp.Waze)),
            CountryInfo("IN", "91", "INR", "₹", AddressStyle.SmallToLarge, PhoneRule(10..10, "[6-9][0-9]{9}", "98765 43210"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("ID", "62", "IDR", "Rp", AddressStyle.SmallToLarge, PhoneRule(9..12, "8[0-9]{8,11}", "812 3456 7890"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.Waze, NavigationApp.AppleMaps)),
            CountryInfo("TH", "66", "THB", "฿", AddressStyle.SmallToLarge, PhoneRule(9..9, "[689][0-9]{8}", "81 234 5678"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("VN", "84", "VND", "₫", AddressStyle.SmallToLarge, PhoneRule(9..9, "[35789][0-9]{8}", "91 234 5678"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("PH", "63", "PHP", "₱", AddressStyle.SmallToLarge, PhoneRule(10..10, "9[0-9]{9}", "917 123 4567"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.Waze, NavigationApp.AppleMaps)),
            CountryInfo("DK", "45", "DKK", "kr ", AddressStyle.SmallToLarge, PhoneRule(8..8, "[2-9][0-9]{7}", "20 12 34 56"),
                listOf(NavigationApp.AppleMaps, NavigationApp.GoogleMaps)),
            CountryInfo("NZ", "64", "NZD", "NZ$", AddressStyle.SmallToLarge, PhoneRule(8..10, "2[0-9]{7,9}", "21 123 4567"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps, NavigationApp.Waze)),
            CountryInfo("DE", "49", "EUR", "€", AddressStyle.SmallToLarge, PhoneRule(10..11, "1[5-7][0-9]{8,9}", "1512 3456789"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps)),
            CountryInfo("FR", "33", "EUR", "€", AddressStyle.SmallToLarge, PhoneRule(9..9, "[67][0-9]{8}", "6 12 34 56 78"),
                listOf(NavigationApp.GoogleMaps, NavigationApp.AppleMaps, NavigationApp.Waze)),
        )

        /** 未收录的国家：通用规则（6–14 位数字） */
        fun generic(code: String): CountryInfo {
            val upper = code.uppercase()
            val currency = try {
                Currency.getInstance(Locale("en", upper))?.currencyCode
            } catch (_: IllegalArgumentException) {
                null
            } ?: "USD"
            return CountryInfo(
                upper, "", currency, "$currency ", AddressStyle.SmallToLarge, PhoneRule(6..14, null, ""),
                listOf(NavigationApp.AppleMaps, NavigationApp.GoogleMaps, NavigationApp.Waze),
            )
        }

        fun info(code: String?): CountryInfo {
            if (code.isNullOrEmpty()) return defaultCountry
            return all.firstOrNull { it.code == code.uppercase() } ?: generic(code)
        }

        /** 首发市场 */
        val defaultCountry: CountryInfo get() = all[0]

        /** 设备所在地区（用于手机号默认国家码）；未知时为美国 */
        val deviceCountry: CountryInfo get() = all.firstOrNull { it.code == Locale.getDefault().country } ?: defaultCountry

        /** 支持手机号登录的国家/地区 */
        val phoneCountries: List<CountryInfo> get() = all
    }
}

// MARK: - 金额

object Money {
    /** 整数金额 + 币种符号，如 "$12"、"¥80"、"RM 15" */
    fun format(amount: Int, currency: String): String {
        val symbol = CountryInfo.all.firstOrNull { it.currencyCode == currency }?.currencySymbol ?: "$currency "
        return symbol + NumberFormat.getIntegerInstance(Locale.getDefault()).format(amount)
    }

    // iPhone 的 Money.icon(for:)（币种对应的 SF Symbol）是界面用的，等搬到用它的页面时再加图标
}

// MARK: - 手机号（E.164）

class PhoneNumber(val country: CountryInfo, national: String) {
    /** 国内号码（已去掉开头的 0 与分隔符） */
    val national: String

    init {
        var digits = national.filter { it in '0'..'9' }
        // 去掉国内长途前缀 0（日本 090…、英国 07…、马来西亚 012… 等）
        while (digits.startsWith("0") && digits.length > country.phone.lengths.first) digits = digits.drop(1)
        // 北美用户常把国家码 1 一起输入
        if (country.callingCode == "1" && digits.length == 11 && digits.startsWith("1")) digits = digits.drop(1)
        this.national = digits
    }

    val isValid: Boolean get() = country.callingCode.isNotEmpty() && country.phone.isValid(national)

    /** 存储格式：+16265550123 */
    val e164: String get() = "+" + country.callingCode + national

    /** 展示格式：+1 626 555 0123 */
    val display: String get() = "+${country.callingCode} " + group(national, country)

    /** 脱敏展示：+1 626 *** 0123 */
    val masked: String
        get() = if (national.length < 7) display else "+${country.callingCode} ${national.take(3)} *** ${national.takeLast(4)}"

    override fun equals(other: Any?): Boolean = other is PhoneNumber && other.country == country && other.national == national

    override fun hashCode(): Int = country.hashCode() * 31 + national.hashCode()

    companion object {
        /** 解析 E.164（"+16265550123"）；兼容旧数据中不带国家码的 11 位大陆手机号 */
        fun parse(stored: String): PhoneNumber? {
            if (stored.startsWith("+")) {
                val digits = stored.drop(1)
                // 最长前缀匹配国家码（852 优先于 8x）
                val candidates = CountryInfo.all.filter { digits.startsWith(it.callingCode) }.sortedByDescending { it.callingCode.length }
                for (country in candidates) {
                    val number = PhoneNumber(country, digits.drop(country.callingCode.length))
                    if (number.isValid) return number
                }
                return null
            }
            val legacy = PhoneNumber(CountryInfo.info("CN"), stored)
            return if (legacy.isValid) legacy else null
        }

        private fun group(digits: String, country: CountryInfo): String {
            val count = digits.length
            val sizes = when {
                country.callingCode == "1" && count == 10 -> listOf(3, 3, 4)
                country.callingCode == "86" && count == 11 -> listOf(3, 4, 4)
                count > 8 -> listOf(count - 8, 4, 4)
                else -> listOf(count - 4, 4)
            }
            val result = mutableListOf<String>()
            var index = 0
            for (size in sizes) {
                if (size <= 0 || index >= count) continue
                val end = minOf(count, index + size)
                result += digits.substring(index, end)
                index = end
            }
            if (index < count) result += digits.substring(index)
            return result.joinToString(" ")
        }
    }
}
