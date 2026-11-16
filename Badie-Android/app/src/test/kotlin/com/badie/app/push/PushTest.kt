package com.badie.app.push

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.ProfileApi
import com.badie.app.backend.ProfileStore
import com.badie.app.models.MessageThread
import com.badie.app.models.Room
import com.badie.app.remote.FakeServer
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import com.badie.app.shell.Router
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 推送：通知里的网址打开对应页面、推送内容、向服务器登记设备。对应 iPhone 的 PushTests */
class PushTest {
    private fun route(link: String) = PushRegistry.route(link).first
    private fun tab(link: String) = PushRegistry.route(link).second

    @After
    fun tearDown() {
        NotificationRouter.isForeground = false
    }

    @Test
    fun linksOpenTheRightScreen() {
        assertEquals(Route.Game("g-1"), route("/app/games/g-1/"))
        assertEquals(MainTab.Games, tab("/games/g-1/"))
        assertEquals(Route.Room("r-1"), route("/rooms/r-1/"))
        assertEquals(Route.Group("p-1"), route("/app/groups/p-1/"))
        assertEquals(Route.Challenges, route("/app/challenges/"))
        assertEquals("没有具体球局就打开通知列表", Route.Notifications, route("/app/games/"))
        assertEquals(Route.Notifications, route(""))
        assertEquals(MainTab.Home, tab(""))
    }

    /** 点开 badie.rsvp 的链接：邀请链接带着码打开加入页，球群链接打开球群 */
    @Test
    fun universalLinks() {
        assertEquals(Route.JoinRoom("AB12CD"), route("https://badie.rsvp/join/?code=AB12CD"))
        assertEquals(Route.JoinRoom(null), route("https://badie.rsvp/join/"))
        assertEquals(Route.Group("p-1"), route("https://badie.rsvp/groups/p-1/"))
        assertEquals(MainTab.Games, tab("https://badie.rsvp/games/g-1/?from=email"))
        assertTrue(Room.joinLink("AB12CD").endsWith("/join/?code=AB12CD"))
    }

    /** 聊天推送和链接打开对应的会话 */
    @Test
    fun chatLinks() {
        assertEquals(Route.Chat("u-2"), route("/messages/dm/u-2/"))
        assertEquals(MainTab.Messages, tab("/app/messages/dm/u-2/"))
        assertEquals(Route.GroupChat(MessageThread.gameThreadId("g-1")), route("/messages/game/g-1/"))
        assertEquals(Route.GroupChat(MessageThread.groupThreadId("p-1")), route("https://badie.rsvp/messages/group/p-1/"))
        assertEquals("没有具体会话就打开通知列表", Route.Notifications, route("/messages/"))
    }

    // MARK: 推送内容（服务器的 fcmPayload）

    @Test
    fun parsesPlainPush() {
        val content = PushContent.parse(mapOf("title" to "配上了", "body" to "周六 10:00", "link" to "/app/games/g-1/"))!!
        assertEquals("配上了", content.title)
        assertEquals("/app/games/g-1/", content.link)
        assertNull(content.chat)
        assertEquals("周六 10:00", content.messageText)
        assertNull("没有标题的不显示", PushContent.parse(mapOf("body" to "x")))
    }

    @Test
    fun parsesChatPush() {
        val dm = PushContent.parse(
            mapOf(
                "title" to "Sam", "body" to "明天见", "link" to "/messages/dm/u-2/",
                "chat" to """{"thread":"u-1|u-2","sender":"u-2","name":"Sam","group":null,"members":null,"avatar":"https://x.supabase.co/storage/v1/object/public/avatars/u-2/a.jpg"}""",
            ),
        )!!
        assertEquals(ChatPush("u-1|u-2", "u-2", "Sam", "https://x.supabase.co/storage/v1/object/public/avatars/u-2/a.jpg"), dm.chat)
        assertEquals("明天见", dm.messageText)

        val group = PushContent.parse(
            mapOf(
                "title" to "周六球局", "body" to "Sam: 我带球",
                "chat" to """{"thread":"group:p-1","sender":"u-2","name":"Sam","group":"周六球局","members":8,"avatar":null,"extra":1}""",
            ),
        )!!
        assertEquals(8, group.chat?.members)
        assertNull(group.chat?.avatar)
        assertEquals("群聊的正文去掉前面的昵称（会话通知里每句已经带着发消息的人）", "我带球", group.messageText)

        val broken = PushContent.parse(mapOf("title" to "Sam", "body" to "hi", "chat" to "{oops"))!!
        assertNull("chat 坏了就按普通通知显示", broken.chat)
    }

    // MARK: 点通知

    @Test
    fun tapOpensTheRouteOnceTheUiIsReady() {
        val router = Router()
        NotificationRouter.detach(router)
        val target = NotificationRouter.target(gameId = null, link = "/messages/dm/u-2/")!!
        NotificationRouter.open(target)
        assertEquals("冷启动：界面还没好，先记下", target, NotificationRouter.pending)
        NotificationRouter.attach(router, null)
        assertNull(NotificationRouter.pending)
        assertEquals(MainTab.Messages, router.selectedTab)
        assertEquals(listOf(Route.Chat("u-2")), router.path(MainTab.Messages))

        // 本地提醒带 gameId
        NotificationRouter.open(NotificationRouter.target(gameId = "g-1", link = null)!!)
        assertEquals(listOf(Route.Game("g-1")), router.path(MainTab.Games))
        assertNull(NotificationRouter.target(null, null))
        NotificationRouter.detach(router)
    }

    @Test
    fun openChatIsNotShownAgainInTheForeground() {
        val router = Router()
        NotificationRouter.attach(router, null)
        router.show(Route.Chat("u-2"), MainTab.Messages)
        assertTrue("在后台：照常显示", NotificationRouter.willPresent("/messages/dm/u-2/"))
        NotificationRouter.isForeground = true
        assertFalse("正开着这个会话", NotificationRouter.willPresent("/messages/dm/u-2/"))
        assertTrue("别的会话照常显示", NotificationRouter.willPresent("/messages/dm/u-3/"))
        assertTrue(NotificationRouter.willPresent("/app/games/g-1/"))
        assertTrue(NotificationRouter.willPresent(null))
        NotificationRouter.detach(router)
    }

    // MARK: 向服务器登记

    private val server = FakeServer()
    private val token = "f".repeat(20) + ":APA91b" + "x".repeat(140)

    private fun calls() = server.requests.map { "${it.method} ${java.net.URI(it.url).path}" }

    @Test
    fun signInRegistersThisDevice() = runTest {
        val backend = TestSupport.backend(server, pushToken = token)
        server.on("POST /auth/v1/token", TestSupport.token("pw"))
        server.on("POST /rest/v1/rpc/register_push", "")
        server.serveProfile("[${TestSupport.profile()}]")
        backend.signIn("alex@example.com", "shuttle rally", captchaToken = null)
        val index = calls().indexOf("POST /rest/v1/rpc/register_push")
        assertEquals(1, index)
        assertEquals("fcm", server.json(index)["p_kind"]?.jsonPrimitive?.content)
        assertEquals(token, server.json(index)["p_token"]?.jsonPrimitive?.content)
    }

    @Test
    fun launchRegistersAgainAndNoTokenMeansNoCall() = runTest {
        val backend = TestSupport.backend(server, TestSupport.session(), pushToken = token)
        server.serveProfile("[${TestSupport.profile()}]")
        server.on("POST /rest/v1/rpc/register_push", "")
        backend.restoreSession()
        assertEquals("POST /rest/v1/rpc/register_push", calls().last())

        // 没允许通知（没有令牌）：不登记
        server.requests.clear()
        TestSupport.backend(server, TestSupport.session()).registerPush()
        assertTrue(server.requests.isEmpty())
        // 没登录：不登记
        TestSupport.backend(server, pushToken = token).registerPush()
        assertTrue(server.requests.isEmpty())
    }

    @Test
    fun signOutUnregistersBeforeLoggingOut() = runTest {
        val backend = TestSupport.backend(server, TestSupport.session(), pushToken = token)
        server.on("POST /rest/v1/rpc/unregister_push", "")
        server.on("POST /auth/v1/logout", "")
        backend.signOut()
        assertEquals(listOf("POST /rest/v1/rpc/unregister_push", "POST /auth/v1/logout"), calls())
        assertEquals(token, server.json(0)["p_token"]?.jsonPrimitive?.content)
    }

    @Test
    fun signOutStillWorksWhenUnregisterFails() = runTest {
        val backend = TestSupport.backend(server, TestSupport.session(), pushToken = token)
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        server.on("POST /rest/v1/rpc/unregister_push", """{"message":"offline"}""", status = 500)
        server.on("POST /auth/v1/logout", "")
        backend.signOut()
        assertNull(backend.currentUser)
    }

    @Test
    fun deleteAccountUnregistersFirstAndOnlyOnce() = runTest {
        val backend = TestSupport.backend(server, TestSupport.session(), pushToken = token)
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        val api = ProfileApi(backend, ProfileStore.memory, CoroutineScope(Dispatchers.Unconfined))
        server.requests.clear()
        server.on("POST /storage/v1/object/list/avatars", "[]")
        server.on("POST /rest/v1/rpc/unregister_push", "")
        server.on("POST /rest/v1/rpc/delete_account", "")
        server.on("POST /auth/v1/logout", "")
        api.deleteAccount()
        val paths = calls()
        assertEquals(1, paths.count { it == "POST /rest/v1/rpc/unregister_push" })
        assertTrue(paths.indexOf("POST /rest/v1/rpc/unregister_push") < paths.indexOf("POST /rest/v1/rpc/delete_account"))
        assertNull(backend.currentUser)
    }
}
