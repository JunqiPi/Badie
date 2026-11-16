package com.badie.app.e2e

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.badie.app.remote.json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * 别的地方也不用重启：B 加 A 为球友、B 约 A、B 用房间码进 A 的房间、两人的约球请求配上，A 开着 App 都能看到。
 * 每个测试新建自己的 A 和 B
 */
@RunWith(AndroidJUnit4::class)
class LiveRefreshTest : E2ETest() {
    private fun hasState(value: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value)

    /** 整点，[days] 天后 */
    private fun later(days: Long): Instant = Instant.now().plus(days, ChronoUnit.DAYS).truncatedTo(ChronoUnit.HOURS)

    @Test
    fun incomingFriendRequestShowsBadge() {
        val a = Harness.createPlayer("friend-a", "Arlo")
        val b = Harness.createPlayer("friend-b", "Bodhi")
        launch()
        signInWithPassword(a.email)

        Harness.rpc(b, "send_friend_request", json("p_user" to a.id))
        waitFor(tab("消息") and hasState(t("%lld 条未处理", 1)), WAIT, "“消息”标签上的 1 条未处理")
        // 通知也到了：发现页的铃铛上有数
        waitFor(desc(t("通知")) and hasState(t("%lld 条未读", 1)), WAIT, "铃铛上的 1 条未读")
    }

    @Test
    fun inviteFromAnotherPlayerShowsUpOnGames() {
        val a = Harness.createPlayer("invite-a", "Aspen")
        val b = Harness.createPlayer("invite-b", "Bexley")
        launch()
        signInWithPassword(a.email)
        openTab("球局")
        waitFor(text(t("球局")), what = "球局页")

        val start = later(2)
        Harness.rpc(
            b, "invite_player",
            json(
                "p_user" to a.id, "p_venue" to Harness.VENUE_ID, "p_window_start" to start.toString(),
                "p_window_end" to start.plus(90, ChronoUnit.MINUTES).toString(), "p_daypart" to null, "p_duration" to 90, "p_mode" to "singles",
            ),
        )
        // 球局页“我的房间”里出现 B 的邀请，等我回复
        waitFor(mentions("Bexley"), WAIT, "球局页上 B 的邀请")
        waitFor(text(t("待回复")), what = "“待回复”")
        // 发现页的铃铛也有数
        openTab("发现")
        waitFor(desc(t("通知")) and hasState(t("%lld 条未读", 1)), WAIT, "铃铛上的 1 条未读")
    }

    @Test
    fun playerJoiningByCodeShowsInLobby() {
        val a = Harness.createPlayer("room-a", "Atlas")
        val b = Harness.createPlayer("room-b", "Brynn")
        val start = later(3)
        val roomId = Harness.rpc(
            a, "create_room",
            json(
                "p_mode" to "singles", "p_visibility" to "private", "p_level_min" to 1, "p_level_max" to 9, "p_tags" to emptyList<String>(),
                "p_note" to "", "p_gender" to null, "p_mixed" to false, "p_venue" to Harness.VENUE_ID,
                "p_starts_at" to start.toString(), "p_ends_at" to start.plus(2, ChronoUnit.HOURS).toString(),
            ),
        ).jsonPrimitive.content
        val code = Harness.rpc(a, "room_page", json("p_room" to roomId)).jsonObject["code"]!!.jsonPrimitive.content

        launch()
        signInWithPassword(a.email)
        openTab("球局")
        tap(text(t("私密 · %@", code), substring = true), WAIT)
        waitFor(text(t("房间码")), what = "房间页")

        Harness.rpc(b, "join_room_code", json("p_code" to code))
        waitFor(mentions("Brynn"), WAIT, "房间里新进来的 B")
    }

    @Test
    fun quickMatchOfferConfirmedBecomesGame() {
        val a = Harness.createPlayer("match-a", "Ash")
        val b = Harness.createPlayer("match-b", "Blair")
        for (p in listOf(a, b)) Harness.rpc(p, "save_assessment", json("p_rating" to 3, "p_answers" to emptyMap<String, Int>()))
        val start = later(4)
        val ticket = json(
            "p_mode" to "singles", "p_starts_at" to start.toString(), "p_ends_at" to start.plus(3, ChronoUnit.HOURS).toString(),
            "p_venue_ids" to listOf(Harness.VENUE_ID), "p_skill_tolerance" to 1, "p_auto_accept" to false, "p_play_with" to null, "p_mixed" to false,
        )
        Harness.rpc(a, "submit_ticket", ticket)

        launch()
        signInWithPassword(a.email)
        openTab("球局")
        waitFor(text(t("约球请求")), WAIT, "球局页上 A 的约球请求")

        // B 也发一个一样的请求：配上了，A 这边自己变成等确认
        Harness.rpc(b, "submit_ticket", ticket)
        tap(text(prefix("约球请求 · %@"), substring = true))
        tapText("确认约球", timeoutMillis = WAIT)

        // B 也确认：成局，A 的球局页出现这场球
        val offer = Harness.rpc(b, "my_matchmaking").jsonArray.firstNotNullOf { (it.jsonObject["offer"] as? JsonObject)?.get("id") }
        Harness.rpc(b, "respond_offer", json("p_offer" to offer.jsonPrimitive.content, "p_accept" to true))
        device.pressBack()
        waitGone(text(t("确认约球")))
        waitFor(text(t("即将开始")), what = "球局页")
        waitFor(mentions("Blair"), WAIT, "球局页上和 B 的球局")
    }

    companion object {
        const val WAIT = 40_000L
    }
}
