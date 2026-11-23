package com.badie.app.features.night

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.BrutalTextField
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.InsetDivider
import com.badie.app.design.RulesButton
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.groups.SessionPayPanel
import com.badie.app.features.matches.MatchPanel
import com.badie.app.features.social.ToggleRow
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.NightState
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 当晚页：排场 | 比赛 | 收款。对应 iPhone 的 Features/Night/NightView.swift。
// 组织者和帮手从球群页的“排场”进来（帮手没有收款）。数据都在服务器上（night_state），每 10 秒重拉；
// 网差时保留上一份，顶上写“x 分钟前更新”。场边单手用：每片场地一个大的“打完了”。
// （iPhone 的 payOnly，从收款记录点进来的某一场，安卓是 SessionPaymentsScreen，收款这一块两边共用 SessionPayPanel）

enum class NightSegment { Courts, Match, Pay }

@Composable
private fun NightSegment.title(): String = when (this) {
    NightSegment.Courts -> tr("排场")
    NightSegment.Match -> tr("比赛")
    NightSegment.Pay -> tr("收款")
}

/** 点了场上的某个人：从等候的人里换一个上来 */
private data class SwapTarget(val game: NightState.Game, val out: String)

@Composable
fun NightScreen(sessionId: String, opensPay: Boolean = false) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val night = env.night

    var state by remember(sessionId) { mutableStateOf<NightState?>(null) }
    var loaded by remember(sessionId) { mutableStateOf(false) }
    var loadedAt by remember(sessionId) { mutableLongStateOf(System.currentTimeMillis()) }
    var segment by rememberSaveable(sessionId) { mutableStateOf(if (opensPay) NightSegment.Pay else NightSegment.Courts) }
    var payTick by remember { mutableIntStateOf(0) }
    // 撤销条显示到什么时候；服务器给的时间换算成本机时间（两边的钟可能不一样）
    var undoDeadline by remember { mutableStateOf<Long?>(null) }
    var lastUndo by remember { mutableStateOf<java.time.Instant?>(null) }
    var personAction by remember { mutableStateOf<NightState.Person?>(null) }
    var rosterMenu by remember { mutableStateOf<NightState.Person?>(null) }
    var swapTarget by remember { mutableStateOf<SwapTarget?>(null) }
    var showsBoard by remember { mutableStateOf(false) }
    var showsAdd by remember { mutableStateOf(false) }
    var showsSettings by remember { mutableStateOf(false) }

    suspend fun load() {
        try {
            val next = night.nightState(sessionId)
            val until = next?.undoUntil
            if (until != null && until != lastUndo) {
                lastUndo = until
                val left = (until.toEpochMilli() - System.currentTimeMillis()).coerceIn(3_000, 10_000)
                undoDeadline = System.currentTimeMillis() + left
            }
            state = next
            loadedAt = System.currentTimeMillis()
        } catch (_: RemoteError) {
            // 网差：保留上一份
        }
        loaded = true
        if (segment == NightSegment.Pay) payTick++
    }

    /** 做一个操作，出错就提示（场地已经换过了等），之后都重拉一次 */
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

    fun mark(signups: List<String>?, status: String?) = perform { night.nightMark(sessionId, signups, status) }

    fun settings(current: NightState, courts: Int = current.courts, doubles: Boolean = current.doubles, balance: Boolean = current.balance) =
        perform { night.nightSettings(sessionId, courts, doubles, balance) }

    fun finish(game: NightState.Game) {
        haptics.impact()
        perform {
            night.nightFinish(game.id)
            undoDeadline = System.currentTimeMillis() + 10_000
        }
    }

    fun undo() = perform {
        night.nightUndo(sessionId)
        undoDeadline = null
    }

    LaunchedEffect(sessionId) {
        while (true) {
            load()
            delay(10_000)
        }
    }

    Column(Modifier.fillMaxSize()) {
        // 顶部：当晚、时间和到了几人，右边是排场设置
        Box(Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.md), contentAlignment = Alignment.Center) {
            Column(Modifier.padding(horizontal = 56.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(tr("当晚"), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.semantics { heading() })
                state?.let { current ->
                    val range = "${DateText.time(current.startsAt.toEpochMilli())}–${DateText.time(current.endsAt.toEpochMilli())}"
                    Text(tr("%@ · 到了 %lld 人", range, current.hereCount), style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1)
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(Sym.chevronLeft, tr("返回")) { env.router.pop() }
                Spacer(Modifier.weight(1f))
                if (state?.open == true) IconButton(Sym.sliderHorizontal3, tr("排场设置")) { showsSettings = true }
            }
        }
        val current = state
        when {
            current != null -> {
                Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    val segments = if (current.isOrganizer) NightSegment.entries else listOf(NightSegment.Courts, NightSegment.Match)
                    SegmentedSticker(segments, segment, { segment = it; if (it == NightSegment.Pay) payTick++ }) { it.title() }
                    StaleLine(loaded, loadedAt)
                }
                if (segment == NightSegment.Pay && current.isOrganizer) {
                    SessionPayPanel(sessionId, current.startsAt, payTick)
                } else {
                    Column(
                        Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen)
                            .padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.xxl),
                        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
                    ) {
                        if (segment == NightSegment.Match) {
                            MatchSection(current, sessionId, onResume = {
                                perform {
                                    night.nightResume(sessionId)
                                    segment = NightSegment.Courts
                                }
                            })
                        } else {
                            CourtsSection(
                                current,
                                onWatchMatch = { segment = NightSegment.Match },
                                onFinish = ::finish,
                                onSwap = { game, out -> swapTarget = SwapTarget(game, out) },
                                onPerson = { personAction = it },
                                onSettings = { courts, doubles, balance -> settings(current, courts, doubles, balance) },
                                onMark = ::mark,
                                onRosterMenu = { rosterMenu = it },
                            )
                        }
                    }
                    if (segment == NightSegment.Courts) {
                        UndoButton(undoDeadline, Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.sm)) { undo() }
                        if (current.open && !current.matchLive) {
                            NightBottomBar {
                                if (current.started) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                                        BrutalButton({ showsBoard = true }, Modifier.weight(1f), kind = ButtonKind.Secondary, enabled = current.boardCode != null) {
                                            Symbol(Sym.qrcode, size = 16)
                                            Spacer(Modifier.size(AppTheme.Spacing.sm))
                                            Text(tr("二维码"))
                                        }
                                        BrutalButton({ showsAdd = true }, Modifier.weight(1f), kind = ButtonKind.Secondary) {
                                            Symbol(Sym.plus, size = 16)
                                            Spacer(Modifier.size(AppTheme.Spacing.sm))
                                            Text(tr("加人"))
                                        }
                                    }
                                } else {
                                    BrutalButton(tr("开始"), { perform { night.nightStart(sessionId) } })
                                }
                            }
                        }
                    }
                }
            }
            loaded -> EmptyStateView(Sym.sportscourt, tr("只有组织者和帮手能看。"))
            else -> Box(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.ink)
            }
        }
    }

    personAction?.let { person ->
        val options = if (person.status == "here") {
            listOf(
                ChoiceOption(tr("放到下一场")) { perform { night.nightBump(person.id, true) } },
                ChoiceOption(tr("跳过")) { perform { night.nightBump(person.id, false) } },
                ChoiceOption(tr("休息")) { mark(listOf(person.id), "resting") },
            )
        } else {
            listOf(ChoiceOption(tr("到了")) { mark(listOf(person.id), "here") })
        } + ChoiceOption(tr("走了"), destructive = true) { mark(listOf(person.id), "left") }
        ChoiceSheet(person.name, options, onDismiss = { personAction = null })
    }
    rosterMenu?.let { person ->
        ChoiceSheet(
            person.name,
            listOf(
                ChoiceOption(tr("到了")) { mark(listOf(person.id), "here") },
                ChoiceOption(tr("休息")) { mark(listOf(person.id), "resting") },
                ChoiceOption(tr("走了")) { mark(listOf(person.id), "left") },
                ChoiceOption(tr("没到")) { mark(listOf(person.id), null) },
            ),
            onDismiss = { rosterMenu = null },
        )
    }
    val current = state
    swapTarget?.let { target ->
        if (current != null) {
            SheetScaffold(onDismiss = { swapTarget = null }, fullHeight = true) {
                NightSwapSheet(current, target.out, onDismiss = { swapTarget = null }, onSwap = { replacement ->
                    perform {
                        night.nightSwap(target.game.id, target.out, replacement)
                        undoDeadline = System.currentTimeMillis() + 10_000
                    }
                }, onMark = { status -> mark(listOf(target.out), status) })
            }
        }
    }
    if (showsBoard) current?.boardCode?.let { code -> BoardSheet(code) { showsBoard = false } }
    if (showsAdd && current != null) {
        SheetScaffold(onDismiss = { showsAdd = false }, fullHeight = true) {
            Box {
                NightAddSheet(current, onDismiss = { showsAdd = false }, onAdd = { name ->
                    perform {
                        night.nightAdd(sessionId, name)
                        env.appState.showToast(L10n.tr("已加上 %@", name), Toast.Style.Success)
                    }
                }, onArrive = { person ->
                    mark(listOf(person.id), "here")
                    env.appState.showToast(L10n.tr("%@ 到了", person.name), Toast.Style.Success)
                })
                com.badie.app.shell.ToastHost()
            }
        }
    }
    if (showsSettings && current != null) {
        SheetScaffold(onDismiss = { showsSettings = false }, fullHeight = true) {
            NightSettingsSheet(current, me = env.appState.currentUser?.id, onDismiss = { showsSettings = false }) { courts, doubles, balance, helpers ->
                perform {
                    night.nightSettings(sessionId, courts, doubles, balance)
                    if (helpers != null && helpers.toSet() != current.helpers.map { it.id }.toSet()) night.nightHelpers(sessionId, helpers)
                }
            }
        }
    }
}

/** 网差时：上一份是几分钟前的（超过 1 分钟变成提示色） */
@Composable
private fun StaleLine(loaded: Boolean, loadedAt: Long) {
    val now = rememberNow(5_000)
    val age = (now - loadedAt) / 1000
    if (loaded && age > 25) {
        Text(tr("%lld 分钟前更新", maxOf(1L, age / 60)), style = AppTheme.Typography.caption, color = if (age > 60) AppTheme.colors.danger else AppTheme.colors.inkSecondary)
    }
}

// MARK: - 排场

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CourtsSection(
    state: NightState,
    onWatchMatch: () -> Unit,
    onFinish: (NightState.Game) -> Unit,
    onSwap: (NightState.Game, String) -> Unit,
    onPerson: (NightState.Person) -> Unit,
    onSettings: (Int, Boolean, Boolean) -> Unit,
    onMark: (List<String>?, String?) -> Unit,
    onRosterMenu: (NightState.Person) -> Unit,
) {
    val colors = AppTheme.colors
    if (!state.open) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Symbol(Sym.clock, size = 14, tint = colors.inkSecondary)
            Text(tr("不在当晚的时间里。"), style = AppTheme.Typography.subheadlineBold, color = colors.inkSecondary)
        }
    }
    when {
        state.matchLive -> Column(Modifier.card(shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            Text(tr("比赛在打，排场先停。"), style = AppTheme.Typography.bodyBold, color = colors.ink)
            BrutalButton(tr("看比赛"), onWatchMatch, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
        }
        state.started -> {
            state.courtNumbers.forEach { court -> CourtCard(state, court, onFinish, onSwap) }
            NextSection(state)
            WaitingSection(state, onPerson)
        }
        else -> {
            // 开始前：设置和点名
            Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)) {
                CourtStepper(state.courts, { onSettings(it, state.doubles, state.balance) }, Modifier.padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs), enabled = state.open)
                InsetDivider(Modifier.padding(horizontal = AppTheme.Stroke.width))
                SegmentedSticker(listOf(false, true), state.doubles, { if (state.open) onSettings(state.courts, it, state.balance) }, Modifier.padding(AppTheme.Spacing.md)) {
                    if (it) tr("双打") else tr("单打")
                }
                InsetDivider(Modifier.padding(horizontal = AppTheme.Stroke.width))
                ToggleRow(tr("按实力分队"), state.balance, { if (state.open) onSettings(state.courts, state.doubles, it) }, Modifier.padding(horizontal = AppTheme.Spacing.lg).defaultMinSize(minHeight = 56.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Text(tr("名单"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
                    Text(tr("到了 %lld/%lld", state.hereCount, state.people.size), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                    Spacer(Modifier.weight(1f))
                    if (state.open) BrutalButton(tr("全到了"), { onMark(null, "here") }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    state.people.forEach { person -> RosterChip(person, state.open, onMark, onRosterMenu) }
                }
                Text(tr("点一下标到了，按住有更多选项。"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
            }
        }
    }
}

@Composable
private fun CourtCard(state: NightState, court: Int, onFinish: (NightState.Game) -> Unit, onSwap: (NightState.Game, String) -> Unit) {
    val colors = AppTheme.colors
    val game = state.games.firstOrNull { it.court == court }
    Row(
        Modifier.fillMaxWidth()
            .sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = if (game == null) AppTheme.Elevation.none else AppTheme.Elevation.card)
            .padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.md, top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                CourtTag(court)
                if (game != null) {
                    val now = rememberNow(30_000)
                    Text(tr("%lld 分钟", maxOf(0L, (now - game.startedAt.toEpochMilli()) / 60_000)), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                }
            }
            if (game != null) {
                val (a, b) = state.sides(game.players)
                SideLine(state, game, a, onSwap)
                SideLine(state, game, b, onSwap)
            } else {
                Text(tr("等人"), style = AppTheme.Typography.title3, color = colors.inkTertiary)
            }
        }
        if (game != null && state.open) BigActionButton(tr("打完了")) { onFinish(game) }
    }
}

/** 一队的名字：点名字换人 */
@Composable
private fun SideLine(state: NightState, game: NightState.Game, ids: List<String>, onSwap: (NightState.Game, String) -> Unit) {
    val colors = AppTheme.colors
    val style = rounded(20, FontWeight.ExtraBold)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ids.forEachIndexed { index, id ->
            if (index > 0) Text("·", style = style, color = colors.inkTertiary)
            Text(
                state.name(id), style = style, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false).pressable(scale = 1f, enabled = state.open) { onSwap(game, id) },
            )
        }
    }
}

@Composable
private fun NextSection(state: NightState) {
    if (state.next.isEmpty()) return
    Column(
        Modifier.fillMaxWidth().sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(tr("接下来"), style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
        state.next.forEach { players ->
            val (a, b) = state.sides(players)
            MatchupLine(a.map(state::name), b.map(state::name))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WaitingSection(state: NightState, onPerson: (NightState.Person) -> Unit) {
    val colors = AppTheme.colors
    val waiting = state.waiting
    val resting = state.people.filter { it.status == "resting" }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(tr("等候 · 今晚打了几场"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
        if (waiting.isEmpty() && resting.isEmpty()) Text(tr("没人在等"), style = AppTheme.Typography.footnote, color = colors.inkTertiary)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            waiting.forEach { person ->
                NameChip(
                    person.name, Modifier.pressable(enabled = state.open) { onPerson(person) },
                    count = person.games, note = if (person.nextUp) tr("下一场") else null,
                )
            }
            resting.forEach { person ->
                NameChip(person.name, Modifier.pressable(enabled = state.open) { onPerson(person) }, note = tr("休息"), fill = colors.surfaceMuted, dimmed = true)
            }
        }
    }
}

/** 点一下：到了 ↔ 没到；按住：到了 / 休息 / 走了 / 没到 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RosterChip(person: NightState.Person, enabled: Boolean, onMark: (List<String>?, String?) -> Unit, onMenu: (NightState.Person) -> Unit) {
    val colors = AppTheme.colors
    val note = when (person.status) {
        "here" -> tr("到了")
        "resting" -> tr("休息")
        "left" -> tr("走了")
        else -> if (person.waitlisted) tr("候补") else tr("没到")
    }
    val fill = when (person.status) {
        "here" -> colors.mint
        "resting" -> colors.butter
        "left" -> colors.surfaceMuted
        else -> colors.surface
    }
    val label = "${person.name} $note"
    NameChip(
        person.name,
        Modifier
            .combinedClickable(
                remember { MutableInteractionSource() }, indication = null, enabled = enabled, role = Role.Button,
                onLongClick = { onMenu(person) },
            ) { onMark(listOf(person.id), if (person.status == "here") null else "here") }
            .semantics(mergeDescendants = true) { contentDescription = label },
        note = note, fill = fill, dimmed = person.status == "absent" || person.status == "left",
    )
}

// MARK: - 比赛

@Composable
private fun MatchSection(state: NightState, sessionId: String, onResume: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val matchId = state.matchId
    if (matchId != null) {
        if (!state.matchLive && state.open) BrutalButton(tr("回到排场"), onResume)
        MatchPanel(matchId, embedded = true)
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            Text(tr("用到场的人打一轮比赛，排场先停。"), style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
            BrutalButton(tr("用今晚的名单开一场"), { env.router.open(Route.CreateMatch(sessionId)) }, enabled = state.open)
        }
    }
}

// MARK: - 换人

@Composable
private fun NightSwapSheet(state: NightState, out: String, onDismiss: () -> Unit, onSwap: (String) -> Unit, onMark: (String) -> Unit) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("换下 %@", state.name(out)), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        if (state.waiting.isEmpty()) Text(tr("没人在等"), style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
        state.waiting.forEach { person ->
            Row(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp)
                    .pressable(scale = 0.98f) {
                        onSwap(person.id)
                        onDismiss()
                    }
                    .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(person.name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                Text(tr("今晚 %lld 场", person.games), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            }
        }
        Row(Modifier.padding(top = AppTheme.Spacing.sm), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            BrutalButton(tr("打完这场休息"), {
                onMark("resting")
                onDismiss()
            }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium)
            BrutalButton(tr("打完这场走"), {
                onMark("left")
                onDismiss()
            }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium)
        }
    }
}

// MARK: - 加人：候补和没到的人排前面，再输名字

@Composable
private fun NightAddSheet(state: NightState, onDismiss: () -> Unit, onAdd: (String) -> Unit, onArrive: (NightState.Person) -> Unit) {
    val colors = AppTheme.colors
    var name by remember { mutableStateOf("") }
    val trimmed = name.trim()
    // 还没到场的人：候补、没到在前，再是休息、走了的
    val order = mapOf("absent" to 0, "resting" to 1, "left" to 2)
    val candidates = state.people.filter { it.status != "here" }.withIndex().sortedWith(
        compareBy<IndexedValue<NightState.Person>> { (if (it.value.waitlisted) -1 else 0) + (order[it.value.status] ?: 0) * 2 }.thenBy { it.index },
    ).map { it.value }
    val typed = trimmed.lowercase()
    val sameName = typed.isNotEmpty() && state.people.any { person ->
        val existing = person.name.lowercase()
        existing == typed || existing.startsWith("$typed ")
    }
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("加人"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        candidates.forEach { person ->
            val note = when {
                person.waitlisted -> tr("候补")
                person.status == "resting" -> tr("休息")
                person.status == "left" -> tr("走了")
                else -> tr("没到")
            }
            Row(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).pressable(scale = 0.98f) { onArrive(person) }
                    .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                Text(person.name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                Text(note, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                Symbol(Sym.plusCircleFill, size = 22, tint = colors.ink)
            }
        }
        Column(Modifier.padding(top = AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalTextField(tr("名单上没有的人"), tr("名字"), name, { name = it }, Modifier.weight(1f), characterLimit = 24)
                BrutalButton(tr("加"), {
                    onAdd(trimmed)
                    name = ""
                }, kind = ButtonKind.Secondary, fullWidth = false, enabled = trimmed.isNotEmpty() && trimmed.codePointCount(0, trimmed.length) <= 24)
            }
            if (sameName) Text(tr("名单上已经有叫 %@ 的人。", trimmed), style = AppTheme.Typography.caption, color = colors.inkSecondary)
        }
    }
}

// MARK: - 设置：场地数、单双打、按实力分队、帮手

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun NightSettingsSheet(state: NightState, me: String?, onDismiss: () -> Unit, onSave: (Int, Boolean, Boolean, List<String>?) -> Unit) {
    val colors = AppTheme.colors
    var courts by remember { mutableIntStateOf(state.courts) }
    var doubles by remember { mutableStateOf(state.doubles) }
    var balance by remember { mutableStateOf(state.balance) }
    var helpers by remember { mutableStateOf(state.helpers.map { it.id }.toSet()) }
    // 帮手从到场的注册用户里选
    val candidates = state.people.filter { it.status == "here" && it.userId != null && it.userId != me }
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            Row(Modifier.padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
                Text(tr("排场设置"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
                IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
            }
            Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)) {
                CourtStepper(courts, { courts = it }, Modifier.padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs))
                InsetDivider(Modifier.padding(horizontal = AppTheme.Stroke.width))
                SegmentedSticker(listOf(false, true), doubles, { doubles = it }, Modifier.padding(AppTheme.Spacing.md)) { if (it) tr("双打") else tr("单打") }
                InsetDivider(Modifier.padding(horizontal = AppTheme.Stroke.width))
                ToggleRow(tr("按实力分队"), balance, { balance = it }, Modifier.padding(horizontal = AppTheme.Spacing.lg).defaultMinSize(minHeight = 56.dp))
            }
            if (state.isOrganizer) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                        Text(tr("帮手"), style = AppTheme.Typography.headline, color = colors.ink)
                        RulesButton(tr("帮手"), listOf(tr("能排场、加人、输比分。"), tr("不能收款，也不能结束或删除。"), tr("最多 3 个，只在今晚有效。")))
                    }
                    if (candidates.isEmpty()) Text(tr("到场的注册用户才能当帮手。"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        candidates.forEach { person ->
                            val userId = person.userId ?: return@forEach
                            val selected = userId in helpers
                            ChoiceChip(person.name, selected, icon = if (selected) Sym.checkmark else null) {
                                helpers = when {
                                    selected -> helpers - userId
                                    helpers.size < 3 -> helpers + userId
                                    else -> helpers
                                }
                            }
                        }
                    }
                }
            }
        }
        BrutalButton(tr("保存"), {
            onSave(courts, doubles, balance, if (state.isOrganizer) helpers.toList() else null)
            onDismiss()
        }, Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.md))
    }
}
