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
import org.junit.Assert.assertFalse
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

    /** 两个球馆：周四在主球馆，周日在第二个球馆 */
    private fun twoVenuePage(): String {
        val start = Instant.now().plusSeconds(2 * 86_400)
        val end = start.plusSeconds(7_200)
        return """{"id":"grp1","name":"Thu doubles","level_min":3,"level_max":5,"join_policy":"open",""" +
            """"venue":{"id":"v-main","name":"Main Hall","city":"Irvine","tz":"America/Los_Angeles"},""" +
            """"venues":[{"id":"v-main","name":"Main Hall","city":"Irvine","tz":"America/Los_Angeles"},{"id":"v-west","name":"West Gym","city":"Tustin","tz":null}],""" +
            """"schedules":[{"weekday":4,"start":1170,"end":1320,"capacity":8,"fee":"","venue":null},{"weekday":0,"start":600,"end":720,"capacity":8,"fee":"","venue":"v-west"}],""" +
            """"activity":{"sessions":6,"average":7.5},"my_role":"owner","invite_code":"ABC2LX",""" +
            """"sessions":[{"id":"s1","starts_at":"$start","ends_at":"$end","capacity":8,"cancelled":false,"confirmed":0,"waitlist":0,"my_status":null,"players":[],"venue":"v-west"}],""" +
            """"members":[{"id":"$ME","nickname":"Alex","rating":4,"role":"owner"}],"pending":[]}"""
    }

    @Test
    fun groupsCanHaveSeveralVenues() = runTest {
        val env = environment(server, backgroundScope)
        val manager = env.groupManager
        server.on("POST /rest/v1/rpc/group_page", twoVenuePage())
        manager.loadGroup("grp1")

        val group = manager.group("grp1")!!
        assertEquals(listOf("v-main", "v-west"), group.venueIds)
        assertEquals(listOf("West Gym"), manager.otherVenues(group).map { it.name })
        assertEquals("v-west", group.schedules[1].venueId)
        assertEquals("v-west", group.schedules[1].effectiveVenueId(group))
        assertEquals("主球馆的场次是 null", "v-main", group.schedules[0].effectiveVenueId(group))
        assertEquals("这一场在哪个球馆", "West Gym", manager.sessionVenueName(manager.session("s1")!!))
        assertEquals("群里任何一个球馆都算", listOf("grp1"), manager.groups(atVenue = "v-west").map { it.id })

        // 建群：p_venue 是主球馆，p_venues 是全部；不在主球馆的场次带 venue
        server.requests.clear()
        server.on("POST /rest/v1/rpc/create_group", "\"grp1\"")
        server.on("POST /rest/v1/rpc/group_page", twoVenuePage())
        val schedule = GroupSchedule("s", 1, 10 * 60, 12 * 60, 8, venueId = "v-west")
        manager.create("Thu doubles", "v-main", listOf(schedule), 3..5, PlayGroup.JoinPolicy.Open, "", otherVenueIds = listOf("v-west"))
        assertEquals("v-main", server.text(0, "p_venue"))
        assertEquals(listOf("v-main", "v-west"), server.json(0)["p_venues"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals("v-west", server.json(0)["p_schedules"]!!.jsonArray.first().jsonObject["venue"]?.jsonPrimitive?.content)

        // 编辑：没给球馆就传 null（不变）
        server.requests.clear()
        server.on("POST /rest/v1/rpc/update_group", "")
        server.on("POST /rest/v1/rpc/group_page", twoVenuePage())
        manager.update("grp1", "Thu doubles", group.schedules, 3..5, PlayGroup.JoinPolicy.Open, "", coached = false)
        assertEquals("null", server.json(0)["p_venues"].toString())
        server.on("POST /rest/v1/rpc/update_group", "")
        server.on("POST /rest/v1/rpc/group_page", twoVenuePage())
        manager.update("grp1", "Thu doubles", group.schedules, 3..5, PlayGroup.JoinPolicy.Open, "", coached = false, venueIds = listOf("v-main"))
        assertEquals(listOf("v-main"), server.json(2)["p_venues"]!!.jsonArray.map { it.jsonPrimitive.content })
    }

    @Test
    fun oneVenueGroupsLookTheSame() = runTest {
        val env = environment(server, backgroundScope)
        server.on("POST /rest/v1/rpc/group_page", groupPage("confirmed"))
        env.groupManager.loadGroup("grp1")
        val group = env.groupManager.group("grp1")!!
        assertEquals("旧服务器没有 venues", listOf("v-test-court"), group.venueIds)
        assertNull("只有一个球馆时场次不写球馆", env.groupManager.sessionVenueName(env.groupManager.session("s1")!!))
        assertTrue(env.groupManager.otherVenues(group).isEmpty())
    }

    @Test
    fun nearestGroupsKeepTheServerOrder() = runTest {
        val env = environment(server, backgroundScope)
        val summary = { id: String, sessions: Int, meters: Int ->
            """{"id":"$id","name":"G$id","level_min":2,"level_max":6,"join_policy":"open","venue":{"id":"v$id","name":"Court"},"schedules":[],""" +
                """"activity":{"sessions":$sessions,"average":6},"distance_m":$meters}"""
        }
        server.on("POST /rest/v1/rpc/groups_near", "[${summary("a", 1, 300)},${summary("b", 8, 2500)}]")
        env.groupManager.loadNearby(Coordinate(34.0, -118.0), 10.0)
        assertEquals("发现页：近的在前", listOf("a", "b"), env.groupManager.nearestGroups().map { it.id })
        assertEquals("球群页：活跃的在前", listOf("b", "a"), env.groupManager.nearbyGroups().map { it.id })
    }

    @Test
    fun venueListsKeepTheMainVenueFirst() {
        val group = PlayGroup(
            "g", "G", "v1", ME, listOf(ME), listOf(ME), emptyList(), "", 1..9, emptyList(), PlayGroup.JoinPolicy.Open, "ABC2LX", 0,
            otherVenueIds = listOf("v1", "v2"),
        )
        assertEquals("主球馆不重复", listOf("v1", "v2"), group.venueIds)
        val moved = group.withVenueIds(listOf("v2", "v3", "v3"))
        assertEquals("v2", moved.venueId)
        assertEquals(listOf("v2", "v3"), moved.venueIds)
        assertNull(group.withVenueIds(listOf("v1")).otherVenueIds)
        val schedule = GroupSchedule("s", 1, 600, 720, 8, venueId = "v-gone")
        assertEquals("删掉的球馆回到主球馆", "v1", schedule.effectiveVenueId(group))
        assertEquals("v1", GroupSession("x", "g", "s", com.badie.app.models.TimeSlot.of(0, 0, 3_600_000), 8, emptyList(), emptyList()).effectiveVenueId(group))
    }

    @Test
    fun schedulesUseSundayZeroOnTheServer() {
        val sunday = GroupSchedule("s", 1, 9 * 60, 11 * 60, 6, "AA")
        val server = GroupsApi.serverSchedules(listOf(sunday)).first()
        assertEquals(0, server["weekday"])
        assertEquals("AA", server["fee"])
        assertEquals("", GroupsApi.serverSchedules(listOf(sunday.copy(feeNote = null))).first()["fee"])
        assertFalse("在主球馆的不带 venue", "venue" in server)
        assertEquals("v2", GroupsApi.serverSchedules(listOf(sunday.copy(venueId = "v2"))).first()["venue"])
    }
}
