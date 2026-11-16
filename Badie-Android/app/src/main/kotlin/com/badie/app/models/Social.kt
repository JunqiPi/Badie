package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.util.UUID

// MARK: - 好友

@Serializable
enum class FriendRequestStatus {
    @SerialName("pending") Pending,
    @SerialName("accepted") Accepted,
    @SerialName("declined") Declined,
}

@Serializable
data class FriendRequest(
    val id: String,
    val fromUserId: String,
    val toUserId: String,
    val note: String,
    val sentAt: Long,
    val status: FriendRequestStatus,
)

/** 双向好友关系。新建用 [Friendship.between]（两个 ID 排好序） */
@Serializable
data class Friendship(val id: String, val userIds: List<String>, val createdAt: Long) {
    fun involves(userId: String): Boolean = userId in userIds

    fun other(than: String): String? = userIds.firstOrNull { it != than }

    companion object {
        fun between(
            first: String, second: String,
            id: String = UUID.randomUUID().toString().uppercase(), createdAt: Long = System.currentTimeMillis(),
        ): Friendship = Friendship(id, listOf(first, second).sorted(), createdAt)
    }
}

// MARK: - 屏蔽与举报

@Serializable
data class BlockedUser(val blockedUserId: String, val blockedAt: Long) {
    val id: String get() = blockedUserId
}

/** rawValue 是存下来的值，不能改；显示用 title */
enum class ReportReason(val rawValue: String) {
    NoShow("爽约 / 临时放鸽子"),
    Harassment("骚扰或不当言论"),
    FakeLevel("严重虚报水平"),
    Scam("推销、诈骗或引流"),
    Unsafe("球场上危险或不文明行为"),
    /** 防止冒充进女生局 */
    WrongGender("资料里的性别不实"),
    /** 昵称、头像、消息不当（审核规则 1.2） */
    Inappropriate("不当内容（昵称、头像、消息）"),
    Other("其他");

    val title: String
        get() = when (this) {
            NoShow -> tr("爽约 / 临时放鸽子")
            Harassment -> tr("骚扰或不当言论")
            FakeLevel -> tr("严重虚报水平")
            Scam -> tr("推销、诈骗或引流")
            Unsafe -> tr("球场上危险或不文明行为")
            WrongGender -> tr("资料里的性别不实")
            Inappropriate -> tr("不当内容（昵称、头像、消息）")
            Other -> tr("其他")
        }
}

// MARK: - 同馆常客

/** 和我常去同一家球馆、并且本人开启了展示的球友 */
data class VenueRegular(
    val user: User,
    /** 我们共同常去的球馆（之一） */
    val venue: Venue,
) {
    val id: String get() = user.id
}

// MARK: - 站内通知

@Serializable
data class InboxItem(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val kind: Kind,
    val title: String,
    val body: String,
    val createdAt: Long = System.currentTimeMillis(),
    val isRead: Boolean = false,
    /** 关联对象 ID（用户、房间码、球局、问卷） */
    val relatedId: String? = null,
) {
    /** 不认识的种类（旧版本存下的）读成系统通知，不让整个缓存读不出来 */
    @Serializable(Kind.Serializer::class)
    enum class Kind(val rawValue: String) {
        FriendRequest("friendRequest"),
        FriendAccepted("friendAccepted"),
        RoomInvite("roomInvite"),
        RoomJoined("roomJoined"),
        Kicked("kicked"),
        RoomClosed("roomClosed"),
        WaitlistPromoted("waitlistPromoted"),
        SurveyDue("surveyDue"),
        GameConfirmed("gameConfirmed"),
        GameCancelled("gameCancelled"),
        GameReminder("gameReminder"),
        ReviewReceived("reviewReceived"),
        /** 找到搭子，等待确认 */
        MatchOffer("matchOffer"),
        /** 匹配进展（补位、没凑成、请求结束） */
        MatchUpdate("matchUpdate"),
        /** 有人想和你聊天（同球群的消息请求） */
        MessageRequest("messageRequest"),
        /** 球群动态（候补转正、加入申请通过、场次取消） */
        GroupUpdate("groupUpdate"),
        /** 你们都想再约一场 */
        Rematch("rematch"),
        /** 收到挑战 / 挑战有了回应 */
        Challenge("challenge"),
        /** 赛果确认、有分歧 */
        ResultUpdate("resultUpdate"),
        /** 附近的人：对方想换个时间 / 这次来不了；球局定好了具体时间 */
        InviteCounter("inviteCounter"),
        InviteDeclined("inviteDeclined"),
        GameTimeSet("gameTimeSet"),
        System("system");

        companion object {
            fun of(rawValue: String): Kind = entries.firstOrNull { it.rawValue == rawValue } ?: System
        }

        object Serializer : KSerializer<Kind> {
            override val descriptor = PrimitiveSerialDescriptor("com.badie.InboxItem.Kind", PrimitiveKind.STRING)
            override fun serialize(encoder: Encoder, value: Kind) = encoder.encodeString(value.rawValue)
            override fun deserialize(decoder: Decoder): Kind = of(decoder.decodeString())
        }
    }
}
