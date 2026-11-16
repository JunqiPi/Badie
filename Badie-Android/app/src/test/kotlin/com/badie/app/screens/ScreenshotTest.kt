package com.badie.app.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.badie.app.TestSupport
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.InfoRow
import com.badie.app.design.InsetDivider
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.MenuRow
import com.badie.app.design.NoticeBanner
import com.badie.app.design.SectionTitle
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.Toast
import com.badie.app.design.ToastView
import com.badie.app.design.card
import com.badie.app.features.onboarding.CaptchaModel
import com.badie.app.l10n.L10n
import com.badie.app.features.onboarding.GenderPromptView
import com.badie.app.features.onboarding.OnboardingFlow
import com.badie.app.features.onboarding.OnboardingModel
import com.badie.app.features.onboarding.OnboardingStep
import com.badie.app.features.onboarding.VenuePicker
import com.badie.app.features.profile.LanguagePicker
import com.badie.app.features.profile.SettingsView
import com.badie.app.models.Avatar
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.SkillAssessment
import com.badie.app.remote.HttpResponse
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.CreateMenuSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTabView
import com.badie.app.shell.SplashView
import com.github.takahirom.roborazzi.captureRoboImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 把界面渲染成图，放在 app/build/outputs/roborazzi（CI 上作为产物上传），用来和 iPhone 的截图对照。
 * 不比对像素，只出图；页面搬过来一个就在这里加一张。
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class ScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @After
    fun detach() = L10n.detach()

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        // 不在界面里取的文字（按钮标题、出错提示）也跟着这次的语言
        L10n.attach(RuntimeEnvironment.getApplication())
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), TestSupport.backend())
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    @Test
    fun mainTabs() = shot("main-zh") { MainTabView() }

    @Test
    fun mainTabsEnglishDark() = shot("main-en-dark", qualifiers = "en", appearance = Appearance.Dark) { MainTabView() }

    @Test
    fun createMenu() = shot("create-menu-zh") { CreateMenuSheet {} }

    @Test
    fun createMenuJapanese() = shot("create-menu-ja", qualifiers = "ja") { CreateMenuSheet {} }

    @Test
    fun splash() = shot("splash") { SplashView() }

    // 从网站下载安装的包有新版本时，标签栏上面那一条
    @Test
    fun updateBanner() = shot("update-banner") { UpdateBannerSample() }

    @Test
    fun updateBannerEnglishDark() = shot("update-banner-en-dark", qualifiers = "en", appearance = Appearance.Dark) { UpdateBannerSample() }

    @Composable
    private fun UpdateBannerSample() {
        Column(Modifier.padding(AppTheme.Spacing.lg).fillMaxWidth()) {
            com.badie.app.shell.UpdateBanner(
                com.badie.app.shell.AndroidRelease(7, "1.0.6", com.badie.app.shell.SideloadUpdates.APK_URL), onDownload = {}, onDismiss = {},
            )
        }
    }

    @Test
    fun components() = shot("components-zh") { Components() }

    @Test
    fun componentsDark() = shot("components-dark", appearance = Appearance.Dark) { Components() }

    // MARK: 登录和注册

    private fun onboarding(step: OnboardingStep, environment: AppEnvironment, setUp: OnboardingModel.() -> Unit = {}): OnboardingModel =
        OnboardingModel(environment.appState, CaptchaModel(), passwordLookup = { HttpResponse(200, ByteArray(0)) }, initialStep = step).apply(setUp)

    @Test
    fun welcome() = shot("onboarding-1-welcome") { OnboardingFlow(onboarding(OnboardingStep.Welcome, LocalEnv.current)) }

    @Test
    fun welcomeEnglishDark() = shot("onboarding-1-welcome-en-dark", qualifiers = "en", appearance = Appearance.Dark) {
        OnboardingFlow(onboarding(OnboardingStep.Welcome, LocalEnv.current))
    }

    @Test
    fun emailSignIn() = shot("onboarding-2-email") {
        OnboardingFlow(onboarding(OnboardingStep.Email, LocalEnv.current) { email = "alex@example.com"; captcha.receive("""{"token":""}""") })
    }

    @Test
    fun emailRegisterWithError() = shot("onboarding-2-register-en", qualifiers = "en") {
        OnboardingFlow(
            onboarding(OnboardingStep.Email, LocalEnv.current) {
                toggleNewAccount(); email = "alex@example"; password = "shuttle rally"; agreed = true
                captcha.receive("""{"token":""}"""); errorText = L10n.tr("邮箱地址好像不对。")
            },
        )
    }

    @Test
    fun code() = shot("onboarding-3-code") {
        OnboardingFlow(onboarding(OnboardingStep.Code, LocalEnv.current) { email = "alex@example.com"; resendRemaining = 42 })
    }

    @Test
    fun profile() = shot("onboarding-4-profile") {
        OnboardingFlow(onboarding(OnboardingStep.Profile, LocalEnv.current) { nickname = "阿杰"; gender = Gender.Male; avatar = Avatar("", 2) })
    }

    @Test
    fun levelQuestion() = shot("onboarding-5-question") {
        OnboardingFlow(onboarding(OnboardingStep.Level, LocalEnv.current) { assessmentAnswers["clear"] = 3 })
    }

    @Test
    fun levelResult() = shot("onboarding-5-result", qualifiers = "b+zh+Hans-h1500dp") {
        OnboardingFlow(onboarding(OnboardingStep.Level, LocalEnv.current) { assessmentAnswers.putAll(SkillAssessment.levelCardDemoAnswers) })
    }

    @Test
    fun levelResultDarkJapanese() = shot("onboarding-5-result-ja-dark", qualifiers = "ja-h1500dp", appearance = Appearance.Dark) {
        OnboardingFlow(onboarding(OnboardingStep.Level, LocalEnv.current) { assessmentAnswers.putAll(SkillAssessment.demoAnswers) })
    }

    @Test
    fun preferences() = shot("onboarding-6-preferences") {
        OnboardingFlow(onboarding(OnboardingStep.Preferences, LocalEnv.current) { preferredMode = GameMode.Doubles })
    }

    @Test
    fun preferencesWithoutVenue() = shot("onboarding-6-preferences-no-venue") {
        OnboardingFlow(onboarding(OnboardingStep.Preferences, LocalEnv.current) { noVenueListed = true })
    }

    @Test
    fun venuePicker() = shot("onboarding-6-venue-picker") {
        val model = onboarding(OnboardingStep.Preferences, LocalEnv.current)
        androidx.compose.runtime.LaunchedEffect(Unit) { model.locationUpdated(null) }
        VenuePicker(model) {}
    }

    @Test
    fun settings() = shot("settings") { SettingsView() }

    @Test
    fun languagePicker() = shot("language-picker-ko", qualifiers = "ko") { LanguagePicker {} }

    @Test
    fun coverCard() = shot("cover-card") {
        val user = com.badie.app.models.User.create("u-7", "欣然", selfReportedLevel = 4).copy(tag = 42)
        Column(Modifier.padding(AppTheme.Spacing.screen).fillMaxWidth()) {
            com.badie.app.design.CoverCard(user, pill = "3.2 公里 · 常去 LABC", line = "双打 · 靠谱", modifier = Modifier.height(480.dp)) {
                com.badie.app.design.NoShowPill(1)
            }
            Row(Modifier.padding(top = 24.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                com.badie.app.design.RoundActionLabel(Sym.xmark, AppTheme.colors.surface)
                com.badie.app.design.RoundActionLabel(Sym.heartFill, AppTheme.colors.lime)
                com.badie.app.design.RoundActionLabel(Sym.starFill, AppTheme.colors.butter)
            }
        }
    }

    @Test
    fun genderPrompt() = shot("gender-prompt") { GenderPromptView() }

    /** 设计系统的基础组件摆在一页上 */
    @Composable
    private fun Components() {
        val colors = AppTheme.colors
        Column(Modifier.fillMaxSize().padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            LargeTitleHeader("球局", subtitle = "Lv.4+ 中级") {
                IconButton(Sym.plus, "约球", badge = 3) {}
            }
            Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                ToastView(Toast("资料已保存", Toast.Style.Success))
                BrutalButton("快速匹配", {})
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    BrutalButton("发起球局", {}, Modifier.weight(1f), kind = ButtonKind.Inverse, size = ButtonSize.Medium)
                    BrutalButton("取消", {}, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium)
                    BrutalButton("删除", {}, Modifier.weight(1f), kind = ButtonKind.Destructive, size = ButtonSize.Medium, enabled = false)
                }
                SectionTitle("本周", detail = "3 场", actionTitle = "全部", action = {})
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    StatTile("12", "场次", Modifier.weight(1f))
                    StatTile("58%", "胜率", Modifier.weight(1f), accent = colors.lime)
                    StatTile("4+", "等级", Modifier.weight(1f), accent = colors.lavender)
                }
                Column(Modifier.card()) {
                    InfoRow(Sym.sportscourtFill, "LA Badminton Club", subtitle = "周六 19:00 · 双打")
                    InsetDivider()
                    MenuRow(Sym.person3Fill, "固定局 · 球群", value = "2", badge = 1) {}
                }
                NoticeBanner(Sym.exclamationmarkTriangleFill, "开启定位", actionTitle = "设置", action = {})
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    com.badie.app.design.LevelBadge(com.badie.app.models.SkillTier(4, com.badie.app.models.SkillTier.Modifier.Plus))
                    com.badie.app.design.ReliableBadge()
                    com.badie.app.design.NewPlayerBadge()
                }
                EmptyStateView(Sym.figureBadminton, "附近暂时没有人", tint = colors.sky)
            }
        }
    }
}
