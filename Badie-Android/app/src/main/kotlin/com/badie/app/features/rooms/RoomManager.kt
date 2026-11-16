package com.badie.app.features.rooms

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.RemoteRoom
import com.badie.app.backend.RoomDraft
import com.badie.app.backend.RoomMapping
import com.badie.app.backend.createRoom
import com.badie.app.backend.findGroup
import com.badie.app.backend.inviteToRoom
import com.badie.app.backend.joinRoom
import com.badie.app.backend.joinRoomCode
import com.badie.app.backend.leaveRoom
import com.badie.app.backend.myRooms
import com.badie.app.backend.myFriends
import com.badie.app.backend.removeRoomMember
import com.badie.app.backend.roomPage
import com.badie.app.backend.roomsNear
import com.badie.app.backend.startRoom
import com.badie.app.backend.updateRoom
import com.badie.app.features.games.GameBook
import com.badie.app.l10n.L10n.tr
import com.badie.app.location.LocationProvider
import com.badie.app.models.Coordinate
import com.badie.app.models.Room
import com.badie.app.models.RoomParticipant
import com.badie.app.models.RoomStatus
import com.badie.app.models.TimeSlot
import com.badie.app.models.UserPreferences
import com.badie.app.models.Venue
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 球局（房间）和我的球局。对应 iPhone 的 Managers/RoomManager.swift。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改。
 * 我的球局（iPhone 在 MatchManager 里）和待评价在 [book]，SurveyManager 也用同一份
 */
@Stable
class RoomManager(private val context: ManagerContext, private val now: () -> Long = System::currentTimeMillis) {
    private val backend get() = context.backend

    /** 页面关掉以后还要接着做完的事（交了赛果再跳转这类）在这里跑 */
    val scope: kotlinx.coroutines.CoroutineScope get() = context.scope

    val book: GameBook = GameBook.of(context.backend).also { book -> context.android?.let { book.android = it.applicationContext } }

    /** 拉到过的房间（按 ID） */
    private val rooms = mutableStateMapOf<String, Room>()

    /** 附近公开局的 ID（按服务器给的顺序） */
    private var nearbyIds by mutableStateOf<List<String>>(emptyList())
    private var nearbyAt: Pair<Coordinate, Long>? = null

    /** 被移出或房间关闭时的提示（界面弹出后清掉） */
    var notice by mutableStateOf<String?>(null)

    /** 附近范围（公里） */
    var radiusKm: Double = UserPreferences.DEFAULT_TRAVEL_RADIUS

    private var owner: String? = null
    private val refreshing = Mutex()

    private val me: String? get() = backend.currentUser?.id

    /** 我参与（或在候补中、被邀请）的开放房间，按开始时间排 */
    val myRooms: List<Room>
        get() {
            val me = me ?: return emptyList()
            return rooms.values
                .filter { it.status.isOpen && (it.contains(me) || it.isWaitlisted(me) || me in it.invitedUserIds) }
                .sortedBy { it.slot?.startTime ?: it.createdAt }
        }

    /** 附近的公开球局（开放的） */
    val publicRooms: List<Room> get() = nearbyIds.mapNotNull { rooms[it] }.filter { it.status.isOpen }

    fun room(id: String): Room? = rooms[id]

    // MARK: 刷新

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调）。球局和待评价也一起 */
    suspend fun refresh() {
        book.refresh(GameBook.SHARED_REFRESH_MILLIS)
        refreshRooms()
        nearbyAt = null
        loadNearby()
    }

    /** 我在里面（或候补、受邀）的房间；不在列表里的旧房间再拉一次，看是开局了还是关了 */
    suspend fun refreshRooms() = refreshing.withLock {
        val me = me
        if (me != owner) {
            owner = me
            rooms.clear()
            nearbyIds = emptyList()
            nearbyAt = null
        }
        if (me == null) return@withLock
        val ids = backend.myRooms().map { it.id }.toSet()
        val stale = rooms.values.filter { room ->
            room.id !in ids && room.status.isOpen && (room.contains(me) || room.isWaitlisted(me) || me in room.invitedUserIds)
        }
        for (id in ids) load(id)
        // 旧房间一个个拉：一个出错不影响别的
        for (room in stale) {
            try {
                load(room.id)
            } catch (_: RemoteError) {
            }
        }
    }

    /** 拉一个房间的详情；看不到了（私密局、被屏蔽）就从缓存删掉。我在里面的房间被别人关掉（或我被移出）时提示一下 */
    suspend fun load(roomId: String) {
        val me = me ?: return
        val detail = backend.roomPage(roomId)
        if (detail == null) {
            rooms.remove(roomId)
            return
        }
        val before = rooms[roomId]
        val after = cache(detail, me)
        if (before == null || !before.status.isOpen || before.ownerId == me) return
        val wasIn = before.contains(me) || before.isWaitlisted(me)
        val status = after.status
        if (status is RoomStatus.Closed && wasIn) {
            notice = tr("房间 %@：%@", before.code, status.reason.message)
        } else if (status.isOpen && wasIn && !after.contains(me) && !after.isWaitlisted(me)) {
            notice = tr("你已被移出房间 %@", before.code)
        }
    }

    /** 附近的公开局：同一位置 60 秒内只拉一次 */
    suspend fun loadNearby(center: Coordinate? = null) {
        val me = me ?: return
        val where = center ?: center()
        val last = nearbyAt
        if (last != null && now() - last.second < 60_000 && last.first.distanceKm(where) < 2) return
        nearbyAt = where to now()
        val found = backend.roomsNear(where, radiusKm)
        for (room in found) cache(room, me)
        nearbyIds = found.map { it.id }
    }

    /** 找附近的球局从哪找：当前位置，没有就用资料里的位置、第一家常去球馆，再没有用默认的中心 */
    suspend fun center(): Coordinate {
        val android = context.android
        val located = if (android != null) {
            try {
                LocationProvider(android).takeIf { it.isAuthorized }?.current()
            } catch (_: SecurityException) {
                null
            }
        } else {
            null
        }
        return located ?: backend.currentUser?.location
            ?: backend.favoriteVenueIds.firstNotNullOfOrNull { backend.venue(it)?.location }
            ?: Coordinate.fallbackCenter
    }

    private fun cache(info: RemoteRoom, me: String): Room {
        val venue = info.venue?.let { it.venue(backend.venue(it.id)) }
        val room = RoomMapping.room(info, me, rooms[info.id], venue, now()) { id -> book.user(id) }
        // 房间里的人也记下来（球局页、邀请名单按 ID 找人）
        for (participant in room.participants + room.waitlist) {
            if (!participant.isAnonymous && book.user(participant.userId) == null) {
                book.remember(
                    com.badie.app.models.User(
                        id = participant.userId, nickname = participant.nickname, phone = "",
                        selfReportedLevel = participant.skillLevel, selfReportedRating = participant.skillRating, avatar = participant.avatar,
                    ),
                )
            }
        }
        rooms[info.id] = room
        return room
    }

    // MARK: 操作

    suspend fun create(draft: RoomDraft): Room {
        val id = backend.createRoom(draft)
        return reloaded(id)
    }

    /** 凭房间码或群号加入的结果：群号是 Group，房间是 Entered */
    sealed interface JoinResult {
        data class Group(val id: String) : JoinResult
        data class Entered(val room: Room) : JoinResult
    }

    /** 正式后端的房间码和群号同一套字母：先看是不是群号（打开球群页面，在那里加入），不是再当房间码加入 */
    suspend fun join(code: String): JoinResult {
        val group = try {
            backend.findGroup(code)
        } catch (_: RemoteError.Server) {
            null
        }
        if (group != null) return JoinResult.Group(group)
        return JoinResult.Entered(reloaded(backend.joinRoomCode(code)))
    }

    suspend fun joinPublic(room: Room): Room {
        backend.joinRoom(room.id)
        return reloaded(room.id)
    }

    suspend fun leave(room: Room) {
        backend.leaveRoom(room.id)
        // 先在缓存里退出，刷新时就不会当成“被移出”
        val me = me
        rooms[room.id]?.let { current ->
            rooms[room.id] = current.copy(
                participants = current.participants.filter { it.userId != me },
                waitlist = current.waitlist.filter { it.userId != me },
            )
        }
        load(room.id)
    }

    suspend fun kick(participant: RoomParticipant, room: Room) {
        backend.removeRoomMember(room.id, participant.userId)
        load(room.id)
    }

    suspend fun invite(userIds: List<String>, room: Room) {
        backend.inviteToRoom(room.id, userIds)
        load(room.id)
    }

    suspend fun updateDetails(room: Room, court: Venue?, slot: TimeSlot?) {
        backend.updateRoom(room.id, court, slot)
        load(room.id)
    }

    /** 开局：服务器生成正式球局，拉一次球局列表，返回球局 ID */
    suspend fun start(room: Room): String {
        val gameId = backend.startRoom(room.id)
        load(room.id)
        try {
            book.refresh()
        } catch (_: RemoteError) {
        }
        return gameId
    }

    /** 我的球友（邀请进房间时选）。TODO：球友列表归 FriendManager，搬好后改用那边的 */
    suspend fun friends(): List<com.badie.app.models.User> = backend.myFriends().map { person ->
        com.badie.app.backend.GameMapping.player(
            com.badie.app.backend.RemotePlayer(person.id, person.nickname, person.rating, 0, false), book.user(person.id),
        )
    }

    private suspend fun reloaded(id: String): Room {
        load(id)
        return rooms[id] ?: throw RemoteError.Server("room_not_found")
    }
}
