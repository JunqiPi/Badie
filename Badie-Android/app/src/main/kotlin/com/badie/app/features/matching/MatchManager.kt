package com.badie.app.features.matching

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import com.badie.app.shell.ManagerContext

/**
 * 占位：快速匹配：约球请求、匹配结果
 * 对应 iPhone 的 Managers/MatchManager.swift。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改
 */
@Stable
class MatchManager(private val context: ManagerContext) {
    /** 匹配流程的全屏页开着（任何页面跳转都会把它关掉） */
    var isFlowPresented by androidx.compose.runtime.mutableStateOf(false)

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {}
}
