package com.badie.app.features.messages

import com.badie.app.backend.MessagesApi
import com.badie.app.features.social.SocialTestSupport.BLAKE
import com.badie.app.features.social.SocialTestSupport.CASEY
import com.badie.app.features.social.SocialTestSupport.ME
import com.badie.app.features.social.SocialTestSupport.environment
import com.badie.app.features.social.SocialTestSupport.text
import com.badie.app.models.InboxItem
import com.badie.app.models.MessageThread
import com.badie.app.models.ReportReason
import com.badie.app.remote.FakeServer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 会话、消息、消息请求、通知。对应 iPhone SupabaseClientTests 的 testFriendsThreadsAndNotificationsComeFromServer、
 * testMessageRequestsFollowTheServer、testOpeningAndSendingInAThread，和 MockBackendTests 里屏蔽、删除会话的规则
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MessageManagerTest {
    private val server = FakeServer()
    private val dm = MessageThread.id(ME, BLAKE)

    private fun serveFriends(friends: String = """{"id":"$BLAKE","nickname":"Blake","rating":4.33}""") {
        server.on("POST /rest/v1/rpc/my_friends", """{"friends":[$friends],"requests":[{"id":"$CASEY","nickname":"Casey","rating":3,"created_at":"2026-10-17T10:00:00+00:00"}]}""")
    }

    private val threads =
        """[{"kind":"dm","id":"$BLAKE","starts_at":null,"venue":null,"tz":null,"name":"Blake","access":"open","last":{"body":"See you","created_at":"2026-10-17T12:00:00+00:00","mine":false},"unread":2},""" +
            """{"kind":"game","id":"g1","starts_at":"2026-10-17T18:00:00+00:00","venue":"Test Court","tz":null,"name":null,"access":"closed","last":{"body":"On my way","created_at":"2026-10-17T17:50:00+00:00","mine":true},"unread":0}]"""

    @Test
    fun friendsThreadsAndNotificationsComeFromServer() = runTest {
        val env = environment(server, backgroundScope)
        serveFriends()
        server.on("POST /rest/v1/rpc/my_threads", threads)
        server.on(
            "GET /rest/v1/notifications",
            """[{"id":7,"kind":"friend_request","title":"Friend request","body":"Casey wants to be friends.","link":"/app/players/$CASEY/","created_at":"2026-10-17T10:00:00+00:00","read_at":null},""" +
                """{"id":6,"kind":"review","title":"How was your game?","body":"…","link":"/app/games/g1/","created_at":"2026-10-17T09:00:00+00:00","read_at":"2026-10-17T09:30:00+00:00"}]""",
        )
        env.friendManager.refreshFriends()
        env.messageManager.refreshThreads()
        env.inboxManager.refresh()
        val messages = env.messageManager

        assertEquals(MessagePermission.Allowed, messages.permission(BLAKE))
        assertEquals("正式后端：私信只发给球友", MessagePermission.FriendsOnly, messages.permission(CASEY))
        assertEquals(2, messages.thread(dm)?.unreadCount(ME))
        assertEquals(BLAKE, messages.thread(dm)?.lastMessage?.senderId)
        assertEquals(ME, messages.thread("game-g1")?.lastMessage?.senderId)
        assertEquals("Test Court", messages.thread("game-g1")?.title)
        assertEquals(2, messages.unreadCount)
        assertEquals("最近的在前", listOf("game-g1", dm), messages.conversations.map { it.id })
        assertFalse("球局群已关闭", messages.canPost("game-g1"))
        assertTrue(messages.canPost(dm))

        val inbox = env.inboxManager.items
        assertEquals(listOf(InboxItem.Kind.FriendRequest, InboxItem.Kind.SurveyDue), inbox.map { it.kind })
        assertEquals("点开去对方资料", CASEY, inbox.first().relatedId)
        assertEquals("g1", inbox.last().relatedId)
        assertEquals(listOf(false, true), inbox.map { it.isRead })
        assertEquals(1, env.inboxManager.unreadCount)

        // 全部已读：服务器一次全标
        server.requests.clear()
        server.on("POST /rest/v1/rpc/mark_notifications_read", "")
        env.inboxManager.markRead(inbox.first())
        runCurrent()
        assertEquals("/rest/v1/rpc/mark_notifications_read", server.path(0))
        assertEquals(0, env.inboxManager.unreadCount)
    }

    @Test
    fun messageRequestsFollowTheServer() = runTest {
        val env = environment(server, backgroundScope)
        // Casey 发来的请求在会话列表里；Blake 的资料页说可以发一条请求
        server.on("POST /rest/v1/rpc/my_friends", """{"friends":[],"requests":[]}""")
        server.on(
            "POST /rest/v1/rpc/my_threads",
            """[{"kind":"dm","id":"$CASEY","starts_at":null,"venue":null,"tz":null,"name":"Casey","access":"open","request":"incoming","last":{"body":"Hi from the club","created_at":"2026-10-17T12:00:00+00:00","mine":false},"unread":1}]""",
        )
        server.on(
            "GET /rest/v1/notifications",
            """[{"id":9,"kind":"message_request","title":"Casey wants to chat","body":"…","link":"/app/messages/dm/$CASEY/","created_at":"2026-10-17T12:00:00+00:00","read_at":null}]""",
        )
        env.friendManager.refreshFriends()
        env.messageManager.refreshThreads()
        env.inboxManager.refresh()
        val messages = env.messageManager
        assertEquals(listOf(MessageThread.id(ME, CASEY)), messages.incomingRequests.map { it.id })
        assertTrue("请求不在普通会话里", messages.conversations.isEmpty())
        assertEquals("回复就算接受", MessagePermission.Allowed, messages.permission(CASEY))
        assertEquals(InboxItem.Kind.MessageRequest, env.inboxManager.items.first().kind)
        assertEquals("点开去和 TA 的会话", CASEY, env.inboxManager.items.first().relatedId)

        server.on(
            "POST /rest/v1/rpc/player_card",
            """{"id":"$BLAKE","nickname":"Blake","rating":4.33,"tags":[],"win_rate":null,"challenge":"hidden","message":{"status":"request","group":"Sunday Club"}}""",
        )
        env.friendManager.refreshPlayer(BLAKE)
        assertEquals(MessagePermission.Request("Sunday Club"), messages.permission(BLAKE))

        // 接受：先改本地，再告诉服务器
        server.requests.clear()
        server.on("POST /rest/v1/rpc/respond_message_request", "")
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        messages.acceptRequest(CASEY)
        assertTrue(messages.incomingRequests.isEmpty())
        runCurrent()
        assertEquals(CASEY, server.text(0, "p_user"))
        assertEquals("true", server.text(0, "p_accept"))
    }

    @Test
    fun openingAndSendingInAThread() = runTest {
        val env = environment(server, backgroundScope)
        val thread =
            """{"access":"open","friend":true,"game":null,"group":null,"members":[{"id":"$ME","nickname":"Alex","me":true},{"id":"$BLAKE","nickname":"Blake","me":false}],""" +
                """"messages":[{"id":1,"body":"Hi","created_at":"2026-10-17T12:00:00+00:00","sender":"$BLAKE","mine":false},{"id":2,"body":"Hello","created_at":"2026-10-17T12:01:00+00:00","sender":"$ME","mine":true}]}"""
        server.on("POST /rest/v1/rpc/send_message", "")
        server.on("POST /rest/v1/rpc/open_thread", thread)
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        env.messageManager.send("  Hello  ", BLAKE)
        assertEquals("dm", server.text(0, "p_kind"))
        assertEquals(BLAKE, server.text(0, "p_id"))
        assertEquals("Hello", server.text(0, "p_body"))
        assertEquals(listOf("Hi", "Hello"), env.messageManager.messages(dm).map { it.content })
        assertEquals(BLAKE, env.messageManager.messages(dm).first().senderId)
        assertEquals("Blake", env.messageManager.user(BLAKE)?.nickname)

        server.requests.clear()
        server.on("POST /rest/v1/rpc/send_message", "")
        server.on("POST /rest/v1/rpc/open_thread", thread)
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        env.messageManager.sendGroup("Court 3", "game-g1")
        assertEquals("game", server.text(0, "p_kind"))
        assertEquals("g1", server.text(0, "p_id"))
    }

    @Test
    fun sendingAMessageRequestWaitsForTheOtherSide() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/player_card", """{"id":"$BLAKE","nickname":"Blake","rating":4.33,"message":{"status":"request","group":"Sunday Club"}}""")
        env.friendManager.refreshPlayer(BLAKE)
        server.on("POST /rest/v1/rpc/send_message", "")
        server.on("POST /rest/v1/rpc/open_thread", """{"access":"requested","messages":[]}""")
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        env.messageManager.send("Hi, see you Sunday", BLAKE)
        assertEquals(MessagePermission.PendingRequest, env.messageManager.permission(BLAKE))
    }

    @Test
    fun blockingHidesTheChatAndTheFriend() = runTest {
        val env = environment(server, backgroundScope)
        serveFriends()
        server.on("POST /rest/v1/rpc/my_threads", threads)
        env.friendManager.refreshFriends()
        env.messageManager.refreshThreads()

        server.requests.clear()
        server.on("POST /rest/v1/rpc/block_user", "")
        env.messageManager.block(BLAKE)
        assertEquals(MessagePermission.Blocked, env.messageManager.permission(BLAKE))
        assertFalse(env.friendManager.isFriend(BLAKE))
        assertNull("屏蔽的人的私信不显示", env.messageManager.conversations.firstOrNull { it.id == dm })
        assertEquals(listOf(BLAKE), env.messageManager.blockedUsers.map { it.blockedUserId })
        runCurrent()
        assertEquals(BLAKE, server.text(0, "p_user"))

        server.on("POST /rest/v1/rpc/unblock_user", "")
        env.messageManager.unblock(BLAKE)
        assertTrue(env.messageManager.blockedUsers.isEmpty())
    }

    @Test
    fun deletingAThreadOnlyHidesItHere() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/my_threads", threads)
        env.messageManager.refreshThreads()
        val thread = env.messageManager.thread(dm)!!
        env.messageManager.deleteThread(thread)
        assertTrue(env.messageManager.conversations.none { it.id == dm })
        assertEquals("删掉的不算未读", 0, env.messageManager.unreadCount)
        assertTrue("不同步服务器", server.requests.none { server.path(server.requests.indexOf(it)).contains("delete") })

        // 之后来了新消息又出现
        server.on("POST /rest/v1/rpc/my_threads", threads.replace("2026-10-17T12:00:00", "2099-10-17T12:00:00"))
        env.messageManager.refreshThreads()
        assertTrue(env.messageManager.conversations.any { it.id == dm })
    }

    @Test
    fun reportSendsTheReason() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/report_user", "")
        env.messageManager.report(BLAKE, ReportReason.NoShow, "没来", alsoBlock = false)
        assertEquals("other", server.text(0, "p_reason"))
        assertEquals("爽约没有对应的分类：写进说明里", "爽约 / 临时放鸽子：没来", server.text(0, "p_details"))
    }

    @Test
    fun serverLinksAndKinds() {
        assertEquals(CASEY, MessagesApi.relatedId("message_request", "/app/messages/dm/$CASEY/"))
        assertEquals("g1", MessagesApi.relatedId("matched", "/app/games/g1/"))
        assertNull(MessagesApi.relatedId("system", "/app/"))
        assertEquals(InboxItem.Kind.GameCancelled, MessagesApi.inboxKind("cancelled"))
        assertEquals(InboxItem.Kind.System, MessagesApi.inboxKind("something_new"))
        assertEquals("dm" to BLAKE, MessagesApi.serverThread(MessageThread.id(ME, BLAKE), ME))
        assertEquals("group" to "grp1", MessagesApi.serverThread("group-grp1", ME))
        assertTrue(InboxItem.Kind.RoomClosed.isUrgent)
        assertFalse(InboxItem.Kind.GameConfirmed.isUrgent)
    }
}
