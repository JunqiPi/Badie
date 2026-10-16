import Foundation

// MARK: - 赛果申报
//
// 一人先报“哪一队赢了”，其他人看到后点“对”或改成自己记得的结果。两队各至少一人报、且一致才算确认。
// 记不清的人选“记不清了”：不算确认也不算争议，这场不计入。报得不一样是“有分歧”，
// 7 天内任何人都可以改，改到一致照常计入。没有“超时自动确认”——虚报不会因为对方没理会就生效。

struct ResultReport: Codable, Hashable {
    let reporterId: String
    /// 获胜队伍在 `Game.teams` 里的下标；nil = 友谊局 / 没打完，不计胜负
    let winningTeam: Int?
    let score: String
    let reportedAt: Date
    /// 记不清了：不算确认，也不算争议
    var unsure = false
}

enum ResultStatus: Hashable {
    /// 还在等另一队确认
    case awaiting
    case verified(winningTeam: Int)
    /// 双方说法不一致：期限内可以改，改不到一致就不计入
    case disputed
    /// 双方都选了不计胜负
    case friendly
    /// 有一队全员记不清，无法确认
    case unsure
    /// 期限内没凑齐确认
    case expired
}

extension Game {
    /// 结束后多久内可以申报、确认赛果
    static let resultWindow: TimeInterval = 7 * 86400

    var resultDeadline: Date { slot.endTime.addingTimeInterval(Self.resultWindow) }

    func team(of userId: String) -> Int? {
        teams.firstIndex { $0.contains(userId) }
    }

    func report(by userId: String) -> ResultReport? {
        resultReports.first { $0.reporterId == userId }
    }

    func resultStatus(now: Date = Date()) -> ResultStatus {
        let claims = resultReports.filter { !$0.unsure }
        let outcomes = Set(claims.map(\.winningTeam))
        if outcomes.count > 1 { return .disputed }
        let claimingTeams = Set(claims.compactMap { team(of: $0.reporterId) })
        if claimingTeams.count == teams.count, let outcome = outcomes.first {
            return outcome.map { .verified(winningTeam: $0) } ?? .friendly
        }
        if teams.contains(where: { $0.allSatisfy { report(by: $0)?.unsure == true } }) { return .unsure }
        return now > resultDeadline ? .expired : .awaiting
    }

    /// 还能报或改赛果：确认之前、期限之内
    func acceptsResultReports(now: Date = Date()) -> Bool {
        guard status == .completed, now <= resultDeadline else { return false }
        switch resultStatus(now: now) {
        case .awaiting, .disputed, .unsure: return true
        case .verified, .friendly, .expired: return false
        }
    }
}

// MARK: - 计入排行的对局

/// 双方确认后的一场比赛（胜率、场馆榜、周榜都只用它）
struct MatchRecord: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let venueId: String
    let countryCode: String
    let mode: GameMode
    let teams: [[String]]
    let winningTeam: Int
    /// 赛时各人的等级分值，用来算对手强度
    let ratings: [String: Double]

    func team(of userId: String) -> Int? { teams.firstIndex { $0.contains(userId) } }

    func opponents(of userId: String) -> [String] {
        guard let mine = team(of: userId) else { return [] }
        return teams.enumerated().filter { $0.offset != mine }.flatMap(\.element)
    }

    func didWin(_ userId: String) -> Bool { team(of: userId) == winningTeam }

    /// 同一个对手（双打按对手组合）算一个“对手”
    func opponentKey(of userId: String) -> String { opponents(of: userId).sorted().joined(separator: "+") }

    /// 对手平均水平 − 我方平均水平（单位：级）
    func strengthGap(for userId: String) -> Double {
        guard let mine = team(of: userId) else { return 0 }
        func average(_ ids: [String]) -> Double {
            let values = ids.compactMap { ratings[$0] }
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        return average(opponents(of: userId)) - average(teams[mine])
    }
}

// MARK: - 水平段（场馆榜分段用）

enum LevelBracket: Int, CaseIterable, Identifiable, Codable {
    case starter = 1, intermediate, advanced, elite

    var id: Int { rawValue }

    init(rating: Double) {
        switch SkillTier(rating: rating).level {
        case ...2: self = .starter
        case 3...4: self = .intermediate
        case 5...6: self = .advanced
        default: self = .elite
        }
    }

    var title: String {
        switch self {
        case .starter: return String(localized: "Lv.1–2 入门")
        case .intermediate: return String(localized: "Lv.3–4 进阶")
        case .advanced: return String(localized: "Lv.5–6 高手")
        case .elite: return String(localized: "Lv.7+ 精英")
        }
    }
}

// MARK: - 规则与计算

enum Rankings {
    /// 本月满这么多场才公开胜率
    static let winRateMinimumGames = 5
    /// 同一对手每月最多计入几场（防好友互刷）
    static let monthlySameOpponentCap = 3
    /// 场馆榜：同一对手每月最多计入、每天最多计入
    static let venueSameOpponentCap = 4
    static let venueDailyCap = 3
    static let venueMinimumGames = 3
    static let venueMinimumOpponents = 2
    /// 周榜：每周最多计入的场数、上榜门槛
    static let weeklyGameCap = 15
    static let weeklyMinimumGames = 3
    static let weeklyMinimumOpponents = 2
    /// 注册满这么多天才上榜（小号刷榜成本更高）
    static let minimumAccountAgeDays = 7
    static let boardSize = 50
    /// 近 60 天和至少 3 位不同对手有赛果争议的人暂不上榜（应对故意拒认），由人工复核后恢复
    static let disputeLimit = 3
    static let disputeWindowDays = 60

    // MARK: 时间段

    static func month(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 30 * 86400)
    }

    /// 全球周榜按 UTC 的周一到周日
    static func week(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86400)
    }

    /// 时间段内某人计入的对局：按时间先后，同一对手超过上限的不再计入
    static func counted(_ records: [MatchRecord], for userId: String, in interval: DateInterval,
                        sameOpponentCap: Int, dailyCap: Int? = nil, calendar: Calendar = .current) -> [MatchRecord] {
        var perOpponent: [String: Int] = [:]
        var perDay: [Date: Int] = [:]
        return records
            .filter { interval.contains($0.date) && $0.team(of: userId) != nil }
            .sorted { $0.date < $1.date }
            .filter { record in
                let key = record.opponentKey(of: userId)
                let day = calendar.startOfDay(for: record.date)
                guard perOpponent[key, default: 0] < sameOpponentCap else { return false }
                if let dailyCap, perDay[day, default: 0] >= dailyCap { return false }
                perOpponent[key, default: 0] += 1
                perDay[day, default: 0] += 1
                return true
            }
    }

    // MARK: 月度胜率

    struct WinRate: Hashable {
        let games: Int
        let wins: Int
        let opponents: Int
        /// 对手平均比我高多少级（负数 = 对手偏弱）
        let averageGap: Double

        var isPublic: Bool { games >= Rankings.winRateMinimumGames }
        var percentage: Int { games == 0 ? 0 : Int((Double(wins) / Double(games) * 100).rounded()) }
    }

    static func winRate(for userId: String, records: [MatchRecord], month: DateInterval) -> WinRate {
        let list = counted(records, for: userId, in: month, sameOpponentCap: monthlySameOpponentCap)
        let gaps = list.map { $0.strengthGap(for: userId) }
        return WinRate(
            games: list.count,
            wins: list.filter { $0.didWin(userId) }.count,
            opponents: Set(list.flatMap { $0.opponents(of: userId) }).count,
            averageGap: gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        )
    }

    // MARK: 榜单

    struct Entry: Identifiable, Hashable {
        let userId: String
        let rank: Int
        /// 场馆榜：计入场数；周榜：积分
        let score: Int
        let games: Int
        let wins: Int

        var id: String { userId }
    }

    /// 场馆月榜：比的是在这家馆打了多少场确认过的球（类似 Strava 的 Local Legends），同分看胜场
    static func venueBoard(venueId: String, records: [MatchRecord], month: DateInterval,
                           eligible: (String) -> Bool) -> [Entry] {
        let atVenue = records.filter { $0.venueId == venueId && month.contains($0.date) }
        let players = Set(atVenue.flatMap { $0.teams.flatMap { $0 } }).filter(eligible)
        let rows: [(String, Int, Int)] = players.compactMap { userId in
            let list = counted(atVenue, for: userId, in: month, sameOpponentCap: venueSameOpponentCap, dailyCap: venueDailyCap)
            let opponents = Set(list.flatMap { $0.opponents(of: userId) }).count
            guard list.count >= venueMinimumGames, opponents >= venueMinimumOpponents else { return nil }
            return (userId, list.count, list.filter { $0.didWin(userId) }.count)
        }
        return ranked(rows.map { ($0.0, $0.1, $0.1, $0.2) })
    }

    /// 一场球的周榜积分：输 10 / 赢 15，按对手强度 ×0.5–1.5，同一对手第二场减半、第三场起不计
    static func points(for record: MatchRecord, userId: String, meetingIndex: Int) -> Double {
        let base: Double = record.didWin(userId) ? 15 : 10
        let strength = min(1.5, max(0.5, 1 + record.strengthGap(for: userId) * 0.5))
        let repeatFactor: Double = meetingIndex == 0 ? 1 : (meetingIndex == 1 ? 0.5 : 0)
        return base * strength * repeatFactor
    }

    static func weeklyScore(for userId: String, records: [MatchRecord], week: DateInterval) -> (points: Int, games: Int, wins: Int, opponents: Int) {
        let list = records
            .filter { week.contains($0.date) && $0.team(of: userId) != nil }
            .sorted { $0.date < $1.date }
            .prefix(weeklyGameCap)
        var meetings: [String: Int] = [:]
        var total = 0.0
        for record in list {
            let key = record.opponentKey(of: userId)
            total += points(for: record, userId: userId, meetingIndex: meetings[key, default: 0])
            meetings[key, default: 0] += 1
        }
        return (Int(total.rounded()), list.count, list.filter { $0.didWin(userId) }.count,
                Set(list.flatMap { $0.opponents(of: userId) }).count)
    }

    /// 全球周榜（可按国家筛选）：积分高的在前
    static func weeklyBoard(records: [MatchRecord], week: DateInterval, countryCode: String? = nil,
                            eligible: (String) -> Bool) -> [Entry] {
        let inWeek = records.filter { week.contains($0.date) && (countryCode == nil || $0.countryCode == countryCode) }
        let players = Set(inWeek.flatMap { $0.teams.flatMap { $0 } }).filter(eligible)
        let rows: [(String, Int, Int, Int)] = players.compactMap { userId in
            let score = weeklyScore(for: userId, records: inWeek, week: week)
            guard score.games >= weeklyMinimumGames, score.opponents >= weeklyMinimumOpponents else { return nil }
            return (userId, score.points, score.games, score.wins)
        }
        return ranked(rows)
    }

    /// 排序并给出名次（同分同名次）
    /// - Parameter rows: (用户, 分数, 场数, 胜场)
    private static func ranked(_ rows: [(String, Int, Int, Int)]) -> [Entry] {
        let sorted = rows.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.3 != $1.3 { return $0.3 > $1.3 }
            return $0.0 < $1.0
        }
        var entries: [Entry] = []
        for (index, row) in sorted.enumerated() {
            let tied = index > 0 && sorted[index - 1].1 == row.1 && sorted[index - 1].3 == row.3
            entries.append(Entry(userId: row.0, rank: tied ? entries[index - 1].rank : index + 1,
                                 score: row.1, games: row.2, wins: row.3))
        }
        return entries
    }
}
