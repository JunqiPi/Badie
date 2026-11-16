package com.badie.app.features.home

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import com.badie.app.design.AppTheme
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.features.groups.GroupCard
import com.badie.app.features.matching.MatchManager
import com.badie.app.l10n.tr
import com.badie.app.remote.RemoteError
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.isSameDay
import com.badie.app.models.startOfDay
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import kotlinx.coroutines.launch

/**
 * 第一个标签“发现”：一张大卡片，左滑跳过、右滑约。对应 iPhone 的 Features/Home/DiscoverView.swift。
 * 最上面一行左边是附近范围（点开选 5 / 10 / 20 / 50 公里），右边是球馆、通知、筛选（选哪天也在筛选里）；
 * 下面一排圆头像是这叠卡里的人。谁约了我、谁想加我这类待办在通知里
 */
@Composable
fun DiscoverScreen() {
    val env = LocalEnv.current
    val manager = env.matchManager
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var filter by remember { mutableStateOf(DayCardFilter.load(context)) }
    var showsFilter by remember { mutableStateOf(false) }
    // 看球友还是球群（记住上次选的）；看球群时的筛选只有“显示：球友 / 球群”
    var mode by remember { mutableStateOf(DiscoverMode.load(context)) }
    var showsGroupFilter by remember { mutableStateOf(false) }
    fun switchMode(next: DiscoverMode) {
        mode = next
        next.save(context)
    }
    // 下拉刷新时加一，卡片跟着重新拉
    var reloadToken by remember { mutableIntStateOf(0) }
    // 点了“好”之后要打开的球局
    var acceptedGameId by remember { mutableStateOf<String?>(null) }
    var counterRoom by remember { mutableStateOf<com.badie.app.models.Room?>(null) }
    val me = env.appState.currentUser?.id
    // 选的那天（已经过去的天当作“任何时间”）
    val selectedDay = manager.discoverDay?.takeIf { it >= startOfDay(System.currentTimeMillis()) }?.let { startOfDay(it) }
    // 轮到我回的邀请（从通知打开的半屏里一个一个回）
    val answering = manager.invites.filter { it.invite?.awaitingId == me && it.status.isOpen }

    val location = env.locationManager
    LaunchedEffect(Unit) {
        if (location.currentLocation == null) {
            try {
                location.start()
            } catch (_: RemoteError) {
            }
        }
        manager.loadInvites()
    }
    LaunchedEffect(location.nearbyCourts) {
        val recurring = com.badie.app.backend.ProfileApi.of(env.appState.backend, context).recurringSlots()
        manager.prepareDraft(env.appState.currentUser, location.nearbyCourts, recurring, location.favoriteCourts.map { it.id })
    }
    LaunchedEffect(manager.showsInvites) {
        if (manager.showsInvites) {
            manager.loadInvites()
            if (manager.invites.none { it.invite?.awaitingId == me && it.status.isOpen }) manager.showsInvites = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        // 只有上面这部分能下拉刷新：卡片要左右滑，不放进滚动视图
        RefreshEverything(extra = {
            reloadToken += 1
            manager.loadInvites()
        }) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                    .padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.sm),
            ) {
                val badge = if (mode == DiscoverMode.Groups) 1 else filter.activeCount + if (selectedDay == null) 0 else 1
                Header(selectedDay, badge) { if (mode == DiscoverMode.Groups) showsGroupFilter = true else showsFilter = true }
            }
        }
        if (mode == DiscoverMode.Groups) {
            NearbyGroupsList(Modifier.weight(1f))
        } else key(selectedDay ?: -1L) {
            DayCandidatesView(
                selectedDay, filter,
                onFilter = { next ->
                    filter = next
                    next.save(context)
                },
                showsFilter = showsFilter, onShowsFilter = { showsFilter = it }, reloadToken = reloadToken,
                // ✕ ♥ ★ 停在标签栏上面（中间的“+”比标签栏高出一截）
                modifier = Modifier.weight(1f).padding(bottom = AppTheme.Spacing.tabBarClearance - AppTheme.Spacing.md),
                onShowGroups = { switchMode(DiscoverMode.Groups) },
            )
        }
    }

    if (showsGroupFilter) {
        SheetScaffold(onDismiss = { showsGroupFilter = false }) {
            GroupsFilterSheet {
                showsGroupFilter = false
                switchMode(DiscoverMode.Players)
            }
        }
    }

    if (manager.showsInvites && answering.isNotEmpty()) {
        SheetScaffold(onDismiss = {
            manager.showsInvites = false
            // 点了好：半屏收起后打开球局
            acceptedGameId?.let { id ->
                acceptedGameId = null
                env.router.open(Route.Game(id), MainTab.Games)
            }
            scope.launch { manager.loadInvites() }
        }) {
            InviteAnswerSheet(
                answering,
                onAnswered = { _, gameId -> if (gameId != null) acceptedGameId = gameId },
                onCounter = { counterRoom = it },
                onDismiss = {
                    manager.showsInvites = false
                    acceptedGameId?.let { id ->
                        acceptedGameId = null
                        env.router.open(Route.Game(id), MainTab.Games)
                    }
                    scope.launch { manager.loadInvites() }
                },
            )
        }
    }
    counterRoom?.let { room ->
        val other = room.invite?.other(me) ?: ""
        SheetScaffold(onDismiss = { counterRoom = null }, fullHeight = true) {
            InviteComposeContent(
                other, counterRoom = room, partnerTimes = manager.usualTimes(other), theirVenues = emptyList(), prefill = null,
                initialMode = room.mode, onDismiss = { counterRoom = null },
            ) { _, _ -> env.appState.showToast(com.badie.app.l10n.L10n.tr("已发给 TA"), com.badie.app.design.Toast.Style.Success) }
        }
    }
}

/** 左边“附近 / 10 公里内 ▾”（点开选范围），右边球馆、通知、筛选 */
@Composable
private fun Header(selectedDay: Long?, filterCount: Int, onFilter: () -> Unit) {
    val env = LocalEnv.current
    val location = env.locationManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var menu by remember { mutableStateOf(false) }
    val radiusText = location.radiusText
    val radiusLabel = tr("附近范围")
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Box(Modifier.weight(1f)) {
            Column(
                Modifier.fillMaxWidth().pressable(scale = 1f) { menu = true }.clearAndSetSemantics {
                    contentDescription = radiusLabel
                    stateDescription = radiusText
                },
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    selectedDay?.let { tr("附近 · %@", dayTitle(it)) } ?: tr("附近"),
                    style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(radiusText, style = AppTheme.Typography.title2, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Symbol(Sym.chevronDown, size = 13, tint = colors.ink)
                }
            }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                for (km in MatchManager.radiusChoices()) {
                    DropdownMenuItem(
                        text = { Text(DistanceFormatter.radius(km), style = AppTheme.Typography.bodyBold) },
                        onClick = {
                            haptics.selection()
                            location.updateTravelRadius(km)
                            menu = false
                        },
                        // 现在的范围不在几个选项里（以前用滑块选的）时，菜单里不打勾
                        trailingIcon = if (km == location.preferences.travelRadiusKm) ({ Symbol(Sym.checkmark, size = 14) }) else null,
                    )
                }
            }
        }
        IconButton(Sym.building2, tr("附近球馆")) { env.router.open(Route.Courts) }
        IconButton(Sym.bellFill, tr("通知"), badge = env.inboxManager.unreadCount) { env.router.open(Route.Notifications) }
        IconButton(Sym.line3HorizontalDecrease, tr("筛选"), badge = filterCount, onClick = onFilter)
    }
}

@Composable
private fun dayTitle(day: Long): String {
    val now = System.currentTimeMillis()
    if (isSameDay(day, now)) return tr("今天")
    if (isSameDay(day, com.badie.app.models.addingDays(now, 1))) return tr("明天")
    return DateText.weekday(day)
}

/** 发现页看球友（原来的卡片）还是球群（附近的球群，近的在前）。记住上次选的 */
enum class DiscoverMode(val rawValue: String) {
    Players("players"),
    Groups("groups");

    fun save(context: Context) {
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE).edit { putString(KEY, rawValue) }
    }

    companion object {
        private const val STORE = "discover"
        private const val KEY = "discoverMode"

        fun load(context: Context): DiscoverMode {
            val raw = context.getSharedPreferences(STORE, Context.MODE_PRIVATE).getString(KEY, null)
            return entries.firstOrNull { it.rawValue == raw } ?: Players
        }
    }
}

// MARK: - 球群：附近的球群，近的在前

/** 看球群时点筛选：只有“显示：球友 / 球群”，选球友就回到卡片 */
@Composable
private fun GroupsFilterSheet(onPlayers: () -> Unit) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Text(tr("筛选"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.semantics { heading() })
        Text(tr("显示"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.semantics { heading() })
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            ChoiceChip(tr("球友"), isSelected = false, onClick = onPlayers)
            ChoiceChip(tr("球群"), isSelected = true) {}
        }
    }
}

@Composable
private fun NearbyGroupsList(modifier: Modifier = Modifier) {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    LaunchedEffect(groupManager.radiusKm, groupManager.location.currentLocation) {
        try {
            groupManager.loadNearby(groupManager.currentCenter(), groupManager.radiusKm)
        } catch (_: RemoteError) {
        }
    }
    val groups = groupManager.nearestGroups()
    val me = groupManager.currentUserId
    RefreshEverything(modifier.fillMaxWidth(), extra = { groupManager.loadNearby(groupManager.currentCenter(), groupManager.radiusKm) }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen)
                .padding(top = AppTheme.Spacing.xs, bottom = AppTheme.Spacing.tabBarClearance),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            if (groups.isEmpty()) {
                EmptyStateView(
                    Sym.person3, tr("附近还没有球群"), Modifier.card(), tint = AppTheme.colors.lavender, actionTitle = tr("建群"),
                ) { env.router.open(Route.CreateGroup()) }
            } else {
                groups.forEach { group ->
                    GroupCard(
                        group, groupManager.venue(group), groupManager.activity(group.id),
                        Modifier.pressable(scale = 0.98f) { env.router.open(Route.Group(group.id)) },
                        status = if (me != null && group.isPending(me)) tr("待审核") else null,
                    )
                }
            }
        }
    }
}
