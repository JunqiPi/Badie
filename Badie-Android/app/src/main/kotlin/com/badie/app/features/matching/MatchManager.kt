package com.badie.app.features.matching

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.MatchApi
import com.badie.app.backend.NearbyApi
import com.badie.app.design.Toast
import com.badie.app.l10n.L10n.tr
import com.badie.app.features.venues.LocationManager
import com.badie.app.models.Coordinate
import com.badie.app.models.DistanceUnit
import com.badie.app.models.MatchOffer
import com.badie.app.models.MatchTicket
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.UserPreferences
import com.badie.app.models.Venue
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 快速匹配：约球请求、匹配结果。对应 iPhone 的 Managers/MatchManager.swift（球局那部分归球局页）。
 * 快速约球是一个“请求”：提交后挂在后台持续匹配，找到人发提议，所有人确认才成局。
 * 全屏流程只是查看某个请求的窗口，关掉不影响请求。
 *
 * 发现页和这里共用的东西也放在这：卡片上的人（[user]）、选的哪天。
 * 位置、附近范围、附近的球馆和 iPhone 一样在 [location]（features/venues 的 LocationManager）
 */
@Stable
class MatchManager(private val context: ManagerContext, val location: LocationManager = LocationManager(context)) {
    sealed interface Phase {
        data object Idle : Phase
        /** 正在提交请求（搜索动画） */
        data object Submitting : Phase
        data class Failed(val message: String) : Phase
    }

    private val backend get() = context.backend
    val api = MatchApi(context.backend)
    val nearbyApi = NearbyApi(context.backend)

    /**
     * 快速匹配选的球馆（最多 3 家）。“选择球馆”页（features/venues 的 MatchVenuesScreen）直接改这个列表，
     * 名字不要改；草稿里的 courtIds 就是它
     */
    val draftVenueIds = mutableStateListOf<String>()

    private var draftState by mutableStateOf(MatchDraft().applying(TimeSlot.suggestedDefault()))

    /** 快速匹配设置的草稿（球馆跟着 [draftVenueIds]） */
    var draft: MatchDraft
        get() = draftState.copy(courtIds = draftVenueIds.toList())
        set(value) {
            draftState = value
            if (draftVenueIds.toList() != value.courtIds) {
                draftVenueIds.clear()
                draftVenueIds.addAll(value.courtIds)
            }
        }

    var phase by mutableStateOf<Phase>(Phase.Idle)
        private set

    /** 我的约球请求（进行中 + 最近结束） */
    var tickets by mutableStateOf<List<MatchTicket>>(emptyList())
        private set

    /** 请求对应的提议（按提议 ID） */
    var offers by mutableStateOf<Map<String, MatchOffer>>(emptyMap())
        private set

    /** 全屏流程正在查看的请求 */
    var flowTicketId by mutableStateOf<String?>(null)
        private set

    /** 放宽建议：正式后端由服务器匹配，App 里算不出来，一直是空的（和 iPhone 连正式后端时一样） */
    var suggestions by mutableStateOf<List<MatchRelaxation>>(emptyList())
        private set

    var isResponding by mutableStateOf(false)
        private set

    /** 匹配流程的全屏页开着（任何页面跳转都会把它关掉） */
    var isFlowPresented by mutableStateOf(false)

    /** 搜索动画最短展示时间 */
    var minimumSearchMillis = 1800L

    private var submitJob: Job? = null

    // MARK: 卡片、提议里的人

    /** 服务器给过的别人的资料（昵称、等级、性别、头像版本、常打的项目） */
    private val people = mutableStateMapOf<String, User>()

    /** 用户：自己或见过的人 */
    fun user(id: String): User? = backend.currentUser?.takeIf { it.id == id } ?: people[id]

    fun remember(users: List<User>) {
        for (user in users) if (user.id != backend.currentUser?.id) people[user.id] = user
    }

    // MARK: 发现页：选的哪天、要回的邀请

    /** 发现页选的哪天（某天 0 点；null = 任何时间，看附近的人） */
    var discoverDay by mutableStateOf<Long?>(null)

    /** 打开“回应邀请”的半屏（通知点进来的时候设成 true） */
    var showsInvites by mutableStateOf(false)

    /** 附近的人里的邀请（我发的、收到的，还没结束的） */
    var invites by mutableStateOf<List<com.badie.app.models.Room>>(emptyList())
        private set

    /** 别人的空闲时间（卡片、邀请里带的）：约 TA、换个时间时用 */
    private val usualTimes = mutableStateMapOf<String, List<com.badie.app.models.RecurringTimeSlot>>()

    fun usualTimes(userId: String): List<com.badie.app.models.RecurringTimeSlot> = usualTimes[userId].orEmpty()

    fun rememberUsualTimes(userId: String, slots: List<com.badie.app.models.RecurringTimeSlot>) {
        usualTimes[userId] = slots
    }

    /** 重新读邀请 */
    suspend fun loadInvites() {
        if (backend.currentUser == null) return
        try {
            val result = nearbyApi.nearbyInvites(::user)
            remember(result.users)
            result.usualTimes.forEach { (id, slots) -> usualTimes[id] = slots }
            invites = result.rooms
        } catch (_: RemoteError) {
        }
    }

    // MARK: 球馆

    /** 读过的球馆（快速匹配选的、请求里的） */
    private val venues = mutableStateMapOf<String, Venue>()

    fun court(id: String): Venue? = venues[id] ?: location.court(id) ?: location.nearbyCourts.firstOrNull { it.id == id }

    fun courts(ids: List<String>): List<Venue> = ids.mapNotNull(::court)

    /** 没读过的球馆读一下（显示名字和距离） */
    suspend fun loadVenues(ids: List<String>) {
        val missing = ids.filter { court(it) == null }
        if (missing.isEmpty()) return
        try {
            api.venues(missing).forEach { venues[it.id] = it }
        } catch (_: RemoteError) {
        }
    }

    // MARK: 请求

    /** 进行中或暂停的请求（球局页展示） */
    val openTickets: List<MatchTicket> get() = tickets.filter { it.isActive || it.status == MatchTicket.Status.Paused }

    val flowTicket: MatchTicket? get() = flowTicketId?.let { id -> tickets.firstOrNull { it.id == id } }

    /** 请求当前的提议；已成局的请求返回成局的那个提议 */
    fun offer(ticket: MatchTicket): MatchOffer? = ticket.offerId?.let { offers[it] }
        ?: ticket.gameId?.let { gameId -> offers.values.firstOrNull { it.gameId == gameId } }

    private val pools = mutableStateMapOf<String, Pair<Int, Int>>()
    private val poolLoadedAt = HashMap<String, Long>()

    /** 这个请求那天附近有空的人数、其中条件都合适的人数。先给缓存，后台每分钟最多拉一次 */
    fun poolSummary(ticket: MatchTicket): Pair<Int, Int> {
        val now = System.currentTimeMillis()
        if (now - (poolLoadedAt[ticket.id] ?: 0L) > 60_000) {
            poolLoadedAt[ticket.id] = now
            context.scope.launch {
                val pool = try {
                    api.ticketPool(ticket.id)
                } catch (_: RemoteError) {
                    null
                } ?: return@launch
                pools[ticket.id] = pool.available to pool.compatible
            }
        }
        return pools[ticket.id] ?: (0 to 0)
    }

    private class DayPool(val center: Coordinate, val radiusKm: Double, val at: Long, val counts: Map<String, Int>)

    private var poolByDay by mutableStateOf<DayPool?>(null)

    /** 日期条：某天附近有多少人在找。同一片区域 1 分钟内只拉一次 */
    fun availableCount(day: Long): Int {
        val center = location.currentLocation ?: return 0
        val radiusKm = location.preferences.travelRadiusKm
        val cached = poolByDay
        val now = System.currentTimeMillis()
        val stale = cached == null || now - cached.at > 60_000 || cached.radiusKm != radiusKm || cached.center.distanceKm(center) > 2
        if (stale && backend.currentUser != null) {
            val radius = radiusKm
            poolByDay = DayPool(center, radius, now, cached?.counts.orEmpty())
            context.scope.launch {
                val counts = try {
                    api.poolByDay(center, radius)
                } catch (_: RemoteError) {
                    return@launch
                }
                poolByDay = DayPool(center, radius, System.currentTimeMillis(), counts)
            }
        }
        return cached?.counts?.get(MatchApi.dayKey(day)) ?: 0
    }

    /** 重新读请求和提议；announce 时状态有变化就提示（约成了 / 等你确认） */
    suspend fun reloadMatchmaking(announce: Boolean = false) {
        val me = backend.currentUser ?: return
        val remote = try {
            api.myMatchmaking()
        } catch (_: RemoteError) {
            return
        }
        val previous = tickets.associate { it.id to it.status }
        val created = tickets.associate { it.id to it.createdAt }
        val now = System.currentTimeMillis()
        val origin = location.coordinate
        val fresh = remote.map { it.ticket(me.id, origin, created[it.id] ?: now) }.sortedBy { it.slot.startTime }
        val map = HashMap<String, MatchOffer>()
        for (item in remote) {
            val offer = item.offer ?: continue
            remember(offer.players.orEmpty().filter { !it.me }.map { player -> people[player.id]?.copy(nickname = player.nickname, selfReportedRating = player.rating) ?: player.user() })
            val court = offer.venue.venue(court(offer.venue.id))
            venues.putIfAbsent(court.id, court)
            map[offer.id] = offer.offer(com.badie.app.models.GameMode.ofServer(item.mode), item.lastMinute ?: false, court, offers[offer.id]?.createdAt ?: now)
        }
        for (item in remote) item.venues.orEmpty().forEach { place -> if (court(place.id) == null) venues[place.id] = place.venue() }
        tickets = fresh
        offers = map
        if (!announce) return
        for (ticket in fresh) {
            val before = previous[ticket.id] ?: continue
            if (before == ticket.status) continue
            val isShowing = isFlowPresented && flowTicketId == ticket.id
            when (val status = ticket.status) {
                is MatchTicket.Status.Matched ->
                    if (!isShowing) context.appState.showToast(tr("约成了。%@", ticket.slot.formattedFull()), Toast.Style.Success)
                is MatchTicket.Status.Offered ->
                    if (map[status.offerId]?.seat(ticket.userId)?.response == MatchOffer.Response.Pending && !isShowing) {
                        context.appState.showToast(tr("找到搭子了，请确认"), Toast.Style.Success)
                    }
                else -> Unit
            }
        }
    }

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {
        poolByDay = poolByDay?.let { DayPool(it.center, it.radiusKm, 0, it.counts) }
        poolLoadedAt.clear()
        reloadMatchmaking()
    }

    // MARK: 草稿

    /** 准备默认草稿：首次用常打的项目、常用时间，并预选常去球馆（其次最近的球馆），最多 2 家 */
    fun prepareDraft(user: User?, nearbyCourts: List<Venue>, recurring: List<com.badie.app.models.RecurringTimeSlot>, favorites: List<String>) {
        var next = draft
        val mode = user?.preferredMode
        if (mode != null && next.courtIds.isEmpty()) next = next.copy(mode = mode)
        if (!next.validation().isValid) {
            val upcoming = recurring.filter { it.isActive }.mapNotNull { it.nextOccurrence() }.minByOrNull { it.startTime }
            next = next.applying(upcoming ?: TimeSlot.suggestedDefault())
        }
        if (next.courtIds.isEmpty()) {
            val fallback = nearbyCourts.map { it.id }
            next = next.copy(courtIds = (favorites + fallback.filter { it !in favorites }).take(2))
        }
        draft = next
    }

    // MARK: 流程

    /** 提交约球请求并打开流程；[delayMillis] 是等设置页收起来 */
    fun startSearch(delayMillis: Long = 0) {
        if (delayMillis > 0) {
            context.scope.launch {
                delay(delayMillis)
                startSearch()
            }
            return
        }
        val snapshot = draft
        val slot = snapshot.slot() ?: return
        submitJob?.cancel()
        suggestions = emptyList()
        flowTicketId = null
        isFlowPresented = true
        phase = Phase.Submitting
        val minimum = minimumSearchMillis
        submitJob = context.scope.launch {
            val started = System.currentTimeMillis()
            val outcome = runCatching {
                api.submitTicket(snapshot.mode, slot, snapshot.courtIds, snapshot.skillTolerance, snapshot.autoAccept, snapshot.event, snapshot.replacingTicketId)
            }
            val remaining = minimum - (System.currentTimeMillis() - started)
            if (remaining > 0) delay(remaining)
            outcome.onSuccess { id ->
                draft = draft.copy(replacingTicketId = null)
                reloadMatchmaking()
                flowTicketId = id
                phase = if (tickets.any { it.id == id }) Phase.Idle else Phase.Failed(RemoteError.message("bad_response"))
            }.onFailure { error ->
                phase = Phase.Failed((error as? RemoteError)?.message ?: tr("没能发起请求，请重试"))
            }
        }
    }

    /** 修改请求：把它的条件填回设置页，提交时换掉旧请求（新的不合格就保留旧的） */
    fun prepareEdit(ticket: MatchTicket) {
        draft = draft.applying(ticket.slot).copy(
            mode = ticket.mode, courtIds = ticket.courtIds, skillTolerance = ticket.skillTolerance, autoAccept = ticket.autoAccept,
            event = ticket.event, replacingTicketId = ticket.id,
        )
    }

    /** 打开某个请求（球局页卡片、通知） */
    fun openTicket(id: String) {
        submitJob?.cancel()
        flowTicketId = id
        phase = Phase.Idle
        isFlowPresented = true
        context.scope.launch { reloadMatchmaking() }
    }

    /** 关掉流程（请求继续在后台匹配） */
    fun closeFlow() {
        // 还没拿到请求 ID 时关闭：等提交完成后照常保留请求
        if (phase == Phase.Submitting) submitJob = null
        isFlowPresented = false
        phase = Phase.Idle
    }

    /** 接受 / 拒绝当前提议 */
    suspend fun respond(accept: Boolean) {
        val offerId = flowTicket?.offerId ?: return
        isResponding = true
        try {
            api.respondOffer(offerId, accept)
        } catch (error: RemoteError) {
            context.appState.showError(error)
        } finally {
            reloadMatchmaking()
            isResponding = false
        }
    }

    /** 先改本机的（界面马上有反应），再让服务器处理；失败就提示并按服务器的数据恢复 */
    private fun runRemote(update: () -> Unit, operation: suspend () -> Unit) {
        update()
        context.scope.launch {
            try {
                operation()
            } catch (error: RemoteError) {
                context.appState.showError(error)
            }
            reloadMatchmaking()
        }
    }

    private fun setStatus(id: String, status: MatchTicket.Status) {
        tickets = tickets.map { if (it.id == id) it.copy(status = status) else it }
    }

    fun cancelTicket(id: String) {
        runRemote({ setStatus(id, MatchTicket.Status.Cancelled) }) { api.cancelTicket(id) }
        if (flowTicketId == id) closeFlow()
    }

    fun resumeTicket(id: String) {
        runRemote({ setStatus(id, MatchTicket.Status.Searching) }) { api.resumeTicket(id) }
    }

    /** 到点没约成：用同样的条件转成临时局（只找附近此刻在找人的球友） */
    fun retryAsLastMinute(ticket: MatchTicket) {
        submitJob?.cancel()
        phase = Phase.Submitting
        submitJob = context.scope.launch {
            try {
                val id = api.submitTicket(ticket.mode, ticket.slot, ticket.courtIds, ticket.skillTolerance, true, ticket.event)
                reloadMatchmaking()
                flowTicketId = id
                phase = Phase.Idle
            } catch (error: RemoteError) {
                phase = Phase.Failed(error.message)
            }
        }
    }

    init {
        // 定时刷新请求和提议（单元测试、截图里没有 Android 的 Context，不跑）
        if (context.android != null) {
            context.scope.launch {
                try {
                    location.start()
                } catch (_: RemoteError) {
                }
                while (true) {
                    reloadMatchmaking(announce = true)
                    delay(PROCESSING_INTERVAL)
                }
            }
        }
    }

    companion object {
        /** 定时刷新请求和提议的间隔 */
        const val PROCESSING_INTERVAL = 15_000L

        /** 5 / 10 / 20 / 50 公里（用英里的地区：3 / 5 / 10 / 30 英里），存的都是公里 */
        fun radiusChoices(unit: DistanceUnit = DistanceUnit.current): List<Double> {
            val values = if (unit == DistanceUnit.Miles) listOf(3.0, 5.0, 10.0, 30.0) else listOf(5.0, 10.0, 20.0, 50.0)
            return values.map { minOf(UserPreferences.MAXIMUM_TRAVEL_RADIUS, unit.km(it)) }
        }
    }
}
