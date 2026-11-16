package com.badie.app.features.rankings

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.Backend
import com.badie.app.models.ChallengeStatus
import com.badie.app.models.GameMode
import com.badie.app.models.LevelBracket
import com.badie.app.models.Rankings
import com.badie.app.models.ReportReason
import com.badie.app.models.TimeSlot
import com.badie.app.models.Venue
import com.badie.app.models.VenuePricing
import com.badie.app.remote.FakeServer
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * 排行榜、我的胜率、挑战走服务器的那一路。对应 iPhone SupabaseClientTests 的 testRankingsComeFromServer、
 * testChallengesComeFromServer，加上排行榜页、挑战页里的几条规则（筛选后重排、我的位置、剩余时间）
 */
class RankingManagerTest {
    private val server = FakeServer()
    private val me = TestSupport.USER_ID
    private val blake = "6f1c2c3e-0000-4000-8000-000000000002"
    private val casey = "6f1c2c3e-0000-4000-8000-000000000003"
    private val now = TestSupport.CLOCK
    private val week = Rankings.week(now)
    private val month = Rankings.month(now)

    private suspend fun signedIn(profile: String = TestSupport.profile()): Pair<Backend, RankingManager> {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[$profile]")
        backend.refreshProfile()
        server.requests.clear()
        return backend to RankingManager(backend, now = { now })
    }

    private fun iso(millis: Long) = Instant.ofEpochMilli(millis).toString()

    private fun text(index: Int, key: String) = server.json(index)[key]?.jsonPrimitive?.content

    private val weekly =
        """{"week_starts":"2026-10-12T00:00:00+00:00","entries":[{"id":"$blake","nickname":"Blake","rating":4.33,"rank":1,"points":45,"games":3,"wins":2,"me":false}],"me":null,"progress":{"games":1,"opponents":1,"points":10},"eligible":true}"""

    // MARK: 榜单

    @Test
    fun rankingsComeFromServer() = runTest {
        val (_, manager) = signedIn()
        assertTrue("先返回空，拉回来之前显示占位", manager.weeklyLeaderboard(week, country = false).isEmpty())
        assertTrue(manager.isWeeklyLoading(week, country = false))
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        manager.loadWeekly(week, country = false)
        val entry = manager.weeklyLeaderboard(week, country = false).first()
        assertEquals(blake, entry.userId)
        assertEquals(45, entry.score)
        assertEquals("Blake", manager.user(blake)?.nickname)
        assertEquals("global", text(0, "p_scope"))
        assertEquals("male", text(0, "p_gender"))
        assertEquals(0, server.json(0)["p_offset"]?.jsonPrimitive?.int)
        val score = manager.weeklyScore(week, country = false)
        assertEquals(10, score.points)
        assertEquals(1, score.games)
        assertFalse(manager.isWeeklyLoading(week, country = false))

        // 60 秒内不重复拉
        manager.loadWeekly(week, country = false)
        assertEquals(1, server.requests.size)

        // 上周单独拉一份（p_offset = 1）；更早的服务器不提供
        server.requests.clear()
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        val lastWeek = Rankings.week(week.start - 1)
        manager.loadWeekly(lastWeek, country = true)
        assertEquals(1, server.json(0)["p_offset"]?.jsonPrimitive?.int)
        assertEquals("country", text(0, "p_scope"))
        assertTrue(manager.weeklyLeaderboard(lastWeek, country = false).isEmpty())
        assertEquals(1, manager.weeklyLeaderboard(lastWeek, country = true).size)
        val older = Rankings.week(lastWeek.start - 1)
        server.requests.clear()
        manager.loadWeekly(older, country = false)
        assertTrue("服务器只有本周和上周", server.requests.isEmpty())
        assertTrue(manager.weeklyLeaderboard(older, country = false).isEmpty())
        assertFalse(manager.isWeeklyLoading(older, country = false))

        val venueBoard =
            """{"venue":{"id":"v1","name":"Court","city":"Irvine"},"bands":[{"band":2,"entries":[{"id":"$blake","nickname":"Blake","rating":4.33,"rank":1,"games":5,"wins":3,"me":false}]}]}"""
        server.on("POST /rest/v1/rpc/venue_board", venueBoard)
        manager.loadVenueBoard("v1", month)
        val (bracket, entries) = manager.venueLeaderboard("v1", month).first()
        assertEquals(LevelBracket.Intermediate, bracket)
        assertEquals("场馆榜按场次", 5, entries.first().score)
        server.requests.clear()
        server.on("POST /rest/v1/rpc/venue_board", venueBoard)
        val lastMonth = Rankings.month(month.start - 1)
        manager.loadVenueBoard("v1", lastMonth)
        assertEquals("上月", 1, server.json(0)["p_offset"]?.jsonPrimitive?.int)
        assertEquals("v1", text(0, "p_venue"))

        server.on("POST /rest/v1/rpc/my_record", """{"games":6,"wins":4,"opponents":3,"gap":0.5,"public":true,"losses":2,"games_played":7,"no_shows":0,"late_cancels":0}""")
        manager.loadRecord()
        assertEquals(67, manager.winRate(month).percentage)
        assertEquals("胜率只有本月", 0, manager.winRate(lastMonth).games)
    }

    @Test
    fun failedBoardStopsLoadingAndRetries() = runTest {
        val (_, manager) = signedIn()
        server.on("POST /rest/v1/rpc/weekly_board", """{"message":"boom"}""", status = 500)
        manager.loadWeekly(week, country = false)
        assertFalse("拉失败了不显示占位", manager.isWeeklyLoading(week, country = false))
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        manager.loadWeekly(week, country = false)
        assertEquals("失败后不等 60 秒，下次就重拉", 1, manager.weeklyLeaderboard(week, country = false).size)
    }

    @Test
    fun womenSeeTheWomenBoard() = runTest {
        val (_, manager) = signedIn(TestSupport.profile().replace("\"gender\":\"male\"", "\"gender\":\"female\""))
        assertEquals("female", manager.myBoard.rawValue)
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        manager.loadWeekly(week, country = false)
        assertEquals("female", text(0, "p_gender"))
    }

    @Test
    fun reportHidesFromBoard() = runTest {
        val (_, manager) = signedIn()
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        manager.loadWeekly(week, country = false)
        server.on("POST /rest/v1/rpc/report_user", "null")
        manager.report(blake, ReportReason.Other)
        assertTrue("举报后立即对我隐藏", manager.weeklyLeaderboard(week, country = false).isEmpty())
        assertEquals("other", text(1, "p_reason"))
        assertEquals("来自排行榜", text(1, "p_details"))
    }

    @Test
    fun standingSummary() = runTest {
        val (backend, manager) = signedIn(TestSupport.profile(""","created_at":"2026-01-01T00:00:00+00:00""""))
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        manager.loadWeekly(week, country = false)
        val standing = manager.standing(week, country = false, manager.weeklyLeaderboard(week, country = false))!!
        assertEquals("还差 2 场上榜", standing.summary)
        assertNull(standing.rank)

        val onBoard = WeeklyStanding.of(Rankings.WeeklyScore(120, 5, 3, 2), me, listOf(Rankings.Entry(me, 3, 120, 5, 3)), null, true)
        assertEquals("第 3 名 · 120 分", onBoard.summary)
        val outside = WeeklyStanding.of(Rankings.WeeklyScore(30, 3, 1, 2), me, emptyList(), null, true)
        assertEquals("30 分 · 暂未进前 50 名", outside.summary)
        assertEquals("上周没有上榜", WeeklyStanding.of(Rankings.WeeklyScore(0, 0, 0, 0), me, emptyList(), null, false).summary)

        // 新注册的人：注册满 7 天才上榜
        val fresh = RankingManager(backend, now = { backend.currentUser!!.joinDate + 86_400_000L })
        assertTrue(fresh.boardAbsenceReason()!!.startsWith("注册满 7 天后上榜"))
    }

    @Test
    fun optedOutPlayerSeesWhy() = runTest {
        val (_, manager) = signedIn(TestSupport.profile(""","created_at":"2026-01-01T00:00:00+00:00""""))
        assertNull(manager.boardAbsenceReason())
        val (_, hidden) = signedIn(TestSupport.profile().replace("\"show_on_boards\":true", "\"show_on_boards\":false"))
        assertEquals("你在设置里关闭了上榜", hidden.boardAbsenceReason())
    }

    @Test
    fun filteredBoardIsReranked() {
        val list = listOf(
            Rankings.Entry("a", 2, 90, 5, 3),
            Rankings.Entry("b", 4, 60, 4, 2),
            Rankings.Entry("c", 5, 60, 4, 2),
            Rankings.Entry("d", 7, 40, 3, 1),
        )
        assertEquals(listOf(1, 2, 2, 4), RankingManager.reranked(list).map { it.rank })
    }

    @Test
    fun onlyCurrentAndPreviousPeriodComeFromServer() {
        val current = Rankings.week(now)
        val last = Rankings.week(current.start - 1)
        assertEquals(0, RankingManager.remoteOffset(current, current))
        assertEquals(1, RankingManager.remoteOffset(last, current))
        assertNull(RankingManager.remoteOffset(Rankings.week(last.start - 1), current))
    }

    @Test
    fun remainingTime() {
        assertEquals("31 小时", RankingManager.remaining(now + 31 * 3_600_000L + 120_000, now))
        assertEquals("40 分钟", RankingManager.remaining(now + 40 * 60_000L, now))
        assertEquals("至少 1 分钟", "1 分钟", RankingManager.remaining(now, now))
    }

    // MARK: 挑战

    @Test
    fun challengesComeFromServer() = runTest {
        val (_, manager) = signedIn()
        val start = iso(now + 86_400_000L)
        val end = iso(now + 86_400_000L + 3_600_000L)
        val expires = iso(now + 40 * 3_600_000L)
        server.on(
            "POST /rest/v1/rpc/my_challenges",
            """{"incoming":[{"id":"c1","starts_at":"$start","ends_at":"$end","message":"Best of three?","expires_at":"$expires","venue":{"name":"Court","tz":null},"player":{"id":"$blake","nickname":"Blake","rating":4.33}}],"outgoing":[{"id":"c2","starts_at":"$start","ends_at":"$end","game_id":null,"status":"not_happening","venue":{"name":"Court","tz":null},"player":{"id":"$blake","nickname":"Blake","rating":4.33}},{"id":"c6","starts_at":"$start","ends_at":"$end","game_id":"g1","status":"accepted","venue":{"name":"Court","tz":null},"player":{"id":"$blake","nickname":"Blake","rating":4.33}}]}""",
        )
        manager.refreshChallenges()
        val incoming = manager.challenges().first { it.id == "c1" }
        assertEquals(blake, incoming.challengerId)
        assertEquals(me, incoming.targetId)
        assertEquals(ChallengeStatus.Pending, incoming.status)
        assertEquals("Best of three?", incoming.message)
        assertEquals("截止时间倒推发出时间", now - 8 * 3_600_000L, incoming.createdAt)
        assertEquals("Court", incoming.court.name)
        assertEquals("没成行", ChallengeStatus.Expired, manager.challenges().first { it.id == "c2" }.status)
        assertEquals("g1", manager.challenges().first { it.id == "c6" }.gameId)
        assertEquals(listOf("c1"), manager.incoming().map { it.id })
        assertEquals(setOf("c2", "c6"), manager.outgoing().map { it.id }.toSet())

        server.requests.clear()
        server.on("POST /rest/v1/rpc/send_challenge", "\"c3\"")
        server.on("POST /rest/v1/rpc/my_challenges", """{"incoming":[],"outgoing":[]}""")
        val court = Venue("v1", "Court", lat = 0.0, lon = 0.0, countryCode = "US", pricing = VenuePricing.Unknown)
        val slot = TimeSlot.of(now, now + 86_400_000L, now + 90_000_000L)
        manager.send(blake, court, slot, " Rematch? ", null)
        assertEquals(blake, text(0, "p_target"))
        assertEquals("v1", text(0, "p_venue"))
        assertEquals("Rematch?", text(0, "p_message"))
        assertEquals(iso(now + 86_400_000L), text(0, "p_starts_at"))
        assertEquals("单打不带搭档", JsonNull, server.json(0)["p_partner"])
        assertTrue("服务器上没有的不留", manager.challenges().isEmpty())

        // 双打：发起时带搭档，接受时选自己的搭档
        server.requests.clear()
        server.on("POST /rest/v1/rpc/send_challenge", "\"c4\"")
        server.on(
            "POST /rest/v1/rpc/my_challenges",
            """{"incoming":[{"id":"c5","starts_at":"$start","ends_at":"$end","message":"","expires_at":"$expires","mode":"doubles","venue":{"name":"Court","tz":null},"player":{"id":"$blake","nickname":"Blake","rating":4.33},"partner":{"id":"$casey","nickname":"Casey","rating":4}}],"outgoing":[]}""",
        )
        manager.send(blake, court, slot, "", casey)
        assertEquals(casey, text(0, "p_partner"))
        val doubles = manager.challenges().first { it.id == "c5" }
        assertEquals(GameMode.Doubles, doubles.mode)
        assertEquals(casey, doubles.challengerPartnerId)
        assertEquals("Casey", manager.user(casey)?.nickname)

        server.requests.clear()
        server.on("POST /rest/v1/rpc/respond_challenge", "\"g9\"")
        server.on("POST /rest/v1/rpc/my_challenges", """{"incoming":[],"outgoing":[]}""")
        assertEquals("g9", manager.respond("c5", accept = true, partnerId = "dana"))
        assertEquals("dana", text(0, "p_partner"))
        assertEquals("true", text(0, "p_accept"))
    }

    @Test
    fun withdrawMarksLocallyFirst() = runTest {
        val (_, manager) = signedIn()
        val start = iso(now + 86_400_000L)
        server.on(
            "POST /rest/v1/rpc/my_challenges",
            """{"incoming":[],"outgoing":[{"id":"c2","starts_at":"$start","ends_at":"$start","status":"pending","venue":{"name":"Court"},"player":{"id":"$blake","nickname":"Blake","rating":4.33}}]}""",
        )
        manager.refreshChallenges()
        assertEquals(ChallengeStatus.Pending, manager.challenges().single().status)
        server.on("POST /rest/v1/rpc/withdraw_challenge", "null")
        manager.withdraw("c2")
        assertEquals(ChallengeStatus.Withdrawn, manager.challenges().single().status)
        assertEquals("c2", text(1, "p_challenge"))
    }

    @Test
    fun friendsBecomePartnerOptions() = runTest {
        val (_, manager) = signedIn()
        server.on("POST /rest/v1/rpc/my_friends", """{"friends":[{"id":"$casey","nickname":"Casey","rating":4.0,"created_at":null}],"requests":[]}""")
        manager.loadFriends()
        assertEquals(listOf("Casey"), manager.friends?.map { it.nickname })
    }
}
