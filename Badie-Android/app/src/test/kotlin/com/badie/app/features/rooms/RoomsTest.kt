package com.badie.app.features.rooms

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.RoomDraft
import com.badie.app.models.Coordinate
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.PlayEvent
import com.badie.app.models.Room
import com.badie.app.models.RoomCloseReason
import com.badie.app.models.RoomStatus
import com.badie.app.models.RoomTag
import com.badie.app.models.RoomVisibility
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.title
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteError
import com.badie.app.shell.AppState
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

/** 房间：从服务器读、往服务器写，加入的规则。对应 iPhone 的 SupabaseClientTests 里“球局（房间）”那几条 */
class RoomsTest {
    private val server = FakeServer()
    private val me = TestSupport.USER_ID
    private val blake = "6f1c2c3e-0000-4000-8000-000000000002"
    private val roomId = "8d1c2c3e-0000-4000-8000-0000000000aa"
    private val venue = """{"id":"v-test-court","name":"Test Court","city":"Irvine","street":"1 Main St","tz":"America/Los_Angeles","lat":33.68,"lon":-117.8,"country":"US","pricing":{"perPerson":12}}"""

    /** room_page / my_rooms / rooms_near 的一条；members 为 null 时是外人看到的样子 */
    private fun roomJSON(
        status: String = "open", reason: String = "null", owner: String? = null, myStatus: String = "owner",
        code: String = "\"ABC234\"", members: String? = null, going: Int = 2, waitlist: Int = 0,
    ): String {
        val host = owner ?: me
        val other = if (host == me) blake else me
        val list = members
            ?: """[{"id":"$host","nickname":"Host","rating":4,"waitlisted":false,"me":${host == me}},{"id":"$other","nickname":"Other","rating":4.33,"waitlisted":false,"me":${other == me}}]"""
        val mine = if (myStatus == "null") "null" else "\"$myStatus\""
        return """{"id":"$roomId","mode":"doubles","visibility":"public","status":"$status","closed_reason":$reason,"game_id":null,"starts_at":"2026-10-25T02:00:00+00:00","ends_at":"2026-10-25T04:00:00+00:00","level_min":3,"level_max":5,"tags":["casual","not_a_tag"],"note":"Court 3","capacity":4,"going":$going,"waitlist":$waitlist,"last_activity_at":"2026-10-18T02:00:00+00:00","owner":{"id":"$host","nickname":"Host","rating":4},"venue":$venue,"my_status":$mine,"code":$code,"members":$list}"""
    }

    private suspend fun TestScope.manager(): RoomManager {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        server.requests.clear()
        return RoomManager(ManagerContext(backgroundScope, backend, AppState(backgroundScope, backend), null))
    }

    @Test
    fun myRoomsComeFromServer() = runTest {
        val manager = manager()
        server.on("POST /rest/v1/rpc/my_rooms", "[${roomJSON(owner = blake, myStatus = "member")}]")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(owner = blake, myStatus = "member"))
        manager.refreshRooms()

        val room = manager.myRooms.single()
        assertEquals("ABC234", room.code)
        assertEquals(blake, room.ownerId)
        assertEquals(listOf(blake, me), room.participants.map { it.userId })
        assertEquals(RoomVisibility.PublicListing, room.visibility)
        assertEquals(3..5, room.levelRange)
        assertEquals("不认识的标签跳过", listOf(RoomTag.Casual), room.tags)
        assertEquals("Test Court", room.court?.name)
        assertEquals(Instant.parse("2026-10-25T02:00:00Z").toEpochMilli(), room.slot?.startTime)
        assertEquals("房间里的人记下来", "Host", manager.book.user(blake)?.nickname)

        // 房主解散后不在“我的房间”里了：再拉一次，提示房间已关闭
        server.on("POST /rest/v1/rpc/my_rooms", "[]")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(status = "closed", reason = "\"owner_closed\"", owner = blake, myStatus = "member"))
        manager.refreshRooms()
        assertEquals(RoomStatus.Closed(RoomCloseReason.OwnerClosed), manager.room(roomId)?.status)
        assertTrue(manager.myRooms.isEmpty())
        assertEquals("房间 ABC234：房主已解散房间", manager.notice)
    }

    @Test
    fun nearbyRoomsHideWhoIsPlaying() = runTest {
        val manager = manager()
        server.on(
            "POST /rest/v1/rpc/rooms_near",
            "[${roomJSON(owner = blake, myStatus = "null", code = "null", members = "null", going = 3, waitlist = 1)}]",
        )
        manager.loadNearby(Coordinate(33.68, -117.8))
        val room = manager.publicRooms.single()
        assertEquals("外人拿不到房间码", "", room.code)
        assertEquals(3, room.participants.size)
        assertEquals("房主是谁看得到", blake, room.participants.first().userId)
        assertEquals("其他人只占位", 2, room.participants.count { it.isAnonymous })
        assertEquals(1, room.waitlist.size)
        assertEquals(10.0, server.json(0)["radius_km"]?.jsonPrimitive?.content?.toDouble() ?: 0.0, 0.0)

        // 60 秒内同一位置不重复拉
        manager.loadNearby(Coordinate(33.681, -117.8))
        assertEquals(1, server.requests.size)
    }

    @Test
    fun roomActionsCallTheServer() = runTest {
        val manager = manager()
        val draft = RoomDraft(
            mode = GameMode.Doubles, visibility = RoomVisibility.PrivateRoom, tags = listOf(RoomTag.Casual, RoomTag.Coaching),
            levelRange = 2..6, note = "  Court 3 ", event = PlayEvent.Women,
        )
        server.on("POST /rest/v1/rpc/create_room", "\"$roomId\"")
        server.on("POST /rest/v1/rpc/room_page", roomJSON())
        val created = manager.create(draft)
        assertEquals(roomId, created.id)
        val body = server.json(0)
        assertEquals("private", body["p_visibility"]?.jsonPrimitive?.content)
        assertEquals(listOf("casual", "coaching"), body["p_tags"]?.jsonArray?.map { it.jsonPrimitive.content })
        assertEquals(2, body["p_level_min"]?.jsonPrimitive?.int)
        assertEquals("Court 3", body["p_note"]?.jsonPrimitive?.content)
        assertEquals("女双", "female", body["p_gender"]?.jsonPrimitive?.content)
        assertEquals(false, body["p_mixed"]?.jsonPrimitive?.boolean)
        assertEquals("私密局可以先不定球馆", JsonNull, body["p_venue"])
        assertEquals(JsonNull, body["p_starts_at"])

        // 房间码：先查是不是群号，不是再加入；找不到房间要报错
        server.requests.clear()
        server.on("POST /rest/v1/rpc/find_group", "null")
        server.on("POST /rest/v1/rpc/join_room_code", """{"code":"P0002","details":null,"hint":null,"message":"room_not_found"}""", status = 400)
        try {
            manager.join("ZZZZZZ")
            fail("找不到房间要报错")
        } catch (error: RemoteError) {
            assertEquals(RemoteError.Server("room_not_found"), error)
        }
        assertEquals("ZZZZZZ", server.json(1)["p_code"]?.jsonPrimitive?.content)

        // 群号：返回球群，不加入房间
        server.requests.clear()
        server.on("POST /rest/v1/rpc/find_group", "\"g-42\"")
        assertEquals(RoomManager.JoinResult.Group("g-42"), manager.join("GRP234"))
        assertEquals(1, server.requests.size)

        // 自己退出不算“被移出”
        server.on("POST /rest/v1/rpc/leave_room", "null")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(owner = blake, myStatus = "null", code = "null", members = "null", going = 1))
        manager.leave(manager.room(roomId)!!)
        assertNull(manager.notice)
        assertFalse(manager.room(roomId)?.contains(me) ?: true)
    }

    @Test
    fun startAndUpdateCallTheServer() = runTest {
        val manager = manager()
        server.on("POST /rest/v1/rpc/start_room", "\"g-new\"")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(status = "started"))
        server.on("POST /rest/v1/rpc/my_games", "[]")
        val room = makeRoom()
        assertEquals("g-new", manager.start(room))
        assertEquals(roomId, server.json(0)["p_room"]?.jsonPrimitive?.content)

        server.requests.clear()
        server.on("POST /rest/v1/rpc/update_room", "")
        server.on("POST /rest/v1/rpc/room_page", roomJSON())
        val slot = TimeSlot(0, 1_800_000_000_000L, 1_800_007_200_000L)
        manager.updateDetails(room, null, slot)
        assertEquals("2027-01-15T08:00:00Z", server.json(0)["p_starts_at"]?.jsonPrimitive?.content)
        assertEquals(JsonNull, server.json(0)["p_venue"])

        server.requests.clear()
        server.on("POST /rest/v1/rpc/invite_to_room", "")
        server.on("POST /rest/v1/rpc/room_page", roomJSON())
        manager.invite(listOf(blake), room)
        assertEquals(listOf(blake), server.json(0)["p_users"]?.jsonArray?.map { it.jsonPrimitive.content })
    }

    private fun makeRoom(
        mode: GameMode = GameMode.Doubles, participants: Int = 2, visibility: RoomVisibility = RoomVisibility.PublicListing,
        levels: IntRange = 3..5, event: PlayEvent? = null, mixed: Room.MixedGoing? = null,
    ) = Room(
        id = roomId, code = "ABC234", ownerId = blake, mode = mode, visibility = visibility,
        participants = (0 until participants).map { com.badie.app.models.RoomParticipant.anonymous("spot-$it") },
        invitedUserIds = emptyList(), waitlist = emptyList(), levelRange = levels, tags = listOf(RoomTag.Casual), note = "",
        createdAt = 0, lastActivityAt = 0, status = RoomStatus.Open, event = event, mixedGoing = mixed,
    )

    @Test
    fun joinRules() {
        val open = makeRoom()
        assertFalse(RoomJoinRules(open, me, Gender.Male, 4).levelBlocked)
        assertTrue("水平不在范围里", RoomJoinRules(open, me, Gender.Male, 7).levelBlocked)
        assertFalse("私密局不看水平", RoomJoinRules(makeRoom(visibility = RoomVisibility.PrivateRoom), me, Gender.Male, 7).levelBlocked)
        assertTrue("女双只有女生能加入", RoomJoinRules(makeRoom(event = PlayEvent.Women), me, Gender.Male, 4).genderBlocked)
        assertTrue("混双要先选性别", RoomJoinRules(makeRoom(event = PlayEvent.Mixed), me, Gender.Unspecified, 4).genderBlocked)
        assertTrue("满员只能候补", RoomJoinRules(makeRoom(participants = 4), me, Gender.Male, 4).joinsWaitlist)
        assertTrue("混双男生满了只能候补", RoomJoinRules(makeRoom(event = PlayEvent.Mixed, mixed = Room.MixedGoing(2, 0)), me, Gender.Male, 4).joinsWaitlist)
        assertFalse(RoomJoinRules(makeRoom(event = PlayEvent.Mixed, mixed = Room.MixedGoing(2, 0)), me, Gender.Female, 4).joinsWaitlist)
    }

    @Test
    fun publicRoomFilters() {
        val doubles = makeRoom()
        val singles = makeRoom(mode = GameMode.Singles, levels = 6..8).copy(id = "r2", tags = listOf(RoomTag.Competitive))
        val rooms = listOf(doubles, singles)
        assertEquals(listOf(singles), filterPublicRooms(rooms, GameMode.Singles, null, false, 4))
        assertEquals(listOf(singles), filterPublicRooms(rooms, null, RoomTag.Competitive, false, 4))
        assertEquals("适合我的水平", listOf(doubles), filterPublicRooms(rooms, null, null, true, 4))
    }

    @Test
    fun createRoomValidation() {
        val now = 1_800_000_000_000L
        val slot = TimeSlot.of(now + 86_400_000, now + 86_400_000, now + 86_400_000 + 7_200_000)
        assertNull("私密局可以不定时间和球馆", createRoomProblem(null, RoomVisibility.PrivateRoom, null, now))
        assertEquals("公开球局需要选择球馆", createRoomProblem(slot, RoomVisibility.PublicListing, null, now))
        val short = TimeSlot.of(slot.date, slot.startTime, slot.startTime + 1_800_000)
        assertEquals("时间不对先报时间", "至少需要 1 小时", createRoomProblem(short, RoomVisibility.PublicListing, null, now))
        assertEquals(GameMode.Singles, parseMode("singles"))
        assertEquals(GameMode.Doubles, parseMode("双打"))
        assertNull(parseMode(null))
    }

    @Test
    fun levelByEvent() {
        val woman = User(id = "w", nickname = "W", phone = "", selfReportedLevel = 5, selfReportedRating = 5.0, gender = Gender.Female)
        assertEquals("男女都能来：女子等级按低 1.5 级", 4, woman.level(null as PlayEvent?))
        assertEquals("女单女双按女子等级", 5, woman.level(PlayEvent.Women))
        assertEquals("混双不换算", 5, woman.level(PlayEvent.Mixed))
        val man = User(id = "m", nickname = "M", phone = "", selfReportedLevel = 5, selfReportedRating = 5.0, gender = Gender.Male)
        assertEquals(5, man.level(null as PlayEvent?))
    }

    @Test
    fun scheduleStartsFromRoomOrSuggestion() {
        val zone = java.time.ZoneId.systemDefault()
        val day = com.badie.app.models.startOfDay(1_800_000_000_000L, zone)
        val slot = slotOn(day, 19 * 60, 24 * 60)!!
        val schedule = initialSchedule(slot)
        assertEquals(19 * 60, schedule.start)
        assertEquals("结束在第二天 0 点：写成 24:00", 24 * 60, schedule.end)
        val suggested = initialSchedule(null, now = 1_800_000_000_000L)
        assertEquals("推荐时间打 2 小时", minOf(24 * 60, suggested.start + 120), suggested.end)
    }

    // MARK: 项目（iPhone 的 PlayEventTests）

    @Test
    fun eventChoicesFollowModeAndGender() {
        assertEquals(listOf(null, PlayEvent.Men), PlayEvent.choices(GameMode.Singles, Gender.Male))
        assertEquals(listOf(null, PlayEvent.Women, PlayEvent.Mixed), PlayEvent.choices(GameMode.Doubles, Gender.Female))
        assertEquals("没选性别只能不限", listOf(null), PlayEvent.choices(GameMode.Doubles, Gender.Unspecified))
        assertEquals("两个男生约单打就是男单", listOf(PlayEvent.Men), PlayEvent.choices(GameMode.Singles, Gender.Male, Gender.Male))
        assertEquals("男女约单打只能不限", listOf(null), PlayEvent.choices(GameMode.Singles, Gender.Male, Gender.Female))
        assertEquals(listOf(null, PlayEvent.Women), PlayEvent.choices(GameMode.Doubles, Gender.Female, Gender.Female))
        assertEquals(listOf(null, PlayEvent.Mixed), PlayEvent.choices(GameMode.Doubles, Gender.Female, Gender.Male))
        assertEquals(PlayEvent.Women, PlayEvent.ofServer(Gender.Female, false))
        assertEquals(PlayEvent.Mixed, PlayEvent.ofServer(null, true))
        assertNull("不限", PlayEvent.ofServer(null, false))
        assertEquals("女单", PlayEvent.Women.title(GameMode.Singles))
        assertEquals("男双", PlayEvent.Men.title(GameMode.Doubles))
        assertEquals("不限就写双打", GameMode.Doubles.title, (null as PlayEvent?).title(GameMode.Doubles))
    }
}
