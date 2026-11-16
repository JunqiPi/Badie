package com.badie.app.features.games

import android.content.Context
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.Backend
import com.badie.app.backend.GameMapping
import com.badie.app.backend.RemoteGame
import com.badie.app.backend.cancelGame
import com.badie.app.backend.checkIn
import com.badie.app.backend.markPaid
import com.badie.app.backend.myGames
import com.badie.app.backend.reportResult
import com.badie.app.backend.reviewPlayer
import com.badie.app.backend.setGameTime
import com.badie.app.models.Avatar
import com.badie.app.models.AttendanceAnswer
import com.badie.app.models.Game
import com.badie.app.models.GameCount
import com.badie.app.models.PendingSurvey
import com.badie.app.models.SkillTier
import com.badie.app.models.SurveyIssue
import com.badie.app.models.SurveyTag
import com.badie.app.models.User
import com.badie.app.remote.RemoteError
import com.badie.app.shell.AppState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.WeakHashMap

/**
 * 我的球局和待评价：一次 my_games 拉齐两样。RoomManager（球局列表、操作）和 SurveyManager（待评价）共用这一份，
 * 所以按后端各留一份（[of]）。iPhone 上球局在 MatchManager 里（nextGame / upcomingGames / pastGames），
 * 安卓的 MatchManager 归快速匹配那边，球局放到这里。
 * 也记着同局、同房间的球友（服务器只给昵称和等级），界面按 ID 找人用 [user]
 */
@Stable
class GameBook internal constructor(
    private val backend: Backend,
    private val now: () -> Long = System::currentTimeMillis,
) {
    var games by mutableStateOf<List<Game>>(emptyList())
        private set

    var pendingSurveys by mutableStateOf<List<PendingSurvey>>(emptyList())
        private set

    /** 同局、同房间的球友（不含自己） */
    private val players = mutableStateMapOf<String, User>()

    /** 拉到的是谁的：换了账号就清掉 */
    private var owner: String? = null

    private val refreshing = Mutex()

    /** 闹钟和通知要用；单元测试里为空 */
    internal var android: Context? = null

    val upcomingGames: List<Game> get() = games.filter { it.isUpcoming(now()) }.sortedBy { it.slot.startTime }

    val pastGames: List<Game> get() = games.filter { !it.isUpcoming(now()) }.sortedByDescending { it.slot.startTime }

    val nextGame: Game? get() = upcomingGames.firstOrNull()

    fun game(id: String): Game? = games.firstOrNull { it.id == id }

    fun user(id: String): User? {
        val me = backend.currentUser
        return if (me != null && me.id == id) me else players[id]
    }

    fun players(game: Game): List<User> = game.playerIds.mapNotNull(::user)

    /** 别处（房间）拉到的球友也记下来 */
    fun remember(user: User) {
        if (user.id != backend.currentUser?.id) players[user.id] = user
    }

    fun pending(gameId: String): List<PendingSurvey> = pendingSurveys.filter { it.matchId == gameId }

    fun survey(id: String): PendingSurvey? = pendingSurveys.firstOrNull { it.id == id }

    // MARK: 刷新

    /** 上次拉到的时间 */
    private var loadedAt = 0L

    /**
     * 重新拉一遍；没登录时清空。[ifOlderThan] 毫秒内拉过就不再拉
     * （下拉刷新时 RoomManager 和 SurveyManager 都会调，只拉一次）
     */
    suspend fun refresh(ifOlderThan: Long = 0) = refreshing.withLock {
        val me = backend.currentUser?.id
        if (me != owner) clear(me)
        if (me == null) return@withLock
        if (ifOlderThan > 0 && now() - loadedAt < ifOlderThan) return@withLock
        apply(backend.myGames(), me)
        loadedAt = now()
    }

    private fun clear(me: String?) {
        owner = me
        loadedAt = 0
        games = emptyList()
        pendingSurveys = emptyList()
        players.clear()
    }

    internal fun apply(rows: List<RemoteGame>, me: String) {
        val time = now()
        val before = games.associateBy { it.id }
        for (row in rows) {
            for (player in row.players.orEmpty()) {
                if (!player.me) players[player.id] = GameMapping.player(player, players[player.id])
            }
        }
        val fresh = rows.map { row -> GameMapping.game(row, me, row.venue.venue(backend.venue(row.venue.id)), before[row.id], time) }
        games = fresh
        pendingSurveys = GameMapping.pendingSurveys(rows, me, time) { id -> players[id]?.avatar ?: Avatar.default(id) }
        // 没定时间的球局定好了：开着的提醒按新的开始时间重排
        android?.let { context ->
            for (game in fresh) {
                if (game.isTimeSet && before[game.id]?.isTimeSet == false) ReminderService.rescheduleIfPending(context, game)
            }
        }
    }

    // MARK: 球局里的操作（做完都重新拉一遍）

    suspend fun cancel(game: Game) {
        backend.cancelGame(game.id)
        android?.let { ReminderService.cancel(it, game.id) }
        refreshQuietly()
    }

    suspend fun checkIn(game: Game) {
        backend.checkIn(game.id)
        refreshQuietly()
    }

    /** 标记 AA 已付：本人可以标自己，发起人可以标所有人。先改本机（马上有反应），再同步到服务器；失败就提示并按服务器的数据恢复 */
    fun togglePaid(game: Game, userId: String, scope: CoroutineScope, appState: AppState) {
        val me = backend.currentUser?.id ?: return
        if (userId != me && game.hostId != me) return
        val current = this.game(game.id) ?: return
        val paid = !current.hasPaid(userId)
        replace(current.copy(paidPlayerIds = if (paid) current.paidPlayerIds + userId else current.paidPlayerIds - userId))
        scope.launch {
            try {
                backend.markPaid(game.id, userId, paid)
            } catch (error: RemoteError) {
                appState.showError(error)
            }
            refreshQuietly()
        }
    }

    /** 开关提醒；没开通知权限时返回 false */
    fun setReminder(game: Game, enabled: Boolean): Boolean {
        val context = android
        if (enabled) {
            if (context == null || ReminderService.schedule(context, game, now()) == 0) return false
        } else if (context != null) {
            ReminderService.cancel(context, game.id)
        }
        replace(game.copy(reminderEnabled = enabled))
        return true
    }

    /** 结束球局：报两边各赢了几局（或练球、记不清） */
    suspend fun complete(game: Game, score: String, games: GameCount?, unsure: Boolean) {
        val didWin = games?.let { if (it.mine == it.theirs) null else it.mine > it.theirs }
        backend.reportResult(game, didWin, score, games = games)
        if (unsure) backend.reportResult(game, null, unsure = true)
        android?.let { ReminderService.cancel(it, game.id) }
        refreshQuietly()
    }

    /** 确认或修改赛果 */
    suspend fun report(game: Game, score: String, games: GameCount?, unsure: Boolean) {
        if (unsure) {
            backend.reportResult(game, null, unsure = true)
        } else {
            val didWin = games?.let { if (it.mine == it.theirs) null else it.mine > it.theirs }
            backend.reportResult(game, didWin, score, games = games)
        }
        refreshQuietly()
    }

    suspend fun setTime(game: Game, startsAt: Long) {
        backend.setGameTime(game.id, startsAt)
        refreshQuietly()
    }

    suspend fun submitSurvey(
        pending: PendingSurvey, skillRating: SkillTier, attendance: AttendanceAnswer,
        tags: List<SurveyTag>, issues: List<SurveyIssue>, wantsRematch: Boolean,
    ) {
        backend.reviewPlayer(pending, skillRating, attendance, tags, issues, wantsRematch)
        pendingSurveys = pendingSurveys.filter { it.id != pending.id }
        refreshQuietly()
    }

    /** 操作已经成功了：重新拉失败（网络）也不报错，下次再拉 */
    private suspend fun refreshQuietly() {
        try {
            refresh()
        } catch (_: RemoteError) {
        }
    }

    private fun replace(game: Game) {
        games = games.map { if (it.id == game.id) game else it }
    }

    companion object {
        /** 下拉刷新时两个管理器都会调：这么久之内拉过就不再拉 */
        const val SHARED_REFRESH_MILLIS = 2_000L

        private val books = WeakHashMap<Backend, GameBook>()

        /** 同一个后端共用一份 */
        fun of(backend: Backend): GameBook = synchronized(books) { books.getOrPut(backend) { GameBook(backend) } }
    }
}
