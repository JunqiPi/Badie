package com.badie.app.features.games

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.ArrowButtonLabel
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.sticker
import com.badie.app.features.rooms.InviteRoomCard
import com.badie.app.features.rooms.PublicRoomCard
import com.badie.app.l10n.tr
import com.badie.app.models.Coordinate
import com.badie.app.models.Game
import com.badie.app.models.RoomVisibility
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route

// 球局页（第二个标签）和历史球局。对应 iPhone 的 Features/Games/GamesView.swift
// 入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面）

private enum class Segment { Upcoming, Past }

@Composable
fun GamesScreen() {
    val env = LocalEnv.current
    val rooms = env.roomManager
    val book = rooms.book
    val router = env.router
    val me = env.appState.currentUser?.id
    var segment by rememberSaveable { mutableStateOf(Segment.Upcoming) }
    LaunchedEffect(me) {
        try {
            rooms.refresh()
        } catch (_: RemoteError) {
        }
    }
    RoomNotice()
    RefreshEverything(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.tabBarClearance),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            LargeTitleHeader(tr("球局")) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    IconButton(Sym.flag2Crossed, tr("挑战")) { router.open(Route.Challenges) }
                    IconButton(Sym.clockArrowCirclepath, tr("历史球局")) { router.open(Route.GameHistory) }
                }
            }
            TodoPills()
            book.nextGame?.let { game ->
                GameTicketCard(
                    game, book.players(game), me, compact = true,
                    modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen).pressable(scale = 0.98f) { router.open(Route.Game(game.id)) },
                )
            }
            // TODO：约球请求（“约球请求 · N 个进行中”）在 MatchManager 里，等快速匹配那边搬好再接上
            MyRoomsSection()
            QuickMatchCard(Modifier.padding(horizontal = AppTheme.Spacing.screen))
            QuickActions(Modifier.padding(horizontal = AppTheme.Spacing.screen))
            PublicGamesSection()
            // TODO：我的球群、我报名的固定局（GroupManager）、本周排行（排行榜）、同馆常客（FriendManager）、附近球馆小地图（要地图的 key），
            // 等这几块搬好再接上；顺序照 iPhone：球局入口 → 附近球局 → 球群 → 固定局 → 本周排行 → 同馆常客 → 列表 → 小地图
            Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                SegmentedSticker(
                    Segment.entries, segment, { segment = it },
                    badge = { if (it == Segment.Upcoming) book.upcomingGames.size else 0 },
                ) { if (it == Segment.Upcoming) tr("即将开始") else tr("已结束") }
                GamesList(segment)
            }
        }
    }
}

/** 房间被关掉、被移出时的提示 */
@Composable
internal fun RoomNotice() {
    val env = LocalEnv.current
    val notice = env.roomManager.notice
    LaunchedEffect(notice) {
        if (notice != null) {
            env.appState.showToast(notice)
            env.roomManager.notice = null
        }
    }
}

// MARK: 待办

@Composable
private fun TodoPills() {
    val env = LocalEnv.current
    val pending = env.surveyManager.pendingSurveys
    // TODO：别人发给我、还没回应的挑战（挑战 N）归排行榜那边，搬好后加在前面
    if (pending.isEmpty()) return
    Flow(Modifier.padding(horizontal = AppTheme.Spacing.screen)) {
        CountPill(Sym.starBubbleFill, tr("待评价"), pending.size) { env.router.open(Route.Surveys) }
        RulesButton(tr("待评价"), listOf(tr("打完 48 小时内可以评价")))
    }
}

// MARK: 我的房间

@Composable
private fun MyRoomsSection() {
    val env = LocalEnv.current
    val rooms = env.roomManager.myRooms
    val me = env.appState.currentUser?.id
    if (rooms.isEmpty()) return
    Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("我的房间"), detail = tr("%lld 个进行中", rooms.size))
        for (room in rooms) {
            val open = Modifier.pressable(scale = 0.98f) { env.router.open(Route.Room(room.id)) }
            val invite = room.invite
            if (invite != null) {
                // 附近的人里的邀请：和谁、大概什么时候、轮到谁
                InviteRoomCard(room, me, env.roomManager.book.user(invite.other(me)), open)
            } else {
                androidx.compose.foundation.layout.Box(open) {
                    PublicRoomCard(room, room.court?.let { distanceText(it.location) }, me, width = null)
                    if (room.visibility == RoomVisibility.PrivateRoom) {
                        TagPill(
                            tr("私密 · %@", room.code), icon = Sym.lockFill, fill = AppTheme.colors.butter,
                            modifier = Modifier.align(Alignment.TopEnd).offset((-12).dp, (-10).dp),
                        )
                    }
                }
            }
        }
    }
}

/** 到球馆的距离：只有资料里有位置时才写（安卓的定位在 LocationManager 那边，还没搬） */
@Composable
internal fun distanceText(location: Coordinate): String? {
    val here = LocalEnv.current.appState.currentUser?.location ?: return null
    return com.badie.app.models.DistanceFormatter.string(location.distanceKm(here))
}

// MARK: 快速约球

/**
 * 快速约球卡。iPhone 上四个摘要（模式、时间、几个球馆、水平）来自 MatchManager 的草稿；
 * 安卓的 MatchManager 归快速匹配那边，现在只有选的球馆，其余三项等那边搬好再接（TODO）
 */
@Composable
private fun QuickMatchCard(modifier: Modifier = Modifier) {
    val env = LocalEnv.current
    val router = env.router
    val ink = AppTheme.colors.onAccent
    Column(modifier.card(AppTheme.colors.lime, padding = AppTheme.Spacing.xl), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("快速约球"), style = AppTheme.Typography.title2, color = ink, modifier = Modifier.weight(1f).semantics { heading() })
            Text(
                tr("调整"), style = AppTheme.Typography.footnoteBold, color = ink,
                modifier = Modifier.pressable { router.isMatchSetupPresented = true }.padding(vertical = AppTheme.Spacing.sm),
            )
        }
        Flow(Modifier.pressable(scale = 1f) { router.isMatchSetupPresented = true }, spacing = 6.dp) {
            SummaryChip(tr("%lld 个球馆", env.matchManager.draftVenueIds.size), Sym.mappin)
        }
        // 草稿还不能直接搜（没有时间这些）：和 iPhone 一样先打开设置页
        BrutalButton(onClick = { router.isMatchSetupPresented = true }, kind = ButtonKind.Inverse) {
            ArrowButtonLabel(tr("开始匹配"))
        }
    }
}

@Composable
private fun SummaryChip(text: String, icon: SymbolId) {
    val ink = Color(0xFF17140F)
    Row(
        Modifier
            .sticker(Color.White, radius = 14.dp, shadow = AppTheme.Elevation.none, stroke = ink, strokeWidth = 1.5.dp)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Symbol(icon, size = 10, tint = ink)
        Text(text, style = AppTheme.Typography.footnoteBold, color = ink, maxLines = 1)
    }
}

// MARK: 三个入口

@Composable
private fun QuickActions(modifier: Modifier = Modifier) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    // 英文等长一点的语言排两行；三块按最高的那块对齐
    Row(modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        QuickAction(Sym.sportscourtFill, tr("发起球局"), colors.peach, Modifier.weight(1f)) { env.router.open(Route.CreateRoom()) }
        QuickAction(Sym.person3Fill, tr("球群"), colors.sky, Modifier.weight(1f)) { env.router.open(Route.Groups) }
        QuickAction(Sym.number, tr("房间码"), colors.lavender, Modifier.weight(1f)) { env.router.open(Route.JoinRoom()) }
    }
}

@Composable
private fun QuickAction(icon: SymbolId, title: String, tint: Color, modifier: Modifier, onClick: () -> Unit) {
    val ink = AppTheme.colors.onAccent
    Column(
        modifier
            .fillMaxHeight()
            .pressable(onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = title }
            .sticker(tint, radius = AppTheme.Radius.lg)
            .padding(horizontal = AppTheme.Spacing.md, vertical = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(icon, size = 20, tint = ink)
        Text(title, style = AppTheme.Typography.headline, color = ink, maxLines = 2)
    }
}

// MARK: 附近球局

@Composable
private fun PublicGamesSection() {
    val env = LocalEnv.current
    val rooms = env.roomManager.publicRooms
    val me = env.appState.currentUser?.id
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("附近球局"), Modifier.padding(horizontal = AppTheme.Spacing.screen), actionTitle = tr("全部")) {
            env.router.open(Route.PublicGames)
        }
        if (rooms.isEmpty()) {
            EmptyStateView(
                Sym.sportscourt, tr("附近暂时没有公开球局"), Modifier.padding(horizontal = AppTheme.Spacing.screen).card(),
                tint = AppTheme.colors.peach, actionTitle = tr("发起球局"),
            ) { env.router.open(Route.CreateRoom(), com.badie.app.shell.MainTab.Games) }
        } else {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                for (room in rooms) {
                    PublicRoomCard(
                        room, room.court?.let { distanceText(it.location) }, me,
                        Modifier.pressable(scale = 0.98f) { env.router.open(Route.Room(room.id)) },
                    )
                }
            }
        }
    }
}

// MARK: 列表

@Composable
private fun GamesList(segment: Segment) {
    val env = LocalEnv.current
    val book = env.roomManager.book
    // 下一场已经在最上面了，这里不再列
    val games = if (segment == Segment.Upcoming) book.upcomingGames.drop(1) else book.pastGames.take(20)
    when {
        games.isEmpty() && segment == Segment.Upcoming && book.nextGame != null -> Unit
        games.isEmpty() -> EmptyStateView(
            if (segment == Segment.Upcoming) Sym.calendarBadgePlus else Sym.clock,
            if (segment == Segment.Upcoming) tr("还没有约好的球局") else tr("还没有打过的球局"),
            Modifier.card(), tint = AppTheme.colors.sky,
            actionTitle = if (segment == Segment.Upcoming) tr("快速匹配") else null,
            action = if (segment == Segment.Upcoming) ({ env.router.isMatchSetupPresented = true }) else null,
        )
        else -> Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            for (game in games) GameRow(game)
        }
    }
}

@Composable
private fun GameRow(game: Game) {
    val env = LocalEnv.current
    val book = env.roomManager.book
    GameRowCard(
        game, book.players(game), env.appState.currentUser?.id,
        Modifier.pressable(scale = 0.98f) { env.router.open(Route.Game(game.id)) },
        pendingSurveyCount = book.pending(game.id).size,
    )
}

// MARK: - 历史球局

@Composable
fun GameHistoryScreen() {
    val env = LocalEnv.current
    val book = env.roomManager.book
    val me = env.appState.currentUser
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("历史球局"), onBack = { env.router.pop() })
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                StatTile("${me?.totalGames ?: 0}", tr("总场次"), Modifier.weight(1f))
                StatTile("${me?.wins ?: 0}", tr("胜场"), Modifier.weight(1f))
                StatTile("${me?.attendance?.reliabilityPercentage ?: 100}%", tr("履约率"), Modifier.weight(1f))
            }
            if (book.pastGames.isEmpty()) EmptyStateView(Sym.clock, tr("还没有历史球局"))
            for (game in book.pastGames) GameRow(game)
        }
    }
}
