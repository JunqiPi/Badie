package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import com.badie.app.remote.InstantSerializer
import kotlinx.serialization.Serializable
import java.time.Instant

// MARK: - 球群当晚：排场、比赛（服务器的 JSON，见 Badie-iOS/docs/CLUB_NIGHT.md 的“接口”）
// 对应 iPhone 的 Models/ClubNight.swift。收款的那几样（收款方式、金额、付款链接、NightPay、MyDue、收款记录）在 Payments.kt。
// 字段名按 RemoteJSON 的规则从 snake_case 转过来；服务器可能给 null 的都写成可空

/** 帮手（当晚或比赛） */
@Serializable
data class NightHelper(val id: String, val nickname: String)

/** 当晚页（night_state）：只有组织者和帮手拿得到 */
@Serializable
data class NightState(
    val sessionId: String,
    val groupId: String,
    val group: String,
    val venue: String? = null,
    @Serializable(InstantSerializer::class) val startsAt: Instant,
    @Serializable(InstantSerializer::class) val endsAt: Instant,
    /** organizer | helper */
    val role: String,
    /** 开场前 1 小时到结束后 3 小时：能改排场 */
    val open: Boolean,
    val started: Boolean,
    val courts: Int,
    val doubles: Boolean,
    val balance: Boolean,
    val boardCode: String? = null,
    val matchId: String? = null,
    val matchLive: Boolean = false,
    val helpers: List<NightHelper> = emptyList(),
    @Serializable(InstantSerializer::class) val undoUntil: Instant? = null,
    val people: List<Person> = emptyList(),
    val games: List<Game> = emptyList(),
    /** 接下来两场（报名 id） */
    val next: List<List<String>> = emptyList(),
) {
    @Serializable
    data class Person(
        /** 报名那一行的 id（访客也有） */
        val id: String,
        val name: String,
        val userId: String? = null,
        val guest: Boolean,
        /** absent | here | resting | left */
        val status: String,
        val waitlisted: Boolean = false,
        val games: Int = 0,
        /** 在哪片场地上打（不在场上为 null） */
        val onCourt: Int? = null,
        val nextUp: Boolean = false,
        /** 等候的人排第几（和排人的顺序一样；不在等候为 null） */
        val queue: Int? = null,
    )

    @Serializable
    data class Game(
        val id: Int,
        val court: Int,
        /** 报名 id；双打前两个一队 */
        val players: List<String>,
        @Serializable(InstantSerializer::class) val startedAt: Instant,
    )

    val isOrganizer: Boolean get() = role == "organizer"

    fun person(id: String): Person? = people.firstOrNull { it.id == id }

    fun name(id: String): String = person(id)?.name ?: "?"

    /** 一场的两边：双打前两个一队 */
    fun sides(players: List<String>): Pair<List<String>, List<String>> {
        val half = players.size / 2
        return players.take(half) to players.drop(half)
    }

    /** 到了、不在场上的人，按排队的顺序（旧数据没有顺序时：手动放到下一场的在前，再按今晚打的场数） */
    val waiting: List<Person>
        get() = people.withIndex()
            .filter { it.value.status == "here" && it.value.onCourt == null }
            .sortedWith { lhs, rhs ->
                val left = lhs.value
                val right = rhs.value
                when {
                    left.queue != null && right.queue != null -> left.queue.compareTo(right.queue)
                    left.nextUp != right.nextUp -> if (left.nextUp) -1 else 1
                    left.games != right.games -> left.games.compareTo(right.games)
                    else -> lhs.index.compareTo(rhs.index)
                }
            }
            .map { it.value }

    val hereCount: Int get() = people.count { it.status == "here" }

    /** 要显示的场地：设置的几片，加上减场地后还没打完的 */
    val courtNumbers: List<Int> get() = ((1..maxOf(1, courts)).toList() + games.map { it.court }).toSortedSet().toList()
}

/** 球群页的当天场次（group_tonight） */
@Serializable
data class GroupTonight(
    val id: String,
    @Serializable(InstantSerializer::class) val startsAt: Instant,
    @Serializable(InstantSerializer::class) val endsAt: Instant,
    /** 组织者、帮手显示“排场” */
    val canRun: Boolean? = null,
    /** 排场开始后的看板码：成员的“看排场” */
    val board: String? = null,
    /** 我要付的钱 */
    val pay: Pay? = null,
    /** 组织者：还有几个人没付 */
    val unpaid: Int? = null,
) {
    @Serializable
    data class Pay(
        val to: String,
        val amount: Double? = null,
        val handles: PaymentHandles? = null,
        val paid: Boolean,
        val paidSelf: Boolean? = null,
    )

    /** 写了金额、还没付的由球群页最上面的“你还没付”卡（DuesCard）收，场次行上只管没写金额的和已付的 */
    val paysHere: Boolean
        get() {
            val pay = pay ?: return false
            return pay.paid || (pay.amount ?: 0.0) <= 0
        }

    /** 组织者、帮手有“排场”，不用换掉报名按钮 */
    val replacesSignup: Boolean get() = paysHere || (board != null && canRun != true)

    /** 已经结束、不在“接下来的场次”里的这一场还有没有要做的（付钱、收款、排场） */
    val hasAction: Boolean get() = canRun == true || (unpaid ?: 0) > 0 || replacesSignup
}

/** 球局页最上面的“今晚”（my_tonight） */
@Serializable
data class TonightItem(
    /** night | match */
    val kind: String,
    val sessionId: String? = null,
    val groupId: String? = null,
    val matchId: String? = null,
    val name: String,
    val boardCode: String? = null,
    /** court | next | waiting | resting */
    val status: String,
    val court: Int? = null,
    val round: Int? = null,
    val games: Int? = null,
) {
    val id: String get() = sessionId ?: matchId ?: name

    /** “你在场地 2”“下一场是你”“等候中 · 今晚打了 2 场” */
    val statusText: String
        get() = when (status) {
            "court" -> tr("你在场地 %lld", court ?: 0)
            "next" -> tr("下一场是你")
            "resting" -> tr("休息中 · 今晚打了 %lld 场", games ?: 0)
            else -> tr("等候中 · 今晚打了 %lld 场", games ?: 0)
        }
}

// MARK: - 比赛

/** 赛制：循环 / 小组赛 + 淘汰赛 / 瑞士轮 / 单淘汰 */
enum class MatchFormat(val raw: String) {
    RoundRobin("round_robin"), Groups("groups"), Swiss("swiss"), Knockout("knockout");

    val title: String
        get() = when (this) {
            RoundRobin -> tr("循环赛")
            Groups -> tr("小组赛 + 淘汰赛")
            Swiss -> tr("瑞士轮")
            Knockout -> tr("单淘汰")
        }

    /** 自己定打几轮的：循环、瑞士轮 */
    val byRounds: Boolean get() = this == RoundRobin || this == Swiss

    /** 有淘汰赛的：可以打三四名 */
    val hasKnockout: Boolean get() = this == Groups || this == Knockout

    companion object {
        fun of(raw: String): MatchFormat? = entries.firstOrNull { it.raw == raw }

        /** “循环赛 · 单打”；轮换搭档只有循环，就写“双打轮换搭档” */
        fun title(format: String, play: String?): String {
            if (play == MatchPlay.Rotating.raw) return MatchPlay.Rotating.title
            val name = of(format)?.title ?: format
            val mode = play?.let(MatchPlay::of) ?: return name
            return "$name · ${mode.title}"
        }
    }
}

/** 参赛方式：单打 / 双打固定搭档 / 双打轮换搭档（只配循环） */
enum class MatchPlay(val raw: String) {
    Singles("singles"), Fixed("fixed"), Rotating("rotating");

    val title: String
        get() = when (this) {
            Singles -> tr("单打")
            Fixed -> tr("双打固定搭档")
            Rotating -> tr("双打轮换搭档")
        }

    companion object {
        fun of(raw: String): MatchPlay? = entries.firstOrNull { it.raw == raw }
    }
}

object MatchSetup {
    /** 人数够不够这个赛制：不够时返回给人看的话（服务器还会再查一次） */
    fun countProblem(format: MatchFormat, play: MatchPlay, players: Int, pools: Int, advance: Int): String? {
        val per = if (play == MatchPlay.Fixed) 2 else 1
        val entries = players / per
        if (players > 64 || players < 2) return tr("要 2–64 人。")
        if (play == MatchPlay.Rotating && players < 4) return tr("双打轮换搭档要 4–64 人。")
        if (play == MatchPlay.Fixed && (players < 4 || players % 2 == 1)) return tr("双打固定搭档要 4–64 人，而且是双数。")
        if (format == MatchFormat.Swiss && entries < 3) return tr("瑞士轮至少要 %lld 人。", 3 * per)
        if (format == MatchFormat.Groups && entries < pools * (advance + 1)) {
            return tr("%lld 组至少要 %lld 人。", pools, pools * (advance + 1) * per)
        }
        return null
    }
}

/** 比分规则（和服务器的 score_winner、retire_scores_ok 一样） */
object MatchScoring {
    sealed interface Check {
        /** 还没填 */
        data object Empty : Check
        data class Winner(val side: Int) : Check
        data class Problem(val text: String) : Check
    }

    data class Rules(val points: Int, val bestOf: Int, val winByTwo: Boolean)

    /** 加分时打到几封顶：21 → 30、15 → 21、11 → 15 */
    fun cap(points: Int): Int = mapOf(21 to 30, 15 to 21, 11 to 15)[points] ?: points

    fun gameDone(hi: Int, lo: Int, rules: Rules): Boolean {
        if (lo < 0 || hi <= lo) return false
        if (!rules.winByTwo) return hi == rules.points
        val top = cap(rules.points)
        return (hi == rules.points && lo <= rules.points - 2) ||
            (hi > rules.points && hi <= top && (hi - lo == 2 || (hi == top && lo == hi - 1)))
    }

    /** 打得出来、但还没打完的一局 */
    fun unfinished(hi: Int, lo: Int, rules: Rules): Boolean =
        hi < rules.points || (rules.winByTwo && lo >= rules.points - 1 && hi - lo <= 1 && hi < cap(rules.points))

    /** 去掉后面没填的局（0–0） */
    fun played(scores: List<Int>): List<Int> {
        var end = scores.size
        while (end >= 2 && scores[end - 1] == 0 && scores[end - 2] == 0) end -= 2
        return scores.take(end)
    }

    /** 一局不合规时说哪里不对 */
    fun gameProblem(a: Int, b: Int, game: Int, rules: Rules): String {
        val hi = maxOf(a, b)
        val lo = minOf(a, b)
        val score = "$a–$b"
        val text = when {
            unfinished(hi, lo, rules) -> tr("%@ 还没打完。", score)
            rules.winByTwo -> tr("%@ 打不出来：%lld 分一局，要领先 2 分，最多到 %lld。", score, rules.points, cap(rules.points))
            else -> tr("%@ 打不出来：一局打到 %lld 分就结束。", score, rules.points)
        }
        return if (rules.bestOf == 1) text else tr("第 %lld 局：%@", game, text)
    }

    /** 输的比分（已经去掉了后面没填的局）：合规就是赢的一边 */
    fun check(scores: List<Int>, rules: Rules): Check {
        if (scores.isEmpty()) return Check.Empty
        val need = rules.bestOf / 2 + 1
        val wins = intArrayOf(0, 0)
        for (game in 0 until scores.size / 2) {
            if (wins[0] == need || wins[1] == need) return Check.Problem(tr("前两局已经分出胜负，第 3 局不用填。"))
            val a = scores[game * 2]
            val b = scores[game * 2 + 1]
            if (!gameDone(maxOf(a, b), minOf(a, b), rules)) return Check.Problem(gameProblem(a, b, game + 1, rules))
            wins[if (a > b) 0 else 1] += 1
        }
        if (wins[0] < need && wins[1] < need) return Check.Problem(tr("三局两胜，要有一边赢满两局。"))
        return Check.Winner(if (wins[0] == need) 1 else 2)
    }

    /** 中途退赛的比分：前面的局打完了、还没分出胜负，最后一局可以没打完。合规是 null */
    fun retireProblem(scores: List<Int>, rules: Rules): String? {
        val need = rules.bestOf / 2 + 1
        val wins = intArrayOf(0, 0)
        val games = scores.size / 2
        for (game in 0 until games) {
            val a = scores[game * 2]
            val b = scores[game * 2 + 1]
            if (gameDone(maxOf(a, b), minOf(a, b), rules)) {
                wins[if (a > b) 0 else 1] += 1
            } else if (game < games - 1 || !unfinished(maxOf(a, b), minOf(a, b), rules)) {
                return gameProblem(a, b, game + 1, rules)
            }
        }
        if (wins[0] >= need || wins[1] >= need) return tr("已经分出胜负了，直接保存比分就行。")
        return null
    }
}

/** 比赛页（match_state） */
@Serializable
data class MatchState(
    val id: String,
    val name: String,
    val format: String,
    val play: String? = null,
    val thirdPlace: Boolean? = null,
    val doubles: Boolean,
    val points: Int,
    val bestOf: Int,
    val winByTwo: Boolean,
    val courts: Int,
    val rounds: Int,
    val round: Int? = null,
    val pools: Int? = null,
    val advance: Int? = null,
    /** live | done */
    val status: String,
    @Serializable(InstantSerializer::class) val createdAt: Instant,
    @Serializable(InstantSerializer::class) val endedAt: Instant? = null,
    val boardCode: String,
    val sessionId: String? = null,
    val venue: String? = null,
    val tieAtCut: Boolean? = null,
    val players: List<Player> = emptyList(),
    val games: List<Game> = emptyList(),
    val standings: List<Standing> = emptyList(),
    val ranking: List<Standing>? = null,
    /** organizer | helper | player */
    val role: String? = null,
    /** 我在这场比赛里的球员 id */
    val me: String? = null,
    val helpers: List<NightHelper>? = null,
    @Serializable(InstantSerializer::class) val undoUntil: Instant? = null,
) {
    @Serializable
    data class Player(
        val id: String,
        val name: String,
        val team: Int? = null,
        val pool: Int? = null,
        val withdrawn: Boolean = false,
        /** 注册用户（只有组织者、帮手拿得到） */
        val userId: String? = null,
    )

    @Serializable
    data class Game(
        val id: Int,
        val round: Int,
        /** pool | ko（淘汰赛，koSize 是这一轮的签位数：2 = 决赛）| third（三四名） */
        val stage: String,
        val pool: Int? = null,
        val koSize: Int? = null,
        val slot: Int? = null,
        /** 轮空：不是一场球，不显示 */
        val bye: Boolean? = null,
        /** 中途退赛的一边（1 / 2） */
        val retired: Int? = null,
        val a: List<String> = emptyList(),
        val b: List<String> = emptyList(),
        val court: Int? = null,
        /** queued | playing | done | cancelled | skipped */
        val status: String,
        /** 每局两个数：[a1, b1, a2, b2, …] */
        val scores: List<Int>? = null,
        val winner: Int? = null,
        val walkover: Boolean? = null,
        val version: Int? = null,
        val scoredBy: String? = null,
        val editedBy: String? = null,
        val flagged: Boolean? = null,
    )

    /** 积分榜、最终排名的一行：一个人或一队 */
    @Serializable
    data class Standing(
        val key: String,
        val name: String,
        val members: List<String> = emptyList(),
        val pool: Int? = null,
        val played: Int,
        val wins: Int,
        val losses: Int,
        val pf: Int,
        val pa: Int,
        val diff: Int,
        val rank: Int,
        val tied: Boolean? = null,
        val withdrawn: Boolean? = null,
    )

    val isLive: Boolean get() = status == "live"

    /** 轮空不是一场球 */
    val realGames: List<Game> get() = games.filter { it.bye != true }
    val matchFormat: MatchFormat get() = MatchFormat.of(format) ?: MatchFormat.RoundRobin
    val scoring: MatchScoring.Rules get() = MatchScoring.Rules(points, bestOf, winByTwo)
    val canManage: Boolean get() = role == "organizer" || role == "helper"
    val isOrganizer: Boolean get() = role == "organizer"

    fun name(playerId: String): String = players.firstOrNull { it.id == playerId }?.name ?: "?"

    fun sideName(ids: List<String>): String = ids.joinToString(" · ") { name(it) }

    /** 能不能输这一场的比分：组织者、帮手随时能改；球员只能在打的时候输自己那场 */
    fun canScore(game: Game): Boolean {
        if (game.status == "cancelled" || game.bye == true) return false
        if (canManage) return isLive || game.status == "done"
        val me = me ?: return false
        return game.status == "playing" && (me in game.a || me in game.b)
    }

    fun isMine(game: Game): Boolean {
        val me = me ?: return false
        return me in game.a || me in game.b
    }
}

/** 我的 → 比赛（my_matches） */
@Serializable
data class MyMatch(
    val id: String,
    val name: String,
    val format: String,
    val play: String? = null,
    val status: String,
    @Serializable(InstantSerializer::class) val createdAt: Instant,
    @Serializable(InstantSerializer::class) val endedAt: Instant? = null,
    val players: Int,
    val rank: Int? = null,
)

/** 新建比赛前的预计（match_preview） */
@Serializable
data class MatchPreview(
    /** 循环打满一遍的轮数 */
    val fullRounds: Int,
    /** 能选几轮：默认、最多 */
    val defaultRounds: Int,
    val maxRounds: Int,
    val rounds: Int,
    val minutes: Double,
)

/** 比赛的规则文字和显示用的小函数（iPhone 的 MatchRules） */
object MatchRules {
    val points: List<String>
        get() = listOf(
            tr("先看胜场；打的场数不一样时看胜率。"),
            tr("再看净胜分、总得分。"),
            tr("还一样就看两人（两队）之间的胜负。"),
            tr("三人以上还分不开，写并列。"),
        )

    /** +5、−2、0 */
    fun diffText(diff: Int): String = when {
        diff > 0 -> "+$diff"
        diff < 0 -> "−${-diff}"
        else -> "0"
    }

    /** 比分：“21–18 19–21” */
    fun scoreText(scores: List<Int>): String =
        (0 until scores.size - 1 step 2).joinToString(" ") { "${scores[it]}–${scores[it + 1]}" }

    /** 这一场叫什么：第几轮、四分之一决赛、半决赛、决赛、三四名决赛、16 强 */
    fun stageTitle(game: MatchState.Game): String {
        if (game.stage == "third") return tr("三四名决赛")
        if (game.stage == "ko") {
            return when (game.koSize ?: 0) {
                2 -> tr("决赛")
                4 -> tr("半决赛")
                8 -> tr("四分之一决赛")
                else -> tr("%lld 强", game.koSize ?: 0)
            }
        }
        return tr("第 %lld 轮", game.round)
    }

    /** 全部对阵里右边那一格 */
    fun result(game: MatchState.Game): String = when (game.status) {
        "done" -> when {
            game.walkover == true -> tr("已退赛")
            game.retired != null -> listOf(scoreText(game.scores.orEmpty()), tr("中途退赛")).filter { it.isNotEmpty() }.joinToString(" · ")
            else -> scoreText(game.scores.orEmpty())
        }
        "playing" -> game.court?.let { tr("场地 %lld", it) } ?: ""
        "cancelled" -> tr("取消")
        "skipped" -> tr("没打")
        else -> ""
    }
}
