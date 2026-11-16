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
import com.badie.app.features.venues.AddVenueScreen
import com.badie.app.features.venues.CourtsScreen
import com.badie.app.features.venues.MatchVenuesScreen
import com.badie.app.features.venues.TravelRadiusSheet
import com.badie.app.features.venues.VenuePickerMode
import com.badie.app.features.venues.VenuePickerView
import com.badie.app.features.venues.VenueScreen
import com.badie.app.l10n.L10n
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

/** 球馆这一块的界面图（附近球馆、球馆页、选球馆、搜索、添加、附近范围），放在 app/build/outputs/roborazzi */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class VenuesScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @After
    fun detach() = L10n.detach()

    private val server = FakeServer()

    private fun row(
        id: String, name: String, east: Double, north: Double, street: String, city: String,
        status: String = "verified", extra: String = "", aliases: String = "[]",
    ): String {
        val lat = 34.0686 + north / 110.574
        val lon = -118.0276 + east / 92.2
        return """{"id":"$id","name":"$name","aliases":$aliases,"lat":$lat,"lon":$lon,"street":"$street","city":"$city","region":"CA",""" +
            """"postal_code":"91731","country_code":"US","status":"$status","source":"player","created_at":"2026-10-17T23:17:25+00:00"$extra}"""
    }

    private val labc = row(
        "v-labc", "Los Angeles Badminton Club", 1.2, 0.8, "10410 Valley Blvd", "El Monte",
        aliases = """["LABC","洛杉矶羽毛球俱乐部"]""",
        extra = ""","court_count":16,"pricing":{"perPerson":15},"pricing_note":"散客 $15/人次 · 包场 $38/场·时",""" +
            """"phone":"+1 626 555 0123","website":"https://www.example.com/book","entrance_note":"从后门进，停车场在侧面","time_zone_id":"America/Los_Angeles"""",
    )
    private val elite = row("v-elite", "Elite Rally Badminton Club", -4.5, 2.0, "4800 Rivergrade Rd", "Baldwin Park", extra = ""","court_count":12""")
    private val arena = row("v-arena", "Arena Badminton", 6.0, -3.0, "1500 S Grand Ave", "Covina", status = "confirmed", extra = ""","court_count":8""")
    private val pending = row("v-new", "Rally Point Community Center", 2.0, -1.0, "321 Main St", "Rosemead", status = "unconfirmed")

    private fun nearby(vararg rows: String) =
        server.on("POST /rest/v1/rpc/venues_near", rows.joinToString(",", "[", "]") { """{"venue":$it,"distance_m":100}""" })

    /** 登录过、常去 LABC；附近有 4 家 */
    private fun environment(favorites: String = """[{"venue_id":"v-labc"}]""", courts: List<String> = listOf(labc, elite, arena, pending)): AppEnvironment {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.on("GET /rest/v1/profiles", "[${TestSupport.profile()}]")
        server.on("GET /rest/v1/favorite_venues", favorites)
        nearby(*courts.toTypedArray())
        server.on(
            "GET /rest/v1/venue_regular_counts",
            """[{"venue_id":"v-labc","regulars":23},{"venue_id":"v-elite","regulars":9},{"venue_id":"v-arena","regulars":4}]""",
        )
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
        runBlocking {
            backend.refreshProfile()
            environment.locationManager.start()
        }
        return environment
    }

    private fun shot(
        name: String, environment: AppEnvironment, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light,
        content: @Composable () -> Unit,
    ) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        // 搜索要等 0.15 秒
        compose.mainClock.advanceTimeBy(1_000)
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    @Test
    fun courts() = shot("venues-1-courts", environment()) { CourtsScreen() }

    @Test
    fun courtsEmpty() = shot("venues-1-courts-empty", environment(favorites = "[]", courts = emptyList())) { CourtsScreen() }

    private fun detailEnvironment(): AppEnvironment {
        val environment = environment()
        server.on("GET /rest/v1/venue_regular_counts", """[{"venue_id":"v-labc","regulars":23}]""")
        server.on(
            "POST /rest/v1/rpc/venue_people",
            """{"recent":[{"id":"u-1","nickname":"欣然","rating":4.33},{"id":"u-2","nickname":"阿杰","rating":3.67},{"id":"u-3","nickname":"Mia","rating":5.0}],""" +
                """"regulars":[{"id":"u-4","nickname":"小林","rating":4.0},{"id":"u-1","nickname":"欣然","rating":4.33}]}""",
        )
        environment.matchManager.draftVenueIds.add("v-labc")
        return environment
    }

    @Test
    fun venueDetail() = shot("venues-2-detail", detailEnvironment(), qualifiers = "b+zh+Hans-h2000dp") { VenueScreen("v-labc") }

    @Test
    fun venueDetailEnglishDark() = shot("venues-2-detail-en-dark", detailEnvironment(), qualifiers = "en-h2000dp", appearance = Appearance.Dark) {
        VenueScreen("v-labc")
    }

    @Test
    fun pendingVenueDetail() = shot("venues-2-detail-pending", environment(), qualifiers = "b+zh+Hans-h1400dp") { VenueScreen("v-new") }

    @Test
    fun matchVenues() = shot("venues-3-match", environment().also { it.matchManager.draftVenueIds.add("v-elite") }) { MatchVenuesScreen(null) }

    @Test
    fun search() {
        val environment = environment()
        server.on("GET /rest/v1/venues", "[$labc]")
        server.on("GET /rest/v1/venue_regular_counts", "[]")
        shot("venues-4-search", environment) {
            VenuePickerView(VenuePickerMode.Browse, emptyList(), {}, {}, Modifier.fillMaxSize(), initialQuery = "labc")
        }
    }

    @Test
    fun searchNothingFound() {
        val environment = environment()
        server.on("GET /rest/v1/venues", "[]")
        shot("venues-4-search-empty", environment) {
            VenuePickerView(VenuePickerMode.Single, emptyList(), {}, {}, Modifier.fillMaxSize(), initialQuery = "pickleball")
        }
    }

    @Test
    fun addVenue() = shot("venues-5-add", environment(), qualifiers = "b+zh+Hans-h1100dp") { AddVenueScreen() }

    @Test
    fun travelRadius() = shot("venues-6-radius", environment()) { TravelRadiusSheet {} }

    @Test
    fun travelRadiusJapanese() = shot("venues-6-radius-ja", environment(), qualifiers = "ja") { TravelRadiusSheet {} }
}
