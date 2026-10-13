import Foundation

// MARK: - 匹配请求与结果

struct MatchRequest: Hashable {
    var mode: GameMode
    var slot: TimeSlot
    /// 用户选择的球馆（1-3 个）
    var courts: [BadmintonCourt]
    /// 可接受的水平差（1、2 或 8=不限）
    var skillTolerance: Int
    var userId: String
    var userLevel: Int
    var userLocation: Coordinate
    var radiusKm: Double
    var excludedUserIds: Set<String>

    static let anySkill = 8
}

/// 某位球友在一段日期内的空闲情况
struct PlayerAvailability: Hashable {
    let user: User
    let location: Coordinate
    let slots: [TimeSlot]
}

struct MatchCandidate: Identifiable, Hashable {
    var id: String { user.id }
    let user: User
    /// 与发起者的距离（公里）
    let distanceKm: Double
    /// 对方等级 - 我的等级
    let skillDifference: Int
    /// 与发起者时间段的重叠部分
    let overlap: TimeSlot

    /// 排序分：水平差优先，其次距离（越小越好）
    var matchScore: Double {
        Double(abs(skillDifference)) * 10 + distanceKm
    }

    var formattedSkillDifference: String {
        switch skillDifference {
        case 0: return "同水平"
        case let diff where diff > 0: return "高 \(diff) 级"
        default: return "低 \(-skillDifference) 级"
        }
    }
}

/// 一个可确认的约球方案（单打 1 位对手，双打 3 位球友）
struct MatchProposal: Identifiable, Hashable {
    let id: String
    let mode: GameMode
    let others: [MatchCandidate]
    /// 截取后的比赛时间（≤ 2 小时）
    let slot: TimeSlot
    /// 所有人共同空闲的完整时间
    let commonOverlap: TimeSlot
    let court: BadmintonCourt
    let teams: [[String]]
    let cost: CostSplit
    /// 匹配度 0-100
    let compatibility: Int

    var primary: MatchCandidate? { others.first }
}

/// 无结果时的放宽建议
enum MatchRelaxation: Hashable, Identifiable {
    case widenSkill(Int)
    case widenTime(hours: Int)
    case widenRadius(km: Double)
    case otherDay(Date)

    var id: String {
        switch self {
        case .widenSkill(let value): return "skill-\(value)"
        case .widenTime(let hours): return "time-\(hours)"
        case .widenRadius(let km): return "radius-\(Int(km))"
        case .otherDay(let date): return "day-\(Int(date.timeIntervalSince1970))"
        }
    }

    var title: String {
        switch self {
        case .widenSkill(let value):
            return value >= MatchRequest.anySkill ? "不限水平差" : "放宽到 ±\(value) 级"
        case .widenTime(let hours): return "时间前后各放宽 \(hours) 小时"
        case .widenRadius(let km): return "扩大到 \(Int(km)) 公里"
        case .otherDay(let date): return "改到\(DateText.relativeDay(date))"
        }
    }

    var icon: String {
        switch self {
        case .widenSkill: return "chart.bar.fill"
        case .widenTime: return "clock.fill"
        case .widenRadius: return "location.circle.fill"
        case .otherDay: return "calendar"
        }
    }

    func apply(to request: MatchRequest) -> MatchRequest {
        var next = request
        switch self {
        case .widenSkill(let value):
            next.skillTolerance = value
        case .widenTime(let hours):
            next.slot = request.slot.expanded(byHours: Double(hours))
        case .widenRadius(let km):
            next.radiusKm = km
        case .otherDay(let date):
            let calendar = Calendar.current
            let start = calendar.dateComponents([.hour, .minute], from: request.slot.startTime)
            let end = calendar.dateComponents([.hour, .minute], from: request.slot.endTime)
            if let slot = TimeSlot.on(date, startHour: start.hour ?? 19, startMinute: start.minute ?? 0,
                                      endHour: end.hour ?? 21, endMinute: end.minute ?? 0) {
                next.slot = slot
            }
        }
        return next
    }
}

// MARK: - 匹配算法（纯函数，便于测试）

enum MatchingService {

    /// 过滤并排序候选人：同城半径内、时间重叠 ≥ 30 分钟、水平差在容忍范围内
    static func candidates(for request: MatchRequest, pool: [PlayerAvailability]) -> [MatchCandidate] {
        pool.compactMap { entry -> MatchCandidate? in
            let user = entry.user
            guard user.id != request.userId, !request.excludedUserIds.contains(user.id) else { return nil }
            let distance = entry.location.distanceKm(to: request.userLocation)
            guard distance <= request.radiusKm else { return nil }
            let difference = user.displayLevel - request.userLevel
            guard abs(difference) <= request.skillTolerance else { return nil }
            let overlaps = entry.slots.compactMap { $0.overlaps(with: request.slot) }
            guard let best = overlaps.max(by: { $0.duration < $1.duration }) else { return nil }
            return MatchCandidate(user: user, distanceKm: distance, skillDifference: difference, overlap: best)
        }
        .sorted { lhs, rhs in
            if lhs.matchScore != rhs.matchScore { return lhs.matchScore < rhs.matchScore }
            return lhs.user.reputation.compositeScore > rhs.user.reputation.compositeScore
        }
    }

    /// 生成约球方案
    static func proposals(for request: MatchRequest, pool: [PlayerAvailability], limit: Int = 5) -> [MatchProposal] {
        let ranked = candidates(for: request, pool: pool)
        guard !ranked.isEmpty, !request.courts.isEmpty else { return [] }

        switch request.mode {
        case .singles:
            return ranked.prefix(limit).compactMap { candidate in
                makeProposal(request: request, others: [candidate], overlap: candidate.overlap)
            }
        case .doubles:
            let top = Array(ranked.prefix(8))
            guard top.count >= 3 else { return [] }
            var groups: [(score: Double, others: [MatchCandidate], overlap: TimeSlot)] = []
            for i in 0..<top.count {
                for j in (i + 1)..<top.count {
                    for k in (j + 1)..<top.count {
                        let group = [top[i], top[j], top[k]]
                        guard let overlap = commonOverlap(of: group.map(\.overlap)) else { continue }
                        let score = group.reduce(0) { $0 + $1.matchScore } + spread(of: group, userLevel: request.userLevel) * 5
                        groups.append((score, group, overlap))
                    }
                }
            }
            groups.sort { $0.score < $1.score }
            var used = Set<String>()
            var results: [MatchProposal] = []
            for group in groups where results.count < limit {
                let key = group.others.map(\.id).sorted().joined(separator: ",")
                guard !used.contains(key) else { continue }
                used.insert(key)
                if let proposal = makeProposal(request: request, others: group.others, overlap: group.overlap) {
                    results.append(proposal)
                }
            }
            return results
        }
    }

    /// 无结果时，找出确实能带来结果的放宽方式（最多 3 条）
    static func suggestions(for request: MatchRequest, pool: [PlayerAvailability], now: Date = Date()) -> [MatchRelaxation] {
        var options: [MatchRelaxation] = []
        if request.skillTolerance < 2 { options.append(.widenSkill(2)) }
        if request.skillTolerance < MatchRequest.anySkill { options.append(.widenSkill(MatchRequest.anySkill)) }
        options.append(.widenTime(hours: 1))
        options.append(.widenTime(hours: 2))
        if request.radiusKm < UserPreferences.maximumTravelRadius {
            options.append(.widenRadius(km: min(UserPreferences.maximumTravelRadius, request.radiusKm * 2)))
        }
        let calendar = Calendar.current
        for offset in 1...3 {
            if let day = calendar.date(byAdding: .day, value: offset, to: request.slot.date),
               let limit = calendar.date(byAdding: .day, value: TimeSlotConstants.maximumDaysAhead, to: calendar.startOfDay(for: now)),
               day <= limit {
                options.append(.otherDay(day))
            }
        }

        var useful: [MatchRelaxation] = []
        var seenKinds = Set<String>()
        for option in options {
            let kind = String(option.id.prefix(while: { $0 != "-" }))
            guard !seenKinds.contains(kind) else { continue }
            if !proposals(for: option.apply(to: request), pool: pool, limit: 1).isEmpty {
                useful.append(option)
                seenKinds.insert(kind)
            }
            if useful.count == 3 { break }
        }
        return useful
    }

    // MARK: Helpers

    /// 多个时间段的共同重叠（≥ 30 分钟）
    static func commonOverlap(of slots: [TimeSlot]) -> TimeSlot? {
        guard var current = slots.first else { return nil }
        for slot in slots.dropFirst() {
            guard let next = current.overlaps(with: slot) else { return nil }
            current = next
        }
        return current
    }

    /// 双打分组：按水平排序后 1+4 vs 2+3，保证两队总水平接近
    static func balancedTeams(players: [(id: String, level: Int)]) -> [[String]] {
        guard players.count == 4 else { return players.map { [$0.id] } }
        let sorted = players.sorted { $0.level > $1.level }
        return [[sorted[0].id, sorted[3].id], [sorted[1].id, sorted[2].id]]
    }

    /// 选择对所有人最方便、且在该时段营业的球馆
    static func bestCourt(for request: MatchRequest, locations: [Coordinate], slot: TimeSlot) -> BadmintonCourt? {
        let open = request.courts.filter { $0.operatingHours.covers(slot) }
        let pool = open.isEmpty ? request.courts : open
        return pool.min { lhs, rhs in
            totalDistance(lhs, locations) < totalDistance(rhs, locations)
        }
    }

    private static func totalDistance(_ court: BadmintonCourt, _ locations: [Coordinate]) -> Double {
        locations.reduce(0) { $0 + court.location.distanceKm(to: $1) }
    }

    private static func spread(of group: [MatchCandidate], userLevel: Int) -> Double {
        let levels = group.map(\.user.displayLevel) + [userLevel]
        guard let high = levels.max(), let low = levels.min() else { return 0 }
        return Double(high - low)
    }

    private static func makeProposal(request: MatchRequest, others: [MatchCandidate], overlap: TimeSlot) -> MatchProposal? {
        let gameSlot = overlap.trimmedForGame()
        let locations = [request.userLocation] + others.compactMap { $0.user.location }
        guard let court = bestCourt(for: request, locations: locations, slot: gameSlot) else { return nil }

        let teams: [[String]]
        if request.mode == .doubles {
            let players = [(id: request.userId, level: request.userLevel)] + others.map { (id: $0.user.id, level: $0.user.displayLevel) }
            teams = balancedTeams(players: players)
        } else {
            teams = [[request.userId], others.map(\.user.id)]
        }

        let averageDiff = Double(others.reduce(0) { $0 + abs($1.skillDifference) }) / Double(others.count)
        let averageDistance = others.reduce(0) { $0 + $1.distanceKm } / Double(others.count)
        let reputation = Double(others.reduce(0) { $0 + ($1.user.isNewPlayer ? 80 : $1.user.reputation.compositeScore) }) / Double(others.count)
        let raw = 100 - averageDiff * 14 - averageDistance * 1.5 - (100 - reputation) * 0.2
        let compatibility = Int(min(99, max(35, raw)).rounded())

        return MatchProposal(
            id: UUID().uuidString,
            mode: request.mode,
            others: others,
            slot: gameSlot,
            commonOverlap: overlap,
            court: court,
            teams: teams,
            cost: CostSplit.estimate(court: court, slot: gameSlot, mode: request.mode),
            compatibility: compatibility
        )
    }
}
