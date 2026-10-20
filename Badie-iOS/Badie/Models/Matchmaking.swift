import Foundation

// MARK: - 匹配时间规则
//
// 普通局：开赛前 2 小时锁定（与“开赛前 2 小时内取消算临时取消”一致），确认期限随距开赛的时间放宽。
// 临时局：开赛不到 2.5 小时，只匹配附近此刻也在找人的球友，确认期限 5–10 分钟，最晚开赛前 20 分钟确认完。
// 见 docs/DESIGN.md §10。

enum MatchTiming {
    /// 普通局锁定：开赛前 2 小时必须全部确认
    static let lockLead: TimeInterval = 2 * 3600
    /// 开赛时间在这之内的请求按临时局处理
    static let lastMinuteThreshold: TimeInterval = 2.5 * 3600
    /// 发起请求最晚要在开赛前 30 分钟
    static let minimumLead: TimeInterval = 30 * 60
    /// 临时局最晚在开赛前 20 分钟确认完（留出路上时间）
    static let lastMinuteConfirmBefore: TimeInterval = 20 * 60
    /// 临时局只找附近的人（约 5 英里）
    static let lastMinuteRadiusKm: Double = 8

    static func isLastMinute(start: Date, now: Date = Date()) -> Bool {
        start.timeIntervalSince(now) < lastMinuteThreshold
    }

    static func canRequest(start: Date, now: Date = Date()) -> Bool {
        start.timeIntervalSince(now) >= minimumLead
    }

    /// 锁定时间：到点必须全部确认，没约成就结束
    static func lock(start: Date, lastMinute: Bool) -> Date {
        start.addingTimeInterval(-(lastMinute ? lastMinuteConfirmBefore : lockLead))
    }

    /// 少于这个确认时间就不再发出新提议（来不及回复）
    static func minimumResponseWindow(lastMinute: Bool) -> TimeInterval {
        lastMinute ? 3 * 60 : 10 * 60
    }

    /// 夜里（23:00–8:00）到期的确认顺延到早上 9 点，不让人半夜被催（仍不晚于锁定时间）
    static let quietHours = (start: 23, end: 8, resume: 9)

    /// 确认期限：开赛越远给得越长，但不晚于锁定时间
    static func respondBy(start: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let lead = start.timeIntervalSince(now)
        if isLastMinute(start: start, now: now) {
            let window: TimeInterval = lead < 3600 ? 5 * 60 : 10 * 60
            return min(now.addingTimeInterval(window), start.addingTimeInterval(-lastMinuteConfirmBefore))
        }
        let window: TimeInterval
        switch lead {
        case (26 * 3600)...: window = 12 * 3600
        case (6 * 3600)...: window = 2 * 3600
        default: window = 30 * 60
        }
        let lock = start.addingTimeInterval(-lockLead)
        return min(skippingQuietHours(now.addingTimeInterval(window), calendar: calendar), lock)
    }

    /// 落在夜里的时间顺延到早上 9 点
    static func skippingQuietHours(_ date: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= quietHours.start || hour < quietHours.end else { return date }
        let day = hour >= quietHours.start ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date
        return calendar.date(bySettingHour: quietHours.resume, minute: 0, second: 0, of: day) ?? date
    }

    /// 剩余时间文案："还剩 1 小时 52 分" / "还剩 4 分钟"
    static func remainingText(until date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? String(localized: "还剩 \(hours) 小时 \(minutes) 分") : String(localized: "还剩 \(hours) 小时")
        }
        let shownMinutes = max(1, minutes)
        return String(localized: "还剩 \(shownMinutes) 分钟")
    }
}

// MARK: - 约球请求（挂在后台，找到人就通知）

struct MatchTicket: Identifiable, Codable, Hashable {
    enum Status: Codable, Hashable {
        /// 在找
        case searching
        /// 有了提议，等大家确认
        case offered(offerId: String)
        /// 已成局
        case matched(gameId: String)
        /// 错过确认，暂停，等用户说“继续找”
        case paused
        /// 到锁定时间还没约成
        case expired
        case cancelled
    }

    let id: String
    let userId: String
    var mode: GameMode
    var slot: TimeSlot
    /// 可接受的球馆
    var courtIds: [String]
    var skillTolerance: Int
    var radiusKm: Double
    /// 发起时的位置
    var origin: Coordinate
    /// 符合条件的提议直接视为接受
    var autoAccept: Bool
    var isLastMinute: Bool
    var status: Status
    var createdAt: Date
    /// 锁定时间（普通局开赛前 2 小时，临时局开赛前 20 分钟）
    var deadline: Date
    /// 因为别人没确认被退回：下一轮优先
    var hasPriority: Bool
    /// 不再推荐的人（我拒绝过的、没确认的）
    var excludedUserIds: [String]
    /// 项目：男单女单男双女双、混双；nil = 不限
    var event: PlayEvent? = nil

    var isActive: Bool {
        switch status {
        case .searching, .offered: return true
        default: return false
        }
    }

    var offerId: String? {
        if case .offered(let id) = status { return id }
        return nil
    }

    var gameId: String? {
        if case .matched(let id) = status { return id }
        return nil
    }
}

// MARK: - 匹配提议（所有人都确认才成局）

struct MatchOffer: Identifiable, Codable, Hashable {
    enum Response: String, Codable, Hashable {
        case pending, accepted, declined, expired
    }

    enum Status: Codable, Hashable {
        case open
        case confirmed(gameId: String)
        /// 没凑成（有人没确认且补不上）
        case failed
    }

    struct Seat: Codable, Hashable {
        var userId: String
        /// 真实用户的请求（模拟球友为 nil）
        var ticketId: String?
        var response: Response
        /// 这个座位的确认期限（补位进来的人有自己的期限）
        var respondBy: Date
        var respondedAt: Date?

        /// 没来（拒绝或超时），等待补位
        var isVacant: Bool { response == .declined || response == .expired }
    }

    let id: String
    var mode: GameMode
    var slot: TimeSlot
    var commonOverlap: TimeSlot
    var court: BadmintonCourt
    var teams: [[String]]
    var seats: [Seat]
    var cost: CostSplit
    var compatibility: Int
    var createdAt: Date
    /// 锁定时间：到点没全部确认就作废
    var lockAt: Date
    var isLastMinute: Bool
    var status: Status
    /// 已补位次数
    var backfillCount: Int

    static let maximumBackfills = 3

    var playerIds: [String] { seats.map(\.userId) }

    /// 仍在局中的人（不含拒绝/超时的座位）
    var activePlayerIds: [String] { seats.filter { !$0.isVacant }.map(\.userId) }

    var vacantCount: Int { seats.filter(\.isVacant).count }

    func seat(of userId: String) -> Seat? { seats.first { $0.userId == userId } }

    var acceptedCount: Int { seats.filter { $0.response == .accepted }.count }

    var isFullyAccepted: Bool { seats.allSatisfy { $0.response == .accepted } }

    var isOpen: Bool { if case .open = status { return true } else { return false } }

    var gameId: String? {
        if case .confirmed(let id) = status { return id }
        return nil
    }
}
