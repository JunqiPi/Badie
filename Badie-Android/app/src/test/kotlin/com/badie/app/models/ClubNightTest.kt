package com.badie.app.models

import com.badie.app.TestSupport
import com.badie.app.backend.NightApi
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteJSON
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 当晚和比赛：服务器给的 JSON 能读出来（字段名、可能为 null 的项、比赛的整数 id）、比分规则、人数规则。对应 iPhone 的 ClubNightTests */
class ClubNightTest {

    @Test
    fun decodesNightState() {
        val state = RemoteJSON.decode<NightState>(
            """{"session_id":"s-1","group_id":"g-1","group":"LABC 周三","venue":"LABC","tz":"America/Los_Angeles",
             "starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00","role":"organizer",
             "open":true,"started":true,"courts":2,"doubles":true,"balance":false,"board_code":"AB12CD34",
             "match_id":null,"match_live":false,"helpers":[{"id":"u-2","nickname":"Amy"}],
             "undo_until":"2026-11-18T20:01:05.123456+00:00",
             "people":[
               {"id":"a","name":"Kevin","user_id":"u-1","guest":false,"status":"here","waitlisted":false,"games":2,"on_court":1,"next_up":false},
               {"id":"b","name":"Tony 2","user_id":null,"guest":true,"status":"here","waitlisted":false,"games":1,"on_court":null,"next_up":true,"queue":1},
               {"id":"c","name":"Mei","user_id":"u-3","guest":false,"status":"here","waitlisted":false,"games":0,"on_court":null,"next_up":false,"queue":2},
               {"id":"d","name":"Raj","user_id":"u-4","guest":false,"status":"absent","waitlisted":true,"games":0,"on_court":null,"next_up":false}],
             "games":[{"id":42,"court":1,"players":["a","x","y","z"],"started_at":"2026-11-18T19:40:00+00:00"}],
             "next":[["b","c","e","f"]]}""".toByteArray(),
        )
        assertTrue(state.isOrganizer)
        assertEquals("AB12CD34", state.boardCode)
        assertNull(state.matchId)
        assertNotNull(state.undoUntil)
        assertEquals(42, state.games.first().id)
        assertEquals(listOf("a", "x"), state.sides(state.games[0].players).first)
        assertNull(state.people[1].userId)
        assertEquals(3, state.hereCount)
        // 等候：按排队的顺序（手动放到下一场的在前，再按场数）
        assertEquals(listOf("b", "c"), state.waiting.map { it.id })
        assertEquals(listOf(1, 2), state.courtNumbers)
        assertEquals(4, state.next.first().size)
        assertEquals("?", state.name("nobody"))
    }

    @Test
    fun waitingWithoutQueueAndCourtsStillPlaying() {
        val state = RemoteJSON.decode<NightState>(
            """{"session_id":"s-1","group_id":"g-1","group":"LABC","starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00",
             "role":"helper","open":true,"started":true,"courts":1,"doubles":true,"balance":false,
             "people":[
               {"id":"a","name":"A","guest":true,"status":"here","games":2},
               {"id":"b","name":"B","guest":true,"status":"here","games":1},
               {"id":"c","name":"C","guest":true,"status":"here","games":2,"next_up":true}],
             "games":[{"id":1,"court":3,"players":["x","y","z","w"],"started_at":"2026-11-18T19:40:00+00:00"}],"next":[]}""".toByteArray(),
        )
        assertFalse(state.isOrganizer)
        // 旧数据没有顺序：手动放到下一场的在前，再按今晚打的场数
        assertEquals(listOf("c", "b", "a"), state.waiting.map { it.id })
        // 减场地后还没打完的那片场地也显示
        assertEquals(listOf(1, 3), state.courtNumbers)
    }

    @Test
    fun noPermissionIsNull() = runTest {
        val server = FakeServer()
        server.on("POST /rest/v1/rpc/night_state", "null")
        assertNull(NightApi(TestSupport.backend(server, TestSupport.session()).remote).nightState("s-1"))
    }

    @Test
    fun decodesTonight() {
        val group = RemoteJSON.decode<List<GroupTonight>>(
            """[{"id":"s-1","starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00","can_run":false,"board":"AB12",
                 "pay":{"to":"Kevin","amount":null,"handles":{"venmo":"kevin-w"},"paid":false,"paid_self":null},"unpaid":null},
                {"id":"s-2","starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00","can_run":true,"board":"CD34","pay":null,"unpaid":3},
                {"id":"s-3","starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00","pay":{"to":"Kevin","amount":12,"paid":false}}]""".toByteArray(),
        )
        // 没写金额：场次行上“付给 Kevin”，换掉报名按钮
        assertTrue(group[0].paysHere)
        assertTrue(group[0].replacesSignup)
        // 组织者：有“排场”，不换掉报名按钮
        assertFalse(group[1].replacesSignup)
        assertTrue(group[1].hasAction)
        // 写了金额、还没付的由“你还没付”卡收
        assertFalse(group[2].paysHere)
        assertFalse(group[2].hasAction)

        val mine = RemoteJSON.decode<List<TonightItem>>(
            """[{"kind":"night","session_id":"s-1","group_id":"g-1","name":"LABC 周三","board_code":"AB12","status":"court","court":2,"games":1},
                {"kind":"match","match_id":"m-1","name":"周三比赛","board_code":"CD34","status":"waiting","court":null,"round":2,"games":3}]""".toByteArray(),
        )
        assertEquals("s-1", mine[0].id)
        assertEquals("m-1", mine[1].id)
        assertEquals(L10nKeys.court(2), mine[0].statusText)
    }

    @Test
    fun decodesMatchState() {
        val match = RemoteJSON.decode<MatchState>(
            """{"kind":"match","id":"m-1","name":"11月18日 比赛","format":"round_robin","play":"rotating","third_place":false,"doubles":false,"points":21,"best_of":1,
             "win_by_two":true,"courts":2,"rounds":7,"pools":null,"advance":null,"status":"live",
             "created_at":"2026-11-18T19:00:00+00:00","ended_at":null,"board_code":"ZX98YW76","session_id":null,
             "venue":null,"tie_at_cut":false,"round":3,
             "players":[{"id":"p1","name":"Kevin","team":null,"pool":null,"withdrawn":false},
                        {"id":"p2","name":"Amy","team":null,"pool":null,"withdrawn":false},
                        {"id":"p3","name":"Leo","team":null,"pool":null,"withdrawn":false},
                        {"id":"p4","name":"Raj","team":null,"pool":null,"withdrawn":true}],
             "games":[{"id":7,"round":1,"stage":"pool","a":["p1","p3"],"b":["p2","p4"],"status":"done","scores":[21,18],
                       "winner":1,"version":2,"scored_by":"Amy","flagged":true},
                      {"id":8,"round":3,"stage":"pool","a":["p1","p2"],"b":["p3","p4"],"court":1,"status":"playing","version":0},
                      {"id":9,"round":4,"stage":"ko","ko_size":8,"slot":1,"bye":true,"a":["p1"],"b":[],"status":"skipped","winner":1},
                      {"id":10,"round":4,"stage":"ko","ko_size":8,"slot":2,"a":["p2"],"b":["p3"],"status":"done","scores":[21,10,5,3],
                       "winner":1,"retired":2,"version":1}],
             "standings":[{"key":"p1","name":"Kevin","members":["p1"],"pool":null,"seed":1,"withdrawn":false,"played":1,"wins":1,
                           "losses":0,"pf":21,"pa":18,"diff":3,"rate":1.0,"rank":1,"tied":false}],
             "ranking":null,"role":"player","me":"p1","helpers":[],"undo_until":null}""".toByteArray(),
        )
        assertTrue(match.isLive)
        assertFalse(match.canManage)
        assertEquals(1, match.bestOf)
        assertEquals("Kevin · Leo", match.sideName(match.games[0].a))
        assertEquals("Amy", match.games[0].scoredBy)
        assertNull(match.games[1].scores)
        // 球员只能在打的时候输自己那场
        assertFalse(match.canScore(match.games[0]))
        assertTrue(match.canScore(match.games[1]))
        assertEquals(3, match.standings.first().diff)
        assertEquals("21–18 19–21", MatchRules.scoreText(listOf(21, 18, 19, 21)))
        // 轮空不是一场球
        assertEquals(3, match.realGames.size)
        assertFalse(match.canScore(match.games[2]))
        assertEquals(2, match.games[3].retired)
        assertEquals(MatchPlay.Rotating.title, MatchFormat.title(match.format, match.play))
        assertEquals("${MatchFormat.Knockout.title} · ${MatchPlay.Singles.title}", MatchFormat.title("knockout", "singles"))
        assertEquals("+3", MatchRules.diffText(3))
        assertEquals("−2", MatchRules.diffText(-2))
    }

    @Test
    fun scoreRulesOnlyAcceptRealScores() {
        val fifteen = MatchScoring.Rules(points = 15, bestOf = 1, winByTwo = false)
        assertEquals(MatchScoring.Check.Winner(1), MatchScoring.check(listOf(15, 9), fifteen))
        // 15 分封顶：16:1 存不了
        assertTrue(MatchScoring.check(listOf(16, 1), fifteen) is MatchScoring.Check.Problem)
        val deuce = MatchScoring.Rules(points = 21, bestOf = 1, winByTwo = true)
        assertEquals(MatchScoring.Check.Winner(2), MatchScoring.check(listOf(22, 24), deuce))
        assertEquals(MatchScoring.Check.Winner(1), MatchScoring.check(listOf(30, 29), deuce))
        assertTrue("21:20 没拉开 2 分", MatchScoring.check(listOf(21, 20), deuce) is MatchScoring.Check.Problem)
        assertTrue("25:3 打不出来", MatchScoring.check(listOf(25, 3), deuce) is MatchScoring.Check.Problem)
        assertEquals(MatchScoring.Check.Empty, MatchScoring.check(emptyList(), deuce))
        // 三局两胜：只填一局不收，赢满两局才行，第三局多余也不收
        val bo3 = MatchScoring.Rules(points = 21, bestOf = 3, winByTwo = true)
        assertTrue("三局两胜只填一局", MatchScoring.check(listOf(21, 10), bo3) is MatchScoring.Check.Problem)
        assertEquals(MatchScoring.Check.Winner(1), MatchScoring.check(listOf(21, 10, 15, 21, 21, 19), bo3))
        assertTrue("前两局已经分出胜负", MatchScoring.check(listOf(21, 10, 21, 15, 21, 3), bo3) is MatchScoring.Check.Problem)
        assertEquals(listOf(21, 10, 21, 15), MatchScoring.played(listOf(21, 10, 21, 15, 0, 0)))
        // 中途退赛：前面的局打完、最后一局可以没打完
        assertNull(MatchScoring.retireProblem(listOf(21, 10, 5, 3), bo3))
        assertNull(MatchScoring.retireProblem(emptyList(), bo3))
        assertNotNull(MatchScoring.retireProblem(listOf(21, 10, 21, 5), bo3))
        assertNotNull(MatchScoring.retireProblem(listOf(5, 3, 21, 10), bo3))
        assertNotNull(MatchScoring.retireProblem(listOf(25, 3), deuce))
    }

    @Test
    fun countRulesPerFormat() {
        assertNull(MatchSetup.countProblem(MatchFormat.RoundRobin, MatchPlay.Singles, 2, 2, 1))
        assertNotNull(MatchSetup.countProblem(MatchFormat.RoundRobin, MatchPlay.Rotating, 3, 2, 1))
        assertNotNull(MatchSetup.countProblem(MatchFormat.RoundRobin, MatchPlay.Fixed, 5, 2, 1))
        assertNotNull(MatchSetup.countProblem(MatchFormat.Swiss, MatchPlay.Singles, 2, 2, 1))
        assertNull(MatchSetup.countProblem(MatchFormat.Knockout, MatchPlay.Singles, 6, 2, 1))
        // 2 组各出 2 人：每组至少 3 人
        assertNotNull(MatchSetup.countProblem(MatchFormat.Groups, MatchPlay.Singles, 5, 2, 2))
        assertNull(MatchSetup.countProblem(MatchFormat.Groups, MatchPlay.Singles, 6, 2, 2))
    }

    @Test
    fun boardLink() {
        assertEquals("$12", FeeText.text(12.0))
        assertEquals("$12.50", FeeText.text(12.5))
        assertEquals("https://badie.rsvp/live/AB12CD34/", PayLinks.board("AB12CD34"))
    }

    /** 发给服务器的参数和 iPhone 一样：点名的 null、比赛的参赛名单、只在有值时带的几项 */
    @Test
    fun sendsTheSameArguments() = runTest {
        val server = FakeServer()
        val api = NightApi(TestSupport.backend(server, TestSupport.session()).remote)
        server.on("POST /rest/v1/rpc/night_mark", "null")
        api.nightMark("s-1", null, "here")
        val mark = server.json(server.requests.lastIndex)
        assertEquals(JsonNull, mark["p_signups"])
        assertEquals("here", mark["p_status"]?.jsonPrimitive?.content)

        server.on("POST /rest/v1/rpc/create_match", "\"m-1\"")
        val id = api.createMatch(
            " 周三比赛 ", null, 2, MatchFormat.RoundRobin, MatchPlay.Rotating, 21, 1, true,
            listOf(mapOf("user_id" to "u-1"), mapOf("signup_id" to "a"), mapOf("name" to "Tony")), rounds = 5, pools = null, advance = null,
            thirdPlace = false, sessionId = "s-1",
        )
        assertEquals("m-1", id)
        val create = server.json(server.requests.lastIndex)
        assertEquals("周三比赛", create["p_name"]?.jsonPrimitive?.content)
        assertEquals("round_robin", create["p_format"]?.jsonPrimitive?.content)
        assertEquals("rotating", create["p_play"]?.jsonPrimitive?.content)
        assertEquals(JsonNull, create["p_venue"])
        assertEquals(5, create["p_rounds"]?.jsonPrimitive?.content?.toInt())
        assertFalse(create.containsKey("p_pools"))
        assertEquals("s-1", create["p_session"]?.jsonPrimitive?.content)
        assertEquals("a", create["p_players"]?.jsonArray?.get(1)?.jsonObject?.get("signup_id")?.jsonPrimitive?.content)

        server.on("POST /rest/v1/rpc/match_withdraw", "null")
        api.matchWithdraw("p1", null)
        assertFalse(server.json(server.requests.lastIndex).containsKey("p_game"))
    }

    @Test
    fun entryPayloads() {
        assertEquals(mapOf("signup_id" to "a"), com.badie.app.features.matches.MatchEntry("a", "Kevin", userId = "u-1", signupId = "a").payload)
        assertEquals(mapOf("user_id" to "u-1"), com.badie.app.features.matches.MatchEntry("u-1", "Kevin", userId = "u-1").payload)
        assertEquals(mapOf("name" to "Tony"), com.badie.app.features.matches.MatchEntry("x", "Tony", guest = true).payload)
    }

    private object L10nKeys {
        fun court(n: Int) = com.badie.app.l10n.L10n.tr("你在场地 %lld", n)
    }
}
