package com.badie.app.backend

import com.badie.app.models.Avatar
import com.badie.app.models.CardColor
import com.badie.app.models.Coordinate
import com.badie.app.models.CostSplit
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.MatchOffer
import com.badie.app.models.MatchTicket
import com.badie.app.models.MatchTiming
import com.badie.app.models.PlayEvent
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenuePricing
import com.badie.app.models.VenueSource
import com.badie.app.models.VenueStatus
import com.badie.app.models.startOfDay
import com.badie.app.remote.EpochMillisSerializer
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId

// 快速匹配（约球请求、提议）和首页按天看人，对应 iPhone 的 MockBackend+RemoteGames.swift、
// MockBackend+Matchmaking.swift 的正式后端那一路、MockBackend+DayCards.swift。
// 球局（my_games）不在这里，归球局那一块

/** 服务器的时间写法 */
internal fun iso(millis: Long): String = Instant.ofEpochMilli(millis).toString()

// MARK: - 服务器的格式

@Serializable
class RemoteOffer(
    val id: String,
    @Serializable(EpochMillisSerializer::class) val startsAt: Long,
    @Serializable(EpochMillisSerializer::class) val endsAt: Long,
    @Serializable(EpochMillisSerializer::class) val respondBy: Long,
    val myResponse: String,
    @Serializable(EpochMillisSerializer::class) val lockAt: Long? = null,
    val venue: RemotePlace,
    val accepted: Int,
    val players: List<RemotePlayer>? = null,
) {
    /**
     * 服务器不告诉别人谁确认了，只给人数：自己按实际，其他人按人数依次标记（界面只显示人数）
     */
    fun offer(mode: GameMode, lastMinute: Boolean, court: Venue, createdAt: Long): MatchOffer {
        val people = players.orEmpty()
        val slot = TimeSlot.of(startsAt, startsAt, endsAt)
        var othersAccepted = accepted - if (myResponse == "accepted") 1 else 0
        val seats = people.map { player ->
            val yes = if (player.me) {
                myResponse == "accepted"
            } else {
                (othersAccepted > 0).also { othersAccepted -= 1 }
            }
            MatchOffer.Seat(player.id, null, if (yes) MatchOffer.Response.Accepted else MatchOffer.Response.Pending, respondBy)
        }
        return MatchOffer(
            id = id, mode = mode, slot = slot, commonOverlap = slot, court = court,
            teams = listOf(1, 2).map { team -> people.filter { it.team == team }.map { it.id } },
            seats = seats, cost = CostSplit.estimate(court, slot, mode), compatibility = 0, createdAt = createdAt,
            lockAt = lockAt ?: MatchTiming.lock(startsAt, lastMinute), isLastMinute = lastMinute, status = MatchOffer.Status.Open, backfillCount = 0,
        )
    }
}

@Serializable
class RemoteTicket(
    val id: String,
    val mode: String,
    @Serializable(EpochMillisSerializer::class) val startsAt: Long,
    @Serializable(EpochMillisSerializer::class) val endsAt: Long,
    val status: String,
    val skillTolerance: Int,
    val autoAccept: Boolean,
    @Serializable(EpochMillisSerializer::class) val lockAt: Long,
    val lastMinute: Boolean? = null,
    val playWith: String? = null,
    val mixed: Boolean? = null,
    val gameId: String? = null,
    val venues: List<RemotePlace>? = null,
    val offer: RemoteOffer? = null,
) {
    fun ticket(me: String, origin: Coordinate, createdAt: Long): MatchTicket {
        val state = when (status) {
            "offered" -> offer?.let { MatchTicket.Status.Offered(it.id) } ?: MatchTicket.Status.Searching
            "matched" -> gameId?.let { MatchTicket.Status.Matched(it) } ?: MatchTicket.Status.Expired
            "paused" -> MatchTicket.Status.Paused
            "expired" -> MatchTicket.Status.Expired
            "cancelled" -> MatchTicket.Status.Cancelled
            else -> MatchTicket.Status.Searching
        }
        return MatchTicket(
            id = id, userId = me, mode = GameMode.ofServer(mode), slot = TimeSlot.of(startsAt, startsAt, endsAt),
            courtIds = venues.orEmpty().map { it.id }, skillTolerance = skillTolerance, radiusKm = 0.0, origin = origin,
            autoAccept = autoAccept, isLastMinute = lastMinute ?: false, status = state, createdAt = createdAt, deadline = lockAt,
            hasPriority = false, excludedUserIds = emptyList(),
            event = PlayEvent.ofServer(playWith?.let { Gender.ofServer(it) }, mixed ?: false),
        )
    }
}

/** 我的请求：同一天附近找同类球局的人数，和其中条件都合适的人数 */
@Serializable
class TicketPool(val available: Int, val compatible: Int)

// MARK: - 按天看人的卡片

/** 某天附近在找人、我能约的一个请求 */
data class DayCandidate(
    val ticketId: String,
    val userId: String,
    val mode: GameMode,
    val mixed: Boolean,
    val startsAt: Long,
    val endsAt: Long,
    val recentNoShows: Int,
    val venues: List<Place>,
) {
    /** 卡片上的球馆 */
    data class Place(val id: String, val name: String, /** 离我多远（公里） */ val km: Double? = null)

    val id: String get() = ticketId
}

@Serializable
private class RemoteCandidate(
    val ticket: String,
    val mode: String,
    val mixed: Boolean,
    @Serializable(EpochMillisSerializer::class) val startsAt: Long,
    @Serializable(EpochMillisSerializer::class) val endsAt: Long,
    val user: RemoteLobbyUser,
    val venues: List<RemotePlaceKm>? = null,
)

@Serializable
internal class RemotePlaceKm(val id: String, val name: String, val km: Double? = null) {
    val place: DayCandidate.Place get() = DayCandidate.Place(id, name, km)
}

/** 卡片、邀请里带的人：昵称、等级、性别、头像和卡片背景、常打的项目、空闲时间 */
@Serializable
class RemoteLobbyUser(
    val id: String,
    val nickname: String,
    val tag: Int? = null,
    val rating: Double,
    val gender: String? = null,
    val recentNoShows: Int? = null,
    val avatar: String? = null,
    val cardColor: String? = null,
    val cardPhoto: String? = null,
    val preferredMode: String? = null,
    val usualTimes: List<com.badie.app.models.ServerUsualTime>? = null,
) {
    /** 换成本机的用户（[known] 是以前存下的同一个人，本机才有的东西接着用） */
    fun user(known: User? = null): User {
        val base = known ?: User(id = id, nickname = nickname, phone = "", selfReportedLevel = SkillTier.ofRating(rating).level)
        val avatarBase = base.avatar.takeIf { known != null } ?: Avatar.default(id)
        return base.copy(
            nickname = nickname,
            tag = tag ?: base.tag.takeIf { base.nickname == nickname },
            selfReportedRating = rating,
            gender = if (gender != null) Gender.ofServer(gender) else base.gender,
            preferredMode = preferredMode?.let(GameMode::ofServer),
            avatar = avatarBase.copy(
                cardColor = CardColor.of(cardColor),
                photoVersion = avatar?.let(PhotoStore::version),
                cardPhotoVersion = cardPhoto?.let(PhotoStore::version),
            ),
        )
    }
}

/** 头像和卡片背景：前两个人的先下好再显示，后面的边刷边下 */
internal suspend fun PhotoStore.applyLobby(people: List<RemoteLobbyUser>, later: (suspend () -> Unit) -> Unit) {
    for (person in people.take(2)) {
        apply(person.id, person.avatar)
        applyCard(person.id, person.cardPhoto)
    }
    val rest = people.drop(2)
    if (rest.isNotEmpty()) {
        later {
            for (person in rest) {
                apply(person.id, person.avatar)
                applyCard(person.id, person.cardPhoto)
            }
        }
    }
}

// MARK: - 接口

/** 快速匹配、按天看人的服务器接口 */
class MatchApi(private val backend: Backend) {
    private val remote get() = backend.remote

    /** 我的约球请求（进行中 + 最近结束）和各自的提议 */
    suspend fun myMatchmaking(): List<RemoteTicket> = remote.rpc("my_matchmaking")

    /** 发起请求；replacing 不为空时服务器在同一个事务里取消旧的、提交新的。返回请求 ID */
    suspend fun submitTicket(
        mode: GameMode, slot: TimeSlot, courtIds: List<String>, skillTolerance: Int, autoAccept: Boolean, event: PlayEvent?, replacing: String? = null,
    ): String {
        val pairs = mutableListOf<Pair<String, Any?>>(
            "p_mode" to mode.serverValue,
            "p_starts_at" to iso(slot.startTime),
            "p_ends_at" to iso(slot.endTime),
            "p_venue_ids" to courtIds,
            "p_skill_tolerance" to skillTolerance,
            "p_auto_accept" to autoAccept,
            "p_play_with" to event?.gender?.serverJSON,
            "p_mixed" to (event == PlayEvent.Mixed),
        )
        if (replacing != null) pairs += "p_ticket" to replacing
        return remote.rpc(if (replacing == null) "submit_ticket" else "replace_ticket", json(*pairs.toTypedArray()))
    }

    suspend fun cancelTicket(id: String) = remote.call("cancel_ticket", json("p_ticket" to id))

    suspend fun resumeTicket(id: String) = remote.call("resume_ticket", json("p_ticket" to id))

    suspend fun respondOffer(offerId: String, accept: Boolean) = remote.call("respond_offer", json("p_offer" to offerId, "p_accept" to accept))

    suspend fun ticketPool(id: String): TicketPool? = remote.rpc("ticket_pool", json("p_ticket" to id))

    /** 今后几天每天附近有多少人在找（按本机时区分天，键是 yyyy-MM-dd） */
    suspend fun poolByDay(center: Coordinate, radiusKm: Double, zone: ZoneId = ZoneId.systemDefault()): Map<String, Int> =
        remote.rpc("pool_by_day", json("p_lat" to center.latitude, "p_lon" to center.longitude, "p_radius_km" to radiusKm, "p_tz" to zone.id))

    /** 这天附近在找人、我能约的请求；卡片上的人一起返回 */
    suspend fun dayCandidates(
        day: Long, center: Coordinate, radiusKm: Double, zone: ZoneId = ZoneId.systemDefault(), known: (String) -> User? = { null },
        later: (suspend () -> Unit) -> Unit = {},
    ): Pair<List<DayCandidate>, List<User>> {
        val start = startOfDay(day, zone)
        val end = com.badie.app.models.addingDays(start, 1, zone)
        val items = remote.rpc<List<RemoteCandidate>>(
            "day_candidates",
            json("p_from" to iso(start), "p_to" to iso(end), "p_lat" to center.latitude, "p_lon" to center.longitude, "p_radius_km" to radiusKm),
        )
        backend.photos.applyLobby(items.map { it.user }, later)
        val users = items.map { it.user.user(known(it.user.id)) }
        val cards = items.map { item ->
            DayCandidate(
                item.ticket, item.user.id, GameMode.ofServer(item.mode), item.mixed, item.startsAt, item.endsAt,
                item.user.recentNoShows ?: 0, item.venues.orEmpty().map { it.place },
            )
        }
        return cards to users
    }

    suspend fun skipCandidate(ticketId: String) = remote.call("skip_candidate", json("p_ticket" to ticketId))

    /** 约 TA 打单打：服务器给我们俩发提议（我这边已确认），TA 确认就成局 */
    suspend fun inviteTicket(ticketId: String, venueId: String, startsAt: Long) =
        remote.call("invite_ticket", json("p_ticket" to ticketId, "p_venue" to venueId, "p_starts_at" to iso(startsAt)))

    /** 约 TA 打双打：服务器替我开一个公开的双打局（TA 的时间、这家球馆）并邀请 TA */
    suspend fun inviteDoubles(ticketId: String, venueId: String, startsAt: Long) {
        remote.rpc<String>("invite_doubles", json("p_ticket" to ticketId, "p_venue" to venueId, "p_starts_at" to iso(startsAt)))
    }

    /** 按 ID 读球馆（快速匹配选的球馆、请求里的球馆显示名字和距离用） */
    suspend fun venues(ids: List<String>): List<Venue> {
        if (ids.isEmpty()) return emptyList()
        return remote.select("venues", "select=$VENUE_FIELDS&id=in.(${ids.joinToString(",")})")
    }

    companion object {
        private const val VENUE_FIELDS = "id,name,aliases,lat,lon,street,unit,city,region,postal_code,country_code,status,location_approximate," +
            "time_zone_id,apple_place_id,court_count,pricing,pricing_note,currency_code,phone,website,entrance_note,source,created_at,play_times"

        /** 服务器按本机时区分天：yyyy-MM-dd */
        fun dayKey(day: Long, zone: ZoneId = ZoneId.systemDefault()): String =
            Instant.ofEpochMilli(day).atZone(zone).toLocalDate().toString()
    }
}
