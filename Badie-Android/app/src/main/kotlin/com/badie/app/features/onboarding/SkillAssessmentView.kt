package com.badie.app.features.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BadieTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ProgressBar
import com.badie.app.design.RulesButton
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.AssessmentOption
import com.badie.app.models.AssessmentQuestion
import com.badie.app.models.PlayProfile
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillAssessmentResult
import com.badie.app.models.SkillLevel
import com.badie.app.models.VerificationStatus
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// MARK: - 定级问卷：一次一题，答完自动出等级

@Composable
fun SkillAssessmentView(answers: MutableMap<String, Int>, modifier: Modifier = Modifier) {
    val questions = SkillAssessment.questions
    val result = SkillAssessment.evaluate(answers)
    // 已经答完（返回上一步再回来）直接显示结果
    var index by rememberSaveable { mutableIntStateOf(if (result != null) questions.size else 0) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()

    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
        if (index >= questions.size && result != null) {
            AssessmentResultCard(result)
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                BrutalButton(
                    onClick = {
                        answers.clear()
                        index = 0
                    },
                    Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small,
                ) {
                    Symbol(Sym.arrowCounterclockwise, size = 13)
                    Spacer(Modifier.size(6.dp))
                    Text(tr("重新回答"), maxLines = 1)
                }
                RulesButton(tr("怎么定级"), assessmentRules(result))
            }
        } else {
            AnimatedContent(
                minOf(index, questions.size - 1),
                transitionSpec = { (slideInHorizontally(AppTheme.Motion.standard()) { it / 3 } + fadeIn()) togetherWith fadeOut() },
                label = "question",
            ) { position ->
                val question = questions[position]
                QuestionCard(
                    question, position + 1, questions.size, answers[question.id],
                    onBack = {
                        haptics.tap()
                        index = maxOf(0, index - 1)
                    },
                    onSelect = { option ->
                        haptics.selection()
                        answers[question.id] = option.id
                        // 选完自动进下一题
                        scope.launch {
                            delay(220)
                            index = minOf(questions.size, position + 1)
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun QuestionCard(
    question: AssessmentQuestion, position: Int, total: Int, selected: Int?,
    onBack: () -> Unit, onSelect: (AssessmentOption) -> Unit,
) {
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 32.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("第 %lld / %lld 题", position, total), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            Spacer(Modifier.weight(1f))
            if (position > 1) {
                Text(
                    tr("上一题"), style = AppTheme.Typography.footnoteBold, color = colors.ink,
                    modifier = Modifier.clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onBack),
                )
            }
        }
        ProgressBar((position - 1).toFloat() / total)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(question.title, style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.semantics { heading() })
            Text(question.hint, style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
        }
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            for (option in question.options) {
                OptionRow(option, isSelected = selected == option.id) { onSelect(option) }
            }
        }
    }
}

@Composable
private fun OptionRow(option: AssessmentOption, isSelected: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val letter = "ABCDEFG"[minOf(option.id, 6)].toString()
    val badge = if (isSelected) colors.onAccent else colors.surfaceMuted
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.RadioButton, onClick = onClick)
            .semantics { selected = isSelected }
            // 选中是在白底上盖一层淡淡的柠檬色
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .sticker(if (isSelected) colors.lime.copy(alpha = 0.35f) else Color.Transparent, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Box(Modifier.size(32.dp).clip(CircleShape).drawBehind { drawRect(badge) }, contentAlignment = Alignment.Center) {
            Text(letter, style = AppTheme.Typography.headline, color = if (isSelected) colors.lime else colors.ink)
        }
        Text(option.text, style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
    }
}

// MARK: - 定级结果

/** “?”里的说明：怎么升级、为什么这样定、之后怎么校准 */
@Composable
fun assessmentRules(result: SkillAssessmentResult): List<String> = buildList {
    val gate = result.limitingGate
    if (gate != null) {
        add(gate)
    } else if (result.tier < SkillAssessment.maxTier) {
        val next = result.tier.offset(1)
        SkillLevel.tierCriteria(next).firstOrNull()?.let { add(tr("想到 %@：%@", next.code, it)) }
    }
    if (result.needsCalibration) add(tr("你的比赛经历比技术题的结果高，先按经历定级；打几场后会按球友评价更快校准。"))
    if (result.isReturning) add(tr("回归球友：按现在的状态定级，球友评价会帮你更快回到原来的水平。"))
    if (result.tier == SkillAssessment.maxTier) {
        add(tr("%@ 是问卷能给的最高档；球友评价最多推到 %@，7 起凭证据认证。", SkillAssessment.maxTier.code, VerificationStatus.unverifiedMaxTier.code))
    }
    if (result.suggestsVerification) add(tr("打过 A 组或 Open 组？7 起凭赛果、全国排名或运动员等级证书认证，注册后在资料页申请。"))
    add(tr("打满 5 场并获得评价后，等级会按球友评价自动校准。"))
}

/** 柠檬色的结果卡。深色模式下也用浅色的配色（底是柠檬色，字都是墨色） */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AssessmentResultCard(result: SkillAssessmentResult, modifier: Modifier = Modifier) {
    BadieTheme(Appearance.Light) {
        val colors = AppTheme.colors
        val ink = colors.onAccent
        val soft = ink.copy(alpha = 0.75f)
        Column(
            modifier
                .fillMaxWidth()
                .sticker(colors.lime, radius = AppTheme.Radius.lg)
                .padding(AppTheme.Spacing.xl)
                .semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            Text(tr("你的等级"), style = AppTheme.Typography.footnoteBold, color = soft)
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(result.tier.text, style = rounded(44, FontWeight.Black), color = ink, modifier = Modifier.alignByBaseline())
                Text(result.tier.name, style = AppTheme.Typography.title2, color = ink, modifier = Modifier.alignByBaseline())
            }
            Text(
                tr("%@：%@", result.tier.code, SkillLevel.tierCriteria(result.tier).firstOrNull() ?: result.tier.modifier.meaning),
                style = AppTheme.Typography.subheadlineBold, color = ink,
            )
            SkillLevel.usFlight(result.level)?.let {
                Text(tr("大致相当于美国业余赛 %@", it), style = AppTheme.Typography.footnote, color = soft)
            }
            if (result.dimensions.isNotEmpty()) DimensionProfile(result)
            result.play?.let { PlaySection(it) }
            val tags = buildList {
                if (result.needsCalibration) add(tr("按经历定级"))
                if (result.isReturning) add(tr("回归球友"))
                if (result.suggestsVerification) add(tr("可申请认证"))
            }
            if (tags.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (tag in tags) TagPill(tag, fill = Color.White.copy(alpha = 0.7f), foreground = ink)
                }
            }
        }
    }
}

/** 打法：类型、一句话、最佳搭档 */
@Composable
private fun PlaySection(play: PlayProfile) {
    val ink = AppTheme.colors.onAccent
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(tr("打法"), style = AppTheme.Typography.footnoteBold, color = ink.copy(alpha = 0.75f))
        Text(play.style.title, style = AppTheme.Typography.title2, color = ink)
        Text(play.style.line, style = AppTheme.Typography.subheadline, color = ink)
        Text(tr("最佳搭档：%@", play.style.partnerText), style = AppTheme.Typography.footnoteBold, color = ink)
    }
}

/** 技术分项：每项几级，最强的标出来（技术特点），最弱的用蜜桃色 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DimensionProfile(result: SkillAssessmentResult) {
    val colors = AppTheme.colors
    val ink = colors.onAccent
    val strengths = result.strengths.map { it.id }.toSet()
    val lowest = result.dimensions.minOf { it.rating }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(tr("技术分项"), style = AppTheme.Typography.footnoteBold, color = ink.copy(alpha = 0.75f))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (dimension in result.dimensions) {
                val isStrength = dimension.id in strengths
                val isWeak = strengths.isNotEmpty() && dimension.rating == lowest
                val fill = if (isWeak) colors.peach else Color.White.copy(alpha = if (isStrength) 0.9f else 0.55f)
                val label = when {
                    isStrength -> tr("%@ %@ 级，技术特点", dimension.name, dimension.code)
                    isWeak -> tr("%@ %@ 级，短板", dimension.name, dimension.code)
                    else -> tr("%@ %@ 级", dimension.name, dimension.code)
                }
                Row(
                    Modifier
                        .clip(CircleShape)
                        .drawBehind { drawRect(fill) }
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                        .clearAndSetSemantics { contentDescription = label },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (isStrength) Symbol(Sym.starFill, size = 9, tint = ink)
                    Text("${dimension.name} ${dimension.code}", style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Bold), color = ink)
                }
            }
        }
    }
}
