package com.badie.app.features.social

import com.badie.app.features.social.SocialTestSupport.BLAKE
import com.badie.app.features.social.SocialTestSupport.CASEY
import com.badie.app.features.social.SocialTestSupport.ME
import com.badie.app.features.social.SocialTestSupport.call
import com.badie.app.features.social.SocialTestSupport.environment
import com.badie.app.features.social.SocialTestSupport.text
import com.badie.app.models.DISTANT_FUTURE
import com.badie.app.models.Gender
import com.badie.app.models.MyStrikes
import com.badie.app.models.SurveyTag
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteError
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

/** 球友、球友资料、爽约记录。对应 iPhone SupabaseClientTests 里球友那几个（testPlayerSearchGoesToServer 等） */
@OptIn(ExperimentalCoroutinesApi::class)
class FriendManagerTest {
    private val server = FakeServer()

    @Test
    fun playerSearchGoesToServer() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/find_players", """[{"id":"$BLAKE","nickname":"Blake","tag":42,"rating":4.33,"mutual_friends":1,"relationship":"requested"}]""")
        val found = env.friendManager.findPlayers("bla")
        assertEquals(listOf("Blake"), found.map { it.nickname })
        assertEquals("#0042", found.first().tagText)
        assertEquals("bla", server.text(0, "p_query"))
        assertTrue("在别处申请过的也显示等待通过", env.friendManager.hasPendingRequest(BLAKE))

        server.on("POST /rest/v1/rpc/find_players", """{"code":"54000","details":null,"hint":null,"message":"too_many_searches"}""", status = 400)
        try {
            env.friendManager.findPlayers("bla")
            fail("限速要报错")
        } catch (error: RemoteError) {
            assertEquals(RemoteError.Server("too_many_searches").message, error.message)
        }
    }

    @Test
    fun friendsAndRequestsComeFromServer() = runTest {
        val env = environment(server, backgroundScope)
        server.on(
            "POST /rest/v1/rpc/my_friends",
            """{"friends":[{"id":"$BLAKE","nickname":"Blake","rating":4.33}],"requests":[{"id":"$CASEY","nickname":"Casey","rating":3,"created_at":"2026-10-17T10:00:00+00:00"}]}""",
        )
        env.friendManager.refreshFriends()
        assertEquals(listOf(BLAKE), env.friendManager.friends.map { it.id })
        assertTrue(env.friendManager.isFriend(BLAKE))
        assertEquals(listOf(CASEY), env.friendManager.incomingRequests.map { it.fromUserId })
        assertEquals(1, env.friendManager.incomingRequestCount)
        assertEquals("Casey", env.friendManager.user(CASEY)?.nickname)
        assertEquals(Instant.parse("2026-10-17T10:00:00Z").toEpochMilli(), env.friendManager.incomingRequests.first().sentAt)

        // 接受申请：按对方的 ID 调用，之后球友和会话一起重拉
        server.requests.clear()
        server.on("POST /rest/v1/rpc/respond_friend_request", "")
        server.on("POST /rest/v1/rpc/my_friends", """{"friends":[{"id":"$BLAKE","nickname":"Blake","rating":4.33},{"id":"$CASEY","nickname":"Casey","rating":3}],"requests":[]}""")
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        env.friendManager.respond(env.friendManager.incomingRequests.first(), accept = true)
        assertEquals(CASEY, server.text(0, "p_user"))
        assertEquals("true", server.text(0, "p_accept"))
        assertEquals("/rest/v1/rpc/my_threads", server.path(2))
        assertTrue(env.friendManager.isFriend(CASEY))
        assertEquals(0, env.friendManager.incomingRequestCount)
    }

    @Test
    fun sentRequestsWaitUntilAccepted() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/send_friend_request", "\"requested\"")
        server.on("POST /rest/v1/rpc/my_friends", """{"friends":[],"requests":[]}""")
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        env.friendManager.sendRequest(BLAKE)
        assertEquals(BLAKE, server.text(0, "p_user"))
        assertTrue("服务器只列收到的申请：发出的留在本机", env.friendManager.hasPendingRequest(BLAKE))

        // 对方通过以后就不再是“等待通过”
        server.on("POST /rest/v1/rpc/my_friends", """{"friends":[{"id":"$BLAKE","nickname":"Blake","rating":4.33}],"requests":[]}""")
        env.friendManager.refreshFriends()
        assertFalse(env.friendManager.hasPendingRequest(BLAKE))
        assertTrue(env.friendManager.isFriend(BLAKE))
    }

    @Test
    fun playerCardFillsTheProfile() = runTest {
        val env = environment(server, backgroundScope)
        server.on(
            "POST /rest/v1/rpc/player_card",
            """{"id":"$BLAKE","nickname":"Blake","rating":7.0,"tag":7,"tags":["punctual","nope"],"win_rate":{"games":6,"wins":4,"opponents":3,"gap":0.2,"rounds":12,"round_wins":9},""" +
                """"challenge":"friends_only","message":{"status":"request","group":"Sunday Club"},"verified":"tournament","gender":"female",""" +
                """"recent_no_shows":2,"suspended_until":"infinity","card_color":"mint","usual_times":[{"weekday":2,"start":"19:00","end":"21:00"}]}""",
        )
        env.friendManager.refreshPlayer(BLAKE)
        val blake = env.friendManager.user(BLAKE)!!
        assertEquals("#0007", blake.tagText)
        assertEquals(Gender.Female, blake.gender)
        assertEquals(VerificationStatus.Tournament, blake.verificationStatus)
        assertEquals(listOf(SurveyTag.ofServer("punctual")), blake.reputation.publicTags)
        assertEquals(2 to DISTANT_FUTURE, env.friendManager.noShows(BLAKE))
        assertEquals("friends_only", env.friendManager.cache.challengeStatus[BLAKE])
        assertEquals("Sunday Club", env.friendManager.cache.messageOptions[BLAKE]?.group)
        assertEquals(75, env.friendManager.cache.winRates[BLAKE]?.percentage)
        assertEquals(1, env.friendManager.cache.usualTimes[BLAKE]?.size)

        // 拉不到（没打过交道）：资料保持原样
        server.on("POST /rest/v1/rpc/player_card", "null")
        env.friendManager.refreshPlayer(BLAKE)
        assertEquals("Blake", env.friendManager.user(BLAKE)?.nickname)
    }

    @Test
    fun gamesTogetherAndCoPlayersComeFromMyGames() = runTest {
        val env = environment(server, backgroundScope)
        val player = { id: String, name: String -> """{"id":"$id","nickname":"$name","rating":4,"team":1,"me":${id == ME}}""" }
        server.on(
            "POST /rest/v1/rpc/my_games",
            """[{"id":"g1","mode":"singles","starts_at":"2026-10-10T18:00:00+00:00","ends_at":"2026-10-10T20:00:00+00:00","status":"scheduled",""" +
                """"venue":{"id":"v1","name":"Test Court"},"my_team":1,"review_until":"2026-10-12T20:00:00+00:00","my_report":{"outcome":"team1"},"players":[${player(ME, "Alex")},${player(BLAKE, "Blake")}]},""" +
                """{"id":"g2","mode":"singles","starts_at":"2026-10-12T18:00:00+00:00","ends_at":"2026-10-12T20:00:00+00:00","status":"scheduled",""" +
                """"venue":{"id":"v1","name":"Test Court"},"my_team":1,"review_until":"2026-10-14T20:00:00+00:00","my_report":null,"players":[${player(ME, "Alex")},${player(CASEY, "Casey")}]}]""",
        )
        env.friendManager.refreshGames(force = true)
        assertEquals(listOf("g1"), env.friendManager.gamesTogether(BLAKE).map { it.id })
        assertTrue("还没填赛果的不算打完", env.friendManager.gamesTogether(CASEY).isEmpty())
        assertEquals(listOf(BLAKE), env.friendManager.recentCoPlayers().map { it.id })
        assertEquals("Casey", env.friendManager.user(CASEY)?.nickname)
    }

    @Test
    fun strikesComeFromServer() = runTest {
        val env = environment(server, backgroundScope)
        server.on(
            "POST /rest/v1/rpc/my_strikes",
            """{"suspended_until":"2026-11-20T03:00:00+00:00","recent":2,"strikes":[{"id":5,"level":2,"status":"appealed","created_at":"2026-11-13T03:00:00+00:00",""" +
                """"seen":false,"can_appeal":true,"game_starts_at":"2026-11-12T03:00:00+00:00","tz":"America/Los_Angeles","venue":"Test Court"}]}""",
        )
        env.friendManager.refreshStrikes()
        val strikes = env.friendManager.strikes!!
        assertEquals(2, strikes.recent)
        assertEquals(Instant.parse("2026-11-20T03:00:00Z").toEpochMilli(), strikes.suspendedUntil)
        assertEquals(MyStrikes.Status.Appealed, strikes.strikes.first().status)
        assertEquals("America/Los_Angeles", strikes.strikes.first().timeZone?.id)
        assertTrue("有没看过的就弹说明", env.appState.showsStrikes)

        server.requests.clear()
        server.on("POST /rest/v1/rpc/appeal_strike", "")
        server.on("POST /rest/v1/rpc/my_strikes", """{"suspended_until":null,"recent":1,"strikes":[]}""")
        env.friendManager.appealStrike(5, "去了，只是忘了签到")
        assertEquals("5", server.text(server.call("appeal_strike"), "p_strike"))
        assertEquals("去了，只是忘了签到", server.text(0, "p_text"))
        assertNull(env.friendManager.strikes?.suspendedUntil)

        server.on("POST /rest/v1/rpc/mark_strikes_seen", "")
        env.friendManager.markStrikesSeen()
        runCurrent()
        assertEquals("/rest/v1/rpc/mark_strikes_seen", server.path(server.requests.size - 1))
    }

    @Test
    fun friendLinkIsRead() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/open_friend_link", "\"$BLAKE\"")
        assertEquals(BLAKE, env.friendManager.openFriendLink("abc123"))
        assertEquals("abc123", server.text(0, "p_code"))
        server.on("POST /rest/v1/rpc/open_friend_link", "null")
        assertNull("链接失效", env.friendManager.openFriendLink("old"))
    }
}
