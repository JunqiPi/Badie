import Foundation

// MARK: - 对战模式

enum GameMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case singles = "单打"
    case doubles = "双打"

    var id: String { rawValue }

    var title: String { rawValue }

    var versusText: String {
        switch self {
        case .singles: return "1 vs 1"
        case .doubles: return "2 vs 2"
        }
    }

    var icon: String {
        switch self {
        case .singles: return "person.fill"
        case .doubles: return "person.2.fill"
        }
    }

    var requiredPlayers: Int {
        switch self {
        case .singles: return 2
        case .doubles: return 4
        }
    }
}

// MARK: - 费用 AA

/// 费用明细：场地费 + 用球费，平台不收服务费。币种跟随球馆所在国家。
struct CostSplit: Codable, Hashable {
    enum Basis: String, Codable {
        /// 按场地小时收费，参与者平摊
        case courtHour
        /// 球馆按人次收费（美国俱乐部常见的 drop-in）
        case dropIn
        /// 球馆价格未知
        case unknown
    }

    var basis: Basis
    /// courtHour：每片场地每小时；dropIn：每人次
    var rate: Int
    var hours: Double
    var shuttleFee: Int
    var players: Int
    var currencyCode: String

    var courtFee: Int? {
        switch basis {
        case .courtHour: return Int((Double(rate) * hours).rounded())
        case .dropIn: return rate * players
        case .unknown: return nil
        }
    }

    var total: Int? { courtFee.map { $0 + shuttleFee } }

    /// 每人应付（向上取整）；价格未知时为 nil
    var perPerson: Int? {
        guard let total else { return nil }
        guard players > 0 else { return total }
        return Int((Double(total) / Double(players)).rounded(.up))
    }

    func money(_ amount: Int) -> String { Money.format(amount, currency: currencyCode) }

    /// "$17/人" 或 "费用待定"
    var perPersonText: String { perPerson.map { "\(money($0))/人" } ?? "费用待定" }

    var breakdownText: String {
        let hoursText = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        let shuttle = shuttleFee > 0 ? " + 用球 \(money(shuttleFee))" : ""
        switch basis {
        case .courtHour:
            return "场地 \(money(rate))/时 × \(hoursText) 小时\(shuttle) = \(money(total ?? 0))，\(players) 人 AA"
        case .dropIn:
            return "球馆按人次收费 \(money(rate))/人\(shuttleFee > 0 ? "，用球 \(money(shuttleFee)) 平摊" : "")"
        case .unknown:
            return "球馆价格未知，到场后按实际费用 AA"
        }
    }

    static func estimate(court: BadmintonCourt, slot: TimeSlot, mode: GameMode) -> CostSplit {
        let basis: Basis
        let rate: Int
        switch court.pricing {
        case .perCourtHour(let price): basis = .courtHour; rate = price
        case .dropIn(let price): basis = .dropIn; rate = price
        case .unknown: basis = .unknown; rate = 0
        }
        return CostSplit(basis: basis, rate: rate, hours: slot.duration / 3600,
                         shuttleFee: court.country.shuttleFee(for: mode),
                         players: mode.requiredPlayers, currencyCode: court.currencyCode)
    }
}

// MARK: - 球局

enum GameStatus: String, Codable, Hashable {
    case confirmed
    case completed
    case cancelled
}

enum GameOrigin: Codable, Hashable {
    case quickMatch
    case room(code: String)
}

struct GameResult: Codable, Hashable {
    /// 当前用户视角是否获胜（nil = 未记录）
    var didWin: Bool?
    var score: String
}

/// 已确认的一场球
struct Game: Identifiable, Codable, Hashable {
    let id: String
    var mode: GameMode
    var court: BadmintonCourt
    var slot: TimeSlot
    var playerIds: [String]
    /// 分组：单打 [[A],[B]]，双打 [[A,B],[C,D]]
    var teams: [[String]]
    var hostId: String
    var origin: GameOrigin
    var status: GameStatus
    var createdAt: Date
    /// 到场签到时间
    var checkIns: [String: Date]
    /// 已付 AA 的球友
    var paidPlayerIds: [String]
    var cost: CostSplit
    var result: GameResult?
    var cancelledBy: String?
    /// 是否为临时取消（开赛前 2 小时内）
    var cancelledLate: Bool
    var reminderEnabled: Bool

    /// 开赛前多少时间内取消算临时取消
    static let freeCancellationWindow: TimeInterval = 2 * 3600
    /// 开赛前 30 分钟可签到
    static let checkInWindow: TimeInterval = 30 * 60

    func isUpcoming(now: Date = Date()) -> Bool {
        status == .confirmed && slot.endTime > now
    }

    func isInProgress(now: Date = Date()) -> Bool {
        status == .confirmed && slot.contains(now)
    }

    /// 可签到：开赛前 30 分钟到结束
    func canCheckIn(now: Date = Date()) -> Bool {
        status == .confirmed && now >= slot.startTime.addingTimeInterval(-Self.checkInWindow) && now < slot.endTime
    }

    /// 可标记完成：开赛后
    func canComplete(now: Date = Date()) -> Bool {
        status == .confirmed && now >= slot.startTime
    }

    /// 现在取消是否属于临时取消
    func isLateCancellation(now: Date = Date()) -> Bool {
        slot.startTime.timeIntervalSince(now) < Self.freeCancellationWindow
    }

    func hasCheckedIn(_ userId: String) -> Bool { checkIns[userId] != nil }

    func hasPaid(_ userId: String) -> Bool { paidPlayerIds.contains(userId) }

    func otherPlayerIds(excluding userId: String) -> [String] {
        playerIds.filter { $0 != userId }
    }

    var statusText: String {
        switch status {
        case .confirmed: return "已确认"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }

    var shareText: String {
        "🏸 \(mode.title)球局 · \(slot.formattedFull)\n📍 \(court.name)\n\(court.address)\n💰 AA \(cost.perPersonText) —— 来自 Badie"
    }
}
