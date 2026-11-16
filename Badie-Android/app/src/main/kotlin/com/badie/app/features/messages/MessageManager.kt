package com.badie.app.features.messages

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.BackendError
import com.badie.app.backend.MessagesApi
import com.badie.app.backend.RemoteMessageOption
import com.badie.app.backend.RemoteThreadSummary
import com.badie.app.backend.SocialApi
import com.badie.app.features.social.SocialCache
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.BlockedUser
import com.badie.app.models.Message
import com.badie.app.models.MessageThread
import com.badie.app.models.MessageValidation
import com.badie.app.models.ReportReason
import com.badie.app.models.ThreadContext
import com.badie.app.models.User
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** 能不能私信某人、在哪聊。对应 iPhone MockBackend+Conversations.swift 的 MessagePermission */
sealed interface MessagePermission {
    data object Allowed : MessagePermission
    /** 可以发一条消息请求（同球群） */
    data class Request(val groupName: String) : MessagePermission
    /** 已经发过请求，等对方接受 */
    data object PendingRequest : MessagePermission
    /** 在同一场球局里：去球局群聊 */
    data class GameChat(val gameId: String) : MessagePermission
    /** 陌生人：先加好友 */
    data object FriendsOnly : MessagePermission
    /** 新账号还不能发消息请求 */
    data object NewAccount : MessagePermission
    /** 我屏蔽了对方 */
    data object Blocked : MessagePermission
}

/**
 * 私信和群聊（球局群、球群）。对应 iPhone 的 Managers/SocialManagers.swift 的 MessageManager，
 * 和 MockBackend+RemoteSocial.swift、MockBackend+Conversations.swift、MockBackend+Social.swift 里连正式后端的部分。
 * 没有实时推送：每 15 秒拉一次会话列表，正开着的会话连消息一起拉
 */
@Stable
class MessageManager(private val context: ManagerContext) {
    private val api = MessagesApi(context.backend.remote)
    private val social = SocialApi(context.backend.remote)
    private val now: () -> Long = System::currentTimeMillis

    val cache: SocialCache = SocialCache.of(context.backend).also {
        if (context.android != null) it.android = context.android
        it.refreshThreads = { refreshThreads() }
    }

    /** 会话 ID → 会话（服务器给的，加上本机打开过的群聊） */
    private var threadMap by mutableStateOf<Map<String, MessageThread>>(emptyMap())

    /** 群聊能不能发言：服务器给的 open / closed */
    private val access = mutableStateMapOf<String, String>()

    private val messagesByThread = mutableStateMapOf<String, List<Message>>()
    private val loadedAt = HashMap<String, Long>()

    /** 当前打开的会话（打开期间新消息自动已读） */
    var activeThreadId: String? = null
        private set

    private var polling: Job? = null

    val currentUserId: String? get() = cache.me

    /** 能看到的会话：删除后没有新消息的不显示，屏蔽的人的私信不显示；最近的在前 */
    val threads: List<MessageThread>
        get() {
            val me = cache.me ?: return emptyList()
            val blocked = cache.blockedIds()
            return threadMap.values
                .map { thread -> cache.clearedAt[thread.id]?.let { thread.copy(clearedAt = thread.clearedAt + (me to it)) } ?: thread }
                .filter { me in it.participantIds && it.isVisible(me) }
                .filter { thread -> thread.isGroup || thread.otherParticipantId(me)?.let { it !in blocked } == true }
                .sortedByDescending { it.lastActivityAt }
        }

    /** 没读的消息数（消息标签的角标） */
    val unreadCount: Int
        get() {
            val me = cache.me ?: return 0
            return threads.sumOf { it.unreadCount(me) }
        }

    /** 别人发来、我还没处理的消息请求 */
    val incomingRequests: List<MessageThread> get() = threads.filter { it.isPendingRequest && it.requestFrom != currentUserId }

    /** 普通会话（不含待处理的请求） */
    val conversations: List<MessageThread> get() = threads.filter { !(it.isPendingRequest && it.requestFrom != currentUserId) }

    val blockedUsers: List<BlockedUser> get() = cache.blocked

    fun user(id: String): User? = cache.user(id)

    fun thread(id: String): MessageThread? = threadMap[id]

    fun threadId(userId: String): String? = cache.me?.let { MessageThread.id(it, userId) }

    fun threadWith(userId: String): MessageThread? = threadId(userId)?.let(threadMap::get)

    fun messages(threadId: String): List<Message> {
        val list = messagesByThread[threadId] ?: return emptyList()
        val cleared = cache.clearedAt[threadId] ?: return list.takeLast(DEFAULT_MESSAGE_LIMIT)
        return list.filter { it.sentAt > cleared }.takeLast(DEFAULT_MESSAGE_LIMIT)
    }

    fun messagesWith(userId: String): List<Message> = threadId(userId)?.let(::messages) ?: emptyList()

    fun isBlocked(userId: String): Boolean = cache.isBlocked(userId)

    // MARK: 私信规则

    fun permission(userId: String): MessagePermission {
        val me = cache.me
        if (me == null || userId == me) return MessagePermission.FriendsOnly
        if (cache.isBlocked(userId)) return MessagePermission.Blocked
        if (cache.isFriend(userId)) return MessagePermission.Allowed
        threadMap[MessageThread.id(me, userId)]?.takeIf { it.isPendingRequest }?.let {
            // 对方发来的请求：回复即接受
            return if (it.requestFrom == me) MessagePermission.PendingRequest else MessagePermission.Allowed
        }
        sharedOpenGame(userId)?.let { return MessagePermission.GameChat(it) }
        val option = cache.messageOptions[userId] ?: return MessagePermission.FriendsOnly
        return when (option.status) {
            "friends", "open" -> MessagePermission.Allowed
            "requested" -> MessagePermission.PendingRequest
            "request" -> MessagePermission.Request(option.group ?: "")
            "new_account" -> MessagePermission.NewAccount
            else -> MessagePermission.FriendsOnly
        }
    }

    /** 和对方共同的、群聊仍开放的球局（最早的那场） */
    private fun sharedOpenGame(userId: String): String? {
        val me = cache.me ?: return null
        val time = now()
        return cache.games.filter { me in it.playerIds && userId in it.playerIds && it.isChatOpen(time) }.minByOrNull { it.startsAt }?.id
    }

    /** 群聊是否还能发言 */
    fun canPost(threadId: String): Boolean {
        val me = cache.me ?: return false
        val thread = threadMap[threadId] ?: return false
        if (me !in thread.participantIds) return false
        return when (val context = thread.context) {
            is ThreadContext.Game -> access[threadId]?.let { it == "open" }
                ?: cache.games.firstOrNull { it.id == context.gameId }?.isChatOpen(now()) ?: false
            is ThreadContext.Group -> access[threadId]?.let { it == "open" } ?: true
            null -> true
        }
    }

    /** 私信会话在服务器上存在或者可以开始（球友、请求、可以发请求）时才去拉 */
    private fun canOpenRemoteThread(threadId: String): Boolean {
        if (threadMap.containsKey(threadId)) return true
        val target = MessagesApi.serverThread(threadId, cache.me) ?: return true
        if (target.first != "dm") return true
        return when (permission(target.second)) {
            MessagePermission.Allowed, is MessagePermission.Request, MessagePermission.PendingRequest -> true
            else -> false
        }
    }

    // MARK: 拉取

    /** 下拉刷新：重新读一遍会话列表（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {
        refreshThreads()
    }

    suspend fun refreshThreads() {
        cache.syncAccount()
        val me = cache.me ?: return
        apply(api.myThreads(), me)
    }

    internal fun apply(summaries: List<RemoteThreadSummary>, me: String) {
        val threads = LinkedHashMap<String, MessageThread>()
        val changed = ArrayList<String>()
        for (summary in summaries) {
            val id = MessagesApi.threadId(summary.kind, summary.id, me)
            val existing = threadMap[id]
            var participants = listOf(me)
            var threadContext: ThreadContext? = null
            when (summary.kind) {
                "dm" -> {
                    participants = participants + summary.id
                    summary.name?.let { cache.cache(summary.id, it, null) }
                }
                "game" -> {
                    threadContext = ThreadContext.Game(summary.id)
                    participants = cache.games.firstOrNull { it.id == summary.id }?.playerIds?.takeIf { it.isNotEmpty() }
                        ?: existing?.participantIds ?: participants
                }
                else -> {
                    threadContext = ThreadContext.Group(summary.id)
                    participants = existing?.participantIds ?: participants
                }
            }
            val last = summary.last?.let { last ->
                val sentAt = last.createdAt.toEpochMilli()
                // 别人发的最后一条：私信是对方，群聊不知道是谁（列表只显示内容）
                Message(
                    id = "last-$id", threadId = id, senderId = if (last.mine) me else if (summary.kind == "dm") summary.id else "",
                    content = last.body, sentAt = sentAt, deliveredAt = sentAt,
                )
            }
            threads[id] = MessageThread(
                id = id, participantIds = participants, lastMessage = last,
                lastActivityAt = last?.sentAt ?: summary.startsAt?.toEpochMilli() ?: existing?.lastActivityAt ?: now(),
                unreadCounts = mapOf(me to summary.unread),
                context = threadContext,
                title = if (summary.kind == "dm") null else summary.name ?: summary.venue,
                requestFrom = when (summary.request) {
                    "incoming" -> summary.id
                    "outgoing" -> me
                    else -> null
                },
                isPendingRequest = summary.request != null,
            )
            if (summary.kind != "dm") access[id] = summary.access
            if (last != null && (existing?.lastMessage?.sentAt != last.sentAt || existing.lastMessage.content != last.content)) changed += id
        }
        // 本机打开过、服务器列表里还没有的群聊（刚建的群、刚确认的球局）留着
        for ((id, thread) in threadMap) if (thread.isGroup && id !in threads && thread.lastMessage == null) threads[id] = thread
        if (threads != threadMap) threadMap = threads
        // 正开着的会话来了新消息：马上拉
        activeThreadId?.takeIf { it in changed }?.let { id -> context.scope.launch { loadQuietly(id) } }
    }

    /** 拉取一个会话的消息（服务器同时记为已读） */
    suspend fun loadThread(threadId: String) {
        cache.syncAccount()
        val me = cache.me ?: throw RemoteError.NotSignedIn
        val target = MessagesApi.serverThread(threadId, me) ?: return
        loadedAt[threadId] = now()
        val thread = api.openThread(target.first, target.second)
        for (member in thread.members.orEmpty()) if (!member.me) cache.cache(member.id, member.nickname, null)
        messagesByThread[threadId] = thread.messages.map { item ->
            val sentAt = item.createdAt.toEpochMilli()
            Message(
                id = "message-${item.id}", threadId = threadId, senderId = if (item.mine) me else item.sender, content = item.body,
                sentAt = sentAt, deliveredAt = sentAt,
            )
        }
        if (target.first != "dm") access[threadId] = thread.access
        threadMap[threadId]?.let { cached ->
            var updated = cached.copy(unreadCounts = cached.unreadCounts + (me to 0))
            thread.members?.takeIf { cached.isGroup }?.let { members -> updated = updated.copy(participantIds = members.map { it.id }) }
            if (updated != cached) threadMap = threadMap + (threadId to updated)
        }
    }

    private suspend fun loadQuietly(threadId: String) {
        try {
            loadThread(threadId)
        } catch (error: RemoteError) {
            context.appState.showError(error)
        }
    }

    /** 标为已读：打开会话时拉取消息（服务器同时记为已读），3 秒内不重复拉；还不能私信的人没有会话可拉 */
    private fun markRead(threadId: String) {
        if (canOpenRemoteThread(threadId) && now() - (loadedAt[threadId] ?: 0) > 3_000) {
            loadedAt[threadId] = now()
            context.scope.launch { loadQuietly(threadId) }
        }
        val me = cache.me ?: return
        threadMap[threadId]?.takeIf { it.unreadCount(me) > 0 }?.let { threadMap = threadMap + (threadId to it.copy(unreadCounts = it.unreadCounts + (me to 0))) }
    }

    // MARK: 打开、关闭

    fun open(userId: String) {
        val id = threadId(userId) ?: return
        openThread(id)
    }

    fun close(userId: String) {
        threadId(userId)?.let(::closeThread)
    }

    fun openThread(threadId: String) {
        activeThreadId = threadId
        markRead(threadId)
    }

    fun closeThread(threadId: String) {
        if (activeThreadId == threadId) activeThreadId = null
    }

    /** 推送到了或回到前台：马上重拉会话列表；正开着的会话连消息一起拉 */
    fun refreshNow() {
        activeThreadId?.takeIf(::canOpenRemoteThread)?.let { id -> context.scope.launch { loadQuietly(id) } }
        context.scope.launch {
            try {
                refreshThreads()
            } catch (_: RemoteError) {
            }
        }
    }

    // MARK: 发送

    suspend fun send(text: String, userId: String) {
        val me = cache.me ?: throw RemoteError.NotSignedIn
        validate(text)
        val threadId = MessageThread.id(me, userId)
        val wasRequest = cache.messageOptions[userId]?.status == "request" && threadMap[threadId]?.isPendingRequest != true
        api.send("dm", userId, text.trim())
        loadThread(threadId)
        if (wasRequest) {
            // 发出的是消息请求：之后等对方接受（会话列表会标出来）
            cache.messageOptions[userId] = RemoteMessageOption("requested")
        }
        refreshThreads()
    }

    suspend fun sendGroup(text: String, threadId: String) {
        val me = cache.me ?: throw RemoteError.NotSignedIn
        validate(text)
        val target = MessagesApi.serverThread(threadId, me) ?: throw BackendError(tr("这个群聊已经结束了"))
        api.send(target.first, target.second, text.trim())
        loadThread(threadId)
        refreshThreads()
    }

    private fun validate(text: String) {
        when (Message.validate(text)) {
            MessageValidation.Empty -> throw BackendError(tr("消息不能为空"))
            MessageValidation.TooLong -> throw BackendError(tr("消息不能超过 %lld 字", Message.MAX_CONTENT_LENGTH))
            MessageValidation.Valid -> Unit
        }
    }

    // MARK: 消息请求

    /** 接受对方的消息请求：先改本机，再告诉服务器 */
    fun acceptRequest(from: String) {
        val id = threadId(from) ?: return
        val thread = threadMap[id]?.takeIf { it.isPendingRequest && it.requestFrom == from } ?: return
        threadMap = threadMap + (id to thread.copy(isPendingRequest = false))
        cache.messageOptions[from] = RemoteMessageOption("open")
        respond(from, accept = true)
    }

    /** 忽略：只对自己隐藏，对方不会知道被忽略（仍显示“等待接受”） */
    fun declineRequest(from: String) {
        val id = threadId(from) ?: return
        threadMap = threadMap - id
        messagesByThread.remove(id)
        respond(from, accept = false)
    }

    private fun respond(from: String, accept: Boolean) {
        context.scope.launch {
            try {
                api.respondMessageRequest(from, accept)
            } catch (error: RemoteError) {
                context.appState.showError(error)
            }
            try {
                refreshThreads()
            } catch (_: RemoteError) {
            }
        }
    }

    // MARK: 群聊

    /** 球局群聊的会话 ID（本机还没有就先建一个，打开时从服务器拉） */
    fun gameChatId(gameId: String): String {
        val id = MessageThread.gameThreadId(gameId)
        if (!threadMap.containsKey(id)) {
            val me = cache.me ?: return id
            val game = cache.games.firstOrNull { it.id == gameId }
            threadMap = threadMap + (
                id to MessageThread(
                    id = id, participantIds = game?.playerIds?.takeIf { me in it } ?: listOf(me), lastActivityAt = game?.startsAt ?: now(),
                    context = ThreadContext.Game(gameId), title = game?.venueName,
                )
                )
        }
        return id
    }

    /** 球群群聊的会话 ID（只有成员才有） */
    fun groupChatId(groupId: String, groupName: String, memberIds: List<String>): String? {
        val me = cache.me ?: return null
        if (me !in memberIds) return null
        val id = MessageThread.groupThreadId(groupId)
        val existing = threadMap[id]
        if (existing == null || existing.title != groupName) {
            threadMap = threadMap + (
                id to (
                    existing?.copy(title = groupName) ?: MessageThread(
                        id = id, participantIds = memberIds.sorted(), lastActivityAt = now(), context = ThreadContext.Group(groupId), title = groupName,
                    )
                    )
                )
        }
        return id
    }

    // MARK: 删除、屏蔽、举报

    /** 删除会话：只在本机隐藏，对方仍保留（不同步服务器，和 iPhone 一样） */
    fun deleteThread(thread: MessageThread) {
        cache.clear(thread.id, now())
        val me = cache.me ?: return
        threadMap[thread.id]?.let { threadMap = threadMap + (thread.id to it.copy(unreadCounts = it.unreadCounts + (me to 0))) }
    }

    /** 屏蔽：对方无法再给你发消息、加好友或进入你的房间；不会通知对方 */
    fun block(userId: String) {
        cache.block(userId, now())
        runRemote { social.block(userId) }
    }

    fun unblock(userId: String) {
        cache.unblock(userId)
        runRemote { social.unblock(userId) }
    }

    suspend fun report(userId: String, reason: ReportReason, detail: String, alsoBlock: Boolean) {
        try {
            social.report(userId, reason, detail)
        } catch (error: RemoteError) {
            context.appState.showError(error)
        }
        if (alsoBlock) block(userId)
    }

    /** 先改了本机，再告诉服务器；之后重拉球友和会话 */
    private fun runRemote(operation: suspend () -> Unit) {
        context.scope.launch {
            try {
                operation()
            } catch (error: RemoteError) {
                context.appState.showError(error)
            }
            try {
                cache.refreshFriends?.invoke()
                refreshThreads()
            } catch (_: RemoteError) {
            }
        }
    }

    // MARK: 轮询

    /** 没有实时推送：每 15 秒拉一次会话列表（回到前台时开始，退到后台时停） */
    fun startPolling() {
        if (polling?.isActive == true) return
        polling = context.scope.launch {
            while (isActive) {
                try {
                    refreshThreads()
                } catch (_: RemoteError) {
                    // 网络问题：下次再拉
                }
                delay(POLL_MILLIS)
            }
        }
    }

    fun stopPolling() {
        polling?.cancel()
        polling = null
    }

    companion object {
        const val DEFAULT_MESSAGE_LIMIT = 50
        const val MAX_MESSAGE_LENGTH = Message.MAX_CONTENT_LENGTH
        const val POLL_MILLIS = 15_000L
    }
}
