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
import com.badie.app.backend.DayCandidate
import com.badie.app.backend.RemoteTicket
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.features.home.DayCardFilter
import com.badie.app.features.home.DayCardFilterSheet
import com.badie.app.features.home.DiscoverMode
import com.badie.app.features.home.DiscoverScreen
import com.badie.app.features.home.InviteAnswerSheet
import com.badie.app.features.home.InviteComposeContent
import com.badie.app.features.home.VenueCount
import com.badie.app.features.matching.MatchDraft
import com.badie.app.features.matching.MatchSetupContent
import com.badie.app.features.matching.OfferView
import com.badie.app.features.matching.SearchingView
import com.badie.app.features.matching.TicketEndedView
import com.badie.app.features.matching.TicketStatusCard
import com.badie.app.features.matching.TicketWaitingView
import com.badie.app.l10n.L10n
import com.badie.app.models.Coordinate
import com.badie.app.models.GameMode
import com.badie.app.models.MatchTicket
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.User
import com.badie.app.models.addingDays
import com.badie.app.models.startOfDay
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteJSON
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

/** 发现页（附近的人、按天看人、筛选、约 TA、回邀请）和快速匹配（设置、找人、提议、等待、结束）的截图，用假数据 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class DiscoverScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    private val server = FakeServer()
    private val me = TestSupport.USER_ID
    private val tomorrow = addingDays(startOfDay(System.currentTimeMillis()), 1)

    @After
    fun detach() = L10n.detach()

    private fun iso(millis: Long) = Instant.ofEpochMilli(millis).toString()

    private fun shot(name: String, appearance: Appearance = Appearance.Light, setup: (AppEnvironment) -> Unit = {}, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+b+zh+Hans")
        L10n.attach(RuntimeEnvironment.getApplication())
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile(""","preferred_mode":"singles","show_as_regular":true""")}]")
        runBlocking { backend.refreshProfile() }
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
        environment.locationManager.currentLocation = Coordinate.fallbackCenter
        setup(environment)
        // 页面里有一直转的动画和定时刷新：不自动走时间，走一段就拍
        compose.mainClock.autoAdvance = false
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        repeat(30) {
            compose.mainClock.advanceTimeBy(100)
            compose.waitForIdle()
        }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    private fun lobbyUser(id: String, name: String, rating: Double, color: String, mode: String, noShows: Int = 0) =
        """{"id":"$id","nickname":"$name","rating":$rating,"gender":"female","recent_no_shows":$noShows,"card_color":"$color","preferred_mode":"$mode",
            "usual_times":[{"weekday":7,"start":"14:00","end":"18:00"},{"weekday":3,"start":"19:00","end":"21:00"},{"weekday":1,"start":"09:00","end":"12:00"}]}"""

    private val nearbyPlayers = """[
        {"user":${lobbyUser("u1", "林小满", 4.33, "lime", "singles")},"venues":[{"id":"v1","name":"圣盖博羽毛球馆","km":3.2}],"shared_venues":1},
        {"user":${lobbyUser("u2", "Mia", 5.0, "sky", "doubles", noShows = 1)},"venues":[{"id":"v2","name":"Arcadia Badminton","km":5.8}]},
        {"user":${lobbyUser("u3", "阿杰", 3.67, "peach", "doubles")},"venues":[{"id":"v1","name":"圣盖博羽毛球馆","km":3.2}]}]"""

    private val ticketJSON: String
        get() {
            val start = tomorrow + 19 * 3_600_000L
            return """{"id":"t1","mode":"singles","starts_at":"${iso(start)}","ends_at":"${iso(start + 7_200_000)}","status":"offered","skill_tolerance":1,
             "auto_accept":false,"lock_at":"${iso(start - 7_200_000)}","venues":[{"id":"v1","name":"圣盖博羽毛球馆"}],
             "offer":{"id":"o1","starts_at":"${iso(start)}","ends_at":"${iso(start + 7_200_000)}","respond_by":"${iso(start - 9_000_000)}",
                      "my_response":"pending","venue":{"id":"v1","name":"圣盖博羽毛球馆","lat":34.1,"lon":-118.1,"street":"123 Main St","city":"San Gabriel","country":"US","pricing":{"per_person":12}},"accepted":1,
                      "players":[{"id":"$me","nickname":"Alex","rating":4.0,"team":1,"me":true},{"id":"u1","nickname":"林小满","rating":4.33,"team":2,"me":false}]}}"""
        }

    private fun ticket(env: AppEnvironment, status: MatchTicket.Status? = null): MatchTicket {
        val remote = RemoteJSON.decode<RemoteTicket>(ticketJSON.encodeToByteArray())
        val ticket = remote.ticket(me, Coordinate.fallbackCenter, 0)
        env.matchManager.remember(listOf(User(id = "u1", nickname = "林小满", phone = "", selfReportedLevel = 4, selfReportedRating = 4.33)))
        return if (status == null) ticket else ticket.copy(status = status)
    }

    @Test
    fun nearbyPeople() {
        server.on("POST /rest/v1/rpc/nearby_invites", "[]")
        server.on("POST /rest/v1/rpc/nearby_players", nearbyPlayers)
        shot("discover-nearby-zh") { DiscoverScreen() }
    }

    @Test
    fun nearbyPeopleDark() {
        server.on("POST /rest/v1/rpc/nearby_invites", "[]")
        server.on("POST /rest/v1/rpc/nearby_players", nearbyPlayers)
        shot("discover-nearby-dark", Appearance.Dark) { DiscoverScreen() }
    }

    @Test
    fun dayCards() {
        val start = tomorrow + 14 * 3_600_000L
        server.on("POST /rest/v1/rpc/nearby_invites", "[]")
        server.on(
            "POST /rest/v1/rpc/day_candidates",
            """[{"ticket":"t1","mode":"singles","mixed":false,"starts_at":"${iso(start)}","ends_at":"${iso(start + 3 * 3_600_000)}",
                 "user":${lobbyUser("u1", "林小满", 4.33, "lavender", "singles")},"venues":[{"id":"v1","name":"圣盖博羽毛球馆","km":3.2}]},
                {"ticket":"t2","mode":"doubles","mixed":true,"starts_at":"${iso(start + 3_600_000)}","ends_at":"${iso(start + 4 * 3_600_000)}",
                 "user":${lobbyUser("u2", "Mia", 5.0, "pink", "doubles", noShows = 1)},"venues":[{"id":"v2","name":"Arcadia Badminton","km":5.8}]}]""",
        )
        shot("discover-day-zh", setup = { it.matchManager.discoverDay = tomorrow }) { DiscoverScreen() }
    }

    @Test
    fun outOfCards() {
        server.on("POST /rest/v1/rpc/nearby_invites", "[]")
        server.on("POST /rest/v1/rpc/nearby_players", "[]")
        shot("discover-empty-zh") { DiscoverScreen() }
    }

    @Test
    fun nearbyGroups() {
        server.on("POST /rest/v1/rpc/nearby_invites", "[]")
        server.on(
            "POST /rest/v1/rpc/groups_near",
            """[{"id":"g1","name":"周四晚双打群","level_min":3,"level_max":5,"join_policy":"open","venue":{"id":"v1","name":"圣盖博羽毛球馆"},""" +
                """"venues":[{"id":"v1","name":"圣盖博羽毛球馆"},{"id":"v2","name":"Arcadia Badminton"}],""" +
                """"schedules":[{"weekday":4,"start":1170,"end":1320,"capacity":8},{"weekday":0,"start":600,"end":720,"capacity":12,"venue":"v2"}],""" +
                """"activity":{"sessions":8,"average":7.4},"distance_m":800},""" +
                """{"id":"g2","name":"周末早场","level_min":2,"level_max":4,"join_policy":"approval","gender":"female","venue":{"id":"v3","name":"LA Badminton Center"},""" +
                """"schedules":[{"weekday":6,"start":540,"end":720,"capacity":16}],"activity":{"sessions":0,"average":0},"my_role":"pending","distance_m":6400}]""",
        )
        shot("discover-groups-zh", setup = { DiscoverMode.Groups.save(RuntimeEnvironment.getApplication()) }) { DiscoverScreen() }
    }

    @Test
    fun needsLocation() {
        shot("discover-location-zh", setup = { it.locationManager.currentLocation = null }) { DiscoverScreen() }
    }

    @Test
    fun filter() = shot("discover-filter-zh") {
        DayCardFilterSheet(
            DayCardFilter(event = DayCardFilter.Event.Singles, venueIds = setOf("v1"), minLevel = 3),
            listOf(VenueCount(DayCandidate.Place("v1", "圣盖博羽毛球馆"), 3), VenueCount(DayCandidate.Place("v2", "Arcadia Badminton"), 1)),
            count = { 3 }, day = null, onApply = {}, onDay = {},
        )
    }

    @Test
    fun inviteCompose() {
        server.on("POST /rest/v1/rpc/suggest_invite_window", "null")
        shot("discover-invite-zh", setup = {
            it.matchManager.remember(listOf(User(id = "u1", nickname = "林小满", phone = "", selfReportedLevel = 4)))
        }) {
            InviteComposeContent(
                "u1", null, listOf(RecurringTimeSlot.create(dayOfWeek = 7, startHour = 14, endHour = 18)),
                listOf(DayCandidate.Place("v1", "圣盖博羽毛球馆", 3.2)), prefill = null, initialMode = GameMode.Singles, onDismiss = {},
            ) { _, _ -> }
        }
    }

    @Test
    fun inviteAnswer() {
        val start = tomorrow + 22 * 3_600_000L
        server.on(
            "POST /rest/v1/rpc/nearby_invites",
            """[{"id":"r1","mode":"singles","visibility":"private","status":"open","level_min":1,"level_max":9,"going":1,"waitlist":0,
                "owner":{"id":"u1","nickname":"林小满","rating":4.33},"venue":{"id":"v1","name":"圣盖博羽毛球馆","lat":34.1,"lon":-118.1,"country":"US"},
                "time_set":false,"window_start":"${iso(start)}","window_end":"${iso(start + 4 * 3_600_000)}","duration_minutes":120,"daypart":"afternoon",
                "invite":{"from":${lobbyUser("u1", "林小满", 4.33, "lime", "singles")},"to":{"id":"$me","nickname":"Alex","rating":4.0},"awaiting_id":"$me","rounds":0,
                          "answer_by":"${iso(start)}"}}]""",
        )
        shot("discover-answer-zh", setup = { runBlocking { it.matchManager.loadInvites() } }) {
            InviteAnswerSheet(LocalEnv.current.matchManager.invites, { _, _ -> }, {}, {})
        }
    }

    @Test
    fun matchSetup() = shot("match-setup-zh", setup = {
        it.matchManager.draft = MatchDraft(day = tomorrow, courtIds = emptyList(), skillTolerance = 1)
    }) { MatchSetupContent({}, {}, {}) }

    @Test
    fun searching() = shot("match-searching-zh") { SearchingView() }

    @Test
    fun offer() = shot("match-offer-zh") {
        val env = LocalEnv.current
        val ticket = ticket(env)
        val remote = RemoteJSON.decode<RemoteTicket>(ticketJSON.encodeToByteArray())
        OfferView(ticket, remote.offer!!.offer(GameMode.Singles, false, remote.offer.venue.venue(), 0))
    }

    @Test
    fun waiting() = shot("match-waiting-zh") {
        val ticket = ticket(LocalEnv.current, MatchTicket.Status.Searching)
        TicketWaitingView(ticket)
    }

    @Test
    fun ended() = shot("match-ended-zh") { TicketEndedView(ticket(LocalEnv.current, MatchTicket.Status.Expired)) }

    @Test
    fun ticketCard() = shot("match-ticket-card-zh") {
        TicketStatusCard(ticket(LocalEnv.current, MatchTicket.Status.Paused), null, Modifier) {}
    }
}
