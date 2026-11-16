package com.badie.app.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.BrutalTextField
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.InfoRow
import com.badie.app.design.LevelBadge
import com.badie.app.design.LoadingDots
import com.badie.app.design.NoticeBanner
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.VerifiedBadge
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.SkillLevel
import com.badie.app.models.SkillTier
import com.badie.app.models.VerificationEvidence
import com.badie.app.models.VerificationRequest
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.launch

// MARK: - 高水平认证申请（7− 起）。对应 iPhone 的 Features/Profile/VerificationView.swift

private val evidenceKinds = listOf(VerificationStatus.Tournament, VerificationStatus.National, VerificationStatus.Bwf)

@Composable
fun VerificationView() {
    val env = LocalEnv.current
    val appState = env.appState
    val api = rememberProfileApi()
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val user = appState.currentUser
    // 已认证过：默认从下一类证据开始
    val start = remember {
        if (user != null && user.verificationStatus != VerificationStatus.Unverified) {
            evidenceKinds.firstOrNull { it.maxTier > user.tierCap } ?: VerificationStatus.Bwf
        } else {
            VerificationStatus.Tournament
        }
    }
    var kind by remember { mutableStateOf(start) }
    var tier by remember { mutableStateOf(start.minTier) }
    var link by remember { mutableStateOf("") }
    var nameOnRecord by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var isSubmitting by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try {
            api.refreshVerification()
        } catch (_: RemoteError) {
        }
    }
    val request = api.verification
    val linkProblem = if (link.isEmpty()) null else VerificationEvidence.problem(link, kind)
    val canSubmit = !isSubmitting && link.isNotEmpty() && linkProblem == null && nameOnRecord.trim().length >= 2

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("高水平认证"), onBack = { env.router.pop() }) {
            RulesButton(
                tr("高水平认证"),
                listOf(
                    tr("问卷最高 6+，球友评价最多到 7−。7 起（州级以上）只看能公开查到的证据：赛事成绩、全国排名或运动员等级证书、BWF 世界排名。"),
                    tr("认证后以认证档位为准；球友评价最多往下调 1 档（比如伤病、状态下滑）。"),
                    tr("链接和姓名只给审核人员看，不会公开；审核时会核对证件。冒用他人成绩会被封号。"),
                ),
            )
        }
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            if (user != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    LevelBadge(user.displayTier)
                    VerifiedBadge(user.verificationStatus)
                }
            }
            if (request != null && request.status == VerificationRequest.Status.Pending) {
                PendingCard(request, api)
            } else {
                if (request != null && request.status == VerificationRequest.Status.Rejected) {
                    NoticeBanner(Sym.exclamationmarkCircleFill, tr("上次没通过：%@", request.reviewNote ?: tr("证据无法核实")), tint = AppTheme.colors.peach)
                }
                KindPicker(kind) { option ->
                    haptics.selection()
                    kind = option
                    tier = minOf(maxOf(tier, option.minTier), option.maxTier)
                }
                TierPicker(tier, kind) { tier = it }
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    BrutalTextField(
                        if (kind == VerificationStatus.National) tr("证据链接或证书编号") else tr("证据链接"),
                        VerificationEvidence.placeholder(kind), link, { link = it },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), errorText = linkProblem,
                    )
                    BrutalTextField(
                        tr("成绩 / 证书上的姓名"), tr("和证件一致，例如 Wei Zhang"), nameOnRecord, { nameOnRecord = limited(it, 40) }, characterLimit = 40,
                    )
                    MultilineField(tr("补充说明（选填）"), tr("例：2025 洛杉矶公开赛 A 组男双亚军"), note, { note = it }, 200)
                }
            }
        }
        if (request?.status != VerificationRequest.Status.Pending) {
            BrutalButton(
                {
                    isSubmitting = true
                    scope.launch {
                        try {
                            api.submitVerification(kind, tier, link, nameOnRecord, note)
                            haptics.success()
                            appState.showToast(L10n.tr("已提交，审核结果会发到通知里"), Toast.Style.Success)
                        } catch (error: RemoteError) {
                            haptics.error()
                            appState.showError(error)
                        } finally {
                            isSubmitting = false
                        }
                    }
                },
                Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.md),
                enabled = canSubmit,
            ) {
                if (isSubmitting) LoadingDots()
                Text(tr("提交审核"))
            }
        }
    }
}

@Composable
private fun PendingCard(request: VerificationRequest, api: ProfileApi) {
    val appState = LocalEnv.current.appState
    val scope = rememberCoroutineScope()
    Column(Modifier.card(AppTheme.colors.surface, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TagPill(tr("审核中"), icon = Sym.hourglass, fill = AppTheme.colors.butter)
            RulesButton(tr("审核中"), listOf(tr("一般 %lld 个工作日内审核完，结果会发到通知里。", VerificationRequest.REVIEW_DAYS)))
            Spacer(Modifier.weight(1f))
            Text(tr("提交于 %@", DateText.shortDay(request.submittedAt)), style = AppTheme.Typography.caption, color = AppTheme.colors.inkSecondary)
        }
        InfoRow(Sym.checkmarkSealFill, tr("申请 %@", request.claimedTier.text), tint = AppTheme.colors.lime, subtitle = request.kind.title)
        InfoRow(Sym.link, tr("证据"), subtitle = request.evidenceURL)
        InfoRow(Sym.personTextRectangle, tr("证据上的姓名"), tint = AppTheme.colors.peach, subtitle = request.nameOnRecord)
        BrutalButton(tr("撤回申请"), {
            scope.launch {
                try {
                    api.withdrawVerification()
                    appState.showToast(L10n.tr("已撤回申请"))
                } catch (error: RemoteError) {
                    appState.showError(error)
                }
            }
        }, kind = ButtonKind.Secondary, size = ButtonSize.Small)
    }
}

/** 区块标题 + “?” */
@Composable
private fun SectionHeader(title: String, rules: List<String>, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = AppTheme.Typography.title3, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        RulesButton(title, rules)
    }
}

/** 每类证据一行；具体怎么换算档位在“?”里 */
@Composable
private fun evidenceLine(kind: VerificationStatus): String = when (kind) {
    VerificationStatus.Unverified -> ""
    VerificationStatus.Tournament -> tr("tournamentsoftware.com 上的签表和成绩")
    VerificationStatus.National -> tr("USAB 全国排名或运动员技术等级证书")
    VerificationStatus.Bwf -> tr("bwfbadminton.com 上本人的球员页")
}

@Composable
private fun KindPicker(kind: VerificationStatus, onSelect: (VerificationStatus) -> Unit) {
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionHeader(tr("证据类型"), evidenceKinds.map(SkillLevel::evidenceSummary))
        for (option in evidenceKinds) {
            val selected = kind == option
            Row(
                Modifier
                    .fillMaxWidth()
                    .pressable(scale = 1f, role = Role.RadioButton) { onSelect(option) }
                    .semantics { this.selected = selected }
                    .sticker(if (selected) colors.lime.copy(alpha = 0.35f).compositeOver(colors.surface) else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                    .padding(AppTheme.Spacing.md),
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                Symbol(if (selected) Sym.largecircleFillCircle else Sym.circle, size = 18, tint = colors.ink)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(option.title, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                        Text(
                            SkillTier.rangeText(option.minTier, option.maxTier), style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"),
                            color = colors.ink,
                        )
                    }
                    Text(evidenceLine(option), style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun TierPicker(tier: SkillTier, kind: VerificationStatus, onChange: (SkillTier) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionHeader(tr("申请的档位"), listOf(tr("按证据能证明的最高一档填，审核时可能下调")), Modifier.weight(1f))
            TierStepper(tier, kind.minTier, kind.maxTier, onChange, Modifier.width(170.dp))
        }
        Column(
            Modifier
                .fillMaxWidth()
                .sticker(AppTheme.colors.surfaceMuted, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                .padding(AppTheme.Spacing.md),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (line in SkillLevel.tierCriteria(tier)) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Symbol(Sym.checkmark, size = 12, tint = AppTheme.colors.ink, modifier = Modifier.padding(top = 3.dp))
                    Text(line, style = AppTheme.Typography.footnote, color = AppTheme.colors.ink)
                }
            }
        }
    }
}

/** 档位的加减：中间写档位名和“Lv.7−”（对应 iPhone CreateRoomView.swift 的 TierStepper） */
@Composable
fun TierStepper(tier: SkillTier, lower: SkillTier, upper: SkillTier, onChange: (SkillTier) -> Unit, modifier: Modifier = Modifier) {
    val haptics = rememberHaptics()
    fun step(delta: Int) {
        val next = tier.offset(delta)
        if (next == tier || next < lower || next > upper) return
        haptics.selection()
        onChange(next)
    }
    val label = tr("水平")
    Row(
        modifier
            .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = 4.dp)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = tier.displayText
                customActions = listOf(CustomAccessibilityAction("+") { step(1); true }, CustomAccessibilityAction("−") { step(-1); true })
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(40.dp, 44.dp).pressable(scale = 0.85f, enabled = tier != lower) { step(-1) }, contentAlignment = Alignment.Center) {
            Symbol(Sym.minus, size = 14, tint = if (tier != lower) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(tier.name, style = AppTheme.Typography.caption, color = AppTheme.colors.inkSecondary, maxLines = 1)
            Text(tier.text, style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = AppTheme.colors.ink)
        }
        Box(Modifier.size(40.dp, 44.dp).pressable(scale = 0.85f, enabled = tier != upper) { step(1) }, contentAlignment = Alignment.Center) {
            Symbol(Sym.plus, size = 14, tint = if (tier != upper) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
        }
    }
}
