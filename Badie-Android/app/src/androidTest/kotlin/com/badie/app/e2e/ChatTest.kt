package com.badie.app.e2e

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.badie.app.remote.json
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 聊天不用手动刷新：A 开着 App，B（测试直接调服务器）发消息，A 在会话列表和打开的聊天里都能看到；A 回的 B 能收到。
 * 私信和球局群聊各一遍。App 每 15 秒拉一次，这里最多等 [WAIT] 毫秒
 */
@RunWith(AndroidJUnit4::class)
class ChatTest : E2ETest() {
    private val stamp = System.currentTimeMillis() % 100_000

    @Test
    fun directMessagesArriveWithoutRefreshing() {
        val a = Harness.createPlayer("chat-a", "Alex")
        val b = Harness.createPlayer("chat-b", "Blake")
        Harness.befriend(a, b)

        launch()
        signInWithPassword(a.email)
        openTab("消息")
        waitFor(text(t("还没有聊天")), what = "会话列表（刚成为球友、还没聊过的不列出来，和 iPhone 一样）")

        // 停在会话列表：B 发来的私信自己出现，标签上有角标
        val first = "Hi Alex $stamp"
        Harness.sendDm(b, a, first)
        waitFor(text(first, substring = true), WAIT, "会话列表里的新消息")
        waitFor(tab("消息") and hasState(t("%lld 条未处理", 1)), WAIT, "“消息”标签上的 1 条未处理")

        // 打开聊天：B 接着发，直接出现在聊天里
        tap(text(first, substring = true))
        waitFor(text(first), what = "聊天里的第一条")
        val second = "Court 3 at 7? $stamp"
        Harness.sendDm(b, a, second)
        waitFor(text(second), WAIT, "打开的聊天里收到的新消息")

        // A 回复，B 那边能读到
        val reply = "See you there $stamp"
        type(hasContentDescription(t("发消息…")), reply)
        tap(hasContentDescription(t("发送")))
        waitFor(text(reply), what = "自己发的消息")
        Harness.eventually("B 收到 A 的回复") { reply in Harness.messages(b, "dm", a.id) }
    }

    @Test
    fun gameGroupChatArrivesWithoutRefreshing() {
        val a = Harness.createPlayer("group-a", "Ana")
        val b = Harness.createPlayer("group-b", "Ben")
        val game = Harness.createGame(listOf(a, b))

        launch()
        signInWithPassword(a.email)
        openTab("消息")

        // 球局群聊的名字是球馆名
        val first = "Bringing shuttles $stamp"
        Harness.rpc(b, "send_message", json("p_kind" to "game", "p_id" to game, "p_body" to first))
        waitFor(text(first, substring = true), WAIT, "会话列表里球局群聊的新消息")
        tap(text(first, substring = true))
        waitFor(text(first), what = "群聊里的第一条")

        val second = "Running late $stamp"
        Harness.rpc(b, "send_message", json("p_kind" to "game", "p_id" to game, "p_body" to second))
        waitFor(text(second), WAIT, "打开的群聊里收到的新消息")

        val reply = "No problem $stamp"
        type(hasContentDescription(t("发消息…")), reply)
        tap(hasContentDescription(t("发送")))
        waitFor(text(reply), what = "自己发的群消息")
        Harness.eventually("B 收到 A 的群消息") { reply in Harness.messages(b, "game", game) }
    }

    private fun hasState(value: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value)

    companion object {
        /** 轮询间隔 15 秒，再留点余量 */
        const val WAIT = 40_000L
    }
}
