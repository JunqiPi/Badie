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
import com.badie.app.backend.Backend
import com.badie.app.backend.CachedState
import com.badie.app.backend.CacheStore
import com.badie.app.backend.RankingsApi
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.features.rankings.ChallengeComposer
import com.badie.app.features.rankings.ChallengeComposerSheet
import com.badie.app.models.GameMode
import com.badie.app.features.rankings.ChallengesScreen
import com.badie.app.features.rankings.LeaderboardScreen
import com.badie.app.features.rankings.RankingManager
import com.badie.app.l10n.L10n
import com.badie.app.models.Challenge
import com.badie.app.models.ChallengeStatus
import com.badie.app.models.Gender
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenuePricing
import com.badie.app.remote.FakeServer
import com.badie.app.remote.SessionStorage
import com.badie.app.remote.SupabaseClient
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.LocalEnv
import com.github.takahirom.roborazzi.captureRoboImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** 排行榜、场馆月榜、挑战列表、发起挑战。数据是假的，服务器的请求都回 404（界面保留已有的数据） */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class RankingsScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @After
    fun detach() = L10n.detach()

    private val now = System.currentTimeMillis()
    private val me = User.create(TestSupport.USER_ID, "Alex", selfReportedLevel = 4)
        .copy(gender = Gender.Male, selfReportedRating = 4.0, joinDate = now - 60 * 86_400_000L)
    private val labc = Venue("v-labc", "LA Badminton Center", lat = 34.07, lon = -118.03, city = "El Monte", region = "CA", countryCode = "US", pricing = VenuePricing.DropIn(15))
    private val orange = Venue("v-oc", "Orange County Badminton Club", lat = 33.7, lon = -117.8, city = "Tustin", region = "CA", countryCode = "US", pricing = VenuePricing.DropIn(16))

    private fun backend(): Backend {
        val cached = Json.encodeToString(CachedState.serializer(), CachedState(me, listOf(labc.id, orange.id)))
        return Backend(
            SupabaseClient(SessionStorage({ TestSupport.session() }, {}), FakeServer().transport, now = { now }),
            CacheStore({ cached }, {}), deviceCountry = { "US" }, serverLocale = { "zh-Hans" },
        )
    }

    private fun entry(id: String, name: String, rating: Double, rank: Int, points: Int?, games: Int, wins: Int) =
        RankingsApi.BoardEntry(id, name, rating, rank, points, games, wins)

    private fun shot(
        name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, setUp: (RankingManager) -> Unit,
        friends: List<Pair<String, String>> = emptyList(), content: @Composable () -> Unit,
    ) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        val backend = backend()
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
        val manager = RankingManager.of(backend)
        manager.preload(challenges = emptyList(), people = emptyList(), places = listOf(labc, orange))
        setUp(manager)
        // 球友在 FriendManager 里（挑战带搭档时选）
        environment.friendManager.cache.syncAccount()
        friends.forEach { (id, name) -> environment.friendManager.cache.cache(id, name, 4.0) }
        environment.friendManager.cache.friendIds = friends.map { it.first }
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    private val weekly = RankingsApi.WeeklyBoard(
        entries = listOf(
            entry("u1", "林小羽", 6.0, 1, 186, 12, 10),
            entry("u2", "Kevin", 5.33, 2, 171, 11, 8),
            entry("u3", "欣然", 4.67, 3, 150, 10, 7),
            entry(TestSupport.USER_ID, "Alex", 4.0, 4, 132, 9, 5),
            entry("u5", "Mia Chen", 4.33, 5, 118, 8, 4),
            entry("u6", "阿杰", 3.67, 5, 118, 8, 4),
            entry("u7", "Daniel", 3.33, 7, 96, 7, 3),
        ),
        me = RankingsApi.WeeklyBoard.Mine(4, 132),
    )

    private fun boards(manager: RankingManager) = manager.preload(weekly = mapOf("global-0-male" to weekly))

    @Test
    fun weeklyBoard() = shot("rankings-weekly", setUp = ::boards) { LeaderboardScreen() }

    @Test
    fun weeklyBoardEnglishDark() = shot("rankings-weekly-en-dark", qualifiers = "en", appearance = Appearance.Dark, setUp = ::boards) { LeaderboardScreen() }

    @Test
    fun weeklyBoardLoading() = shot("rankings-weekly-loading", setUp = {}) { LeaderboardScreen() }

    @Test
    fun venueBoard() = shot("rankings-venue", setUp = { manager ->
        manager.preload(
            venue = mapOf(
                "v-labc-0-male" to RankingsApi.VenueBoard(
                    listOf(
                        RankingsApi.VenueBoard.Band(2, listOf(entry("u3", "欣然", 4.0, 1, null, 9, 6), entry(TestSupport.USER_ID, "Alex", 4.0, 2, null, 7, 4), entry("u6", "阿杰", 3.67, 3, null, 5, 2))),
                        RankingsApi.VenueBoard.Band(3, listOf(entry("u1", "林小羽", 5.33, 1, null, 11, 9), entry("u2", "Kevin", 5.0, 2, null, 6, 3))),
                    ),
                ),
            ),
        )
    }) { LeaderboardScreen(labc.id) }

    private fun challenges(manager: RankingManager) {
        val rival = User.create("u2", "Kevin", selfReportedLevel = 5).copy(selfReportedRating = 5.0)
        val partner = User.create("u8", "Casey", selfReportedLevel = 4)
        val other = User.create("u3", "欣然", selfReportedLevel = 4)
        val tomorrow = TimeSlot.on(now + 86_400_000L, startHour = 19, endHour = 21)!!
        val later = TimeSlot.on(now + 3 * 86_400_000L, startHour = 10, endHour = 12)!!
        manager.preload(
            challenges = listOf(
                Challenge("c1", "u2", me.id, labc, tomorrow, "打三局两胜？", now - 5 * 3_600_000L, ChallengeStatus.Pending),
                Challenge("c2", "u3", me.id, orange, later, "", now - 3_600_000L, ChallengeStatus.Pending, challengerPartnerId = "u8"),
                Challenge("c3", me.id, "u2", labc, later, "Rematch?", now - 2 * 3_600_000L, ChallengeStatus.Pending),
                Challenge("c4", me.id, "u3", orange, tomorrow, "", now - 30 * 3_600_000L, ChallengeStatus.Accepted, gameId = "g1"),
                Challenge("c5", me.id, "u8", labc, tomorrow, "", now - 50 * 3_600_000L, ChallengeStatus.Expired),
            ),
            people = listOf(rival, partner, other),
        )
    }

    @Test
    fun challengeList() = shot("rankings-challenges", qualifiers = "b+zh+Hans-h1400dp", setUp = ::challenges) { ChallengesScreen() }

    @Test
    fun challengesEmpty() = shot("rankings-challenges-empty", setUp = {}) { ChallengesScreen() }

    @Test
    fun composer() = shot("rankings-composer", setUp = { manager ->
        manager.preload(challenges = emptyList(), people = listOf(User.create("u2", "Kevin", selfReportedLevel = 5)))
    }) { ChallengeComposerSheet("u2") {} }

    @Test
    fun composerDoublesJapanese() = shot("rankings-composer-ja", qualifiers = "ja", setUp = { manager ->
        manager.preload(challenges = emptyList(), people = listOf(User.create("u2", "Kevin", selfReportedLevel = 5)))
    }, friends = listOf("u8" to "Casey", "u9" to "美玲")) { ChallengeComposer("u2", {}, initialMode = GameMode.Doubles) }
}
