package com.badie.app.features.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import com.badie.app.design.AppLogo
import com.badie.app.design.IconTile
import com.badie.app.design.SheetScaffold
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.location.LocationProvider
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.BrutalTextField
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.CodeField
import com.badie.app.design.GenderPicker
import com.badie.app.design.IconButton
import com.badie.app.design.LegalLinksRow
import com.badie.app.design.LoadingDots
import com.badie.app.design.PasswordField
import com.badie.app.design.ProgressBar
import com.badie.app.design.RulesButton
import com.badie.app.design.StickerTextField
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TextAction
import com.badie.app.design.Wordmark
import com.badie.app.design.markedText
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.Avatar
import com.badie.app.models.GameMode
import com.badie.app.models.SkillAssessment
import com.badie.app.remote.OkHttpTransport
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 登录和注册：欢迎页，然后 5 步（邮箱、验证码、称呼、定级、最后一步），顶部有返回和进度条 */
@Composable
fun OnboardingFlow() {
    val appState = LocalEnv.current.appState
    OnboardingFlow(remember { OnboardingModel(appState, CaptchaModel(), OkHttpTransport.transport) })
}

@Composable
fun OnboardingFlow(model: OnboardingModel) {
    val scope = rememberCoroutineScope()
    // 重发验证码的倒计时
    LaunchedEffect(model.resendRemaining) {
        if (model.resendRemaining > 0) {
            delay(1000)
            model.resendRemaining -= 1
        }
    }
    BackHandler(enabled = model.step != OnboardingStep.Welcome) { model.goBack() }

    Column(
        Modifier.fillMaxSize().background(AppTheme.colors.canvas).windowInsetsPadding(WindowInsets.safeDrawing).imePadding(),
    ) {
        if (model.step == OnboardingStep.Welcome) {
            Welcome(Modifier.weight(1f))
        } else {
            Header(model)
            AnimatedContent(model.step, Modifier.weight(1f), transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "step") { step ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = AppTheme.Spacing.screen)
                        .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.xxl),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
                        when (step) {
                            OnboardingStep.Welcome -> Unit
                            OnboardingStep.Email -> EmailStep(model) { scope.launch { it() } }
                            OnboardingStep.Code -> CodeStep(model) { scope.launch { it() } }
                            OnboardingStep.Profile -> ProfileStep(model)
                            OnboardingStep.Level -> LevelStep(model)
                            OnboardingStep.Preferences -> PreferencesStep(model)
                        }
                    }
                }
            }
        }
        Footer(model) { scope.launch { model.primaryAction() } }
    }
}

// MARK: 顶部：返回和进度条

@Composable
private fun Header(model: OnboardingModel) {
    val index = model.step.progressIndex
    val total = OnboardingStep.PROGRESS_TOTAL
    Row(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconButton(Sym.chevronLeft, tr("上一步")) { model.goBack() }
        ProgressBar(index.toFloat() / total, Modifier.weight(1f), height = 14.dp, minimumFill = 14.dp, label = tr("第 %lld 步，共 %lld 步", index, total))
        Text(
            "$index/$total", style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = AppTheme.colors.inkSecondary,
            modifier = Modifier.clearAndSetSemantics {},
        )
    }
}

/** 标题 + 可选的一行副标题；说明放进旁边的“?” */
@Composable
private fun StepTitle(title: String, subtitle: String? = null, rulesTitle: String? = null, rules: List<String> = emptyList()) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(title, style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        if (subtitle != null || rules.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (subtitle != null) Text(subtitle, style = AppTheme.Typography.subheadline, color = AppTheme.colors.inkSecondary)
                if (rules.isNotEmpty()) RulesButton(rulesTitle ?: title, rules)
            }
        }
    }
}

@Composable
private fun ErrorLine(text: String?) {
    if (text != null) Text(text, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.danger)
}

// MARK: 欢迎页

/** 只有 Logo 和一句话，登录按钮在下面：一屏放得下，不用滚动（屏幕矮时 Logo 自动缩小） */
@Composable
private fun Welcome(modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen), contentAlignment = Alignment.Center) {
        val logo = (maxHeight * 0.3f).coerceIn(88.dp, 168.dp)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
            AppLogo(Modifier.size(logo))
            Wordmark(size = 34)
            Text(
                markedText(tr("羽毛球搭子？\n就在*今日*。")),
                style = AppTheme.Typography.display.copy(lineHeight = AppTheme.Typography.display.fontSize * 1.4f),
                color = AppTheme.colors.ink, textAlign = TextAlign.Center,
            )
        }
    }
}

// MARK: 邮箱

@Composable
private fun EmailStep(model: OnboardingModel, run: (suspend () -> Unit) -> Unit) {
    val emailFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { emailFocus.requestFocus() }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        StepTitle(if (model.newAccount) tr("注册 Badie") else tr("用邮箱登录"))
        TextAction(
            if (model.newAccount) tr("已有账号？去登录") else tr("还没有账号？注册一个"),
            onClick = { model.toggleNewAccount() }, color = AppTheme.colors.ink,
        )
    }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        StickerTextField(
            model.email, { model.email = it; model.edited() }, tr("邮箱"),
            invalid = model.errorText != null,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Email, imeAction = ImeAction.Next,
            ),
            // 密码管理器把密码存到这个邮箱名下，下次自动填
            contentType = ContentType.Username + ContentType.EmailAddress,
            focusRequester = emailFocus,
        )
        PasswordField(
            model.password, { model.password = it; model.edited() },
            placeholder = if (model.newAccount) tr("密码（至少 8 位）") else tr("密码"),
            isNew = model.newAccount, invalid = model.errorText != null,
            onSubmit = { if (model.canContinue) run { model.primaryAction() } },
        )
    }
    ErrorLine(model.errorText)
    if (model.newAccount) {
        AgreeRow(model.agreed) { model.agreed = !model.agreed }
        LegalLinksRow()
    } else {
        // 忘了密码，或者以前用验证码登录、还没设过密码
        val enabled = !model.isWorking && model.captcha.isReady
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextAction(tr("忘记密码？"), { run { model.sendEmailCode(CodePurpose.Recovery) } }, enabled = enabled)
            TextAction(tr("改用邮箱验证码登录"), { run { model.sendEmailCode(CodePurpose.Email) } }, enabled = enabled)
        }
    }
}

/** 注册要勾的那一行 */
@Composable
private fun AgreeRow(agreed: Boolean, onToggle: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(
        Modifier
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Checkbox) {
                haptics.selection()
                onToggle()
            }
            .semantics(mergeDescendants = true) { selected = agreed },
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(if (agreed) Sym.checkmarkSquareFill else Sym.square, size = 22, tint = if (agreed) colors.ink else colors.inkTertiary)
        Text(
            tr("我已阅读并同意《用户协议》和《隐私政策》，了解邮箱仅用于登录与安全验证，不会展示给其他球友。"),
            style = AppTheme.Typography.footnote, color = colors.inkSecondary,
        )
    }
}

// MARK: 验证码

@Composable
private fun CodeStep(model: OnboardingModel, run: (suspend () -> Unit) -> Unit) {
    val codeFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { codeFocus.requestFocus() }
    StepTitle(if (model.isResettingPassword) tr("重设密码") else tr("输入验证码"), subtitle = tr("已发送至 %@", model.email))
    CodeField(model.code, { value -> run { model.updateCode(value) } }, focusRequester = codeFocus)
    if (model.isResettingPassword) {
        PasswordField(
            model.password, { model.password = it; model.edited() }, placeholder = tr("新密码（至少 8 位）"),
            isNew = true, invalid = model.errorText != null,
            onSubmit = { if (model.canContinue) run { model.primaryAction() } },
        )
    }
    ErrorLine(model.errorText)
    TextAction(
        if (model.resendRemaining > 0) tr("%lld 秒后可重新发送", model.resendRemaining) else tr("重新发送验证码"),
        onClick = { run { model.sendEmailCode(model.codePurpose) } },
        enabled = model.resendRemaining == 0 && !model.isWorking && model.captcha.isReady,
    )
}

// MARK: 怎么称呼你

@Composable
private fun ProfileStep(model: OnboardingModel) {
    val colors = AppTheme.colors
    StepTitle(tr("怎么称呼你？"))
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        AvatarView(
            model.avatar.text(model.nickname.trim()), paletteIndex = model.avatar.paletteIndex, size = 96.dp,
            modifier = Modifier.drawBehind { drawCircle(colors.shadow, center = center.copy(x = center.x + 3.dp.toPx(), y = center.y + 4.dp.toPx())) },
        )
    }
    AvatarPaletteEditor(model.avatar) { model.avatar = it }
    BrutalTextField(
        tr("昵称"), tr("2-12 个字"), model.nickname, { model.nickname = it; model.edited() },
        errorText = model.errorText, characterLimit = 12,
    )
    GenderPicker(model.gender, { model.gender = it })
}

/** 头像：6 种颜色，加上表情或昵称的第一个字 */
@Composable
fun AvatarPaletteEditor(avatar: Avatar, onChange: (Avatar) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val symbols = listOf("", "🏸", "😎", "🐯", "🦊", "🐼", "⚡️", "🍑")
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            colors.palette.forEachIndexed { index, color ->
                val isSelected = avatar.paletteIndex == index
                val label = tr("颜色 %lld", index + 1)
                Box(
                    Modifier
                        .size(44.dp)
                        .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.RadioButton) {
                            haptics.selection()
                            onChange(avatar.copy(paletteIndex = index))
                        }
                        .semantics { contentDescription = label; selected = isSelected },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.size(36.dp).drawBehind {
                            val width = (if (isSelected) 3.5.dp else 2.dp).toPx()
                            drawCircle(color)
                            drawCircle(colors.stroke, radius = size.minDimension / 2 - width / 2, style = Stroke(width))
                        },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (isSelected) Symbol(Sym.checkmark, size = 13, tint = colors.onAccent)
                    }
                }
            }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            for (symbol in symbols) {
                ChoiceChip(symbol.ifEmpty { tr("昵称首字") }, isSelected = avatar.symbol == symbol) { onChange(avatar.copy(symbol = symbol)) }
            }
        }
    }
}

// MARK: 测一下你的水平

@Composable
private fun LevelStep(model: OnboardingModel) {
    StepTitle(
        tr("测一下你的水平"), subtitle = tr("%lld 道题", SkillAssessment.questions.size), rulesTitle = tr("怎么定级"),
        rules = listOf(
            tr("按你能稳定做到的选，不按偶尔打出来的球。"),
            tr("答完自动算出等级，细分到 −、本级、+。"),
            tr("问卷最高到 6+（俱乐部顶尖）；7 起是州级以上，凭赛果、全国排名、运动员等级证书或 BWF 世界排名认证。打满 5 场后会按球友评价自动校准。"),
            tr("跳过的话先按 Lv.%lld 匹配，之后可以在资料页完成定级。", SkillAssessment.PROVISIONAL_LEVEL),
        ),
    )
    SkillAssessmentView(model.assessmentAnswers)
    if (model.assessmentResult == null) {
        val hint = tr("之后可以在资料页完成定级")
        Box(
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 44.dp)
                .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClickLabel = hint) { model.skipAssessment() },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                tr("先跳过"), style = AppTheme.Typography.footnoteBold.copy(textDecoration = TextDecoration.Underline),
                color = AppTheme.colors.inkSecondary,
            )
        }
    }
}

// MARK: 最后一步

@Composable
private fun PreferencesStep(model: OnboardingModel) {
    val colors = AppTheme.colors
    StepTitle(tr("最后一步"))
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(tr("常打"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            ChoiceChip(tr("单打"), model.preferredMode == GameMode.Singles, icon = GameMode.Singles.icon) { model.preferredMode = GameMode.Singles }
            ChoiceChip(tr("双打"), model.preferredMode == GameMode.Doubles, icon = GameMode.Doubles.icon) { model.preferredMode = GameMode.Doubles }
            ChoiceChip(tr("都行"), model.preferredMode == null) { model.preferredMode = null }
        }
    }
    FavoriteVenuesCard(model)
    LocationCard(model)
}

/** 常去球馆：选一次，以后快速匹配默认就是它们（选同一家的人才会被匹配到一起），附近的人也按它找到你 */
@Composable
private fun FavoriteVenuesCard(model: OnboardingModel) {
    val colors = AppTheme.colors
    var showPicker by remember { mutableStateOf(false) }
    val venues = model.favoriteVenueIds.mapNotNull(model::venue)
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("常去球馆"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            RulesButton(
                tr("常去球馆"),
                listOf(tr("选好后，快速匹配默认用这几家。"), tr("选了同一家球馆的人才会被匹配到一起。"), tr("附近的人按常去球馆找到你。")),
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .pressable(scale = 0.98f) { showPicker = true }
                .sticker(colors.surface, radius = AppTheme.Radius.lg)
                .padding(AppTheme.Spacing.lg)
                .semantics(mergeDescendants = true) {},
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            IconTile(Sym.figureBadminton, fill = colors.lime, size = 48.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (venues.isEmpty()) {
                    Text(tr("添加球馆"), style = AppTheme.Typography.headline, color = colors.ink)
                    Text(tr("至少选一家"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                } else {
                    for (venue in venues) Text(venue.name, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary, modifier = Modifier.padding(top = 4.dp))
        }
        // 我们还没收录的地方搜不到球馆：可以先不选，以后在球馆页再选
        if (venues.isEmpty()) {
            if (model.noVenueListed) {
                Text(tr("好的，以后可以在球馆页再选。"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            } else {
                Text(
                    tr("列表里没有我的球馆"), style = AppTheme.Typography.footnoteBold.copy(textDecoration = TextDecoration.Underline),
                    color = colors.inkSecondary,
                    modifier = Modifier
                        .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { model.noVenueListed = true }
                        .padding(vertical = AppTheme.Spacing.xs),
                )
            }
        }
    }
    if (showPicker) {
        SheetScaffold(onDismiss = { showPicker = false }, fullHeight = true) { VenuePicker(model) { showPicker = false } }
    }
}

/** 定位：找附近的球馆和球友，只在用 App 时取。给了以后读附近的球馆，并替人选上最近的一家 */
@Composable
private fun LocationCard(model: OnboardingModel) {
    val colors = AppTheme.colors
    val context = LocalContext.current
    val provider = remember { LocationProvider(context) }
    val scope = rememberCoroutineScope()
    var authorized by remember { mutableStateOf(provider.isAuthorized) }
    var asked by remember { mutableStateOf(false) }
    val refresh: () -> Unit = { scope.launch { model.locationUpdated(provider.current()) } }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        asked = true
        authorized = result.values.any { it }
        refresh()
    }
    LaunchedEffect(Unit) { refresh() }
    Row(
        Modifier.card(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(if (authorized) Sym.locationFill else Sym.location, fill = colors.sky, size = 48.dp)
        Text(if (authorized) tr("已开启定位") else tr("开启定位"), style = AppTheme.Typography.headline, color = colors.ink)
        RulesButton(tr("定位"), listOf(tr("用于找附近的球馆和球友，只在使用 App 时获取")))
        Spacer(Modifier.weight(1f))
        when {
            authorized -> Symbol(Sym.checkmarkCircleFill, size = 24, tint = colors.success)
            // 拒绝过一次以后系统不再弹窗，这时不放按钮（和 iPhone 一样）
            !asked -> BrutalButton(tr("允许"), { launcher.launch(LocationProvider.PERMISSIONS) }, size = ButtonSize.Small, fullWidth = false)
        }
    }
}

// MARK: 底部的大按钮

@Composable
private fun Footer(model: OnboardingModel, onPrimary: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(AppTheme.colors.canvas)
            .padding(horizontal = AppTheme.Spacing.screen)
            .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        // 发请求前的人机验证：填邮箱和输验证码（重新发送）两步都要
        if (model.step == OnboardingStep.Email || model.step == OnboardingStep.Code) CaptchaArea(model.captcha)
        BrutalButton(
            onPrimary,
            kind = if (model.step == OnboardingStep.Welcome) ButtonKind.Inverse else ButtonKind.Primary,
            enabled = model.canContinue && !model.isWorking,
        ) {
            if (model.isWorking) {
                LoadingDots()
                Spacer(Modifier.size(AppTheme.Spacing.sm))
            }
            Text(model.primaryTitle, maxLines = 1)
        }
    }
}

/** 平时看不见；Cloudflare 要人点一下时才展开验证框 */
@Composable
private fun CaptchaArea(captcha: CaptchaModel) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        CaptchaView(
            captcha,
            Modifier
                .fillMaxWidth()
                .height(if (captcha.needsInteraction) 72.dp else 1.dp)
                .alpha(if (captcha.needsInteraction) 1f else 0.01f)
                .then(if (captcha.needsInteraction) Modifier else Modifier.clearAndSetSemantics {}),
        )
        if (captcha.failed) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(
                    tr("人机验证没加载出来，请检查网络后重试。"), style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.danger,
                    modifier = Modifier.weight(1f),
                )
                TextAction(tr("重试"), { captcha.reset() })
            }
        }
    }
}
