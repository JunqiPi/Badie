package com.badie.app.push

import android.Manifest
import android.content.Context
import android.os.Build
import com.badie.app.backend.ProfileStore
import com.badie.app.features.games.ReminderService
import com.badie.app.models.MessageThread
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import com.google.firebase.messaging.FirebaseMessaging
import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder

/**
 * 推送（Firebase Cloud Messaging，免费）：允许了通知就向 Firebase 要这台设备的令牌，登录状态下交给服务器（register_push，kind 是 fcm）。
 * 服务器有新通知时推过来，由 [BadieMessagingService] 显示。对应 iPhone 的 Services/PushRegistry.swift。
 *
 * Firebase 的配置在 res/values/firebase.xml（不用 Google Services 插件）。AndroidManifest.xml 里关了自动要令牌：
 * 没允许通知就不要（和 iPhone 一样），单元测试里也不连网
 */
object PushRegistry {
    /** 这台设备的令牌；每次启动都重新要，可能会变 */
    @Volatile
    var token: String? = null
        private set

    /** 拿到令牌后要做的事：登录状态下报给服务器（见 BadieApplication） */
    var onToken: ((String) -> Unit)? = null

    /** 弹系统的通知权限框（Android 13 起要问）：MainActivity 在的时候才有 */
    var askPermission: (() -> Unit)? = null

    /** 每次启动、登录后：已经允许通知的，重新要一次令牌 */
    fun refresh(context: Context) {
        if (ReminderService.canNotify(context)) fetchToken()
    }

    /** 发出约球请求后：配上了要第一时间知道。没问过就问一次，拒绝过的不再打扰 */
    fun askAfterRequest(context: Context) {
        if (ReminderService.canNotify(context)) return fetchToken()
        // Android 13 以前不用问：默认能发，关了的只能去系统设置打开
        if (Build.VERSION.SDK_INT < 33) return
        val ask = askPermission ?: return
        // 和设置页“球局提醒”那一行同一个记号：问过以后那里显示“已关闭”，点了去系统设置
        val store = ProfileStore.preferences(context)
        val key = "asked-${Manifest.permission.POST_NOTIFICATIONS}"
        if (store.load(key) != null) return
        store.save(key, "1")
        ask()
    }

    private fun fetchToken() {
        val messaging = try {
            FirebaseMessaging.getInstance()
        } catch (_: IllegalStateException) {
            // Firebase 没有初始化（单元测试里）
            return
        }
        // 没有 Google Play 服务的手机要不到，不影响别的
        messaging.token.addOnSuccessListener { didRegister(it) }
    }

    fun didRegister(token: String) {
        this.token = token
        onToken?.invoke(token)
    }

    /**
     * 推送里带的网址（/app/games/<id>/ 这种）和点开的 badie.rsvp 链接（https://badie.rsvp/join/?code=… 这种），
     * 网页和 App 共用一套地址，对应 App 里的页面
     */
    fun route(link: String): Pair<Route, MainTab> {
        val uri = try {
            URI(link)
        } catch (_: URISyntaxException) {
            null
        }
        val parts = (uri?.path ?: link).split("/").filter { it.isNotEmpty() && it != "app" }
        val id = parts.getOrNull(1)
        // 聊天：/messages/dm/<对方>/、/messages/game/<球局>/、/messages/group/<球群>/
        if (parts.firstOrNull() == "messages" && parts.size > 2) {
            when (parts[1]) {
                "dm" -> return Route.Chat(parts[2]) to MainTab.Messages
                "game" -> return Route.GroupChat(MessageThread.gameThreadId(parts[2])) to MainTab.Messages
                "group" -> return Route.GroupChat(MessageThread.groupThreadId(parts[2])) to MainTab.Messages
            }
        }
        val first = parts.firstOrNull()
        return when {
            first == "games" && id != null -> Route.Game(id) to MainTab.Games
            first == "rooms" && id != null -> Route.Room(id) to MainTab.Games
            first == "groups" && id != null -> Route.Group(id) to MainTab.Games
            first == "matches" && id != null -> Route.Match(id) to MainTab.Games
            first == "join" -> Route.JoinRoom(query(uri, "code")) to MainTab.Games
            first == "challenges" -> Route.Challenges to MainTab.Games
            else -> Route.Notifications to MainTab.Home
        }
    }

    private fun query(uri: URI?, name: String): String? =
        uri?.rawQuery?.split("&")?.firstNotNullOfOrNull { item ->
            val pair = item.split("=", limit = 2)
            if (pair.first() == name) URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8") else null
        }
}
