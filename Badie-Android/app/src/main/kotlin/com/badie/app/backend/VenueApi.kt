package com.badie.app.backend

import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Avatar
import com.badie.app.models.CardColor
import com.badie.app.models.Coordinate
import com.badie.app.models.CoordinateDatum
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.PostalAddress
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenueSource
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.RemoteError
import com.badie.app.remote.RemoteJSON
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// 球馆的读写：添加、确认、报错、查重、常去人数、球馆里的人。
// 对应 iPhone 的 MockBackend+RemoteVenues.swift、VenueService.swift，和 MockBackend+Nearby.swift 里的 venuePeople

/** 要加进球馆库的地点（iPhone 的 VenueCandidate；安卓没有地图搜索，只有手动添加这一种来源） */
data class VenueCandidate(
    val name: String,
    val location: Coordinate,
    val address: PostalAddress,
    val timeZoneId: String? = null,
    val phone: String? = null,
    val website: String? = null,
) {
    /** 中国大陆的地图数据可能是 GCJ-02（按国家保守处理，和 iPhone 一样） */
    val datum: CoordinateDatum get() = if (address.countryCode == "CN") CoordinateDatum.Gcj02 else CoordinateDatum.Wgs84
}

/** “信息有误”的五个选项 */
enum class VenueIssue(val serverValue: String) {
    WrongLocation("wrong_location"),
    Closed("closed"),
    Duplicate("duplicate"),
    NotBadminton("not_badminton"),
    Other("other");

    val title: String
        get() = when (this) {
            WrongLocation -> tr("位置或地址不对")
            Closed -> tr("已关门/不再开放")
            Duplicate -> tr("和另一个球馆重复")
            NotBadminton -> tr("不是羽毛球场地")
            Other -> tr("其他")
        }
}

/** 查重结果的三种（服务器的 venue_duplicates） */
enum class DuplicateKind(val serverValue: String) {
    /** 地图的地点 ID 相同 */
    SamePlace("same_place"),
    /** 200 米内且名称相近 */
    Likely("likely"),
    /** 40 米内（同一栋楼），名称不同 */
    SameBuilding("same_building");

    /** 同一地点 / 很可能同一家：不允许新建，只能选已有的 */
    val blocksAdding: Boolean get() = this != SameBuilding

    companion object {
        fun ofServer(value: String): DuplicateKind? = entries.firstOrNull { it.serverValue == value }
    }
}

data class VenueDuplicate(val venue: Venue, val kind: DuplicateKind, val distanceMeters: Double)

/** 球馆页的两排头像：最近 30 天在这打完过一场的人、常客（都是大厅里能看到的人，最多各 20 个） */
data class VenuePeople(val recent: List<User> = emptyList(), val regulars: List<User> = emptyList())

/** 按 id 读一家球馆（球馆页从链接或别的页面进来、缓存里没有时）；合并过的跳到保留的那一家 */
suspend fun Backend.fetchVenue(id: String): Venue? {
    var target = id
    repeat(3) {
        val row = remote.venueRowsByIds(listOf(target)).firstOrNull() ?: return null
        val merged = (row["merged_into"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        if (merged == null) return venueFromRow(row)?.also(::cacheVenue)
        target = merged
    }
    return null
}

/** 这几家球馆各有多少人常去（公开的 venue_regular_counts，不知道是谁） */
suspend fun Backend.regularCounts(ids: Collection<String>): Map<String, Int> {
    if (ids.isEmpty()) return emptyMap()
    val result = HashMap<String, Int>()
    for (batch in ids.distinct().chunked(100)) {
        val list = batch.joinToString(",") { "\"${it.replace("\"", "")}\"" }
        val rows = remote.select<List<RegularCountRow>>("venue_regular_counts", "select=venue_id,regulars&venue_id=in.(${encode(list)})")
        for (id in batch) result[id] = 0
        for (row in rows) result[row.venueId] = row.regulars
    }
    return result
}

/** 最近在这打过的人、常客。头像边显示边下 */
suspend fun Backend.venuePeople(venueId: String): VenuePeople {
    val raw = remote.rpc<RemoteVenuePeople>("venue_people", json("p_venue" to venueId))
    val me = currentUser?.id
    val all = (raw.recent.orEmpty() + raw.regulars.orEmpty()).distinctBy { it.id }
    for (person in all) {
        try {
            photos.apply(person.id, person.avatar)
        } catch (_: RemoteError) {
        }
    }
    fun users(list: List<RemoteVenuePerson>?) = list.orEmpty().filter { it.id != me }.map { it.user() }
    return VenuePeople(recent = users(raw.recent), regulars = users(raw.regulars))
}

/** 添加前查重：服务器按地点 ID、200 米内名称相近、40 米内同一栋楼找（和添加时的规则一样） */
suspend fun Backend.venueDuplicates(candidate: VenueCandidate): List<VenueDuplicate> {
    val rows = remote.rpc<List<DuplicateRow>>(
        "venue_duplicates",
        json("name" to candidate.name, "lat" to candidate.location.latitude, "lng" to candidate.location.longitude),
    )
    if (rows.isEmpty()) return emptyList()
    val missing = rows.map { it.venueId }.filter { venue(it) == null }
    if (missing.isNotEmpty()) remote.venuesByIds(missing).forEach(::cacheVenue)
    return rows.mapNotNull { row ->
        val kind = DuplicateKind.ofServer(row.kind) ?: return@mapNotNull null
        val venue = venue(row.venueId) ?: return@mapNotNull null
        VenueDuplicate(venue, kind, row.distanceM)
    }
}

/**
 * 加一家球馆（服务器查重、每人每天 3 家）。和已有球馆是同一地点时服务器返回那一家。
 * 简称、入口说明是空的就不传
 */
suspend fun Backend.addVenue(candidate: VenueCandidate, aliases: List<String>, courtCount: Int?, entranceNote: String?): Venue {
    val address = candidate.address
    val args = linkedMapOf<String, Any?>(
        "name" to candidate.name, "lat" to candidate.location.latitude, "lng" to candidate.location.longitude,
        "street" to address.street, "city" to address.city, "region" to address.region,
        "postal_code" to address.postalCode, "country_code" to address.countryCode,
        "source" to VenueSource.Player.serverValue, "datum" to candidate.datum.serialName,
        "aliases" to aliases.map { it.trim() }.filter { it.isNotEmpty() }, "alternate_place_ids" to emptyList<String>(),
    )
    val optional = mapOf(
        "unit" to address.unit, "time_zone_id" to candidate.timeZoneId, "court_count" to courtCount,
        "entrance_note" to entranceNote?.trim()?.ifEmpty { null }, "phone" to candidate.phone, "website" to candidate.website,
    )
    for ((key, value) in optional) if (value != null) args[key] = value
    val row = remote.rpc<JsonObject>("add_venue", json(*args.toList().toTypedArray()))
    val added = venueFromRow(row) ?: throw RemoteError.Server("bad_response")
    cacheVenue(added)
    return added
}

/** 确认地址：服务器不告诉别人确认过谁，状态以服务器为准 */
suspend fun Backend.confirmVenue(id: String): Venue {
    val row = remote.rpc<JsonObject>("confirm_venue", json("target" to id))
    val confirmed = venueFromRow(row) ?: throw RemoteError.Server("bad_response")
    cacheVenue(confirmed)
    return confirmed
}

suspend fun Backend.reportVenue(id: String, issue: VenueIssue, detail: String = "") {
    remote.call("report_venue", json("target" to id, "issue" to issue.serverValue, "detail" to detail.take(200)))
}

/** venues_by_ids 一次最多给这么多家（多的服务器不管），多了分批 */
internal const val VENUES_BY_IDS_LIMIT = 100

/**
 * 按 id 读球馆的整行：调服务器的 venues_by_ids，不直接读 venues 表（服务器以后只让按位置、搜索、按 id 的函数读，
 * 防止整表被翻页拿走）。超过 100 家分批；没有的 id 不返回
 */
internal suspend fun SupabaseClient.venueRowsByIds(ids: Collection<String>): List<JsonObject> {
    val rows = ArrayList<JsonObject>()
    for (batch in ids.distinct().chunked(VENUES_BY_IDS_LIMIT)) {
        rows += rpc<List<JsonObject>>("venues_by_ids", json("p_ids" to batch))
    }
    return rows
}

/** 按 id 读球馆（[venueRowsByIds]，读不懂的一家跳过） */
internal suspend fun SupabaseClient.venuesByIds(ids: Collection<String>): List<Venue> = venueRowsByIds(ids).mapNotNull(::venueFromRow)

/**
 * 服务器 venues 表的一整行（add_venue、confirm_venue、venues_by_ids 返回的）换成球馆：只读 iPhone 也读的那些列，
 * 别的列（营业时间这些服务器上的写法和本机不同）不管
 */
fun venueFromRow(row: JsonObject): Venue? {
    val columns = VENUE_COLUMNS.split(",").toSet()
    val kept = JsonObject(row.filterKeys { it in columns })
    return try {
        RemoteJSON.json.decodeFromJsonElement(Venue.serializer(), kept)
    } catch (_: SerializationException) {
        null
    } catch (_: IllegalArgumentException) {
        null
    }
}

private fun encode(text: String) = java.net.URLEncoder.encode(text, "UTF-8")

private val CoordinateDatum.serialName: String get() = if (this == CoordinateDatum.Gcj02) "gcj02" else "wgs84"

@Serializable
private class RegularCountRow(val venueId: String, val regulars: Int)

@Serializable
private class DuplicateRow(val venueId: String, val venueName: String, val kind: String, val distanceM: Double = 0.0)

@Serializable
private class RemoteVenuePeople(val recent: List<RemoteVenuePerson>? = null, val regulars: List<RemoteVenuePerson>? = null)

/** 服务器的 nearby_user：大厅里显示一个人要的那几项 */
@Serializable
private class RemoteVenuePerson(
    val id: String,
    val nickname: String,
    val tag: Int? = null,
    val rating: Double = 3.0,
    val gender: String? = null,
    val avatar: String? = null,
    val cardColor: String? = null,
    val cardPhoto: String? = null,
    val preferredMode: String? = null,
    val usualTimes: JsonElement? = null,
) {
    fun user(): User {
        val tier = SkillTier.ofRating(rating)
        return User.create(id, nickname, selfReportedLevel = tier.level).copy(
            tag = tag,
            selfReportedRating = rating,
            gender = Gender.ofServer(gender),
            preferredMode = preferredMode?.let(GameMode::ofServer),
            avatar = Avatar.default(id).copy(
                cardColor = CardColor.of(cardColor),
                photoVersion = avatar?.let(PhotoStore::version),
                cardPhotoVersion = cardPhoto?.let(PhotoStore::version),
            ),
        ).applyingVerification(VerificationStatus.Unverified, tier)
    }
}
