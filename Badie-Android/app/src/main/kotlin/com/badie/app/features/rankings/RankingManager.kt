package com.badie.app.features.rankings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.badie.app.backend.Backend
import com.badie.app.backend.RankingsApi
import com.badie.app.features.venues.LocationManager
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Challenge
import com.badie.app.models.ChallengeStatus
import com.badie.app.models.Coordinate
import com.badie.app.models.CountryInfo
import com.badie.app.models.DateInterval
import com.badie.app.models.DateText
import com.badie.app.models.Gender
import com.badie.app.models.LevelBracket
import com.badie.app.models.Rankings
import com.badie.app.models.ReportReason
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenueSource
import com.badie.app.models.VenueStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.util.WeakHashMap

// MARK: - 我在周榜上的位置（周榜页、首页共用）

data class WeeklyStanding(
    val points: Int,
    val games: Int,
    val wins: Int,
    /** 在榜上的名次；达到门槛但在前 50 名外时为 null */
    val rank: Int?,
    val isQualified: Boolean,
    /** 不能上榜的原因（关闭了上榜、注册未满 7 天） */
    val absenceReason: String?,
    /** 还要再打几场才达到上榜门槛 */
    val gamesNeeded: Int,
    val isCurrentWeek: Boolean,
) {
    /** 首页、置顶卡片上的一句话 */
    val summary: String
        get() = when {
            absenceReason != null -> absenceReason
            rank != null -> tr("第 %lld 名 · %lld 分", rank, points)
            isQualified -> tr("%lld 分 · 暂未进前 %lld 名", points, Rankings.BOARD_SIZE)
            !isCurrentWeek -> tr("上周没有上榜")
            else -> tr("还差 %lld 场上榜", gamesNeeded)
        }

    companion object {
        fun of(score: Rankings.WeeklyScore, userId: String, entries: List<Rankings.Entry>, absenceReason: String?, isCurrentWeek: Boolean) =
            WeeklyStanding(
                points = score.points,
                games = score.games,
                wins = score.wins,
                rank = entries.firstOrNull { it.userId == userId }?.rank,
                isQualified = score.games >= Rankings.WEEKLY_MINIMUM_GAMES && score.opponents >= Rankings.WEEKLY_MINIMUM_OPPONENTS,
                absenceReason = absenceReason,
                gamesNeeded = maxOf(1, Rankings.WEEKLY_MINIMUM_GAMES - score.games, Rankings.WEEKLY_MINIMUM_OPPONENTS - score.opponents),
                isCurrentWeek = isCurrentWeek,
            )
    }
}

/**
 * 排行榜、我的胜率、挑战的数据。服务器的榜单只有本期和上一期（上周、上月），胜率只有本月：更早的返回空。
 * 榜单按需拉取（60 秒内同一个只拉一次），界面读这里的状态，拉回来自动刷新。
 * 对应 iPhone 的 MockBackend+RemoteRankings.swift 和 MockBackend+Rankings.swift 里正式后端的那一路。
 * 不放进 AppEnvironment：同一个后端（同一个登录的人）共用一份，用 [rememberRankingManager] 拿
 */
@Stable
class RankingManager(private val backend: Backend, private val now: () -> Long = System::currentTimeMillis) {
    private val api = RankingsApi(backend.remote)
    private val ownerId: String? = backend.currentUser?.id

    private val weeklyBoards = mutableStateMapOf<String, RankingsApi.WeeklyBoard>()
    private val venueBoards = mutableStateMapOf<String, RankingsApi.VenueBoard>()
    /** 上次拉取的时间；拉失败了删掉，下次再拉 */
    private val loadedAt = HashMap<String, Long>()
    /** 拉失败的榜：不再显示占位，显示“没人上榜” */
    private val failed = mutableStateMapOf<String, Boolean>()
    /** 在榜单、挑战里见过的人（昵称、等级） */
    private val users = mutableStateMapOf<String, User>()
    private val venues = mutableStateMapOf<String, Venue>()
    /** 举报后对我隐藏 */
    private val hidden = mutableStateListOf<String>()
    private val challengeMap = mutableStateMapOf<String, Challenge>()
    private var myWinRate by mutableStateOf<Rankings.WinRate?>(null)

    /** 我资料里的国家/地区（“本国榜”）；读到之前先用设备地区 */
    var countryCode by mutableStateOf(CountryInfo.deviceCountry.code)
        private set

    /** 位置、附近的球馆、附近范围（和 iPhone 一样看 LocationManager）；[rememberRankingManager] 接上 */
    var locationManager: LocationManager? = null

    /** 附近的球馆，按距离排 */
    val nearbyVenues: List<Venue> get() = locationManager?.nearbyCourts.orEmpty()

    /** 算距离用的坐标：有定位用定位，没有用默认城市（和 iPhone 的 locationManager.coordinate 一样） */
    val location: Coordinate? get() = locationManager?.coordinate

    /** 附近范围（公里） */
    val radiusKm: Double get() = locationManager?.preferences?.travelRadiusKm ?: Venue.DEFAULT_TRAVEL_RADIUS_KM

    val me: User? get() = backend.currentUser

    fun user(id: String): User? = if (id == me?.id) me else users[id]

    /** 我默认看的榜（男子 / 女子） */
    val myBoard: Gender get() = (me?.gender ?: Gender.Unspecified).board

    private fun cache(player: RankingsApi.Player) = cache(player.id, player.nickname, player.rating)

    private fun cache(id: String, nickname: String, rating: Double?) {
        if (id == me?.id) return
        val known = users[id]
        users[id] = known?.copy(nickname = nickname, selfReportedRating = rating ?: known.selfReportedRating)
            ?: User(id = id, nickname = nickname, phone = "", selfReportedLevel = SkillTier.ofRating(rating ?: 3.0).level, selfReportedRating = rating)
    }

    // MARK: 拉取

    /** 同一个榜 60 秒内只拉一次（force：下拉刷新） */
    private suspend fun refresh(key: String, force: Boolean = false, load: suspend () -> Unit) {
        val last = loadedAt[key]
        if (!force && last != null && now() - last <= 60_000) return
        loadedAt[key] = now()
        var done = false
        try {
            load()
            failed.remove(key)
            done = true
        } catch (_: RemoteError) {
            failed[key] = true
        } finally {
            if (!done) loadedAt.remove(key)
        }
    }

    // MARK: 周榜

    private fun weekOffset(week: DateInterval): Int? = remoteOffset(week, Rankings.week(now()))

    private fun weeklyKey(offset: Int, country: Boolean, gender: Gender) = "${if (country) "country" else "global"}-$offset-${gender.board.rawValue}"

    suspend fun loadWeekly(week: DateInterval, country: Boolean, gender: Gender = myBoard, force: Boolean = false) {
        val offset = weekOffset(week) ?: return
        val key = weeklyKey(offset, country, gender)
        refresh("weekly-$key", force) {
            val board = api.weeklyBoard(if (country) "country" else "global", offset, gender.board)
            board.entries.forEach { cache(it.id, it.nickname, it.rating) }
            weeklyBoards[key] = board
        }
    }

    /** 打开排行榜时把常切的几个榜（全球 / 本国 × 本周 / 上周）一起拉，切换时不用等 */
    suspend fun prefetchWeekly() = coroutineScope {
        val current = Rankings.week(now())
        for (week in listOf(current, Rankings.week(current.start - 1))) {
            for (country in listOf(false, true)) launch { loadWeekly(week, country) }
        }
    }

    private fun weeklyBoard(week: DateInterval, country: Boolean, gender: Gender): RankingsApi.WeeklyBoard? =
        weekOffset(week)?.let { weeklyBoards[weeklyKey(it, country, gender)] }

    /** 周榜（举报过的人不显示）；男女分榜，不传就看自己的 */
    fun weeklyLeaderboard(week: DateInterval, country: Boolean, gender: Gender = myBoard): List<Rankings.Entry> =
        (weeklyBoard(week, country, gender)?.entries ?: emptyList()).filter { it.id !in hidden }.map { entry(it, it.points ?: 0) }

    /** 榜还没拉回来（界面显示占位，不显示“没人上榜”）；拉失败了不算 */
    fun isWeeklyLoading(week: DateInterval, country: Boolean, gender: Gender = myBoard): Boolean {
        val offset = weekOffset(week) ?: return false
        val key = weeklyKey(offset, country, gender)
        return weeklyBoards[key] == null && failed["weekly-$key"] != true
    }

    /** 我在这周榜上的分数和场次（不在榜上时用进度） */
    fun weeklyScore(week: DateInterval, country: Boolean): Rankings.WeeklyScore {
        val board = weeklyBoard(week, country, myBoard) ?: return Rankings.WeeklyScore(0, 0, 0, 0)
        board.entries.firstOrNull { it.id == me?.id }?.let {
            return Rankings.WeeklyScore(it.points ?: 0, it.games, it.wins, Rankings.WEEKLY_MINIMUM_OPPONENTS)
        }
        board.progress?.let { return Rankings.WeeklyScore(it.points, it.games, 0, it.opponents) }
        return Rankings.WeeklyScore(board.me?.points ?: 0, 0, 0, 0)
    }

    /** 我为什么不在榜上（在榜上时为 null） */
    fun boardAbsenceReason(week: DateInterval? = null, country: Boolean = false): String? {
        val me = me ?: return null
        if (!me.privacy.showsOnLeaderboards) return tr("你在设置里关闭了上榜")
        val ready = me.joinDate + Rankings.MINIMUM_ACCOUNT_AGE_DAYS * 86_400_000L
        if (now() < ready) return tr("注册满 %lld 天后上榜（%@ 起）", Rankings.MINIMUM_ACCOUNT_AGE_DAYS, DateText.shortDay(ready))
        // 剩下的原因只有赛果争议（服务器算）
        if (week != null && weeklyBoard(week, country, myBoard)?.eligible == false) {
            return tr("最近 %lld 天和多位球友有赛果争议，暂不上榜，核实后恢复", Rankings.DISPUTE_WINDOW_DAYS)
        }
        return null
    }

    fun standing(week: DateInterval, country: Boolean, entries: List<Rankings.Entry>): WeeklyStanding? {
        val me = me ?: return null
        return WeeklyStanding.of(weeklyScore(week, country), me.id, entries, boardAbsenceReason(week, country), now() in week)
    }

    // MARK: 场馆月榜

    private fun monthOffset(month: DateInterval): Int? = remoteOffset(month, Rankings.month(now()))

    private fun venueKey(venueId: String, offset: Int, gender: Gender) = "$venueId-$offset-${gender.board.rawValue}"

    suspend fun loadVenueBoard(venueId: String, month: DateInterval, gender: Gender = myBoard, force: Boolean = false) {
        val offset = monthOffset(month) ?: return
        val key = venueKey(venueId, offset, gender)
        refresh("venue-$key", force) {
            val board = api.venueBoard(venueId, offset, gender.board)
            board.bands.flatMap { it.entries }.forEach { cache(it.id, it.nickname, it.rating) }
            venueBoards[key] = board
        }
    }

    /** 场馆月榜：按水平段分开，只返回有人上榜的段（按场数排） */
    fun venueLeaderboard(venueId: String, month: DateInterval, gender: Gender = myBoard): List<Pair<LevelBracket, List<Rankings.Entry>>> {
        val offset = monthOffset(month) ?: return emptyList()
        val board = venueBoards[venueKey(venueId, offset, gender)] ?: return emptyList()
        return board.bands.mapNotNull { band ->
            val bracket = LevelBracket.entries.firstOrNull { it.rawValue == band.band } ?: return@mapNotNull null
            val entries = band.entries.filter { it.id !in hidden }.map { entry(it, it.games) }
            if (entries.isEmpty()) null else bracket to entries
        }
    }

    fun isVenueLoading(venueId: String, month: DateInterval, gender: Gender = myBoard): Boolean {
        val offset = monthOffset(month) ?: return false
        val key = venueKey(venueId, offset, gender)
        return venueBoards[key] == null && failed["venue-$key"] != true
    }

    // MARK: 胜率

    /** 我本月的胜率（my_record）。别人的胜率在球友资料卡里 */
    suspend fun loadRecord(force: Boolean = false) = refresh("record", force) {
        val record = api.myRecord()
        myWinRate = Rankings.WinRate(record.games, record.wins, record.opponents, record.gap, record.rounds, record.roundWins)
    }

    fun winRate(month: DateInterval): Rankings.WinRate {
        val empty = Rankings.WinRate(0, 0, 0, 0.0)
        if (now() !in month) return empty
        return myWinRate ?: empty
    }

    // MARK: 举报

    /** 举报榜单上的人：先对我隐藏，再交给人工复核 */
    suspend fun report(userId: String, reason: ReportReason) {
        if (userId == me?.id) return
        if (userId !in hidden) hidden.add(userId)
        api.report(userId, if (reason == ReportReason.Scam) "scam" else "other", tr("来自排行榜"))
    }

    // MARK: 挑战

    /** 和我有关的挑战（新的在前）；过期的标成过期 */
    fun challenges(): List<Challenge> {
        val time = now()
        return challengeMap.values
            .map { if (it.isExpired(time)) it.copy(status = ChallengeStatus.Expired) else it }
            .sortedByDescending { it.createdAt }
    }

    /** 收到的（待回应的排前面）和发出的 */
    fun incoming(all: List<Challenge> = challenges()): List<Challenge> {
        val mine = all.filter { it.targetId == me?.id }
        return mine.filter { it.status == ChallengeStatus.Pending } + mine.filter { it.status != ChallengeStatus.Pending }
    }

    fun outgoing(all: List<Challenge> = challenges()): List<Challenge> = all.filter { it.challengerId == me?.id }

    suspend fun refreshChallenges() {
        val me = me?.id ?: return
        val mine = api.myChallenges()
        val list = HashMap<String, Challenge>()
        for (item in mine.incoming) {
            list[item.id] = challenge(item, challenger = item.player.id, target = me, status = ChallengeStatus.Pending)
        }
        for (item in mine.outgoing) {
            val status = when (item.status) {
                "accepted" -> ChallengeStatus.Accepted
                "pending" -> ChallengeStatus.Pending
                else -> ChallengeStatus.Expired
            }
            list[item.id] = challenge(item, challenger = me, target = item.player.id, status = status)
        }
        challengeMap.keys.retainAll(list.keys)
        challengeMap.putAll(list)
    }

    private fun challenge(item: RankingsApi.Challenges.Item, challenger: String, target: String, status: ChallengeStatus): Challenge {
        listOfNotNull(item.player, item.partner).forEach(::cache)
        val known = challengeMap[item.id]
        val court = known?.court ?: Venue(
            id = "challenge-${item.id}", name = item.venue.name, lat = 0.0, lon = 0.0, countryCode = CountryInfo.deviceCountry.code,
            timeZoneId = item.venue.tz, source = VenueSource.Player, status = VenueStatus.Unconfirmed,
        )
        // 有效期是发出后 48 小时：按服务器给的截止时间倒推发出时间
        val createdAt = item.expiresAt?.let { it - Challenge.RESPONSE_WINDOW } ?: known?.createdAt ?: now()
        return Challenge(
            id = item.id, challengerId = challenger, targetId = target, court = court,
            slot = TimeSlot.of(item.startsAt, item.startsAt, item.endsAt), message = item.message ?: "",
            createdAt = createdAt, status = status, gameId = item.gameId, challengerPartnerId = item.partner?.id,
        )
    }

    suspend fun send(targetId: String, court: Venue, slot: TimeSlot, message: String, partnerId: String?): Challenge? {
        val id = api.sendChallenge(targetId, court.id, slot.startTime, slot.endTime, message, partnerId)
        refreshChallenges()
        return challengeMap[id]
    }

    /** 接受（双打要带上自己的搭档）或婉拒；接受时返回生成的球局 ID */
    suspend fun respond(id: String, accept: Boolean, partnerId: String? = null): String? {
        val gameId = api.respondChallenge(id, accept, partnerId)
        refreshChallenges()
        return gameId
    }

    /** 撤回：先在本机标成撤回，再告诉服务器 */
    suspend fun withdraw(id: String) {
        challengeMap[id]?.let { challengeMap[id] = it.copy(status = ChallengeStatus.Withdrawn, respondedAt = now()) }
        api.withdrawChallenge(id)
    }

    // MARK: 球友、球馆

    /** 被挑战的人：没见过就读一下昵称和等级 */
    suspend fun loadPlayer(id: String) {
        if (user(id) != null) return
        api.player(id)?.let(::cache)
    }

    suspend fun loadCountry() {
        val id = me?.id ?: return
        api.myCountry(id)?.let { countryCode = it }
    }

    fun venue(id: String): Venue? = venues[id] ?: backend.venue(id)

    /** 常去球馆（按收藏的顺序） */
    val favoriteVenues: List<Venue> get() = backend.favoriteVenueIds.mapNotNull(::venue)

    fun isFavorite(id: String): Boolean = id in backend.favoriteVenueIds

    /** 读常去球馆和另外要显示名字的球馆，再让 LocationManager 取位置、拉附近的 */
    suspend fun loadVenues(extra: List<String> = emptyList()) {
        val missing = (backend.favoriteVenueIds + extra).distinct().filter { venue(it) == null }
        if (missing.isNotEmpty()) api.venues(missing).forEach { venues[it.id] = it }
        locationManager?.start()
    }

    suspend fun searchVenues(query: String): List<Venue> {
        val center = locationManager?.currentLocation ?: favoriteVenues.firstOrNull()?.location
        val found = backend.searchVenues(query, center)
        found.forEach { venues[it.id] = it }
        return if (center == null) found else found.sortedBy { it.distanceKm(center) }
    }

    fun rememberVenue(venue: Venue) {
        venues[venue.id] = venue
    }

    // 测试和截图用：直接放数据
    internal fun preload(weekly: Map<String, RankingsApi.WeeklyBoard> = emptyMap(), venue: Map<String, RankingsApi.VenueBoard> = emptyMap()) {
        weekly.values.flatMap { it.entries }.forEach { cache(it.id, it.nickname, it.rating) }
        venue.values.flatMap { board -> board.bands.flatMap { it.entries } }.forEach { cache(it.id, it.nickname, it.rating) }
        weeklyBoards.putAll(weekly)
        venueBoards.putAll(venue)
    }

    internal fun preload(challenges: List<Challenge>, people: List<User>, places: List<Venue> = emptyList()) {
        challenges.forEach { challengeMap[it.id] = it }
        people.forEach { users[it.id] = it }
        places.forEach { venues[it.id] = it }
    }

    companion object {
        private val instances = WeakHashMap<Backend, RankingManager>()

        /** 同一个后端共用一个；换了登录的人就换一个新的 */
        fun of(backend: Backend): RankingManager = synchronized(instances) {
            val existing = instances[backend]
            if (existing != null && existing.ownerId == backend.currentUser?.id) return existing
            RankingManager(backend).also { instances[backend] = it }
        }

        /** 0 = 本期，1 = 上一期（紧挨着本期结束），更早的服务器不提供 */
        fun remoteOffset(period: DateInterval, current: DateInterval): Int? = when {
            period.start == current.start -> 0
            period.end == current.start -> 1
            else -> null
        }

        fun entry(remote: RankingsApi.BoardEntry, score: Int) = Rankings.Entry(remote.id, remote.rank, score, remote.games, remote.wins)

        /** 筛选后重新编号（同分同胜场同名次） */
        fun reranked(list: List<Rankings.Entry>): List<Rankings.Entry> {
            val result = mutableListOf<Rankings.Entry>()
            for ((index, entry) in list.withIndex()) {
                val tied = index > 0 && list[index - 1].score == entry.score && list[index - 1].wins == entry.wins
                result += entry.copy(rank = if (tied) result[index - 1].rank else index + 1)
            }
            return result
        }

        /** “31 小时” / “40 分钟” */
        fun remaining(until: Long, now: Long = System.currentTimeMillis()): String {
            val minutes = maxOf(1L, (until - now) / 60_000)
            if (minutes >= 60) return tr("%lld 小时", minutes / 60)
            return tr("%lld 分钟", minutes)
        }
    }
}

/** 界面里拿排行榜的数据（同一个登录的人共用一份） */
@Composable
fun rememberRankingManager(): RankingManager {
    val env = LocalEnv.current
    val userId = env.appState.currentUser?.id
    return remember(env, userId) { RankingManager.of(env.appState.backend).also { it.locationManager = env.locationManager } }
}

/** 拉取出错时不打断界面（下次再拉） */
internal suspend fun quietly(block: suspend () -> Unit) {
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (_: RemoteError) {
    }
}
