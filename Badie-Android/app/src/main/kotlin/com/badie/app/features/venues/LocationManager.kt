package com.badie.app.features.venues

import androidx.compose.runtime.Stable
import com.badie.app.shell.ManagerContext

/**
 * 占位：位置、附近的球馆、常去球馆
 * 对应 iPhone 的 Managers/LocationManager.swift。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改
 */
@Stable
class LocationManager(private val context: ManagerContext) {
    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {}
}
