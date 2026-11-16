package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.TemporalAdjusters

// MARK: - 赛果申报
//
// 一人先报“哪一队赢了”，其他人看到后点“对”或改成自己记得的结果。两队各至少一人报、且一致才算确认。
// 记不清的人选“记不清了”：不算确认也不算争议，这场不计入。报得不一样是“有分歧”，
// 7 天内任何人都可以改，改到一致照常计入。没有“超时自动确认”——虚报不会因为对方没理会就生效。
// 判断赛果的几个函数（resultStatus 等）在 Game.kt 的 Game 里。

@Serializable
data class ResultReport(
    val reporterId: String,
    /** 获胜队伍在 `Game.teams` 里的下标；null = 友谊局 / 没打完，不计胜负 */
    val winningTeam: Int?,
    val score: String,
    val reportedAt: Long,
    /** 记不清了：不算确认，也不算争议 */
    val unsure: Boolean = false,
    /** 各队赢了几局（下标同 `Game.teams`）；null = 没填局数（老版本，或“没计分，就是练球”） */
    val teamGames: List<Int>? = null,
)

sealed interface ResultStatus {
    /** 还在等另一队确认 */
    data object Awaiting : ResultStatus
    data class Verified(val winningTeam: Int) : ResultStatus
    /** 双方说法不一致：期限内可以改，改不到一致就不计入 */
    data object Disputed : ResultStatus
    /** 双方都选了不计胜负（没计分，就是练球） */
    data object Friendly : ResultStatus
    /** 平局：两边赢的局一样多，局数计入胜率 */
    data object Draw : ResultStatus
    /** 有一队全员记不清，无法确认 */
    data object Unsure : ResultStatus
    /** 期限内没凑齐确认 */
    data object Expired : ResultStatus
}

// MARK: - 计入排行的对局

/** 双方确认后的一场比赛（胜率、场馆榜、周榜都只用它） */
@Serializable
data class MatchRecord(
    val id: String,
    val date: Long,
    val venueId: String,
    val countryCode: String,
    val mode: GameMode,
    val teams: List<List<String>>,
    val winningTeam: Int,
    /** 赛时各人的等级分值，用来算对手强度 */
    val ratings: Map<String, Double>,
) {
    fun team(userId: String): Int? = teams.indexOfFirst { userId in it }.takeIf { it >= 0 }

    fun opponents(userId: String): List<String> {
        val mine = team(userId) ?: return emptyList()
        return teams.filterIndexed { index, _ -> index != mine }.flatten()
    }

    fun didWin(userId: String): Boolean = team(userId) == winningTeam

    /** 同一个对手（双打按对手组合）算一个“对手” */
    fun opponentKey(userId: String): String = opponents(userId).sorted().joinToString("+")

    /** 对手平均水平 − 我方平均水平（单位：级） */
    fun strengthGap(userId: String): Double {
        val mine = team(userId) ?: return 0.0
        fun average(ids: List<String>): Double {
            val values = ids.mapNotNull { ratings[it] }
            return if (values.isEmpty()) 0.0 else values.sum() / values.size
        }
        return average(opponents(userId)) - average(teams[mine])
    }
}

// MARK: - 水平段（场馆榜分段用）

enum class LevelBracket(val rawValue: Int) {
    Starter(1), Intermediate(2), Advanced(3), Elite(4);

    val title: String
        get() = when (this) {
            Starter -> tr("Lv.1–2 入门")
            Intermediate -> tr("Lv.3–4 进阶")
            Advanced -> tr("Lv.5–6 高手")
            Elite -> tr("Lv.7+ 精英")
        }

    companion object {
        fun of(rating: Double): LevelBracket = when (SkillTier.ofRating(rating).level) {
            in Int.MIN_VALUE..2 -> Starter
            in 3..4 -> Intermediate
            in 5..6 -> Advanced
            else -> Elite
        }
    }
}

// MARK: - 时间段

/** 一段时间（毫秒），和 iPhone 的 DateInterval 一样两头都算在里面 */
data class DateInterval(val start: Long, val end: Long) {
    operator fun contains(date: Long): Boolean = date in start..end
}

// MARK: - 规则与计算

object Rankings {
    /** 本月满这么多场才公开胜率 */
    const val WIN_RATE_MINIMUM_GAMES = 5
    /** 同一对手每月最多计入几场（防好友互刷） */
    const val MONTHLY_SAME_OPPONENT_CAP = 3
    /** 场馆榜：同一对手每月最多计入、每天最多计入 */
    const val VENUE_SAME_OPPONENT_CAP = 4
    const val VENUE_DAILY_CAP = 3
    const val VENUE_MINIMUM_GAMES = 3
    const val VENUE_MINIMUM_OPPONENTS = 2
    /** 周榜：每周最多计入的场数、上榜门槛 */
    const val WEEKLY_GAME_CAP = 15
    const val WEEKLY_MINIMUM_GAMES = 3
    const val WEEKLY_MINIMUM_OPPONENTS = 2
    /** 注册满这么多天才上榜（小号刷榜成本更高） */
    const val MINIMUM_ACCOUNT_AGE_DAYS = 7
    const val BOARD_SIZE = 50
    /** 近 60 天和至少 3 位不同对手有赛果争议的人暂不上榜（应对故意拒认），由人工复核后恢复 */
    const val DISPUTE_LIMIT = 3
    const val DISPUTE_WINDOW_DAYS = 60

    // MARK: 时间段

    fun month(containing: Long, zone: ZoneId = ZoneId.systemDefault()): DateInterval {
        val first = containing.zoned(zone).toLocalDate().withDayOfMonth(1)
        return DateInterval(
            first.atStartOfDay(zone).toInstant().toEpochMilli(),
            first.plusMonths(1).atStartOfDay(zone).toInstant().toEpochMilli(),
        )
    }

    /** 全球周榜按 UTC 的周一到周日 */
    fun week(containing: Long): DateInterval {
        val monday = containing.zoned(ZoneOffset.UTC).toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return DateInterval(
            monday.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            monday.plusWeeks(1).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
    }

    /** 时间段内某人计入的对局：按时间先后，同一对手超过上限的不再计入 */
    fun counted(
        records: List<MatchRecord>, userId: String, interval: DateInterval,
        sameOpponentCap: Int, dailyCap: Int? = null, zone: ZoneId = ZoneId.systemDefault(),
    ): List<MatchRecord> {
        val perOpponent = HashMap<String, Int>()
        val perDay = HashMap<Long, Int>()
        return records
            .filter { it.date in interval && it.team(userId) != null }
            .sortedBy { it.date }
            .filter { record ->
                val key = record.opponentKey(userId)
                val day = startOfDay(record.date, zone)
                if (perOpponent.getOrDefault(key, 0) >= sameOpponentCap) return@filter false
                if (dailyCap != null && perDay.getOrDefault(day, 0) >= dailyCap) return@filter false
                perOpponent[key] = perOpponent.getOrDefault(key, 0) + 1
                perDay[day] = perDay.getOrDefault(day, 0) + 1
                true
            }
    }

    // MARK: 月度胜率

    data class WinRate(
        val games: Int,
        val wins: Int,
        val opponents: Int,
        /** 对手平均比我高多少级（负数 = 对手偏弱） */
        val averageGap: Double,
        /** 按局：打了几局、赢了几局（一场常常打好几局）。没有就按每场一局 */
        val rounds: Int? = null,
        val roundWins: Int? = null,
    ) {
        val playedRounds: Int get() = rounds ?: games
        val wonRounds: Int get() = roundWins ?: wins
        val isPublic: Boolean get() = games >= WIN_RATE_MINIMUM_GAMES
        /** 胜率按局算：赢的局数 ÷ 打的局数 */
        val percentage: Int
            get() = if (playedRounds == 0) 0 else roundHalfAway(wonRounds.toDouble() / playedRounds * 100).toInt()
    }

    fun winRate(userId: String, records: List<MatchRecord>, month: DateInterval): WinRate {
        val list = counted(records, userId, month, MONTHLY_SAME_OPPONENT_CAP)
        val gaps = list.map { it.strengthGap(userId) }
        return WinRate(
            games = list.size,
            wins = list.count { it.didWin(userId) },
            opponents = list.flatMap { it.opponents(userId) }.toSet().size,
            averageGap = if (gaps.isEmpty()) 0.0 else gaps.sum() / gaps.size,
        )
    }

    // MARK: 榜单

    data class Entry(
        val userId: String,
        val rank: Int,
        /** 场馆榜：计入场数；周榜：积分 */
        val score: Int,
        val games: Int,
        val wins: Int,
    ) {
        val id: String get() = userId
    }

    /** 一行：用户、分数、场数、胜场 */
    private data class Row(val userId: String, val score: Int, val games: Int, val wins: Int)

    /** 场馆月榜：比的是在这家馆打了多少场确认过的球（类似 Strava 的 Local Legends），同分看胜场 */
    fun venueBoard(venueId: String, records: List<MatchRecord>, month: DateInterval, eligible: (String) -> Boolean): List<Entry> {
        val atVenue = records.filter { it.venueId == venueId && it.date in month }
        val players = atVenue.flatMap { it.teams.flatten() }.toSet().filter(eligible)
        val rows = players.mapNotNull { userId ->
            val list = counted(atVenue, userId, month, VENUE_SAME_OPPONENT_CAP, VENUE_DAILY_CAP)
            val opponents = list.flatMap { it.opponents(userId) }.toSet().size
            if (list.size < VENUE_MINIMUM_GAMES || opponents < VENUE_MINIMUM_OPPONENTS) return@mapNotNull null
            Row(userId, list.size, list.size, list.count { it.didWin(userId) })
        }
        return ranked(rows)
    }

    /** 一场球的周榜积分：输 10 / 赢 15，按对手强度 ×0.5–1.5，同一对手第二场减半、第三场起不计 */
    fun points(record: MatchRecord, userId: String, meetingIndex: Int): Double {
        val base = if (record.didWin(userId)) 15.0 else 10.0
        val strength = minOf(1.5, maxOf(0.5, 1 + record.strengthGap(userId) * 0.5))
        val repeatFactor = if (meetingIndex == 0) 1.0 else if (meetingIndex == 1) 0.5 else 0.0
        return base * strength * repeatFactor
    }

    data class WeeklyScore(val points: Int, val games: Int, val wins: Int, val opponents: Int)

    fun weeklyScore(userId: String, records: List<MatchRecord>, week: DateInterval): WeeklyScore {
        val list = records
            .filter { it.date in week && it.team(userId) != null }
            .sortedBy { it.date }
            .take(WEEKLY_GAME_CAP)
        val meetings = HashMap<String, Int>()
        var total = 0.0
        for (record in list) {
            val key = record.opponentKey(userId)
            total += points(record, userId, meetings.getOrDefault(key, 0))
            meetings[key] = meetings.getOrDefault(key, 0) + 1
        }
        return WeeklyScore(
            roundHalfAway(total).toInt(), list.size, list.count { it.didWin(userId) },
            list.flatMap { it.opponents(userId) }.toSet().size,
        )
    }

    /** 全球周榜（可按国家筛选）：积分高的在前 */
    fun weeklyBoard(
        records: List<MatchRecord>, week: DateInterval, countryCode: String? = null, eligible: (String) -> Boolean,
    ): List<Entry> {
        val inWeek = records.filter { it.date in week && (countryCode == null || it.countryCode == countryCode) }
        val players = inWeek.flatMap { it.teams.flatten() }.toSet().filter(eligible)
        val rows = players.mapNotNull { userId ->
            val score = weeklyScore(userId, inWeek, week)
            if (score.games < WEEKLY_MINIMUM_GAMES || score.opponents < WEEKLY_MINIMUM_OPPONENTS) return@mapNotNull null
            Row(userId, score.points, score.games, score.wins)
        }
        return ranked(rows)
    }

    /** 排序并给出名次（同分同名次） */
    private fun ranked(rows: List<Row>): List<Entry> {
        val sorted = rows.sortedWith(compareByDescending<Row> { it.score }.thenByDescending { it.wins }.thenBy { it.userId })
        val entries = mutableListOf<Entry>()
        for ((index, row) in sorted.withIndex()) {
            val tied = index > 0 && sorted[index - 1].score == row.score && sorted[index - 1].wins == row.wins
            entries += Entry(row.userId, if (tied) entries[index - 1].rank else index + 1, row.score, row.games, row.wins)
        }
        return entries
    }
}
