package com.badie.app.backend

import com.badie.app.models.Coordinate
import com.badie.app.models.Gender
import com.badie.app.models.GroupSchedule
import com.badie.app.models.PlayGroup
import com.badie.app.remote.InstantSerializer
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import java.time.Instant

// 正式后端：球群（固定局）。对应 iPhone 的 MockBackend+RemoteGroups.swift（参数和字段照抄）

/** venue：在哪个球馆；null = 主球馆（旧服务器没有这一项） */
@Serializable
class RemoteSchedule(
    val weekday: Int, val start: Int, val end: Int, val capacity: Int, val fee: String? = null, val venue: String? = null,
    /** 每人每场多少钱：0 = 免费，null = 没写（旧服务器没有这一项） */
    val price: Double? = null,
)

@Serializable
class RemoteGroupVenue(val id: String, val name: String, val city: String? = null, val tz: String? = null)

@Serializable
class RemoteGroupActivity(val sessions: Int, val average: Double)

@Serializable
class RemoteGroupSummary(
    val id: String,
    val name: String,
    val summary: String? = null,
    val levelMin: Int,
    val levelMax: Int,
    val joinPolicy: String,
    val gender: String? = null,
    val coached: Boolean? = null,
    /** 主球馆 */
    val venue: RemoteGroupVenue,
    /** 所有球馆，主球馆在前（旧服务器没有这一项） */
    val venues: List<RemoteGroupVenue>? = null,
    val schedules: List<RemoteSchedule>? = null,
    val activity: RemoteGroupActivity,
    val myRole: String? = null,
    /** groups_near 才有：离搜索中心最近的那个球馆有多远（米） */
    val distanceM: Double? = null,
)

@Serializable
class RemoteGroupDetail(
    val id: String,
    val name: String,
    val summary: String? = null,
    val levelMin: Int,
    val levelMax: Int,
    val joinPolicy: String,
    val gender: String? = null,
    val coached: Boolean? = null,
    val venue: RemoteGroupVenue,
    val venues: List<RemoteGroupVenue>? = null,
    val schedules: List<RemoteSchedule>? = null,
    val activity: RemoteGroupActivity,
    val myRole: String? = null,
    val inviteCode: String? = null,
    val sessions: List<Session>? = null,
    val members: List<Member>? = null,
    val pending: List<Member>? = null,
) {
    @Serializable
    class Session(
        val id: String,
        @Serializable(InstantSerializer::class) val startsAt: Instant,
        @Serializable(InstantSerializer::class) val endsAt: Instant,
        val capacity: Int,
        val cancelled: Boolean,
        val confirmed: Int,
        val waitlist: Int,
        val myStatus: String? = null,
        val players: List<Player>? = null,
        /** 这一场在哪个球馆（旧服务器没有这一项） */
        val venue: String? = null,
        /** 这一场每人多少钱（旧服务器没有这一项） */
        val price: Double? = null,
    ) {
        @Serializable
        class Player(val id: String, val nickname: String, val waitlisted: Boolean)
    }

    @Serializable
    class Member(val id: String, val nickname: String, val rating: Double, val role: String? = null)
}

@Serializable
private class RemoteMyGroups(val groups: List<RemoteGroupSummary>)

class GroupsApi(private val remote: SupabaseClient) {
    /** 我加入（含待审核）的球群 */
    suspend fun myGroups(): List<RemoteGroupSummary> = remote.rpc<RemoteMyGroups>("my_groups").groups

    /** 不存在（或被屏蔽）时是 null */
    suspend fun groupPage(groupId: String): RemoteGroupDetail? =
        remote.rpc("group_page", json("p_group" to groupId), RemoteGroupDetail.serializer().nullable)

    suspend fun groupsNear(center: Coordinate, radiusKm: Double): List<RemoteGroupSummary> =
        remote.rpc("groups_near", json("lat" to center.latitude, "lng" to center.longitude, "radius_km" to radiusKm))

    /** 返回新球群的 ID。venueIds：1–5 个球馆，第一个是主球馆（p_venue 也照旧发主球馆） */
    suspend fun create(
        name: String, venueIds: List<String>, schedules: List<GroupSchedule>, levelRange: IntRange, joinPolicy: PlayGroup.JoinPolicy,
        summary: String, audience: Gender?, coached: Boolean,
    ): String = remote.rpc(
        "create_group",
        json(
            "p_name" to name.trim(),
            "p_venue" to venueIds.first(),
            "p_venues" to venueIds,
            "p_summary" to summary.trim(),
            "p_level_min" to levelRange.first,
            "p_level_max" to levelRange.last,
            "p_policy" to joinPolicy.rawValue,
            "p_gender" to audience?.serverJSON,
            "p_coached" to coached,
            "p_schedules" to serverSchedules(schedules),
        ),
    )

    /** venueIds 为 null 时球馆不变 */
    suspend fun update(
        groupId: String, name: String, schedules: List<GroupSchedule>, levelRange: IntRange, joinPolicy: PlayGroup.JoinPolicy,
        summary: String, coached: Boolean, venueIds: List<String>? = null,
    ) = remote.call(
        "update_group",
        json(
            "p_group" to groupId,
            "p_name" to name.trim(),
            "p_summary" to summary.trim(),
            "p_level_min" to levelRange.first,
            "p_level_max" to levelRange.last,
            "p_policy" to joinPolicy.rawValue,
            "p_schedules" to serverSchedules(schedules),
            "p_coached" to coached,
            "p_venues" to venueIds,
        ),
    )

    suspend fun disband(groupId: String) = remote.call("disband_group", json("p_group" to groupId))

    /** 输群号找球群：返回球群 ID，找不到是 null */
    suspend fun find(code: String): String? = remote.rpc("find_group", json("p_code" to code), String.serializer().nullable)

    suspend fun join(groupId: String) = remote.call("join_group", json("p_group" to groupId))

    suspend fun leave(groupId: String) = remote.call("leave_group", json("p_group" to groupId))

    suspend fun approve(userId: String, groupId: String) =
        remote.call("respond_join_request", json("p_group" to groupId, "p_user" to userId, "p_accept" to true))

    suspend fun signUp(sessionId: String) = remote.call("sign_up_session", json("p_session" to sessionId))

    suspend fun cancelSignup(sessionId: String) = remote.call("cancel_signup", json("p_session" to sessionId))

    suspend fun cancelSession(sessionId: String) = remote.call("cancel_session", json("p_session" to sessionId))

    companion object {
        /** 服务器的星期是 0 = 周日（本地 1 = 周日）；不在主球馆的场次带上 venue */
        fun serverSchedules(schedules: List<GroupSchedule>): List<Map<String, Any?>> = schedules.map {
            val item = mutableMapOf<String, Any?>(
                "weekday" to it.weekday - 1, "start" to it.startMinutes, "end" to it.endMinutes, "capacity" to it.capacity, "fee" to (it.feeNote ?: ""),
                "price" to it.price,
            )
            it.venueId?.let { venue -> item["venue"] = venue }
            item
        }
    }
}
