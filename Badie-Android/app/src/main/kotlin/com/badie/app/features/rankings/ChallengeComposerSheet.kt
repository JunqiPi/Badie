package com.badie.app.features.rankings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
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
import com.badie.app.design.NoticeBanner
import com.badie.app.design.RulesButton
import com.badie.app.design.SectionTitle
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StickerTextField
import com.badie.app.design.BrutalTextField
import com.badie.app.design.FitText
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.Challenge
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.GameMode
import com.badie.app.models.TimeSlot
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.addingDays
import com.badie.app.models.isSameDay
import com.badie.app.models.startOfDay
import com.badie.app.models.zoned
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import androidx.compose.ui.text.font.FontWeight

/**
 * 向某人发起挑战（半屏弹层的内容）：单打或双打（双打从球友里选搭档）、球馆、日期和起止时间、留言。
 * 球友资料弹层（features/social）会调它，名字和参数不要改。
 * 对应 iPhone 的 Features/Rankings/ChallengeViews.swift 里的 ChallengeComposer
 */
@Composable
fun ChallengeComposerSheet(targetId: String, onDismiss: () -> Unit) = ChallengeComposer(targetId, onDismiss)

/** [initialMode]：截图用，先选好单打或双打 */
@Composable
internal fun ChallengeComposer(targetId: String, onDismiss: () -> Unit, initialMode: GameMode = GameMode.Singles) {
    val env = LocalEnv.current
    val appState = env.appState
    val manager = rememberRankingManager()
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()

    var courtId by remember { mutableStateOf<String?>(null) }
    var day by remember { mutableLongStateOf(startOfDay(System.currentTimeMillis())) }
    var startMinutes by remember { mutableIntStateOf(19 * 60) }
    var endMinutes by remember { mutableIntStateOf(21 * 60) }
    var message by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(initialMode) }
    var partnerId by remember { mutableStateOf<String?>(null) }
    var showCourtPicker by remember { mutableStateOf(false) }
    var isSending by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val suggested = TimeSlot.suggestedDefault()
        val start = suggested.startTime.zoned()
        day = startOfDay(suggested.startTime)
        startMinutes = start.hour * 60 + start.minute
        endMinutes = minOf(24 * 60, startMinutes + 120)
        launch { quietly { manager.loadPlayer(targetId) } }
        launch { quietly { env.friendManager.refreshFriends() } }
        quietly { manager.loadVenues() }
        if (courtId == null) courtId = manager.favoriteVenues.firstOrNull()?.id ?: manager.nearbyVenues.firstOrNull()?.id
    }

    val target = manager.user(targetId)
    // 搭档只能是我的球友，且不能是被挑战的人
    val partnerOptions = env.friendManager.friends.filter { it.id != targetId }
    val court = courtId?.let(manager::venue)
    val slot = TimeSlot.on(day, startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    val slotError = slot?.validate()?.errorMessage
    val validation = when {
        court == null -> tr("选一个球馆")
        mode == GameMode.Doubles && partnerId == null -> tr("选一位搭档")
        slot == null -> tr("时间无效")
        else -> slotError
    }
    // 常去球馆在前，再补附近的
    val suggestedCourts = buildList {
        if (court != null && !manager.isFavorite(court.id)) add(court)
        addAll(manager.favoriteVenues)
        addAll(manager.nearbyVenues)
    }.distinctBy { it.id }.take(6)
    val today = startOfDay(System.currentTimeMillis())
    val days = (0 until TimeSlotConstants.MAXIMUM_DAYS_AHEAD).map { addingDays(today, it) }
    val name = target?.nickname ?: tr("TA")
    val rules = buildList {
        add(tr("对方 48 小时内可以接受，没回应会自动过期"))
        add(tr("被拒绝也只会显示“未成行”"))
        if (mode == GameMode.Doubles) {
            add(tr("对方接受时会选自己的搭档"))
            add(tr("四人都确认赛果后计入排行"))
        } else {
            add(tr("接受后生成一场单打，双方确认赛果后计入排行"))
        }
    }

    Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                if (mode == GameMode.Doubles) tr("向 %@ 发起双打挑战", name) else tr("向 %@ 发起单打挑战", name),
                style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.weight(1f, fill = false).semantics { heading() },
            )
            RulesButton(tr("挑战规则"), rules)
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }

        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            SegmentedSticker(GameMode.entries, mode, { mode = it }) { it.title }

            if (mode == GameMode.Doubles) {
                Group(tr("你的搭档")) {
                    if (partnerOptions.isEmpty()) {
                        NoticeBanner(Sym.person2Fill, tr("先加球友，才能带搭档发起双打挑战"))
                    } else {
                        PartnerPicker(partnerOptions, partnerId) { partnerId = it }
                    }
                }
            }

            Group(tr("球馆")) {
                CourtChips(manager, suggestedCourts, courtId, onSelect = { courtId = it }) { showCourtPicker = true }
                val location = manager.location
                if (court != null && location != null) {
                    Text(court.formattedDistance(location), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                }
            }

            Group(tr("时间")) {
                DateStrip(days, day, Modifier.bleed(AppTheme.Spacing.screen)) { day = it }
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    TimeStepper(tr("开始"), startMinutes, 6 * 60..23 * 60, Modifier.weight(1f)) { startMinutes = it }
                    TimeStepper(tr("结束"), endMinutes, 7 * 60..24 * 60, Modifier.weight(1f)) { endMinutes = it }
                }
                if (slotError != null) {
                    InfoLabel(Sym.exclamationmarkCircleFill, slotError, colors.danger)
                }
            }

            BrutalTextField(
                tr("留言（可选）"), tr("说一句，比如：打三局两胜？"), message,
                onValueChange = { text ->
                    message = if (text.codePointCount(0, text.length) > Challenge.MESSAGE_LIMIT) {
                        text.substring(0, text.offsetByCodePoints(0, Challenge.MESSAGE_LIMIT))
                    } else {
                        text
                    }
                },
                characterLimit = Challenge.MESSAGE_LIMIT,
            )
        }

        Box(Modifier.fillMaxWidth()) {
            BrutalButton(
                onClick = {
                    val chosen = court ?: return@BrutalButton
                    val chosenSlot = slot ?: return@BrutalButton
                    isSending = true
                    scope.launch {
                        try {
                            manager.send(targetId, chosen, chosenSlot, message, if (mode == GameMode.Doubles) partnerId else null)
                            haptics.success()
                            appState.showToast(L10n.tr("挑战已发出"), Toast.Style.Success)
                            onDismiss()
                        } catch (error: RemoteError) {
                            appState.showError(error)
                        } finally {
                            isSending = false
                        }
                    }
                },
                modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg),
                enabled = validation == null && !isSending,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    if (isSending) LoadingDots()
                    FitText(tr("发起挑战"))
                }
            }
            InsetDivider(Modifier.align(Alignment.TopCenter))
        }
    }

    if (showCourtPicker) {
        SheetScaffold(onDismiss = { showCourtPicker = false }, fullHeight = true) {
            CourtPickerSheet(manager, courtId, onDismiss = { showCourtPicker = false }) { venue ->
                manager.rememberVenue(venue)
                courtId = venue.id
                showCourtPicker = false
            }
        }
    }
}

@Composable
private fun Group(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Text(title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        content()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CourtChips(manager: RankingManager, courts: List<Venue>, selected: String?, onSelect: (String) -> Unit, onOther: () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        for (option in courts) {
            ChoiceChip(option.name, selected == option.id, icon = if (manager.isFavorite(option.id)) Sym.heartFill else null) { onSelect(option.id) }
        }
        ChoiceChip(tr("其他球馆"), false, icon = Sym.magnifyingglass, onClick = onOther)
    }
}

/** 往左右各伸出 [horizontal]（横向滚动的一排贴到屏幕边上） */
internal fun Modifier.bleed(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val extra = horizontal.roundToPx() * 2
    val wide = if (constraints.hasBoundedWidth) constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = constraints.maxWidth + extra) else constraints
    val placeable = measurable.measure(wide)
    layout((placeable.width - extra).coerceAtLeast(0), placeable.height) { placeable.place(-horizontal.roundToPx(), 0) }
}

// MARK: - 搭档选择

/** 横向的球友头像胶囊，单选 */
@Composable
internal fun PartnerPicker(friends: List<User>, selection: String?, onSelect: (String) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(
        Modifier
            .bleed(AppTheme.Spacing.screen)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = AppTheme.Spacing.screen, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        for (friend in friends) {
            val isSelected = selection == friend.id
            Row(
                Modifier
                    .pressable {
                        haptics.selection()
                        onSelect(friend.id)
                    }
                    .semantics(mergeDescendants = true) { selected = isSelected }
                    .defaultMinSize(minHeight = 40.dp)
                    .sticker(if (isSelected) colors.lime else colors.surface, radius = 20.dp, shadow = AppTheme.Elevation.none)
                    .padding(start = 5.dp, end = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                AvatarView(friend, size = 28.dp)
                Text(friend.nickname, style = AppTheme.Typography.footnoteBold, color = if (isSelected) colors.onAccent else colors.ink, maxLines = 1)
            }
        }
    }
}

// MARK: - 日期条（未来 30 天）

@Composable
private fun DateStrip(days: List<Long>, selection: Long, modifier: Modifier = Modifier, onSelect: (Long) -> Unit) {
    val haptics = rememberHaptics()
    Row(
        modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = AppTheme.Spacing.screen, vertical = 6.dp),
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
    val description = DateText.relativeDay(day)
    Column(
        Modifier
            .pressable(onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = description
                selected = isSelected
            }
            .width(52.dp)
            .sticker(if (isSelected) colors.lime else colors.surface, radius = 16.dp, shadow = if (isSelected) AppTheme.Elevation.low else AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(label, style = AppTheme.Typography.caption, color = ink, maxLines = 1)
        Text("${day.zoned().dayOfMonth}", style = rounded(20, FontWeight.Bold).copy(fontFeatureSettings = "tnum"), color = ink)
    }
}

// MARK: - 时间步进器（30 分钟一档）

@Composable
private fun TimeStepper(title: String, minutes: Int, range: IntRange, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var menu by remember { mutableStateOf(false) }
    fun adjust(delta: Int) {
        val next = minutes + delta
        if (next !in range) return
        haptics.selection()
        onChange(next)
    }
    val label = tr("%@时间", title)
    val value = tr("%lld 点 %@ 分", minutes / 60, String.format(Locale.ROOT, "%02d", minutes % 60))
    Column(
        modifier
            .fillMaxWidth()
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = value
            }
            .padding(vertical = AppTheme.Spacing.sm, horizontal = AppTheme.Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = AppTheme.Typography.caption, color = colors.inkSecondary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepButton(Sym.minus, enabled = minutes - 30 in range) { adjust(-30) }
            // 点时间直接从列表里选，加减按钮微调
            Box(Modifier.weight(1f).defaultMinSize(minHeight = 40.dp).pressable(scale = 1f) { menu = true }, contentAlignment = Alignment.Center) {
                FitText(clock(minutes), style = rounded(22, FontWeight.Bold).copy(fontFeatureSettings = "tnum"), color = colors.ink)
                DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = colors.surface, shape = RoundedCornerShape(AppTheme.Radius.md)) {
                    for (option in range step 30) {
                        MenuItem(clock(option), option == minutes) {
                            haptics.selection()
                            menu = false
                            onChange(option)
                        }
                    }
                }
            }
            StepButton(Sym.plus, enabled = minutes + 30 in range) { adjust(30) }
        }
    }
}

@Composable
private fun StepButton(icon: com.badie.app.design.SymbolId, enabled: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    Box(Modifier.size(40.dp).pressable(scale = 0.85f, enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Symbol(icon, size = 14, tint = if (enabled) colors.ink else colors.inkTertiary)
    }
}

private fun clock(minutes: Int): String = String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)

// MARK: - 选球馆（“其他球馆”）

/** 单选球馆：上面是常去的和附近的，打字就按名字搜（服务器的 search_venues，不认街道地址）。对应 iPhone 的 CourtPickerSheet（VenuePickerView 的单选模式） */
@Composable
private fun CourtPickerSheet(manager: RankingManager, selectedId: String?, onDismiss: () -> Unit, onSelect: (Venue) -> Unit) {
    val colors = AppTheme.colors
    var query by remember { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<Venue>?>(null) }
    // 打字时等一下再搜（连续输入只搜最后一次）
    LaunchedEffect(query) {
        if (query.isBlank()) {
            hits = null
            return@LaunchedEffect
        }
        delay(300)
        hits = try {
            manager.searchVenues(query)
        } catch (_: RemoteError) {
            emptyList()
        }
    }
    val radius = tr("%@内", DistanceFormatter.radius(manager.radiusKm))
    val favorites = manager.favoriteVenues
    val nearby = manager.nearbyVenues.filter { !manager.isFavorite(it.id) }

    Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("选择球馆"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        StickerTextField(
            query, { query = it }, tr("搜索球馆"),
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen),
            style = AppTheme.Typography.body,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
            trailing = if (query.isEmpty()) null else {
                {
                    val label = tr("清除搜索")
                    Box(
                        Modifier.size(44.dp).clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { query = "" }
                            .semantics { contentDescription = label },
                        contentAlignment = Alignment.Center,
                    ) { Symbol(Sym.xmarkCircleFill, size = 17, tint = colors.inkTertiary) }
                }
            },
        )
        LazyColumn(
            Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(AppTheme.Spacing.screen),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            val found = hits
            if (found != null) {
                item {
                    if (found.isEmpty()) {
                        EmptyStateView(Sym.magnifyingglass, tr("没有找到“%@”", query.trim()))
                    } else {
                        VenueSection(null, null, found, manager, selectedId, onSelect)
                    }
                }
            } else {
                if (favorites.isNotEmpty()) item { VenueSection(tr("常去"), null, favorites, manager, selectedId, onSelect) }
                item {
                    if (nearby.isNotEmpty()) {
                        VenueSection(tr("附近"), radius, nearby, manager, selectedId, onSelect)
                    } else if (manager.location != null) {
                        InfoLabel(Sym.mappinSlash, tr("%@还没有收录的球馆", radius))
                    }
                }
            }
        }
    }
}

@Composable
private fun VenueSection(title: String?, detail: String?, venues: List<Venue>, manager: RankingManager, selectedId: String?, onSelect: (Venue) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        if (title != null) SectionTitle(title, detail = detail)
        Column(Modifier.fillMaxWidth().sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md)) {
            venues.forEachIndexed { index, venue ->
                if (index > 0) InsetDivider()
                VenueRow(venue, manager.location?.let(venue::formattedDistance), venue.id == selectedId) { onSelect(venue) }
            }
        }
    }
}

/** 一家球馆：名字、距离、地址，右边是单选圈 */
@Composable
private fun VenueRow(venue: Venue, distance: String?, isOn: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 64.dp)
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.RadioButton) {
                haptics.selection()
                onClick()
            }
            .semantics(mergeDescendants = true) { selected = isOn }
            .padding(vertical = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.figureBadminton, fill = if (isOn) colors.lime else colors.surfaceMuted, size = 42.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(venue.name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (distance != null) {
                    Spacer(Modifier.size(AppTheme.Spacing.sm))
                    Text(distance, style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = colors.inkSecondary)
                }
            }
            if (venue.compactAddress.isNotEmpty()) {
                Text(venue.compactAddress, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
        }
        val stroke = colors.stroke
        val fill = colors.ink
        Box(
            Modifier.size(22.dp).drawBehind {
                val width = 2.dp.toPx()
                drawCircle(stroke, radius = size.minDimension / 2 - width / 2, style = Stroke(width))
                if (isOn) drawCircle(fill, radius = size.minDimension / 2 - 5.dp.toPx())
            },
        )
    }
}
