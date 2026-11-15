package com.badie.app.shell

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppLogo
import com.badie.app.design.AppTheme
import com.badie.app.design.ToastView
import com.badie.app.design.Wordmark
import com.badie.app.features.onboarding.GenderPromptView
import com.badie.app.features.onboarding.OnboardingFlow
import com.badie.app.models.Gender
import com.badie.app.design.reduceMotion
import kotlinx.coroutines.delay

@Composable
fun RootView() {
    val appState = LocalEnv.current.appState
    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) {
        AnimatedContent(appState.phase, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "phase") { phase ->
            when (phase) {
                AppState.Phase.Launching -> SplashView()
                AppState.Phase.Onboarding -> OnboardingFlow()
                AppState.Phase.Main -> {
                    MainTabView()
                    // 以前注册、还没选定级用的性别：先补上（男女等级分开算，匹配要用）
                    if (appState.currentUser?.gender == Gender.Unspecified) GenderPromptView()
                }
            }
        }
        ToastHost()
    }
}

/** 提示条：根页面和每个全屏页、弹层各挂一个（它们会盖住根页面的提示） */
@Composable
fun ToastHost(modifier: Modifier = Modifier) {
    val appState = LocalEnv.current.appState
    Box(modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(
            appState.toast != null,
            enter = slideInVertically { -it } + fadeIn(),
            exit = slideOutVertically { -it } + fadeOut(),
        ) {
            // 消失的过程中还要画着最后那一条
            var last by remember { mutableStateOf(appState.toast) }
            appState.toast?.let { last = it }
            last?.let {
                ToastView(
                    it,
                    Modifier.padding(top = AppTheme.Spacing.sm).clickable(remember { MutableInteractionSource() }, indication = null) { appState.toast = null },
                )
            }
        }
    }
}

@Composable
fun SplashView() {
    val appState = LocalEnv.current.appState
    val still = reduceMotion()
    var appeared by remember { mutableStateOf(false) }
    val reveal by animateFloatAsState(if (appeared) 1f else 0f, AppTheme.Motion.standard(), label = "reveal")
    val bounce = if (still) 0f else rememberInfiniteTransition(label = "bounce")
        .animateFloat(0f, 1f, infiniteRepeatable(tween(500), RepeatMode.Reverse), label = "bounce").value
    LaunchedEffect(Unit) {
        appeared = true
        delay(1300)
        appState.finishLaunch()
    }
    Column(
        Modifier.fillMaxSize().clearAndSetSemantics { contentDescription = "Badie" },
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        AppLogo(
            Modifier.size(120.dp).graphicsLayer {
                rotationZ = 4f - 10f * bounce
                translationY = -14.dp.toPx() * bounce
            },
        )
        Wordmark(
            Modifier.graphicsLayer {
                alpha = reveal
                translationY = 12.dp.toPx() * (1f - reveal)
            },
            size = 46,
        )
    }
}
