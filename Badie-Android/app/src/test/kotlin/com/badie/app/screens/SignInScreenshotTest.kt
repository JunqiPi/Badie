package com.badie.app.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.badie.app.TestSupport
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.features.onboarding.CaptchaModel
import com.badie.app.features.onboarding.OnboardingFlow
import com.badie.app.features.onboarding.OnboardingModel
import com.badie.app.l10n.L10n
import com.badie.app.remote.HttpResponse
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.LocalEnv
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

/** 欢迎页的 Apple、Google 按钮：对着 iPhone 的欢迎页截图看（一屏放不放得下、长语言会不会挤） */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class SignInScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @After
    fun detach() = L10n.detach()

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, setUp: OnboardingModel.() -> Unit = {}, providers: Set<String>? = null) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), TestSupport.backend())
        val model = OnboardingModel(environment.appState, CaptchaModel(), passwordLookup = { HttpResponse(200, ByteArray(0)) }, savedProviders = providers)
            .apply(setUp)
        compose.setContent { Screen(environment, appearance) { OnboardingFlow(model) } }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    @Composable
    private fun Screen(environment: AppEnvironment, appearance: Appearance, content: @Composable () -> Unit) {
        CompositionLocalProvider(LocalEnv provides environment) {
            BadieTheme(appearance) { Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() } }
        }
    }

    @Test
    fun welcomeWithSocial() = shot("signin-welcome-zh")

    @Test
    fun welcomeSocialFailed() = shot("signin-welcome-failed-en-dark", qualifiers = "en", appearance = Appearance.Dark, setUp = {
        errorText = L10n.tr("登录没有完成，请再试一次，或改用邮箱。")
    })

    @Test
    fun welcomeLongLanguage() = shot("signin-welcome-vi", qualifiers = "vi")

    /** 后台只开了邮箱：和以前一样只有一个黑色大按钮 */
    @Test
    fun welcomeEmailOnly() = shot("signin-welcome-email-only", providers = setOf("email"))
}
