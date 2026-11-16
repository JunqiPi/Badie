package com.badie.app.features.home

import androidx.core.graphics.scale
import androidx.core.content.edit
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.backend.DayCandidate
import com.badie.app.backend.InviteResult
import com.badie.app.backend.NearbyPlayer
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.PersonBubble
import com.badie.app.design.RoundActionLabel
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.GameMode
import com.badie.app.models.PlayWindow
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.TimeSlot
import com.badie.app.models.isSameDay
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.ceil

/** 一张卡：这天的约球请求，或常在附近的人 */
sealed interface DeckCard {
    val id: String
    val userId: String

    data class Day(val card: DayCandidate) : DeckCard {
        override val id: String get() = "day-${card.id}"
        override val userId: String get() = card.userId
    }

    data class Nearby(val player: NearbyPlayer) : DeckCard {
        override val id: String get() = "nearby-${player.id}"
        override val userId: String get() = player.userId
    }
}

/** 卡片页上的说法和算法（纯函数，便于测试） */
object DayCards {
    /** 从 TA 的开始时间约；今天的话至少半小时后、按半小时对齐 */
    fun inviteStart(card: DayCandidate, now: Long = System.currentTimeMillis()): Long {
        val earliest = now + 30 * 60_000L
        if (card.startsAt >= earliest) return card.startsAt
        return (ceil(earliest / 1_800_000.0) * 1_800_000).toLong()
    }

    /** 卡片页上没有让人选时间，有些通用的错误说法会让人看不懂，换成这里的说法 */
    fun inviteError(error: Throwable): String {
        val code = (error as? RemoteError.Server)?.code ?: return error.message ?: L10n.tr("出了点问题，请重试。")
        return when (code) {
            "overlapping" -> L10n.tr("这个时间你已经有球局或待确认的约球了。")
            "too_soon", "invalid_slot" -> L10n.tr("TA 的时间快到了，来不及约了。")
            "too_many_requests" -> L10n.tr("今天约得太多了，明天再来。")
            "too_many_invites" -> L10n.tr("这天已经在等 3 个人回复了，有人回复再约。")
            "too_many_rooms" -> L10n.tr("你已经开了 3 个局，先关掉一个再约双打。")
            "invalid_event" -> L10n.tr("约混双要先在资料里填性别。")
            else -> error.message
        }
    }

    /** 新拉到的接在后面，不打乱正在看的那张；已经走了的拿掉；滑过的不再加回来 */
    fun <T> merge(current: List<T>, fresh: List<T>, seen: Set<String>, focused: String?, id: (T) -> String): List<T> {
        val freshIds = fresh.map(id).toSet()
        val kept = current.filter { id(it) in freshIds || id(it) == focused }
        val known = kept.map(id).toSet()
        return kept + fresh.filter { id(it) !in known && id(it) !in seen }
    }

    /** 卡片里出现的球馆，按人数排 */
    fun venueCounts(lists: List<List<DayCandidate.Place>>): List<VenueCount> {
        val counts = LinkedHashMap<String, VenueCount>()
        for (list in lists) for (venue in list) {
            val before = counts[venue.id]
            counts[venue.id] = VenueCount(before?.venue ?: venue, (before?.count ?: 0) + 1)
        }
        return counts.values.sortedWith(compareByDescending<VenueCount> { it.count }.thenBy { it.venue.name })
    }
}

/**
 * 发现页中间的一叠卡片，上面一排圆头像是叠里的人（点一个跳到 TA），左右滑，下面 ✕ ♥ ★ 三个按钮。对应 iPhone 的 DayCandidatesView.swift
 * - 选了某天（[day] 不为 null）：这天附近在找人、和我水平对得上的球友。右滑和点爱心一样，直接约。
 * - 附近的人（[day] 为 null）：常在附近打的人，不分日期。右滑是约 TA：选哪天几点和球馆发一个邀请。
 */
@Composable
fun DayCandidatesView(
    day: Long?,
    filter: DayCardFilter,
    onFilter: (DayCardFilter) -> Unit,
    showsFilter: Boolean,
    onShowsFilter: (Boolean) -> Unit,
    reloadToken: Int,
    modifier: Modifier = Modifier,
) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val appState = env.appState
    val context = LocalContext.current
    val density = LocalDensity.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val lobbyOnly = day == null

    var cards by remember { mutableStateOf(emptyList<DayCandidate>()) }
    var seen by remember { mutableStateOf(emptySet<String>()) }
    var isLoading by remember { mutableStateOf(true) }
    var nearby by remember { mutableStateOf(emptyList<NearbyPlayer>()) }
    var nearbySeen by remember { mutableStateOf(emptySet<String>()) }
    // 卡片正在飞走：这段时间不再接受右滑、左滑和按钮（防止连点约两次）
    var leaving by remember { mutableStateOf(false) }
    var focusId by remember { mutableStateOf<String?>(null) }
    var prompt by remember { mutableStateOf<InvitePromptKind?>(null) }
    var promptCard by remember { mutableStateOf<NearbyPlayer?>(null) }
    var promptSlot by remember { mutableStateOf<RecurringTimeSlot?>(null) }
    var composeTarget by remember { mutableStateOf<Pair<NearbyPlayer, RecurringTimeSlot?>?>(null) }
    var showsRadius by remember { mutableStateOf(false) }
    val dragX = remember { Animatable(0f) }
    val dragY = remember { Animatable(0f) }

    val visible = cards.filter { filter.matches(it, manager.user(it.userId)) }
    val visibleNearby = nearby.filter { filter.matches(it, manager.user(it.userId)) }
    val deck: List<DeckCard> = if (lobbyOnly) visibleNearby.map { DeckCard.Nearby(it) } else visible.map { DeckCard.Day(it) }
    val currentIndex = deck.indexOfFirst { it.id == focusId }.takeIf { it >= 0 } ?: 0
    val currentCard = deck.getOrNull(currentIndex)
    // 后面露出来的那张：下一张，到底了是第一张
    val nextCard = if (deck.size > 1) deck[(currentIndex + 1) % deck.size] else null
    // 没开定位：不能按默认城市找人（会约到别的城市）
    val location = env.locationManager
    val needsLocation = location.currentLocation == null

    suspend fun load(showsErrors: Boolean) {
        // 位置还没回来：先不按默认城市找人，位置一到会再调一次
        val center = location.currentLocation ?: return
        val radiusKm = location.preferences.travelRadiusKm
        val later: (suspend () -> Unit) -> Unit = { block -> scope.launch { block() } }
        try {
            if (day == null) {
                val (fresh, users) = manager.nearbyApi.nearbyPlayers(center, radiusKm, manager::user, later)
                manager.remember(users)
                fresh.forEach { manager.rememberUsualTimes(it.userId, it.usualTimes) }
                val focused = (currentCard as? DeckCard.Nearby)?.player?.id
                nearby = DayCards.merge(nearby, fresh, nearbySeen, focused) { it.id }
            } else {
                val (fresh, users) = manager.api.dayCandidates(day, center, radiusKm, known = manager::user, later = later)
                manager.remember(users)
                val focused = (currentCard as? DeckCard.Day)?.card?.id
                cards = DayCards.merge(cards, fresh, seen, focused) { it.id }
            }
        } catch (error: RemoteError) {
            // 附近的人加载失败不提示（和 iPhone 一样）
            if (showsErrors && day != null) appState.showError(error)
        }
        isLoading = false
    }

    LaunchedEffect(needsLocation, location.preferences.travelRadiusKm, reloadToken) { load(showsErrors = true) }
    // 某天的卡片每 30 秒拉一次（在别的标签页时不拉）；附近的人变得慢，只在打开、下拉、开定位、改范围时拉
    LaunchedEffect(day) {
        if (day == null) return@LaunchedEffect
        while (true) {
            delay(30_000)
            if (env.router.selectedTab == MainTab.Home) load(showsErrors = false)
        }
    }

    /** 卡片飞走，动画放完再从叠里拿掉 */
    fun fly(toRight: Boolean, remove: () -> Unit) {
        leaving = true
        scope.launch {
            launch { dragX.animateTo(with(density) { (if (toRight) 600 else -600).dp.toPx() }, AppTheme.Motion.standard()) }
            delay(220)
            remove()
            dragX.snapTo(0f)
            dragY.snapTo(0f)
            leaving = false
        }
    }

    fun following(id: String): String? {
        val index = deck.indexOfFirst { it.id == id }
        if (deck.size <= 1 || index < 0) return null
        return deck[(index + 1) % deck.size].id
    }

    fun next(card: DayCandidate, toRight: Boolean) {
        seen = seen + card.id
        val after = following(DeckCard.Day(card).id)
        fly(toRight) {
            cards = cards.filter { it.id != card.id }
            focusId = after
        }
    }

    fun next(player: NearbyPlayer, toRight: Boolean) {
        nearbySeen = nearbySeen + player.id
        val after = following(DeckCard.Nearby(player).id)
        fly(toRight) {
            nearby = nearby.filter { it.id != player.id }
            focusId = after
        }
    }

    fun resetDrag() {
        scope.launch {
            launch { dragX.animateTo(0f, AppTheme.Motion.standard()) }
            dragY.animateTo(0f, AppTheme.Motion.standard())
        }
    }

    /** 卡片回到中间，弹出“约<昵称>”；发出去了卡片才飞走 */
    fun openCompose(player: NearbyPlayer, slot: RecurringTimeSlot?, after: Long = 0) {
        resetDrag()
        scope.launch {
            // 等上一个半屏收起来，下一个才弹得出来
            if (after > 0) delay(after)
            composeTarget = player to slot
        }
    }

    /** 右滑、点卡片上的空闲时间：约 TA。没打开“在同馆常客里显示我”先问；没卡片照片提醒一次 */
    fun invite(player: NearbyPlayer, slot: RecurringTimeSlot?) {
        val me = appState.currentUser ?: return
        if (leaving) return
        val settings = context.getSharedPreferences("discover", Context.MODE_PRIVATE)
        val kind = when {
            !me.privacy.showsAsRegular -> InvitePromptKind.Visibility
            me.avatar.cardPhotoVersion == null && !settings.getBoolean(PHOTO_ASKED_KEY, false) -> {
                settings.edit { putBoolean(PHOTO_ASKED_KEY, true) }
                InvitePromptKind.Photo
            }
            else -> null
        }
        if (kind == null) {
            openCompose(player, slot)
        } else {
            resetDrag()
            promptCard = player
            promptSlot = slot
            prompt = kind
        }
    }

    fun skip(card: DeckCard) {
        if (leaving) return
        haptics.selection()
        when (card) {
            is DeckCard.Day -> {
                next(card.card, toRight = false)
                scope.launch { runCatching { manager.api.skipCandidate(card.card.ticketId) } }
            }
            is DeckCard.Nearby -> {
                next(card.player, toRight = false)
                scope.launch { runCatching { manager.nearbyApi.skipNearby(card.player.userId) } }
            }
        }
    }

    /** 右滑和点爱心一样：某天的卡直接约，不再让人选；附近的人打开“约<昵称>” */
    fun like(card: DeckCard) {
        if (leaving) return
        val candidate = when (card) {
            is DeckCard.Nearby -> return invite(card.player, null)
            is DeckCard.Day -> card.card
        }
        val venue = filter.venue(candidate) ?: return
        haptics.tap()
        next(candidate, toRight = true)
        val start = DayCards.inviteStart(candidate)
        scope.launch {
            try {
                if (candidate.mode == GameMode.Singles && !candidate.mixed) {
                    manager.api.inviteTicket(candidate.ticketId, venue.id, start)
                    appState.showToast(L10n.tr("已约 TA %@ 在 %@ 打单打，对方确认就成局", com.badie.app.models.DateText.time(start), venue.name), Toast.Style.Success)
                } else {
                    manager.api.inviteDoubles(candidate.ticketId, venue.id, start)
                    appState.showToast(L10n.tr("已开一个双打局并邀请 TA，附近的人可以加入"), Toast.Style.Success)
                }
                haptics.success()
                manager.reloadMatchmaking()
            } catch (error: RemoteError) {
                appState.showToast(DayCards.inviteError(error), Toast.Style.Error)
                // 没约成（网络、撞时间等）：卡片放回最前面，还能再滑；TA 已经约不了的就不放回
                if ((error as? RemoteError.Server)?.code != "not_available") {
                    delay(300)
                    seen = seen - candidate.id
                    cards = listOf(candidate) + cards.filter { it.id != candidate.id }
                    focusId = DeckCard.Day(candidate).id
                }
            }
        }
    }

    /** 没人可约：打开约球设置，日期就是选的这天 */
    fun request() {
        if (day != null) {
            var draft = manager.draft.copy(day = day)
            if (!draft.validation().isValid && isSameDay(day, System.currentTimeMillis())) draft = draft.applying(TimeSlot.suggestedDefault())
            manager.draft = draft
        }
        env.router.isMatchSetupPresented = true
    }

    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        if (result.values.any { it }) {
            location.permissionAnswered(true)
        } else {
            // 以前拒绝过、系统不再弹窗：去系统设置里打开
            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
        }
    }

    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
        when {
            // 已经允许定位，位置还没回来：等一下，不提示“开启定位”
            needsLocation && location.isAuthorized -> Spinner()
            needsLocation -> Centered {
                EmptyStateView(Sym.location, tr("开启定位"), actionTitle = tr("开启定位")) {
                    locationLauncher.launch(com.badie.app.location.LocationProvider.PERMISSIONS)
                }
            }
            isLoading -> Spinner()
            currentCard != null -> {
                PeopleRow(deck, currentCard) { card ->
                    if (!leaving && card.id != currentCard.id) {
                        haptics.selection()
                        resetDrag()
                        focusId = card.id
                    }
                }
                Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen)) {
                    nextCard?.let { behind ->
                        CardFor(behind, filter, Modifier.fillMaxSize().graphicsLayer {
                            scaleX = 0.96f
                            scaleY = 0.96f
                            translationY = 10.dp.toPx()
                        }.clearAndSetSemantics {}, null, null)
                    }
                    val threshold = with(density) { 110.dp.toPx() }
                    val stampAt = with(density) { 40.dp.toPx() }
                    Box(
                        Modifier
                            .fillMaxSize()
                            .graphicsLayer {
                                translationX = dragX.value
                                translationY = dragY.value * 0.2f
                                rotationZ = dragX.value / density.density / 25f
                            }
                            .pointerInput(currentCard.id) {
                                detectDragGestures(
                                    onDragEnd = {
                                        if (!leaving) {
                                            when {
                                                dragX.value > threshold -> like(currentCard)
                                                dragX.value < -threshold -> skip(currentCard)
                                                else -> resetDrag()
                                            }
                                        }
                                    },
                                    onDragCancel = { resetDrag() },
                                ) { change, amount ->
                                    if (leaving) return@detectDragGestures
                                    change.consume()
                                    scope.launch {
                                        dragX.snapTo(dragX.value + amount.x)
                                        dragY.snapTo(dragY.value + amount.y)
                                    }
                                }
                            },
                    ) {
                        CardFor(
                            currentCard, filter, Modifier.fillMaxSize(),
                            onProfile = { appState.showPlayer(currentCard.userId) },
                            onInvite = { slot -> (currentCard as? DeckCard.Nearby)?.let { invite(it.player, slot) } },
                        )
                        if (abs(dragX.value) > stampAt) SwipeStamp(toRight = dragX.value > 0, Modifier.align(if (dragX.value > 0) Alignment.TopStart else Alignment.TopEnd))
                    }
                }
                // ✕ 跳过 / ♥ 约 TA / ★ 加球友（★ 不翻页）
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
                    val skipLabel = tr("跳过")
                    val likeLabel = tr("约 TA")
                    RoundActionLabel(
                        Sym.xmark, AppTheme.colors.surface,
                        Modifier.pressable(enabled = !leaving) { skip(currentCard) }.semantics { contentDescription = skipLabel },
                        foreground = AppTheme.colors.ink,
                    )
                    RoundActionLabel(
                        Sym.heartFill, AppTheme.colors.lime,
                        Modifier.pressable(enabled = !leaving) { like(currentCard) }.semantics { contentDescription = likeLabel }, size = 80.dp,
                    )
                    // 换一张卡，★ 的状态（已申请）跟着重置
                    androidx.compose.runtime.key(currentCard.id) {
                        when (currentCard) {
                            is DeckCard.Day -> FriendStarButton(currentCard.userId)
                            is DeckCard.Nearby -> FriendStarButton(currentCard.userId, currentCard.player.isFriend, currentCard.player.friendRequest)
                        }
                    }
                }
            }
            (if (lobbyOnly) nearby.isNotEmpty() else cards.isNotEmpty()) -> Centered {
                EmptyStateView(Sym.line3HorizontalDecreaseCircle, tr("没有符合筛选的人"), actionTitle = tr("清除筛选")) {
                    onFilter(DayCardFilter())
                }
            }
            else -> Centered {
                // 刷完了 / 这天没人：一句话 + 发个约球请求 / 扩大范围
                val title = if (lobbyOnly) {
                    if (nearbySeen.isEmpty()) tr("附近暂时没有人") else tr("附近的人都看完了")
                } else {
                    if (seen.isEmpty()) tr("这天还没人约") else tr("这天的刷完了")
                }
                Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
                    EmptyStateView(Sym.person2, title)
                    // 字长的语言放不下一行就上下排
                    @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        BrutalButton(tr("发个约球请求"), ::request, size = ButtonSize.Small, fullWidth = false)
                        BrutalButton(tr("扩大范围"), { showsRadius = true }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
                    }
                }
            }
        }
    }

    if (showsFilter) {
        SheetScaffold(onDismiss = { onShowsFilter(false) }, fullHeight = true) {
            val venueCounts = DayCards.venueCounts(if (lobbyOnly) nearby.map { it.venues } else cards.map { it.venues })
            DayCardFilterSheet(
                filter, venueCounts,
                count = { draft ->
                    cards.count { draft.matches(it, manager.user(it.userId)) } + nearby.count { draft.matches(it, manager.user(it.userId)) }
                },
                day = day,
                onApply = { applied ->
                    onFilter(applied)
                    onShowsFilter(false)
                },
                // 筛选里换了一天（换一天整叠卡会重建）；快速约球的日期也跟着变（和原来首页的日期条一样）
                onDay = { newDay ->
                    manager.discoverDay = newDay
                    if (newDay != null) {
                        var draft = manager.draft.copy(day = newDay)
                        if (!draft.validation().isValid && isSameDay(newDay, System.currentTimeMillis())) draft = draft.applying(TimeSlot.suggestedDefault())
                        manager.draft = draft
                    }
                },
            )
        }
    }

    prompt?.let { kind ->
        SheetScaffold(onDismiss = {
            prompt = null
            promptCard = null
            promptSlot = null
        }) {
            InvitePromptSheet(
                kind,
                onConfirm = {
                    prompt = null
                    val player = promptCard ?: return@InvitePromptSheet
                    val slot = promptSlot
                    promptCard = null
                    promptSlot = null
                    when (kind) {
                        InvitePromptKind.Photo -> openCompose(player, slot, after = 450)
                        InvitePromptKind.Visibility -> scope.launch {
                            try {
                                env.appState.backend.updateShowsAsRegular(true)
                                openCompose(player, slot, after = 450)
                            } catch (error: RemoteError) {
                                appState.showError(error)
                            }
                        }
                    }
                },
                onCancel = {
                    prompt = null
                    promptCard = null
                    promptSlot = null
                },
                // 选了照片：先关提醒，裁成卡片的比例上传，再接着约
                onPhoto = { uri ->
                    prompt = null
                    scope.launch {
                        val jpeg = withContext(Dispatchers.IO) { cardJpeg(context, uri) }
                        if (jpeg == null) {
                            appState.showToast(L10n.tr("无法读取这张照片"), Toast.Style.Error)
                        } else {
                            try {
                                env.appState.backend.uploadCardPhoto(jpeg)
                            } catch (error: RemoteError) {
                                appState.showError(error)
                            }
                        }
                        val player = promptCard ?: return@launch
                        val slot = promptSlot
                        promptCard = null
                        promptSlot = null
                        openCompose(player, slot, after = 450)
                    }
                },
            )
        }
    }

    composeTarget?.let { (player, slot) ->
        SheetScaffold(onDismiss = { composeTarget = null }, fullHeight = true) {
            InviteComposeContent(
                player.userId, counterRoom = null, partnerTimes = player.usualTimes, theirVenues = player.venues, prefill = slot,
                initialMode = player.preferredMode, onDismiss = { composeTarget = null },
            ) { result: InviteResult?, window: PlayWindow ->
                // 邀请发出去了：卡片飞走，说一声还能约几个
                next(player, toRight = true)
                appState.showToast(sentText(manager.user(player.userId)?.nickname ?: "", result, window), Toast.Style.Success)
            }
        }
    }

    if (showsRadius) {
        SheetScaffold(onDismiss = { showsRadius = false }) { com.badie.app.features.venues.TravelRadiusSheet { showsRadius = false } }
    }
}

private const val PHOTO_ASKED_KEY = "BadieNearbyPhotoAsked"

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.Spinner() {
    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = AppTheme.colors.ink) }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.Centered(content: @Composable () -> Unit) {
    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { content() }
}

/** 叠里的人，一人一个圆头像（同一个人有几张卡只放一个）；正在看的那个加一圈柠檬绿 */
@Composable
private fun PeopleRow(deck: List<DeckCard>, current: DeckCard, onJump: (DeckCard) -> Unit) {
    val manager = LocalEnv.current.matchManager
    val people = deck.distinctBy { it.userId }
    val state = rememberLazyListState()
    LaunchedEffect(current.userId) {
        val index = people.indexOfFirst { it.userId == current.userId }
        if (index >= 0) state.animateScrollToItem(maxOf(0, index - 2))
    }
    LazyRow(
        Modifier.fillMaxWidth(),
        state = state,
        contentPadding = PaddingValues(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.xxs),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        items(people, key = { it.userId }) { card ->
            manager.user(card.userId)?.let { user ->
                PersonBubble(user, isCurrent = card.userId == current.userId, size = 44.dp) { onJump(card) }
            }
        }
    }
}

@Composable
private fun CardFor(card: DeckCard, filter: DayCardFilter, modifier: Modifier, onProfile: (() -> Unit)?, onInvite: ((RecurringTimeSlot) -> Unit)?) {
    val manager = LocalEnv.current.matchManager
    when (card) {
        is DeckCard.Nearby -> NearbyCardView(
            manager.user(card.userId), card.player, modifier, venue = card.player.venues.firstOrNull { it.id in filter.venueIds },
            onProfile = onProfile, onInvite = onInvite,
        )
        is DeckCard.Day -> {
            val candidate = card.card
            // 约在哪家的那家排第一
            val first = filter.venue(candidate)
            val venues = if (first == null) candidate.venues else listOf(first) + candidate.venues.filter { it.id != first.id }
            DayCardView(
                manager.user(card.userId), if (candidate.mixed) tr("混双") else candidate.mode.title, candidate.startsAt, candidate.endsAt,
                venues.map { it.name }, candidate.recentNoShows, modifier, onProfile,
            )
        }
    }
}

@Composable
private fun SwipeStamp(toRight: Boolean, modifier: Modifier) {
    val colors = AppTheme.colors
    Text(
        if (toRight) tr("约 TA") else tr("跳过"), style = AppTheme.Typography.title3, color = if (toRight) colors.onAccent else colors.ink,
        modifier = modifier
            .padding(AppTheme.Spacing.lg)
            .rotate(if (toRight) -8f else 8f)
            .sticker(if (toRight) colors.lime else colors.surface, radius = AppTheme.Radius.sm, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.md, vertical = AppTheme.Spacing.xs),
    )
}

/** 选的照片裁成卡片背景：中间 3:4，600×800 的 JPEG（iPhone 让人自己拖动裁剪，这里先按中间裁） */
internal fun cardJpeg(context: Context, uri: Uri): ByteArray? {
    val resolver = context.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= 600 && bounds.outHeight / (sample * 2) >= 800) sample *= 2
    val bitmap = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return null
    val ratio = 3f / 4f
    val (width, height) = if (bitmap.width.toFloat() / bitmap.height > ratio) {
        (bitmap.height * ratio).toInt() to bitmap.height
    } else {
        bitmap.width to (bitmap.width / ratio).toInt()
    }
    val cropped = Bitmap.createBitmap(bitmap, (bitmap.width - width) / 2, (bitmap.height - height) / 2, width, height)
    val scaled = cropped.scale(600, 800)
    return ByteArrayOutputStream().use { out ->
        scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
        out.toByteArray()
    }
}
