package com.badie.app.features.rooms

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.LoadingDots
import com.badie.app.design.RulesButton
import com.badie.app.design.SectionTitle
import com.badie.app.design.StickerTextField
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.games.Flow
import com.badie.app.l10n.tr
import com.badie.app.models.Coordinate
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.PlayEvent
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.isSameDay
import com.badie.app.models.title
import com.badie.app.models.zoned
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.delay
import java.util.Locale

// 开房间、改房间时用的几个控件：日期条、时间和等级步进器、项目、选球馆、选球友

// MARK: - 日期条（未来 N 天）。对应 iPhone 的 DateStrip（DesignSystem/Feedback.swift）

@Composable
fun DateStrip(days: List<Long>, selection: Long, onSelect: (Long) -> Unit, modifier: Modifier = Modifier) {
    val haptics = rememberHaptics()
    Row(
        modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        for (day in days) {
            DateChip(day, isSameDay(day, selection)) {
                haptics.selection()
                onSelect(day)
            }
        }
    }
}

@Composable
private fun DateChip(day: Long, isSelected: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val ink = if (isSelected) colors.onAccent else colors.ink
    val label = if (isSameDay(day, System.currentTimeMillis())) tr("今天") else DateText.weekday(day)
    val spoken = DateText.relativeDay(day)
    Column(
        Modifier
            .pressable(onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = spoken; selected = isSelected }
            .width(52.dp)
            .sticker(if (isSelected) colors.lime else colors.surface, radius = 16.dp, shadow = if (isSelected) AppTheme.Elevation.low else AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(label, style = AppTheme.Typography.caption, color = ink, maxLines = 1)
        Text("${day.zoned().dayOfMonth}", style = rounded(20, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = ink)
    }
}

/** 今天起往后 [count] 天（每天 0 点） */
fun upcomingDays(count: Int = com.badie.app.models.TimeSlotConstants.MAXIMUM_DAYS_AHEAD, now: Long = System.currentTimeMillis()): List<Long> {
    val today = com.badie.app.models.startOfDay(now)
    return (0 until count).map { com.badie.app.models.addingDays(today, it) }
}

// MARK: - 时间步进器（30 分钟一档）。对应 iPhone 的 TimeStepper（MatchSetupView.swift）

@Composable
fun TimeStepper(title: String, minutes: Int, range: IntRange, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var choosing by remember { mutableStateOf(false) }
    fun adjust(delta: Int) {
        val next = minutes + delta
        if (next !in range) return
        haptics.selection()
        onChange(next)
    }
    val spoken = tr("%lld 点 %@ 分", minutes / 60, String.format(Locale.ROOT, "%02d", minutes % 60))
    val label = tr("%@时间", title)
    Column(
        modifier
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm, horizontal = AppTheme.Spacing.xs)
            .semantics { contentDescription = label; stateDescription = spoken },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = AppTheme.Typography.caption, color = colors.inkSecondary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepIcon(Sym.minus, minutes - 30 in range) { adjust(-30) }
            // 点时间直接从列表里选，加减按钮微调
            Box(Modifier.weight(1f).defaultMinSize(minHeight = 40.dp).pressable(scale = 0.96f) { choosing = true }, contentAlignment = Alignment.Center) {
                com.badie.app.design.FitText(clock(minutes), style = rounded(22, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.ink)
                DropdownMenu(choosing, { choosing = false }, containerColor = colors.surface) {
                    for (option in range step 30) {
                        DropdownMenuItem(
                            text = { Text(clock(option), style = AppTheme.Typography.bodyBold, color = colors.ink) },
                            trailingIcon = if (option == minutes) ({ Symbol(Sym.checkmark, size = 14, tint = colors.ink) }) else null,
                            onClick = {
                                haptics.selection()
                                onChange(option)
                                choosing = false
                            },
                        )
                    }
                }
            }
            StepIcon(Sym.plus, minutes + 30 in range) { adjust(30) }
        }
    }
}

private fun clock(minutes: Int) = String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)

@Composable
private fun StepIcon(icon: com.badie.app.design.SymbolId, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(40.dp).pressable(scale = 0.85f, enabled = enabled, onClick = onClick).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Symbol(icon, size = 14, tint = if (enabled) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
    }
}

/** 一天里的 [startMinutes]–[endMinutes]（结束 24:00 = 第二天 0 点） */
fun slotOn(day: Long, startMinutes: Int, endMinutes: Int): TimeSlot? =
    TimeSlot.on(day, startHour = startMinutes / 60, startMinute = startMinutes % 60, endHour = endMinutes / 60, endMinute = endMinutes % 60)

// MARK: - 等级步进器。对应 iPhone 的 LevelStepper（CreateRoomView.swift）

@Composable
fun LevelStepper(title: String, level: Int, range: IntRange, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val label = tr("%@等级", title)
    val spoken = tr("%lld 级", level)
    Row(
        modifier
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = 4.dp)
            .semantics { contentDescription = label; stateDescription = spoken },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepIcon(Sym.minus, level - 1 in range) {
            haptics.selection()
            onChange(level - 1)
        }
        Column(Modifier.weight(1f).clearAndSetSemantics {}, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, style = AppTheme.Typography.caption, color = colors.inkSecondary)
            Text("Lv.$level", style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink)
        }
        StepIcon(Sym.plus, level + 1 in range) {
            haptics.selection()
            onChange(level + 1)
        }
    }
}

// MARK: - 项目。对应 iPhone 的 EventPicker（DesignSystem/GenderViews.swift）

@Composable
fun EventPicker(mode: GameMode, gender: Gender, partner: Gender?, selection: PlayEvent?, onSelect: (PlayEvent?) -> Unit) {
    val choices = PlayEvent.choices(mode, gender, partner)
    Flow {
        for (event in choices) {
            ChoiceChip(event?.title(mode) ?: tr("不限"), selection == event) { onSelect(event) }
        }
        RulesButton(tr("项目"), choices.map { PlayEvent.caption(it) })
    }
}

/** 公开局、球群按参加的人算等级：只限女生按女子等级，男女都能来时女子等级按低 1.5 级换算。对应 iPhone 的 User.level(for:) */
fun User.level(audience: Gender?): Int {
    val offset = if (gender == Gender.Female && audience != Gender.Female) Gender.WOMEN_OFFSET else 0.0
    return com.badie.app.models.roundHalfAway(displayTier.rating - offset).toInt().coerceIn(1, 9)
}

/** 按项目算：混双男生和男生比、女生和女生比，用自己的等级；其余同上。对应 iPhone 的 User.level(in:) */
fun User.level(event: PlayEvent?): Int =
    if (event == PlayEvent.Mixed) com.badie.app.models.roundHalfAway(displayTier.rating).toInt().coerceIn(1, 9) else level(event?.gender)

// MARK: - 选一家球馆（开房间、改房间时）。iPhone 用的是球馆库的 VenuePickerView 单选模式；这里是简化版：附近的加搜索

@Composable
fun VenuePickerSheet(selectedId: String?, onPick: (Venue) -> Unit, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val backend = env.appState.backend
    val colors = AppTheme.colors
    var query by remember { mutableStateOf("") }
    var center by remember { mutableStateOf<Coordinate?>(null) }
    var nearby by remember { mutableStateOf<List<Venue>?>(null) }
    var hits by remember { mutableStateOf<List<Venue>?>(null) }
    LaunchedEffect(Unit) {
        val here = env.roomManager.center()
        center = here
        nearby = try {
            backend.venuesNear(here, env.roomManager.radiusKm)
        } catch (_: RemoteError) {
            emptyList()
        }
    }
    // 打字时等一下再搜（连续输入只搜最后一次）
    LaunchedEffect(query) {
        if (query.isBlank()) {
            hits = null
            return@LaunchedEffect
        }
        delay(300)
        hits = try {
            backend.searchVenues(query)
        } catch (_: RemoteError) {
            emptyList()
        }
    }
    Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("选择球馆"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        StickerTextField(
            query, { query = it }, tr("球馆名、简称（如 LABC）或地址"),
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen),
            style = AppTheme.Typography.body,
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
        )
        val list = hits ?: nearby
        when {
            list == null -> Box(Modifier.fillMaxWidth().padding(AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) { LoadingDots() }
            list.isEmpty() && hits != null -> EmptyStateView(Sym.magnifyingglass, tr("没有找到“%@”", query.trim()))
            list.isEmpty() -> Row(
                Modifier.padding(AppTheme.Spacing.screen), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Symbol(Sym.mappinSlash, size = 13, tint = colors.inkSecondary)
                Text(
                    tr("%@还没有收录的球馆", tr("%@内", DistanceFormatter.radius(env.roomManager.radiusKm))),
                    style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary,
                )
            }
            else -> LazyColumn(
                Modifier.fillMaxWidth(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(AppTheme.Spacing.screen),
            ) {
                if (hits == null) {
                    item { SectionTitle(tr("附近"), Modifier.padding(bottom = AppTheme.Spacing.sm), detail = tr("%@内", DistanceFormatter.radius(env.roomManager.radiusKm))) }
                }
                items(list, key = { it.id }) { venue ->
                    PickerVenueRow(venue, center, venue.id == selectedId) { onPick(venue) }
                    InsetDivider()
                }
            }
        }
    }
}

@Composable
private fun PickerVenueRow(venue: Venue, center: Coordinate?, isOn: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 64.dp)
            .pressable(scale = 0.98f) {
                haptics.selection()
                onClick()
            }
            .semantics(mergeDescendants = true) { selected = isOn }
            .padding(vertical = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.figureBadminton, fill = if (isOn) colors.lime else colors.surfaceMuted, size = 42.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(venue.name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                if (center != null) {
                    Text(DistanceFormatter.string(venue.distanceKm(center)), style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = colors.inkSecondary)
                }
            }
            Text(
                listOf(venue.compactAddress, venue.pricingText).filter { it.isNotEmpty() }.joinToString(" · "),
                style = AppTheme.Typography.footnote, color = colors.inkSecondary,
            )
        }
        if (isOn) Symbol(Sym.checkmarkCircleFill, size = 22, tint = colors.ink)
    }
}

// MARK: - 选球友（邀请进房间）。对应 iPhone 的 FriendPickerSheet（JoinRoomView.swift）

@Composable
fun FriendPickerSheet(title: String, maxSelection: Int, excluded: Set<String>, onConfirm: (List<String>) -> Unit, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var query by remember { mutableStateOf("") }
    var friends by remember { mutableStateOf<List<User>?>(null) }
    var selection by remember { mutableStateOf(listOf<String>()) }
    LaunchedEffect(Unit) {
        // TODO：球友列表归 FriendManager（features/social），搬好后改用那边的；现在直接读 my_friends
        friends = try {
            env.roomManager.friends()
        } catch (_: RemoteError) {
            emptyList()
        }
    }
    val shown = friends.orEmpty().filter { it.id !in excluded && (query.isBlank() || it.nickname.contains(query.trim(), ignoreCase = true)) }
    Column(
        Modifier.fillMaxWidth().fillMaxHeight(0.92f).padding(horizontal = AppTheme.Spacing.screen),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        StickerTextField(
            query, { query = it }, tr("搜索球友昵称"), style = AppTheme.Typography.body,
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
            trailing = { Symbol(Sym.magnifyingglass, size = 16, tint = colors.inkSecondary) },
        )
        Text(tr("已选 %lld/%lld", selection.size, maxSelection), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
        LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
            if (friends != null && shown.isEmpty()) item { EmptyStateView(Sym.person2, tr("没有可邀请的球友")) }
            items(shown, key = { it.id }) { friend ->
                val chosen = friend.id in selection
                val full = !chosen && selection.size >= maxSelection
                Row(
                    Modifier
                        .fillMaxWidth()
                        .pressable(scale = 0.98f) {
                            haptics.selection()
                            if (chosen) selection = selection - friend.id else if (!full) selection = selection + friend.id
                        }
                        .semantics(mergeDescendants = true) { selected = chosen }
                        .alpha(if (full) 0.45f else 1f)
                        .padding(vertical = AppTheme.Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    AvatarView(friend, size = 44.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(friend.nickname, style = AppTheme.Typography.bodyBold, color = colors.ink)
                        Text("${friend.displayLevelText} · ${friend.publicSummary}", style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                    }
                    Symbol(if (chosen) Sym.checkmarkCircleFill else Sym.circle, size = 24, tint = if (chosen) colors.ink else colors.inkTertiary)
                }
            }
        }
        BrutalButton(tr("邀请 %lld 位球友", selection.size), { onConfirm(selection) }, Modifier.padding(bottom = AppTheme.Spacing.md), enabled = selection.isNotEmpty())
    }
}
