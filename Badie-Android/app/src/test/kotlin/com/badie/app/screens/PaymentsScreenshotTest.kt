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
import com.badie.app.features.groups.GroupLedgerScreen
import com.badie.app.features.groups.GroupScreen
import com.badie.app.features.groups.PaymentHandlesScreen
import com.badie.app.features.groups.SessionPaymentsScreen
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

/** 收款：球群页（价格、你还没付、组织者的“收款”）、编辑球群的价格、收款记录、某一场的收款、收款方式。对应 iPhone 1.0.8 的设计稿 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class PaymentsScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    private val me = TestSupport.session().userId
    private fun iso(offset: Long) = Instant.ofEpochMilli(System.currentTimeMillis() + offset).toString()

    private val venue = """{"id":"v-1","name":"LA Badminton Club","city":"El Monte","tz":"America/Los_Angeles"}"""

    /** 群主是我（组织者），两个每周场次，价格不一样 */
    private val groupPage
        get() = """{"id":"grp1","name":"周三晚双打","summary":"","level_min":3,"level_max":6,"join_policy":"open","venue":$venue,""" +
            """"schedules":[{"weekday":3,"start":1140,"end":1320,"capacity":20,"fee":"含球","price":12},{"weekday":6,"start":840,"end":1020,"capacity":16,"price":15}],""" +
            """"activity":{"sessions":6,"average":14},"my_role":"owner","invite_code":"482913",""" +
            """"sessions":[{"id":"s1","starts_at":"${iso(50 * 3_600_000L)}","ends_at":"${iso(53 * 3_600_000L)}","capacity":20,"cancelled":false,"confirmed":12,"waitlist":0,"my_status":"confirmed","price":12,"players":[{"id":"$me","nickname":"Alex","waitlisted":false}]}],""" +
            """"members":[{"id":"$me","nickname":"Alex","rating":4,"role":"owner"},{"id":"u-2","nickname":"Kai","rating":4.33,"role":"member"}],"pending":[]}"""

    private val dues
        get() = """[{"session_id":"p1","group_id":"grp1","group":"周三晚双打","starts_at":"${iso(-5 * 86_400_000L)}","ends_at":"${iso(-5 * 86_400_000L + 10_800_000L)}","tz":"America/Los_Angeles","amount":12,"to":"Kevin","to_id":"u-9","handles":{"venmo":"kevin-w","zelle":"kevin@example.com"}},""" +
            """{"session_id":"p2","group_id":"grp1","group":"周三晚双打","starts_at":"${iso(-2 * 86_400_000L)}","ends_at":"${iso(-2 * 86_400_000L + 10_800_000L)}","tz":"America/Los_Angeles","amount":15,"to":"Kevin","to_id":"u-9","handles":{"venmo":"kevin-w"}}]"""

    private val ledger
        get() = """{"sessions":[""" +
            """{"id":"p2","starts_at":"${iso(-2 * 86_400_000L)}","ends_at":"${iso(-2 * 86_400_000L + 10_800_000L)}","venue":"LA Badminton Club","tz":"America/Los_Angeles","amount":15,"payee":"Alex","owes":16,"paid":13},""" +
            """{"id":"p1","starts_at":"${iso(-5 * 86_400_000L)}","ends_at":"${iso(-5 * 86_400_000L + 10_800_000L)}","venue":"LA Badminton Club","tz":"America/Los_Angeles","amount":12,"payee":"Alex","owes":20,"paid":20},""" +
            """{"id":"p0","starts_at":"${iso(-12 * 86_400_000L)}","ends_at":"${iso(-12 * 86_400_000L + 10_800_000L)}","venue":"LA Badminton Club","tz":"America/Los_Angeles","amount":null,"payee":"Alex","owes":18,"paid":0}],""" +
            """"owed":[{"id":"u-3","name":"Raj","guest":false,"sessions":2,"amount":27,"signups":["a","b"]},{"id":null,"name":"Tony","guest":true,"sessions":1,"amount":15,"signups":["c"]}]}"""

    private val nightState
        get() = """{"session_id":"p2","group_id":"grp1","group":"周三晚双打","venue":"LA Badminton Club","tz":"America/Los_Angeles","starts_at":"${iso(-2 * 86_400_000L)}","ends_at":"${iso(-2 * 86_400_000L + 10_800_000L)}","role":"organizer","open":false,"started":false,"courts":2,"doubles":true,"balance":false,"helpers":[],"people":[],"games":[],"next":[]}"""

    private val nightPay =
        """{"amount":15,"amount_set":true,"payee":"Alex","payee_is_me":true,"has_handles":true,"reminded_at":null,"can_remind":true,"people":[""" +
            """{"id":"a","name":"Raj","guest":false,"status":"here","owes":true,"paid":false},{"id":"c","name":"Tony","guest":true,"email":false,"status":"here","owes":true,"paid":false},""" +
            """{"id":"d","name":"Mei","guest":false,"status":"here","owes":true,"paid":true,"paid_self":true},{"id":"e","name":"Kai","guest":false,"status":"absent","owes":false,"paid":false}]}"""

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

    @Test
    fun groupWithDues() = shot("payments-group", qualifiers = "b+zh+Hans-h1300dp", setup = {
        on("POST /rest/v1/rpc/group_page", groupPage)
        on("POST /rest/v1/rpc/my_dues", dues)
    }, prepare = { groupManager.loadGroup("grp1") }) { GroupScreen("grp1") }

    @Test
    fun editGroupPrice() = shot("payments-edit-group", qualifiers = "b+zh+Hans-h2000dp", setup = {
        on("POST /rest/v1/rpc/group_page", groupPage)
    }, prepare = { groupManager.loadGroup("grp1") }) { CreateGroupScreen(venueId = null, editingGroupId = "grp1") }

    @Test
    fun ledger() = shot("payments-ledger", setup = { on("POST /rest/v1/rpc/group_ledger", ledger) }) { GroupLedgerScreen("grp1") }

    @Test
    fun ledgerEnglish() = shot("payments-ledger-en", qualifiers = "en", setup = { on("POST /rest/v1/rpc/group_ledger", ledger) }) { GroupLedgerScreen("grp1") }

    @Test
    fun sessionPayments() = shot("payments-session", setup = {
        on("POST /rest/v1/rpc/night_state", nightState)
        on("POST /rest/v1/rpc/night_pay", nightPay)
    }) { SessionPaymentsScreen("p2") }

    @Test
    fun paymentHandles() = shot("payments-handles", setup = {
        on("POST /rest/v1/rpc/my_payment_handles", """{"venmo":"alex-w","zelle":"alex@example.com"}""")
    }) { PaymentHandlesScreen() }
}
