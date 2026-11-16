package com.badie.app.features.matching

import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Coordinate
import com.badie.app.models.CostSplit
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.GameMode
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlot
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.User
import com.badie.app.models.UserPreferences
import com.badie.app.models.Venue
import com.badie.app.models.addingDays
import com.badie.app.models.startOfDay
import com.badie.app.models.zoned
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToInt

// 对应 iPhone 的 Services/MatchingService.swift：匹配请求、候选人、方案、放宽建议（纯函数，便于测试）。
// 正式后端由服务器匹配，App 里只用到 MatchRelaxation 的说法；算法照搬，测试也照搬

/** 匹配请求 */
data class MatchRequest(
    val mode: GameMode,
    val slot: TimeSlot,
    /** 用户选择的球馆（1-3 个） */
    val courts: List<Venue>,
    /** 可接受的水平差（1、2 或 8=不限） */
    val skillTolerance: Int,
    val userId: String,
    val userLevel: Int,
    val userLocation: Coordinate,
    val radiusKm: Double,
    val excludedUserIds: Set<String> = emptySet(),
    /** 发起者的细分档位分值（为空时用整数等级） */
    val userRating: Double? = null,
) {
    val userTier: SkillTier get() = SkillTier.ofRating(userRating ?: userLevel.toDouble())

    companion object {
        const val ANY_SKILL = 8
    }
}

/** 某位球友在一段日期内的空闲情况 */
data class PlayerAvailability(
    val user: User,
    val location: Coordinate,
    val slots: List<TimeSlot>,
    /** 对方能去的球馆；空 = 没有限制（发起者选的球馆都可以） */
    val venues: List<Venue> = emptyList(),
)

data class MatchCandidate(
    val user: User,
    /** 与发起者的距离（公里） */
    val distanceKm: Double,
    /** 对方比我高几档（1 档 = 1/3 级） */
    val skillDifference: Int,
    /** 与发起者时间段的重叠部分 */
    val overlap: TimeSlot,
    /** 发起者所选球馆中，对方也能去的（同一家、已合并或 150 米内的同一处） */
    val courtIds: List<String> = emptyList(),
) {
    val id: String get() = user.id

    /** 排序分：水平差优先（每差 1 级 10 分），其次距离（越小越好） */
    val matchScore: Double get() = abs(skillDifference).toDouble() * 10 / 3 + distanceKm
}

/** 一个可确认的约球方案（单打 1 位对手，双打 3 位球友） */
data class MatchProposal(
    val id: String,
    val mode: GameMode,
    val others: List<MatchCandidate>,
    /** 截取后的比赛时间（≤ 2 小时） */
    val slot: TimeSlot,
    /** 所有人共同空闲的完整时间 */
    val commonOverlap: TimeSlot,
    val court: Venue,
    val teams: List<List<String>>,
    val cost: CostSplit,
    /** 匹配度 0-100 */
    val compatibility: Int,
)

/** 无结果时的放宽建议 */
sealed interface MatchRelaxation {
    data class WidenSkill(val value: Int) : MatchRelaxation
    data class WidenTime(val hours: Int) : MatchRelaxation
    data class WidenRadius(val km: Double) : MatchRelaxation
    data class OtherDay(val date: Long) : MatchRelaxation

    val id: String
        get() = when (this) {
            is WidenSkill -> "skill-$value"
            is WidenTime -> "time-$hours"
            is WidenRadius -> "radius-${km.toInt()}"
            is OtherDay -> "day-${date / 1000}"
        }

    val title: String
        get() = when (this) {
            is WidenSkill -> if (value >= MatchRequest.ANY_SKILL) tr("不限水平差") else tr("放宽到 ±%lld 级", value)
            is WidenTime -> tr("时间前后各放宽 %lld 小时", hours)
            is WidenRadius -> tr("扩大到 %@", DistanceFormatter.radius(km))
            is OtherDay -> tr("改到%@", DateText.relativeDay(date))
        }

    fun apply(request: MatchRequest, zone: ZoneId = ZoneId.systemDefault()): MatchRequest = when (this) {
        is WidenSkill -> request.copy(skillTolerance = value)
        is WidenTime -> request.copy(slot = request.slot.expanded(hours.toDouble(), zone))
        is WidenRadius -> request.copy(radiusKm = km)
        is OtherDay -> {
            val start = request.slot.startTime.zoned(zone)
            val end = request.slot.endTime.zoned(zone)
            val slot = TimeSlot.on(date, start.hour, start.minute, end.hour, end.minute, zone)
            if (slot != null) request.copy(slot = slot) else request
        }
    }
}

object MatchingService {
    /** 150 米内算同一处（同一栋楼的两个入口、别人加的“隔壁馆”） */
    private const val SAME_VENUE_METERS = 150.0

    /** 两家球馆是不是同一处：同一个 ID、合并过、或 150 米内 */
    fun sameVenue(a: Venue, b: Venue): Boolean {
        if (a.id == b.id) return true
        if (a.mergedInto == b.id || b.mergedInto == a.id) return true
        if (a.mergedInto != null && a.mergedInto == b.mergedInto) return true
        return a.location.distanceKm(b.location) * 1000 <= SAME_VENUE_METERS
    }

    /** 过滤并排序候选人：同城半径内、时间重叠 ≥ 30 分钟、水平差在容忍范围内 */
    fun candidates(request: MatchRequest, pool: List<PlayerAvailability>): List<MatchCandidate> = pool.mapNotNull { entry ->
        val user = entry.user
        if (user.id == request.userId || user.id in request.excludedUserIds) return@mapNotNull null
        val distance = entry.location.distanceKm(request.userLocation)
        if (distance > request.radiusKm) return@mapNotNull null
        // 按细分档位比较：容忍 1 级 = 上下 3 档
        val difference = request.userTier.steps(user.displayTier)
        if (abs(difference) > request.skillTolerance * 3) return@mapNotNull null
        val best = entry.slots.mapNotNull { it.overlaps(request.slot) }.maxByOrNull { it.duration } ?: return@mapNotNull null
        // 球馆对不上就约不成：只看双方都能去的球馆
        val shared = request.courts.filter { court -> entry.venues.isEmpty() || entry.venues.any { sameVenue(court, it) } }
        if (shared.isEmpty()) return@mapNotNull null
        MatchCandidate(user, distance, difference, best, shared.map { it.id })
    }.sortedWith(compareBy<MatchCandidate> { it.matchScore }.thenByDescending { it.user.reputation.compositeScore })

    /** 生成约球方案 */
    fun proposals(request: MatchRequest, pool: List<PlayerAvailability>, limit: Int = 5): List<MatchProposal> {
        val ranked = candidates(request, pool)
        if (ranked.isEmpty() || request.courts.isEmpty()) return emptyList()
        return when (request.mode) {
            GameMode.Singles -> ranked.take(limit).mapNotNull { makeProposal(request, listOf(it), it.overlap) }
            GameMode.Doubles -> {
                val top = ranked.take(8)
                if (top.size < 3) return emptyList()
                data class Group(val score: Double, val others: List<MatchCandidate>, val overlap: TimeSlot)
                val groups = mutableListOf<Group>()
                for (i in top.indices) for (j in i + 1 until top.size) for (k in j + 1 until top.size) {
                    val group = listOf(top[i], top[j], top[k])
                    val overlap = commonOverlap(group.map { it.overlap }) ?: continue
                    if (sharedCourts(request, group).isEmpty()) continue
                    val score = group.sumOf { it.matchScore } + spread(group, request.userTier.rating) * 5
                    groups += Group(score, group, overlap)
                }
                groups.sortBy { it.score }
                val used = HashSet<String>()
                val results = mutableListOf<MatchProposal>()
                for (group in groups) {
                    if (results.size >= limit) break
                    val key = group.others.map { it.id }.sorted().joinToString(",")
                    if (!used.add(key)) continue
                    makeProposal(request, group.others, group.overlap)?.let { results += it }
                }
                results
            }
        }
    }

    /** 无结果时，找出确实能带来结果的放宽方式（最多 3 条） */
    fun suggestions(
        request: MatchRequest, pool: List<PlayerAvailability>, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(),
    ): List<MatchRelaxation> {
        val options = mutableListOf<MatchRelaxation>()
        if (request.skillTolerance < 2) options += MatchRelaxation.WidenSkill(2)
        if (request.skillTolerance < MatchRequest.ANY_SKILL) options += MatchRelaxation.WidenSkill(MatchRequest.ANY_SKILL)
        options += MatchRelaxation.WidenTime(1)
        options += MatchRelaxation.WidenTime(2)
        if (request.radiusKm < UserPreferences.MAXIMUM_TRAVEL_RADIUS) {
            options += MatchRelaxation.WidenRadius(minOf(UserPreferences.MAXIMUM_TRAVEL_RADIUS, request.radiusKm * 2))
        }
        val limit = addingDays(startOfDay(now, zone), TimeSlotConstants.MAXIMUM_DAYS_AHEAD, zone)
        for (offset in 1..3) {
            val day = addingDays(request.slot.date, offset, zone)
            if (day <= limit) options += MatchRelaxation.OtherDay(day)
        }
        val useful = mutableListOf<MatchRelaxation>()
        val seenKinds = HashSet<String>()
        for (option in options) {
            val kind = option.id.substringBefore("-")
            if (kind in seenKinds) continue
            if (proposals(option.apply(request, zone), pool, limit = 1).isNotEmpty()) {
                useful += option
                seenKinds += kind
            }
            if (useful.size == 3) break
        }
        return useful
    }

    /** 多个时间段的共同重叠（≥ 30 分钟） */
    fun commonOverlap(slots: List<TimeSlot>): TimeSlot? {
        var current = slots.firstOrNull() ?: return null
        for (slot in slots.drop(1)) current = current.overlaps(slot) ?: return null
        return current
    }

    /** 双打分组：按水平排序后 1+4 vs 2+3，保证两队总水平接近 */
    fun balancedTeams(players: List<Pair<String, Double>>): List<List<String>> {
        if (players.size != 4) return players.map { listOf(it.first) }
        val sorted = players.sortedByDescending { it.second }
        return listOf(listOf(sorted[0].first, sorted[3].first), listOf(sorted[1].first, sorted[2].first))
    }

    /** 所有人都能去的球馆 */
    fun sharedCourts(request: MatchRequest, others: List<MatchCandidate>): List<Venue> =
        request.courts.filter { court -> others.all { it.courtIds.isEmpty() || court.id in it.courtIds } }

    /** 选择对所有人最方便、且在该时段营业的球馆 */
    fun bestCourt(request: MatchRequest, locations: List<Coordinate>, slot: TimeSlot, among: List<Venue>? = null): Venue? {
        val candidates = among ?: request.courts
        // 营业时间未知的球馆视为可用（无法判断），已知不营业的排除
        val open = candidates.filter { it.isOpen(slot) }
        return open.ifEmpty { candidates }.minByOrNull { court -> locations.sumOf { court.location.distanceKm(it) } }
    }

    private fun spread(group: List<MatchCandidate>, userRating: Double): Double {
        val ratings = group.map { it.user.displayTier.rating } + userRating
        return (ratings.maxOrNull() ?: 0.0) - (ratings.minOrNull() ?: 0.0)
    }

    private fun makeProposal(request: MatchRequest, others: List<MatchCandidate>, overlap: TimeSlot): MatchProposal? {
        val gameSlot = overlap.trimmedForGame()
        val locations = listOf(request.userLocation) + others.mapNotNull { it.user.location }
        val court = bestCourt(request, locations, gameSlot, sharedCourts(request, others)) ?: return null
        val teams = if (request.mode == GameMode.Doubles) {
            balancedTeams(listOf(request.userId to request.userTier.rating) + others.map { it.user.id to it.user.displayTier.rating })
        } else {
            listOf(listOf(request.userId), others.map { it.user.id })
        }
        val averageDiff = others.sumOf { abs(it.skillDifference) }.toDouble() / 3 / others.size
        val averageDistance = others.sumOf { it.distanceKm } / others.size
        val reputation = others.sumOf { if (it.user.isNewPlayer) 80 else it.user.reputation.compositeScore }.toDouble() / others.size
        val raw = 100 - averageDiff * 14 - averageDistance * 1.5 - (100 - reputation) * 0.2
        val compatibility = minOf(99.0, maxOf(35.0, raw)).roundToInt()
        return MatchProposal(
            UUID.randomUUID().toString(), request.mode, others, gameSlot, overlap, court, teams,
            CostSplit.estimate(court, gameSlot, request.mode), compatibility,
        )
    }
}
