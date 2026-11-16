package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.ZoneId
import java.util.Locale
import kotlin.math.ceil

// 对战模式（GameMode）在 Basics.kt

// MARK: - 费用 AA

/** 费用明细：场地费 + 用球费，平台不收服务费。币种跟随球馆所在国家。 */
@Serializable
data class CostSplit(
    val basis: Basis,
    /** courtHour：每片场地每小时；dropIn：每人次 */
    val rate: Int,
    val hours: Double,
    val shuttleFee: Int,
    val players: Int,
    val currencyCode: String,
) {
    @Serializable
    enum class Basis {
        /** 按场地小时收费，参与者平摊 */
        @SerialName("courtHour") CourtHour,
        /** 球馆按人次收费（美国俱乐部常见的 drop-in） */
        @SerialName("dropIn") DropIn,
        /** 球馆价格未知 */
        @SerialName("unknown") Unknown,
    }

    val courtFee: Int?
        get() = when (basis) {
            Basis.CourtHour -> roundHalfAway(rate * hours).toInt()
            Basis.DropIn -> rate * players
            Basis.Unknown -> null
        }

    val total: Int? get() = courtFee?.let { it + shuttleFee }

    /** 每人应付（向上取整）；价格未知时为 null */
    val perPerson: Int?
        get() {
            val total = total ?: return null
            if (players <= 0) return total
            return ceil(total.toDouble() / players).toInt()
        }

    fun money(amount: Int): String = Money.format(amount, currencyCode)

    /** "$17/人" 或 "费用待定" */
    val perPersonText: String
        get() {
            val perPerson = perPerson ?: return tr("费用待定")
            return tr("%@/人", money(perPerson))
        }

    val breakdownText: String
        get() {
            val hoursText = if (hours == roundHalfAway(hours)) "${hours.toInt()}" else String.format(Locale.ROOT, "%.1f", hours)
            val rateText = money(rate)
            val shuttleText = money(shuttleFee)
            return when (basis) {
                Basis.CourtHour -> {
                    val shuttle = if (shuttleFee > 0) tr(" + 用球 %@", shuttleText) else ""
                    tr("场地 %@/时 × %@ 小时%@ = %@，%lld 人 AA", rateText, hoursText, shuttle, money(total ?: 0), players)
                }
                Basis.DropIn -> {
                    val shuttle = if (shuttleFee > 0) tr("，用球 %@ 平摊", shuttleText) else ""
                    tr("球馆按人次收费 %@/人%@", rateText, shuttle)
                }
                Basis.Unknown -> tr("球馆价格未知，到场后按实际费用 AA")
            }
        }

    companion object {
        fun estimate(court: Venue, slot: TimeSlot, mode: GameMode): CostSplit {
            val (basis, rate) = when (val pricing = court.pricing) {
                is VenuePricing.PerCourtHour -> Basis.CourtHour to pricing.price
                is VenuePricing.DropIn -> Basis.DropIn to pricing.perPerson
                VenuePricing.Unknown -> Basis.Unknown to 0
            }
            return CostSplit(
                basis, rate, hours = slot.duration / 3_600_000.0, shuttleFee = court.country.shuttleFee(mode),
                players = mode.requiredPlayers, currencyCode = court.currency,
            )
        }
    }
}

// MARK: - 球局

@Serializable
enum class GameStatus {
    @SerialName("confirmed") Confirmed,
    @SerialName("completed") Completed,
    @SerialName("cancelled") Cancelled,
}

@Serializable
sealed interface GameOrigin {
    @Serializable
    @SerialName("quickMatch")
    data object QuickMatch : GameOrigin

    @Serializable
    @SerialName("room")
    data class Room(val code: String) : GameOrigin

    @Serializable
    @SerialName("challenge")
    data class Challenge(val id: String) : GameOrigin
}

/** 两边各赢了几局（我方视角） */
data class GameCount(val mine: Int, val theirs: Int)

@Serializable
data class GameResult(
    /** 当前用户视角是否获胜（null = 未记录） */
    val didWin: Boolean?,
    val score: String,
) {
    companion object {
        private val scorePattern = Regex("""(?<!\d)(\d{1,2})\s*[:/-]\s*(\d{1,2})(?!\d)""")
        private val validScore = Regex("""^[0-9 :,/-]+$""")

        /**
         * 每局比分（“21:18 19:21 21:15”，前面的数是我方）数出两边各赢了几局；一局都数不出来返回 null。
         * 每局至少有一边到 11 分才算（“2:1”这种是局数，不是比分）
         */
        fun games(fromScore: String): GameCount? {
            var mine = 0
            var theirs = 0
            for (match in scorePattern.findAll(fromScore)) {
                val a = match.groupValues[1].toInt()
                val b = match.groupValues[2].toInt()
                if (a == b || maxOf(a, b) < 11) continue
                if (a > b) mine += 1 else theirs += 1
            }
            return if (mine + theirs > 0) GameCount(mine, theirs) else null
        }

        /** 比分只能是数字和分隔符（如 21:18 19:21），最多 40 个字，和服务器的检查一致 */
        fun isValidScore(score: String): Boolean {
            val trimmed = score.trim { it == ' ' || it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
            return trimmed.isEmpty() || (trimmed.length <= 40 && validScore.matches(trimmed))
        }
    }
}

/** 已确认的一场球 */
@Serializable
data class Game(
    val id: String,
    val mode: GameMode,
    val court: Venue,
    val slot: TimeSlot,
    val playerIds: List<String>,
    /** 分组：单打 [[A],[B]]，双打 [[A,B],[C,D]] */
    val teams: List<List<String>>,
    val hostId: String,
    val origin: GameOrigin,
    val status: GameStatus,
    val createdAt: Long,
    /** 到场签到时间 */
    val checkIns: Map<String, Long>,
    /** 已付 AA 的球友 */
    val paidPlayerIds: List<String>,
    val cost: CostSplit,
    val result: GameResult? = null,
    val cancelledBy: String? = null,
    /** 是否为临时取消（开赛前 2 小时内） */
    val cancelledLate: Boolean = false,
    val reminderEnabled: Boolean = false,
    /** 每位球员各自申报的赛果（见 [resultStatus]） */
    val resultReports: List<ResultReport> = emptyList(),
    /** 附近的人里约的球局还没定具体几点：时间窗口（slot 就是整个窗口）；定好了是 null */
    val window: PlayWindow? = null,
) {
    /** 具体几点定了没有 */
    val isTimeSet: Boolean get() = window == null

    fun isUpcoming(now: Long = System.currentTimeMillis()): Boolean = status == GameStatus.Confirmed && slot.endTime > now

    fun isInProgress(now: Long = System.currentTimeMillis()): Boolean = status == GameStatus.Confirmed && isTimeSet && slot.contains(now)

    /** 可签到：开赛前 30 分钟到结束 */
    fun canCheckIn(now: Long = System.currentTimeMillis()): Boolean =
        status == GameStatus.Confirmed && now >= slot.startTime - CHECK_IN_WINDOW && now < slot.endTime

    /** 可标记完成：开赛后 */
    fun canComplete(now: Long = System.currentTimeMillis()): Boolean =
        status == GameStatus.Confirmed && isTimeSet && now >= slot.startTime && now <= slot.endTime + 7 * 86_400_000L

    /** 现在取消是否属于临时取消 */
    fun isLateCancellation(now: Long = System.currentTimeMillis()): Boolean {
        // 还没定时间的不算临时取消
        if (!isTimeSet) return false
        return slot.startTime - now < FREE_CANCELLATION_WINDOW
    }

    fun hasCheckedIn(userId: String): Boolean = checkIns[userId] != null

    fun hasPaid(userId: String): Boolean = userId in paidPlayerIds

    fun otherPlayerIds(excluding: String): List<String> = playerIds.filter { it != excluding }

    val statusText: String
        get() = when (status) {
            GameStatus.Confirmed -> tr("已确认")
            GameStatus.Completed -> tr("已完成")
            GameStatus.Cancelled -> tr("已取消")
        }

    fun shareText(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String =
        tr("%@球局 · %@\n%@\n%@\nAA %@ —— 来自 Badie", mode.title, slot.formattedFull(now, zone), court.name, court.address, cost.perPersonText)

    // MARK: 赛果（iPhone 在 Ranking.swift 里）

    val resultDeadline: Long get() = slot.endTime + RESULT_WINDOW

    fun team(userId: String): Int? = teams.indexOfFirst { userId in it }.takeIf { it >= 0 }

    fun report(userId: String): ResultReport? = resultReports.firstOrNull { it.reporterId == userId }

    /** 报上来的局数，换成某人的视角 */
    fun games(report: ResultReport, userId: String): GameCount? {
        val counts = report.teamGames ?: return null
        if (counts.size != 2) return null
        val mine = team(userId) ?: return null
        return GameCount(counts[mine], counts[1 - mine])
    }

    /** 已经有人报的局数（我方视角），我报的优先 */
    fun reportedGames(userId: String): GameCount? {
        val reports = resultReports.filter { it.teamGames != null }
        val report = reports.firstOrNull { it.reporterId == userId } ?: reports.firstOrNull() ?: return null
        return games(report, userId)
    }

    fun resultStatus(now: Long = System.currentTimeMillis()): ResultStatus {
        val claims = resultReports.filter { !it.unsure }
        val outcomes = claims.map { it.winningTeam }.toSet()
        // 局数也要一致（没填局数的不比）；“练球”（没填局数）和“平局”（填了一样多）是两种说法
        val friendlyKinds = claims.filter { it.winningTeam == null }.map { it.teamGames == null }.toSet()
        if (outcomes.size > 1 || claims.mapNotNull { it.teamGames }.toSet().size > 1 || friendlyKinds.size > 1) return ResultStatus.Disputed
        val claimingTeams = claims.mapNotNull { team(it.reporterId) }.toSet()
        if (claimingTeams.size == teams.size && outcomes.isNotEmpty()) {
            val outcome = outcomes.first()
            if (outcome != null) return ResultStatus.Verified(outcome)
            return if (claims.any { it.teamGames != null }) ResultStatus.Draw else ResultStatus.Friendly
        }
        if (teams.any { team -> team.all { report(it)?.unsure == true } }) return ResultStatus.Unsure
        return if (now > resultDeadline) ResultStatus.Expired else ResultStatus.Awaiting
    }

    /** 还能报或改赛果：确认之前、期限之内 */
    fun acceptsResultReports(now: Long = System.currentTimeMillis()): Boolean {
        if (status != GameStatus.Completed || now > resultDeadline) return false
        return when (resultStatus(now)) {
            ResultStatus.Awaiting, ResultStatus.Disputed, ResultStatus.Unsure -> true
            else -> false
        }
    }

    companion object {
        /** 开赛前多少时间内取消算临时取消（毫秒） */
        const val FREE_CANCELLATION_WINDOW = 2 * 3_600_000L
        /** 开赛前 30 分钟可签到 */
        const val CHECK_IN_WINDOW = 30 * 60_000L
        /** 结束后多久内可以申报、确认赛果 */
        const val RESULT_WINDOW = 7 * 86_400_000L
    }
}
