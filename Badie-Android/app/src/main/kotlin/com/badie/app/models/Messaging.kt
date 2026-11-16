package com.badie.app.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

// MARK: - 私信

@Serializable
sealed interface MessageKind {
    @Serializable @SerialName("text") data object Text : MessageKind
    /** 房间邀请卡片 */
    @Serializable @SerialName("roomInvite") data class RoomInvite(val code: String) : MessageKind
    /** 球局分享卡片 */
    @Serializable @SerialName("gameShare") data class GameShare(val gameId: String) : MessageKind
    /** 系统提示（如"你们已成为球友"） */
    @Serializable @SerialName("system") data object System : MessageKind
}

@Serializable
data class Message(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val threadId: String,
    val senderId: String,
    val content: String,
    val sentAt: Long = System.currentTimeMillis(),
    val deliveredAt: Long? = null,
    val readAt: Long? = null,
    val kind: MessageKind = MessageKind.Text,
) {
    val isDelivered: Boolean get() = deliveredAt != null
    val isRead: Boolean get() = readAt != null

    companion object {
        const val MAX_CONTENT_LENGTH = 1000

        /** 验证消息内容（1-1000 字） */
        fun validate(content: String): MessageValidation {
            if (content.trim().isEmpty()) return MessageValidation.Empty
            if (content.characterCount > MAX_CONTENT_LENGTH) return MessageValidation.TooLong
            return MessageValidation.Valid
        }
    }
}

enum class MessageValidation { Valid, Empty, TooLong }

// MARK: - 防骗：站外联系方式与链接

object ContactInfoDetector {
    private val keywords = listOf(
        "微信", "wechat", "weixin", "vx", "v信", "加v", "whatsapp", "telegram", "电报", "line id",
        "手机号", "电话号", "venmo", "zelle", "paypal", "cash app", "cashapp", "验证码",
    )

    private val phoneLike = Regex("""(?:\d[\s\-.]?){7,}""")

    /**
     * 链接：iPhone 用系统的 NSDataDetector。这里用正则认 http(s)://、www. 开头的，
     * 和“名字.常见后缀”这种不带协议的网址
     */
    private val link = Regex(
        """(?i)(?:\b[a-z][a-z0-9+.-]*://\S+|\bwww\.[^\s.]+\.\S+|\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*""" +
            """\.(?:com|net|org|io|co|me|app|dev|info|biz|xyz|top|cn|hk|tw|sg|my|jp|kr|uk|au|ca|us|in|id|th|vn|ph|nz|de|fr|dk|ly|gl|link|site|online|shop|rsvp)\b(?:/\S*)?)""",
    )

    /** 是否提到站外联系方式或转账方式（手机号、微信、WhatsApp、Venmo…） */
    fun mentionsOffPlatformContact(text: String): Boolean {
        val lower = text.lowercase()
        if (keywords.any { it in lower }) return true
        return phoneLike.containsMatchIn(text)
    }

    fun containsLink(text: String): Boolean = link.containsMatchIn(text)
}

/** 群聊的来源 */
@Serializable
sealed interface ThreadContext {
    /** 球局群：确认后开放，赛后 48 小时关闭 */
    @Serializable @SerialName("game") data class Game(val gameId: String) : ThreadContext
    /** 球群：成员都在 */
    @Serializable @SerialName("group") data class Group(val groupId: String) : ThreadContext
}

/** 会话：两人私信，或球局 / 球群的群聊 */
@Serializable
data class MessageThread(
    val id: String,
    val participantIds: List<String>,
    val lastMessage: Message? = null,
    val lastActivityAt: Long,
    /** 每位参与者的未读数 */
    val unreadCounts: Map<String, Int> = emptyMap(),
    /** 每位参与者“删除会话”的时间：只隐藏该时间之前的消息，对方不受影响 */
    val clearedAt: Map<String, Long> = emptyMap(),
    /** null = 两人私信 */
    val context: ThreadContext? = null,
    /** 群聊标题 */
    val title: String? = null,
    /** 消息请求的发起人：对方接受前只能发这一条 */
    val requestFrom: String? = null,
    val isPendingRequest: Boolean = false,
) {
    val isGroup: Boolean get() = context != null

    fun otherParticipantId(currentUserId: String): String? = participantIds.firstOrNull { it != currentUserId }

    fun unreadCount(userId: String): Int = unreadCounts[userId] ?: 0

    /** 对某个用户是否可见（删除后无新消息则隐藏） */
    fun isVisible(userId: String): Boolean {
        val last = lastMessage ?: return false
        val cleared = clearedAt[userId] ?: return true
        return last.sentAt > cleared
    }

    companion object {
        /** 赛后多久关闭球局群聊（毫秒） */
        const val GAME_CHAT_OPEN_AFTER_END = 48 * 3_600_000L

        fun id(first: String, second: String): String = listOf(first, second).sorted().joinToString("|")

        fun gameThreadId(gameId: String): String = "game-$gameId"

        fun groupThreadId(groupId: String): String = "group-$groupId"
    }
}
