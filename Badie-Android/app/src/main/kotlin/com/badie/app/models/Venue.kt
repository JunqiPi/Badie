package com.badie.app.models

import com.badie.app.design.Sym
import com.badie.app.design.SymbolId
import com.badie.app.l10n.L10n.tr
import com.badie.app.l10n.ListText
import com.badie.app.remote.EpochMillisSerializer
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// 对应 iPhone 的 Court.swift（BadmintonCourt 在安卓叫 Venue）

// MARK: - 球馆设施

/** rawValue 是存下来的值，不能改；显示用 title */
@Serializable(CourtAmenity.Serializer::class)
enum class CourtAmenity(val rawValue: String, val icon: SymbolId) {
    Parking("停车场", Sym.carFill),
    Shower("淋浴", Sym.showerFill),
    Locker("储物柜", Sym.lockFill),
    Rental("器材租赁", Sym.bagFill),
    Cafe("餐饮", Sym.cupAndSaucerFill),
    AirConditioning("空调", Sym.snowflake);

    val title: String
        get() = when (this) {
            Parking -> tr("停车场")
            Shower -> tr("淋浴")
            Locker -> tr("储物柜")
            Rental -> tr("器材租赁")
            Cafe -> tr("餐饮")
            AirConditioning -> tr("空调")
        }

    object Serializer : RawValueSerializer<CourtAmenity>("CourtAmenity", { it.rawValue }, { raw -> CourtAmenity.entries.first { it.rawValue == raw } })
}

/** 按 rawValue 存的枚举 */
open class RawValueSerializer<T>(name: String, private val raw: (T) -> String, private val of: (String) -> T) : KSerializer<T> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("com.badie.$name", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: T) = encoder.encodeString(raw(value))
    override fun deserialize(decoder: Decoder): T = of(decoder.decodeString())
}

// MARK: - 营业时间

@Serializable
data class OperatingHours(
    val openHour: Int,
    val openMinute: Int,
    val closeHour: Int,
    val closeMinute: Int,
    /** 营业日（1=周日 … 7=周六） */
    val daysOpen: List<Int>,
) {
    val openMinutes: Int get() = openHour * 60 + openMinute
    val closeMinutes: Int get() = closeHour * 60 + closeMinute

    val formattedTimeRange: String
        get() = String.format(Locale.ROOT, "%02d:%02d – %02d:%02d", openHour, openMinute, closeHour, closeMinute)

    val formattedDaysOpen: String
        get() {
            val days = daysOpen.sorted()
            if (days.size == 7) return tr("每天")
            if (days == listOf(2, 3, 4, 5, 6)) return tr("周一至周五")
            if (days == listOf(1, 7)) return tr("周末")
            val names = RecurringTimeSlot.weekdayNames
            return ListText.and(days.filter { it in 1..7 }.map { names[it - 1] })
        }

    /** 时间段是否完全落在营业时间内（跨午夜结束的按 24 点之后计） */
    fun covers(slot: TimeSlot, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (weekdayOf(slot.startTime, zone) !in daysOpen) return false
        val start = slot.startTime.zoned(zone).let { it.hour * 60 + it.minute }
        var end = slot.endTime.zoned(zone).let { it.hour * 60 + it.minute }
        if (!isSameDay(slot.endTime, slot.startTime, zone)) end += 24 * 60
        return start >= openMinutes && end <= closeMinutes
    }

    companion object {
        val standard = OperatingHours(8, 0, 22, 0, (1..7).toList())
    }
}

// MARK: - 结构化地址

/** 分字段存储，按国家习惯（AddressStyle）格式化。新建用 [PostalAddress.create]（去空白、国家码大写） */
@Serializable
data class PostalAddress(
    /** 门牌与街道，如 "10410 Valley Blvd"、"工体北路4号" */
    val street: String,
    /** 单元/楼层/场馆内位置，如 "Unit B" */
    val unit: String? = null,
    /** 城市（大陆地址里是区县） */
    val city: String,
    /** 州/省（大陆地址里是省市），如 "CA"、"北京市" */
    val region: String,
    val postalCode: String = "",
    /** ISO 3166-1 alpha-2，如 "US" */
    val countryCode: String,
) {
    val style: AddressStyle get() = CountryInfo.info(countryCode).addressStyle

    /** 第一行：街道 + 单元（"10410 Valley Blvd, Unit B"） */
    val streetLine: String
        get() = when (style) {
            AddressStyle.SmallToLarge -> listOfNotNull(street, unit).filter { it.isNotEmpty() }.joinToString(", ")
            AddressStyle.LargeToSmall -> street + (unit ?: "")
        }

    /** 第二行：城市 州 邮编（"El Monte, CA 91731"） */
    val cityLine: String
        get() = when (style) {
            AddressStyle.SmallToLarge -> {
                val regionPart = listOf(region, postalCode).filter { it.isNotEmpty() }.joinToString(" ")
                listOf(city, regionPart).filter { it.isNotEmpty() }.joinToString(", ")
            }
            AddressStyle.LargeToSmall -> if (region == city) region else region + city
        }

    /** 列表用的紧凑地址：街道 + 城市 + 州（省略邮编与国家），足够分辨同名球馆 */
    val compactLine: String
        get() = when (style) {
            AddressStyle.SmallToLarge -> listOf(streetLine, city, region).filter { it.isNotEmpty() }.joinToString(", ")
            AddressStyle.LargeToSmall -> (if (region == city) "" else city) + streetLine
        }

    val singleLine: String
        get() = when (style) {
            AddressStyle.SmallToLarge -> listOf(streetLine, cityLine).filter { it.isNotEmpty() }.joinToString(", ")
            AddressStyle.LargeToSmall -> cityLine + streetLine
        }

    /** 至少要有街道和城市，才能让别人确认位置 */
    val isComplete: Boolean get() = street.isNotEmpty() && city.isNotEmpty()

    companion object {
        fun create(street: String, unit: String? = null, city: String, region: String, postalCode: String = "", countryCode: String) =
            PostalAddress(
                street = street.trim(),
                unit = unit?.trim()?.ifEmpty { null },
                city = city.trim(),
                region = region.trim(),
                postalCode = postalCode.trim(),
                countryCode = countryCode.uppercase(),
            )
    }
}

// MARK: - 球馆来源、可信度、价格

@Serializable(VenueSource.Serializer::class)
enum class VenueSource(val rawValue: String) {
    /** 平台收录：经过人工核对 */
    Curated("curated"),
    /** 用户从地图结果中选择后加入 */
    AppleMaps("appleMaps"),
    /** 用户手动添加（放图钉/输入地址/粘贴地图链接） */
    Player("player"),
    /** 按城市从 OpenStreetMap 导入（未实地核实） */
    OpenStreetMap("openStreetMap"),
    /** 各地政府开放数据 */
    OpenData("openData");

    /** 服务器的写法：apple_maps / open_street_map / open_data，其余和 rawValue 一样 */
    val serverValue: String
        get() = when (this) {
            AppleMaps -> "apple_maps"
            OpenStreetMap -> "open_street_map"
            OpenData -> "open_data"
            else -> rawValue
        }

    companion object {
        fun ofServer(value: String): VenueSource = when (value) {
            "apple_maps" -> AppleMaps
            "open_street_map" -> OpenStreetMap
            "open_data" -> OpenData
            else -> entries.firstOrNull { it.rawValue == value } ?: Player
        }
    }

    /** 服务器和本机缓存都按服务器的写法 */
    object Serializer : RawValueSerializer<VenueSource>("VenueSource", { it.serverValue }, { VenueSource.ofServer(it) })
}

@Serializable(VenueStatus.Serializer::class)
enum class VenueStatus(val rawValue: String) {
    /** 平台核实 */
    Verified("verified"),
    /** 至少 3 位不同球友确认过（或在此签到打过球） */
    Confirmed("confirmed"),
    /** 新加入，等待确认 */
    Unconfirmed("unconfirmed");

    val icon: SymbolId
        get() = when (this) {
            Verified -> Sym.checkmarkSealFill
            Confirmed -> Sym.person2Fill
            Unconfirmed -> Sym.questionmarkCircleFill
        }

    val title: String
        get() = when (this) {
            Verified -> tr("已核实")
            Confirmed -> tr("球友确认")
            Unconfirmed -> tr("待确认")
        }

    companion object {
        /** 服务器的值和 rawValue 一样；不认识的按待确认 */
        fun of(rawValue: String?): VenueStatus = entries.firstOrNull { it.rawValue == rawValue } ?: Unconfirmed
    }

    object Serializer : RawValueSerializer<VenueStatus>("VenueStatus", { it.rawValue }, { VenueStatus.of(it) })
}

/** 场地类型：专营球馆以外的地方（社区中心、学校、教会体育馆）只在固定时段开放羽毛球；还有公园、学校、小区的露天场地 */
enum class VenueFacility(val serverValue: String) {
    Dedicated("dedicated"),
    MultiSport("multi_sport"),
    RecCenter("rec_center"),
    School("school"),
    CommunityHall("community_hall"),
    /** OpenStreetMap 里公园、学校、小区的露天场地 */
    Outdoor("outdoor");

    val title: String
        get() = when (this) {
            Dedicated -> tr("羽毛球馆")
            MultiSport -> tr("综合运动馆")
            RecCenter -> tr("社区中心")
            School -> tr("学校")
            CommunityHall -> tr("社区会馆")
            Outdoor -> tr("露天场地")
        }

    companion object {
        /** 数据库里 venues.kind 的写法（multi_sport）；不认识的是 null */
        fun ofServer(value: String?): VenueFacility? = entries.firstOrNull { it.serverValue == value }
    }

    /** 服务器的 kind 列：空或不认识的读成 null（不让一家球馆因为新的类型读不出来） */
    object Serializer : KSerializer<VenueFacility?> {
        override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

        override fun deserialize(decoder: Decoder): VenueFacility? {
            val element = (decoder as? JsonDecoder)?.decodeJsonElement() as? JsonPrimitive ?: return null
            return if (element.isString) ofServer(element.content) else null
        }

        override fun serialize(encoder: Encoder, value: VenueFacility?) {
            (encoder as JsonEncoder).encodeJsonElement(value?.let { JsonPrimitive(it.serverValue) } ?: kotlinx.serialization.json.JsonNull)
        }
    }
}

/** 收费方式：国内多为“按场地小时”，美国俱乐部常见“按人次 drop-in” */
@Serializable(VenuePricing.Serializer::class)
sealed interface VenuePricing {
    data class PerCourtHour(val price: Int) : VenuePricing
    data class DropIn(val perPerson: Int) : VenuePricing
    data object Unknown : VenuePricing

    fun text(currency: String): String = when (this) {
        is PerCourtHour -> tr("%@/场·时", Money.format(price, currency))
        is DropIn -> if (perPerson == 0) tr("免费") else tr("%@/人次", Money.format(perPerson, currency))
        Unknown -> tr("价格未知")
    }

    val isKnown: Boolean get() = this != Unknown

    /**
     * 服务器的 pricing 列：{"perPerson": 15, "perCourtHour": 38}，没有的键省略（两个都有时按人次）。
     * 键是驼峰写法，不跟着 snake_case 转，所以自己读
     */
    object Serializer : KSerializer<VenuePricing> {
        override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

        override fun deserialize(decoder: Decoder): VenuePricing {
            val json = (decoder as? JsonDecoder)?.decodeJsonElement() as? JsonObject ?: return Unknown
            fun amount(vararg keys: String) =
                keys.firstNotNullOfOrNull { (json[it] as? JsonPrimitive)?.doubleOrNull }?.let { roundHalfAway(it).toInt() }
            amount("perPerson", "per_person")?.let { return DropIn(it) }
            amount("perCourtHour", "per_court_hour")?.let { return PerCourtHour(it) }
            return Unknown
        }

        override fun serialize(encoder: Encoder, value: VenuePricing) {
            val json = when (value) {
                is PerCourtHour -> JsonObject(mapOf("perCourtHour" to JsonPrimitive(value.price)))
                is DropIn -> JsonObject(mapOf("perPerson" to JsonPrimitive(value.perPerson)))
                Unknown -> JsonObject(emptyMap())
            }
            (encoder as JsonEncoder).encodeJsonElement(json)
        }
    }
}

/** 坐标系：国际通用 WGS-84；中国大陆地图数据（高德/Apple 地图在大陆）为 GCJ-02 */
@Serializable
enum class CoordinateDatum {
    @SerialName("wgs84") Wgs84,
    @SerialName("gcj02") Gcj02,
}

// MARK: - 球馆

/**
 * 球馆（服务器 venues 表的一行，加上本机记的几项）。对应 iPhone 的 BadmintonCourt。
 * 地址按服务器的列分开存（street、city…），完整的地址见 [postalAddress]。
 * iPhone 的构造函数会去掉名字和入口说明的空白、场地数至少 1；这里的数据来自服务器，服务器已经检查过
 */
@Serializable
data class Venue(
    /** 平台内的唯一 ID：匹配、房间、球局都只比较这个 ID，不比较名字或坐标 */
    val id: String,
    val name: String,
    /** 别名与简称（"LABC"、中文俗称），用于搜索 */
    val aliases: List<String>? = null,
    val lat: Double,
    val lon: Double,
    val street: String? = null,
    val unit: String? = null,
    val city: String? = null,
    val region: String? = null,
    val postalCode: String? = null,
    val countryCode: String,
    val status: VenueStatus = VenueStatus.Verified,
    /** 坐标只是大概（目录里有些球馆只知道在哪个区），不拿来算“离我最近” */
    val locationApproximate: Boolean? = null,
    /** IANA 时区，如 "America/Los_Angeles"；营业时间按球馆当地时间判断 */
    val timeZoneId: String? = null,
    /** Apple 地图 Place ID，用于去重 */
    val applePlaceId: String? = null,
    /** null = 场地数未知 */
    val courtCount: Int? = null,
    val pricing: VenuePricing = VenuePricing.Unknown,
    /** 价格说明（如“散客 $15/人次 · 包场 $28/场·时”） */
    val pricingNote: String? = null,
    /** 币种；没有时按国家，见 [currency] */
    val currencyCode: String? = null,
    val phone: String? = null,
    val website: String? = null,
    /** 入口/楼层/停车说明（与地址分开，如“后门进，2 楼”） */
    val entranceNote: String? = null,
    val source: VenueSource = VenueSource.Curated,
    @Serializable(EpochMillisSerializer::class) val createdAt: Long = 1_767_225_600_000L,
    /** 羽毛球开放时段（社区中心等），照录官方页面 */
    val playTimes: String? = null,
    // 下面这些服务器的 venues 表有、但 iPhone 不从服务器读（或者只在本机记）
    /** 坐标来源的坐标系；导航到高德/百度时据此传参 */
    val datum: CoordinateDatum = CoordinateDatum.Wgs84,
    val amenities: List<CourtAmenity> = emptyList(),
    /** null = 营业时间未知 */
    val operatingHours: OperatingHours? = null,
    val addedBy: String? = null,
    /** 确认过地址的球友（去重后的用户 ID） */
    val confirmedBy: List<String> = emptyList(),
    /** 最近一次有人确认/签到的时间（信息新鲜度） */
    @Serializable(EpochMillisSerializer::class) val lastConfirmedAt: Long? = null,
    /** 重复条目合并后指向保留的球馆：旧 ID 的收藏、房间、请求继续有效 */
    val mergedInto: String? = null,
    /** 需要人工看一眼的原因（如“同一栋楼已有另一家球馆”）；不影响使用 */
    val reviewFlag: String? = null,
    /** 开放数据要求的署名（详情页显示） */
    val attribution: String? = null,
    /** 坐标只精确到区，地图核对后才显示 */
    val needsLocationCheck: Boolean? = null,
    /** 场地类型（服务器的 kind 列）；露天场地在球馆页标出来，自动选常去球馆时排在室内的后面 */
    @SerialName("kind") @Serializable(VenueFacility.Serializer::class) val facility: VenueFacility? = null,
    /** 平台最后一次人工核实的日期 */
    @Serializable(EpochMillisSerializer::class) val checkedOn: Long? = null,
) {
    val location: Coordinate get() = Coordinate(lat, lon)

    val postalAddress: PostalAddress
        get() = PostalAddress.create(street.orEmpty(), unit, city.orEmpty(), region.orEmpty(), postalCode.orEmpty(), countryCode)

    /** 单行完整地址 */
    val address: String get() = postalAddress.singleLine

    /** 列表用的紧凑地址：街道 + 城市 + 州（省略邮编和国家），够分辨同名球馆 */
    val compactAddress: String get() = postalAddress.compactLine

    val country: CountryInfo get() = CountryInfo.info(countryCode)

    /** 币种：服务器没给就按国家 */
    val currency: String get() = currencyCode ?: country.currencyCode

    /** 球馆当地时区（营业时间、球局时间都按当地时间计算）；不认识的按设备的 */
    val zone: ZoneId
        get() = timeZoneId?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.systemDefault()

    /** 球馆所在时区与设备不同（如出差）时，用于在时间旁标注 */
    fun timeZoneAbbreviation(now: Long = System.currentTimeMillis()): String? {
        val zone = timeZoneId?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: return null
        val instant = Instant.ofEpochMilli(now)
        if (zone.rules.getOffset(instant) == ZoneId.systemDefault().rules.getOffset(instant)) return null
        return DateTimeFormatter.ofPattern("zzz", Locale.getDefault()).format(instant.atZone(zone))
    }

    val pricingText: String get() = pricing.text(currency)

    /** 该时段是否营业；营业时间未知时视为可用（无法判断） */
    fun isOpen(slot: TimeSlot): Boolean = operatingHours?.covers(slot, zone) ?: true

    val hoursText: String get() = operatingHours?.formattedTimeRange ?: tr("营业时间未知")

    /** 到用户的距离（公里） */
    fun distanceKm(from: Coordinate): Double = location.distanceKm(from)

    fun formattedDistance(from: Coordinate): String = DistanceFormatter.string(distanceKm(from))

    /** 记录一位球友的确认；够数后升级为“球友确认” */
    fun addingConfirmation(userId: String, at: Long = System.currentTimeMillis()): Venue {
        val confirmedAt = maxOf(lastConfirmedAt ?: DISTANT_PAST, at)
        if (userId in confirmedBy) return copy(lastConfirmedAt = confirmedAt)
        val confirmed = confirmedBy + userId
        val promoted = status == VenueStatus.Unconfirmed && confirmed.size >= CONFIRMATIONS_NEEDED
        return copy(lastConfirmedAt = confirmedAt, confirmedBy = confirmed, status = if (promoted) VenueStatus.Confirmed else status)
    }

    companion object {
        /** 达到这个人数的确认后，状态从“待确认”变为“球友确认” */
        const val CONFIRMATIONS_NEEDED = 3

        /** 附近范围（公里）：默认 10，和 iPhone 一样 */
        const val DEFAULT_TRAVEL_RADIUS_KM = UserPreferences.DEFAULT_TRAVEL_RADIUS

        /** 范围内离我最近的球馆：先挑核实过的，再挑室内的，都没有才用露天场地 */
        fun nearest(venues: List<Venue>, to: Coordinate, withinKm: Double): Venue? {
            val inRange = venues.filter { it.distanceKm(to) <= withinKm }
            val listed = inRange.filter { it.status != VenueStatus.Unconfirmed }
            val indoor = inRange.filter { it.facility != VenueFacility.Outdoor }
            return listed.ifEmpty { indoor.ifEmpty { inRange } }.minByOrNull { it.distanceKm(to) }
        }
    }
}

// MARK: - 用户偏好

@Serializable
data class UserPreferences(
    /** 出行半径（公里） */
    val travelRadiusKm: Double,
) {
    fun isValidTravelRadius(radius: Double): Boolean = radius >= MINIMUM_TRAVEL_RADIUS && radius <= MAXIMUM_TRAVEL_RADIUS

    companion object {
        const val DEFAULT_TRAVEL_RADIUS = 10.0
        const val MINIMUM_TRAVEL_RADIUS = 1.0
        const val MAXIMUM_TRAVEL_RADIUS = 50.0

        val default = UserPreferences(DEFAULT_TRAVEL_RADIUS)
    }
}
