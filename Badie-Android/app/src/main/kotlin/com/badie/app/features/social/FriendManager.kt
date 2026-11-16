package com.badie.app.features.social

import androidx.compose.runtime.Stable
import com.badie.app.shell.ManagerContext

/**
 * 占位：球友、好友申请、屏蔽
 * 对应 iPhone 的 Managers/SocialManagers.swift 的 FriendManager。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改
 */
@Stable
class FriendManager(private val context: ManagerContext) {
    /** 收到、还没处理的好友申请（消息标签的角标） */
    val incomingRequestCount: Int get() = 0

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {}
}
