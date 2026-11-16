package com.badie.app.features.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.FitText
import com.badie.app.design.LevelBadge
import com.badie.app.design.LoadingDots
import com.badie.app.design.RatingPicker
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.AttendanceAnswer
import com.badie.app.models.DateText
import com.badie.app.models.LevelCalibration
import com.badie.app.models.PendingSurvey
import com.badie.app.models.SkillTier
import com.badie.app.models.SurveyIssue
import com.badie.app.models.SurveyTag
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.launch

// 待评价列表和评价表单。对应 iPhone 的 Features/Surveys/SurveyViews.swift

@Composable
fun SurveyListScreen() {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val surveys = env.surveyManager.pendingSurveys
    LaunchedEffect(Unit) {
        try {
            env.surveyManager.refresh()
        } catch (_: RemoteError) {
        }
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("待评价"), onBack = { env.router.pop() }) {
            RulesButton(
                tr("评价规则"),
                listOf(
                    tr("评价匿名，只展示汇总结果；双方都提交后（或 48 小时后）才会计入，避免“互相客气”和报复性差评。"),
                    tr("评价需要在球局结束后 48 小时内完成。"),
                ),
            )
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            if (surveys.isEmpty()) EmptyStateView(Sym.checkmarkSealFill, tr("都评价完了"), tint = colors.mint)
            for (survey in surveys) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .pressable(scale = 0.98f) { env.router.open(Route.Survey(survey.id)) }
                        .sticker(colors.surface, radius = AppTheme.Radius.lg)
                        .padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    AvatarView(survey.opponentId, survey.opponentAvatarText, survey.opponentAvatar.paletteIndex, size = 46.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(tr("评价 %@", survey.opponentNickname), style = AppTheme.Typography.headline, color = colors.ink)
                        Text(
                            "${DateText.relativeDay(survey.matchDate)} · ${survey.courtName}", style = AppTheme.Typography.footnote,
                            color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                    TagPill(DateText.remaining(survey.expiresAt), icon = Sym.hourglass, fill = colors.pink)
                }
            }
        }
    }
}

// MARK: - 评价表单

@Composable
fun SurveyFormScreen(pendingId: String) {
    val env = LocalEnv.current
    // 提交前保存一份，避免提交后列表刷新导致页面消失
    val snapshot = remember { env.surveyManager.survey(pendingId) }
    val survey = env.surveyManager.survey(pendingId) ?: snapshot
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("赛后评价"), onBack = { env.router.pop() }) {
            RulesButton(
                tr("评价规则"),
                listOf(tr("评价匿名，只展示汇总；双方都提交后（或 48 小时后）才会计入。"), tr("评价需要在球局结束后 48 小时内完成。")),
            )
        }
        if (survey != null) {
            SurveyForm(survey)
        } else {
            Spacer(Modifier.weight(1f))
            EmptyStateView(Sym.hourglassBottomhalfFilled, tr("这份评价已提交或已过期"))
            Spacer(Modifier.weight(1f))
        }
    }
}

/** 评价表单里选的东西（纯数据，方便测试） */
internal data class SurveyAnswers(
    val attendance: AttendanceAnswer = AttendanceAnswer.OnTime,
    val calibration: LevelCalibration? = LevelCalibration.Accurate,
    val skillRating: SkillTier,
    val characterRating: Int = 5,
    val tags: Set<SurveyTag> = emptySet(),
    val issues: Set<SurveyIssue> = emptySet(),
    val wantsRematch: Boolean = false,
) {
    /** 精确调档：正好是高 / 低 / 差不多一档时，三选一跟着亮 */
    fun withTier(tier: SkillTier, displayed: SkillTier): SurveyAnswers =
        copy(skillRating = tier, calibration = LevelCalibration.entries.firstOrNull { it.rating(displayed) == tier })

    fun withCalibration(option: LevelCalibration, displayed: SkillTier): SurveyAnswers =
        copy(calibration = option, skillRating = option.rating(displayed))

    /** 给了好评（问不问商店评分看这个） */
    val isPositive: Boolean get() = attendance != AttendanceAnswer.NoShow && characterRating >= 4
}

@Composable
private fun ColumnScope.SurveyForm(survey: PendingSurvey) {
    val env = LocalEnv.current
    val context = LocalContext.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var answers by remember(survey.id) { mutableStateOf(SurveyAnswers(skillRating = survey.opponentTier)) }
    var submitting by remember { mutableStateOf(false) }
    Column(
        Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xxl),
    ) {
        OpponentCard(survey)
        Question(tr("TA 准时到场了吗？"), listOf(tr("到场情况会计入对方的履约记录"))) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                for (answer in AttendanceAnswer.entries) {
                    OptionCard(
                        answer.title, null, attendanceIcon(answer), answers.attendance == answer,
                        if (answer == AttendanceAnswer.NoShow) colors.pink else colors.lime, Modifier.weight(1f),
                    ) { answers = answers.copy(attendance = answer) }
                }
            }
        }
        Question(tr("TA 的实际水平和标注的 %@ 比？", survey.opponentTier.text), listOf(tr("高低各一档（1/3 级）；差得多就精确调，越如实越好"))) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                for (option in LevelCalibration.entries) {
                    OptionCard(
                        option.title, option.rating(survey.opponentTier).text, calibrationIcon(option), answers.calibration == option,
                        colors.lime, Modifier.weight(1f),
                    ) { answers = answers.withCalibration(option, survey.opponentTier) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(tr("精确到档"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.weight(1f))
                TierStepper(answers.skillRating, Modifier.width(180.dp)) { answers = answers.withTier(it, survey.opponentTier) }
            }
        }
        Question(tr("球品如何？"), listOf(tr("只用于匹配排序，不会显示分数。"))) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                RatingPicker(answers.characterRating, { answers = answers.copy(characterRating = it) })
                Text(characterHint(answers.characterRating), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            }
        }
        Question(tr("TA 的优点（可选）"), listOf(tr("5 位以上球友评价后，大家给得最多的会显示在 TA 的主页"))) {
            Flow {
                for (tag in SurveyTag.entries) {
                    ChoiceChip(tag.title, tag in answers.tags, tint = colors.mint) {
                        answers = answers.copy(tags = if (tag in answers.tags) answers.tags - tag else answers.tags + tag)
                    }
                }
            }
        }
        Question(tr("有什么需要 TA 注意的？（可选）"), listOf(tr("不公开、不扣分；多位球友都提到时，我们会私下提醒 TA，不说是谁"))) {
            Flow {
                for (issue in SurveyIssue.entries) {
                    ChoiceChip(issue.title, issue in answers.issues, tint = colors.peach) {
                        answers = answers.copy(issues = if (issue in answers.issues) answers.issues - issue else answers.issues + issue)
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("下次还想和 TA 打"), style = AppTheme.Typography.headline, color = colors.ink)
            RulesButton(tr("下次还想和 TA 打"), listOf(tr("只有你们都选了才会告诉双方；只有一方选，谁也不会知道")))
            Spacer(Modifier.weight(1f))
            BadieSwitch(answers.wantsRematch, { answers = answers.copy(wantsRematch = it) })
        }
    }
    BrutalButton(
        onClick = {
            submitting = true
            scope.launch {
                try {
                    env.surveyManager.submit(
                        survey, answers.skillRating, answers.attendance,
                        SurveyTag.entries.filter { it in answers.tags }, SurveyIssue.entries.filter { it in answers.issues }, answers.wantsRematch,
                    )
                    env.appState.showToast(L10n.tr("评价已提交，谢谢。"), Toast.Style.Success)
                    env.router.pop()
                    val next = env.surveyManager.pending(survey.matchId).firstOrNull()
                    if (next != null) {
                        env.router.open(Route.Survey(next.id))
                    } else if (RatingPrompt.shouldAsk(context, env.appState.currentUser?.totalGames ?: 0, answers.isPositive)) {
                        RatingPrompt.markAsked(context)
                        // TODO：这里该弹 Google Play 的应用内评价（要加 com.google.android.play:review 依赖）
                    }
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
                submitting = false
            }
        },
        modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.md),
        enabled = !submitting && !survey.isExpired(System.currentTimeMillis()),
    ) {
        if (submitting) {
            LoadingDots()
            Spacer(Modifier.width(AppTheme.Spacing.sm))
        }
        FitText(tr("提交评价"))
    }
}

@Composable
private fun OpponentCard(survey: PendingSurvey) {
    val ink = AppTheme.colors.onAccent
    Row(
        Modifier.card(AppTheme.colors.lavender),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        AvatarView(survey.opponentId, survey.opponentAvatarText, survey.opponentAvatar.paletteIndex, size = 60.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(survey.opponentNickname, style = AppTheme.Typography.title3, color = ink)
            LevelBadge(survey.opponentTier)
            Text(
                "${DateText.relativeDay(survey.matchDate)} · ${survey.courtName}", style = AppTheme.Typography.footnote,
                color = ink.copy(alpha = 0.75f), maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Symbol(Sym.hourglass, size = 16, tint = ink)
            Text(DateText.remaining(survey.expiresAt), style = AppTheme.Typography.caption, color = ink)
        }
    }
}

/** 一句问题 + “?”（为什么问、结果怎么用） */
@Composable
private fun Question(title: String, rules: List<String>, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.weight(1f, fill = false).semantics { heading() })
            RulesButton(title, rules)
        }
        content()
    }
}

@Composable
private fun OptionCard(title: String, subtitle: String?, icon: SymbolId, isSelected: Boolean, tint: Color, modifier: Modifier, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val ink = if (isSelected) colors.onAccent else colors.ink
    Column(
        modifier
            .pressable {
                haptics.selection()
                onClick()
            }
            .semantics(mergeDescendants = true) { selected = isSelected }
            .defaultMinSize(minHeight = 84.dp)
            .sticker(if (isSelected) tint else colors.surface, radius = AppTheme.Radius.md, shadow = if (isSelected) AppTheme.Elevation.low else AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.md, horizontal = AppTheme.Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Symbol(icon, size = 20, tint = ink)
        FitText(title, style = AppTheme.Typography.subheadlineBold, color = ink)
        if (subtitle != null) Text(subtitle, style = AppTheme.Typography.caption, color = ink.copy(alpha = 0.75f))
    }
}

@Composable
private fun characterHint(rating: Int): String = when (rating) {
    1 -> tr("很差：言语冒犯或危险动作")
    2 -> tr("较差：不太尊重人")
    3 -> tr("一般")
    4 -> tr("不错：友善配合")
    else -> tr("非常好：下次还想约")
}

private fun attendanceIcon(answer: AttendanceAnswer): SymbolId = when (answer) {
    AttendanceAnswer.OnTime -> Sym.checkmarkCircleFill
    AttendanceAnswer.Late -> Sym.tortoiseFill
    AttendanceAnswer.NoShow -> Sym.personFillXmark
}

private fun calibrationIcon(option: LevelCalibration): SymbolId = when (option) {
    LevelCalibration.Lower -> Sym.arrowDownCircleFill
    LevelCalibration.Accurate -> Sym.equalCircleFill
    LevelCalibration.Higher -> Sym.arrowUpCircleFill
}

/** 细分档位步进器（1− … 9+）。对应 iPhone 的 TierStepper（在 CreateRoomView.swift 里） */
@Composable
internal fun TierStepper(tier: SkillTier, modifier: Modifier = Modifier, range: ClosedRange<SkillTier> = SkillTier.all.first()..SkillTier.all.last(), onChange: (SkillTier) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    fun step(delta: Int) {
        val next = tier.offset(delta)
        if (next == tier || next !in range) return
        haptics.selection()
        onChange(next)
    }
    val label = tr("水平")
    Row(
        modifier
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = 4.dp)
            .semantics { contentDescription = label; stateDescription = tier.spokenText },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(40.dp, 44.dp).pressable(scale = 0.85f, enabled = tier != range.start) { step(-1) }, contentAlignment = Alignment.Center) {
            Symbol(Sym.minus, size = 14, tint = if (tier != range.start) colors.ink else colors.inkTertiary)
        }
        Column(Modifier.weight(1f).clearAndSetSemantics {}, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(tier.name, style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1)
            Text(tier.text, style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink)
        }
        Box(Modifier.size(40.dp, 44.dp).pressable(scale = 0.85f, enabled = tier != range.endInclusive) { step(1) }, contentAlignment = Alignment.Center) {
            Symbol(Sym.plus, size = 14, tint = if (tier != range.endInclusive) colors.ink else colors.inkTertiary)
        }
    }
}
