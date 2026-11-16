package com.badie.app.features.matching

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.MatchApi
import com.badie.app.backend.RemoteTicket
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.MatchOffer
import com.badie.app.models.MatchTicket
import com.badie.app.models.PlayEvent
import com.badie.app.models.TimeSlot
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.addingDays
import com.badie.app.models.startOfDay
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteJSON
import com.badie.app.shell.AppEnvironment
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * 快速匹配：草稿的规则、服务器的请求和提议换成本机的模型、管理器的提交和刷新。
 * iPhone 的 MatchmakingTests 大多测演示模式的匹配（服务器上才有），时间规则那几条在 models/RankingTest 里
 */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class MatchmakingTest {
    private val server = FakeServer()
    private val me = TestSupport.USER_ID
    private val zone = ZoneId.of("America/Los_Angeles")

    // MARK: 草稿（iPhone ModelTests 里的两条）

    @Test
    fun anyTimeAllowsSixteenHoursForMatching() {
        val draft = MatchDraft(day = addingDays(startOfDay(System.currentTimeMillis()), 2)).withAnyTime()
        assertTrue(draft.isAnyTime)
        assertTrue(draft.validation().isValid)
        assertFalse("开局最长 8 小时", draft.slot()!!.validate().isValid)
    }

    @Test
    fun matchDraftDefaultsToAnyLevel() {
        assertEquals("约球默认不限水平", MatchRequest.ANY_SKILL, MatchDraft().skillTolerance)
    }

    @Test
    fun anyTimeTodayStartsHalfAnHourFromNow() {
        val now = ZonedDateTime.of(2026, 11, 16, 15, 10, 0, 0, zone).toInstant().toEpochMilli()
        val draft = MatchDraft(day = startOfDay(now, zone)).withAnyTime(now, zone)
        assertEquals(16 * 60, draft.startMinutes)
        assertEquals(23 * 60, draft.endMinutes)
        val late = ZonedDateTime.of(2026, 11, 16, 22, 50, 0, 0, zone).toInstant().toEpochMilli()
        assertEquals("最晚 22:00 开始", 22 * 60, MatchDraft(day = startOfDay(late, zone)).withAnyTime(late, zone).startMinutes)
    }

    @Test
    fun courtsUpToThreeAndApplyingASlot() {
        var draft = MatchDraft()
        for (id in listOf("a", "b", "c")) draft = draft.togglingCourt(id)!!
        assertNull("最多 3 家", draft.togglingCourt("d"))
        assertEquals(listOf("a", "c"), draft.togglingCourt("b")?.courtIds)
        val day = ZonedDateTime.of(2026, 11, 20, 0, 0, 0, 0, zone).toInstant().toEpochMilli()
        val applied = draft.applying(TimeSlot.on(day, 21, 0, 24, zone = zone)!!, zone)
        assertEquals(21 * 60, applied.startMinutes)
        assertEquals("结束在第二天 0 点算 24:00", 24 * 60, applied.endMinutes)
        assertEquals(TimeSlotConstants.MAXIMUM_MATCH_DURATION, 16 * 3_600_000L)
    }

    // MARK: 服务器 → 本机

    private val ticketJSON = """
        {"id":"t1","mode":"doubles","starts_at":"2026-11-21T03:00:00+00","ends_at":"2026-11-21T05:00:00+00","status":"offered","skill_tolerance":1,
         "auto_accept":false,"lock_at":"2026-11-21T01:00:00+00","last_minute":false,"play_with":"female","mixed":false,
         "venues":[{"id":"v1","name":"圣盖博球馆"}],
         "offer":{"id":"o1","starts_at":"2026-11-21T03:00:00+00","ends_at":"2026-11-21T05:00:00+00","respond_by":"2026-11-20T20:00:00+00",
                  "my_response":"pending","venue":{"id":"v1","name":"圣盖博球馆","lat":34.1,"lon":-118.1,"country":"US","pricing":{"per_person":12}},"accepted":2,
                  "players":[{"id":"$me","nickname":"Alex","rating":4.0,"team":1,"me":true},{"id":"p2","nickname":"小林","rating":4.33,"team":1,"me":false},
                             {"id":"p3","nickname":"阿杰","rating":3.67,"team":2,"me":false},{"id":"p4","nickname":"Mia","rating":4.0,"team":2,"me":false}]}}
    """.trimIndent()

    @Test
    fun remoteTicketAndOfferBecomeLocalModels() {
        val remote = RemoteJSON.decode<RemoteTicket>(ticketJSON.encodeToByteArray())
        val ticket = remote.ticket(me, com.badie.app.models.Coordinate.fallbackCenter, createdAt = 0)
        assertEquals(MatchTicket.Status.Offered("o1"), ticket.status)
        assertEquals(GameMode.Doubles, ticket.mode)
        assertEquals(PlayEvent.Women, ticket.event)
        assertEquals(listOf("v1"), ticket.courtIds)
        val offer = remote.offer!!.offer(ticket.mode, false, remote.offer.venue.venue(), createdAt = 0)
        assertEquals(listOf(listOf(me, "p2"), listOf("p3", "p4")), offer.teams)
        // 服务器只说 2 人确认了：我没确认，其他人按顺序标
        assertEquals(MatchOffer.Response.Pending, offer.seat(me)?.response)
        assertEquals(2, offer.acceptedCount)
        assertEquals("按球馆的价格估算", 4, offer.cost.players)
        assertEquals("matched 没有球局 ID 算过期", MatchTicket.Status.Expired,
            RemoteJSON.decode<RemoteTicket>(ticketJSON.replace("\"offered\"", "\"matched\"").encodeToByteArray()).ticket(me, com.badie.app.models.Coordinate.fallbackCenter, 0).status)
    }

    @Test
    fun submitSendsTheDraft() = runTest {
        server.on("POST /rest/v1/rpc/replace_ticket", "\"t2\"")
        val api = MatchApi(TestSupport.backend(server, TestSupport.session()))
        val slot = TimeSlot(0, 1_800_000_000_000L, 1_800_000_000_000L + 7_200_000L)
        val id = api.submitTicket(GameMode.Doubles, slot, listOf("v1", "v2"), 2, true, PlayEvent.Mixed, replacing = "t1")
        assertEquals("t2", id)
        val body = server.json(0)
        assertEquals("doubles", body["p_mode"]?.jsonPrimitive?.content)
        assertEquals(2, body["p_venue_ids"]?.jsonArray?.size)
        assertEquals(true, body["p_mixed"]?.jsonPrimitive?.boolean)
        assertEquals(JsonNull, body["p_play_with"])
        assertEquals("t1", body["p_ticket"]?.jsonPrimitive?.content)
        assertEquals(2, body["p_skill_tolerance"]?.jsonPrimitive?.int)
    }

    @Test
    fun dayKeyUsesTheLocalDate() {
        val evening = ZonedDateTime.of(2026, 11, 16, 23, 30, 0, 0, zone).toInstant().toEpochMilli()
        assertEquals("2026-11-16", MatchApi.dayKey(evening, zone))
    }

    // MARK: 管理器

    @Test
    fun managerSubmitsThenShowsTheTicket() {
        val scope = TestScope(StandardTestDispatcher())
        val backend = TestSupport.backend(server, TestSupport.session())
        val environment = AppEnvironment(scope, backend)
        val manager = environment.matchManager
        server.serveProfile("[${TestSupport.profile()}]")
        scope.launchAndRun { backend.refreshProfile() }
        val tomorrow = addingDays(startOfDay(System.currentTimeMillis()), 1)
        manager.draft = MatchDraft(day = tomorrow, courtIds = listOf("v1"))
        assertEquals(listOf("v1"), manager.draftVenueIds.toList())
        manager.draftVenueIds.add("v2")
        assertEquals("选球馆页改的列表就是草稿的球馆", listOf("v1", "v2"), manager.draft.courtIds)

        server.on("POST /rest/v1/rpc/submit_ticket", "\"t1\"")
        server.on("POST /rest/v1/rpc/my_matchmaking", "[$ticketJSON]")
        manager.startSearch()
        assertTrue(manager.isFlowPresented)
        assertEquals(MatchManager.Phase.Submitting, manager.phase)
        scope.advanceUntilIdle()
        assertEquals(MatchManager.Phase.Idle, manager.phase)
        assertEquals("t1", manager.flowTicket?.id)
        assertEquals("o1", manager.offer(manager.flowTicket!!)?.id)
        assertEquals("小林", manager.user("p2")?.nickname)
        assertEquals(Gender.Unspecified, manager.user("p2")?.gender)

        manager.closeFlow()
        assertFalse(manager.isFlowPresented)
    }

    private fun TestScope.launchAndRun(block: suspend () -> Unit) {
        launch { block() }
        advanceUntilIdle()
    }
}
