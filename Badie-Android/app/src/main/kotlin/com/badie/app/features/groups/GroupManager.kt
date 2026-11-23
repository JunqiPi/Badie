package com.badie.app.features.groups

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.BackendError
import com.badie.app.backend.GroupsApi
import com.badie.app.backend.RemoteGroupActivity
import com.badie.app.backend.RemoteGroupDetail
import com.badie.app.backend.RemoteGroupSummary
import com.badie.app.backend.RemoteGroupVenue
import com.badie.app.backend.RemoteSchedule
import com.badie.app.features.social.SocialCache
import com.badie.app.l10n.L10n.tr
import com.badie.app.features.venues.LocationManager
import com.badie.app.models.Coordinate
import com.badie.app.models.Gender
import com.badie.app.models.GroupActivity
import com.badie.app.models.GroupGuest
import com.badie.app.models.GroupLateCancel
import com.badie.app.models.GroupSchedule
import com.badie.app.models.GroupSession
import com.badie.app.models.GuestSignup
import com.badie.app.models.PlayGroup
import com.badie.app.models.Room
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenueSource
import com.badie.app.models.VenueStatus
import com.badie.app.models.zoned
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Locale

/** 报名一场的结果：报上了，或者进了候补第几位 */
sealed interface SignupResult {
    data object Confirmed : SignupResult
    data class Waitlisted(val position: Int) : SignupResult
}

/**
 * 球群（固定局）。对应 iPhone 的 Managers/SocialManagers.swift 的 GroupManager，
 * 和 MockBackend+RemoteGroups.swift、MockBackend+Groups.swift 里连正式后端的部分。
 * 我的球群和场次每 15 秒拉一次；别的球群在打开、看附近、输群号时按需拉
 */
@Stable
class GroupManager(
    private val context: ManagerContext,
    /** 位置和附近范围（和 iPhone 一样看 LocationManager） */
    val location: LocationManager = LocationManager(context),
) {
    private val api = GroupsApi(context.backend.remote)
    private val cache = SocialCache.of(context.backend)
    private val now: () -> Long = System::currentTimeMillis

    private val groups = mutableStateMapOf<String, PlayGroup>()
    private val sessionMap = mutableStateMapOf<String, GroupSession>()
    private val activities = mutableStateMapOf<String, GroupActivity>()
    /** 球群所在的球馆（服务器只给名字、城市、时区） */
    private val venues = mutableStateMapOf<String, Venue>()
    private val loadedAt = HashMap<String, Long>()

    /** 附近的球群：在哪找的、找到哪些、什么时候 */
    private var nearby by mutableStateOf<Triple<Coordinate, List<String>, Long>?>(null)
    private var nearbyRadius = 0.0

    /** 变化计数（球群详情等页面据此刷新） */
    var revision by mutableIntStateOf(0)
        private set

    private var owner: String? = null
    private var polling: Job? = null

    val currentUserId: String? get() = cache.me

    /** 我加入的球群（按名字排） */
    val myGroups: List<PlayGroup>
        get() {
            val me = cache.me ?: return emptyList()
            return groups.values.filter { it.isMember(me) }.sortedBy { it.name }
        }

    /** 我报名或候补的未来场次 */
    val mySessions: List<GroupSession>
        get() {
            val me = cache.me ?: return emptyList()
            val time = now()
            return sessionMap.values.filter { it.isUpcoming(time) && it.status(me) != GroupSession.Status.None }.sortedBy { it.slot.startTime }
        }

    fun group(id: String): PlayGroup? = groups[id]

    fun session(id: String): GroupSession? = sessionMap[id]

    fun activity(groupId: String): GroupActivity = activities[groupId] ?: GroupActivity(0, 0.0)

    /** 未来的场次（最近的在前） */
    fun sessions(groupId: String): List<GroupSession> {
        val time = now()
        return sessionMap.values.filter { it.groupId == groupId && it.isUpcoming(time) }.sortedBy { it.slot.startTime }
    }

    /** 球群的主球馆：读过详情的用完整资料（有地址），没读过的用服务器给的名字 */
    fun venue(group: PlayGroup): Venue? = venue(group.venueId)

    fun venue(id: String): Venue? = context.backend.venue(id) ?: venues[id]

    /** 主球馆以外的球馆（按顺序） */
    fun otherVenues(group: PlayGroup): List<Venue> = group.venueIds.drop(1).mapNotNull(::venue)

    /** 球群有几个球馆时，这一场在哪个球馆；只有一个球馆时是 null（界面和以前一样） */
    fun sessionVenueName(session: GroupSession): String? {
        val group = groups[session.groupId]?.takeIf { it.venueIds.size > 1 } ?: return null
        return venue(session.effectiveVenueId(group))?.name
    }

    fun user(id: String): User? = cache.user(id)

    /** 附近的球群（按近 30 天场次数排），不含已加入的由页面自己去掉 */
    fun nearbyGroups(): List<PlayGroup> = sortedByActivity(nearestGroups())

    /** 附近的球群，近的在前（服务器按最近的那个球馆排好；发现页的“球群”） */
    fun nearestGroups(): List<PlayGroup> = nearby?.second.orEmpty().mapNotNull { groups[it] }

    /** 这家球馆的球群（群里任何一个球馆是这家就算，按活跃度排）；先调 [loadAtVenue] 拉一次 */
    fun groups(atVenue: String): List<PlayGroup> = sortedByActivity(groups.values.filter { atVenue in it.venueIds })

    private fun sortedByActivity(list: List<PlayGroup>): List<PlayGroup> =
        list.sortedWith(compareByDescending<PlayGroup> { activity(it.id).sessionsLast30Days }.thenBy { it.name })

    // MARK: 拉取

    private fun syncAccount(): String? {
        cache.syncAccount()
        val me = cache.me
        if (me != owner) {
            owner = me
            groups.clear()
            sessionMap.clear()
            activities.clear()
            nearby = null
            loadedAt.clear()
            revision += 1
        }
        return me
    }

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() {
        val me = syncAccount() ?: return
        val mine = api.myGroups()
        for (summary in mine) loadGroup(summary.id)
        // 已经不在的群：从缓存里去掉成员身份
        val ids = mine.map { it.id }.toSet()
        for ((id, group) in groups.toMap()) {
            if (id !in ids && (group.isMember(me) || group.isPending(me))) {
                groups[id] = group.copy(
                    memberIds = group.memberIds - me, organizerIds = group.organizerIds - me, pendingIds = group.pendingIds - me,
                )
            }
        }
        revision += 1
    }

    /** 拉一个球群的详情；不存在（或被屏蔽）时从缓存删掉 */
    suspend fun loadGroup(groupId: String) {
        val me = syncAccount() ?: return
        loadedAt[groupId] = now()
        val detail = api.groupPage(groupId)
        if (detail == null) {
            groups.remove(groupId)
        } else {
            cacheGroup(detail, me)
        }
        revision += 1
    }

    /** 打开球群页：缓存里没有或超过 60 秒，在后台重拉 */
    fun refreshIfStale(groupId: String) {
        if (now() - (loadedAt[groupId] ?: 0) <= 60_000) return
        loadedAt[groupId] = now()
        context.scope.launch {
            try {
                loadGroup(groupId)
            } catch (_: RemoteError) {
            }
        }
    }

    /** 附近的球群（同一位置 60 秒内只拉一次） */
    suspend fun loadNearby(center: Coordinate, radiusKm: Double) {
        val me = syncAccount() ?: return
        nearby?.let { (place, _, at) -> if (now() - at < 60_000 && place.distanceKm(center) < 2 && nearbyRadius == radiusKm) return }
        nearby = Triple(center, nearby?.second.orEmpty(), now())
        nearbyRadius = radiusKm
        val found = api.groupsNear(center, radiusKm)
        for (summary in found) cacheGroup(summary, me)
        nearby = Triple(center, found.map { it.id }, now())
        revision += 1
    }

    /** 球馆页：拉这家球馆附近 5 公里的球群（不影响“附近的球群”那份列表） */
    suspend fun loadAtVenue(venue: Venue) {
        val me = syncAccount() ?: return
        for (summary in api.groupsNear(venue.location, 5.0)) cacheGroup(summary, me)
        revision += 1
    }

    /** 看附近用的位置：开了定位用当前位置，否则用第一家常去球馆，都没有就用默认的地方 */
    fun currentCenter(): Coordinate {
        location.currentLocation?.let { return it }
        context.backend.favoriteVenueIds.firstNotNullOfOrNull { context.backend.venue(it) }?.let { return it.location }
        return Coordinate.fallbackCenter
    }

    /** 附近范围（公里） */
    val radiusKm: Double get() = location.preferences.travelRadiusKm

    // MARK: 操作（都等服务器）

    /** venueId 是主球馆，otherVenueIds 是其他球馆（一共最多 5 个） */
    suspend fun create(
        name: String, venueId: String, schedules: List<GroupSchedule>, levelRange: IntRange, joinPolicy: PlayGroup.JoinPolicy,
        summary: String, audience: Gender? = null, coached: Boolean = false, otherVenueIds: List<String> = emptyList(),
    ): PlayGroup {
        val id = api.create(name, listOf(venueId) + otherVenueIds, schedules, levelRange, joinPolicy, summary, audience, coached)
        loadGroup(id)
        return groups[id] ?: throw BackendError(tr("没有找到这个球群"))
    }

    /** venueIds 为 null 时球馆不变 */
    suspend fun update(
        groupId: String, name: String, schedules: List<GroupSchedule>, levelRange: IntRange, joinPolicy: PlayGroup.JoinPolicy,
        summary: String, coached: Boolean, venueIds: List<String>? = null,
    ) {
        api.update(groupId, name, schedules, levelRange, joinPolicy, summary, coached, venueIds)
        loadGroup(groupId)
    }

    suspend fun disband(groupId: String) {
        api.disband(groupId)
        groups.remove(groupId)
        refresh()
        cache.refreshThreads?.invoke()
    }

    /** 输群号找球群 */
    suspend fun find(code: String): PlayGroup? = try {
        api.find(Room.normalize(code))?.let { id ->
            loadGroup(id)
            groups[id]
        }
    } catch (_: RemoteError) {
        null
    }

    suspend fun join(groupId: String): PlayGroup {
        api.join(groupId)
        loadGroup(groupId)
        return groups[groupId] ?: throw BackendError(tr("没有找到这个球群"))
    }

    suspend fun leave(groupId: String) {
        api.leave(groupId)
        loadGroup(groupId)
        cache.refreshThreads?.invoke()
    }

    suspend fun approve(userId: String, groupId: String) {
        api.approve(userId, groupId)
        loadGroup(groupId)
    }

    suspend fun signUp(sessionId: String): SignupResult {
        val groupId = sessionMap[sessionId]?.groupId ?: throw BackendError(tr("这一场已经结束或取消了"))
        api.signUp(sessionId)
        loadGroup(groupId)
        val me = cache.me
        val session = sessionMap[sessionId]
        if (me == null || session == null) throw BackendError(tr("这一场已经结束或取消了"))
        return when (val status = session.status(me)) {
            is GroupSession.Status.Waitlisted -> SignupResult.Waitlisted(status.position)
            else -> SignupResult.Confirmed
        }
    }

    suspend fun cancelSignup(sessionId: String) {
        val groupId = sessionMap[sessionId]?.groupId ?: throw BackendError(tr("这一场已经结束或取消了"))
        api.cancelSignup(sessionId)
        loadGroup(groupId)
    }

    suspend fun cancelSession(sessionId: String) {
        val groupId = sessionMap[sessionId]?.groupId ?: throw BackendError(tr("这一场已经结束或取消了"))
        api.cancelSession(sessionId)
        loadGroup(groupId)
    }

    /** 允许不注册的人报名；limit 为 null 是每场名额的一半 */
    suspend fun setGuestSignup(groupId: String, allowed: Boolean, limit: Int?) {
        api.setGuestSignup(groupId, allowed, limit)
        loadGroup(groupId)
    }

    /** 换一个报名链接，旧的马上失效 */
    suspend fun resetGuestLink(groupId: String) {
        api.resetGuestLink(groupId)
        loadGroup(groupId)
    }

    /** 组织者把访客移出某一场（guestId 是那一行报名的 id） */
    suspend fun removeGuest(guestId: String, sessionId: String) {
        val groupId = sessionMap[sessionId]?.groupId ?: throw BackendError(tr("这一场已经结束或取消了"))
        api.removeGuest(guestId)
        loadGroup(groupId)
    }

    // MARK: 服务器数据 → 本地模型

    internal fun cacheGroup(summary: RemoteGroupSummary, me: String) {
        cacheGroup(
            summary.id, summary.name, summary.summary, summary.levelMin..maxOf(summary.levelMin, summary.levelMax), summary.joinPolicy,
            summary.gender, summary.coached, summary.venue, summary.venues, summary.schedules.orEmpty(), summary.activity, summary.myRole,
            inviteCode = null, members = null, pending = null, me = me,
        )
    }

    internal fun cacheGroup(detail: RemoteGroupDetail, me: String) {
        cacheGroup(
            detail.id, detail.name, detail.summary, detail.levelMin..maxOf(detail.levelMin, detail.levelMax), detail.joinPolicy,
            detail.gender, detail.coached, detail.venue, detail.venues, detail.schedules.orEmpty(), detail.activity, detail.myRole,
            detail.inviteCode, detail.members, detail.pending, me,
            guestSignup = detail.guestsAllowed?.let { GuestSignup(it, detail.guestLimit, detail.guestCode) },
        )
        val group = groups[detail.id] ?: return
        val zone = venue(group)?.zone ?: java.time.ZoneId.systemDefault()
        // 这个群的场次以服务器为准
        sessionMap.keys.filter { sessionMap[it]?.groupId == detail.id }.forEach(sessionMap::remove)
        for (session in detail.sessions.orEmpty()) {
            // 访客不是用户：记在这一场的名单里，不进用户缓存
            val guests = mutableMapOf<String, GroupGuest>()
            for (player in session.players.orEmpty()) {
                if (player.guest == true) {
                    guests[player.id] = GroupGuest(player.nickname, (player.signedUpAt ?: session.startsAt).toEpochMilli())
                } else {
                    cache.cache(player.id, player.nickname, null)
                }
            }
            val signedUp = session.players?.filter { !it.waitlisted }?.map { it.id }?.toMutableList()
                ?: (0 until session.confirmed).map { "spot-${session.id}-$it" }.toMutableList()
            val waitlist = session.players?.filter { it.waitlisted }?.map { it.id }?.toMutableList()
                ?: (0 until session.waitlist).map { "wait-${session.id}-$it" }.toMutableList()
            // 看不到名单时（非成员）用占位，只保证人数和我的位置对
            if (session.myStatus == "confirmed" && me !in signedUp) {
                if (signedUp.isEmpty()) signedUp.add(me) else signedUp[signedUp.size - 1] = me
            }
            val status = session.myStatus
            if (status != null && status.startsWith("waitlisted") && me !in waitlist) {
                val position = status.split(":").last().toIntOrNull() ?: waitlist.size
                val index = (position - 1).coerceIn(0, waitlist.size)
                if (index < waitlist.size) waitlist[index] = me else waitlist.add(me)
            }
            val start = session.startsAt.toEpochMilli()
            val local = start.zoned(zone)
            val weekday = local.dayOfWeek.value % 7 + 1
            val minutes = local.hour * 60 + local.minute
            // 同一时间在不同球馆的两个场次：按球馆分开
            val sameTime = group.schedules.filter { it.weekday == weekday && it.startMinutes == minutes }
            val schedule = sameTime.firstOrNull { session.venue == null || it.effectiveVenueId(group) == session.venue } ?: sameTime.firstOrNull()
            sessionMap[session.id] = GroupSession(
                id = session.id, groupId = detail.id, scheduleId = schedule?.id ?: "",
                slot = TimeSlot.of(start, start, session.endsAt.toEpochMilli(), zone),
                capacity = session.capacity, signedUp = signedUp, waitlist = waitlist, isCancelled = session.cancelled,
                venueId = session.venue ?: schedule?.effectiveVenueId(group), guests = guests.ifEmpty { null },
                lateCancels = session.lateCancels?.map { GroupLateCancel(it.nickname, it.guest) }, price = session.price,
            )
        }
    }

    private fun cacheGroup(
        id: String, name: String, summary: String?, levels: IntRange, joinPolicy: String, audience: String?, coached: Boolean?,
        place: RemoteGroupVenue, places: List<RemoteGroupVenue>?, schedules: List<RemoteSchedule>, activity: RemoteGroupActivity,
        myRole: String?, inviteCode: String?,
        members: List<RemoteGroupDetail.Member>?, pending: List<RemoteGroupDetail.Member>?, me: String,
        // 列表里的球群信息不带访客设置：沿用上次球群页拿到的
        guestSignup: GuestSignup? = groups[id]?.guestSignup,
    ) {
        val existing = groups[id]
        for (member in members.orEmpty() + pending.orEmpty()) cache.cache(member.id, member.nickname, member.rating)
        // 本地还没有的球馆先记个名字（主球馆在前）
        val courts = listOf(place) + places.orEmpty().filter { it.id != place.id }
        for (court in courts) {
            if (context.backend.venue(court.id) != null || venues[court.id] != null) continue
            venues[court.id] = Venue(
                id = court.id, name = court.name, lat = 0.0, lon = 0.0, city = court.city,
                countryCode = Locale.getDefault().country.ifEmpty { "US" }, timeZoneId = court.tz ?: place.tz,
                source = VenueSource.Player, status = VenueStatus.Unconfirmed,
            )
        }
        val joined = myRole in listOf("owner", "organizer", "member")
        val organizers = members?.filter { it.role == "owner" || it.role == "organizer" }?.map { it.id }
            ?: if (myRole == "owner" || myRole == "organizer") listOf(me) else existing?.organizerIds.orEmpty()
        var memberIds = members?.map { it.id } ?: existing?.memberIds.orEmpty()
        if (joined && me !in memberIds) memberIds = memberIds + me
        if (!joined) memberIds = memberIds - me
        var pendingIds = pending?.map { it.id } ?: existing?.pendingIds.orEmpty().filter { it != me }
        if (myRole == "pending") pendingIds = pendingIds + me
        val group = PlayGroup(
            id = id, name = name, venueId = place.id,
            ownerId = members?.firstOrNull { it.role == "owner" }?.id ?: if (myRole == "owner") me else existing?.ownerId ?: "",
            organizerIds = organizers, memberIds = memberIds, pendingIds = pendingIds, summary = summary ?: "",
            levelRange = levels,
            schedules = schedules.mapIndexed { index, schedule ->
                GroupSchedule(
                    "$id-$index", schedule.weekday + 1, schedule.start, schedule.end, schedule.capacity,
                    schedule.fee?.takeIf { it.isNotEmpty() }, venueId = schedule.venue, price = schedule.price,
                )
            },
            joinPolicy = if (joinPolicy == "approval") PlayGroup.JoinPolicy.Approval else PlayGroup.JoinPolicy.Open,
            inviteCode = inviteCode ?: existing?.inviteCode ?: "", createdAt = existing?.createdAt ?: now(),
            audience = audience?.let { value -> Gender.entries.firstOrNull { it.rawValue == value } }, coached = coached,
            otherVenueIds = courts.drop(1).map { it.id }.ifEmpty { null },
            guestSignup = guestSignup,
        )
        if (groups[id] != group) groups[id] = group
        activities[id] = GroupActivity(activity.sessions, activity.average)
    }

    // MARK: 轮询

    /** 没有实时推送：每 15 秒拉一次我的球群（回到前台时开始，退到后台时停） */
    fun startPolling() {
        if (polling?.isActive == true) return
        polling = context.scope.launch {
            while (isActive) {
                try {
                    refresh()
                } catch (_: RemoteError) {
                    // 网络问题：下次再拉
                }
                delay(POLL_MILLIS)
            }
        }
    }

    fun stopPolling() {
        polling?.cancel()
        polling = null
    }

    companion object {
        const val POLL_MILLIS = 15_000L
    }
}
