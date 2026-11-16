package com.badie.app.backend

import com.badie.app.models.Coordinate
import com.badie.app.models.Daypart
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.LobbyInvite
import com.badie.app.models.PlayEvent
import com.badie.app.models.PlayWindow
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.Room
import com.badie.app.models.RoomCloseReason
import com.badie.app.models.RoomParticipant
import com.badie.app.models.RoomStatus
import com.badie.app.models.RoomTag
import com.badie.app.models.RoomVisibility
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.remote.EpochMillisSerializer
import com.badie.app.remote.json
import kotlinx.serialization.Serializable

// 附近的人和邀请局，对应 iPhone 的 MockBackend+Nearby.swift（正式后端那一路）。
// 附近的人：有等级、打开了“在发现里显示我”、常去附近球馆的人（球友也在里面）。
// 右滑是约 TA：选单打或双打、哪天几点和球馆，发一个只邀请 TA 的局。TA 可以说好、换个时间或不了。每 24 小时最多发 10 个

/** 和 TA 之间的好友申请 */
enum class FriendRequestState {
    /** 我申请了加 TA */
    Sent,
    /** TA 申请了加我 */
    Received;

    companion object {
        fun ofServer(value: String?): FriendRequestState? = when (value) {
            "sent" -> Sent
            "received" -> Received
            else -> null
        }
    }
}

/** 附近的人里的一张卡 */
data class NearbyPlayer(
    val userId: String,
    val recentNoShows: Int,
    /** 常打单打还是双打（没填是 null） */
    val preferredMode: GameMode?,
    /** TA 常去、在我半径内的球馆，近的在前 */
    val venues: List<DayCandidate.Place>,
    /** 和我共同常去的球馆有几家 */
    val sharedVenues: Int,
    /** TA 的空闲时间 */
    val usualTimes: List<RecurringTimeSlot> = emptyList(),
    val isFriend: Boolean = false,
    val friendRequest: FriendRequestState? = null,
) {
    val id: String get() = userId
}

/** 约 TA 时默认的时间和球馆：两人空闲时间的交集（没有交集就只有球馆） */
data class InviteSuggestion(val window: PlayWindow? = null, val venueId: String? = null, val venueName: String? = null)

data class InviteResult(val roomId: String, /** 今天还能约几个 */ val remaining: Int)

@Serializable
private class RemoteNearbyPlayer(
    val user: RemoteLobbyUser,
    val venues: List<RemotePlaceKm>? = null,
    val sharedVenues: Int? = null,
    val isFriend: Boolean? = null,
    val friendRequest: String? = null,
)

@Serializable
private class RemoteSuggestion(
    @Serializable(EpochMillisSerializer::class) val windowStart: Long? = null,
    @Serializable(EpochMillisSerializer::class) val windowEnd: Long? = null,
    val daypart: String? = null,
    val venueId: String? = null,
    val venueName: String? = null,
)

@Serializable
private class RemoteInviteResult(val roomId: String, val remaining: Int)

@Serializable
private class RemoteRespondResult(val status: String, val gameId: String? = null)

/** 房间（这里只用到附近的人里的邀请局）。对应 iPhone 的 MockBackend+RemoteRooms.swift 的 RemoteRoom */
@Serializable
class RemoteInviteRoom(
    val id: String,
    val mode: String,
    val visibility: String,
    val status: String,
    val closedReason: String? = null,
    val gameId: String? = null,
    @Serializable(EpochMillisSerializer::class) val startsAt: Long? = null,
    @Serializable(EpochMillisSerializer::class) val endsAt: Long? = null,
    val levelMin: Int,
    val levelMax: Int,
    val tags: List<String> = emptyList(),
    val note: String = "",
    val gender: String? = null,
    val mixed: Boolean? = null,
    val mixedGoing: Room.MixedGoing? = null,
    val going: Int = 1,
    val waitlist: Int = 0,
    @Serializable(EpochMillisSerializer::class) val lastActivityAt: Long? = null,
    val owner: Person,
    val venue: RemotePlace? = null,
    val myStatus: String? = null,
    val code: String? = null,
    val members: List<Person>? = null,
    val timeSet: Boolean? = null,
    @Serializable(EpochMillisSerializer::class) val windowStart: Long? = null,
    @Serializable(EpochMillisSerializer::class) val windowEnd: Long? = null,
    val durationMinutes: Int? = null,
    val daypart: String? = null,
    val invite: Invite? = null,
) {
    @Serializable
    class Person(val id: String, val nickname: String, val rating: Double, val waitlisted: Boolean? = null)

    @Serializable
    class Invite(
        val from: RemoteLobbyUser,
        val to: RemoteLobbyUser,
        val awaitingId: String? = null,
        val rounds: Int,
        @Serializable(EpochMillisSerializer::class) val answerBy: Long,
    )

    /** 换成本机的房间；[user] 找名单里的人（自己、存下的球友） */
    fun room(me: String, now: Long, venue: (RemotePlace) -> com.badie.app.models.Venue, user: (String) -> User?): Room {
        fun participant(person: Person): RoomParticipant {
            val known = user(person.id) ?: User(id = person.id, nickname = person.nickname, phone = "", selfReportedLevel = SkillTier.ofRating(person.rating).level, selfReportedRating = person.rating)
            return RoomParticipant.of(known, now)
        }
        val listed = members
        val participants = listed?.filter { it.waitlisted != true }?.map(::participant)
            ?: (listOf(participant(owner)) + (1 until maxOf(1, going)).map { RoomParticipant.anonymous("spot-$id-$it") })
        val waiting = listed?.filter { it.waitlisted == true }?.map(::participant) ?: (0 until waitlist).map { RoomParticipant.anonymous("wait-$id-$it") }
        val state = when (status) {
            "started" -> RoomStatus.Started(gameId ?: "")
            "closed" -> RoomStatus.Closed(RoomCloseReason.ofServer(closedReason))
            else -> RoomStatus.Open
        }
        val slot = if (startsAt != null && endsAt != null) TimeSlot.of(startsAt, startsAt, endsAt) else null
        val activity = lastActivityAt ?: now
        return Room(
            id = id, code = code ?: "", ownerId = owner.id, mode = GameMode.ofServer(mode),
            visibility = if (visibility == "public") RoomVisibility.PublicListing else RoomVisibility.PrivateRoom,
            participants = participants, invitedUserIds = if (myStatus == "invited") listOf(me) else emptyList(), waitlist = waiting,
            court = this.venue?.let(venue), slot = slot, levelRange = levelMin..maxOf(levelMin, levelMax),
            tags = tags.mapNotNull(RoomTag::ofServer), note = note, createdAt = activity, lastActivityAt = activity, status = state,
            event = PlayEvent.ofServer(gender?.let { Gender.ofServer(it) }, mixed ?: false), mixedGoing = mixedGoing,
            window = window(timeSet, windowStart, windowEnd, daypart, durationMinutes),
            invite = invite?.let { LobbyInvite(it.from.id, it.to.id, it.awaitingId, it.rounds, it.answerBy) },
        )
    }

    companion object {
        /** 还没定具体几点（time_set = false）的时间窗口；定好了是 null */
        fun window(timeSet: Boolean?, start: Long?, end: Long?, daypart: String?, duration: Int?): PlayWindow? {
            if (timeSet != false || start == null || end == null) return null
            return PlayWindow(start, end, Daypart.of(daypart), duration ?: 120)
        }
    }
}

/** 附近的人、邀请的服务器接口 */
class NearbyApi(private val backend: Backend) {
    private val remote get() = backend.remote

    /** 附近的人；卡片上的人一起返回 */
    suspend fun nearbyPlayers(
        center: Coordinate, radiusKm: Double, known: (String) -> User? = { null }, later: (suspend () -> Unit) -> Unit = {},
    ): Pair<List<NearbyPlayer>, List<User>> {
        val items = remote.rpc<List<RemoteNearbyPlayer>>(
            "nearby_players", json("p_lat" to center.latitude, "p_lon" to center.longitude, "p_radius_km" to radiusKm),
        )
        val me = backend.currentUser?.id
        val people = items.filter { it.user.id != me }
        backend.photos.applyLobby(people.map { it.user }, later)
        val users = people.map { it.user.user(known(it.user.id)) }
        val cards = people.map { item ->
            NearbyPlayer(
                userId = item.user.id, recentNoShows = item.user.recentNoShows ?: 0,
                preferredMode = item.user.preferredMode?.let(GameMode::ofServer),
                venues = item.venues.orEmpty().map { it.place }, sharedVenues = item.sharedVenues ?: 0,
                usualTimes = item.user.usualTimes.orEmpty().mapNotNull(RecurringTimeSlot::ofServer),
                isFriend = item.isFriend ?: false, friendRequest = FriendRequestState.ofServer(item.friendRequest),
            )
        }
        return cards to users
    }

    /** 左滑：30 天内不再出现 */
    suspend fun skipNearby(userId: String) = remote.call("skip_nearby", json("p_user" to userId))

    /** 约 TA 时默认填的时间和球馆（拿不到就是 null） */
    suspend fun suggestInvite(userId: String, venueId: String? = null): InviteSuggestion? {
        val raw = try {
            remote.rpc<RemoteSuggestion?>("suggest_invite_window", json("p_user" to userId, "p_venue" to venueId))
        } catch (_: com.badie.app.remote.RemoteError) {
            null
        } ?: return null
        val window = if (raw.windowStart != null && raw.windowEnd != null) PlayWindow(raw.windowStart, raw.windowEnd, Daypart.of(raw.daypart)) else null
        return InviteSuggestion(window, raw.venueId, raw.venueName)
    }

    /** 发邀请：一个只邀请 TA 的局。窗口正好一场那么长（durationMinutes）就是定好的时间 */
    suspend fun invitePlayer(userId: String, venueId: String, window: PlayWindow, mode: GameMode = GameMode.Singles): InviteResult {
        val raw = remote.rpc<RemoteInviteResult>(
            "invite_player",
            json(
                "p_user" to userId, "p_venue" to venueId, "p_window_start" to iso(window.start), "p_window_end" to iso(window.end),
                "p_daypart" to window.daypart?.rawValue, "p_duration" to window.durationMinutes, "p_mode" to mode.serverValue,
            ),
        )
        return InviteResult(raw.roomId, raw.remaining)
    }

    /** 邀请和里面的人（含 TA 的空闲时间） */
    class Invites(val rooms: List<Room>, val users: List<User>, val usualTimes: Map<String, List<RecurringTimeSlot>>)

    /** 我发出的、收到的还没结束的邀请（轮到我回的在前） */
    suspend fun nearbyInvites(known: (String) -> User? = { null }): Invites {
        val me = backend.currentUser ?: return Invites(emptyList(), emptyList(), emptyMap())
        val rooms = remote.rpc<List<RemoteInviteRoom>>("nearby_invites")
        val people = rooms.flatMap { listOfNotNull(it.invite?.from, it.invite?.to) }.filter { it.id != me.id }.distinctBy { it.id }
        for (person in people) backend.photos.apply(person.id, person.avatar)
        val users = people.map { it.user(known(it.id)) }
        val byId = users.associateBy { it.id } + (me.id to me)
        val now = System.currentTimeMillis()
        val times = people.filter { it.usualTimes != null }.associate { person -> person.id to person.usualTimes.orEmpty().mapNotNull(RecurringTimeSlot::ofServer) }
        return Invites(rooms.map { room -> room.room(me.id, now, { place -> place.venue(backend.venue(place.id)) }) { byId[it] ?: known(it) } }, users, times)
    }

    /** 好 / 不了。说好返回球局 ID */
    suspend fun respondInvite(roomId: String, accept: Boolean): String? =
        remote.rpc<RemoteRespondResult>("respond_invite", json("p_room" to roomId, "p_accept" to accept)).gameId

    /** 换个时间：venueId 为 null 时球馆不变 */
    suspend fun counterInvite(roomId: String, venueId: String?, window: PlayWindow, mode: GameMode = GameMode.Singles) = remote.call(
        "counter_invite",
        json(
            "p_room" to roomId, "p_venue" to venueId, "p_window_start" to iso(window.start), "p_window_end" to iso(window.end),
            "p_daypart" to window.daypart?.rawValue, "p_duration" to window.durationMinutes, "p_mode" to mode.serverValue,
        ),
    )

    companion object {
        /** 每 24 小时最多发几个邀请（换个时间、加球友不算） */
        const val INVITE_LIMIT = 10
    }
}
