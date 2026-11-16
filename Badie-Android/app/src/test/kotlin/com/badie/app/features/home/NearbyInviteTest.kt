package com.badie.app.features.home

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.DayCandidate
import com.badie.app.backend.NearbyApi
import com.badie.app.backend.RemoteRoom
import com.badie.app.models.Coordinate
import com.badie.app.models.Daypart
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.LobbyInvite
import com.badie.app.models.PlayWindow
import com.badie.app.models.Room
import com.badie.app.models.RoomCloseReason
import com.badie.app.models.RoomStatus
import com.badie.app.models.RoomVisibility
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 附近的人、邀请。iPhone 的 NearbyInviteTests 测的是演示模式的假数据，这里只搬里面的说法（InviteText），
 * 再测连服务器的那一路：参数、解码、卡片的合并和直接约的开始时间
 */
class NearbyInviteTest {
    private val server = FakeServer()
    private val me = TestSupport.USER_ID

    private fun room(fromMe: Boolean, rounds: Int, awaiting: String? = "x"): Room = Room(
        id = "r1", code = "", ownerId = if (fromMe) me else "other", mode = GameMode.Singles, visibility = RoomVisibility.PrivateRoom,
        participants = emptyList(), invitedUserIds = emptyList(), waitlist = emptyList(), levelRange = 1..9, tags = emptyList(), note = "",
        createdAt = 0, lastActivityAt = 0, status = RoomStatus.Open,
        invite = LobbyInvite(if (fromMe) me else "other", if (fromMe) "other" else me, awaiting, rounds, 0),
    )

    @Test
    fun titleSaysWhoProposedTheCurrentTime() {
        val incoming = room(fromMe = false, rounds = 0)
        assertEquals("阿杰约你打球", InviteText.title(incoming, me) { "阿杰" })
        assertEquals("发邀请的人看到的是自己约了谁", "你约了小林", InviteText.title(incoming, "other") { "小林" })
        val countered = room(fromMe = false, rounds = 1)
        assertEquals("阿杰想换个时间", InviteText.title(countered, "other") { "阿杰" })
        assertEquals("你想换个时间", InviteText.title(countered, me) { "阿杰" })
    }

    @Test
    fun inviteErrorsSayWhatHappened() {
        assertEquals("今天的 10 个用完了，明天再来", InviteText.error(RemoteError.Server("invite_limit")))
        assertEquals("在等对方回复", InviteText.error(RemoteError.Server("not_your_turn")))
        assertEquals("这天已经在等 3 个人回复了，有人回复再约。", DayCards.inviteError(RemoteError.Server("too_many_invites")))
        assertEquals("TA 的时间快到了，来不及约了。", DayCards.inviteError(RemoteError.Server("too_soon")))
        // 别的错误用通用的说法
        assertEquals(RemoteError.Server("suspended").message, InviteText.error(RemoteError.Server("suspended")))
    }

    @Test
    fun inviteStartIsAtLeastHalfAnHourAwayOnTheHalfHour() {
        val now = 1_800_000_000_000L // 整点后 20 分钟（UTC 08:00 + 0）
        val later = DayCandidate("t", "u", GameMode.Singles, false, now + 3 * 3_600_000L, now + 5 * 3_600_000L, 0, emptyList())
        assertEquals("离得远就用 TA 的开始时间", later.startsAt, DayCards.inviteStart(later, now))
        val soon = later.copy(startsAt = now - 3_600_000L)
        val start = DayCards.inviteStart(soon, now)
        assertTrue(start >= now + 30 * 60_000L)
        assertEquals(0L, start % 1_800_000L)
        assertTrue(start - (now + 30 * 60_000L) < 1_800_000L)
    }

    @Test
    fun mergeKeepsTheCurrentCardAndSkipsSeenOnes() {
        val merged = DayCards.merge(listOf("a", "b", "c"), listOf("b", "d", "e"), seen = setOf("e"), focused = "a") { it }
        assertEquals(listOf("a", "b", "d"), merged)
        val counts = DayCards.venueCounts(listOf(listOf(DayCandidate.Place("v1", "B")), listOf(DayCandidate.Place("v1", "B"), DayCandidate.Place("v2", "A"))))
        assertEquals(listOf("v1" to 2, "v2" to 1), counts.map { it.venue.id to it.count })
    }

    @Test
    fun nearbyPlayersDecodeCardsAndPeople() = runTest {
        server.on(
            "POST /rest/v1/rpc/nearby_players",
            """[{"user":{"id":"u1","nickname":"阿杰","tag":12,"rating":4.33,"gender":"female","recent_no_shows":1,"card_color":"sky","preferred_mode":"doubles",
                "usual_times":[{"weekday":7,"start":"14:00","end":"18:00"}]},"venues":[{"id":"v1","name":"圣盖博球馆","km":3.2}],"shared_venues":1,"is_friend":false,"friend_request":"received"}]""",
        )
        val api = NearbyApi(TestSupport.backend(server, TestSupport.session()))
        val (cards, users) = api.nearbyPlayers(Coordinate.fallbackCenter, 10.0)
        assertEquals(1, server.requests.size)
        assertEquals(10.0, server.json(0)["p_radius_km"]?.jsonPrimitive?.double)
        val card = cards.single()
        assertEquals(GameMode.Doubles, card.preferredMode)
        assertEquals(1, card.recentNoShows)
        assertEquals(3.2, card.venues.single().km)
        assertEquals(14 * 60, card.usualTimes.single().startMinutes)
        assertEquals(com.badie.app.backend.FriendRequestState.Received, card.friendRequest)
        val user = users.single()
        assertEquals(Gender.Female, user.gender)
        assertEquals(12, user.tag)
        assertEquals(com.badie.app.models.CardColor.Sky, user.cardColor)
        assertEquals(4, user.displayLevel)
    }

    @Test
    fun inviteSendsTheExactWindow() = runTest {
        server.on("POST /rest/v1/rpc/invite_player", """{"room_id":"r9","remaining":7}""")
        val api = NearbyApi(TestSupport.backend(server, TestSupport.session()))
        val start = 1_800_000_000_000L
        val window = PlayWindow(start, start + 90 * 60_000L, durationMinutes = 90)
        val result = api.invitePlayer("u1", "v1", window, GameMode.Doubles)
        assertEquals("r9", result.roomId)
        assertEquals(7, result.remaining)
        val body = server.json(0)
        assertEquals("doubles", body["p_mode"]?.jsonPrimitive?.content)
        assertEquals(90, body["p_duration"]?.jsonPrimitive?.int)
        assertEquals("2027-01-15T08:00:00Z", body["p_window_start"]?.jsonPrimitive?.content)
        assertEquals("2027-01-15T09:30:00Z", body["p_window_end"]?.jsonPrimitive?.content)
    }

    @Test
    fun invitesDecodeIntoRooms() = runTest {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        server.on(
            "POST /rest/v1/rpc/nearby_invites",
            """[{"id":"r1","mode":"singles","visibility":"private","status":"open","level_min":1,"level_max":9,"tags":[],"note":"","going":1,"waitlist":0,
                "owner":{"id":"u1","nickname":"阿杰","rating":4.0},"venue":{"id":"v1","name":"圣盖博球馆","lat":34.1,"lon":-118.1,"country":"US","pricing":{"per_person":12}},
                "time_set":false,"window_start":"2026-11-21T22:00:00+00","window_end":"2026-11-22T02:00:00+00","duration_minutes":120,"daypart":"afternoon",
                "invite":{"from":{"id":"u1","nickname":"阿杰","rating":4.0,"usual_times":[{"weekday":7,"start":"14:00","end":"18:00"}]},
                          "to":{"id":"$me","nickname":"Alex","rating":4.0},"awaiting_id":"$me","rounds":0,"answer_by":"2026-11-20T00:00:00+00"}},
               {"id":"r2","mode":"doubles","visibility":"private","status":"closed","closed_reason":"declined","level_min":1,"level_max":9,"going":2,"waitlist":0,
                "owner":{"id":"$me","nickname":"Alex","rating":4.0},"starts_at":"2026-11-21T22:00:00+00","ends_at":"2026-11-22T00:00:00+00"}]""",
        )
        val result = NearbyApi(backend).nearbyInvites()
        val (first, second) = result.rooms
        assertEquals(me, first.invite?.awaitingId)
        assertEquals("u1", first.invite?.fromId)
        assertEquals(Daypart.Afternoon, first.window?.daypart)
        assertNull("没定时间的邀请没有 slot", first.slot)
        assertEquals("圣盖博球馆", first.court?.name)
        assertTrue(first.status.isOpen)
        assertEquals(listOf("u1"), result.users.map { it.id })
        assertEquals(1, result.usualTimes["u1"]?.size)
        assertEquals(RoomStatus.Closed(RoomCloseReason.Declined), second.status)
        assertNull("定好时间的不是窗口", second.window)
        assertEquals(2, second.participants.size)
        assertFalse(second.participants[1].userId == me)
        assertEquals(RemoteRoom.window(true, 1, 2, null, 120), null)
    }
}
