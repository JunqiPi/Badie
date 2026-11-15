package com.badie.app.shell

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.badie.app.design.Appearance
import com.badie.app.design.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Stable
class AppState(private val scope: CoroutineScope) {
    enum class Phase { Launching, Onboarding, Main }

    var phase by mutableStateOf(Phase.Launching)
        private set

    var toast by mutableStateOf<Toast?>(null)

    var appearance by mutableStateOf(Appearance.System)

    private var toastJob: Job? = null

    /** 启动页放完 */
    fun finishLaunch() {
        if (phase == Phase.Launching) phase = Phase.Main
    }

    /** 顶部的提示条，2.6 秒后自己消失 */
    fun showToast(message: String, style: Toast.Style = Toast.Style.Info) {
        toastJob?.cancel()
        val shown = Toast(message, style)
        toast = shown
        toastJob = scope.launch {
            delay(TOAST_MILLIS)
            if (toast?.id == shown.id) toast = null
        }
    }

    companion object {
        const val TOAST_MILLIS = 2600L
    }
}

/** 整个 App 共用的状态和管理器，对应 iPhone 的 AppEnvironment */
class AppEnvironment(scope: CoroutineScope) {
    val appState = AppState(scope)
    val router = Router()
}

val LocalEnv = staticCompositionLocalOf<AppEnvironment> { error("没有提供 AppEnvironment") }
