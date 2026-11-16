package com.badie.app.features.profile

import androidx.compose.animation.animateContentSize
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.IconButton
import com.badie.app.design.RulesButton
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.onboarding.SkillAssessmentView
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillLevel
import com.badie.app.models.SkillTier
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.launch

// 对应 iPhone 的 Features/Onboarding/SkillAssessmentViews.swift 里的 SkillLevelGuideView、ReassessSheet

/** 等级对照表的“?” */
private fun guideRules(): List<String> = listOf(
    L10n.tr("1–9 级，每级再分 −、本级、+ 三档，共 27 档。"),
    L10n.tr("3–6 级一级比一级多一个维度：技术会不会 → 主动球好不好 → 被动球能不能摆脱、战术 → 在俱乐部里的位置。"),
    L10n.tr("每级可以展开看分项标准（步法、发力、前后场、攻防）。"),
    L10n.tr("对照“能稳定做到”的，而不是偶尔打出来的球。"),
    L10n.tr("7 级起差距大，每一档单独命名，按证据定档。"),
    L10n.tr("7 起是州级、全国、国际水平，只看能查到的赛果、排名和证书。"),
    L10n.tr(
        "分项标准参考中羽在线论坛流传的 1–9 级分项描述；1–6 级还参考了打球吧“业余 1–9 级”和 USTA NTRP；7 起按 tournamentsoftware 公开成绩、USAB 全国排名、《运动员技术等级标准》（2025 版）和 BWF 世界排名划分。中国羽协的业余等级是“九级最低”，方向和这里相反；美国各赛事的组别强度不同，所以按“最高组 / 次高组”的相对位置认定。",
    ),
)

/** 1–9 级对照表：每级的标准、三档、可展开的分项标准。[highlight] 是“你在这里” */
@Composable
fun SkillLevelGuideView(highlight: SkillTier?, modifier: Modifier = Modifier, onClose: (() -> Unit)? = null) {
    // 默认展开当前所在的级
    val expanded = remember { mutableStateMapOf<Int, Boolean>().apply { highlight?.let { put(it.level, true) } } }
    // 打开时停在当前所在的级（第 0 项是 −/本级/+ 的说明）
    val list = rememberLazyListState(initialFirstVisibleItemIndex = highlight?.level?.minus(1)?.coerceAtLeast(0) ?: 0)
    Column(modifier) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("等级对照表"), style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(tr("等级对照表"), guideRules())
            Spacer(Modifier.weight(1f))
            if (onClose != null) IconButton(Sym.xmark, tr("关闭"), onClick = onClose)
        }
        LazyColumn(
            state = list,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(start = AppTheme.Spacing.screen, end = AppTheme.Spacing.screen, bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            item { ModifierLegend() }
            items(SkillLevel.range.toList()) { level ->
                LevelCard(level, highlight, expanded[level] == true) { expanded[level] = expanded[level] != true }
            }
        }
    }
}

/** −/本级/+ 的通用含义 */
@Composable
private fun ModifierLegend() {
    Column(
        Modifier
            .fillMaxWidth()
            .sticker(AppTheme.colors.surfaceMuted, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        for (modifier in listOf(SkillTier.Modifier.Minus, SkillTier.Modifier.Base, SkillTier.Modifier.Plus)) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(
                    if (modifier == SkillTier.Modifier.Base) tr("本级") else modifier.symbol,
                    style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.ink, modifier = Modifier.width(36.dp),
                )
                Text(modifier.meaning, style = AppTheme.Typography.footnote, color = AppTheme.colors.ink)
            }
        }
    }
}

@Composable
private fun LevelCard(level: Int, highlight: SkillTier?, isOpen: Boolean, onToggle: () -> Unit) {
    val colors = AppTheme.colors
    val isCurrent = level == highlight?.level
    val tiers = listOf(SkillTier.Modifier.Minus, SkillTier.Modifier.Base, SkillTier.Modifier.Plus).map { SkillTier(level, it) }
    Column(
        Modifier
            .fillMaxWidth()
            .sticker(if (isCurrent) colors.lime.copy(alpha = 0.35f).compositeOver(colors.surface) else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            val fill = colors.paletteColor(level)
            val stroke = colors.stroke
            Box(
                Modifier.size(40.dp).drawBehind {
                    val r = CornerRadius(12.dp.toPx())
                    drawRoundRect(fill, cornerRadius = r)
                    val w = 2.dp.toPx()
                    drawRoundRect(stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), r, style = Stroke(w))
                },
                contentAlignment = Alignment.Center,
            ) { Text("$level", style = rounded(20, FontWeight.Black), color = colors.onAccent) }
            Column(Modifier.weight(1f)) {
                Text(SkillLevel.name(level), style = AppTheme.Typography.headline, color = colors.ink)
                Text(
                    listOfNotNull(SkillLevel.usFlight(level)?.let { "≈ $it" }, SkillLevel.typicalExperience(level)).joinToString(" · "),
                    style = AppTheme.Typography.caption, color = colors.inkSecondary,
                )
            }
            if (isCurrent) {
                TagPill(tr("你在这里"), fill = colors.lime)
            } else if (level > SkillLevel.MAX_SELF_SELECTABLE) {
                TagPill(tr("需认证"), icon = Sym.lockFill, fill = colors.surfaceMuted, foreground = colors.inkSecondary)
            }
        }
        if (level <= SkillLevel.MAX_SELF_SELECTABLE) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (anchor in SkillLevel.anchors(level)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val ink = colors.ink
                        Box(Modifier.padding(top = 9.dp).size(5.dp).drawBehind { drawCircle(ink) })
                        Text(anchor, style = AppTheme.Typography.subheadline, color = ink)
                    }
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { tiers.forEach { TierRow(it, highlight) } }
        DimensionNotes(level, isOpen, onToggle)
    }
}

/** 可展开的分项标准：步法、发力、前后场、攻防在这一级是什么样子 */
@Composable
private fun DimensionNotes(level: Int, isOpen: Boolean, onToggle: () -> Unit) {
    val notes = SkillLevel.dimensionNotes(level)
    if (notes.isEmpty()) return
    val colors = AppTheme.colors
    val label = tr("Lv.%lld 分项标准", level)
    val state = if (isOpen) tr("已展开") else tr("已收起")
    Column(Modifier.animateContentSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 32.dp)
                .pressable(scale = 1f, onClick = onToggle)
                .semantics {
                    contentDescription = label
                    stateDescription = state
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Symbol(Sym.listBulletRectangle, size = 12, tint = colors.inkSecondary)
            Text(
                if (isOpen) tr("收起分项标准") else tr("分项标准（%lld 项）", notes.size),
                style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.weight(1f),
            )
            Symbol(Sym.chevronDown, size = 11, tint = colors.inkSecondary, modifier = Modifier.rotate(if (isOpen) 180f else 0f))
        }
        if (isOpen) {
            val muted = colors.surfaceMuted
            Column(
                Modifier
                    .fillMaxWidth()
                    .drawBehind { drawRoundRect(muted, cornerRadius = CornerRadius(12.dp.toPx())) }
                    .padding(AppTheme.Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                for ((name, text) in notes) {
                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        Text(name, style = AppTheme.Typography.footnoteBold, color = colors.ink, modifier = Modifier.width(72.dp))
                        Text(text, style = AppTheme.Typography.footnote, color = colors.ink)
                    }
                }
            }
        }
    }
}

/** 每一档的标准（7 起需认证的档位带锁） */
@Composable
private fun TierRow(tier: SkillTier, highlight: SkillTier?) {
    val colors = AppTheme.colors
    val selected = tier == highlight
    val locked = tier > VerificationStatus.unverifiedMaxTier
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        val fill = if (selected) colors.lime else colors.surfaceMuted
        Box(
            Modifier.size(40.dp, 28.dp).drawBehind { drawRoundRect(fill, cornerRadius = CornerRadius(8.dp.toPx())) },
            contentAlignment = Alignment.Center,
        ) {
            Text(tier.code, style = AppTheme.Typography.subheadlineBold.copy(fontFeatureSettings = "tnum"), color = if (selected) colors.onAccent else colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (tier.level >= SkillLevel.MAX_SELF_SELECTABLE && tier.name != SkillLevel.name(tier.level)) {
                Text(tier.name, style = AppTheme.Typography.footnoteBold, color = colors.ink)
            }
            for (line in SkillLevel.tierCriteria(tier)) Text(line, style = AppTheme.Typography.footnote, color = colors.ink)
        }
        if (locked) {
            val lockLabel = tr("需认证")
            Symbol(Sym.lockFill, size = 11, tint = colors.inkTertiary, modifier = Modifier.semantics { contentDescription = lockLabel })
        }
    }
}

// MARK: - 重新测评（每 90 天一次）

@Composable
fun ReassessSheet(onDismiss: () -> Unit) {
    val appState = LocalEnv.current.appState
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val answers = remember { mutableStateMapOf<String, Int>() }
    var isSaving by remember { mutableStateOf(false) }
    val result = SkillAssessment.evaluate(answers)
    Column(Modifier.fillMaxWidth()) {
        SheetHeader(
            tr("重新测评"), onDismiss, Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.md),
            rules = listOf(tr("90 天内只能重测一次；已有球友评价的话，显示等级仍以球友评价为主")),
        )
        SkillAssessmentView(
            answers,
            Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xl),
        )
        if (result != null) {
            BrutalButton(
                tr("使用 %@", result.tier.displayText),
                {
                    if (isSaving) return@BrutalButton
                    isSaving = true
                    scope.launch {
                        try {
                            appState.backend.saveAssessment(result, answers.toMap())
                            haptics.success()
                            appState.showToast(L10n.tr("问卷等级已更新为 %@", result.tier.text), Toast.Style.Success)
                            onDismiss()
                        } catch (error: RemoteError) {
                            haptics.error()
                            appState.showError(error)
                        } finally {
                            isSaving = false
                        }
                    }
                },
                Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.md),
                enabled = !isSaving,
            )
        }
    }
}
