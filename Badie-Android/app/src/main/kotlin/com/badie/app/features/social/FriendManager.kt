package com.badie.app.features.social

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.RemoteFriends
import com.badie.app.backend.SocialApi
import com.badie.app.features.games.GameBook
import com.badie.app.models.CardColor
import com.badie.app.models.FriendRequest
import com.badie.app.models.FriendRequestStatus
import com.badie.app.models.Gender
import com.badie.app.models.MyStrikes
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.SkillTier
import com.badie.app.models.SurveyTag
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 球友、好友申请、加球友链接、球友资料、我的爽约记录。
 * 对应 iPhone 的 Managers/SocialManagers.swift 的 FriendManager（连正式后端的那一路），
 * 以及 AppState 里的爽约记录（strikes、refreshStrikes、appealStrike、markStrikesSeen）
 */
@Stable
class FriendManager(private val context: ManagerContext) {
    private val api = SocialApi(context.backend.remote)
    private val now: () -> Long = System::currentTimeMillis

    /** 和私信、球群共用的缓存 */
    val cache: SocialCache = SocialCache.of(context.backend).also {
        if (context.android != null) it.android = context.android
        it.refreshFriends = { refreshFriends() }
    }

    /** 同馆常客（只有本人开了的）的 ID */
    var regularIds by mutableStateOf<List<String>>(emptyList())
        private set
    private var regularsLoadedAt = 0L

    /** 我的爽约记录 */
    var strikes by mutableStateOf<MyStrikes?>(null)
        private set

    private var polling: Job? = null

    val currentUserId: String? get() = cache.me

    /** 我的球友（屏蔽的不算） */
    val friends: List<User>
        get() {
            val blocked = cache.blockedIds()
            return cache.friendIds.filter { it !in blocked }.mapNotNull(cache::user)
        }

    /** 收到、还没处理的好友申请（不含屏蔽的人） */
    val incomingRequests: List<FriendRequest>
        get() {
            val blocked = cache.blockedIds()
            return cache.incomingRequests.filter { it.fromUserId !in blocked }.sortedByDescending { it.sentAt }
        }

    /** 收到、还没处理的好友申请（消息标签的角标） */
    val incomingRequestCount: Int get() = incomingRequests.size

    fun user(id: String): User? = cache.user(id)

    fun isFriend(userId: String): Boolean = cache.isFriend(userId)

    fun searchFriends(query: String): List<User> {
        val text = query.trim()
        if (text.isEmpty()) return friends
        return friends.filter { it.nickname.contains(text, ignoreCase = true) }
    }

    fun hasPendingRequest(to: String): Boolean = cache.outgoingRequests.any { it.toUserId == to }

    fun incomingRequest(from: String): FriendRequest? = incomingRequests.firstOrNull { it.fromUserId == from }

    /** 别的球友：近 180 天爽约次数、不能约球到什么时候 */
    fun noShows(userId: String): Pair<Int, Long?> = cache.noShows[userId] ?: (0 to null)

    /** 正式后端不知道别人在哪：和 iPhone 一样没有距离 */
    fun distance(userId: String): Double? = null

    /** 我和 TA 共同的球友：服务器不给对方的球友名单，和 iPhone 正式后端一样总是空的 */
    fun mutualFriends(userId: String): List<User> = emptyList()

    /** 我和 TA 一起打完的球局（最近的在前） */
    fun gamesTogether(userId: String): List<GameBrief> =
        cache.games.filter { it.isCompleted && userId in it.playerIds }.sortedByDescending { it.startsAt }

    /** 一起打过球、还不是球友的人（最近的在前） */
    fun recentCoPlayers(limit: Int = 20): List<User> {
        val me = cache.me ?: return emptyList()
        val blocked = cache.blockedIds()
        val seen = HashSet<String>()
        return cache.games.filter { it.isCompleted }.sortedByDescending { it.startsAt }
            .flatMap { game -> game.playerIds.filter { it != me } }
            .filter { it !in blocked && !cache.isFriend(it) && seen.add(it) }
            .take(limit)
            .mapNotNull(cache::user)
    }

    /** 同馆常客常去的哪家（按用户 ID） */
    private var regularVenueIds by mutableStateOf<Map<String, String>>(emptyMap())

    /** 同馆常客和共同常去的那家球馆（球局页用；球馆读不到的不列，和 iPhone 一样） */
    fun venueRegulars(limit: Int = 20, venue: (String) -> Venue?): List<Pair<User, Venue>> =
        regularIds.mapNotNull { id ->
            val user = cache.user(id) ?: return@mapNotNull null
            val place = regularVenueIds[id]?.let(venue) ?: return@mapNotNull null
            user to place
        }.take(limit)

    /** 同馆常客里还不是球友的 */
    val regulars: List<User> get() = regularIds.mapNotNull(cache::user).filter { !cache.isFriend(it.id) }

    // MARK: 拉取

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {
        refreshFriends()
        refreshGames(force = true)
        refreshRegulars(force = true)
    }

    /** 球友和收到的申请 */
    suspend fun refreshFriends() {
        cache.syncAccount()
        val me = cache.me ?: return
        apply(api.myFriends(), me)
    }

    internal fun apply(remote: RemoteFriends, me: String) {
        for (friend in remote.friends + remote.requests) cache.cache(friend.id, friend.nickname, friend.rating)
        val ids = remote.friends.map { it.id }
        // 服务器只列别人发给我的申请；我发出的申请保留本地记录，直到成为球友
        val outgoing = cache.outgoingRequests.filter { it.toUserId !in ids }
        val incoming = remote.requests.map {
            FriendRequest("request-${it.id}", it.id, me, "", it.createdAt?.toEpochMilli() ?: now(), FriendRequestStatus.Pending)
        }
        if (cache.friendIds != ids) cache.friendIds = ids
        if (cache.incomingRequests != incoming) cache.incomingRequests = incoming
        if (cache.outgoingRequests != outgoing) cache.outgoingRequests = outgoing
    }

    /** 我的球局（资料卡上的“一起打过”、私信规则）：和球局页同一份（GameBook）；不强制时 60 秒内只拉一次 */
    suspend fun refreshGames(force: Boolean = false) {
        cache.syncAccount()
        val me = cache.me ?: return
        val book = GameBook.of(context.backend)
        book.refresh(ifOlderThan = if (force) GameBook.SHARED_REFRESH_MILLIS else 60_000)
        // 同局的人也记进球友的缓存（资料卡、“一起打过”的名单按 ID 找人）
        for (id in book.games.flatMap { it.playerIds }.toSet() - me) {
            book.user(id)?.let { cache.cache(id, it.nickname, it.selfReportedRating) }
        }
    }

    /** 同馆常客（5 分钟内不重复拉） */
    suspend fun refreshRegulars(force: Boolean = false) {
        cache.syncAccount()
        if (cache.me == null) return
        if (!force && now() - regularsLoadedAt < 300_000) return
        regularsLoadedAt = now()
        val rows = api.venueRegulars()
        for (row in rows) cache.cache(row.id, row.nickname, row.rating)
        regularIds = rows.map { it.id }
        regularVenueIds = rows.associate { it.id to it.venue.id }
    }

    /** 打开球友资料前拉取最新的昵称、等级、印象标签这些（只有打过交道的人才拉得到） */
    suspend fun refreshPlayer(userId: String) {
        cache.syncAccount()
        val card = try {
            api.playerCard(userId)
        } catch (_: RemoteError) {
            null
        } ?: return
        cache.cache(card.id, card.nickname, card.rating, card.tag)
        card.challenge?.let { cache.challengeStatus[card.id] = it } ?: cache.challengeStatus.remove(card.id)
        cache.noShows[card.id] = (card.recentNoShows ?: 0) to SocialApi.suspension(card.suspendedUntil)
        card.message?.let { cache.messageOptions[card.id] = it } ?: cache.messageOptions.remove(card.id)
        card.usualTimes?.let { times -> cache.usualTimes[card.id] = times.mapNotNull(RecurringTimeSlot::ofServer) }
        card.winRate?.let { cache.winRates[card.id] = it.rate }
        context.backend.photos.apply(card.id, card.avatar)
        context.backend.photos.applyCard(card.id, card.cardPhoto)
        cache.update(card.id) { user ->
            val tags = card.tags.mapNotNull(SurveyTag::ofServer)
            // 认证过的人按服务器的档位显示（不受未认证 7− 的上限限制）
            user.applyingVerification(VerificationStatus.ofServer(card.verified) ?: VerificationStatus.Unverified, SkillTier.ofRating(card.rating))
                .copy(
                    reputation = user.reputation.copy(publicTags = tags, publishedAt = if (tags.isEmpty()) null else now()),
                    gender = Gender.ofServer(card.gender),
                    avatar = user.avatar.copy(cardColor = CardColor.of(card.cardColor)),
                )
        }
    }

    // MARK: 球友

    /** 按昵称搜：只搜得到允许被搜到的人 */
    suspend fun findPlayers(query: String): List<User> {
        cache.syncAccount()
        val me = cache.me ?: throw RemoteError.NotSignedIn
        val found = api.findPlayers(query)
        for (player in found) {
            cache.cache(player.id, player.nickname, player.rating, player.tag)
            // 在别的设备上申请过的，也显示“等待通过”
            if (player.relationship == "requested" && !hasPendingRequest(player.id)) addOutgoing(me, player.id)
        }
        return found.mapNotNull { cache.user(it.id) }
    }

    private fun addOutgoing(me: String, userId: String) {
        cache.outgoingRequests = cache.outgoingRequests +
            FriendRequest("request-$me-$userId", me, userId, "", now(), FriendRequestStatus.Pending)
    }

    suspend fun sendRequest(userId: String) {
        cache.syncAccount()
        val me = cache.me ?: throw RemoteError.NotSignedIn
        val result = api.sendFriendRequest(userId)
        if (result == "requested" && !hasPendingRequest(userId)) addOutgoing(me, userId)
        refreshSocial()
    }

    suspend fun respond(request: FriendRequest, accept: Boolean) {
        api.respondFriendRequest(request.fromUserId, accept)
        refreshSocial()
    }

    suspend fun remove(userId: String) {
        api.removeFriend(userId)
        refreshSocial()
    }

    /** 球友有变化：球友和会话列表一起重拉 */
    private suspend fun refreshSocial() {
        refreshFriends()
        cache.refreshThreads?.invoke()
    }

    /** 打开别人的加球友链接：返回对方的 ID；链接失效返回 null */
    suspend fun openFriendLink(code: String): String? = api.openFriendLink(code)

    /** 换一个加球友链接，旧链接失效（重新读一遍自己的资料，拿到新的链接） */
    suspend fun resetFriendLink() {
        api.resetFriendCode()
        context.backend.refreshProfile()
    }

    // MARK: 爽约记录

    /** 打开 App、回到前台：读我的爽约记录；有没看过的就弹说明 */
    suspend fun refreshStrikes() {
        if (cache.me == null) return
        val latest = try {
            api.myStrikes()
        } catch (_: RemoteError) {
            return
        }
        strikes = latest
        if (latest.strikes.any { !it.seen }) context.appState.showsStrikes = true
    }

    suspend fun appealStrike(id: Int, text: String) {
        api.appealStrike(id, text)
        strikes = try {
            api.myStrikes()
        } catch (_: RemoteError) {
            strikes
        }
    }

    fun markStrikesSeen() {
        context.scope.launch {
            try {
                api.markStrikesSeen()
            } catch (_: RemoteError) {
            }
        }
    }

    // MARK: 轮询

    /** 没有实时推送：每 15 秒重拉一次球友和球局（回到前台时开始，退到后台时停） */
    fun startPolling() {
        if (polling?.isActive == true) return
        polling = context.scope.launch {
            while (isActive) {
                try {
                    refreshFriends()
                    refreshGames()
                    refreshRegulars()
                } catch (_: RemoteError) {
                    // 网络问题：下次再拉
                }
                delay(POLL_MILLIS)
            }
        }
    }

    fun stopPolling() {
        polling?.cancel()
        polling = null
    }

    companion object {
        const val POLL_MILLIS = 15_000L
    }
}
