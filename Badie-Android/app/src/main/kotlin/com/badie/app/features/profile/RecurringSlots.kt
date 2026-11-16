package com.badie.app.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.badie.app.backend.BackendError
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.canAddMore
import com.badie.app.models.remainingSlots
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import java.util.Locale

// 对应 iPhone 的 SettingsView.swift 里的 RecurringSlotsView、RecurringSlotEditor，和 MatchSetupView.swift 的 TimeStepper

/** 存常用时间；不合规（太多、时长不对）就提示并按存着的恢复 */
fun ProfileApi.persistSlots(slots: List<RecurringTimeSlot>, onError: (Exception) -> Unit): List<RecurringTimeSlot> = try {
    saveRecurringSlots(slots)
    slots
} catch (error: BackendError) {
    onError(error)
    recurringSlots()
} catch (error: RemoteError) {
    onError(error)
    recurringSlots()
}

/** 常用时间（最多 5 个）：开关、删除、添加 */
@Composable
fun RecurringSlotsView() {
    val env = LocalEnv.current
    val api = rememberProfileApi()
    var slots by remember { mutableStateOf(api.recurringSlots()) }
    var showEditor by remember { mutableStateOf(false) }
    fun persist(next: List<RecurringTimeSlot>) {
        slots = api.persistSlots(next) { env.appState.showError(it) }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("常用时间"), onBack = { env.router.pop() }) {
            RulesButton(
                tr("常用时间"),
                listOf(
                    tr("快速匹配会优先用最近的常用时间"),
                    tr("附近的人能看到你打开的常用时间，按它约你"),
                    tr("最多保存 %lld 个，还可添加 %lld 个", TimeSlotConstants.MAXIMUM_RECURRING_SLOTS, slots.remainingSlots),
                ),
            )
            if (slots.canAddMore) IconButton(Sym.plus, tr("添加常用时间"), accent = AppTheme.colors.lime) { showEditor = true }
        }
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            if (slots.isEmpty()) {
                EmptyStateView(Sym.calendarBadgePlus, tr("还没有常用时间"), tint = AppTheme.colors.peach, actionTitle = tr("添加")) { showEditor = true }
            }
            for (slot in slots) {
                val deleteLabel = tr("删除 %@", slot.displayText)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                        .padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    IconTile(Sym.calendar, fill = if (slot.isActive) AppTheme.colors.peach else AppTheme.colors.surfaceMuted, size = 42.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(slot.dayOfWeekName, style = AppTheme.Typography.headline, color = AppTheme.colors.ink)
                        Text(
                            slot.formattedTimeRange, style = AppTheme.Typography.subheadline.copy(fontFeatureSettings = "tnum"),
                            color = AppTheme.colors.inkSecondary,
                        )
                    }
                    val enableLabel = tr("启用")
                    BadieSwitch(
                        slot.isActive,
                        { on -> persist(slots.map { if (it.id == slot.id) it.copy(isActive = on) else it }) },
                        Modifier.semantics { contentDescription = enableLabel },
                    )
                    Box(
                        Modifier
                            .size(44.dp)
                            .pressable { persist(slots.filter { it.id != slot.id }) }
                            .semantics { contentDescription = deleteLabel },
                        contentAlignment = Alignment.Center,
                    ) { Symbol(Sym.trashFill, size = 17, tint = AppTheme.colors.danger) }
                }
            }
        }
    }

    if (showEditor) {
        BadieSheet(onDismiss = { showEditor = false }) { dismiss ->
            RecurringSlotEditor(onSave = { slot -> persist(slots + slot) }, onDismiss = dismiss)
        }
    }
}

/** 加一段常用时间：星期几、开始、结束（每段 1–8 小时） */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RecurringSlotEditor(onSave: (RecurringTimeSlot) -> Unit, onDismiss: () -> Unit) {
    var dayOfWeek by remember { mutableIntStateOf(4) }
    var startMinutes by remember { mutableIntStateOf(19 * 60) }
    var endMinutes by remember { mutableIntStateOf(21 * 60) }
    val candidate = RecurringTimeSlot.create(dayOfWeek, startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(tr("添加常用时间"), style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            for (day in listOf(2, 3, 4, 5, 6, 7, 1)) {
                ChoiceChip(RecurringTimeSlot.weekdayNames[day - 1], dayOfWeek == day) { dayOfWeek = day }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            TimeStepper(tr("开始"), startMinutes, { startMinutes = it }, (6 * 60)..(23 * 60), Modifier.weight(1f))
            TimeStepper(tr("结束"), endMinutes, { endMinutes = it }, (7 * 60)..(24 * 60), Modifier.weight(1f))
        }
        if (!candidate.isValidDuration) {
            Text(tr("时间段需要 1-8 小时"), style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.danger)
        }
        BrutalButton(tr("保存"), {
            onSave(candidate)
            onDismiss()
        }, enabled = candidate.isValidDuration)
    }
}

/** 选一个时间：中间点开列表选（每半小时一个），两边加减半小时 */
@Composable
fun TimeStepper(title: String, minutes: Int, onChange: (Int) -> Unit, range: IntRange, modifier: Modifier = Modifier) {
    val haptics = rememberHaptics()
    var expanded by remember { mutableStateOf(false) }
    fun text(value: Int) = String.format(Locale.ROOT, "%02d:%02d", value / 60, value % 60)
    fun adjust(delta: Int) {
        val next = minutes + delta
        if (next !in range) return
        haptics.selection()
        onChange(next)
    }
    val label = tr("%@时间", title)
    val spoken = tr("%lld 点 %@ 分", minutes / 60, String.format(Locale.ROOT, "%02d", minutes % 60))
    Column(
        modifier
            .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm, horizontal = AppTheme.Spacing.xs)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = spoken
                customActions = listOf(
                    CustomAccessibilityAction("+30") { adjust(30); true },
                    CustomAccessibilityAction("−30") { adjust(-30); true },
                )
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = AppTheme.Typography.caption, color = AppTheme.colors.inkSecondary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepButton(Sym.minus, enabled = minutes - 30 in range) { adjust(-30) }
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Text(
                    text(minutes), style = rounded(22, androidx.compose.ui.text.font.FontWeight.Bold).copy(fontFeatureSettings = "tnum"),
                    color = AppTheme.colors.ink, maxLines = 1,
                    modifier = Modifier.pressable(scale = 1f) { expanded = true }.padding(vertical = AppTheme.Spacing.sm),
                )
                DropdownMenu(expanded, { expanded = false }, containerColor = AppTheme.colors.surface) {
                    for (option in range step 30) {
                        DropdownMenuItem(
                            text = { Text(text(option), style = AppTheme.Typography.body, color = AppTheme.colors.ink) },
                            onClick = {
                                haptics.selection()
                                onChange(option)
                                expanded = false
                            },
                            trailingIcon = if (option == minutes) ({ Symbol(Sym.checkmark, size = 13, tint = AppTheme.colors.ink) }) else null,
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
