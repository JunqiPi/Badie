package com.badie.app.features.matches

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.FitText
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.night.BigActionButton
import com.badie.app.features.night.BoardSheet
import com.badie.app.features.night.ChoiceOption
import com.badie.app.features.night.ChoiceSheet
import com.badie.app.features.night.CourtStepper
import com.badie.app.features.night.CourtTag
import com.badie.app.features.night.MatchupLine
import com.badie.app.features.night.TextInputDialog
import com.badie.app.features.night.UndoButton
import com.badie.app.features.night.showClubError
import com.badie.app.features.social.ConfirmDialog
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.MatchFormat
import com.badie.app.models.MatchPlay
import com.badie.app.models.MatchRules
import com.badie.app.models.MatchScoring
import com.badie.app.models.MatchState
import com.badie.app.models.MyMatch
import com.badie.app.models.NightHelper
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 比赛页。对应 iPhone 的 Features/Matches/MatchViews.swift。
// 进行中：正在打的场地（输比分）、下一场、积分榜、全部对阵；结束后：冠军 + 最终排名 + 分享成图片。
// 当晚页的“比赛”分段用同一个 MatchPanel（embedded）。数据在服务器上（match_state），每 10 秒重拉

@Composable
fun MatchScreen(matchId: String) {
    val env = LocalEnv.current
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("比赛"), onBack = { env.router.pop() })
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        ) {
            MatchPanel(matchId)
        }
    }
}

/** 管理菜单里点开的几样 */
private enum class MatchSheet { Board, Menu, Courts, Helpers, Qualify, Withdraw, AddPlayer, End, Delete }

/** 比赛的内容。embedded：放在当晚页里，不显示分享按钮，删掉后不返回 */
@Composable
fun MatchPanel(matchId: String, embedded: Boolean = false) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val api = env.night
    var state by remember(matchId) { mutableStateOf<MatchState?>(null) }
    var loaded by remember(matchId) { mutableStateOf(false) }
    var scoring by remember { mutableStateOf<MatchState.Game?>(null) }
    var sheet by remember { mutableStateOf<MatchSheet?>(null) }
    var showsAllGames by remember { mutableStateOf(false) }
    var undoDeadline by remember { mutableStateOf<Long?>(null) }
    var lastUndo by remember { mutableStateOf<java.time.Instant?>(null) }
    var shareImage by remember { mutableStateOf<ImageBitmap?>(null) }

    suspend fun load() {
        try {
            val next = api.matchState(matchId)
            val until = next?.undoUntil
            if (until != null && until != lastUndo) {
                lastUndo = until
                undoDeadline = System.currentTimeMillis() + (until.toEpochMilli() - System.currentTimeMillis()).coerceIn(3_000, 10_000)
            }
            val finished = next?.isLive == false && state?.isLive != false
            state = next
            if (finished && next != null && !embedded) shareImage = MatchShareRenderer.render(context, next)
        } catch (_: RemoteError) {
            // 网差：保留上一份
        }
        loaded = true
    }

    fun perform(work: suspend () -> Unit) {
        scope.launch {
            try {
                work()
            } catch (error: RemoteError) {
                env.appState.showClubError(error)
            }
            load()
        }
    }

    LaunchedEffect(matchId) {
        while (true) {
            load()
            delay(10_000)
        }
    }

    val current = state
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
        when {
            current != null -> {
                // 顶部：名字、赛制和第几轮，右边是二维码和管理
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(current.name, style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.semantics { heading() })
                        Text(subtitle(current), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                    }
                    IconButton(Sym.qrcode, tr("二维码和链接")) { sheet = MatchSheet.Board }
                    if (current.canManage && (current.isLive || current.isOrganizer)) {
                        IconButton(Sym.ellipsis, tr("管理比赛")) { sheet = MatchSheet.Menu }
                    }
                }
                if (current.isLive) {
                    if (current.tieAtCut == true && current.isOrganizer) {
                        Column(Modifier.card(colors.butter, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            Text(tr("出线的名额卡在并列上。"), style = AppTheme.Typography.bodyBold, color = colors.onAccent)
                            BrutalButton(tr("选谁出线"), { sheet = MatchSheet.Qualify }, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
                        }
                    }
                    if (current.canManage) {
                        UndoButton(undoDeadline) {
                            perform {
                                api.matchUndo(matchId)
                                undoDeadline = null
                            }
                        }
                    }
                    PlayingSection(current) { scoring = it }
                    NextGamesSection(current)
                    // 单淘汰没有积分榜
                    if (current.matchFormat != MatchFormat.Knockout) StandingsSection(current)
                    AllGamesSection(current, showsAllGames, { showsAllGames = it }) { scoring = it }
                } else {
                    FinalContent(current, if (embedded) null else shareImage)
                }
            }
            loaded -> EmptyStateView(Sym.trophy, tr("没有找到这场比赛"))
            else -> Box(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.ink)
            }
        }
    }

    if (current == null) return
    scoring?.let { game ->
        SheetScaffold(onDismiss = { scoring = null }, fullHeight = true) {
            MatchScoreSheet(current, game, onDismiss = { scoring = null }) { load() }
        }
    }
    val deleted = tr("已删除")
    when (sheet) {
        MatchSheet.Board -> BoardSheet(current.boardCode) { sheet = null }
        MatchSheet.Menu -> {
            val options = buildList {
                if (current.isLive) {
                    add(ChoiceOption(tr("场地数")) { sheet = MatchSheet.Courts })
                    if (current.isOrganizer) add(ChoiceOption(tr("帮手")) { sheet = MatchSheet.Helpers })
                    if (current.play == MatchPlay.Rotating.raw) add(ChoiceOption(tr("加人")) { sheet = MatchSheet.AddPlayer })
                    add(ChoiceOption(tr("退赛")) { sheet = MatchSheet.Withdraw })
                    if (current.isOrganizer) add(ChoiceOption(tr("结束比赛")) { sheet = MatchSheet.End })
                }
                if (current.isOrganizer) add(ChoiceOption(tr("删除"), destructive = true) { sheet = MatchSheet.Delete })
            }
            // 选了一项：先关菜单，再打开那一项
            ChoiceSheet(tr("管理比赛"), options, onDismiss = { if (sheet == MatchSheet.Menu) sheet = null })
        }
        MatchSheet.Courts -> SheetScaffold(onDismiss = { sheet = null }) {
            MatchCourtsSheet(current.courts, onDismiss = { sheet = null }) { courts -> perform { api.matchCourts(matchId, courts) } }
        }
        MatchSheet.Helpers -> SheetScaffold(onDismiss = { sheet = null }, fullHeight = true) {
            MatchHelpersSheet(helperCandidates(current), current.helpers.orEmpty().map { it.id }.toSet(), onDismiss = { sheet = null }) { users ->
                perform { api.matchHelpers(matchId, users) }
            }
        }
        MatchSheet.Qualify -> SheetScaffold(onDismiss = { sheet = null }, fullHeight = true) {
            MatchQualifySheet(current, onDismiss = { sheet = null }) { keys -> perform { api.matchQualify(matchId, keys) } }
        }
        MatchSheet.Withdraw -> ChoiceSheet(
            tr("谁退赛了？"),
            current.players.filter { !it.withdrawn }.map { player -> ChoiceOption(player.name) { perform { api.matchWithdraw(player.id, null) } } },
            onDismiss = { if (sheet == MatchSheet.Withdraw) sheet = null },
            message = tr("没打的场次取消，已经打完的照算。"),
        )
        MatchSheet.AddPlayer -> TextInputDialog(
            tr("加人"), tr("加"), onDismiss = { sheet = null }, message = tr("从下一轮开始排。"), placeholder = tr("名字"),
        ) { name -> perform { api.matchAddPlayer(matchId, name) } }
        MatchSheet.End -> ConfirmDialog(tr("结束比赛？"), tr("没打的写“没打”，按已经打的排名。"), tr("结束比赛"), onDismiss = { sheet = null }) {
            perform { api.matchEnd(matchId) }
        }
        MatchSheet.Delete -> ConfirmDialog(tr("删掉这场比赛？"), tr("参赛的人会收到通知，不能恢复。"), tr("删除"), onDismiss = { sheet = null }) {
            scope.launch {
                try {
                    api.matchDelete(matchId)
                    env.appState.showToast(deleted)
                    if (!embedded) env.router.pop()
                } catch (error: RemoteError) {
                    env.appState.showClubError(error)
                }
            }
        }
        null -> Unit
    }
}

@Composable
private fun subtitle(state: MatchState): String {
    val format = MatchFormat.title(state.format, state.play)
    // 循环、瑞士轮写第几轮；有淘汰赛的不写
    val round = state.round
    if (state.isLive && state.matchFormat.byRounds && round != null && round <= state.rounds) {
        return tr("%@ · 第 %lld/%lld 轮", format, round, state.rounds)
    }
    return format
}

/** 能当帮手的人：参赛的注册用户、球友（不含自己） */
@Composable
private fun helperCandidates(state: MatchState): List<NightHelper> {
    val env = LocalEnv.current
    val me = env.appState.currentUser?.id
    val seen = mutableSetOf<String>()
    val list = mutableListOf<NightHelper>()
    state.players.forEach { player ->
        val userId = player.userId
        if (userId != null && userId != me && seen.add(userId)) list += NightHelper(userId, player.name)
    }
    env.friendManager.friends.forEach { friend ->
        if (friend.id != me && seen.add(friend.id)) list += NightHelper(friend.id, friend.nickname)
    }
    return list
}

@Composable
private fun SectionTitle(title: String, extra: @Composable () -> Unit = {}) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        Text(title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        extra()
    }
}

// MARK: - 进行中

@Composable
private fun PlayingSection(state: MatchState, onScore: (MatchState.Game) -> Unit) {
    val colors = AppTheme.colors
    val playing = state.realGames.filter { it.status == "playing" }.sortedBy { it.court ?: 0 }
    if (playing.isEmpty()) return
    val style = rounded(20, FontWeight.ExtraBold)
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("正在打"))
        playing.forEach { game ->
            Row(
                Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg)
                    .padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.md, top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    game.court?.let { CourtTag(it) }
                    FitText(state.sideName(game.a), style = style, color = colors.ink, minimumScale = 0.7f)
                    FitText(state.sideName(game.b), style = style, color = colors.ink, minimumScale = 0.7f)
                }
                if (state.canScore(game)) BigActionButton(tr("输比分")) { onScore(game) }
            }
        }
    }
}

@Composable
private fun NextGamesSection(state: MatchState) {
    val queued = state.realGames.filter { it.status == "queued" }.take(maxOf(2, state.courts))
    if (queued.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("下一场"))
        Column(
            Modifier.fillMaxWidth().sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
                .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            queued.forEach { game -> MatchupLine(game.a.map(state::name), game.b.map(state::name)) }
        }
    }
}

@Composable
private fun StandingsSection(state: MatchState) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("积分榜")) { RulesButton(tr("排名规则"), MatchRules.points) }
        val pools = state.pools
        if (pools != null && pools > 1) {
            (1..pools).forEach { pool -> StandingsTable(state.standings.filter { it.pool == pool }, title = tr("第 %lld 组", pool)) }
        } else {
            StandingsTable(state.standings)
        }
    }
}

@Composable
private fun AllGamesSection(state: MatchState, isOpen: Boolean, onToggle: (Boolean) -> Unit, onOpen: (MatchState.Game) -> Unit) {
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).pressable(scale = 1f) { onToggle(!isOpen) }
                .sticker(colors.surfaceMuted, radius = 16.dp, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("全部对阵"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
            Symbol(Sym.chevronDown, size = 13, tint = colors.ink, modifier = Modifier.rotate(if (isOpen) 180f else 0f))
        }
        if (isOpen) {
            state.realGames.map { it.round }.distinct().sorted().forEach { round ->
                val games = state.realGames.filter { it.round == round }
                // 决赛和三四名同一轮：写“决赛”
                val title = (games.firstOrNull { it.stage == "ko" } ?: games.firstOrNull())?.let(MatchRules::stageTitle) ?: tr("第 %lld 轮", round)
                Text(title, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.padding(top = AppTheme.Spacing.xs))
                games.forEach { game -> GameRow(state, game, onOpen) }
            }
        }
    }
}

@Composable
private fun GameRow(state: MatchState, game: MatchState.Game, onOpen: (MatchState.Game) -> Unit) {
    val colors = AppTheme.colors
    val opens = state.canScore(game) || (game.status == "done" && state.isMine(game))
    val flaggedLabel = tr("有人说比分不对")
    Row(
        Modifier.fillMaxWidth().pressable(scale = 1f, enabled = opens) { onOpen(game) }
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.md, vertical = AppTheme.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(state.sideName(game.a), style = AppTheme.Typography.subheadlineBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(state.sideName(game.b), style = AppTheme.Typography.subheadlineBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (game.flagged == true && state.canManage) {
            Symbol(Sym.questionmarkCircleFill, size = 17, tint = colors.danger, modifier = Modifier.semantics { contentDescription = flaggedLabel })
        }
        Text(MatchRules.result(game), style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = colors.inkSecondary)
    }
}

// MARK: - 结束：最终排名

@Composable
private fun FinalContent(state: MatchState, shareImage: ImageBitmap?) {
    val colors = AppTheme.colors
    val context = LocalContext.current
    val rows = state.ranking ?: state.standings
    val champion = rows.firstOrNull { it.rank == 1 }
    SectionTitle(tr("最终排名"))
    if (champion != null) {
        Row(
            Modifier.card(colors.butter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            Box(Modifier.size(76.dp).background(Color.White, CircleShape).border(AppTheme.Stroke.width, colors.stroke, CircleShape), contentAlignment = Alignment.Center) {
                Symbol(Sym.trophyFill, size = 32, tint = colors.onAccent)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(tr("冠军"), style = AppTheme.Typography.subheadlineBold, color = colors.onAccent)
                FitText(champion.name, style = rounded(36, FontWeight.Black), color = colors.onAccent, minimumScale = 0.5f)
                Text(
                    tr("%lld 胜 %lld 负 · 净胜 %@", champion.wins, champion.losses, MatchRules.diffText(champion.diff)),
                    style = AppTheme.Typography.subheadlineBold, color = colors.onAccent,
                )
            }
        }
    }
    val others = rows.filter { it.key != champion?.key }
    if (others.isNotEmpty()) StandingsTable(others, isFinal = true)
    if (shareImage != null) {
        BrutalButton({ MatchShareRenderer.share(context, shareImage, state.name) }) {
            Symbol(Sym.squareAndArrowUp, size = 16)
            Spacer(Modifier.size(AppTheme.Spacing.sm))
            Text(tr("分享成图片"))
        }
    }
}

/** 积分榜（进行中）和最终排名的表：名次、名字、胜-负、净胜分 */
@Composable
fun StandingsTable(rows: List<MatchState.Standing>, title: String? = null, isFinal: Boolean = false) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
            .padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.sm),
    ) {
        title?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.padding(top = AppTheme.Spacing.sm)) }
        Row(Modifier.defaultMinSize(minHeight = 28.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            val caption = AppTheme.Typography.caption
            Text(if (isFinal) tr("名次") else "", style = caption, color = colors.inkSecondary, modifier = Modifier.width(36.dp))
            Text(tr("名字"), style = caption, color = colors.inkSecondary, modifier = Modifier.weight(1f))
            Text(tr("胜-负"), style = caption, color = colors.inkSecondary, textAlign = TextAlign.Center, modifier = Modifier.width(56.dp))
            Text(tr("净胜分"), style = caption, color = colors.inkSecondary, textAlign = TextAlign.End, modifier = Modifier.width(56.dp))
        }
        rows.forEach { row ->
            Row(
                Modifier.defaultMinSize(minHeight = if (isFinal) 44.dp else 32.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                Box(Modifier.width(36.dp)) {
                    if (isFinal) {
                        val top = row.rank <= 3
                        Box(
                            Modifier.size(28.dp).background(if (top) colors.lavender else colors.surface, CircleShape)
                                .border(AppTheme.Stroke.hairline, colors.stroke, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) { Text("${row.rank}", style = rounded(14, FontWeight.Black), color = if (top) colors.onAccent else colors.ink) }
                    } else {
                        Text("${row.rank}", style = AppTheme.Typography.bodyBold, color = colors.inkSecondary)
                    }
                }
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        row.name, style = AppTheme.Typography.bodyBold, color = if (row.withdrawn == true) colors.inkTertiary else colors.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                    )
                    if (row.tied == true) Text(tr("并列"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
                    if (row.withdrawn == true) Text(tr("已退赛"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
                }
                Text(
                    "${row.wins}-${row.losses}", style = AppTheme.Typography.bodyBold.copy(fontFeatureSettings = "tnum"), color = colors.ink,
                    textAlign = TextAlign.Center, modifier = Modifier.width(56.dp),
                )
                Text(
                    MatchRules.diffText(row.diff), style = AppTheme.Typography.subheadlineBold.copy(fontFeatureSettings = "tnum"), color = colors.ink,
                    textAlign = TextAlign.End, modifier = Modifier.width(56.dp),
                )
            }
        }
    }
}

// MARK: - 输比分（半屏）
// 两边大数字，加减，点数字直接输；三局两胜一局一局填。
// 球员只能在打的时候输自己那场，先存的算；别人再打开看到“Amy 填的：21–18”，只能点“不对”。
// 组织者、帮手随时能改（写“Kevin 改的”）；不合规的比分存不了，写明哪里不对；中途退赛单独记

private enum class ScoreDialog { Typing, Retire, Withdraw }

@Composable
fun MatchScoreSheet(match: MatchState, game: MatchState.Game, onDismiss: () -> Unit, onDone: suspend () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val api = env.night
    // 每局两个数：[a1, b1, a2, b2, a3, b3]
    val scores = remember(game.id) {
        val count = if (match.bestOf == 3) 6 else 2
        mutableStateListOf<Int>().apply { addAll((game.scores.orEmpty() + List(count) { 0 }).take(count)) }
    }
    var setIndex by remember { mutableIntStateOf(0) }
    var saving by remember { mutableStateOf(false) }
    var dialog by remember { mutableStateOf<ScoreDialog?>(null) }
    var typingIndex by remember { mutableIntStateOf(0) }
    val editable = match.canScore(game)
    val stage = MatchRules.stageTitle(game)
    val title = game.court?.let { tr("场地 %lld · %@", it, stage) } ?: stage
    val entered = MatchScoring.played(scores.toList())
    val check = MatchScoring.check(entered, match.scoring)
    val retireProblem = MatchScoring.retireProblem(entered, match.scoring)
    val sets = if (match.bestOf == 3) tr("三局两胜") else tr("一局")
    val flaggedText = tr("已经告诉组织者了。")

    fun send(call: suspend () -> Unit) {
        saving = true
        scope.launch {
            try {
                call()
                haptics.success()
                onDone()
                onDismiss()
            } catch (error: RemoteError) {
                if (error is RemoteError.Server && (error.code == "score_taken" || error.code == "score_changed")) {
                    // 有人先存了：提示一句，关掉重看
                    env.appState.showError(error)
                    onDone()
                    onDismiss()
                } else {
                    // 没存上：数字留在原处，可以再点一次
                    env.appState.showClubError(error)
                }
            }
            saving = false
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.semantics { heading() })
                Text(tr("%lld 分 · %@", match.points, sets), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        if (editable) {
            // 谁填的、谁改的
            when {
                game.editedBy != null -> Text(tr("%@ 改的", game.editedBy), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                game.scoredBy != null && game.status == "done" -> Text(tr("%@ 填的", game.scoredBy), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            }
            if (match.bestOf == 3) SegmentedSticker(listOf(0, 1, 2), setIndex, { setIndex = it }) { tr("第 %lld 局", it + 1) }
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                listOf(0, 1).forEach { side ->
                    val index = setIndex * 2 + side
                    val names = match.sideName(if (side == 0) game.a else game.b)
                    val label = tr("%@ 的比分，点一下直接输", names)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        Text(
                            names, style = AppTheme.Typography.headline, color = colors.ink, textAlign = TextAlign.Center, maxLines = 2,
                            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp),
                        )
                        Box(
                            Modifier.fillMaxWidth().defaultMinSize(minHeight = 112.dp)
                                .pressable {
                                    typingIndex = index
                                    dialog = ScoreDialog.Typing
                                }
                                .sticker(colors.surface, radius = AppTheme.Radius.lg)
                                .semantics { contentDescription = label },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("${scores[index]}", style = rounded(64, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.ink)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            StepButton(Sym.minus, tr("减一分"), colors.surfaceMuted, Modifier.weight(1f)) {
                                haptics.tap()
                                scores[index] = maxOf(0, scores[index] - 1)
                            }
                            StepButton(Sym.plus, tr("加一分"), colors.surface, Modifier.weight(1f)) {
                                haptics.tap()
                                scores[index] = minOf(99, scores[index] + 1)
                            }
                        }
                    }
                }
            }
            if (match.bestOf == 3 && entered.isNotEmpty()) {
                Text(
                    MatchRules.scoreText(entered), style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                )
            }
            if (check is MatchScoring.Check.Problem) Text(check.text, style = AppTheme.Typography.footnoteBold, color = colors.danger)
            // 不合规的比分存不了
            BrutalButton(tr("保存"), { send { api.matchScore(game.id, entered, game.version ?: 0) } }, enabled = !saving && check is MatchScoring.Check.Winner)
            if (match.canManage) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg, Alignment.CenterHorizontally)) {
                    TextAction(tr("有人中途退赛"), {
                        if (retireProblem != null) env.appState.showToast(retireProblem, Toast.Style.Error) else dialog = ScoreDialog.Retire
                    }, color = colors.danger)
                    if (game.status != "done") TextAction(tr("退赛"), { dialog = ScoreDialog.Withdraw }, color = colors.danger)
                }
            }
        } else {
            // 球员看别人填的比分：只能点“不对”
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                Text(match.sideName(game.a), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                Text(match.sideName(game.b), style = AppTheme.Typography.headline, color = colors.ink, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
            }
            if (game.status == "done") {
                Text(MatchRules.result(game), style = rounded(44, FontWeight.Black), color = colors.ink, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                val enteredBy = when {
                    game.editedBy != null -> tr("%@ 改的", game.editedBy)
                    game.scoredBy != null -> tr("%@ 填的：%@", game.scoredBy, MatchRules.scoreText(game.scores.orEmpty()))
                    else -> null
                }
                enteredBy?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary) }
                if (match.isMine(game)) {
                    if (game.flagged == true) {
                        Text(tr("已经告诉组织者了。"), style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
                    } else {
                        BrutalButton(tr("不对"), {
                            scope.launch {
                                try {
                                    api.matchFlag(game.id)
                                    env.appState.showToast(flaggedText)
                                    onDone()
                                    onDismiss()
                                } catch (error: RemoteError) {
                                    env.appState.showClubError(error)
                                }
                            }
                        }, kind = ButtonKind.Secondary)
                    }
                }
            } else {
                Text(MatchRules.result(game), style = AppTheme.Typography.bodyBold, color = colors.inkSecondary)
            }
        }
    }

    when (dialog) {
        ScoreDialog.Typing -> TextInputDialog(
            tr("输入比分"), tr("好"), onDismiss = { dialog = null }, initial = "${scores.getOrElse(typingIndex) { 0 }}", keyboard = KeyboardType.Number,
        ) { text ->
            val value = text.trim().toIntOrNull()
            if (value != null && value in 0..99 && typingIndex in scores.indices) scores[typingIndex] = value
        }
        ScoreDialog.Retire -> ChoiceSheet(
            tr("谁中途退赛了？"),
            listOf(1, 2).map { side ->
                ChoiceOption(tr("%@ 中途退赛", match.sideName(if (side == 1) game.a else game.b))) {
                    send { api.matchRetire(game.id, side, entered, game.version ?: 0) }
                }
            },
            onDismiss = { dialog = null },
            message = tr("按退赛时的比分填，没打完的那局也填上。对方赢。"),
        )
        ScoreDialog.Withdraw -> ChoiceSheet(
            tr("谁退赛了？"),
            (game.a + game.b).map { playerId ->
                ChoiceOption(match.name(playerId)) {
                    scope.launch {
                        try {
                            api.matchWithdraw(playerId, game.id)
                            onDone()
                            onDismiss()
                        } catch (error: RemoteError) {
                            env.appState.showClubError(error)
                        }
                    }
                }
            },
            onDismiss = { dialog = null },
            message = tr("这一场算对方赢。"),
        )
        null -> Unit
    }
}

@Composable
private fun StepButton(icon: com.badie.app.design.SymbolId, label: String, fill: Color, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.defaultMinSize(minHeight = 56.dp).pressable(onClick = onClick).sticker(fill, radius = 16.dp, shadow = AppTheme.Elevation.none)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Symbol(icon, size = 22, tint = AppTheme.colors.ink) }
}

// MARK: - 组织者菜单里的几个半屏

@Composable
private fun MatchCourtsSheet(initial: Int, onDismiss: () -> Unit, onSave: (Int) -> Unit) {
    var courts by remember { mutableIntStateOf(initial) }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(tr("场地数"), style = AppTheme.Typography.title2, color = AppTheme.colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.lg))
        CourtStepper(
            courts, { courts = it },
            Modifier.sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs),
        )
        BrutalButton(tr("保存"), {
            onSave(courts)
            onDismiss()
        })
    }
}

/** 帮手（记分员）：最多 3 个，从参赛的人和球友里选 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MatchHelpersSheet(candidates: List<NightHelper>, initial: Set<String>, onDismiss: () -> Unit, onSave: (List<String>) -> Unit) {
    val colors = AppTheme.colors
    var selected by remember { mutableStateOf(initial) }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("帮手"), style = AppTheme.Typography.title2, color = colors.ink)
            RulesButton(tr("帮手"), listOf(tr("能输比分、改场地数、加人。"), tr("不能结束或删除比赛。"), tr("最多 3 个。")))
        }
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                candidates.forEach { person ->
                    val isSelected = person.id in selected
                    ChoiceChip(person.nickname, isSelected, icon = if (isSelected) Sym.checkmark else null) {
                        selected = when {
                            isSelected -> selected - person.id
                            selected.size < 3 -> selected + person.id
                            else -> selected
                        }
                    }
                }
            }
            if (candidates.isEmpty()) Text(tr("还没有球友。"), style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
        }
        BrutalButton(tr("保存"), {
            onSave(selected.toList())
            onDismiss()
        })
    }
}

/** 分组出线卡在并列上：组织者点选谁出线 */
@Composable
private fun MatchQualifySheet(match: MatchState, onDismiss: () -> Unit, onSave: (List<String>) -> Unit) {
    val colors = AppTheme.colors
    val selected = remember { mutableStateListOf<String>() }
    // 出线的名额：每组前几名
    val needed = (match.pools ?: 2) * (match.advance ?: 1)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(tr("选谁出线"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.lg))
        Text(tr("选 %lld 个，按名次排种子。", needed), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            match.standings.filter { it.withdrawn != true }.forEach { row ->
                val isSelected = row.key in selected
                Row(
                    Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp)
                        .pressable(scale = 1f) {
                            if (isSelected) selected.remove(row.key) else if (selected.size < needed) selected.add(row.key)
                        }
                        .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.lg),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                ) {
                    Text("${row.rank}", style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.width(28.dp))
                    Text(row.name, style = AppTheme.Typography.bodyBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    row.pool?.let { Text(tr("第 %lld 组", it), style = AppTheme.Typography.caption, color = colors.inkSecondary) }
                    Spacer(Modifier.weight(1f))
                    Symbol(if (isSelected) Sym.checkmarkCircleFill else Sym.circle, size = 22, tint = colors.ink)
                }
            }
        }
        BrutalButton(tr("保存"), {
            // 种子顺序：先按组里的名次，再按组
            val seeded = match.standings.filter { it.key in selected }.sortedWith(compareBy({ it.rank }, { it.pool ?: 0 })).map { it.key }
            onSave(seeded)
            onDismiss()
        }, enabled = selected.size == needed)
    }
}

// MARK: - 我的 → 比赛

@Composable
fun MyMatchesScreen() {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    var matches by remember { mutableStateOf(emptyList<MyMatch>()) }
    var loaded by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try {
            matches = env.night.myMatches()
        } catch (_: RemoteError) {
        }
        loaded = true
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("比赛"), onBack = { env.router.pop() })
        if (loaded && matches.isEmpty()) {
            EmptyStateView(Sym.trophy, tr("还没有比赛"), tint = colors.butter, actionTitle = tr("建一场")) { env.router.open(Route.CreateMatch()) }
        } else {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                matches.forEach { match -> MyMatchRow(match) { env.router.open(Route.Match(match.id)) } }
            }
        }
    }
}

@Composable
private fun MyMatchRow(match: MyMatch, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val status = when {
        match.status == "live" -> tr("进行中")
        match.rank != null -> tr("第 %lld 名", match.rank)
        else -> tr("已结束")
    }
    Row(
        Modifier.fillMaxWidth().pressable(scale = 0.98f, onClick = onClick).sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.trophyFill, fill = colors.butter, size = 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(match.name, style = AppTheme.Typography.bodyBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                tr("%@ · %lld 人 · %@", MatchFormat.title(match.format, match.play), match.players, DateText.monthDay(match.createdAt.toEpochMilli())),
                style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        TagPill(status, fill = if (match.status == "live") colors.lime else colors.surfaceMuted, foreground = colors.onAccent)
    }
}

