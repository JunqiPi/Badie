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
import com.badie.app.features.groups.CreateGroupScreen
import com.badie.app.features.groups.GroupScreen
import com.badie.app.features.groups.SessionSheet
import com.badie.app.l10n.L10n
import com.badie.app.remote.FakeServer
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

/** 访客报名：编辑球群里的“访客报名”、球群页的“复制报名链接”、场次名单里的访客、同名和临时退出。对应 iPhone 1.0.7 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class GuestSignupScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    private val me = TestSupport.session().userId
    private fun iso(offset: Long) = Instant.ofEpochMilli(System.currentTimeMillis() + offset).toString()

    private val venue = """{"id":"v-1","name":"LA Badminton Club","city":"El Monte","tz":"America/Los_Angeles"}"""

    /** 群主是我；开了访客报名。名单里两个访客，其中一个和成员同名；有一个访客临时退出 */
    private fun groupPage(guests: String = """"guests_allowed":true,"guest_limit":null,"guest_code":"7fQk2Rx9"""") =
        """{"id":"grp1","name":"周三晚双打","summary":"","level_min":3,"level_max":6,"join_policy":"open","venue":$venue,""" +
            """"schedules":[{"weekday":3,"start":1140,"end":1320,"capacity":12}],""" +
            """"activity":{"sessions":6,"average":10},"my_role":"owner","invite_code":"482913",$guests,""" +
            """"sessions":[{"id":"s1","starts_at":"${iso(50 * 3_600_000L)}","ends_at":"${iso(53 * 3_600_000L)}","capacity":12,"cancelled":false,"confirmed":5,"waitlist":1,"my_status":"confirmed",""" +
            """"late_cancels":[{"nickname":"Sam","guest":true},{"nickname":"Raj","guest":false}],""" +
            """"players":[{"id":"$me","nickname":"Alex","waitlisted":false},{"id":"u-2","nickname":"Kai","waitlisted":false},""" +
            """{"id":"g-1","nickname":"Tina","waitlisted":false,"guest":true,"signed_up_at":"${iso(-86_400_000L)}"},""" +
            """{"id":"u-3","nickname":"Mei","waitlisted":false},{"id":"g-2","nickname":"kai","waitlisted":false,"guest":true,"signed_up_at":"${iso(-3_600_000L)}"},""" +
            """{"id":"g-3","nickname":"Tony","waitlisted":true,"guest":true,"signed_up_at":"${iso(-1_800_000L)}"}]}],""" +
            """"members":[{"id":"$me","nickname":"Alex","rating":4,"role":"owner"},{"id":"u-2","nickname":"Kai","rating":4.33,"role":"member"},""" +
            """{"id":"u-3","nickname":"Mei","rating":3.67,"role":"member"}],"pending":[]}"""

    private fun environment(setup: FakeServer.() -> Unit): AppEnvironment {
        val server = FakeServer()
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
        runBlocking { backend.refreshProfile() }
        server.setup()
        return environment
    }

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", setup: FakeServer.() -> Unit, prepare: suspend AppEnvironment.() -> Unit = {}, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
        val environment = environment(setup)
        runBlocking { environment.prepare() }
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(Appearance.Light) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        compose.waitForIdle()
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    private val page: FakeServer.() -> Unit = {
        on("POST /rest/v1/rpc/group_page", groupPage())
        on("POST /rest/v1/rpc/my_dues", "[]")
    }

    @Test
    fun editGroupGuests() = shot("guests-edit-group", qualifiers = "b+zh+Hans-h1900dp", setup = page, prepare = { groupManager.loadGroup("grp1") }) {
        CreateGroupScreen(venueId = null, editingGroupId = "grp1")
    }

    /** 第一次打开、还没保存：还没有链接 */
    @Test
    fun editGroupGuestsBeforeSave() = shot("guests-edit-group-off", qualifiers = "b+zh+Hans-h1900dp", setup = {
        on("POST /rest/v1/rpc/group_page", groupPage(""""guests_allowed":false,"guest_limit":null,"guest_code":null"""))
    }, prepare = { groupManager.loadGroup("grp1") }) { CreateGroupScreen(venueId = null, editingGroupId = "grp1") }

    @Test
    fun groupCopyLink() = shot("guests-group", qualifiers = "b+zh+Hans-h1300dp", setup = page, prepare = { groupManager.loadGroup("grp1") }) { GroupScreen("grp1") }

    @Test
    fun rosterWithGuests() = shot("guests-roster", setup = page, prepare = { groupManager.loadGroup("grp1") }) { SessionSheet("s1") {} }

    @Test
    fun rosterWithGuestsEnglish() = shot("guests-roster-en", qualifiers = "en", setup = page, prepare = { groupManager.loadGroup("grp1") }) { SessionSheet("s1") {} }
}
