package com.badie.app.features.matching

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ChoiceChip
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.RulesButton
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.CostSplit
import com.badie.app.models.DateText
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.MatchTiming
import com.badie.app.models.PlayEvent
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.Venue
import com.badie.app.models.addingDays
import com.badie.app.models.isSameDay
import com.badie.app.models.startOfDay
import com.badie.app.models.title
import com.badie.app.models.zoned
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import java.util.Locale

// 对应 iPhone 的 Features/Matching/MatchSetupView.swift：快速匹配设置（项目 · 日期 · 时间 · 球馆 · 实力差），
// 还有几处共用的小控件（时间步进器、日期条）

/** 匹配流程（全屏）；MatchManager 说要显示时才显示（内容在 MatchFlow.kt） */
@Composable
fun MatchFlowOverlay() {
    MatchFlowHost()
}

/** 匹配设置（半屏弹层的内容），关掉时调 onDismiss */
@Composable
fun MatchSetupSheet(onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val user = env.appState.currentUser
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(Unit) {
        val recurring = com.badie.app.backend.ProfileApi.of(env.appState.backend, context).recurringSlots()
        manager.prepareDraft(user, env.locationManager.nearbyCourts, recurring, env.locationManager.favoriteCourts.map { it.id })
    }
    LaunchedEffect(manager.draftVenueIds.toList()) { manager.loadVenues(manager.draftVenueIds.toList()) }
    MatchSetupContent(
        onClose = onDismiss,
        onPickVenues = {
            // 选球馆是一个推进去的页面（features/venues），先收起这个半屏
            onDismiss()
            env.router.open(Route.MatchVenues(null))
        },
        onStart = {
            onDismiss()
            manager.startSearch(delayMillis = 450)
        },
    )
}

/** 设置页本身（截图测试直接用） */
@Composable
fun MatchSetupContent(onClose: () -> Unit, onPickVenues: () -> Unit, onStart: () -> Unit) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val draft = manager.draft
    val colors = AppTheme.colors
    val gender = env.appState.currentUser?.gender ?: Gender.Unspecified
    val tier = env.appState.currentUser?.displayTier ?: SkillTier(4)
    val slot = draft.slot()
    val canRequest = slot?.let { MatchTiming.canRequest(it.startTime) } ?: false
    val isLastMinute = slot?.let { MatchTiming.isLastMinute(it.startTime) } ?: false

    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("快速匹配"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            IconButton(Sym.xmark, tr("关闭"), onClick = onClose)
        }
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xxl),
        ) {
            val padded = Modifier.padding(horizontal = AppTheme.Spacing.screen)
            if (draft.replacingTicketId != null) {
                Row(padded.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TagPill(tr("修改中"), icon = Sym.pencil, fill = colors.butter)
                    Spacer(Modifier.weight(1f))
                    TextAction(tr("不改了"), { manager.draft = manager.draft.copy(replacingTicketId = null) })
                }
            }
            EventSection(padded, gender)
            DateSection()
            TimeSection(padded)
            CourtsSection(padded, onPickVenues)
            SkillSection(padded, tier)
            ConfirmSection(padded, canRequest, isLastMinute)
        }
        InsetDivider()
        Footer(canRequest, onStart)
    }
}

@Composable
private fun FieldLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = modifier.semantics { heading() })
}

// MARK: 项目：单打 / 双打 / 混双；不是混双时还能只限同性别（男单、女双……）

private enum class EventChoice { Singles, Doubles, Mixed }

@Composable
private fun EventSection(modifier: Modifier, gender: Gender) {
    val manager = LocalEnv.current.matchManager
    val draft = manager.draft
    // 混双要知道自己的性别
    val choices = if (PlayEvent.Mixed in PlayEvent.choices(GameMode.Doubles, gender)) EventChoice.entries else listOf(EventChoice.Singles, EventChoice.Doubles)
    val current = when {
        draft.event == PlayEvent.Mixed -> EventChoice.Mixed
        draft.mode == GameMode.Singles -> EventChoice.Singles
        else -> EventChoice.Doubles
    }
    val audience = PlayEvent.choices(draft.mode, gender).filter { it != PlayEvent.Mixed }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FieldLabel(tr("项目"))
            Spacer(Modifier.weight(1f))
            RulesButton(tr("项目"), PlayEvent.choices(GameMode.Doubles, gender).map { PlayEvent.caption(it) })
        }
        SegmentedSticker(choices, current, onSelect = { choice ->
            manager.draft = when (choice) {
                EventChoice.Singles, EventChoice.Doubles -> manager.draft.copy(
                    mode = if (choice == EventChoice.Singles) GameMode.Singles else GameMode.Doubles,
                    event = manager.draft.event.takeIf { it != PlayEvent.Mixed },
                )
                EventChoice.Mixed -> manager.draft.copy(mode = GameMode.Doubles, event = PlayEvent.Mixed)
            }
        }) { choice ->
            when (choice) {
                EventChoice.Singles -> GameMode.Singles.title
                EventChoice.Doubles -> GameMode.Doubles.title
                EventChoice.Mixed -> PlayEvent.Mixed.title(GameMode.Doubles)
            }
        }
        if (draft.event != PlayEvent.Mixed && audience.size > 1) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                for (event in audience) {
                    ChoiceChip(event?.title(draft.mode) ?: tr("不限"), isSelected = draft.event == event) {
                        manager.draft = manager.draft.copy(event = event)
                    }
                }
            }
        }
    }
}

// MARK: 日期

@Composable
private fun DateSection() {
    val manager = LocalEnv.current.matchManager
    val today = startOfDay(System.currentTimeMillis())
    val days = remember(today) { (0 until TimeSlotConstants.MAXIMUM_DAYS_AHEAD).map { addingDays(today, it) } }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        FieldLabel(tr("日期"), Modifier.padding(horizontal = AppTheme.Spacing.screen))
        DateStrip(days, manager.draft.day, onSelect = { manager.draft = manager.draft.copy(day = it) }, counts = { manager.availableCount(it) })
    }
}

// MARK: 时间

private val presets: List<Triple<String, Int, Int>>
    @Composable get() = listOf(
        Triple(tr("早上"), 7 * 60, 9 * 60), Triple(tr("中午"), 12 * 60, 14 * 60), Triple(tr("下午"), 14 * 60, 17 * 60),
        Triple(tr("晚上"), 19 * 60, 21 * 60), Triple(tr("夜里"), 21 * 60, 23 * 60),
    )

@Composable
private fun TimeSection(modifier: Modifier) {
    val manager = LocalEnv.current.matchManager
    val draft = manager.draft
    val colors = AppTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FieldLabel(tr("时间"))
            Spacer(Modifier.weight(1f))
            RulesButton(tr("时间"), listOf(tr("匹配时，你和对方的时间至少要重叠 30 分钟。"), tr("离开赛不到 30 分钟就不能发起了。")))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            TimeStepper(tr("开始"), draft.startMinutes, 6 * 60..23 * 60, Modifier.weight(1f)) { manager.draft = manager.draft.copy(startMinutes = it) }
            Symbol(Sym.arrowRight, size = 14, tint = colors.inkTertiary)
            TimeStepper(tr("结束"), draft.endMinutes, 7 * 60..24 * 60, Modifier.weight(1f)) { manager.draft = manager.draft.copy(endMinutes = it) }
        }
        draft.validation().errorMessage?.let { ErrorLine(it) }
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            ChoiceChip(tr("任何时间"), isSelected = draft.isAnyTime, tint = colors.lime) { manager.draft = manager.draft.withAnyTime() }
            for ((title, start, end) in presets) {
                ChoiceChip(title, isSelected = draft.startMinutes == start && draft.endMinutes == end, tint = colors.peach) {
                    manager.draft = manager.draft.copy(startMinutes = start, endMinutes = end)
                }
            }
        }
    }
}

/** 红色的一行提示（带感叹号） */
@Composable
fun ErrorLine(text: String, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Symbol(Sym.exclamationmarkCircleFill, size = 13, tint = AppTheme.colors.danger)
        Text(text, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.danger)
    }
}

// MARK: 球馆（每行只有名字和距离）

@Composable
private fun CourtsSection(modifier: Modifier, onPickVenues: () -> Unit) {
    val manager = LocalEnv.current.matchManager
    val colors = AppTheme.colors
    val selected = manager.courts(manager.draft.courtIds)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FieldLabel(tr("球馆"))
            RulesButton(
                tr("球馆"),
                listOf(
                    tr("只和也能去这些球馆（或 150 米内同一处）的球友匹配。"),
                    tr("最多选 %lld 个。", MatchDraft.MAX_COURTS),
                    tr("按钮上的费用按所选球馆里最便宜的一家估算，到场后按实际费用 AA。"),
                    tr("平台不收服务费。"),
                ),
            )
            Spacer(Modifier.weight(1f))
            Text("${selected.size}/${MatchDraft.MAX_COURTS}", style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
        }
        Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md)) {
            selected.forEachIndexed { index, court ->
                if (index > 0) InsetDivider()
                CourtRow(court)
            }
            if (selected.isNotEmpty()) InsetDivider()
            Row(
                Modifier.fillMaxWidth().pressable(scale = 1f, onClick = onPickVenues).padding(vertical = AppTheme.Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                IconTile(if (selected.isEmpty()) Sym.magnifyingglass else Sym.plus, fill = colors.lime, size = 36.dp)
                Text(tr("选择球馆"), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
            }
        }
    }
}

@Composable
private fun CourtRow(court: Venue) {
    val manager = LocalEnv.current.matchManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val isClosed = manager.draft.slot()?.let { !court.isOpen(it) } ?: false
    Row(Modifier.fillMaxWidth().padding(vertical = AppTheme.Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(court.name, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (isClosed) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(Sym.moonZzzFill, size = 11, tint = colors.danger)
                    Text(tr("所选时段不营业"), style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Bold), color = colors.danger)
                }
            }
        }
        manager.location.coordinate.let {
            Text(court.formattedDistance(it), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.padding(start = AppTheme.Spacing.sm))
        }
        val label = tr("移除%@", court.name)
        Box(
            Modifier.size(44.dp).pressable {
                haptics.selection()
                manager.draft.togglingCourt(court.id)?.let { manager.draft = it }
            }.semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Symbol(Sym.xmarkCircleFill, size = 20, tint = colors.inkTertiary)
        }
    }
}

// MARK: 实力差

@Composable
private fun SkillSection(modifier: Modifier, tier: SkillTier) {
    val manager = LocalEnv.current.matchManager
    val tolerance = manager.draft.skillTolerance
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FieldLabel(tr("实力差"))
            Spacer(Modifier.weight(1f))
            // 每档会匹配到的等级范围（一级 = 3 个小档）
            RulesButton(
                tr("实力差"),
                listOf(
                    tr("你的等级是 %@。", tier.text),
                    tr("±1 级：匹配 %@ 的球友。", SkillTier.rangeText(tier.offset(-3), tier.offset(3))),
                    tr("±2 级：匹配 %@ 的球友。", SkillTier.rangeText(tier.offset(-6), tier.offset(6))),
                    tr("不限：匹配所有水平的球友。"),
                    tr("水平越接近，排得越靠前。"),
                ),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            ChoiceChip(tr("±1 级"), isSelected = tolerance == 1) { manager.draft = manager.draft.copy(skillTolerance = 1) }
            ChoiceChip(tr("±2 级"), isSelected = tolerance == 2) { manager.draft = manager.draft.copy(skillTolerance = 2) }
            ChoiceChip(tr("不限"), isSelected = tolerance >= MatchRequest.ANY_SKILL) { manager.draft = manager.draft.copy(skillTolerance = MatchRequest.ANY_SKILL) }
        }
    }
}

// MARK: 找到就直接接受、临时局、来不及

@Composable
private fun ConfirmSection(modifier: Modifier, canRequest: Boolean, isLastMinute: Boolean) {
    val manager = LocalEnv.current.matchManager
    val colors = AppTheme.colors
    val slot = manager.draft.slot()
    val points = buildList {
        add(tr("打开后，条件合适就替你接受，其他人确认后就约成，不用再点一次。"))
        add(tr("所有人都确认才成局，谁没确认不会告诉其他人。"))
        if (slot != null && !isLastMinute) {
            val lock = MatchTiming.lock(slot.startTime, lastMinute = false)
            add(tr("最晚 %@ %@（开赛前 2 小时）前确认完，否则自动取消，不计入记录。", DateText.relativeDay(lock), DateText.time(lock)))
        }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("找到就直接接受"), style = AppTheme.Typography.bodyBold, color = colors.ink)
            RulesButton(tr("找到就直接接受"), points)
            Spacer(Modifier.weight(1f))
            val label = tr("找到就直接接受")
            Switch(
                checked = manager.draft.autoAccept,
                onCheckedChange = { manager.draft = manager.draft.copy(autoAccept = it) },
                modifier = Modifier.semantics { contentDescription = label },
                colors = SwitchDefaults.colors(checkedTrackColor = colors.success, checkedThumbColor = Color.White, checkedBorderColor = colors.stroke),
            )
        }
        if (isLastMinute && canRequest) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TagPill(tr("临时局"), icon = Sym.boltFill, fill = colors.butter)
                RulesButton(
                    tr("临时局"),
                    listOf(tr("离开赛不远时发起的是临时局，只匹配此刻也在找人的球友。"), tr("找到后要在 5–10 分钟内确认，建议打开“找到就直接接受”。")),
                )
            }
        }
        // 只在来不及的时候出一句
        if (slot != null && slot.endTime > System.currentTimeMillis() && !canRequest) {
            ErrorLine(tr("离开赛不到 30 分钟，来不及凑人了，换个时间试试"))
        }
    }
}

// MARK: 底部按钮

@Composable
private fun Footer(canRequest: Boolean, onStart: () -> Unit) {
    val manager = LocalEnv.current.matchManager
    val draft = manager.draft
    val estimate = estimatedCostText()
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.sm),
    ) {
        BrutalButton(onClick = onStart, enabled = draft.canSearch() && canRequest) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(if (draft.replacingTicketId != null) Sym.checkmark else Sym.boltFill, size = 15)
                    Text(if (draft.replacingTicketId != null) tr("保存修改") else tr("开始匹配"))
                }
                if (estimate != null) {
                    Text(estimate, style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Bold), modifier = Modifier.padding(bottom = 2.dp))
                }
            }
        }
    }
}

/** 所选球馆中最便宜的预计 AA：“约 $12/人”；都不知道价格时“费用待定” */
@Composable
private fun estimatedCostText(): String? {
    val manager = LocalEnv.current.matchManager
    val slot = manager.draft.slot()?.takeIf { it.isValidDuration } ?: return null
    val courts = manager.courts(manager.draft.courtIds)
    if (courts.isEmpty()) return null
    val cheapest = courts.map { CostSplit.estimate(it, slot.trimmedForGame(), manager.draft.mode) }
        .filter { it.perPerson != null }.minByOrNull { it.perPerson ?: 0 } ?: return tr("费用待定")
    return tr("约 %@", cheapest.perPersonText)
}

// MARK: - 时间步进器（30 分钟一档）

@Composable
fun TimeStepper(title: String, minutes: Int, range: IntRange, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
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
    val increase = tr("提高")
    val decrease = tr("降低")
    Column(
        modifier
            .fillMaxWidth()
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm, horizontal = AppTheme.Spacing.xs)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = value
                customActions = listOf(
                    CustomAccessibilityAction(increase) { adjust(30); true },
                    CustomAccessibilityAction(decrease) { adjust(-30); true },
                )
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = AppTheme.Typography.caption, color = colors.inkSecondary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepButton(Sym.minus, enabled = minutes - 30 in range) { adjust(-30) }
            // 点时间直接从列表里选，加减按钮微调
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Text(
                    clock(minutes), style = rounded(22, FontWeight.Bold).copy(fontFeatureSettings = "tnum"), color = colors.ink, maxLines = 1,
                    modifier = Modifier.defaultMinSize(minHeight = 40.dp).pressable(scale = 1f) { menu = true }.padding(top = 6.dp),
                )
                DropdownMenu(menu, onDismissRequest = { menu = false }) {
                    for (option in range step 30) {
                        DropdownMenuItem(
                            text = { Text(clock(option), style = AppTheme.Typography.bodyBold) },
                            onClick = {
                                haptics.selection()
                                onChange(option)
                                menu = false
                            },
                            trailingIcon = if (option == minutes) ({ Symbol(Sym.checkmark, size = 14) }) else null,
                        )
                    }
                }
            }
            StepButton(Sym.plus, enabled = minutes + 30 in range) { adjust(30) }
        }
    }
}

@Composable
private fun StepButton(icon: com.badie.app.design.SymbolId, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(40.dp).pressable(scale = 0.85f, enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Symbol(icon, size = 14, tint = if (enabled) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
    }
}

private fun clock(minutes: Int): String = String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)

// MARK: - 日期条（未来 N 天，显示可约人数）

@Composable
fun DateStrip(days: List<Long>, selection: Long, onSelect: (Long) -> Unit, modifier: Modifier = Modifier, counts: (Long) -> Int? = { null }) {
    val haptics = rememberHaptics()
    Row(
        modifier.horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        for (day in days) {
            DateChip(day, isSelected = isSameDay(day, selection), count = counts(day)) {
                haptics.selection()
                onSelect(day)
            }
        }
    }
}

@Composable
private fun DateChip(day: Long, isSelected: Boolean, count: Int?, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val foreground = if (isSelected) colors.onAccent else colors.ink
    val label = if (isSameDay(day, System.currentTimeMillis())) tr("今天") else DateText.weekday(day)
    val description = DateText.relativeDay(day) + (count?.let { tr("，%lld 人有空", it) } ?: "")
    Column(
        Modifier
            .pressable(onClick = onClick)
            .clearAndSetSemantics { contentDescription = description; selected = isSelected }
            .width(52.dp)
            .sticker(if (isSelected) colors.lime else colors.surface, radius = 16.dp, shadow = if (isSelected) AppTheme.Elevation.low else AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(label, style = AppTheme.Typography.caption, color = foreground, maxLines = 1)
        Text(
            day.zoned().dayOfMonth.toString(), style = rounded(20, FontWeight.Bold).copy(fontFeatureSettings = "tnum"), color = foreground,
        )
        if (count != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                Symbol(Sym.personFill, size = 8, tint = foreground.copy(alpha = 0.8f))
                Text(count.toString(), style = rounded(10, FontWeight.Bold), color = foreground.copy(alpha = 0.8f))
            }
        }
    }
}
