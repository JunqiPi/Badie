package com.badie.app.e2e

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.badie.app.remote.json
import org.junit.Test
import org.junit.runner.RunWith

/** 通知中心点一条通知打开对应的页面；下拉刷新 */
@RunWith(AndroidJUnit4::class)
class NotificationCenterTest : E2ETest() {
    @Test
    fun tappingFriendRequestOpensPlayerAndAccepts() {
        val a = Harness.createPlayer("inbox-a", "Avi")
        val b = Harness.createPlayer("inbox-b", "Bram")
        Harness.rpc(b, "send_friend_request", json("p_user" to a.id))

        launch()
        signInWithPassword(a.email)
        tap(desc(t("通知")))
        tap(mentions("Bram"), LiveRefreshTest.WAIT)
        // 打开的是 B 的资料卡，可以直接通过
        tapText("通过好友申请")
        Harness.eventually("B 那边已经是球友") { Harness.rpc(b, "my_friends").toString().contains(a.id) }
    }

    @Test
    fun pullToRefreshLoadsNewGame() {
        val a = Harness.createPlayer("pull-a", "Ari")
        val b = Harness.createPlayer("pull-b", "Pippa")
        launch()
        signInWithPassword(a.email)
        openTab("球局")
        waitFor(text(t("还没有约好的球局")), what = "球局页的空状态")

        // 服务器上多了一场球（App 不知道），下拉一下就出来
        Harness.createGame(listOf(a, b))
        Thread.sleep(1_000)
        device.swipe(device.displayWidth / 2, device.displayHeight / 4, device.displayWidth / 2, device.displayHeight * 3 / 4, 40)
        waitFor(mentions("Pippa"), 10_000, "下拉后出现的球局")
    }
}
