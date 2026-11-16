package com.badie.app.features.messages

import androidx.compose.runtime.Stable
import com.badie.app.shell.ManagerContext

/**
 * 占位：私信和群聊
 * 对应 iPhone 的 Managers/SocialManagers.swift 的 MessageManager。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改
 */
@Stable
class MessageManager(private val context: ManagerContext) {
    /** 没读的消息数（消息标签的角标） */
    val unreadCount: Int get() = 0
}
