package com.badie.app.features.groups

import com.badie.app.backend.GroupsApi
import com.badie.app.features.social.SocialTestSupport.BLAKE
import com.badie.app.features.social.SocialTestSupport.CASEY
import com.badie.app.features.social.SocialTestSupport.ME
import com.badie.app.features.social.SocialTestSupport.call
import com.badie.app.features.social.SocialTestSupport.environment
import com.badie.app.features.social.SocialTestSupport.text
import com.badie.app.models.Coordinate
import com.badie.app.models.GroupSchedule
import com.badie.app.models.GroupSession
import com.badie.app.models.PlayGroup
import com.badie.app.remote.FakeServer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** 球群。对应 iPhone SupabaseClientTests 的 testGroupsComeFromServer、testGroupActionsCallTheServer */
@OptIn(ExperimentalCoroutinesApi::class)
class GroupManagerTest {
    private val server = FakeServer()

    private fun groupPage(myStatus: String, waitlist: Int = 0, players: String? = """[{"id":"$ME","nickname":"Alex","waitlisted":false}]"""): String {
        val start = Instant.now().plusSeconds(2 * 86_400)
        val end = start.plusSeconds(7_200)
        return """{"id":"grp1","name":"Thu doubles","summary":"Friendly","level_min":3,"level_max":5,"join_policy":"approval",""" +
            """"venue":{"id":"v-test-court","name":"Test Court","city":"Irvine","tz":"America/Los_Angeles"},""" +
            """"schedules":[{"weekday":4,"start":1170,"end":1320,"capacity":8,"fee":"$12"}],"activity":{"sessions":6,"average":7.5},"my_role":"owner","invite_code":"ABC2LX",""" +
            """"sessions":[{"id":"s1","starts_at":"$start","ends_at":"$end","capacity":8,"cancelled":false,"confirmed":1,"waitlist":$waitlist,"my_status":"$myStatus","players":$players}],""" +
            """"members":[{"id":"$ME","nickname":"Alex","rating":4,"role":"owner"},{"id":"$BLAKE","nickname":"Blake","rating":4.33,"role":"member"}],""" +
            """"pending":[{"id":"$CASEY","nickname":"Casey","rating":3,"role":null}]}"""
    }

    @Test
    fun groupsComeFromServer() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/group_page", groupPage("confirmed"))
        val manager = env.groupManager
        manager.loadGroup("grp1")

        val group = manager.group("grp1")!!
        assertEquals(ME, group.ownerId)
        assertEquals(setOf(ME, BLAKE), group.memberIds.toSet())
        assertTrue(group.isOrganizer(ME))
        assertEquals(listOf(CASEY), group.pendingIds)
        assertEquals("ABC2LX", group.inviteCode)
        assertEquals(PlayGroup.JoinPolicy.Approval, group.joinPolicy)
        assertEquals(3..5, group.levelRange)
        assertEquals("服务器 4 = 周四；本地 1 = 周日，所以周四是 5", 5, group.schedules.first().weekday)
        assertEquals("$12", group.schedules.first().feeNote)
        assertEquals(6, manager.activity("grp1").sessionsLast30Days)
        assertEquals(listOf("grp1"), manager.myGroups.map { it.id })
        assertEquals(listOf("s1"), manager.mySessions.map { it.id })
        assertEquals(GroupSession.Status.SignedUp, manager.session("s1")?.status(ME))
        assertEquals("服务器上的球馆名字也留着", "Test Court", manager.venue(group)?.name)
        assertEquals("Casey", manager.user(CASEY)?.nickname)
    }

    @Test
    fun groupActionsCallTheServer() = runTest {
        val env = environment(server, backgroundScope)
        val manager = env.groupManager
        server.on("POST /rest/v1/rpc/group_page", groupPage("confirmed"))
        manager.loadGroup("grp1")

        server.requests.clear()
        server.on("POST /rest/v1/rpc/sign_up_session", "\"waitlisted\"")
        server.on("POST /rest/v1/rpc/group_page", groupPage("waitlisted:2", waitlist = 2, players = "null"))
        val result = manager.signUp("s1")
        assertEquals("s1", server.text(0, "p_session"))
        assertEquals("看不到名单时按 my_status 放我的位置", SignupResult.Waitlisted(2), result)

        server.requests.clear()
        server.on("POST /rest/v1/rpc/create_group", "\"grp1\"")
        server.on("POST /rest/v1/rpc/group_page", groupPage("confirmed"))
        val schedule = GroupSchedule("s", 5, 19 * 60 + 30, 22 * 60, 8)
        manager.create(" Thu doubles ", "v-test-court", listOf(schedule), 3..5, PlayGroup.JoinPolicy.Approval, "")
        assertEquals("Thu doubles", server.text(0, "p_name"))
        assertEquals("approval", server.text(0, "p_policy"))
        assertEquals("不勾就是普通群", "false", server.text(0, "p_coached"))
        val schedules = server.json(0)["p_schedules"]!!.jsonArray
        assertEquals("本地周四 5 → 服务器 4", "4", schedules.first().jsonObject["weekday"]?.jsonPrimitive?.content)
        assertEquals("1170", schedules.first().jsonObject["start"]?.jsonPrimitive?.content)

        server.on("POST /rest/v1/rpc/find_group", "null")
        assertNull(manager.find("ZZZZZZ"))
    }

    @Test
    fun leavingAndDisbandingRefresh() = runTest {
        val env = environment(server, backgroundScope)
        val manager = env.groupManager
        server.on("POST /rest/v1/rpc/group_page", groupPage("confirmed"))
        manager.loadGroup("grp1")

        // 群没了：拉不到就从缓存删掉
        server.on("POST /rest/v1/rpc/disband_group", "")
        server.on("POST /rest/v1/rpc/my_groups", """{"groups":[]}""")
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        manager.disband("grp1")
        assertEquals("grp1", server.text(server.call("disband_group"), "p_group"))
        assertNull(manager.group("grp1"))
        assertTrue(manager.myGroups.isEmpty())
    }

    @Test
    fun nearbyGroupsAreSortedByActivity() = runTest {
        val env = environment(server, backgroundScope)
        val summary = { id: String, name: String, sessions: Int ->
            """{"id":"$id","name":"$name","level_min":2,"level_max":6,"join_policy":"open","venue":{"id":"v1","name":"Court"},"schedules":[],"activity":{"sessions":$sessions,"average":6}}"""
        }
        server.on("POST /rest/v1/rpc/groups_near", "[${summary("a", "Quiet", 1)},${summary("b", "Busy", 8)}]")
        env.groupManager.loadNearby(Coordinate(34.0, -118.0), 10.0)
        assertEquals(listOf("b", "a"), env.groupManager.nearbyGroups().map { it.id })
        assertEquals("34.0", server.text(0, "lat"))
        assertEquals("10.0", server.text(0, "radius_km"))

        // 同一个地方 60 秒内不重拉
        env.groupManager.loadNearby(Coordinate(34.001, -118.0), 10.0)
        assertEquals(1, server.requests.size)
    }

    @Test
    fun schedulesUseSundayZeroOnTheServer() {
        val sunday = GroupSchedule("s", 1, 9 * 60, 11 * 60, 6, "AA")
        val server = GroupsApi.serverSchedules(listOf(sunday)).first()
        assertEquals(0, server["weekday"])
        assertEquals("AA", server["fee"])
        assertEquals("", GroupsApi.serverSchedules(listOf(sunday.copy(feeNote = null))).first()["fee"])
    }
}
