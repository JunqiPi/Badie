package com.badie.app.features.games

import androidx.compose.runtime.Stable
import com.badie.app.shell.ManagerContext

/**
 * 占位：赛后评价
 * 对应 iPhone 的 Managers/SocialManagers.swift 的 SurveyManager。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改
 */
@Stable
class SurveyManager(private val context: ManagerContext) {
    /** 待评价的份数（球局标签的角标） */
    val pendingCount: Int get() = 0

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {}
}
