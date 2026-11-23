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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.InsetDivider
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.night.CourtStepper
import com.badie.app.features.night.NightBottomBar
import com.badie.app.features.night.TextInputDialog
import com.badie.app.features.night.showClubError
import com.badie.app.features.rooms.VenuePickerSheet
import com.badie.app.features.social.ToggleRow
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.MatchFormat
import com.badie.app.models.MatchPlay
import com.badie.app.models.MatchPreview
import com.badie.app.models.MatchSetup
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

// 比赛 · 新建。对应 iPhone 的 Features/Matches/MatchCreateView.swift。
// “+”菜单的“比赛 · 循环赛、淘汰赛”，或者当晚页的“用今晚的名单开一场”（到场的人预先填好，用报名 id）。
// 一屏往下填：名字、球馆、场地数、参赛的人、单打还是双打、赛制、打几轮、每局几分；底部是预计几轮几分钟和“开始”

/** 参赛的一个人：球友、当晚的报名，或者输的名字（访客） */
data class MatchEntry(
    val id: String,
    val name: String,
    val userId: String? = null,
    val signupId: String? = null,
    val guest: Boolean = false,
) {
    /** create_match 的 p_players 里的一项 */
    val payload: Map<String, String>
        get() = when {
            signupId != null -> mapOf("signup_id" to signupId)
            userId != null -> mapOf("user_id" to userId)
            else -> mapOf("name" to name)
        }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MatchCreateScreen(sessionId: String? = null) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()

    var name by remember { mutableStateOf("") }
    var venue by remember { mutableStateOf<Venue?>(null) }
    var showsVenuePicker by remember { mutableStateOf(false) }
    var courts by remember { mutableIntStateOf(2) }
    val entries = remember { mutableStateListOf<MatchEntry>() }
    var play by remember { mutableStateOf(MatchPlay.Rotating) }
    var chosenFormat by remember { mutableStateOf(MatchFormat.RoundRobin) }
    var pools by remember { mutableIntStateOf(2) }
    var advance by remember { mutableIntStateOf(1) }
    var thirdPlace by remember { mutableStateOf(false) }
    var points by remember { mutableIntStateOf(21) }
    var bestOf by remember { mutableIntStateOf(1) }
    var winByTwo by remember { mutableStateOf(true) }
    // 打几轮（没选过 = 默认）
    var chosenRounds by remember { mutableStateOf<Int?>(null) }
    var preview by remember { mutableStateOf<MatchPreview?>(null) }
    var showsPicker by remember { mutableStateOf(false) }
    var showsNameEntry by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }

    // 默认的名字：“11月18日 比赛”
    val defaultName = tr("%@ 比赛", DateText.monthDay(System.currentTimeMillis()))
    // 轮换搭档只有循环
    val format = if (play == MatchPlay.Rotating) MatchFormat.RoundRobin else chosenFormat
    // 人数不对时的提示（服务器还会再查一次）
    val countProblem = MatchSetup.countProblem(format, play, entries.size, pools, advance)
    // 打几轮：没选过用默认，超出能选的收回来
    val rounds = preview?.takeIf { format.byRounds }?.let { minOf(chosenRounds ?: it.defaultRounds, it.maxRounds) }
    val fallbackProblem = tr("要 2–64 人。")

    LaunchedEffect(Unit) {
        if (sessionId != null) {
            // 从当晚开：到场的人预先填好（用报名 id），场地数也一样
            val night = try {
                env.night.nightState(sessionId)
            } catch (_: RemoteError) {
                null
            } ?: return@LaunchedEffect
            courts = night.courts
            entries.clear()
            entries.addAll(night.people.filter { it.status == "here" }.map { MatchEntry(it.id, it.name, it.userId, signupId = it.id, guest = it.guest) })
        } else {
            env.appState.currentUser?.let { me -> if (entries.isEmpty()) entries.add(MatchEntry(me.id, me.nickname, me.id)) }
        }
    }
    LaunchedEffect(format, play, entries.size, courts, points, bestOf, pools, advance, chosenRounds, thirdPlace) {
        if (countProblem != null) {
            preview = null
            return@LaunchedEffect
        }
        delay(300)
        preview = try {
            env.night.matchPreview(
                format, play, entries.size, courts, points, bestOf,
                pools = if (format == MatchFormat.Groups) pools else null, advance = if (format == MatchFormat.Groups) advance else null,
                rounds = if (format.byRounds) chosenRounds else null, thirdPlace = format.hasKnockout && thirdPlace,
            )
        } catch (_: RemoteError) {
            null
        }
    }

    fun create() {
        saving = true
        val title = name.trim()
        scope.launch {
            try {
                val id = env.night.createMatch(
                    if (title.isEmpty()) defaultName else title, venue?.id, courts, format, play, points, bestOf, winByTwo,
                    entries.map { it.payload }, rounds, if (format == MatchFormat.Groups) pools else null,
                    if (format == MatchFormat.Groups) advance else null, format.hasKnockout && thirdPlace, sessionId,
                )
                haptics.success()
                env.router.pop()
                // 从当晚开的：回到当晚页的“比赛”
                if (sessionId == null) env.router.open(Route.Match(id))
            } catch (error: RemoteError) {
                if (error is RemoteError.Server && error.code == "invalid_player_count") {
                    env.appState.showToast(countProblem ?: fallbackProblem, Toast.Style.Error)
                } else {
                    env.appState.showClubError(error)
                }
            }
            saving = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("比赛"), onBack = { env.router.pop() })
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            // 名字、球馆、场地
            Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)) {
                Row(
                    Modifier.defaultMinSize(minHeight = 52.dp).padding(horizontal = AppTheme.Spacing.lg),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    Text(tr("名字"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.width(56.dp))
                    val label = tr("名字")
                    BasicTextField(
                        name, { name = it }, Modifier.weight(1f).semantics { contentDescription = label },
                        textStyle = AppTheme.Typography.body.copy(color = colors.ink), singleLine = true, cursorBrush = SolidColor(colors.ink),
                        decorationBox = { field ->
                            Box(contentAlignment = Alignment.CenterStart) {
                                if (name.isEmpty()) Text(defaultName, style = AppTheme.Typography.body, color = colors.inkTertiary, maxLines = 1)
                                field()
                            }
                        },
                    )
                }
                InsetDivider()
                Row(
                    Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).pressable(scale = 1f) { showsVenuePicker = true }.padding(horizontal = AppTheme.Spacing.lg),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    Text(tr("球馆"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.width(56.dp))
                    Text(
                        venue?.name ?: tr("选填"), style = AppTheme.Typography.body, color = if (venue == null) colors.inkTertiary else colors.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                    Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
                }
                InsetDivider()
                CourtStepper(courts, { courts = it }, Modifier.padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs))
            }

            // 参赛的人
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Text(tr("参赛的人"), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.semantics { heading() })
                    Text(tr("%lld 人", entries.size), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                }
                if (entries.isNotEmpty()) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        entries.toList().forEach { entry ->
                            val label = tr("移除%@", entry.name)
                            EntryChip(entry, Modifier.pressable { entries.removeAll { it.id == entry.id } }.semantics { contentDescription = label })
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    BrutalButton({ showsPicker = true }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium) {
                        Symbol(Sym.personBadgePlus, size = 15)
                        Spacer(Modifier.size(AppTheme.Spacing.sm))
                        Text(tr("选球友"))
                    }
                    BrutalButton({ showsNameEntry = true }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium) {
                        Symbol(Sym.pencil, size = 15)
                        Spacer(Modifier.size(AppTheme.Spacing.sm))
                        Text(tr("输入名字"))
                    }
                }
            }

            // 赛制
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(tr("赛制"), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.semantics { heading() })
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    MatchPlay.entries.forEach { option ->
                        ChoiceButton(option.title, option == play, Modifier.weight(1f)) {
                            play = option
                            chosenRounds = null
                        }
                    }
                }
                if (play != MatchPlay.Rotating) {
                    MatchFormat.entries.chunked(2).forEach { pair ->
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            pair.forEach { option ->
                                ChoiceButton(option.title, option == format, Modifier.weight(1f)) {
                                    chosenFormat = option
                                    chosenRounds = null
                                }
                            }
                        }
                    }
                }
                // 赛制下面的设置：分几组、每组前几名、打几轮、三四名
                val currentPreview = preview
                if (format.hasKnockout || rounds != null) {
                    Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)) {
                        if (format == MatchFormat.Groups) {
                            StepperRow(tr("几组"), pools, 2..8) { pools = it }
                            InsetDivider()
                            Row(
                                Modifier.defaultMinSize(minHeight = 56.dp).padding(horizontal = AppTheme.Spacing.lg),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                            ) {
                                Text(tr("每组前几名出线"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
                                ChoiceChip("1", advance == 1) { advance = 1 }
                                ChoiceChip("2", advance == 2) { advance = 2 }
                            }
                        }
                        if (rounds != null && currentPreview != null) {
                            StepperRow(tr("打几轮"), rounds, 1..maxOf(1, currentPreview.maxRounds)) { chosenRounds = it }
                            if (format == MatchFormat.RoundRobin && play != MatchPlay.Rotating && currentPreview.fullRounds > 0) {
                                Text(
                                    tr("循环打满一遍是 %lld 轮。", currentPreview.fullRounds), style = AppTheme.Typography.footnote, color = colors.inkSecondary,
                                    modifier = Modifier.padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.md),
                                )
                            }
                        }
                        if (format.hasKnockout) {
                            if (format == MatchFormat.Groups) InsetDivider()
                            ToggleRow(tr("打三四名"), thirdPlace, { thirdPlace = it }, Modifier.padding(horizontal = AppTheme.Spacing.lg).defaultMinSize(minHeight = 56.dp))
                        }
                    }
                }
            }

            // 每局几分
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(tr("每局"), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.semantics { heading() })
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    SegmentedSticker(listOf(21, 15, 11), points, { points = it }, Modifier.widthIn(max = 180.dp)) { "$it" }
                    SegmentedSticker(listOf(1, 3), bestOf, { bestOf = it }, Modifier.weight(1f)) { if (it == 1) tr("一局") else tr("三局两胜") }
                }
                ToggleRow(tr("领先 2 分"), winByTwo, { winByTwo = it }, Modifier.defaultMinSize(minHeight = 44.dp))
            }
        }

        // 底部：预计、开始
        NightBottomBar {
            preview?.let {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Symbol(Sym.clock, size = 15, tint = colors.ink)
                    Text(tr("预计 %lld 轮，约 %lld 分钟", it.rounds, it.minutes.toInt()), style = AppTheme.Typography.subheadlineBold, color = colors.ink)
                }
            }
            if (countProblem != null && entries.isNotEmpty()) {
                Text(countProblem, style = AppTheme.Typography.caption, color = colors.danger, modifier = Modifier.fillMaxWidth())
            }
            Spacer(Modifier.height(AppTheme.Spacing.xs))
            BrutalButton(tr("开始"), ::create, enabled = !saving && countProblem == null)
        }
    }

    if (showsVenuePicker) {
        BadieSheet(onDismiss = { showsVenuePicker = false }) { dismiss ->
            VenuePickerSheet(venue?.id, onPick = {
                venue = it
                dismiss()
            }, onDismiss = dismiss)
        }
    }
    if (showsPicker) {
        SheetScaffold(onDismiss = { showsPicker = false }, fullHeight = true) {
            MatchPlayerPicker(candidates(), entries.mapNotNull { it.userId }.toSet(), onDone = { showsPicker = false }) { user ->
                val index = entries.indexOfFirst { it.userId == user.id }
                if (index >= 0) entries.removeAt(index) else if (entries.size < 64) entries.add(MatchEntry(user.id, user.nickname, user.id))
            }
        }
    }
    if (showsNameEntry) {
        TextInputDialog(tr("输入名字"), tr("加"), onDismiss = { showsNameEntry = false }, placeholder = tr("名字")) { typed ->
            val clean = typed.trim()
            if (clean.isNotEmpty() && entries.size < 64) entries.add(MatchEntry(UUID.randomUUID().toString(), clean.take(24), guest = true))
        }
    }
}

/** 能选的人：自己、球友、球群里的人 */
@Composable
private fun candidates(): List<User> {
    val env = LocalEnv.current
    val seen = mutableSetOf<String>()
    val list = mutableListOf<User>()
    env.appState.currentUser?.let { me ->
        seen.add(me.id)
        list += me
    }
    env.friendManager.friends.forEach { if (seen.add(it.id)) list += it }
    env.groupManager.myGroups.forEach { group ->
        group.memberIds.forEach { id -> env.groupManager.user(id)?.let { user -> if (seen.add(id)) list += user } }
    }
    return list
}

@Composable
private fun EntryChip(entry: MatchEntry, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    // 访客灰色，其余按名字取一个贴纸色
    val fill = if (entry.guest) colors.surfaceMuted else colors.paletteColor(entry.name.sumOf { it.code })
    Row(
        modifier.height(36.dp).background(colors.surface, CircleShape).border(AppTheme.Stroke.hairline, colors.stroke, CircleShape).padding(start = 4.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(28.dp).background(fill, CircleShape).border(AppTheme.Stroke.hairline, colors.stroke, CircleShape), contentAlignment = Alignment.Center) {
            Text(entry.name.take(1).uppercase(), style = rounded(12, FontWeight.Black), color = colors.onAccent)
        }
        Text(entry.name, style = AppTheme.Typography.footnoteBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (entry.guest) TagPill(tr("访客"), fill = colors.mint)
        Symbol(Sym.xmark, size = 10, tint = colors.inkTertiary)
    }
}

@Composable
private fun ChoiceButton(title: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier.defaultMinSize(minHeight = 52.dp)
            .pressable {
                haptics.selection()
                onClick()
            }
            .background(if (selected) colors.inverse else colors.surface, shape)
            .border(AppTheme.Stroke.width, colors.stroke, shape)
            .semantics { this.selected = selected }
            .padding(horizontal = AppTheme.Spacing.sm),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = AppTheme.Typography.subheadlineBold, color = if (selected) colors.onInverse else colors.ink, textAlign = TextAlign.Center)
    }
}

/** 一行：标题、数字、减、加（iPhone 的 Stepper） */
@Composable
private fun StepperRow(title: String, value: Int, range: IntRange, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    // 读屏：“打几轮 −”“打几轮 +”
    val less = "$title \u2212"
    val more = "$title +"
    Row(
        Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
        Text("$value", style = AppTheme.Typography.bodyBold.copy(fontFeatureSettings = "tnum"), color = colors.ink, modifier = Modifier.padding(end = AppTheme.Spacing.sm))
        Box(
            Modifier.size(44.dp).semantics { contentDescription = less }.pressable(enabled = value > range.first) { onChange(maxOf(range.first, value - 1)) },
            contentAlignment = Alignment.Center,
        ) { Symbol(Sym.minus, size = 17, tint = if (value > range.first) colors.ink else colors.inkTertiary) }
        Box(
            Modifier.size(44.dp).semantics { contentDescription = more }.pressable(enabled = value < range.last) { onChange(minOf(range.last, value + 1)) },
            contentAlignment = Alignment.Center,
        ) { Symbol(Sym.plus, size = 17, tint = if (value < range.last) colors.ink else colors.inkTertiary) }
    }
}

// MARK: - 选球友

@Composable
private fun MatchPlayerPicker(candidates: List<User>, selectedIds: Set<String>, onDone: () -> Unit, onToggle: (User) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        Row(
            Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("选球友"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            BrutalButton(tr("完成"), onDone, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl)) {
            if (candidates.isEmpty()) {
                Text(tr("还没有球友。可以输入名字。"), style = AppTheme.Typography.subheadline, color = colors.inkSecondary, modifier = Modifier.padding(top = AppTheme.Spacing.xl))
            }
            candidates.forEach { user ->
                val isSelected = user.id in selectedIds
                Row(
                    Modifier.fillMaxWidth()
                        .pressable(scale = 1f) {
                            haptics.selection()
                            onToggle(user)
                        }
                        .semantics(mergeDescendants = true) { selected = isSelected }
                        .padding(vertical = AppTheme.Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    AvatarView(user, size = 40.dp)
                    Text(user.nickname, style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
                    Symbol(if (isSelected) Sym.checkmarkCircleFill else Sym.circle, size = 24, tint = if (isSelected) colors.success else colors.inkTertiary)
                }
                InsetDivider()
            }
        }
    }
}

