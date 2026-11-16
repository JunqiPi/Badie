package com.badie.app.features.rankings

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.FitText
import com.badie.app.design.IconButton
import com.badie.app.design.LevelBadge
import com.badie.app.design.NoticeBanner
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.Challenge
import com.badie.app.models.ChallengeStatus
import com.badie.app.models.CountryInfo
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.LevelBracket
import com.badie.app.models.Rankings
import com.badie.app.models.ReportReason
import com.badie.app.models.User
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import kotlinx.coroutines.launch

// 排行榜（全球周榜；选了球馆就看本馆月榜）和挑战列表。
// 对应 iPhone 的 Features/Rankings/LeaderboardViews.swift 和 ChallengeViews.swift 的 ChallengesView

// MARK: - 排行榜

private enum class Scope { Global, Country }
private enum class PeriodChoice { This, Last }

/** venueId 不为空时看这家球馆的月榜（顶部的球馆下拉可以换） */
@Composable
fun LeaderboardScreen(venueId: String? = null) {
    val env = LocalEnv.current
    val router = env.router
    val appState = env.appState
    val manager = rememberRankingManager()
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()

    var selectedVenue by rememberSaveable { mutableStateOf(venueId) }
    var boardScope by rememberSaveable { mutableStateOf(Scope.Global) }
    var weekChoice by rememberSaveable { mutableStateOf(PeriodChoice.This) }
    /** 男子榜 / 女子榜；没选过就看自己的 */
    var boardChoice by rememberSaveable { mutableStateOf<Gender?>(null) }
    var onlyMyBracket by rememberSaveable { mutableStateOf(false) }
    var reportTarget by remember { mutableStateOf<String?>(null) }

    val current = Rankings.week(System.currentTimeMillis())
    val week = if (weekChoice == PeriodChoice.This) current else Rankings.week(current.start - 1)
    val country = boardScope == Scope.Country
    val boardGender = boardChoice ?: manager.myBoard
    val onMyBoard = boardGender == manager.myBoard
    // 看另一个榜时不按我的段筛
    val me = appState.currentUser
    val myBracket = if (onMyBoard && me != null) LevelBracket.of(me.displayTier.rating) else null

    LaunchedEffect(Unit) {
        launch { quietly { manager.prefetchWeekly() } }
        launch { quietly { manager.loadCountry() } }
        launch { quietly { env.roomManager.book.refresh(ifOlderThan = 60_000) } }
        quietly { manager.loadVenues(listOfNotNull(selectedVenue)) }
    }
    LaunchedEffect(week, country, boardGender) { quietly { manager.loadWeekly(week, country, boardGender) } }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("排行榜"), onBack = { router.pop() }) {
            if (selectedVenue == null) {
                RulesButton(tr("积分怎么算"), weeklyRules())
            } else {
                RulesButton(tr("馆榜怎么排"), venueRules())
            }
        }
        RefreshEverything(Modifier.fillMaxSize(), extra = {
            quietly {
                val venue = selectedVenue
                if (venue == null) manager.loadWeekly(week, country, boardGender, force = true)
                else manager.loadVenueBoard(venue, Rankings.month(System.currentTimeMillis()), force = true)
            }
        }) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = AppTheme.Spacing.screen)
                    .padding(bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
            ) {
                VenueFilter(manager, selectedVenue) { selectedVenue = it }
                val venue = selectedVenue
                if (venue != null) {
                    androidx.compose.runtime.key(venue) { VenueBoard(manager, venue) }
                } else {
                    // 筛选
                    Column(Modifier.padding(top = AppTheme.Spacing.xs), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        val info = CountryInfo.info(manager.countryCode)
                        SegmentedSticker(Scope.entries, boardScope, { boardScope = it }) {
                            if (it == Scope.Global) tr("全球") else "${info.flag} ${info.nameZh}"
                        }
                        SegmentedSticker(PeriodChoice.entries, weekChoice, { weekChoice = it }) {
                            if (it == PeriodChoice.This) tr("本周") else tr("上周")
                        }
                        BoardPicker(boardChoice, manager.myBoard) { boardChoice = it }
                        if (myBracket != null) {
                            BracketToggle(myBracket, onlyMyBracket) { onlyMyBracket = it }
                        }
                    }
                    var entries = manager.weeklyLeaderboard(week, country, boardGender)
                    if (onlyMyBracket && myBracket != null) {
                        entries = RankingManager.reranked(entries.filter { entry -> manager.user(entry.userId)?.let { LevelBracket.of(it.displayTier.rating) } == myBracket })
                    }
                    // 看另一个榜时不显示“我的位置”（我不在那个榜上）
                    if (onMyBoard) manager.standing(week, country, entries)?.let { MyStandingCard(it) }
                    when {
                        manager.isWeeklyLoading(week, country, boardGender) -> BoardPlaceholder()
                        entries.isEmpty() -> EmptyStateView(Sym.trophy, tr("还没有人上榜"), Modifier.card(), tint = colors.butter)
                        else -> Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            for (entry in entries) {
                                val user = manager.user(entry.userId) ?: continue
                                val isMe = entry.userId == me?.id
                                LeaderboardRow(
                                    entry, user, isMe, showsLevel = true, points = entry.score,
                                    onReport = if (isMe) null else ({ reportTarget = entry.userId }),
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    reportTarget?.let { userId ->
        ReportSheet(onDismiss = { reportTarget = null }) { reason ->
            reportTarget = null
            scope.launch {
                try {
                    manager.report(userId, reason)
                    appState.showToast(L10n.tr("已隐藏，我们会尽快核实"), Toast.Style.Success)
                } catch (error: RemoteError) {
                    appState.showError(error)
                }
            }
        }
    }
}

// MARK: 规则（“?”里）

@Composable
private fun weeklyRules() = listOf(
    tr("每场确认过的比赛：输 10 分、赢 15 分"),
    tr("输了也有分，多打就多得"),
    tr("对手比你强最多 ×1.5，比你弱最少 ×0.5"),
    tr("同一对手第 2 场减半、第 3 场起不计分"),
    tr("每周最多计 %lld 场", Rankings.WEEKLY_GAME_CAP),
    tr("至少 %lld 场、%lld 位不同对手才上榜", Rankings.WEEKLY_MINIMUM_GAMES, Rankings.WEEKLY_MINIMUM_OPPONENTS),
    tr("双方确认的比赛才算"),
    tr("有分歧或没确认的不计分"),
    tr("注册满 %lld 天才上榜", Rankings.MINIMUM_ACCOUNT_AGE_DAYS),
    tr("可在设置里关闭上榜"),
    tr("每周一 0 点（UTC）重新开始"),
)

@Composable
private fun venueRules() = listOf(
    tr("按本月在这家球馆打的、双方确认过的场数排名"),
    tr("同一对手最多计 %lld 场，每天最多 %lld 场", Rankings.VENUE_SAME_OPPONENT_CAP, Rankings.VENUE_DAILY_CAP),
    tr("至少 %lld 场、%lld 位不同对手才上榜", Rankings.VENUE_MINIMUM_GAMES, Rankings.VENUE_MINIMUM_OPPONENTS),
    tr("每个水平段单独排"),
)

// MARK: 球馆下拉

/** 可选的球馆：当前选的、常去的、打过球的（新的在前）、附近的 */
@Composable
private fun VenueFilter(manager: RankingManager, selected: String?, onSelect: (String?) -> Unit) {
    val colors = AppTheme.colors
    var open by remember { mutableStateOf(false) }
    val games = LocalEnv.current.roomManager.book.games
    val choices = buildList {
        selected?.let(manager::venue)?.let(::add)
        addAll(manager.favoriteVenues)
        addAll(games.sortedByDescending { it.slot.startTime }.map { it.court })
        addAll(manager.nearbyVenues.take(10))
    }.distinctBy { it.id }.take(15)
    val title = selected?.let { manager.venue(it)?.name } ?: tr("全部球馆")
    val label = tr("球馆")
    Box(Modifier.padding(top = AppTheme.Spacing.xs)) {
        Row(
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 48.dp)
                .sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
                .pressable(scale = 0.98f) { open = true }
                .semantics(mergeDescendants = true) { contentDescription = label }
                .padding(horizontal = AppTheme.Spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            Symbol(Sym.mappinAndEllipse, size = 15, tint = colors.ink)
            Text(title, style = AppTheme.Typography.subheadlineBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Symbol(Sym.chevronDown, size = 13, tint = colors.ink)
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = colors.surface, shape = RoundedCornerShape(AppTheme.Radius.md)) {
            MenuItem(tr("全部球馆"), selected == null) {
                open = false
                onSelect(null)
            }
            for (venue in choices) {
                MenuItem(venue.name, selected == venue.id) {
                    open = false
                    onSelect(venue.id)
                }
            }
        }
    }
}

@Composable
internal fun MenuItem(title: String, checked: Boolean, icon: SymbolId? = null, tint: Color = AppTheme.colors.ink, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, style = AppTheme.Typography.body, color = tint) },
        onClick = onClick,
        leadingIcon = when {
            checked -> ({ Symbol(Sym.checkmark, size = 15, tint = tint) })
            icon != null -> ({ Symbol(icon, size = 15, tint = tint) })
            else -> null
        },
    )
}

// MARK: 只看我的水平段

@Composable
private fun BracketToggle(bracket: LevelBracket, isOn: Boolean, onChange: (Boolean) -> Unit) {
    val colors = AppTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = AppTheme.Spacing.xs)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr("只看我的水平段"), style = AppTheme.Typography.subheadlineBold, color = colors.ink)
            Text(bracket.title, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
        }
        Switch(
            isOn, onChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = colors.lime, checkedThumbColor = Color.White, checkedBorderColor = colors.stroke,
                uncheckedTrackColor = colors.surfaceMuted, uncheckedThumbColor = Color.White, uncheckedBorderColor = colors.stroke,
            ),
        )
    }
}

// MARK: 我的位置

@Composable
private fun MyStandingCard(standing: WeeklyStanding) {
    val env = LocalEnv.current
    val ink = AppTheme.colors.onAccent
    Row(
        Modifier.card(AppTheme.colors.lime).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        env.appState.currentUser?.let { AvatarView(it, size = 44.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr("我的位置"), style = AppTheme.Typography.overline.copy(letterSpacing = androidx.compose.ui.unit.TextUnit(0.8f, androidx.compose.ui.unit.TextUnitType.Sp)), color = ink)
            Text(standing.summary, style = AppTheme.Typography.headline, color = ink)
            Text(tr("%lld 场 · 胜 %lld", standing.games, standing.wins), style = AppTheme.Typography.footnote, color = ink, modifier = Modifier.alpha(0.8f))
        }
    }
}

// MARK: - 场馆月榜

private const val VENUE_VISIBLE_COUNT = 10

/** 一家球馆的月榜（排行榜里选了球馆时显示） */
@Composable
private fun VenueBoard(manager: RankingManager, venueId: String) {
    val me = LocalEnv.current.appState.currentUser?.id
    var monthChoice by rememberSaveable { mutableStateOf(PeriodChoice.This) }
    var boardChoice by rememberSaveable { mutableStateOf<Gender?>(null) }
    val current = Rankings.month(System.currentTimeMillis())
    val month = if (monthChoice == PeriodChoice.This) current else Rankings.month(current.start - 1)
    val gender = boardChoice ?: manager.myBoard
    LaunchedEffect(month, gender) { quietly { manager.loadVenueBoard(venueId, month, gender) } }

    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
        SegmentedSticker(PeriodChoice.entries, monthChoice, { monthChoice = it }) {
            if (it == PeriodChoice.This) tr("本月") else tr("上月")
        }
        BoardPicker(boardChoice, manager.myBoard) { boardChoice = it }
        val sections = manager.venueLeaderboard(venueId, month, gender)
        when {
            manager.isVenueLoading(venueId, month, gender) -> BoardPlaceholder()
            sections.isEmpty() -> EmptyStateView(Sym.trophy, tr("这个月还没有人上榜"), Modifier.card(), tint = AppTheme.colors.butter)
            else -> for ((bracket, entries) in sections) {
                val visible = entries.take(VENUE_VISIBLE_COUNT).toMutableList()
                entries.firstOrNull { it.userId == me }?.let { if (it !in visible) visible += it }
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    SectionTitle(bracket.title, detail = tr("%lld 人", entries.size))
                    for (entry in visible) {
                        val user = manager.user(entry.userId) ?: continue
                        LeaderboardRow(
                            entry, user, isMe = entry.userId == me, showsLevel = false,
                            badge = if (entry.rank == 1) tr("本月馆主") else null,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 榜还没拉回来

/** 几行灰条占位：不显示“没人上榜”，免得像是出错了 */
@Composable
private fun BoardPlaceholder() {
    val fill = AppTheme.colors.surfaceMuted
    val label = tr("正在加载")
    Column(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label },
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        repeat(5) {
            Box(
                Modifier.fillMaxWidth().height(64.dp).drawBehind {
                    drawRoundRect(fill, cornerRadius = CornerRadius(AppTheme.Radius.lg.toPx()))
                },
            )
        }
    }
}

// MARK: - 男子榜 / 女子榜

/** 男女等级分开算，榜也分开；默认看自己的 */
@Composable
private fun BoardPicker(selection: Gender?, mine: Gender, onSelect: (Gender) -> Unit) {
    SegmentedSticker(Gender.choices, selection ?: mine, onSelect) { it.boardLabel }
}

// MARK: - 榜单行

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LeaderboardRow(
    entry: Rankings.Entry,
    user: User,
    isMe: Boolean,
    showsLevel: Boolean,
    /** 周榜积分；场馆榜不显示 */
    points: Int? = null,
    badge: String? = null,
    /** 长按举报（自己那一行没有） */
    onReport: (() -> Unit)? = null,
) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var menu by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !isMe) 0.98f else 1f, AppTheme.Motion.press(), label = "press")
    val record = tr("%lld 场 · 胜 %lld", entry.games, entry.wins)
    val detail = if (showsLevel) "${user.displayLevelText} · $record" else record
    val base = tr("第 %lld 名，%@，%@", entry.rank, user.nickname, detail)
    val description = if (points == null) base else tr("%@，%lld 分", base, points)

    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .graphicsLayer { scaleX = scale; scaleY = scale }
                .combinedClickable(
                    interactionSource = interaction, indication = null, enabled = !isMe || onReport != null, role = Role.Button,
                    onLongClick = onReport?.let { { haptics.impact(); menu = true } },
                    onClick = { if (!isMe) env.appState.showPlayer(user.id) },
                )
                .clearAndSetSemantics { contentDescription = description }
                .sticker(if (isMe) colors.lime.copy(alpha = 0.35f) else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                .padding(horizontal = AppTheme.Spacing.md, vertical = AppTheme.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            RankMark(entry.rank)
            AvatarView(user, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                    Text(
                        user.nickname, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                    )
                    if (isMe) TagPill(tr("我"), fill = colors.lime)
                    if (badge != null) TagPill(badge, icon = Sym.crownFill, fill = colors.butter)
                }
                Text(detail, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (points != null) {
                Text(tr("%lld 分", points), style = AppTheme.Typography.bodyBold.copy(fontFeatureSettings = "tnum"), color = colors.ink)
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = colors.surface, shape = RoundedCornerShape(AppTheme.Radius.md)) {
            MenuItem(tr("举报"), checked = false, icon = Sym.exclamationmarkBubble, tint = colors.danger) {
                menu = false
                onReport?.invoke()
            }
        }
    }
}

/** 名次：前三名是金、银、铜色的圆 */
@Composable
private fun RankMark(rank: Int) {
    val colors = AppTheme.colors
    val medal = when (rank) {
        1 -> colors.butter
        2 -> colors.sky
        3 -> colors.peach
        else -> null
    }
    val stroke = colors.stroke
    Box(
        Modifier.size(32.dp).drawBehind {
            if (medal != null) {
                drawCircle(medal)
                val width = AppTheme.Stroke.hairline.toPx()
                drawCircle(stroke, radius = size.minDimension / 2 - width / 2, style = Stroke(width))
            }
        },
        contentAlignment = Alignment.Center,
    ) {
        FitText(
            "$rank", Modifier.padding(horizontal = 2.dp),
            style = AppTheme.Typography.bodyBold.copy(fontFeatureSettings = "tnum"),
            color = if (medal == null) colors.inkSecondary else colors.onAccent,
        )
    }
}

// MARK: - 举报

/** 举报这位球友：选原因（对应 iPhone 的 confirmationDialog） */
@Composable
private fun ReportSheet(onDismiss: () -> Unit, onReport: (ReportReason) -> Unit) {
    val colors = AppTheme.colors
    SheetScaffold(onDismiss = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            Text(tr("举报这位球友？"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
            Text(tr("举报后对方会立即从你的榜单上隐藏，我们会人工核实。"), style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
            Spacer(Modifier.height(AppTheme.Spacing.xs))
            BrutalButton(tr("刷榜 / 虚假比赛"), { onReport(ReportReason.Other) }, kind = ButtonKind.Destructive, size = ButtonSize.Medium)
            BrutalButton(tr("广告 / 引流"), { onReport(ReportReason.Scam) }, kind = ButtonKind.Destructive, size = ButtonSize.Medium)
            BrutalButton(tr("取消"), onDismiss, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
        }
    }
}

// MARK: - 挑战列表（收到的 / 发出的）

@Composable
fun ChallengesScreen() {
    val env = LocalEnv.current
    val router = env.router
    val appState = env.appState
    val manager = rememberRankingManager()
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    var workingId by remember { mutableStateOf<String?>(null) }
    /** 双打挑战接受前先选搭档 */
    var acceptingDoubles by remember { mutableStateOf<Challenge?>(null) }

    LaunchedEffect(Unit) { quietly { manager.refreshChallenges() } }

    fun respond(challenge: Challenge, accept: Boolean, partnerId: String? = null) {
        workingId = challenge.id
        scope.launch {
            try {
                val gameId = manager.respond(challenge.id, accept, partnerId)
                if (accept) {
                    haptics.success()
                    appState.showToast(L10n.tr("已接受，球局已加入你的日程"), Toast.Style.Success)
                    if (gameId != null) router.open(Route.Game(gameId))
                } else {
                    appState.showToast(L10n.tr("已婉拒，对方不会收到通知"))
                }
            } catch (error: RemoteError) {
                appState.showError(error)
            } finally {
                workingId = null
            }
        }
    }

    val all = manager.challenges()
    val incoming = manager.incoming(all)
    val outgoing = manager.outgoing(all)

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("挑战"), onBack = { router.pop() })
        RefreshEverything(Modifier.fillMaxSize(), extra = { quietly { manager.refreshChallenges() } }) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = AppTheme.Spacing.screen)
                    .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
            ) {
                if (all.isEmpty()) {
                    EmptyStateView(Sym.flag2CrossedFill, tr("还没有挑战"), Modifier.card(), tint = AppTheme.colors.peach)
                }
                if (incoming.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        SectionTitle(tr("收到的"))
                        for (challenge in incoming) {
                            ChallengeRow(manager, challenge, otherId = challenge.challengerId) {
                                IncomingTrailing(challenge, working = workingId != null, onDecline = { respond(challenge, false) }) {
                                    if (challenge.mode == GameMode.Doubles) acceptingDoubles = challenge else respond(challenge, true)
                                }
                            }
                        }
                    }
                }
                if (outgoing.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        SectionTitle(tr("发出的"))
                        for (challenge in outgoing) {
                            ChallengeRow(manager, challenge, otherId = challenge.targetId) {
                                OutgoingTrailing(challenge) {
                                    scope.launch {
                                        try {
                                            manager.withdraw(challenge.id)
                                            appState.showToast(L10n.tr("已撤回"))
                                        } catch (error: RemoteError) {
                                            appState.showError(error)
                                            quietly { manager.refreshChallenges() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    acceptingDoubles?.let { challenge ->
        SheetScaffold(onDismiss = { acceptingDoubles = null }) {
            AcceptDoublesSheet(manager, challenge, onDismiss = { acceptingDoubles = null }) { partnerId ->
                acceptingDoubles = null
                respond(challenge, true, partnerId)
            }
        }
    }
}

@Composable
private fun IncomingTrailing(challenge: Challenge, working: Boolean, onDecline: () -> Unit, onAccept: () -> Unit) {
    when (challenge.status) {
        ChallengeStatus.Pending -> Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Text(
                tr("还剩 %@", RankingManager.remaining(challenge.expiresAt)),
                style = AppTheme.Typography.caption, color = AppTheme.colors.inkTertiary,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalButton(tr("不了"), onDecline, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false, enabled = !working)
                BrutalButton(tr("接受"), onAccept, kind = ButtonKind.Primary, size = ButtonSize.Small, fullWidth = false, enabled = !working)
            }
        }
        ChallengeStatus.Accepted -> AcceptedLine(challenge)
        ChallengeStatus.Declined -> StatusText(tr("已婉拒"))
        ChallengeStatus.Expired, ChallengeStatus.Withdrawn -> StatusText(tr("未成行"))
    }
}

@Composable
private fun OutgoingTrailing(challenge: Challenge, onWithdraw: () -> Unit) {
    when (challenge.status) {
        ChallengeStatus.Pending -> Row(verticalAlignment = Alignment.CenterVertically) {
            StatusText(tr("等待回应 · 还剩 %@", RankingManager.remaining(challenge.expiresAt)), Modifier.weight(1f))
            TextAction(tr("撤回"), onWithdraw)
        }
        ChallengeStatus.Accepted -> AcceptedLine(challenge)
        // 对发起人不区分“被拒”和“过期”
        else -> StatusText(tr("未成行"))
    }
}

@Composable
private fun AcceptedLine(challenge: Challenge) {
    val router = LocalEnv.current.router
    Row(verticalAlignment = Alignment.CenterVertically) {
        TagPill(tr("已接受"), icon = Sym.checkmark, fill = AppTheme.colors.lime)
        Spacer(Modifier.weight(1f))
        challenge.gameId?.let { gameId -> TextAction(tr("查看球局"), { router.open(Route.Game(gameId)) }) }
    }
}

@Composable
private fun StatusText(text: String, modifier: Modifier = Modifier) {
    Text(text, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary, modifier = modifier)
}

@Composable
private fun ChallengeRow(manager: RankingManager, challenge: Challenge, otherId: String, trailing: @Composable () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val other = manager.user(otherId)
    // otherId 是发起人时我在被挑战方，反之亦然
    val otherIsChallenger = otherId == challenge.challengerId
    val myPartner = (if (otherIsChallenger) challenge.targetPartnerId else challenge.challengerPartnerId)?.let(manager::user)
    val otherPartner = (if (otherIsChallenger) challenge.challengerPartnerId else challenge.targetPartnerId)?.let(manager::user)
    val hint = tr("查看个人资料")

    Column(Modifier.card(colors.surface, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.Top) {
            Row(
                Modifier
                    .pressable(scale = 1f, onClickLabel = hint) { env.appState.showPlayer(otherId) }
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                if (other != null) AvatarView(other, size = 44.dp)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(other?.nickname ?: tr("球友"), style = AppTheme.Typography.headline, color = colors.ink)
                    if (other != null) LevelBadge(other.displayTier)
                }
            }
            Spacer(Modifier.weight(1f))
            TagPill(challenge.mode.title, icon = Sym.flag2CrossedFill, fill = colors.peach)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            myPartner?.let { InfoLabel(Sym.person2, tr("搭档：%@", it.nickname)) }
            otherPartner?.let { InfoLabel(Sym.person2, tr("对方搭档：%@", it.nickname)) }
            InfoLabel(Sym.calendar, challenge.slot.formattedFull())
            InfoLabel(Sym.mappinAndEllipse, challenge.court.name)
        }
        if (challenge.message.isNotEmpty()) {
            Text(tr("“%@”", challenge.message), style = AppTheme.Typography.body, color = colors.ink)
        }
        trailing()
    }
}

/** 图标 + 一行字（iPhone 的 Label） */
@Composable
internal fun InfoLabel(icon: SymbolId, text: String, color: Color = AppTheme.colors.inkSecondary) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Symbol(icon, size = 12, tint = color)
        Text(text, style = AppTheme.Typography.footnote, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: - 接受双打挑战前选自己的搭档

@Composable
private fun AcceptDoublesSheet(manager: RankingManager, challenge: Challenge, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    val colors = AppTheme.colors
    var partnerId by remember { mutableStateOf<String?>(null) }
    val friendManager = LocalEnv.current.friendManager
    LaunchedEffect(Unit) { quietly { friendManager.refreshFriends() } }
    // 不能选对方两人
    val taken = listOfNotNull(challenge.challengerId, challenge.challengerPartnerId)
    val options = friendManager.friends.filter { it.id !in taken }

    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("选你的搭档"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(tr("挑战规则"), listOf(tr("四人都确认赛果后计入排行")))
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        if (options.isEmpty()) {
            NoticeBanner(Sym.person2Fill, tr("先加球友，才能接受双打挑战"))
        } else {
            PartnerPicker(options, partnerId) { partnerId = it }
        }
        Spacer(Modifier.height(AppTheme.Spacing.lg))
        BrutalButton(tr("接受挑战"), { partnerId?.let(onConfirm) }, enabled = partnerId != null)
    }
}
