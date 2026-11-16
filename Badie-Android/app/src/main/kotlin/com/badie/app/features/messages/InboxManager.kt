package com.badie.app.features.messages

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.MessagesApi
import com.badie.app.backend.RemoteNotification
import com.badie.app.features.social.SocialCache
import com.badie.app.models.InboxItem
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 站内通知（最近 50 条）。对应 iPhone 的 Managers/SocialManagers.swift 的 InboxManager，
 * 和 MockBackend+RemoteSocial.swift 的 apply(notifications:)、MockBackend.swift 的 markInboxRead
 */
@Stable
class InboxManager(private val context: ManagerContext) {
    private val api = MessagesApi(context.backend.remote)
    private val cache = SocialCache.of(context.backend)

    /** 最新的在前 */
    var items by mutableStateOf<List<InboxItem>>(emptyList())
        private set

    private var owner: String? = null
    private var polling: Job? = null

    val unreadCount: Int get() = items.count { !it.isRead }

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {
        cache.syncAccount()
        val me = cache.me
        if (me != owner) {
            owner = me
            items = emptyList()
        }
        if (me == null) return
        apply(api.notifications())
    }

    internal fun apply(notifications: List<RemoteNotification>) {
        val latest = notifications.map { note ->
            InboxItem(
                id = "note-${note.id}", kind = MessagesApi.inboxKind(note.kind), title = note.title, body = note.body,
                createdAt = note.createdAt.toEpochMilli(), isRead = note.readAt != null, relatedId = MessagesApi.relatedId(note.kind, note.link),
            )
        }.sortedByDescending { it.createdAt }
        if (latest != items) items = latest
    }

    /** 标为已读：服务器一次把通知全部记为已读，所以本机也全部标上 */
    fun markRead(@Suppress("UNUSED_PARAMETER") item: InboxItem? = null) {
        if (items.none { !it.isRead }) return
        items = items.map { it.copy(isRead = true) }
        context.scope.launch {
            try {
                api.markNotificationsRead()
            } catch (error: RemoteError) {
                context.appState.showError(error)
            }
        }
    }

    // MARK: 轮询

    /** 没有实时推送：每 15 秒拉一次（回到前台时开始，退到后台时停） */
    fun startPolling() {
        if (polling?.isActive == true) return
        polling = context.scope.launch {
            while (isActive) {
                try {
                    refresh()
                } catch (_: RemoteError) {
                    // 网络问题：下次再拉
                }
                delay(MessageManager.POLL_MILLIS)
            }
        }
    }

    fun stopPolling() {
        polling?.cancel()
        polling = null
    }
}
