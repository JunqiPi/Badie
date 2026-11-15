package com.badie.app.shell

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RouterTest {
    @Test
    fun openPushesOntoTheCurrentTab() {
        val router = Router()
        router.open(Route.Settings)
        assertEquals(listOf(Route.Settings), router.path(MainTab.Home))
        assertFalse(router.isTabBarVisible)
        // 同一个页面连着开两次，只进一次
        router.open(Route.Settings)
        assertEquals(1, router.path(MainTab.Home).size)
        assertEquals(2, router.navigations)
    }

    @Test
    fun openInAnotherTabSwitchesToIt() {
        val router = Router()
        router.open(Route.Game("g1"), MainTab.Games)
        assertEquals(MainTab.Games, router.selectedTab)
        assertEquals(listOf(Route.Game("g1")), router.path(MainTab.Games))
        assertTrue(router.path(MainTab.Home).isEmpty())
        assertTrue(router.isShowing(Route.Game("g1")))
    }

    @Test
    fun selectingTheCurrentTabAgainGoesBackToItsRoot() {
        val router = Router()
        router.open(Route.Friends)
        router.open(Route.AddFriend)
        router.select(MainTab.Profile)
        // 换标签页不动原来那条导航栈
        assertEquals(2, router.path(MainTab.Home).size)
        router.select(MainTab.Home)
        assertEquals(2, router.path(MainTab.Home).size)
        router.select(MainTab.Home)
        assertTrue(router.path(MainTab.Home).isEmpty())
        assertTrue(router.isTabBarVisible)
    }

    @Test
    fun showReplacesTheStack() {
        val router = Router()
        router.open(Route.Courts, MainTab.Games)
        router.open(Route.Venue("v1"))
        router.show(Route.Game("g2"), MainTab.Games)
        assertEquals(listOf(Route.Game("g2")), router.path(MainTab.Games))
        router.showRoot(MainTab.Games)
        assertTrue(router.path(MainTab.Games).isEmpty())
    }

    @Test
    fun popAndReset() {
        val router = Router()
        router.pop()
        router.open(Route.Notifications, MainTab.Messages)
        router.open(Route.Chat("u1"))
        router.pop()
        assertEquals(listOf(Route.Notifications), router.path(MainTab.Messages))
        router.isCreateMenuPresented = true
        router.reset()
        assertEquals(MainTab.Home, router.selectedTab)
        assertTrue(MainTab.entries.all { router.path(it).isEmpty() })
        assertFalse(router.isCreateMenuPresented)
    }
}
