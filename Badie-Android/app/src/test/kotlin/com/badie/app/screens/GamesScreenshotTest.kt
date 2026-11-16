package com.badie.app.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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
import com.badie.app.features.games.GameDetailScreen
import com.badie.app.features.games.GameHistoryScreen
import com.badie.app.features.games.GamesScreen
import com.badie.app.features.games.SurveyFormScreen
import com.badie.app.features.games.SurveyListScreen
import com.badie.app.features.rooms.CreateRoomScreen
import com.badie.app.features.rooms.JoinRoomScreen
import com.badie.app.features.rooms.PublicGamesScreen
import com.badie.app.features.rooms.RoomScreen
import com.badie.app.l10n.L10n
import com.badie.app.models.Coordinate
import com.badie.app.remote.FakeServer
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.LocalEnv
import com.github.takahirom.roborazzi.captureRoboImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant

/** 球局、房间、评价几页的截图（假数据），和 iPhone 的截图对照。在 app/build/outputs/roborazzi */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class GamesScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @After
    fun detach() = L10n.detach()

    private val me = TestSupport.USER_ID
    private val now = System.currentTimeMillis()
    private val roomId = "8d1c2c3e-0000-4000-8000-0000000000aa"

    private fun iso(offsetMillis: Long) = Instant.ofEpochMilli(now + offsetMillis).toString()

    private val venue = """{"id":"v-labc","name":"LA Badminton Club","city":"El Monte","street":"9800 Telstar Ave","tz":"America/Los_Angeles","lat":34.07,"lon":-118.03,"country":"US","pricing":{"perPerson":15}}"""

    private fun player(id: String, name: String, rating: Double, team: Int, checkedIn: Boolean = false, paid: Boolean = false, reviewed: Boolean = false) =
        """{"id":"$id","nickname":"$name","rating":$rating,"team":$team,"me":${id == me},"checked_in":$checkedIn,"paid":$paid,"reviewed":$reviewed}"""

    private val doublesPlayers = listOf(
        player(me, "Alex", 4.0, 1, checkedIn = true, paid = true), player("u-2", "欣然", 4.33, 1),
        player("u-3", "Blake", 4.0, 2, paid = true), player("u-4", "阿杰", 3.67, 2),
    ).joinToString(",", "[", "]")

    private fun game(id: String, start: Long, hours: Int = 2, extra: String = "", players: String = doublesPlayers, mode: String = "doubles") =
        """{"id":"$id","mode":"$mode","starts_at":"${iso(start)}","ends_at":"${iso(start + hours * 3_600_000L)}","status":"scheduled","venue":$venue,"host_id":"$me","my_team":1,"checked_in":false,"review_until":"${iso(start + (hours + 48) * 3_600_000L)}","players":$players$extra}"""

    private val games = listOf(
        game("g-next", 26 * 3_600_000L),
        game("g-later", 4 * 86_400_000L, players = listOf(player(me, "Alex", 4.0, 1), player("u-5", "Mia", 4.33, 2)).joinToString(",", "[", "]"), mode = "singles"),
        game("g-done", -27 * 3_600_000L, extra = ""","my_report":{"outcome":"team1","score":"21:18 19:21 21:15","team1_games":2,"team2_games":1},"result":{"status":"awaiting","outcome":null},"score":"21:18 19:21 21:15""""),
        game("g-old", -6 * 86_400_000L, extra = ""","my_report":{"outcome":"team2","team1_games":1,"team2_games":2},"result":{"status":"verified","outcome":"team2"},"rounds":{"team1":1,"team2":2}"""),
    ).joinToString(",", "[", "]")

    private fun room(visibility: String = "public", owner: String = me, members: String? = null, going: Int = 3) =
        """{"id":"$roomId","mode":"doubles","visibility":"$visibility","status":"open","closed_reason":null,"game_id":null,"starts_at":"${iso(2 * 86_400_000L)}","ends_at":"${iso(2 * 86_400_000L + 7_200_000L)}","level_min":3,"level_max":5,"tags":["casual","beginner_friendly"],"note":"已订 2 小时，自带球","going":$going,"waitlist":0,"last_activity_at":"${iso(-600_000)}","owner":{"id":"$owner","nickname":"Alex","rating":4},"venue":$venue,"my_status":"owner","code":"ABC234","members":${members ?: """[{"id":"$me","nickname":"Alex","rating":4,"waitlisted":false},{"id":"u-2","nickname":"欣然","rating":4.33,"waitlisted":false},{"id":"u-3","nickname":"Blake","rating":4,"waitlisted":false}]"""}}"""

    private val nearby =
        """[{"id":"r-near","mode":"singles","visibility":"public","status":"open","starts_at":"${iso(30 * 3_600_000L)}","ends_at":"${iso(32 * 3_600_000L)}","level_min":4,"level_max":6,"tags":["competitive"],"note":"","going":1,"waitlist":0,"owner":{"id":"u-9","nickname":"Kai","rating":5},"venue":$venue,"my_status":null,"code":null,"members":null},""" +
            """{"id":"r-near2","mode":"doubles","visibility":"public","status":"open","starts_at":"${iso(50 * 3_600_000L)}","ends_at":"${iso(52 * 3_600_000L)}","level_min":1,"level_max":9,"tags":["casual","women_friendly"],"note":"","gender":"female","going":2,"waitlist":0,"owner":{"id":"u-8","nickname":"Lily","rating":3},"venue":$venue,"my_status":null,"code":null,"members":null}]"""

    /** 登录好、拉过球局和房间的环境 */
    private fun environment(withData: Boolean = true): AppEnvironment {
        val server = FakeServer()
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
        runBlocking {
            backend.refreshProfile()
            if (withData) {
                server.on("POST /rest/v1/rpc/my_games", games)
                server.on("POST /rest/v1/rpc/my_rooms", "[${room()}]")
                server.on("POST /rest/v1/rpc/room_page", room())
                server.on("POST /rest/v1/rpc/rooms_near", nearby)
                environment.roomManager.book.refresh()
                environment.roomManager.refreshRooms()
                environment.roomManager.loadNearby(Coordinate(34.07, -118.03))
            } else {
                server.on("POST /rest/v1/rpc/my_games", "[]")
                environment.roomManager.book.refresh()
            }
        }
        return environment
    }

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, withData: Boolean = true, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        val environment = environment(withData)
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    @Test
    fun gamesTab() = shot("games-tab", qualifiers = "b+zh+Hans-h2400dp") { GamesScreen() }

    @Test
    fun gamesTabEmpty() = shot("games-tab-empty", withData = false) { GamesScreen() }

    @Test
    fun gamesTabEnglishDark() = shot("games-tab-en-dark", qualifiers = "en-h2400dp", appearance = Appearance.Dark) { GamesScreen() }

    @Test
    fun gameDetailUpcoming() = shot("game-detail-upcoming", qualifiers = "b+zh+Hans-h1900dp") { GameDetailScreen("g-next") }

    @Test
    fun gameDetailFinished() = shot("game-detail-finished", qualifiers = "b+zh+Hans-h1700dp") { GameDetailScreen("g-done") }

    @Test
    fun completeGameSheet() = shot("game-complete-sheet") {
        val book = LocalEnv.current.roomManager.book
        com.badie.app.features.games.CompleteGameSheet(book.game("g-done")!!, isConfirming = false, initial = null) {}
    }

    @Test
    fun history() = shot("game-history") { GameHistoryScreen() }

    @Test
    fun surveyList() = shot("survey-list") { SurveyListScreen() }

    @Test
    fun surveyForm() = shot("survey-form", qualifiers = "b+zh+Hans-h1300dp") {
        val survey = LocalEnv.current.surveyManager.pendingSurveys.first()
        SurveyFormScreen(survey.id)
    }

    @Test
    fun roomLobby() = shot("room-lobby", qualifiers = "b+zh+Hans-h1300dp") { RoomScreen(roomId) }

    @Test
    fun createRoom() = shot("room-create", qualifiers = "b+zh+Hans-h1400dp") { CreateRoomScreen(null, null) }

    @Test
    fun joinRoom() = shot("room-join") { JoinRoomScreen("ABC2") }

    @Test
    fun publicGames() = shot("room-public-games") { PublicGamesScreen() }
}
