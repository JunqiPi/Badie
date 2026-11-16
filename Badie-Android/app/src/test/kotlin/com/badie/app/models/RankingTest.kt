package com.badie.app.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

/**
 * 赛果双方确认、月度胜率、场馆榜 / 周榜计分，和约球的确认期限。
 * 对应 iPhone 的 RankingTests 和 MatchmakingTests 里只用模型的部分（要模拟后端的那些等搬后端时再搬）
 */
class RankingTest {
    private val now = 1_800_000_000_000L
    private val zone = ZoneId.of("America/Los_Angeles")

    private fun finishedGame(id: String, players: List<String>, hoursAgo: Double = 3.0): Game {
        val start = now - (hoursAgo * 3_600_000).toLong()
        val slot = TimeSlot.of(start, start, start + 2 * 3_600_000L)
        val court = Venue("v1", "LABC", lat = 34.0, lon = -118.0, countryCode = "US", pricing = VenuePricing.DropIn(15))
        return Game(
            id = id, mode = GameMode.Singles, court = court, slot = slot, playerIds = players, teams = players.map { listOf(it) },
            hostId = players[0], origin = GameOrigin.QuickMatch, status = GameStatus.Completed, createdAt = now, checkIns = emptyMap(),
            paidPlayerIds = emptyList(), cost = CostSplit.estimate(court, slot, GameMode.Singles),
        )
    }

    private fun report(by: String, winner: Int?, games: List<Int>? = null, unsure: Boolean = false) =
        ResultReport(by, winner, "", now, unsure, games)

    private fun record(
        id: String, me: String, vs: String, won: Boolean, at: Long, venue: String = "v1", ratings: Map<String, Double> = emptyMap(),
    ) = MatchRecord(id, at, venue, "US", GameMode.Singles, listOf(listOf(me), listOf(vs)), if (won) 0 else 1, ratings)

    // MARK: 赛果确认

    @Test
    fun resultCountsOnlyWhenBothSidesAgree() {
        val game = finishedGame("g", listOf("me", "bot"))
        val mine = game.copy(resultReports = listOf(report("me", 0)))
        assertEquals(ResultStatus.Awaiting, mine.resultStatus(now))
        assertTrue(mine.acceptsResultReports(now))
        val both = mine.copy(resultReports = mine.resultReports + report("bot", 0))
        assertEquals(ResultStatus.Verified(0), both.resultStatus(now))
        assertFalse("确认后不能再改", both.acceptsResultReports(now))
        assertEquals(CostSplit.Basis.DropIn, game.cost.basis)
        assertEquals(5, game.cost.shuttleFee)
    }

    @Test
    fun conflictingReportsAreDisputed() {
        val game = finishedGame("g", listOf("me", "bot")).copy(resultReports = listOf(report("me", 0), report("bot", 1)))
        assertEquals(ResultStatus.Disputed, game.resultStatus(now))
        assertTrue("有分歧可以改", game.acceptsResultReports(now))
        val games = finishedGame("g", listOf("me", "bot")).copy(resultReports = listOf(report("me", 0, listOf(2, 1)), report("bot", 0, listOf(2, 0))))
        assertEquals("局数不一样也算分歧", ResultStatus.Disputed, games.resultStatus(now))
    }

    @Test
    fun unsureIsNeitherConfirmationNorDispute() {
        val game = finishedGame("g", listOf("me", "bot")).copy(resultReports = listOf(report("bot", 1), report("me", null, unsure = true)))
        assertEquals(ResultStatus.Unsure, game.resultStatus(now))
    }

    @Test
    fun unconfirmedResultExpiresInsteadOfAutoConfirming() {
        val game = finishedGame("g", listOf("a", "b"), hoursAgo = 24.0 * 8).copy(resultReports = listOf(report("a", 0)))
        assertEquals(ResultStatus.Expired, game.resultStatus(now))
    }

    @Test
    fun friendlyGameNeverCountsAndDrawNeedsGames() {
        val game = finishedGame("g", listOf("a", "b"))
        assertEquals(ResultStatus.Friendly, game.copy(resultReports = listOf(report("a", null), report("b", null))).resultStatus(now))
        val draw = game.copy(resultReports = listOf(report("a", null, listOf(1, 1)), report("b", null, listOf(1, 1))))
        assertEquals(ResultStatus.Draw, draw.resultStatus(now))
        assertEquals(GameCount(1, 1), draw.reportedGames("b"))
        val mine = game.copy(resultReports = listOf(report("b", 1, listOf(1, 2))))
        assertEquals("换成 a 的视角", GameCount(1, 2), mine.reportedGames("a"))
        assertEquals(GameCount(2, 1), mine.reportedGames("b"))
    }

    // MARK: 胜率

    @Test
    fun monthlyWinRateCapsSameOpponentAndNeedsFiveGames() {
        val month = Rankings.month(now, zone)
        val day = month.start + 3_600_000L
        var records = (0 until 5).map { record("x$it", "me", "friend", true, day + it * 60_000L) }
        var rate = Rankings.winRate("me", records, month)
        assertEquals("同一对手每月最多计入 3 场", Rankings.MONTHLY_SAME_OPPONENT_CAP, rate.games)
        assertFalse(rate.isPublic)

        records = records + listOf(record("y1", "me", "b", false, day), record("y2", "me", "c", true, day))
        rate = Rankings.winRate("me", records, month)
        assertEquals(5, rate.games)
        assertEquals(4, rate.wins)
        assertEquals(3, rate.opponents)
        assertTrue(rate.isPublic)
        assertEquals(80, rate.percentage)
    }

    @Test
    fun monthAndWeekBoundaries() {
        val month = Rankings.month(now, zone)
        val start = ZonedDateTime.of(2027, 1, 1, 0, 0, 0, 0, zone).toInstant().toEpochMilli()
        assertEquals(start, month.start)
        assertEquals(ZonedDateTime.of(2027, 2, 1, 0, 0, 0, 0, zone).toInstant().toEpochMilli(), month.end)
        // 2027-01-15 是周五：周榜从 UTC 的周一 01-11 开始
        val week = Rankings.week(now)
        assertEquals(ZonedDateTime.of(2027, 1, 11, 0, 0, 0, 0, ZoneOffset.UTC).toInstant().toEpochMilli(), week.start)
        assertEquals(week.start + 7 * 86_400_000L, week.end)
    }

    // MARK: 周榜积分

    @Test
    fun weeklyPointsRewardStrongerOpponentsAndDecayOnRepeats() {
        val t = Rankings.week(now).start + 3_600_000L
        val strong = record("s", "me", "pro", true, t, ratings = mapOf("me" to 4.0, "pro" to 5.0))
        val weak = record("w", "me", "rookie", true, t, ratings = mapOf("me" to 4.0, "rookie" to 2.0))
        assertEquals(22.5, Rankings.points(strong, "me", 0), 0.01)
        assertEquals(7.5, Rankings.points(weak, "me", 0), 0.01)
        assertEquals(11.25, Rankings.points(strong, "me", 1), 0.01)
        assertEquals(0.0, Rankings.points(strong, "me", 2), 0.0)
    }

    @Test
    fun weeklyBoardRequiresVarietyAndRespectsEligibility() {
        val week = Rankings.week(now)
        val t = week.start + 3_600_000L
        val farmer = (0 until 6).map { record("f$it", "farmer", "alt", true, t) }
        val regular = listOf(record("r1", "reg", "a", true, t), record("r2", "reg", "b", false, t), record("r3", "reg", "c", true, t))
        val board = Rankings.weeklyBoard(farmer + regular, week) { it != "hidden" }
        assertEquals("只和一个人反复打的不上榜", listOf("reg"), board.map { it.userId })
        assertEquals(40, board.first().score)
    }

    @Test
    fun venueBoardRanksByConfirmedGamesAtVenue() {
        val month = Rankings.month(now, zone)
        val t = month.start + 3_600_000L
        val regular = listOf("a", "b", "c", "d").mapIndexed { index, opponent ->
            record("r$index", "regular", opponent, false, t + index * 86_400_000L)
        }
        val visitor = listOf(record("v1", "visitor", "a", true, t), record("v2", "visitor", "b", true, t), record("v3", "visitor", "c", true, t))
        val elsewhere = (0 until 5).map { record("e$it", "regular", "z$it", true, t, venue = "v2") }
        val board = Rankings.venueBoard("v1", regular + visitor + elsewhere, month) { it in listOf("regular", "visitor") }
        assertEquals("比的是来得多，不是赢得多", listOf("regular", "visitor"), board.map { it.userId })
        assertEquals(4, board.first().score)
    }

    @Test
    fun tiedEntriesShareRank() {
        val week = Rankings.week(now)
        val t = week.start + 3_600_000L
        val records = listOf("x", "y").flatMap { me -> listOf("a", "b", "c").map { record("$me$it", me, it, true, t) } }
        val board = Rankings.weeklyBoard(records, week) { it == "x" || it == "y" }
        assertEquals(listOf(1, 1), board.map { it.rank })
        assertEquals(LevelBracket.Intermediate, LevelBracket.of(4.33))
        assertEquals(LevelBracket.Elite, LevelBracket.of(7.0))
        assertEquals("Lv.1–2 入门", LevelBracket.of(1.0).title)
    }

    // MARK: 约球的确认期限（MatchmakingTests 的时间规则）

    @Test
    fun confirmationWindowScalesWithLeadTime() {
        // 2027-01-15 08:00 UTC：白天，不触发夜间顺延
        fun window(hours: Double): Long =
            MatchTiming.respondBy(now + (hours * 3_600_000).toLong(), now, ZoneOffset.UTC) - now
        assertEquals(12 * 3_600_000L, window(48.0))
        assertEquals(12 * 3_600_000L, window(26.0))
        assertEquals(2 * 3_600_000L, window(10.0))
        assertEquals(2 * 3_600_000L, window(6.0))
        assertEquals(30 * 60_000L, window(4.0))
        assertEquals(30 * 60_000.0, window(2.55).toDouble(), 1000.0)
        // 临时局（2.5 小时内）：1 小时以上给 10 分钟，1 小时内给 5 分钟
        assertEquals(10 * 60_000L, window(2.0))
        assertEquals(5 * 60_000L, window(0.75))
    }

    @Test
    fun overnightDeadlinesMoveToMorning() {
        // 19:00 UTC 发出、开赛在两天后：12 小时窗口落在早上 07:00 → 顺延到 09:00
        val evening = ZonedDateTime.of(2027, 1, 15, 19, 0, 0, 0, ZoneOffset.UTC).toInstant().toEpochMilli()
        val respondBy = MatchTiming.respondBy(evening + 48 * 3_600_000L, evening, ZoneOffset.UTC)
        assertEquals(9, respondBy.zoned(ZoneOffset.UTC).hour)
        assertEquals(14 * 3_600_000L, respondBy - evening)
        // 顺延也不能晚于锁定时间
        val soon = evening + 7 * 3_600_000L
        assertTrue(MatchTiming.respondBy(soon, evening, ZoneOffset.UTC) <= MatchTiming.lock(soon, lastMinute = false))
    }

    @Test
    fun confirmationNeverRunsPastTheLock() {
        for (quarter in 2..(72 * 4)) {
            val start = now + quarter * 900_000L
            val respondBy = MatchTiming.respondBy(start, now, zone)
            val lock = MatchTiming.lock(start, MatchTiming.isLastMinute(start, now))
            assertTrue("开赛前 ${quarter / 4.0} 小时", respondBy <= lock)
            assertTrue(respondBy > now)
        }
    }

    @Test
    fun lastMinuteThresholds() {
        assertTrue(MatchTiming.isLastMinute(now + (2.4 * 3_600_000).toLong(), now))
        assertFalse(MatchTiming.isLastMinute(now + (2.6 * 3_600_000).toLong(), now))
        assertFalse(MatchTiming.canRequest(now + 29 * 60_000L, now))
        assertTrue(MatchTiming.canRequest(now + 30 * 60_000L, now))
        val start = now + 5 * 3_600_000L
        assertEquals(start - 2 * 3_600_000L, MatchTiming.lock(start, lastMinute = false))
        assertEquals(start - 20 * 60_000L, MatchTiming.lock(start, lastMinute = true))
        assertEquals("还剩 1 小时 52 分", MatchTiming.remainingText(now + 112 * 60_000L, now))
        assertEquals("还剩 1 分钟", MatchTiming.remainingText(now + 10_000L, now))
    }
}
