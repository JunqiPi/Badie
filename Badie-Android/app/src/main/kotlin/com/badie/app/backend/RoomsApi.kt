package com.badie.app.backend

import com.badie.app.models.Gender
import com.badie.app.models.GameMode
import com.badie.app.models.LobbyInvite
import com.badie.app.models.PlayEvent
import com.badie.app.models.Room
import com.badie.app.models.RoomCloseReason
import com.badie.app.models.RoomParticipant
import com.badie.app.models.RoomStatus
import com.badie.app.models.RoomTag
import com.badie.app.models.RoomVisibility
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.remote.EpochMillisSerializer
import com.badie.app.remote.json
import kotlinx.serialization.Serializable

// 正式后端：球局（房间）。对应 iPhone 的 MockBackend+RemoteRooms.swift。
// 水平范围、候补递补、过期关闭都在服务器上；界面读拉到的结果

/** 发起球局时填的 */
data class RoomDraft(
    val mode: GameMode = GameMode.Doubles,
    val visibility: RoomVisibility = RoomVisibility.PrivateRoom,
    val court: Venue? = null,
    val slot: TimeSlot? = null,
    val levelRange: IntRange = 1..9,
    val tags: List<RoomTag> = emptyList(),
    val note: String = "",
    val event: PlayEvent? = null,
)

@Serializable
class RemoteRoom(
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
    /** 只有房间里的人和受邀的人拿得到 */
    val code: String? = null,
    val members: List<Person>? = null,
    /** 附近的人里发的邀请局：还没定具体几点时 time_set = false，starts_at / ends_at 就是窗口 */
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
        val from: Person,
        val to: Person,
        /** 说好、不了、过期以后是 null */
        val awaitingId: String? = null,
        val rounds: Int = 0,
        @Serializable(EpochMillisSerializer::class) val answerBy: Long,
    )
}

object RoomMapping {
    /**
     * 服务器的房间换成本机的模型。[user] 按 ID 找已知的球友（自己、同局的人）；[existing] 是上次拉到的同一个房间。
     * 看不到名单时（公开局的外人）只有房主和人数，其余座位用匿名的人占位
     */
    fun room(info: RemoteRoom, me: String, existing: Room?, venue: Venue?, now: Long, user: (String) -> User?): Room {
        fun participant(person: RemoteRoom.Person): RoomParticipant {
            val joinedAt = existing?.let { room -> (room.participants + room.waitlist).firstOrNull { it.userId == person.id }?.joinedAt }
            val known = user(person.id) ?: GameMapping.player(RemotePlayer(person.id, person.nickname, person.rating, 0, false), null)
            return RoomParticipant.of(known, joinedAt ?: now)
        }
        val members = info.members
        val participants: List<RoomParticipant>
        val waitlist: List<RoomParticipant>
        if (members != null) {
            participants = members.filter { it.waitlisted != true }.map(::participant)
            waitlist = members.filter { it.waitlisted == true }.map(::participant)
        } else {
            participants = listOf(participant(info.owner)) + (1 until maxOf(1, info.going)).map { RoomParticipant.anonymous("spot-${info.id}-$it") }
            waitlist = (0 until info.waitlist).map { RoomParticipant.anonymous("wait-${info.id}-$it") }
        }
        val status = when (info.status) {
            "started" -> RoomStatus.Started(info.gameId ?: "")
            "closed" -> RoomStatus.Closed(RoomCloseReason.ofServer(info.closedReason))
            else -> RoomStatus.Open
        }
        val slot = if (info.startsAt != null && info.endsAt != null) TimeSlot(info.startsAt, info.startsAt, info.endsAt) else null
        val lastActivity = info.lastActivityAt ?: existing?.lastActivityAt ?: now
        return Room(
            id = info.id, code = info.code ?: existing?.code ?: "", ownerId = info.owner.id, mode = GameMode.ofServer(info.mode),
            visibility = if (info.visibility == "public") RoomVisibility.PublicListing else RoomVisibility.PrivateRoom,
            participants = participants, invitedUserIds = if (info.myStatus == "invited") listOf(me) else emptyList(), waitlist = waitlist,
            court = venue, slot = slot, levelRange = info.levelMin..maxOf(info.levelMin, info.levelMax),
            tags = info.tags.mapNotNull(RoomTag::ofServer), note = info.note,
            createdAt = existing?.createdAt ?: lastActivity, lastActivityAt = lastActivity, status = status,
            event = PlayEvent.ofServer(info.gender?.let(Gender::ofServer)?.takeIf { it != Gender.Unspecified }, info.mixed ?: false),
            mixedGoing = info.mixedGoing,
            window = GameMapping.window(info.timeSet, info.windowStart, info.windowEnd, info.daypart, info.durationMinutes),
            invite = info.invite?.let { LobbyInvite(it.from.id, it.to.id, it.awaitingId, it.rounds, it.answerBy) },
        )
    }

    fun createArgs(draft: RoomDraft) = json(
        "p_mode" to draft.mode.serverValue,
        "p_visibility" to if (draft.visibility == RoomVisibility.PublicListing) "public" else "private",
        "p_level_min" to draft.levelRange.first,
        "p_level_max" to draft.levelRange.last,
        "p_tags" to draft.tags.map { it.serverValue },
        "p_note" to draft.note.trim(),
        "p_gender" to draft.event?.gender?.serverJSON,
        "p_mixed" to (draft.event == PlayEvent.Mixed),
        // 私密局可以先不定时间和球馆（传 null）
        "p_venue" to draft.court?.id,
        "p_starts_at" to draft.slot?.let { GameMapping.iso(it.startTime) },
        "p_ends_at" to draft.slot?.let { GameMapping.iso(it.endTime) },
    )
}

// MARK: - 调服务器

/** 我在里面（或候补、受邀）的开放房间（只有概要，名单和房间码要再拉 room_page） */
suspend fun Backend.myRooms(): List<RemoteRoom> = remote.rpc("my_rooms")

/** 一个房间的详情；看不到了（私密局、被屏蔽）是 null */
suspend fun Backend.roomPage(roomId: String): RemoteRoom? = remote.rpc("room_page", json("p_room" to roomId))

/** 附近的公开局 */
suspend fun Backend.roomsNear(center: com.badie.app.models.Coordinate, radiusKm: Double): List<RemoteRoom> =
    remote.rpc("rooms_near", json("lat" to center.latitude, "lng" to center.longitude, "radius_km" to radiusKm))

suspend fun Backend.createRoom(draft: RoomDraft): String = remote.rpc("create_room", RoomMapping.createArgs(draft))

/** 凭房间码加入；找不到时报 room_not_found */
suspend fun Backend.joinRoomCode(code: String): String = remote.rpc("join_room_code", json("p_code" to code))

/** 群号：找到了返回球群 ID */
suspend fun Backend.findGroup(code: String): String? = remote.rpc("find_group", json("p_code" to code))

suspend fun Backend.joinRoom(roomId: String) = remote.call("join_room", json("p_room" to roomId))

suspend fun Backend.leaveRoom(roomId: String) = remote.call("leave_room", json("p_room" to roomId))

suspend fun Backend.removeRoomMember(roomId: String, userId: String) =
    remote.call("remove_room_member", json("p_room" to roomId, "p_user" to userId))

/** 只能邀请球友；服务器会通知对方 */
suspend fun Backend.inviteToRoom(roomId: String, userIds: List<String>) =
    remote.call("invite_to_room", json("p_room" to roomId, "p_users" to userIds))

suspend fun Backend.updateRoom(roomId: String, court: Venue?, slot: TimeSlot?) = remote.call(
    "update_room",
    json(
        "p_room" to roomId, "p_venue" to court?.id,
        "p_starts_at" to slot?.let { GameMapping.iso(it.startTime) }, "p_ends_at" to slot?.let { GameMapping.iso(it.endTime) },
    ),
)

/** 开局：服务器生成正式球局，返回球局 ID */
suspend fun Backend.startRoom(roomId: String): String = remote.rpc("start_room", json("p_room" to roomId))

/** 我的球友（邀请进房间时选） */
@Serializable
class RemoteRoomFriends(val friends: List<RemoteRoom.Person> = emptyList())

suspend fun Backend.myFriends(): List<RemoteRoom.Person> = remote.rpc<RemoteRoomFriends>("my_friends").friends
