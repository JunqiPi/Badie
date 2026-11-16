package com.badie.app.features.social

import android.content.Context
import androidx.core.content.edit
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.Backend
import com.badie.app.features.games.GameBook
import com.badie.app.models.Game
import com.badie.app.models.GameStatus
import com.badie.app.backend.RemoteMessageOption
import com.badie.app.models.BlockedUser
import com.badie.app.models.FriendRequest
import com.badie.app.models.MessageThread
import com.badie.app.models.Rankings
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.util.WeakHashMap

/** 我参加过的一场球（资料卡上的“一起打过几场”、私信规则里的“去球局群聊”） */
data class GameBrief(
    val id: String,
    val startsAt: Long,
    val endsAt: Long,
    val venueName: String,
    val playerIds: List<String>,
    val isCancelled: Boolean,
    /** 我填过赛果（iPhone 按这个算“打完了”） */
    val isCompleted: Boolean,
) {
    /** 球局群聊：没取消，赛后 48 小时内 */
    fun isChatOpen(now: Long): Boolean = !isCancelled && now <= endsAt + MessageThread.GAME_CHAT_OPEN_AFTER_END

    companion object {
        fun of(game: Game): GameBrief = GameBrief(
            id = game.id, startsAt = game.slot.startTime, endsAt = game.slot.endTime, venueName = game.court.name,
            playerIds = game.playerIds, isCancelled = game.status == GameStatus.Cancelled, isCompleted = game.status == GameStatus.Completed,
        )
    }
}

/**
 * 球友、私信、球群三个管理器共用的缓存：别人的昵称和等级、球友关系、屏蔽名单、资料卡上的其他信息、我的球局。
 * 对应 iPhone MockBackend 的 db.users、db.friendships、db.blocks 这些（安卓没有演示数据，只存服务器给的）。
 * 一个后端一份（[of]）；换了账号自动清空
 */
@Stable
class SocialCache private constructor(private val backend: Backend) {
    /** 本机存屏蔽名单、删掉的会话（iPhone 也只存在本机）；单元测试里没有 */
    var android: Context? = null
        set(value) {
            field = value
            owner = null
        }

    private val users = mutableStateMapOf<String, User>()

    var friendIds by mutableStateOf<List<String>>(emptyList())
    var incomingRequests by mutableStateOf<List<FriendRequest>>(emptyList())
    var outgoingRequests by mutableStateOf<List<FriendRequest>>(emptyList())
    var blocked by mutableStateOf<List<BlockedUser>>(emptyList())
        private set

    /** 每个会话“删除”的时间（只对自己隐藏） */
    var clearedAt by mutableStateOf<Map<String, Long>>(emptyMap())
        private set

    /** 资料卡（player_card）给的：近 180 天爽约次数和暂停到什么时候 */
    val noShows = mutableStateMapOf<String, Pair<Int, Long?>>()
    val messageOptions = mutableStateMapOf<String, RemoteMessageOption>()
    val challengeStatus = mutableStateMapOf<String, String>()
    val winRates = mutableStateMapOf<String, Rankings.WinRate>()
    val usualTimes = mutableStateMapOf<String, List<RecurringTimeSlot>>()

    /** 我的球局：和球局页同一份（GameBook，一次 my_games 拉齐） */
    val games: List<GameBrief> get() = GameBook.of(backend).games.map(GameBrief::of)

    /** 球友有变化后，会话列表也重拉（新球友、屏蔽）；由 MessageManager 接上 */
    var refreshThreads: (suspend () -> Unit)? = null
    var refreshFriends: (suspend () -> Unit)? = null

    private var owner: String? = null

    val me: String? get() = backend.currentUser?.id

    /** 换了账号：清掉上一个账号的东西（各管理器读服务器之前先调；不在界面里调，界面只读） */
    fun syncAccount() {
        val id = backend.currentUser?.id
        if (id == owner) return
        owner = id
        users.clear()
        friendIds = emptyList()
        incomingRequests = emptyList()
        outgoingRequests = emptyList()
        noShows.clear()
        messageOptions.clear()
        challengeStatus.clear()
        winRates.clear()
        usualTimes.clear()
        val stored = id?.let { load(it) } ?: Stored()
        blocked = stored.blocked
        clearedAt = stored.cleared
    }

    fun user(id: String): User? = if (id == me) backend.currentUser else users[id]

    /** 别的球友：服务器只给昵称和等级，存进缓存让界面能显示 */
    fun cache(id: String, nickname: String, rating: Double?, tag: Int? = null) {
        syncAccount()
        if (id == me) return
        val known = users[id] ?: User(id = id, nickname = nickname, phone = "", selfReportedLevel = SkillTier.ofRating(rating ?: 3.0).level)
        // 改了昵称编号可能也变了：没带编号就不沿用旧的
        var user = if (known.nickname != nickname || tag != null) known.copy(tag = tag) else known
        user = user.copy(nickname = nickname)
        if (rating != null) user = user.copy(selfReportedRating = rating)
        if (users[id] != user) users[id] = user
        backend.photos.requestAvatar(id)
    }

    fun update(id: String, change: (User) -> User) {
        users[id]?.let { users[id] = change(it) }
    }

    fun isFriend(userId: String): Boolean = userId in friendIds

    fun blockedIds(): Set<String> = blocked.map { it.blockedUserId }.toSet()

    fun isBlocked(userId: String): Boolean = blocked.any { it.blockedUserId == userId }

    /** 屏蔽：同时删掉球友关系和申请（服务器那边也一样），对方不会收到通知 */
    fun block(userId: String, now: Long) {
        syncAccount()
        val me = me ?: return
        if (userId == me || isBlocked(userId)) return
        blocked = blocked + BlockedUser(userId, now)
        friendIds = friendIds - userId
        incomingRequests = incomingRequests.filter { it.fromUserId != userId }
        outgoingRequests = outgoingRequests.filter { it.toUserId != userId }
        save(me)
    }

    fun unblock(userId: String) {
        syncAccount()
        val me = me ?: return
        blocked = blocked.filter { it.blockedUserId != userId }
        save(me)
    }

    fun clear(threadId: String, at: Long) {
        syncAccount()
        val me = me ?: return
        clearedAt = clearedAt + (threadId to at)
        save(me)
    }

    // MARK: 本机存储

    @Serializable
    private data class Stored(val blocked: List<BlockedUser> = emptyList(), val cleared: Map<String, Long> = emptyMap())

    private fun prefs() = android?.getSharedPreferences("social", Context.MODE_PRIVATE)

    private fun load(me: String): Stored = try {
        prefs()?.getString(me, null)?.let { storeJson.decodeFromString(Stored.serializer(), it) } ?: Stored()
    } catch (_: SerializationException) {
        Stored()
    } catch (_: IllegalArgumentException) {
        Stored()
    }

    private fun save(me: String) {
        prefs()?.edit { putString(me, storeJson.encodeToString(Stored.serializer(), Stored(blocked, clearedAt))) }
    }

    companion object {
        private val storeJson = Json { ignoreUnknownKeys = true }
        private val all = WeakHashMap<Backend, SocialCache>()

        fun of(backend: Backend): SocialCache = synchronized(all) { all.getOrPut(backend) { SocialCache(backend) } }
    }
}
