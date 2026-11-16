package com.badie.app.push

import android.content.Intent
import com.badie.app.features.messages.MessageManager
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import com.badie.app.shell.Router

/**
 * 处理通知（本地提醒和服务器推送）：前台也展示；点了打开对应页面。对应 iPhone 的 Services/NotificationRouter.swift。
 * 点通知会带着 [EXTRA_GAME]（本地提醒）或 [EXTRA_LINK]（服务器推送）打开 MainActivity，MainActivity 交给 [open]。
 * 都在主线程调
 */
object NotificationRouter {
    const val EXTRA_LINK = "link"
    const val EXTRA_GAME = "gameId"

    private var router: Router? = null
    private var messages: MessageManager? = null

    /** 冷启动时点的通知比界面先到：先记下，界面好了再打开 */
    var pending: Pair<Route, MainTab>? = null
        private set

    /** 界面在前台（MainActivity 在 onStart 和 onStop 之间） */
    @Volatile
    var isForeground = false

    /** 主界面出来了（登录以后） */
    fun attach(router: Router, messages: MessageManager?) {
        this.router = router
        this.messages = messages
        pending?.let {
            router.show(it.first, it.second)
            pending = null
        }
    }

    /** 主界面没了（退出登录） */
    fun detach(router: Router) {
        if (this.router !== router) return
        this.router = null
        messages = null
    }

    /**
     * 推送到了，要不要显示。在前台时：新消息马上拉会话列表和正开着的会话；正开着这个会话就不再弹
     */
    fun willPresent(link: String?): Boolean {
        if (!isForeground || link == null || !link.contains("/messages/")) return true
        messages?.refreshNow()
        return router?.isShowing(PushRegistry.route(link).first) != true
    }

    /** 点了通知：打开对应页面。返回是不是通知打开的 */
    fun open(intent: Intent?): Boolean {
        val target = target(intent?.getStringExtra(EXTRA_GAME), intent?.getStringExtra(EXTRA_LINK)) ?: return false
        // 只处理一次（转屏、从最近任务回来不再跳）
        intent?.removeExtra(EXTRA_GAME)
        intent?.removeExtra(EXTRA_LINK)
        open(target)
        return true
    }

    fun open(target: Pair<Route, MainTab>) {
        val router = router
        if (router != null) router.show(target.first, target.second) else pending = target
    }

    /** 本地提醒带 gameId；服务器推送带 link（和网页同一个地址） */
    fun target(gameId: String?, link: String?): Pair<Route, MainTab>? = when {
        gameId != null -> Route.Game(gameId) to MainTab.Games
        link != null -> PushRegistry.route(link)
        else -> null
    }
}
