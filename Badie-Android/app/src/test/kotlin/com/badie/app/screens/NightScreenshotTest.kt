package com.badie.app.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.features.groups.GroupScreen
import com.badie.app.features.matches.MatchCreateScreen
import com.badie.app.features.matches.MatchScoreSheet
import com.badie.app.features.matches.MatchScreen
import com.badie.app.features.matches.MatchShareRenderer
import com.badie.app.features.night.NightScreen
import com.badie.app.features.night.NightSettingsSheet
import com.badie.app.features.night.TonightCard
import com.badie.app.l10n.L10n
import com.badie.app.models.MatchState
import com.badie.app.models.NightState
import com.badie.app.models.TonightItem
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteJSON
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.LocalEnv
import com.github.takahirom.roborazzi.captureRoboImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant

/** 当晚的排场和比赛：当晚页、排场设置、新建比赛、比赛进行中、输比分、最终排名、球群页的“排场”、球局页的“今晚”卡。对应 iPhone 1.0.7 的设计稿 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class NightScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    private val me = TestSupport.session().userId
    private fun iso(offset: Long) = Instant.ofEpochMilli(System.currentTimeMillis() + offset).toString()

    private val people = listOf("Kevin", "Amy", "Jason", "Mei", "Raj", "Leo", "Tony B", "Sara", "Nina", "Omar", "Priya", "Ben")

    /** 12 人、2 片场地，开始了 40 分钟：两片场地在打，下一场、等候、休息 */
    private val nightState: String
        get() {
            val rows = people.mapIndexed { index, name ->
                val id = "s$index"
                val user = if (index < 6) "\"u-$index\"" else "null"
                val court = when (index) { in 0..3 -> "1"; in 4..7 -> "2"; else -> "null" }
                val status = if (index == 11) "resting" else "here"
                val queue = if (index in 8..10) "${index - 7}" else "null"
                """{"id":"$id","name":"$name","user_id":$user,"guest":${index >= 6},"status":"$status","waitlisted":false,"games":${2 + index % 2},"on_court":$court,"next_up":${index == 8},"queue":$queue}"""
            }
            return """{"session_id":"n1","group_id":"grp1","group":"周三晚双打","venue":"LA Badminton Club","tz":"America/Los_Angeles",""" +
                """"starts_at":"${iso(-40 * 60_000L)}","ends_at":"${iso(140 * 60_000L)}","role":"organizer","open":true,"started":true,"courts":2,"doubles":true,"balance":true,""" +
                """"board_code":"AB12CD34","match_id":null,"match_live":false,"helpers":[{"id":"u-1","nickname":"Amy"}],"undo_until":null,"people":[${rows.joinToString(",")}],""" +
                """"games":[{"id":41,"court":1,"players":["s0","s1","s2","s3"],"started_at":"${iso(-12 * 60_000L)}"},{"id":42,"court":2,"players":["s4","s5","s6","s7"],"started_at":"${iso(-4 * 60_000L)}"}],""" +
                """"next":[["s8","s9","s10","s0"]]}"""
        }

    private fun matchJson(status: String, role: String = "organizer", bestOf: Int = 1): String {
        val players = listOf("Kevin", "Amy", "Jason", "Mei", "Raj", "Leo", "Tony", "Sara")
        val playerRows = players.mapIndexed { i, n -> """{"id":"p$i","name":"$n","withdrawn":false,"user_id":${if (i < 4) "\"u-$i\"" else "null"}}""" }
        val standings = listOf(
            Triple("Amy", 4 to 1, 18), Triple("Kevin", 4 to 1, 12), Triple("Mei", 3 to 2, 6), Triple("Raj", 3 to 2, 2),
            Triple("Jason", 2 to 3, -3), Triple("Sara", 2 to 3, -7), Triple("Leo", 1 to 4, -12), Triple("Tony", 1 to 4, -16),
        ).mapIndexed { i, (name, wl, diff) ->
            """{"key":"k$i","name":"$name","members":["p$i"],"played":5,"wins":${wl.first},"losses":${wl.second},"pf":100,"pa":90,"diff":$diff,"rank":${if (i == 1) 1 else i + 1},"tied":${i == 1 || i == 0}}"""
        } // Amy 和 Kevin 并列第一
        val games = """[
            {"id":1,"round":1,"stage":"pool","a":["p0","p1"],"b":["p2","p3"],"status":"done","scores":[21,18],"winner":1,"version":1,"scored_by":"Amy"},
            {"id":2,"round":1,"stage":"pool","a":["p4","p5"],"b":["p6","p7"],"status":"done","scores":[19,21],"winner":2,"version":1,"scored_by":"Raj","flagged":true},
            {"id":3,"round":2,"stage":"pool","a":["p0","p2"],"b":["p4","p6"],"court":1,"status":"playing","version":0},
            {"id":4,"round":2,"stage":"pool","a":["p1","p3"],"b":["p5","p7"],"court":2,"status":"playing","version":0},
            {"id":5,"round":3,"stage":"pool","a":["p0","p3"],"b":["p5","p6"],"status":"queued","version":0},
            {"id":6,"round":3,"stage":"pool","a":["p1","p2"],"b":["p4","p7"],"status":"queued","version":0}]"""
        val ranking = if (status == "done") "[${standings.joinToString(",")}]" else "null"
        return """{"kind":"match","id":"m1","name":"11月18日 比赛","format":"round_robin","play":"rotating","doubles":true,"points":21,"best_of":$bestOf,""" +
            """"win_by_two":true,"courts":2,"rounds":7,"round":2,"status":"$status","created_at":"${iso(-90 * 60_000L)}","ended_at":${if (status == "done") "\"${iso(-60_000L)}\"" else "null"},""" +
            """"board_code":"ZX98YW76","tie_at_cut":false,"players":[${playerRows.joinToString(",")}],"games":$games,""" +
            """"standings":[${standings.joinToString(",")}],"ranking":$ranking,"role":"$role","me":"p0","helpers":[],"undo_until":null}"""
    }

    private fun environment(setup: FakeServer.() -> Unit): AppEnvironment {
        val server = FakeServer()
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
        runBlocking { backend.refreshProfile() }
        server.setup()
        return environment
    }

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", setup: FakeServer.() -> Unit = {}, prepare: suspend AppEnvironment.() -> Unit = {}, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        val environment = environment(setup)
        runBlocking { environment.prepare() }
        // 页面里有每 10 秒的重拉和计时：不自动走时间，走一段就拍
        compose.mainClock.autoAdvance = false
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(Appearance.Light) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        repeat(20) {
            compose.mainClock.advanceTimeBy(100)
            compose.waitForIdle()
        }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    @Test
    fun nightCourts() = shot("night-courts", qualifiers = "b+zh+Hans-h1000dp", setup = { on("POST /rest/v1/rpc/night_state", nightState) }) { NightScreen("n1") }

    @Test
    fun nightCourtsEnglish() = shot("night-courts-en", qualifiers = "en-h1000dp", setup = { on("POST /rest/v1/rpc/night_state", nightState) }) { NightScreen("n1") }

    @Test
    fun nightSettings() = shot("night-settings") {
        val state = RemoteJSON.decode<NightState>(nightState.toByteArray())
        Column(Modifier.fillMaxSize()) { NightSettingsSheet(state, me = me, onDismiss = {}) { _, _, _, _ -> } }
    }

    @Test
    fun matchCreate() = shot("match-create", qualifiers = "b+zh+Hans-h1300dp", setup = {
        on("POST /rest/v1/rpc/night_state", nightState)
        repeat(3) { on("POST /rest/v1/rpc/match_preview", """{"full_rounds":11,"default_rounds":7,"max_rounds":30,"rounds":7,"minutes":105}""") }
    }) { MatchCreateScreen("n1") }

    @Test
    fun matchLive() = shot("match-live", qualifiers = "b+zh+Hans-h1300dp", setup = { on("POST /rest/v1/rpc/match_state", matchJson("live")) }) { MatchScreen("m1") }

    @Test
    fun scoreEntry() = shot("match-score") {
        val match = RemoteJSON.decode<MatchState>(matchJson("live", bestOf = 3).toByteArray())
        val game = match.games.first { it.id == 3 }.copy(scores = listOf(21, 18, 19, 21, 21, 17))
        Column(Modifier.fillMaxSize()) { MatchScoreSheet(match, game, onDismiss = {}) {} }
    }

    @Test
    fun scoreEntryInvalid() = shot("match-score-invalid") {
        val match = RemoteJSON.decode<MatchState>(matchJson("live").toByteArray())
        val game = match.games.first { it.id == 3 }.copy(scores = listOf(25, 3))
        Column(Modifier.fillMaxSize()) { MatchScoreSheet(match, game, onDismiss = {}) {} }
    }

    @Test
    fun finalRanking() = shot("match-final", qualifiers = "b+zh+Hans-h1100dp", setup = { on("POST /rest/v1/rpc/match_state", matchJson("done")) }) { MatchScreen("m1") }

    @Test
    fun shareCard() = shot("match-share-card") {
        val match = RemoteJSON.decode<MatchState>(matchJson("done").toByteArray())
        val image = MatchShareRenderer.render(RuntimeEnvironment.getApplication(), match)!!
        Image(image, null, Modifier.fillMaxWidth().padding(AppTheme.Spacing.screen))
    }

    /** 群主：今天这一场开场前有“排场”；前天那一场还有 3 人没付 */
    @Test
    fun groupTonight() = shot("night-group", qualifiers = "b+zh+Hans-h1300dp", setup = {
        on("POST /rest/v1/rpc/group_page", groupPage)
        on("POST /rest/v1/rpc/my_dues", "[]")
        on(
            "POST /rest/v1/rpc/group_tonight",
            """[{"id":"s1","starts_at":"${iso(30 * 60_000L)}","ends_at":"${iso(210 * 60_000L)}","can_run":true,"board":null,"pay":null,"unpaid":null},""" +
                """{"id":"s0","starts_at":"${iso(-50 * 3_600_000L)}","ends_at":"${iso(-47 * 3_600_000L)}","can_run":false,"board":null,"pay":null,"unpaid":3}]""",
        )
    }, prepare = { groupManager.loadGroup("grp1") }) { GroupScreen("grp1") }

    /** 球员：开场后“看排场”；没写金额的一场“付给 Kevin” */
    @Test
    fun groupTonightPlayer() = shot("night-group-player", qualifiers = "b+zh+Hans-h1300dp", setup = {
        on("POST /rest/v1/rpc/group_page", groupPage.replace("\"my_role\":\"owner\"", "\"my_role\":\"member\"")
            .replace("\"rating\":4,\"role\":\"owner\"", "\"rating\":4,\"role\":\"member\"").replace("\"rating\":4.33,\"role\":\"member\"", "\"rating\":4.33,\"role\":\"owner\""))
        on("POST /rest/v1/rpc/my_dues", "[]")
        on(
            "POST /rest/v1/rpc/group_tonight",
            """[{"id":"s1","starts_at":"${iso(30 * 60_000L)}","ends_at":"${iso(210 * 60_000L)}","can_run":false,"board":"AB12CD34","pay":null},""" +
                """{"id":"s0","starts_at":"${iso(-26 * 3_600_000L)}","ends_at":"${iso(-23 * 3_600_000L)}","pay":{"to":"Kevin","amount":null,"handles":{"venmo":"kevin-w"},"paid":false}}]""",
        )
    }, prepare = { groupManager.loadGroup("grp1") }) { GroupScreen("grp1") }

    @Test
    fun gamesTonightCard() = shot("night-games-card", qualifiers = "b+zh+Hans-h400dp") {
        val items = RemoteJSON.decode<List<TonightItem>>(
            """[{"kind":"night","session_id":"n1","group_id":"grp1","name":"周三晚双打","board_code":"AB12CD34","status":"court","court":2,"games":2},
                {"kind":"match","match_id":"m1","name":"11月18日 比赛","board_code":"ZX98YW76","status":"waiting","round":3,"games":3}]""".toByteArray(),
        )
        TonightCard(items, Modifier.padding(AppTheme.Spacing.screen))
    }

    private val venue = """{"id":"v-1","name":"LA Badminton Club","city":"El Monte","tz":"America/Los_Angeles"}"""

    private val groupPage
        get() = """{"id":"grp1","name":"周三晚双打","summary":"","level_min":3,"level_max":6,"join_policy":"open","venue":$venue,""" +
            """"schedules":[{"weekday":3,"start":1140,"end":1320,"capacity":20,"price":null}],""" +
            """"activity":{"sessions":6,"average":14},"my_role":"owner","invite_code":"482913",""" +
            """"sessions":[{"id":"s1","starts_at":"${iso(30 * 60_000L)}","ends_at":"${iso(210 * 60_000L)}","capacity":20,"cancelled":false,"confirmed":14,"waitlist":2,"my_status":"confirmed","players":[{"id":"$me","nickname":"Alex","waitlisted":false}]},""" +
            """{"id":"s2","starts_at":"${iso(7 * 86_400_000L)}","ends_at":"${iso(7 * 86_400_000L + 10_800_000L)}","capacity":20,"cancelled":false,"confirmed":6,"waitlist":0,"my_status":null,"players":[]}],""" +
            """"members":[{"id":"$me","nickname":"Alex","rating":4,"role":"owner"},{"id":"u-2","nickname":"Kai","rating":4.33,"role":"member"}],"pending":[]}"""
}
