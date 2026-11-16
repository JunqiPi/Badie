package com.badie.app.models

import com.badie.app.design.Sym
import com.badie.app.design.SymbolId
import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.ZoneId

// MARK: - 房间 / 球局招募

/** 球局氛围标签。rawValue 是存下来的值，不能改；显示用 title */
@Serializable(RoomTag.Serializer::class)
enum class RoomTag(val rawValue: String) {
    BeginnerFriendly("新手友好"),
    Casual("欢乐局"),
    Competitive("竞技局"),
    WomenFriendly("女生友好"),
    Coaching("可指导");

    val title: String
        get() = when (this) {
            BeginnerFriendly -> tr("新手友好")
            Casual -> tr("欢乐局")
            Competitive -> tr("竞技局")
            WomenFriendly -> tr("女生友好")
            Coaching -> tr("可指导")
        }

    val icon: SymbolId
        get() = when (this) {
            BeginnerFriendly -> Sym.leafFill
            Casual -> Sym.faceSmilingInverse
            Competitive -> Sym.flameFill
            WomenFriendly -> Sym.heartFill
            Coaching -> Sym.graduationcapFill
        }

    /** 服务器的写法 */
    val serverValue: String
        get() = when (this) {
            BeginnerFriendly -> "beginner_friendly"
            Casual -> "casual"
            Competitive -> "competitive"
            WomenFriendly -> "women_friendly"
            Coaching -> "coaching"
        }

    companion object {
        fun ofServer(value: String): RoomTag? = entries.firstOrNull { it.serverValue == value }
    }

    object Serializer : RawValueSerializer<RoomTag>("RoomTag", { it.rawValue }, { raw -> RoomTag.entries.first { it.rawValue == raw } })
}

@Serializable
enum class RoomVisibility {
    /** 仅凭房间码 / 好友邀请加入 */
    @SerialName("privateRoom") PrivateRoom,
    /** 公开到“附近球局”，任何符合水平的人可加入 */
    @SerialName("publicListing") PublicListing,
}

@Serializable
enum class RoomCloseReason {
    @SerialName("expired") Expired,
    @SerialName("ownerClosed") OwnerClosed,
    @SerialName("startTimePassed") StartTimePassed,
    /** 附近的人里的邀请：对方说这次来不了 */
    @SerialName("declined") Declined;

    val message: String
        get() = when (this) {
            Declined -> tr("这次来不了")
            Expired -> tr("房间 30 分钟无活动，已自动关闭")
            OwnerClosed -> tr("房主已解散房间")
            StartTimePassed -> tr("已过开始时间，房间已关闭")
        }

    companion object {
        /** 服务器的写法；不认识的按过期 */
        fun ofServer(value: String?): RoomCloseReason = when (value) {
            "owner_closed" -> OwnerClosed
            "start_time_passed" -> StartTimePassed
            "declined" -> Declined
            else -> Expired
        }
    }
}

@Serializable
sealed interface RoomStatus {
    @Serializable @SerialName("open") data object Open : RoomStatus
    @Serializable @SerialName("started") data class Started(val gameId: String) : RoomStatus
    @Serializable @SerialName("closed") data class Closed(val reason: RoomCloseReason) : RoomStatus

    val isOpen: Boolean get() = this == Open
}

@Serializable
data class RoomParticipant(
    val userId: String,
    val nickname: String,
    val skillLevel: Int,
    /** 加入时的细分档位分值；为空时按整数等级 */
    val skillRating: Double? = null,
    val avatar: Avatar,
    val joinedAt: Long,
) {
    val id: String get() = userId

    val tier: SkillTier get() = SkillTier.ofRating(skillRating ?: skillLevel.toDouble())

    val avatarText: String get() = avatar.text(nickname)

    /** 看不到名单时占位的人：只表示“这里有人” */
    val isAnonymous: Boolean get() = userId.startsWith("spot-") || userId.startsWith("wait-")

    companion object {
        fun of(user: User, joinedAt: Long = System.currentTimeMillis()): RoomParticipant = RoomParticipant(
            userId = user.id,
            nickname = user.nickname,
            skillLevel = user.displayLevel,
            skillRating = user.displayTier.rating,
            avatar = user.avatar,
            joinedAt = joinedAt,
        )

        /** 看不到名单时占位：只表示“这里有人” */
        fun anonymous(id: String): RoomParticipant =
            of(User(id = id, nickname = tr("球友"), phone = "", selfReportedLevel = 3), joinedAt = DISTANT_PAST)
    }
}

@Serializable
data class Room(
    val id: String,
    val code: String,
    val ownerId: String,
    val mode: GameMode,
    val visibility: RoomVisibility,
    val participants: List<RoomParticipant>,
    /** 已邀请但尚未加入的用户 */
    val invitedUserIds: List<String>,
    /** 候补名单（公开局满员后排队，有人退出自动递补） */
    val waitlist: List<RoomParticipant>,
    val court: Venue? = null,
    val slot: TimeSlot? = null,
    @Serializable(IntRangeSerializer::class) val levelRange: IntRange,
    val tags: List<RoomTag>,
    val note: String,
    val createdAt: Long,
    val lastActivityAt: Long,
    val status: RoomStatus,
    /** 项目：男单女单男双女双、混双；null = 不限 */
    val event: PlayEvent? = null,
    /** 混双局男女各有几个人（不算候补） */
    val mixedGoing: MixedGoing? = null,
    /** 附近的人里发的邀请局：还没定具体几点时的时间窗口（slot 就是整个窗口）；定好了或普通房间是 null */
    val window: PlayWindow? = null,
    /** 附近的人里发的邀请（谁约谁、轮到谁回）；普通房间是 null */
    val invite: LobbyInvite? = null,
) {
    @Serializable
    data class MixedGoing(val male: Int, val female: Int) {
        fun count(gender: Gender): Int = if (gender == Gender.Female) female else male
    }

    val requiredPlayerCount: Int get() = mode.requiredPlayers
    val isFull: Boolean get() = participants.size >= requiredPlayerCount
    val isReady: Boolean get() = participants.size == requiredPlayerCount
    val openSeats: Int get() = maxOf(0, requiredPlayerCount - participants.size)

    /** 和服务器一致：定了时间的到开始时间还没开局就关闭；没定时间的 30 分钟没有动静就关闭 */
    fun isExpired(now: Long = System.currentTimeMillis()): Boolean = now >= expiresAt()

    fun expiresAt(): Long {
        // 邀请局：到最晚回复的时间（窗口结束前 2 小时）
        invite?.let { return it.answerBy }
        return slot?.startTime ?: (lastActivityAt + EXPIRATION_DURATION)
    }

    fun contains(userId: String): Boolean = participants.any { it.userId == userId }

    fun isWaitlisted(userId: String): Boolean = waitlist.any { it.userId == userId }

    fun accepts(level: Int): Boolean = level in levelRange

    val levelRangeText: String
        get() {
            if (levelRange.first <= 1 && levelRange.last >= 9) return tr("不限水平")
            if (levelRange.first == levelRange.last) return "Lv.${levelRange.first}"
            return "Lv.${levelRange.first}–${levelRange.last}"
        }

    val costEstimate: CostSplit?
        get() {
            val court = court ?: return null
            val slot = slot ?: return null
            return CostSplit.estimate(court, slot, mode)
        }

    fun inviteText(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
        var text = tr("来 Badie 一起打%@。房间码：%@", mode.title, code)
        slot?.let { text += "\n${it.formattedFull(now, zone)}" }
        court?.let { text += "\n${it.name}" }
        return text + "\n" + joinLink(code)
    }

    companion object {
        /** 没定时间的房间多久没有动静就关闭（毫秒） */
        const val EXPIRATION_DURATION = 30 * 60_000L
        const val CODE_LENGTH = 6
        /** 去掉易混淆字符 0 O 1 I L */
        const val CODE_CHARACTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        const val MAX_WAITLIST = 4

        fun generateCode(excluding: Set<String> = emptySet()): String {
            var code: String
            do {
                code = (0 until CODE_LENGTH).map { CODE_CHARACTERS.random() }.joinToString("")
            } while (code in excluding)
            return code
        }

        /** 校验房间码格式（6 位、仅含合法字符） */
        fun isValidCode(code: String): Boolean {
            val upper = code.uppercase()
            return upper.length == CODE_LENGTH && upper.all { it in CODE_CHARACTERS }
        }

        /** 规范化用户输入：转大写、去掉空格与连字符、最多 6 位 */
        fun normalize(input: String): String = input.uppercase().filter { it != ' ' && it != '-' }.take(CODE_LENGTH)

        /** 邀请链接：装了 App 的直接打开加入页，没装的在网页上加入（房间码和群号都行） */
        fun joinLink(code: String): String = "https://badie.rsvp/join/?code=$code"
    }
}
