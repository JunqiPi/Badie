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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.ButtonSize
import com.badie.app.design.IconTile
import com.badie.app.design.LevelBadge
import com.badie.app.design.rememberHaptics
import com.badie.app.features.groups.GroupCard
import com.badie.app.features.groups.SessionRow
import com.badie.app.features.matching.MatchRequest
import com.badie.app.features.matching.TicketStatusCard
import com.badie.app.features.rankings.RankingManager
import com.badie.app.features.rankings.quietly
import com.badie.app.features.rankings.rememberRankingManager
import com.badie.app.features.venues.VenueSearch
import com.badie.app.models.ChallengeStatus
import com.badie.app.models.DateText
import com.badie.app.models.Rankings
import com.badie.app.models.isSameDay
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import kotlinx.coroutines.launch
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
    val rankings = rememberRankingManager()
    LaunchedEffect(me) {
        try {
            rooms.refresh()
        } catch (_: RemoteError) {
        }
    }
    LaunchedEffect(me) {
        launch { quietly { env.friendManager.refreshRegulars() } }
        launch { quietly { rankings.refreshChallenges() } }
        launch { quietly { rankings.loadWeekly(Rankings.week(System.currentTimeMillis()), country = false) } }
    }
    RoomNotice()
    RefreshEverything(Modifier.fillMaxSize(), extra = {
        quietly { rankings.refreshChallenges() }
        quietly { rankings.loadWeekly(Rankings.week(System.currentTimeMillis()), country = false, force = true) }
    }) {
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
            TodoPills(rankings)
            book.nextGame?.let { game ->
                GameTicketCard(
                    game, book.players(game), me, compact = true,
                    modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen).pressable(scale = 0.98f) { router.open(Route.Game(game.id)) },
                )
            }
            TicketsSection()
            MyRoomsSection()
            QuickMatchCard(Modifier.padding(horizontal = AppTheme.Spacing.screen))
            QuickActions(Modifier.padding(horizontal = AppTheme.Spacing.screen))
            PublicGamesSection()
            MyGroupsSection()
            MySessionsSection()
            WeeklyCard(rankings, Modifier.padding(horizontal = AppTheme.Spacing.screen))
            RegularsSection()
            // iPhone 列表下面还有附近球馆的小地图：要等 Google 地图的 key
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
private fun TodoPills(rankings: RankingManager) {
    val env = LocalEnv.current
    val pending = env.surveyManager.pendingSurveys
    // 别人发给我、还没回应的挑战
    val me = env.appState.currentUser?.id
    val challenges = rankings.challenges().count { it.targetId == me && it.status == ChallengeStatus.Pending }
    if (pending.isEmpty() && challenges == 0) return
    Flow(Modifier.padding(horizontal = AppTheme.Spacing.screen)) {
        if (challenges > 0) CountPill(Sym.flag2CrossedFill, tr("挑战"), challenges) { env.router.open(Route.Challenges) }
        if (pending.isNotEmpty()) {
            CountPill(Sym.starBubbleFill, tr("待评价"), pending.size) { env.router.open(Route.Surveys) }
            RulesButton(tr("待评价"), listOf(tr("打完 48 小时内可以评价")))
        }
    }
}

// MARK: 约球请求

@Composable
private fun TicketsSection() {
    val manager = LocalEnv.current.matchManager
    val open = manager.openTickets
    if (open.isEmpty()) return
    Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("约球请求"), detail = tr("%lld 个进行中", open.size))
        for (ticket in open) {
            TicketStatusCard(ticket, manager.offer(ticket)) { manager.openTicket(ticket.id) }
        }
    }
}

// MARK: 球群

@Composable
private fun MyGroupsSection() {
    val env = LocalEnv.current
    val groups = env.groupManager
    val mine = groups.myGroups
    if (mine.isEmpty()) return
    Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("我的球群"), detail = "${mine.size}")
        for (group in mine) {
            GroupCard(
                group, groups.venue(group), groups.activity(group.id),
                Modifier.pressable(scale = 0.98f) { env.router.open(Route.Group(group.id)) },
            )
        }
    }
}

@Composable
private fun MySessionsSection() {
    val env = LocalEnv.current
    val groups = env.groupManager
    val sessions = groups.mySessions
    if (sessions.isEmpty()) return
    val colors = AppTheme.colors
    Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("我报名的固定局"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(tr("我报名的固定局"), listOf(tr("开场前 2 小时内退出算临时取消")))
        }
        for (session in sessions) {
            val group = groups.group(session.groupId) ?: continue
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    Modifier.pressable { env.router.open(Route.Group(group.id)) },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Symbol(Sym.person3Fill, size = 12, tint = colors.inkSecondary)
                    Text(group.name, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1)
                }
                SessionRow(session, env.appState.currentUser?.id ?: "") { env.router.open(Route.Group(group.id)) }
            }
        }
    }
}

// MARK: 本周排行

@Composable
private fun WeeklyCard(rankings: RankingManager, modifier: Modifier = Modifier) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val week = Rankings.week(System.currentTimeMillis())
    // 榜还没拉回来时不显示（不先写“还差几场”）
    if (env.appState.currentUser == null || rankings.isWeeklyLoading(week, country = false)) return
    val standing = rankings.standing(week, country = false, rankings.weeklyLeaderboard(week, country = false)) ?: return
    // 还没达到上榜门槛：只说差几场，门槛写在排行榜的规则里
    val text = if (standing.absenceReason == null && standing.rank == null && !standing.isQualified && standing.isCurrentWeek) {
        tr("差 %lld 场上榜", standing.gamesNeeded)
    } else {
        standing.summary
    }
    Row(
        modifier.fillMaxWidth().pressable(scale = 0.98f) { env.router.open(Route.Leaderboard) }
            .sticker(colors.surface, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.lg)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.trophyFill, fill = colors.butter, size = 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr("本周排行"), style = AppTheme.Typography.overline, color = colors.inkSecondary)
            Text(text, style = AppTheme.Typography.headline, color = colors.ink)
        }
        Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
    }
}

// MARK: 同馆常客

/** 同馆常客：和我常去同一家球馆、并且本人开启了展示的球友（不按距离、不显示在线状态） */
@Composable
private fun RegularsSection() {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val location = env.locationManager
    val regulars = env.friendManager.venueRegulars(limit = 12) { location.court(it) }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(
            Modifier.padding(horizontal = AppTheme.Spacing.screen),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
        ) {
            Text(tr("同馆常客"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
            if (regulars.isNotEmpty()) Text(tr("%lld 人", regulars.size), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            RulesButton(
                tr("同馆常客"),
                listOf(tr("设置常去球馆后，这里显示也常去那里的球友"), tr("对方开启了展示才会出现"), tr("不按距离排，也不显示在线状态")),
            )
        }
        when {
            location.favoriteCourtIds.isEmpty() -> BrutalButton(
                onClick = { env.router.open(Route.Courts) }, Modifier.padding(horizontal = AppTheme.Spacing.screen),
                kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false,
            ) {
                Symbol(Sym.heartFill, size = 13)
                Text(tr("设置常去球馆"))
            }
            regulars.isEmpty() -> Text(
                tr("暂时没有常客"), style = AppTheme.Typography.footnote, color = colors.inkSecondary,
                modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen),
            )
            else -> Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.Top,
            ) {
                for ((user, venue) in regulars) {
                    val acronym = VenueSearch.acronym(venue.name).uppercase()
                    val label = tr("%@，%@，常去%@", user.nickname, user.displayLevelText, venue.name)
                    Column(
                        Modifier.width(72.dp).pressable { env.appState.showPlayer(user.id) }.clearAndSetSemantics { contentDescription = label },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        AvatarView(user, size = 58.dp)
                        Text(user.nickname, style = AppTheme.Typography.footnoteBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        LevelBadge(user.displayTier, showsName = false, compact = true)
                        Text(
                            acronym.ifEmpty { venue.name }, style = AppTheme.Typography.caption, color = colors.inkSecondary,
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
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

/** 到球馆的距离：从当前位置算（没开定位按默认城市，和 iPhone 的 locationManager.coordinate 一样） */
@Composable
internal fun distanceText(location: Coordinate): String? {
    val here = LocalEnv.current.locationManager.coordinate
    return com.badie.app.models.DistanceFormatter.string(location.distanceKm(here))
}

// MARK: 快速约球

/** 快速约球卡：四个摘要（模式、时间、几个球馆、水平）来自 MatchManager 的草稿 */
@Composable
private fun QuickMatchCard(modifier: Modifier = Modifier) {
    val env = LocalEnv.current
    val router = env.router
    val haptics = rememberHaptics()
    val ink = AppTheme.colors.onAccent
    val draft = env.matchManager.draft
    val timeText = draft.slot()?.let { slot ->
        val day = if (isSameDay(slot.startTime, System.currentTimeMillis())) tr("今天") else DateText.weekday(slot.startTime)
        "$day ${slot.formattedTimeRange()}"
    } ?: tr("选择时间")
    val toleranceText = if (draft.skillTolerance >= MatchRequest.ANY_SKILL) tr("不限水平") else tr("水平 ±%lld", draft.skillTolerance)
    Column(modifier.card(AppTheme.colors.lime, padding = AppTheme.Spacing.xl), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("快速约球"), style = AppTheme.Typography.title2, color = ink, modifier = Modifier.weight(1f).semantics { heading() })
            Text(
                tr("调整"), style = AppTheme.Typography.footnoteBold, color = ink,
                modifier = Modifier.pressable { router.isMatchSetupPresented = true }.padding(vertical = AppTheme.Spacing.sm),
            )
        }
        Flow(Modifier.pressable(scale = 1f) { router.isMatchSetupPresented = true }, spacing = 6.dp) {
            SummaryChip(draft.mode.title, draft.mode.icon)
            SummaryChip(timeText, Sym.clockFill)
            SummaryChip(tr("%lld 个球馆", draft.courtIds.size), Sym.mappin)
            SummaryChip(toleranceText, Sym.chartBarFill)
        }
        // 草稿能直接搜就开始匹配，不能（时间过了、没选球馆）先打开设置页
        BrutalButton(onClick = {
            if (env.appState.currentUser == null) return@BrutalButton
            if (!draft.canSearch()) {
                router.isMatchSetupPresented = true
            } else {
                haptics.impact()
                env.matchManager.startSearch()
            }
        }, kind = ButtonKind.Inverse) {
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
