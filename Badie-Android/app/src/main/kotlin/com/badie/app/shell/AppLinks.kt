package com.badie.app.shell

import com.badie.app.l10n.L10n.tr
import com.badie.app.design.Toast
import com.badie.app.push.NotificationRouter
import com.badie.app.push.PushRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.net.URI
import java.net.URISyntaxException

/**
 * 点开 badie.rsvp 的链接（邀请、邮件里的球局、加球友二维码）直接进 App 里对应的页面（App Links）。
 * 对应 iPhone RootView 的 onOpenURL；哪些路径进 App 见 AndroidManifest.xml（和网站的 apple-app-site-association 一致）
 */
object AppLinks {
    const val HOST = "badie.rsvp"

    sealed interface Target {
        /** 普通页面：和推送同一套解析（[PushRegistry.route]） */
        data class Page(val route: Route, val tab: MainTab) : Target
        /** 加球友链接 /add/<码>/：找到人就打开他的资料（在那里加球友） */
        data class FriendLink(val code: String) : Target
        /** 等级页 /levels/<档>/（别的语言前面带 /zh/ 这类前缀） */
        data object Levels : Target
    }

    /** 不是 badie.rsvp 的链接为空 */
    fun target(link: String): Target? {
        val uri = try {
            URI(link)
        } catch (_: URISyntaxException) {
            return null
        }
        if (uri.host != HOST) return null
        val parts = (uri.path ?: "").split("/").filter { it.isNotEmpty() }
        if (parts.firstOrNull() == "add" && parts.size > 1) return Target.FriendLink(parts[1])
        val levels = parts.indexOf("levels")
        if (levels in 0..1) return Target.Levels
        val (route, tab) = PushRegistry.route(link)
        return Target.Page(route, tab)
    }

    /** 打开链接；不是 badie.rsvp 的返回 false。主界面还没出来时（冷启动）先记下，出来再跳 */
    fun open(link: String, env: AppEnvironment, scope: CoroutineScope): Boolean {
        val target = target(link) ?: return false
        when (target) {
            is Target.Page -> NotificationRouter.open(target.route to target.tab)
            is Target.Levels -> {
                // 没登录不处理（和 iPhone 一样）。没定级就进编辑资料去测，定过级打开等级对照表
                val user = env.appState.currentUser ?: return true
                val route = if (user.assessment == null && user.verifiedRating == null) Route.EditProfile else Route.LevelGuide
                NotificationRouter.open(route to MainTab.Profile)
            }
            is Target.FriendLink -> scope.launch { openFriendLink(target.code, env) }
        }
        return true
    }

    private suspend fun openFriendLink(code: String, env: AppEnvironment) {
        val appState = env.appState
        try {
            val userId = env.friendManager.openFriendLink(code)
            if (userId != null) {
                if (userId == appState.currentUser?.id) appState.showToast(tr("这是你自己的加球友链接"))
                appState.showPlayer(userId)
            } else {
                appState.showToast(tr("这个加球友链接已失效"), Toast.Style.Error)
            }
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            appState.showError(error)
        }
    }
}
