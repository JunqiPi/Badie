package com.badie.app.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.badie.app.backend.Backend
import com.badie.app.backend.CacheStore
import com.badie.app.backend.CachedState
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.features.profile.EditProfileView
import com.badie.app.features.profile.HelpSheet
import com.badie.app.features.profile.LevelCardData
import com.badie.app.features.profile.LevelCardFace
import com.badie.app.features.profile.LevelCardLabel
import com.badie.app.features.profile.LevelCardRenderer
import com.badie.app.features.profile.LevelCardSheetContent
import com.badie.app.features.profile.LevelGuideScreen
import com.badie.app.features.profile.MyCardPreviewContent
import com.badie.app.features.profile.PasswordSheet
import com.badie.app.features.profile.ProfileScreen
import com.badie.app.features.profile.RecurringSlotEditor
import com.badie.app.features.profile.RecurringSlotsView
import com.badie.app.features.profile.ReassessSheet
import com.badie.app.features.profile.SettingsView
import com.badie.app.features.profile.TipJarSheet
import com.badie.app.features.venues.TravelRadiusSheet
import com.badie.app.features.profile.VerificationView
import com.badie.app.l10n.L10n
import com.badie.app.models.AttendanceRecord
import com.badie.app.models.CardColor
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillAssessmentSummary
import com.badie.app.models.User
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteSession
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

/** “我的”、编辑资料、设置、等级卡片这些页面的截图（app/build/outputs/roborazzi/profile-*.png），用来和 iPhone 对照 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class ProfileScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    @After
    fun detach() = L10n.detach()

    private val me: User = User(
        id = "6f1c2c3e-0000-4000-8000-000000000001", nickname = "阿杰", phone = "alex@example.com", selfReportedLevel = 4,
        gender = Gender.Male, tag = 3400, preferredMode = GameMode.Doubles, totalGames = 12, friendCode = "k7Qm2x",
        attendance = AttendanceRecord(12, 0, 1), selfReportedRating = 4.33,
        assessment = SkillAssessmentSummary(4, false, false, assessedAt = 1_700_000_000_000, rating = 4.33, answers = SkillAssessment.levelCardDemoAnswers),
    ).let { it.copy(avatar = it.avatar.copy(cardColor = CardColor.Sky)) }

    /** 登录了的后端：用户在本机缓存里，服务器的请求都回 404（页面照样能显示） */
    private fun environment(user: User): AppEnvironment {
        val session = RemoteSession("t", "r", Long.MAX_VALUE / 2, user.id, "alex@example.com")
        val cached = Json.encodeToString(CachedState.serializer(), CachedState(user, listOf("v1")))
        val backend = Backend(
            SupabaseClient(SessionStorage({ session }, {}), FakeServer().transport), CacheStore({ cached }, {}),
            deviceCountry = { "US" }, serverLocale = { "zh-Hans" },
        )
        val api = ProfileApi.of(backend, RuntimeEnvironment.getApplication())
        api.saveRecurringSlots(
            listOf(
                RecurringTimeSlot.create(4, 19, endHour = 21, id = "a"),
                RecurringTimeSlot.create(7, 14, endHour = 17, id = "b"),
                RecurringTimeSlot.create(1, 9, endHour = 11, isActive = false, id = "c"),
            ),
        )
        return AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
    }

    private fun shot(
        name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, user: User? = me,
        wait: (() -> Boolean)? = null, content: @Composable () -> Unit,
    ) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        val environment = if (user != null) environment(user) else AppEnvironment(CoroutineScope(Dispatchers.Unconfined), com.badie.app.TestSupport.backend())
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        if (wait != null) compose.waitUntil(10_000, wait)
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/profile-$name.png")
    }

    @Test
    fun profile() = shot("1-me", qualifiers = "b+zh+Hans-h1700dp") { ProfileScreen() }

    @Test
    fun profileEnglishDark() = shot("1-me-en-dark", qualifiers = "en", appearance = Appearance.Dark) { ProfileScreen() }

    @Test
    fun profileNotAssessed() = shot("1-me-new", user = me.copy(assessment = null, assessmentSkippedAt = 1L, preferredMode = null, totalGames = 0)) {
        ProfileScreen()
    }

    @Test
    fun editProfile() = shot("2-edit", qualifiers = "b+zh+Hans-h1900dp") { EditProfileView() }

    @Test
    fun editProfileEnglish() = shot("2-edit-en", qualifiers = "en") { EditProfileView() }

    @Test
    fun myCardPreview() = shot("2-edit-preview") {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            MyCardPreviewContent(me, listOf(RecurringTimeSlot.create(4, 19, endHour = 21), RecurringTimeSlot.create(7, 14, endHour = 17), RecurringTimeSlot.create(1, 9, endHour = 11)),
                com.badie.app.backend.VenueName("v1", "LA Badminton Club", "Los Angeles"), 0, Modifier.weight(1f))
        }
    }

    @Test
    fun settings() = shot("3-settings", qualifiers = "b+zh+Hans-h2300dp") { SettingsView() }

    @Test
    fun settingsDark() = shot("3-settings-dark", appearance = Appearance.Dark) { SettingsView() }

    @Test
    fun recurringSlots() = shot("4-recurring") { RecurringSlotsView() }

    @Test
    fun recurringSlotEditor() = shot("4-recurring-editor") { RecurringSlotEditor({}, {}) }

    @Test
    fun levelGuide() = shot("5-level-guide") { LevelGuideScreen() }

    @Test
    fun reassess() = shot("5-reassess") { ReassessSheet {} }

    @Test
    fun verification() = shot("6-verification", qualifiers = "b+zh+Hans-h1200dp") { VerificationView() }

    @Test
    fun help() = shot("7-help") { HelpSheet(ProfileApi.of(LocalEnv.current.appState.backend, null)) {} }

    @Test
    fun tipJarAndPassword() = shot("7-tips-password") {
        val api = ProfileApi.of(LocalEnv.current.appState.backend, null)
        Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
            TipJarSheet {}
            PasswordSheet(api) {}
            TravelRadiusSheet {}
        }
    }

    @Test
    fun levelCardFaces() = shot("8-level-card-faces", qualifiers = "b+zh+Hans-h1000dp") {
        val context = androidx.compose.ui.platform.LocalContext.current
        val result = SkillAssessment.evaluate(SkillAssessment.levelCardDemoAnswers)!!
        val data = LevelCardData(
            result.tier, LevelCardLabel.SelfRated, name = "阿杰#3400", region = "Los Angeles", play = result.play, gap = result.nextGap,
            mode = GameMode.Doubles, venue = "LA Badminton Club", times = "周三晚上 · 周末下午",
        )
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (face in LevelCardFace.entries) {
                Image(LevelCardRenderer.render(context, data, face), null, Modifier.fillMaxWidth())
            }
        }
    }

    @Test
    fun levelCardPlain() = shot("8-level-card-plain", qualifiers = "en") {
        val context = androidx.compose.ui.platform.LocalContext.current
        val data = LevelCardData(com.badie.app.models.SkillTier(7), LevelCardLabel.Verified)
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (face in LevelCardFace.entries) Image(LevelCardRenderer.render(context, data, face), null, Modifier.fillMaxWidth(0.7f))
        }
    }

    @Test
    fun levelCardSheet() = shot(
        "8-level-card-sheet",
        // 两面在后台画好以后“分享”才能按
        wait = { compose.onAllNodes(hasText("分享") and isEnabled() and hasClickAction()).fetchSemanticsNodes().isNotEmpty() },
    ) {
        val result = SkillAssessment.evaluate(SkillAssessment.levelCardDemoAnswers)!!
        LevelCardSheetContent(LevelCardData(result.tier, LevelCardLabel.SelfRated, name = "阿杰#3400", play = result.play)) {}
    }
}
