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
import com.badie.app.backend.Backend
import com.badie.app.backend.CacheStore
import com.badie.app.backend.PhotoStore
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.features.groups.CreateGroupScreen
import com.badie.app.features.groups.GroupScreen
import com.badie.app.features.groups.GroupsScreen
import com.badie.app.features.messages.ChatScreen
import com.badie.app.features.messages.GroupChatScreen
import com.badie.app.features.messages.MessagesScreen
import com.badie.app.features.messages.NotificationsScreen
import com.badie.app.features.messages.UrgentNoticeSheet
import com.badie.app.features.social.AddFriendScreen
import com.badie.app.features.social.BlockedUsersScreen
import com.badie.app.features.social.FriendLinkSheet
import com.badie.app.features.social.FriendsScreen
import com.badie.app.features.social.PlayerProfileSheet
import com.badie.app.features.social.ReportSheet
import com.badie.app.features.social.StrikesSheet
import com.badie.app.l10n.L10n
import com.badie.app.models.Coordinate
import com.badie.app.models.InboxItem
import com.badie.app.remote.FakeServer
import com.badie.app.remote.SessionStorage
import com.badie.app.remote.SupabaseClient
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.LocalEnv
import com.github.takahirom.roborazzi.captureRoboImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant

/** 球友、消息、通知、球群的界面截图（假数据），和 iPhone 的截图对照。出图在 app/build/outputs/roborazzi */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class SocialScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    private val server = FakeServer()
    private val me = TestSupport.USER_ID
    private val blake = "6f1c2c3e-0000-4000-8000-000000000002"
    private val casey = "6f1c2c3e-0000-4000-8000-000000000003"
    private val dana = "6f1c2c3e-0000-4000-8000-000000000004"

    @After
    fun detach() = L10n.detach()

    private fun ago(minutes: Long): String = Instant.now().minusSeconds(minutes * 60).toString()

    private fun inDays(days: Long, hour: Long = 0): String = Instant.now().plusSeconds(days * 86_400 + hour * 3_600).toString()

    /** 登录好的环境：照片的后台工作永远不跑，界面里的后台工作当场跑完 */
    private fun environment(): AppEnvironment {
        val remote = SupabaseClient(SessionStorage({ TestSupport.session() }, {}), server.transport, now = { TestSupport.CLOCK })
        val backend = Backend(
            remote, CacheStore.memory, now = { TestSupport.CLOCK }, deviceCountry = { "US" }, serverLocale = { "zh-Hans" },
            photos = PhotoStore(remote, CoroutineScope(StandardTestDispatcher()), cacheDir = null),
        )
        server.serveProfile("[${TestSupport.profile(""","tag":42,"friend_code":"k7Qm2x9a"""")}]")
        runBlocking { backend.refreshProfile() }
        return AppEnvironment(CoroutineScope(Dispatchers.Unconfined), backend)
    }

    private fun AppEnvironment.loadSocial() = runBlocking {
        server.on(
            "POST /rest/v1/rpc/my_friends",
            """{"friends":[{"id":"$blake","nickname":"Blake","rating":4.33},{"id":"$dana","nickname":"小雨","rating":3.67}],""" +
                """"requests":[{"id":"$casey","nickname":"Casey","rating":3,"created_at":"${ago(90)}"}]}""",
        )
        friendManager.refreshFriends()
        server.on(
            "POST /rest/v1/rpc/my_threads",
            """[{"kind":"dm","id":"$casey","name":"Casey","access":"open","request":"incoming","last":{"body":"周日一起打吗？","created_at":"${ago(20)}","mine":false},"unread":1},""" +
                """{"kind":"dm","id":"$blake","name":"Blake","access":"open","last":{"body":"周四 7 点半见","created_at":"${ago(5)}","mine":false},"unread":2},""" +
                """{"kind":"group","id":"grp1","name":"周四晚双打群","venue":"Pasadena Badminton","access":"open","last":{"body":"这周我带球","created_at":"${ago(60)}","mine":true},"unread":0},""" +
                """{"kind":"dm","id":"$dana","name":"小雨","access":"open","request":"outgoing","last":{"body":"你好，球群里见过","created_at":"${ago(3000)}","mine":true},"unread":0}]""",
        )
        messageManager.refreshThreads()
        server.on(
            "GET /rest/v1/notifications",
            """[{"id":9,"kind":"cancelled","title":"球局取消了","body":"周六 10:00 · Pasadena Badminton 的球局取消了，不算谁爽约。","link":"/app/games/g9/","created_at":"${ago(30)}","read_at":null},""" +
                """{"id":8,"kind":"friend_request","title":"Casey 想加你为球友","body":"通过以后就能私信、约球。","link":"/app/players/$casey/","created_at":"${ago(90)}","read_at":null},""" +
                """{"id":7,"kind":"group","title":"候补转正","body":"周四晚双打群：有人退出，你已报上。","link":"/app/groups/grp1/","created_at":"${ago(2000)}","read_at":"${ago(1900)}"}]""",
        )
        inboxManager.refresh()
    }

    private fun groupPage(member: Boolean): String {
        val players = """[{"id":"$me","nickname":"Alex","waitlisted":false},{"id":"$blake","nickname":"Blake","waitlisted":false},{"id":"$dana","nickname":"小雨","waitlisted":true}]"""
        return """{"id":"grp1","name":"周四晚双打群","summary":"轮换上场，新手友好；费用按人头在前台付。","level_min":3,"level_max":5,"join_policy":"approval",""" +
            """"venue":{"id":"v1","name":"Pasadena Badminton","city":"Pasadena","tz":"America/Los_Angeles"},""" +
            """"schedules":[{"weekday":4,"start":1170,"end":1320,"capacity":8,"fee":"每人 $15"},{"weekday":0,"start":600,"end":720,"capacity":12,"fee":"每人 $15"}],""" +
            """"activity":{"sessions":8,"average":7.4},"my_role":${if (member) "\"owner\"" else "null"},"invite_code":"ABC2LX",""" +
            """"sessions":[{"id":"s1","starts_at":"${inDays(2)}","ends_at":"${inDays(2, 2)}","capacity":8,"cancelled":false,"confirmed":2,"waitlist":1,""" +
            """"my_status":${if (member) "\"confirmed\"" else "null"},"players":${if (member) players else "null"}},""" +
            """{"id":"s2","starts_at":"${inDays(5)}","ends_at":"${inDays(5, 2)}","capacity":12,"cancelled":false,"confirmed":12,"waitlist":0,"my_status":null,"players":null}],""" +
            """"members":${if (member) """[{"id":"$me","nickname":"Alex","rating":4,"role":"owner"},{"id":"$blake","nickname":"Blake","rating":4.33,"role":"member"},{"id":"$dana","nickname":"小雨","rating":3.67,"role":"member"}]""" else "null"},""" +
            """"pending":${if (member) """[{"id":"$casey","nickname":"Casey","rating":3,"role":null}]""" else "null"}}"""
    }

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, environment: AppEnvironment, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        L10n.attach(RuntimeEnvironment.getApplication())
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
    fun messages() {
        val env = environment().apply { loadSocial() }
        shot("social-messages", environment = env) { MessagesScreen() }
    }

    @Test
    fun messagesEnglishDark() {
        val env = environment().apply { loadSocial() }
        shot("social-messages-en-dark", qualifiers = "en", appearance = Appearance.Dark, environment = env) { MessagesScreen() }
    }

    @Test
    fun emptyMessages() {
        val env = environment()
        shot("social-messages-empty", environment = env) { MessagesScreen() }
    }

    @Test
    fun friends() {
        val env = environment().apply { loadSocial() }
        shot("social-friends", environment = env) { FriendsScreen() }
    }

    @Test
    fun addFriend() {
        val env = environment().apply { loadSocial() }
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g1","starts_at":"${ago(3000)}","ends_at":"${ago(2900)}","status":"scheduled","venue":{"id":"v1","name":"Pasadena Badminton"},"my_report":{"outcome":"win"},""" +
                """"players":[{"id":"$me","nickname":"Alex","rating":4},{"id":"$casey","nickname":"Casey","rating":3}]}]""",
        )
        server.on("POST /rest/v1/rpc/venue_regulars", """[{"id":"6f1c2c3e-0000-4000-8000-000000000005","nickname":"Jordan","rating":5,"venue":{"id":"v1"}}]""")
        shot("social-add-friend", environment = env) { AddFriendScreen() }
    }

    @Test
    fun chat() {
        val env = environment().apply { loadSocial() }
        server.on(
            "POST /rest/v1/rpc/open_thread",
            """{"access":"open","members":[{"id":"$me","nickname":"Alex","me":true},{"id":"$blake","nickname":"Blake","me":false}],"messages":[""" +
                """{"id":1,"body":"这周四还打吗？","created_at":"${ago(80)}","sender":"$blake","mine":false},""" +
                """{"id":2,"body":"打，7 点半到","created_at":"${ago(78)}","sender":"$me","mine":true},""" +
                """{"id":3,"body":"好，我订了 3 号场","created_at":"${ago(6)}","sender":"$blake","mine":false},""" +
                """{"id":4,"body":"周四 7 点半见","created_at":"${ago(5)}","sender":"$blake","mine":false}]}""",
        )
        shot("social-chat", environment = env) { ChatScreen(blake) }
    }

    @Test
    fun chatRequest() {
        val env = environment().apply { loadSocial() }
        server.on(
            "POST /rest/v1/rpc/open_thread",
            """{"access":"open","members":[{"id":"$me","nickname":"Alex","me":true},{"id":"$casey","nickname":"Casey","me":false}],""" +
                """"messages":[{"id":5,"body":"周日一起打吗？加个微信吧","created_at":"${ago(20)}","sender":"$casey","mine":false}]}""",
        )
        shot("social-chat-request", environment = env) { ChatScreen(casey) }
    }

    @Test
    fun groupChat() {
        val env = environment().apply { loadSocial() }
        server.on(
            "POST /rest/v1/rpc/open_thread",
            """{"access":"open","members":[{"id":"$me","nickname":"Alex","me":true},{"id":"$blake","nickname":"Blake","me":false},{"id":"$dana","nickname":"小雨","me":false}],"messages":[""" +
                """{"id":11,"body":"这周四谁带球？","created_at":"${ago(70)}","sender":"$blake","mine":false},""" +
                """{"id":12,"body":"我带一筒","created_at":"${ago(68)}","sender":"$dana","mine":false},""" +
                """{"id":13,"body":"这周我带球","created_at":"${ago(60)}","sender":"$me","mine":true}]}""",
        )
        shot("social-group-chat", environment = env) { GroupChatScreen("group-grp1") }
    }

    @Test
    fun notifications() {
        val env = environment().apply { loadSocial() }
        shot("social-notifications", environment = env) { NotificationsScreen() }
    }

    @Test
    fun urgentNotice() {
        val env = environment().apply { loadSocial() }
        shot("social-urgent", environment = env) {
            UrgentNoticeSheet(env.inboxManager.items.filter { it.kind == InboxItem.Kind.GameCancelled }, {}, {})
        }
    }

    @Test
    fun playerProfile() {
        val env = environment().apply { loadSocial() }
        server.on(
            "POST /rest/v1/rpc/player_card",
            """{"id":"$casey","nickname":"Casey","rating":4.33,"tag":7,"tags":["punctual","friendly"],"win_rate":{"games":6,"wins":4,"opponents":3,"gap":0.2},""" +
                """"challenge":"available","message":{"status":"request","group":"周四晚双打群"},"gender":"female","recent_no_shows":1,""" +
                """"usual_times":[{"weekday":5,"start":"19:00","end":"22:00"},{"weekday":7,"start":"14:00","end":"17:00"}]}""",
        )
        shot("social-player-profile", qualifiers = "b+zh+Hans-h1100dp", environment = env) { PlayerProfileSheet(casey) {} }
    }

    @Test
    fun report() {
        val env = environment()
        shot("social-report", environment = env) { ReportSheet(blake, "Blake") {} }
    }

    @Test
    fun strikes() {
        val env = environment()
        server.on(
            "POST /rest/v1/rpc/my_strikes",
            """{"suspended_until":"${inDays(5)}","recent":2,"strikes":[""" +
                """{"id":5,"level":2,"status":"active","created_at":"${ago(600)}","seen":false,"can_appeal":true,"game_starts_at":"${ago(900)}","tz":"America/Los_Angeles","venue":"Pasadena Badminton"},""" +
                """{"id":3,"level":1,"status":"upheld","created_at":"${ago(80_000)}","seen":true,"can_appeal":false,"game_starts_at":"${ago(80_300)}","tz":"America/Los_Angeles","venue":"LA Badminton Center"}]}""",
        )
        server.on("POST /rest/v1/rpc/mark_strikes_seen", "")
        runBlocking { env.friendManager.refreshStrikes() }
        shot("social-strikes", environment = env) { StrikesSheet {} }
    }

    @Test
    fun friendLink() {
        val env = environment()
        shot("social-friend-link", environment = env) { FriendLinkSheet() }
    }

    @Test
    fun blockedUsers() {
        val env = environment().apply { loadSocial() }
        server.on("POST /rest/v1/rpc/block_user", "")
        env.messageManager.block(dana)
        shot("social-blocked", environment = env) { BlockedUsersScreen() }
    }

    @Test
    fun groups() {
        val env = environment()
        server.on("POST /rest/v1/rpc/group_page", groupPage(member = true))
        val nearby =
            """[{"id":"grp2","name":"周末早场","level_min":2,"level_max":4,"join_policy":"open","gender":"female","venue":{"id":"v2","name":"LA Badminton Center"},""" +
                """"schedules":[{"weekday":6,"start":540,"end":720,"capacity":16}],"activity":{"sessions":4,"average":10.5}},""" +
                """{"id":"grp3","name":"教练小班","level_min":1,"level_max":3,"join_policy":"approval","coached":true,"venue":{"id":"v3","name":"Arcadia Badminton"},""" +
                """"schedules":[{"weekday":2,"start":1140,"end":1260,"capacity":6}],"activity":{"sessions":0,"average":0},"my_role":"pending"}]"""
        server.on("POST /rest/v1/rpc/groups_near", nearby)
        runBlocking {
            env.groupManager.loadGroup("grp1")
            env.groupManager.loadNearby(Coordinate.fallbackCenter, 10.0)
        }
        shot("social-groups", environment = env) { GroupsScreen() }
    }

    @Test
    fun groupAsOwner() {
        val env = environment()
        server.on("POST /rest/v1/rpc/group_page", groupPage(member = true))
        runBlocking { env.groupManager.loadGroup("grp1") }
        shot("social-group-owner", qualifiers = "b+zh+Hans-h1300dp", environment = env) { GroupScreen("grp1") }
    }

    @Test
    fun groupToJoin() {
        val env = environment()
        server.on("POST /rest/v1/rpc/group_page", groupPage(member = false))
        runBlocking { env.groupManager.loadGroup("grp1") }
        shot("social-group-join", environment = env) { GroupScreen("grp1") }
    }

    @Test
    fun createGroup() {
        val env = environment()
        shot("social-create-group", qualifiers = "b+zh+Hans-h1500dp", environment = env) { CreateGroupScreen(null) }
    }
}
