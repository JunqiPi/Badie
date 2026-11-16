package com.badie.app.backend

import com.badie.app.models.Avatar
import com.badie.app.models.CostSplit
import com.badie.app.models.Daypart
import com.badie.app.models.Game
import com.badie.app.models.GameCount
import com.badie.app.models.GameMode
import com.badie.app.models.GameOrigin
import com.badie.app.models.GameResult
import com.badie.app.models.GameStatus
import com.badie.app.models.PendingSurvey
import com.badie.app.models.PlayWindow
import com.badie.app.models.ResultReport
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlot
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenuePricing
import com.badie.app.models.VenueSource
import com.badie.app.models.VenueStatus
import com.badie.app.remote.EpochMillisSerializer
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import java.time.Instant

// 正式后端：球局、签到、AA、赛果、评价。对应 iPhone 的 MockBackend+RemoteGames.swift 和 MockBackend+Games.swift 里连服务器的那部分。
// 服务器是唯一的数据来源：每次操作后重新拉 my_games，界面读拉到的结果

/** 服务器给的球馆基本信息（球局、房间里带的） */
@Serializable
class RemotePlace(
    val id: String,
    val name: String,
    val city: String? = null,
    val street: String? = null,
    val tz: String? = null,
    val lat: Double? = null,
    val lon: Double? = null,
    val country: String? = null,
    val pricing: VenuePricing? = null,
) {
    /** 球馆：优先用读过的球馆（信息更全），没有就用服务器给的基本信息 */
    fun venue(known: Venue? = null): Venue {
        if (known != null && (known.lat != 0.0 || lat == null)) return known
        return Venue(
            id = id, name = name, lat = lat ?: 0.0, lon = lon ?: 0.0, street = street ?: "", city = city ?: "", region = "",
            countryCode = country ?: "US", timeZoneId = tz, pricing = pricing ?: VenuePricing.Unknown,
            source = VenueSource.Player, status = VenueStatus.Unconfirmed,
        )
    }
}

/** 同局的球友：服务器只给昵称、等级和几个状态 */
@Serializable
class RemotePlayer(
    val id: String,
    val nickname: String,
    val rating: Double,
    val team: Int,
    val me: Boolean,
    val checkedIn: Boolean? = null,
    val reviewed: Boolean? = null,
    val paid: Boolean? = null,
) {
    fun user(): User = User(id = id, nickname = nickname, phone = "", selfReportedLevel = SkillTier.ofRating(rating).level, selfReportedRating = rating)
}

@Serializable
class RemoteGame(
    val id: String,
    val mode: String,
    @Serializable(EpochMillisSerializer::class) val startsAt: Long,
    @Serializable(EpochMillisSerializer::class) val endsAt: Long,
    val status: String,
    val venue: RemotePlace,
    /** 房间开的局才有发起人 */
    val hostId: String? = null,
    val myTeam: Int,
    val checkedIn: Boolean = false,
    val myReport: Report? = null,
    val result: Result? = null,
    /** 最近一次填的比分 */
    val score: String? = null,
    /** 确认过的局数 */
    val rounds: Rounds? = null,
    @Serializable(EpochMillisSerializer::class) val reviewUntil: Long,
    val players: List<RemotePlayer>? = null,
    /** 附近的人里约的球局还没定具体几点：time_set = false，starts_at / ends_at 就是窗口 */
    val timeSet: Boolean? = null,
    @Serializable(EpochMillisSerializer::class) val windowStart: Long? = null,
    @Serializable(EpochMillisSerializer::class) val windowEnd: Long? = null,
    val durationMinutes: Int? = null,
    val daypart: String? = null,
) {
    @Serializable
    class Report(val outcome: String? = null, val score: String? = null, val team1Games: Int? = null, val team2Games: Int? = null)

    @Serializable
    class Rounds(val team1: Int, val team2: Int)

    @Serializable
    class Result(val status: String, val outcome: String? = null)
}

/** 服务器的数据换成本机的模型（纯函数，方便测试） */
object GameMapping {
    /**
     * 一场球。[cached] 是上次拉到的同一场：签到时间、提醒开关接着用。
     * iPhone 连正式后端时提醒开关默认是开的（cached?.reminderEnabled ?? true），这里照搬
     */
    fun game(remote: RemoteGame, me: String, venue: Venue, cached: Game?, now: Long): Game {
        val players = remote.players.orEmpty()
        val mode = GameMode.ofServer(remote.mode)
        val slot = TimeSlot(remote.startsAt, remote.startsAt, remote.endsAt)
        val teams = listOf(1, 2).map { team -> players.filter { it.team == team }.map { it.id } }
        val checkIns = players.filter { it.checkedIn == true }.associate { it.id to (cached?.checkIns?.get(it.id) ?: now) }
        val reports = resultReports(remote, teams, me, now)
        val status = when {
            remote.status == "cancelled" -> GameStatus.Cancelled
            remote.myReport == null -> GameStatus.Confirmed
            else -> GameStatus.Completed
        }
        val mine = reports.firstOrNull { it.reporterId == me }
        val myTeam = remote.myTeam - 1
        return Game(
            id = remote.id, mode = mode, court = venue, slot = slot, playerIds = players.map { it.id }, teams = teams,
            hostId = remote.hostId ?: "", origin = GameOrigin.QuickMatch, status = status, createdAt = cached?.createdAt ?: remote.startsAt,
            checkIns = checkIns, paidPlayerIds = players.filter { it.paid == true }.map { it.id },
            cost = CostSplit.estimate(venue, slot, mode),
            result = mine?.let { report ->
                GameResult(didWin = if (report.unsure) null else report.winningTeam?.let { it == myTeam }, score = remote.score ?: "")
            },
            cancelledBy = null, cancelledLate = false, reminderEnabled = cached?.reminderEnabled ?: true, resultReports = reports,
            window = window(remote.timeSet, remote.windowStart, remote.windowEnd, remote.daypart, remote.durationMinutes),
        )
    }

    /** 服务器只给我报的结果和总体状态；按状态补上对方那一方的申报，让本地的赛果状态和服务器一致 */
    fun resultReports(remote: RemoteGame, teams: List<List<String>>, me: String, now: Long): List<ResultReport> {
        fun index(outcome: String?): Int? = when (outcome) {
            "team1" -> 0
            "team2" -> 1
            else -> null
        }
        val myTeam = remote.myTeam - 1
        if (teams.size != 2 || myTeam !in teams.indices) return emptyList()
        val opponents = teams[1 - myTeam]
        val reports = mutableListOf<ResultReport>()
        remote.myReport?.let { report ->
            val games = if (report.team1Games != null && report.team2Games != null) listOf(report.team1Games, report.team2Games) else null
            reports += ResultReport(me, index(report.outcome), report.score ?: "", now, unsure = report.outcome == null, teamGames = games)
        }
        val result = remote.result ?: return reports
        val opponent = opponents.firstOrNull() ?: return reports
        when {
            result.status == "verified" -> reports += ResultReport(
                opponent, index(result.outcome), remote.score ?: "", now, teamGames = remote.rounds?.let { listOf(it.team1, it.team2) },
            )
            // 服务器只说有分歧，不说谁报了什么：放两份互相矛盾、没有人名的说法，界面只显示“双方填的不一样”
            result.status == "disputed" -> reports += listOf(0, 1).map { ResultReport("", it, "", now) }
            result.status == "unsure" && remote.myReport?.outcome != null ->
                reports += opponents.map { ResultReport(it, null, "", now, unsure = true) }
        }
        return reports
    }

    /** 结束 48 小时内、还没评的球友 */
    fun pendingSurveys(games: List<RemoteGame>, me: String, now: Long, avatar: (String) -> Avatar): List<PendingSurvey> =
        games.filter { it.status != "cancelled" && it.endsAt <= now && now < it.reviewUntil }.flatMap { game ->
            game.players.orEmpty().filter { !it.me && it.reviewed != true }.map { player ->
                PendingSurvey(
                    id = "${game.id}|${player.id}", matchId = game.id, evaluatorId = me, opponentId = player.id,
                    opponentNickname = player.nickname, opponentLevel = SkillTier.ofRating(player.rating).level,
                    opponentAvatar = avatar(player.id), courtName = game.venue.name, matchDate = game.startsAt,
                    expiresAt = game.reviewUntil, opponentRating = player.rating,
                )
            }
        }

    /** 同局球友：服务器只给昵称和等级，记下来让界面能显示 */
    fun player(remote: RemotePlayer, known: User?): User =
        (known ?: User(id = remote.id, nickname = remote.nickname, phone = "", selfReportedLevel = SkillTier.ofRating(remote.rating).level))
            .copy(nickname = remote.nickname, selfReportedRating = remote.rating)

    /** 还没定具体几点（time_set = false）的时间窗口；定好了是 null */
    fun window(timeSet: Boolean?, start: Long?, end: Long?, daypart: String?, duration: Int?): PlayWindow? {
        if (timeSet != false || start == null || end == null) return null
        return PlayWindow(start, end, Daypart.of(daypart), duration ?: 120)
    }

    /** 两边的局数换成服务器的 team1 / team2 */
    fun teamGames(game: Game, userId: String, games: GameCount?): List<Int>? {
        if (games == null || game.teams.size != 2) return null
        val mine = game.team(userId) ?: return null
        return if (mine == 0) listOf(games.mine, games.theirs) else listOf(games.theirs, games.mine)
    }

    /** 报赛果的参数：unsure 是记不清；didWin 为 null 是友谊局（不计胜负） */
    fun reportArgs(game: Game, me: String, didWin: Boolean?, score: String, unsure: Boolean, games: GameCount?): kotlinx.serialization.json.JsonObject {
        val mine = game.team(me) ?: 0
        val outcome: String? = when {
            unsure -> null
            didWin != null -> "team${(if (didWin) mine else 1 - mine) + 1}"
            else -> "friendly"
        }
        val counts = if (unsure) null else teamGames(game, me, games)
        val pairs = mutableListOf<Pair<String, Any?>>("p_game" to game.id, "p_outcome" to outcome, "p_score" to score)
        if (counts != null) {
            pairs += "p_team1_games" to counts[0]
            pairs += "p_team2_games" to counts[1]
        }
        return json(*pairs.toTypedArray())
    }

    /** 评价时选的档位和对方显示的档位比：高、低、差不多 */
    fun levelCheck(chosen: SkillTier, displayed: SkillTier): String {
        val difference = chosen.rating - displayed.rating
        return when {
            difference < -0.01 -> "lower"
            difference > 0.01 -> "higher"
            else -> "accurate"
        }
    }

    fun iso(millis: Long): String = Instant.ofEpochMilli(millis).toString()
}

// MARK: - 调服务器

/** 我参加的球局（最近 60 天） */
suspend fun Backend.myGames(): List<RemoteGame> = remote.rpc("my_games")

suspend fun Backend.cancelGame(gameId: String) = remote.call("cancel_game", json("p_game" to gameId))

suspend fun Backend.checkIn(gameId: String) = remote.call("check_in", json("p_game" to gameId))

/** 标记 AA 已付：本人可以标自己，发起人可以标所有人 */
suspend fun Backend.markPaid(gameId: String, userId: String, paid: Boolean) =
    remote.call("mark_paid", json("p_game" to gameId, "p_user" to userId, "p_paid" to paid))

/** 报赛果（结束球局、确认或修改赛果都是它） */
suspend fun Backend.reportResult(game: Game, didWin: Boolean?, score: String = "", unsure: Boolean = false, games: GameCount? = null) {
    val me = currentUser?.id ?: throw com.badie.app.remote.RemoteError.NotSignedIn
    remote.call("report_result", GameMapping.reportArgs(game, me, didWin, score, unsure, games))
}

/** 约成了还没定具体几点：定开始时间（打满窗口里的时长） */
suspend fun Backend.setGameTime(gameId: String, startsAt: Long) =
    remote.call("set_game_time", json("p_game" to gameId, "p_starts_at" to GameMapping.iso(startsAt)))

/** 赛后评价。等级按“比对方显示的档位高 / 低 / 差不多”换算；球品分只在本机用，服务器不收 */
suspend fun Backend.reviewPlayer(
    pending: PendingSurvey, skillRating: SkillTier, attendance: com.badie.app.models.AttendanceAnswer,
    tags: List<com.badie.app.models.SurveyTag>, issues: List<com.badie.app.models.SurveyIssue>, wantsRematch: Boolean,
) = remote.call(
    "review_player",
    json(
        "p_game" to pending.matchId,
        "p_user" to pending.opponentId,
        "p_attendance" to attendance.serverValue,
        "p_level" to GameMapping.levelCheck(skillRating, pending.opponentTier),
        "p_tags" to tags.map { it.serverValue },
        "p_issues" to issues.map { it.serverValue },
        "p_play_again" to wantsRematch,
    ),
)
