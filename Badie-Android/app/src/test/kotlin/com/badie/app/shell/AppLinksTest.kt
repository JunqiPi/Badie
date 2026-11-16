package com.badie.app.shell

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.models.MessageThread
import com.badie.app.push.NotificationRouter
import com.badie.app.remote.FakeServer
import com.badie.app.shell.AppLinks.Target
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 点开 badie.rsvp 的链接进 App：哪个地址打开哪一页（和 iPhone RootView 的 onOpenURL 一致） */
class AppLinksTest {
    @Test
    fun targets() {
        assertEquals(Target.Page(Route.Game("g1"), MainTab.Games), AppLinks.target("https://badie.rsvp/games/g1/"))
        assertEquals(Target.Page(Route.Room("r1"), MainTab.Games), AppLinks.target("https://badie.rsvp/rooms/r1/"))
        assertEquals(Target.Page(Route.Group("p1"), MainTab.Games), AppLinks.target("https://badie.rsvp/groups/p1/"))
        assertEquals(Target.Page(Route.JoinRoom("AB23CD"), MainTab.Games), AppLinks.target("https://badie.rsvp/join/?code=AB23CD"))
        assertEquals(Target.Page(Route.Challenges, MainTab.Games), AppLinks.target("https://badie.rsvp/challenges/"))
        assertEquals(Target.Page(Route.Chat("u2"), MainTab.Messages), AppLinks.target("https://badie.rsvp/messages/dm/u2/"))
        assertEquals(
            Target.Page(Route.GroupChat(MessageThread.gameThreadId("g1")), MainTab.Messages),
            AppLinks.target("https://badie.rsvp/messages/game/g1/"),
        )
        assertEquals(Target.FriendLink("k7Qz"), AppLinks.target("https://badie.rsvp/add/k7Qz/"))
        assertEquals(Target.Levels, AppLinks.target("https://badie.rsvp/levels/4-plus/"))
        assertEquals("别的语言的等级页", Target.Levels, AppLinks.target("https://badie.rsvp/zh/levels/"))
        assertEquals("其他地址打开通知中心", Target.Page(Route.Notifications, MainTab.Home), AppLinks.target("https://badie.rsvp/messages/"))
        assertNull("别的网站", AppLinks.target("https://example.com/games/g1/"))
        assertNull("登录回调不是网页链接", AppLinks.target("com.badie.app://auth/callback?code=x"))
    }

    @Test
    fun openQueuesUntilMainAppears() = runTest {
        val env = AppEnvironment(backgroundScope, TestSupport.backend())
        assertFalse(AppLinks.open("https://example.com/", env, backgroundScope))
        assertTrue(AppLinks.open("https://badie.rsvp/games/g1/", env, backgroundScope))
        assertEquals(Route.Game("g1") to MainTab.Games, NotificationRouter.pending)
        // 主界面出来时打开
        val router = Router()
        NotificationRouter.attach(router, null)
        assertNull(NotificationRouter.pending)
        NotificationRouter.detach(router)

        // 没登录时等级页不处理
        assertTrue(AppLinks.open("https://badie.rsvp/levels/", env, backgroundScope))
        assertNull(NotificationRouter.pending)
    }

    @Test
    fun levelsAndFriendLinks() = runTest {
        val server = FakeServer()
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        val env = AppEnvironment(backgroundScope, backend)

        // 定过级：等级对照表
        AppLinks.open("https://badie.rsvp/levels/", env, backgroundScope)
        assertEquals(Route.LevelGuide to MainTab.Profile, NotificationRouter.pending)
        val router = Router()
        NotificationRouter.attach(router, null)
        NotificationRouter.detach(router)

        // 加球友链接：找到人就打开资料；失效的给提示
        server.on("POST /rest/v1/rpc/open_friend_link", "\"u-2\"")
        AppLinks.open("https://badie.rsvp/add/k7Qz/", env, this)
        testScheduler.advanceUntilIdle()
        assertEquals("u-2", env.appState.presentedPlayer)

        server.on("POST /rest/v1/rpc/open_friend_link", "null")
        AppLinks.open("https://badie.rsvp/add/gone/", env, this)
        testScheduler.advanceUntilIdle()
        assertEquals("这个加球友链接已失效", env.appState.toast?.message)

        server.on("POST /rest/v1/rpc/open_friend_link", "\"${TestSupport.USER_ID}\"")
        AppLinks.open("https://badie.rsvp/add/mine/", env, this)
        testScheduler.advanceUntilIdle()
        assertEquals("这是你自己的加球友链接", env.appState.toast?.message)
    }
}
