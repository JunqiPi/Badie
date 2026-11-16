package com.badie.app.backend

import com.badie.app.models.InboxItem
import com.badie.app.models.MessageThread
import com.badie.app.remote.InstantSerializer
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import java.time.Instant

// 正式后端：会话、消息、站内通知，以及资料卡、私信规则要用的“我的球局”简表。
// 对应 iPhone 的 MockBackend+RemoteSocial.swift、MockBackend+RemoteRequests.swift（参数和字段照抄）

@Serializable
class RemoteThreadSummary(
    val kind: String,
    val id: String,
    @Serializable(InstantSerializer::class) val startsAt: Instant? = null,
    val venue: String? = null,
    val name: String? = null,
    /** open / closed / requested / request */
    val access: String,
    /** 还没接受的消息请求：incoming = 对方发给我的，outgoing = 我发的 */
    val request: String? = null,
    val last: Last? = null,
    val unread: Int = 0,
) {
    @Serializable
    class Last(val body: String, @Serializable(InstantSerializer::class) val createdAt: Instant, val mine: Boolean)
}

@Serializable
class RemoteThread(val access: String, val members: List<Member>? = null, val messages: List<Item> = emptyList()) {
    @Serializable
    class Member(val id: String, val nickname: String, val me: Boolean)

    @Serializable
    class Item(val id: Long, val body: String, @Serializable(InstantSerializer::class) val createdAt: Instant, val sender: String, val mine: Boolean)
}

@Serializable
class RemoteNotification(
    val id: Long,
    val kind: String,
    val title: String,
    val body: String,
    val link: String? = null,
    @Serializable(InstantSerializer::class) val createdAt: Instant,
    @Serializable(InstantSerializer::class) val readAt: Instant? = null,
)

/** my_games 里资料卡和私信规则用得到的几项（一起打过几场、正在进行的球局群聊） */
@Serializable
class RemoteGameBrief(
    val id: String,
    @Serializable(InstantSerializer::class) val startsAt: Instant,
    @Serializable(InstantSerializer::class) val endsAt: Instant,
    val status: String,
    val venue: Venue,
    val myReport: JsonElement? = null,
    val players: List<Player>? = null,
) {
    @Serializable
    class Venue(val id: String, val name: String)

    @Serializable
    class Player(val id: String, val nickname: String, val rating: Double)
}

class MessagesApi(private val remote: SupabaseClient) {
    suspend fun myThreads(): List<RemoteThreadSummary> = remote.rpc("my_threads")

    /** 拉取一个会话的消息（服务器同时记为已读） */
    suspend fun openThread(kind: String, id: String): RemoteThread = remote.rpc("open_thread", json("p_kind" to kind, "p_id" to id))

    suspend fun send(kind: String, id: String, body: String) = remote.call("send_message", json("p_kind" to kind, "p_id" to id, "p_body" to body))

    /** 接受或忽略收到的消息请求；忽略只是不再显示，对方仍看到“等待接受” */
    suspend fun respondMessageRequest(userId: String, accept: Boolean) =
        remote.call("respond_message_request", json("p_user" to userId, "p_accept" to accept))

    /** 最近 50 条通知 */
    suspend fun notifications(): List<RemoteNotification> =
        remote.select("notifications", "select=id,kind,title,body,link,created_at,read_at&order=id.desc&limit=50")

    /** 服务器一次把通知全部记为已读 */
    suspend fun markNotificationsRead() = remote.call("mark_notifications_read")

    suspend fun myGames(): List<RemoteGameBrief> = remote.rpc("my_games")

    companion object {
        /** 本地会话 ID ↔ 服务器的 (kind, id) */
        fun threadId(kind: String, id: String, me: String): String = when (kind) {
            "dm" -> MessageThread.id(me, id)
            "game" -> MessageThread.gameThreadId(id)
            else -> MessageThread.groupThreadId(id)
        }

        fun serverThread(threadId: String, me: String?): Pair<String, String>? {
            if (threadId.startsWith("game-")) return "game" to threadId.removePrefix("game-")
            if (threadId.startsWith("group-")) return "group" to threadId.removePrefix("group-")
            val ids = threadId.split("|")
            if (ids.size != 2 || me == null) return null
            val other = ids.firstOrNull { it != me } ?: return null
            return "dm" to other
        }

        fun inboxKind(kind: String): InboxItem.Kind = when (kind) {
            "matched" -> InboxItem.Kind.GameConfirmed
            "offer", "offer_auto" -> InboxItem.Kind.MatchOffer
            "requeued", "missed", "expired" -> InboxItem.Kind.MatchUpdate
            "cancelled" -> InboxItem.Kind.GameCancelled
            "friend" -> InboxItem.Kind.FriendAccepted
            "friend_request" -> InboxItem.Kind.FriendRequest
            "review" -> InboxItem.Kind.SurveyDue
            "group" -> InboxItem.Kind.GroupUpdate
            "room" -> InboxItem.Kind.RoomJoined
            "room_promoted" -> InboxItem.Kind.WaitlistPromoted
            "room_removed" -> InboxItem.Kind.Kicked
            "room_closed" -> InboxItem.Kind.RoomClosed
            "challenge" -> InboxItem.Kind.Challenge
            "message_request" -> InboxItem.Kind.MessageRequest
            "invite_counter" -> InboxItem.Kind.InviteCounter
            "invite_declined" -> InboxItem.Kind.InviteDeclined
            "game_time_set" -> InboxItem.Kind.GameTimeSet
            else -> InboxItem.Kind.System
        }

        /**
         * 通知点开去哪：链接里的 ID（球局、球友、球群）。
         * 找到搭子的通知（offer）iPhone 指向手机上有提议的那个请求，安卓的快速匹配还没搬，先不带
         */
        fun relatedId(kind: String, link: String?): String? {
            if (kind == "offer" || kind == "offer_auto") return null
            // 消息请求的链接是 /app/messages/dm/<对方 id>/
            if (kind == "message_request") return link?.split("/")?.lastOrNull { it.isNotEmpty() }
            val parts = (link ?: "").split("/").filter { it.isNotEmpty() }
            return if (parts.size >= 3) parts[2] else null
        }
    }
}
