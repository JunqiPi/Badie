package com.badie.app.backend

import com.badie.app.models.MyStrikes
import com.badie.app.models.DISTANT_FUTURE
import com.badie.app.models.Rankings
import com.badie.app.models.ReportReason
import com.badie.app.models.ServerUsualTime
import com.badie.app.remote.InstantSerializer
import com.badie.app.remote.RemoteJSON
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import java.time.Instant
import java.time.ZoneId

// 正式后端：球友、球友资料、爽约记录、举报和屏蔽。
// 对应 iPhone 的 MockBackend+RemoteSocial.swift、MockBackend+RemoteRequests.swift 里调服务器的部分（参数和字段照抄）

@Serializable
class RemoteFriend(val id: String, val nickname: String, val rating: Double, @Serializable(InstantSerializer::class) val createdAt: Instant? = null)

@Serializable
class RemoteFriends(val friends: List<RemoteFriend>, val requests: List<RemoteFriend>)

/** 资料页上服务器给的“能不能私信”：friends / open / requested / request / new_account / none */
@Serializable
data class RemoteMessageOption(val status: String, val group: String? = null)

@Serializable
class RemoteWinRate(val games: Int, val wins: Int, val opponents: Int, val gap: Double, val rounds: Int? = null, val roundWins: Int? = null) {
    val rate: Rankings.WinRate get() = Rankings.WinRate(games, wins, opponents, gap, rounds, roundWins)
}

@Serializable
class RemotePlayerCard(
    val id: String,
    val nickname: String,
    val rating: Double,
    val tags: List<String> = emptyList(),
    val winRate: RemoteWinRate? = null,
    /** 'available'、'hidden' 或不能挑战的原因 */
    val challenge: String? = null,
    val message: RemoteMessageOption? = null,
    /** 认证类型（tournament / national / bwf），没认证是 null */
    val verified: String? = null,
    /** 男女等级分开算，资料页要标出是哪个等级 */
    val gender: String? = null,
    val tag: Int? = null,
    val recentNoShows: Int? = null,
    /** 时间，或永久的 "infinity" */
    val suspendedUntil: String? = null,
    val cardColor: String? = null,
    val cardPhoto: String? = null,
    val avatar: String? = null,
    /** 空闲时间（资料页上显示“常有空”） */
    val usualTimes: List<ServerUsualTime>? = null,
)

@Serializable
class FoundPlayer(val id: String, val nickname: String, val tag: Int? = null, val rating: Double, val relationship: String)

@Serializable
class RemoteRegular(val id: String, val nickname: String, val rating: Double, val venue: Venue) {
    @Serializable
    class Venue(val id: String)
}

@Serializable
private class RemoteMyStrikes(val suspendedUntil: String? = null, val recent: Int, val strikes: List<Item>) {
    @Serializable
    class Item(
        val id: Int,
        val level: Int,
        val status: String,
        @Serializable(InstantSerializer::class) val createdAt: Instant,
        val seen: Boolean,
        val canAppeal: Boolean,
        @Serializable(InstantSerializer::class) val gameStartsAt: Instant,
        val tz: String? = null,
        val venue: String? = null,
    )
}

class SocialApi(private val remote: SupabaseClient) {
    suspend fun myFriends(): RemoteFriends = remote.rpc("my_friends")

    /** 返回 requested（等对方通过）或 friends（对方也申请过，直接成为球友） */
    suspend fun sendFriendRequest(userId: String): String = remote.rpc("send_friend_request", json("p_user" to userId))

    suspend fun respondFriendRequest(userId: String, accept: Boolean) =
        remote.call("respond_friend_request", json("p_user" to userId, "p_accept" to accept))

    suspend fun removeFriend(userId: String) = remote.call("remove_friend", json("p_user" to userId))

    /** 按昵称搜球友：服务器只返回允许被搜到的人（不含屏蔽关系），并限速 */
    suspend fun findPlayers(query: String): List<FoundPlayer> = remote.rpc("find_players", json("p_query" to query))

    /** 只有打过交道的人才拉得到；拉不到是 null */
    suspend fun playerCard(userId: String): RemotePlayerCard? =
        remote.rpc("player_card", json("p_user" to userId), RemotePlayerCard.serializer().nullable)

    /** 打开别人的加球友链接：返回对方的 ID；链接失效返回 null */
    suspend fun openFriendLink(code: String): String? = remote.rpc("open_friend_link", json("p_code" to code), String.serializer().nullable)

    /** 换一个加球友链接，旧链接失效；返回新的码 */
    suspend fun resetFriendCode(): String = remote.rpc("reset_friend_code")

    suspend fun venueRegulars(): List<RemoteRegular> = remote.rpc("venue_regulars")

    suspend fun block(userId: String) = remote.call("block_user", json("p_user" to userId))

    suspend fun unblock(userId: String) = remote.call("unblock_user", json("p_user" to userId))

    suspend fun report(userId: String, reason: ReportReason, detail: String) {
        val serverReason = when (reason) {
            ReportReason.Harassment -> "harassment"
            ReportReason.Scam -> "scam"
            ReportReason.Unsafe -> "unsafe"
            ReportReason.FakeLevel -> "fake"
            ReportReason.WrongGender -> "wrong_gender"
            ReportReason.Inappropriate -> "inappropriate"
            ReportReason.NoShow, ReportReason.Other -> "other"
        }
        // 爽约没有对应的分类：写进说明里
        val details = if (reason == ReportReason.NoShow) listOf(reason.title, detail).filter { it.isNotEmpty() }.joinToString("：") else detail
        remote.call("report_user", json("p_user" to userId, "p_reason" to serverReason, "p_details" to details.take(500)))
    }

    /** 我的爽约记录（近 180 天） */
    suspend fun myStrikes(): MyStrikes {
        val raw = remote.rpc<RemoteMyStrikes>("my_strikes")
        return MyStrikes(
            suspendedUntil = suspension(raw.suspendedUntil),
            recent = raw.recent,
            strikes = raw.strikes.map {
                MyStrikes.Strike(
                    id = it.id, level = it.level, status = MyStrikes.Status.of(it.status) ?: MyStrikes.Status.Active,
                    createdAt = it.createdAt.toEpochMilli(), seen = it.seen, canAppeal = it.canAppeal,
                    gameStartsAt = it.gameStartsAt.toEpochMilli(),
                    timeZone = it.tz?.let { id -> runCatching { ZoneId.of(id) }.getOrNull() }, venue = it.venue,
                )
            },
        )
    }

    suspend fun markStrikesSeen() = remote.call("mark_strikes_seen")

    suspend fun appealStrike(id: Int, text: String) = remote.call("appeal_strike", json("p_strike" to id, "p_text" to text))

    companion object {
        /** 服务器给的暂停时间：永久是 "infinity" */
        fun suspension(value: String?): Long? {
            value ?: return null
            return if (value == "infinity") DISTANT_FUTURE else RemoteJSON.parseDate(value)?.toEpochMilli()
        }
    }
}
