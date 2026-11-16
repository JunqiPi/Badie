package com.badie.app.features.games

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.Backend
import com.badie.app.models.AttendanceAnswer
import com.badie.app.models.GameCount
import com.badie.app.models.GameResult
import com.badie.app.models.GameStatus
import com.badie.app.models.PendingSurvey
import com.badie.app.models.Avatar
import com.badie.app.models.ResultStatus
import com.badie.app.models.SkillTier
import com.badie.app.models.SurveyIssue
import com.badie.app.models.SurveyTag
import com.badie.app.models.LevelCalibration
import com.badie.app.remote.FakeServer
import com.badie.app.shell.AppState
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.test.TestScope
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
import java.time.Instant

/** 球局、赛果、评价：从服务器读、往服务器写。对应 iPhone 的 SupabaseClientTests 里球局那几条 */
class GamesTest {
    private val server = FakeServer()
    private val me = TestSupport.USER_ID
    private val blake = "6f1c2c3e-0000-4000-8000-000000000002"
    private val now = System.currentTimeMillis()

    private fun iso(offsetMillis: Long) = Instant.ofEpochMilli(now + offsetMillis).toString()

    private fun players(paid: Boolean = false) =
        """[{"id":"$me","nickname":"Alex","rating":4,"team":1,"me":true,"checked_in":true,"reviewed":false},""" +
            """{"id":"$blake","nickname":"Blake","rating":4.33,"team":2,"me":false,"checked_in":false,"reviewed":false${if (paid) ""","paid":true""" else ""}}]"""

    private val venue = """{"id":"v-test-court","name":"Test Court","city":"Irvine","street":"1 Main St","tz":"America/Los_Angeles","lat":33.68,"lon":-117.8,"country":"US","pricing":{"perPerson":12}}"""

    private suspend fun TestScope.signedIn(): Pair<Backend, SurveyManager> {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        server.requests.clear()
        val context = ManagerContext(backgroundScope, backend, AppState(backgroundScope, backend), null)
        return backend to SurveyManager(context)
    }

    @Test
    fun gamesAndSurveysComeFromServer() = runTest {
        val (_, surveys) = signedIn()
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g1","mode":"singles","starts_at":"${iso(-3 * 3_600_000)}","ends_at":"${iso(-3_600_000)}","status":"scheduled","venue":$venue,"my_team":1,"checked_in":true,"my_report":{"outcome":"team1"},"result":{"status":"verified","outcome":"team1"},"review_until":"${iso(47 * 3_600_000)}","players":${players()}}]""",
        )
        surveys.refresh()
        val book = surveys.book
        val game = book.game("g1")!!
        assertEquals("我已经报过赛果", GameStatus.Completed, game.status)
        assertTrue(game.hasCheckedIn(me))
        assertFalse(game.hasCheckedIn(blake))
        assertEquals(ResultStatus.Verified(0), game.resultStatus())
        assertEquals(true, game.result?.didWin)
        assertEquals("球馆库里没有：用服务器给的信息", "Test Court", game.court.name)
        assertEquals("Blake", book.user(blake)?.nickname)
        assertEquals(4.33, book.user(blake)?.selfReportedRating ?: 0.0, 0.001)
        val survey = surveys.pendingSurveys.single()
        assertEquals(blake, survey.opponentId)
        assertEquals("g1", survey.matchId)
        assertEquals(1, surveys.pendingCount)
        assertEquals("打完了：不是下一场", null, book.nextGame)
        assertEquals(listOf("g1"), book.pastGames.map { it.id })
    }

    @Test
    fun scoresAndCourtFeesSyncWithServer() = runTest {
        val (backend, surveys) = signedIn()
        val book = surveys.book
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g1","mode":"singles","starts_at":"${iso(-3 * 3_600_000)}","ends_at":"${iso(-3_600_000)}","status":"scheduled","venue":$venue,"host_id":"$me","my_team":1,"checked_in":true,"my_report":{"outcome":"team1","score":"21:15 21:18"},"result":{"status":"awaiting","outcome":null},"score":"21:15 21:18","review_until":"${iso(47 * 3_600_000)}","players":${players(paid = true)}}]""",
        )
        book.refresh()
        val game = book.game("g1")!!
        assertEquals("房间开的局：服务器给的发起人", me, game.hostId)
        assertTrue(game.hasPaid(blake))
        assertFalse(game.hasPaid(me))
        assertEquals("21:15 21:18", game.report(me)?.score)
        assertEquals("21:15 21:18", game.result?.score)
        assertEquals("21:15 21:18", game.reportedScore(me))
        assertEquals(true, game.resultOutcome(me))

        // 发起人替别人标记：本地马上变，再同步到服务器
        server.requests.clear()
        server.on("POST /rest/v1/rpc/mark_paid", "")
        server.on("POST /rest/v1/rpc/my_games", "[]")
        book.togglePaid(game, blake, this, AppState(backgroundScope, backend))
        assertFalse(book.game("g1")?.hasPaid(blake) ?: true)
        testScheduler.advanceUntilIdle()
        assertEquals(blake, server.json(0)["p_user"]?.jsonPrimitive?.content)
        assertEquals(false, server.json(0)["p_paid"]?.jsonPrimitive?.boolean)

        // 报赛果：两边的局数换成 team1 / team2
        server.requests.clear()
        server.on("POST /rest/v1/rpc/report_result", "\"awaiting\"")
        server.on("POST /rest/v1/rpc/my_games", "[]")
        book.report(game, "18:21", GameCount(0, 1), unsure = false)
        val body = server.json(0)
        assertEquals("team2", body["p_outcome"]?.jsonPrimitive?.content)
        assertEquals("18:21", body["p_score"]?.jsonPrimitive?.content)
        assertEquals(0, body["p_team1_games"]?.jsonPrimitive?.int)
        assertEquals(1, body["p_team2_games"]?.jsonPrimitive?.int)

        assertTrue(GameResult.isValidScore(""))
        assertTrue(GameResult.isValidScore("21:18, 19-21 / 21:15"))
        assertFalse(GameResult.isValidScore("我们赢了"))
        assertFalse(GameResult.isValidScore("1".repeat(41)))
    }

    @Test
    fun unsureAndFriendlyReports() = runTest {
        val (_, surveys) = signedIn()
        val book = surveys.book
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g2","mode":"doubles","starts_at":"${iso(-3 * 3_600_000)}","ends_at":"${iso(-3_600_000)}","status":"scheduled","venue":$venue,"my_team":2,"checked_in":false,"review_until":"${iso(47 * 3_600_000)}","players":${players()}}]""",
        )
        book.refresh()
        val game = book.game("g2")!!
        assertEquals("还没报赛果：已确认", GameStatus.Confirmed, game.status)
        assertTrue("提醒默认开（和 iPhone 一样）", game.reminderEnabled)

        // 记不清：outcome 是 null，不带局数
        server.on("POST /rest/v1/rpc/report_result", "\"awaiting\"")
        server.on("POST /rest/v1/rpc/my_games", "[]")
        book.report(game, "", null, unsure = true)
        assertEquals(JsonNull, server.json(1)["p_outcome"])
        assertNull(server.json(1)["p_team1_games"])

        // 练球：friendly
        server.requests.clear()
        server.on("POST /rest/v1/rpc/report_result", "\"awaiting\"")
        server.on("POST /rest/v1/rpc/my_games", "[]")
        book.report(game, "", null, unsure = false)
        assertEquals("friendly", server.json(0)["p_outcome"]?.jsonPrimitive?.content)
    }

    @Test
    fun disputedResultHidesWhoSaidWhat() = runTest {
        val (_, surveys) = signedIn()
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g3","mode":"singles","starts_at":"${iso(-3 * 3_600_000)}","ends_at":"${iso(-3_600_000)}","status":"scheduled","venue":$venue,"my_team":1,"checked_in":true,"my_report":{"outcome":"team1","team1_games":2,"team2_games":1},"result":{"status":"disputed","outcome":null},"review_until":"${iso(47 * 3_600_000)}","players":${players()}}]""",
        )
        surveys.book.refresh()
        val game = surveys.book.game("g3")!!
        assertEquals(ResultStatus.Disputed, game.resultStatus())
        assertEquals(GameCount(2, 1), game.reportedGames(me))
        assertTrue("有分歧还能改", game.acceptsResultReports())
    }

    @Test
    fun reviewSendsLevelCheckAndTags() = runTest {
        val (_, surveys) = signedIn()
        server.on("POST /rest/v1/rpc/review_player", "")
        server.on("POST /rest/v1/rpc/my_games", "[]")
        val pending = PendingSurvey(
            "g1|b", "g1", me, blake, "Blake", 4, Avatar.default(blake), "Test Court", now, now + 3_600_000, opponentRating = 4.33,
        )
        surveys.submit(pending, SkillTier.ofRating(4.0), AttendanceAnswer.Late, listOf(SurveyTag.FairPlay, SurveyTag.GreatPartner), listOf(SurveyIssue.Unpaid), true)
        val review = server.json(0)
        assertEquals("选的档位比对方显示的低", "lower", review["p_level"]?.jsonPrimitive?.content)
        assertEquals("late", review["p_attendance"]?.jsonPrimitive?.content)
        assertEquals(listOf("fair_play", "great_partner"), review["p_tags"]?.jsonArray?.map { it.jsonPrimitive.content })
        assertEquals(listOf("unpaid"), review["p_issues"]?.jsonArray?.map { it.jsonPrimitive.content })
        assertEquals(true, review["p_play_again"]?.jsonPrimitive?.boolean)
    }

    @Test
    fun surveyAnswersFollowCalibration() {
        val displayed = SkillTier.ofRating(4.0)
        var answers = SurveyAnswers(skillRating = displayed)
        answers = answers.withCalibration(LevelCalibration.Higher, displayed)
        assertEquals(displayed.offset(1), answers.skillRating)
        answers = answers.withTier(displayed.offset(-1), displayed)
        assertEquals("正好低一档：三选一跟着亮", LevelCalibration.Lower, answers.calibration)
        answers = answers.withTier(displayed.offset(3), displayed)
        assertNull("差得多：三个都不亮", answers.calibration)
        assertTrue(answers.isPositive)
        assertFalse(answers.copy(attendance = AttendanceAnswer.NoShow).isPositive)
        assertFalse(answers.copy(characterRating = 3).isPositive)
    }

    @Test
    fun resultFormRules() {
        assertFalse("没选不能交", ResultForm.canSubmit(null, 0, 0, ""))
        assertTrue(ResultForm.canSubmit(Choice.Practice, 0, 0, ""))
        assertFalse("一局都没填", ResultForm.canSubmit(Choice.Counted, 0, 0, ""))
        assertTrue(ResultForm.canSubmit(Choice.Counted, 2, 1, "21:18 19:21 21:15"))
        assertTrue("比分和局数对不上", ResultForm.scoreDisagrees("21:18 19:21 21:15", 1, 2))
        assertFalse(ResultForm.canSubmit(Choice.Counted, 1, 2, "21:18 19:21 21:15"))
        assertFalse("比分格式不对", ResultForm.canSubmit(Choice.Counted, 1, 0, "赢了"))
    }

    @Test
    fun ratingPromptOnlyAfterTwoGamesAndAGoodReview() {
        assertFalse(RatingPrompt.shouldAsk(1, positive = true, now = now, lastAskedAt = null))
        assertFalse(RatingPrompt.shouldAsk(5, positive = false, now = now, lastAskedAt = null))
        assertTrue(RatingPrompt.shouldAsk(2, positive = true, now = now, lastAskedAt = null))
        // 120 天最多一次
        assertFalse(RatingPrompt.shouldAsk(3, positive = true, now = now + 100 * 86_400_000L, lastAskedAt = now))
        assertTrue(RatingPrompt.shouldAsk(3, positive = true, now = now + 121 * 86_400_000L, lastAskedAt = now))
    }

    @Test
    fun remindersOneDayTwoHoursFifteenMinutesBefore() = runTest {
        val (_, surveys) = signedIn()
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g4","mode":"singles","starts_at":"${iso(3 * 3_600_000)}","ends_at":"${iso(5 * 3_600_000)}","status":"scheduled","venue":$venue,"my_team":1,"checked_in":false,"review_until":"${iso(53 * 3_600_000)}","players":${players()}}]""",
        )
        surveys.book.refresh()
        val game = surveys.book.game("g4")!!
        assertEquals("1 天前已经过了：只剩 2 小时和 15 分钟", listOf(game.slot.startTime - 2 * 3_600_000, game.slot.startTime - 15 * 60_000), ReminderService.fireTimes(game, now))
        assertEquals(game, surveys.book.nextGame)
        assertEquals("单元测试里没有系统：开不了提醒", false, surveys.book.setReminder(game, true))
    }
}
