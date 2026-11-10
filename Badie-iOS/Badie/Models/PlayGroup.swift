import Foundation

// MARK: - 球群（固定局）
//
// 绑定球馆的每周固定场次：一键报名、满员候补、有人退出自动递补。
// 对外只显示近 30 天的活跃度，不显示成员总数。见 docs/DESIGN.md §12。

struct PlayGroup: Identifiable, Codable, Hashable {
    enum JoinPolicy: String, Codable, CaseIterable, Identifiable, Hashable {
        /// 水平符合就能直接加入
        case open
        /// 组织者同意后加入
        case approval

        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: return String(localized: "直接加入")
            case .approval: return String(localized: "需要组织者同意")
            }
        }
    }

    let id: String
    var name: String
    var venueId: String
    var ownerId: String
    /// 组织者（含群主），可以审批、取消场次
    var organizerIds: [String]
    var memberIds: [String]
    /// 等待审批的人
    var pendingIds: [String]
    var summary: String
    var levelRange: ClosedRange<Int>
    var schedules: [GroupSchedule]
    var joinPolicy: JoinPolicy
    /// 6 位群号（可以发到微信，别人在“输入房间码 / 群号”里加入）
    var inviteCode: String
    var createdAt: Date
    /// 只限女生 / 男生；nil = 不限
    var audience: Gender? = nil
    /// 教练带课：每场 1–40 人，水平范围只作提示（旧数据里没有这一项）
    var coached: Bool? = nil

    static let maxSchedules = 7
    static let nameLimit = 2...20

    func isMember(_ userId: String) -> Bool { memberIds.contains(userId) }

    func isOrganizer(_ userId: String) -> Bool { organizerIds.contains(userId) }

    func isPending(_ userId: String) -> Bool { pendingIds.contains(userId) }

    var levelText: String { "Lv.\(levelRange.lowerBound)–\(levelRange.upperBound)" }

    var isCoached: Bool { coached ?? false }

    /// 收费说明：各场一样就只留一条，不一样就写明是哪一场
    var feeLines: [String] {
        let notes: [(GroupSchedule, String)] = schedules.compactMap { schedule in schedule.feeNote.map { (schedule, $0) } }
        if notes.count == schedules.count, Set(notes.map { $0.1 }).count == 1 { return [notes[0].1] }
        return notes.map { "\($0.0.weekdayTitle) \($0.0.timeText): \($0.1)" }
    }

    /// 分享到微信的文字
    func inviteText(venueName: String) -> String {
        let times = schedules.map { "\($0.weekdayTitle) \($0.timeText)" }.formatted(.list(type: .and))
        return String(localized: "来「\(name)」一起打羽毛球。\(venueName) · \(times) · \(levelText)。在 Badie App 输入群号 \(inviteCode) 加入，报名、候补都在 App 里。")
            + "\n" + Room.joinLink(inviteCode)
    }
}

/// 每周固定场次
struct GroupSchedule: Identifiable, Codable, Hashable {
    let id: String
    /// Calendar 的星期：1 = 周日 … 7 = 周六
    var weekday: Int
    /// 从 0 点起的分钟数
    var startMinutes: Int
    var endMinutes: Int
    /// 名额（满了进候补）
    var capacity: Int
    /// 费用说明，如“每人 $15”
    var feeNote: String?

    static let feeNoteLimit = 120

    /// 名额 4–40；教练带课的群 1–40（教练不报名，人数指学员）
    static func capacityRange(coached: Bool) -> ClosedRange<Int> { coached ? 1...40 : 4...40 }

    /// 1–7 个；每个 1–12 小时、当天结束，名额和收费说明的长度（和服务器的 valid_schedules 一致）
    static func areValid(_ schedules: [GroupSchedule], coached: Bool = false) -> Bool {
        !schedules.isEmpty && schedules.count <= PlayGroup.maxSchedules && schedules.allSatisfy {
            (60...720).contains($0.endMinutes - $0.startMinutes) && $0.endMinutes <= 24 * 60
                && capacityRange(coached: coached).contains($0.capacity) && (1...7).contains($0.weekday)
        } && schedules.allSatisfy { ($0.feeNote?.count ?? 0) <= feeNoteLimit }
    }

    var weekdayTitle: String {
        let day = RecurringTimeSlot.weekdayNames[(weekday - 1 + 7) % 7]
        return String(localized: "每\(day)")
    }

    var timeText: String {
        String(format: "%02d:%02d–%02d:%02d", startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    }

    /// 某天的这一场（这天不是这个星期几时返回 nil）
    func slot(on day: Date, calendar: Calendar = .current) -> TimeSlot? {
        guard calendar.component(.weekday, from: day) == weekday else { return nil }
        return TimeSlot.on(day, startHour: startMinutes / 60, startMinute: startMinutes % 60,
                           endHour: endMinutes / 60, endMinute: endMinutes % 60)
    }
}

/// 某一场固定局（按需生成）
struct GroupSession: Identifiable, Codable, Hashable {
    enum Status: Equatable {
        case signedUp
        case waitlisted(position: Int)
        case none
    }

    /// groupId|scheduleId|yyyyMMdd
    let id: String
    let groupId: String
    let scheduleId: String
    var slot: TimeSlot
    var capacity: Int
    /// 报名顺序
    var signedUp: [String]
    var waitlist: [String]
    var isCancelled = false

    /// 开场前多久内退出算临时取消（与球局规则一致）
    static let lateCancellationWindow: TimeInterval = 2 * 3600
    /// 能看到并报名未来几天的场次
    static let daysAhead = 14

    static func makeId(groupId: String, scheduleId: String, day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(groupId)|\(scheduleId)|\(stamp)"
    }

    var isFull: Bool { signedUp.count >= capacity }

    func status(of userId: String) -> Status {
        if signedUp.contains(userId) { return .signedUp }
        if let index = waitlist.firstIndex(of: userId) { return .waitlisted(position: index + 1) }
        return .none
    }

    func isUpcoming(now: Date = Date()) -> Bool { !isCancelled && slot.endTime > now }
}

/// 球群的真实活跃度（对外展示用，不显示成员总数）
struct GroupActivity: Hashable {
    /// 近 30 天开了几场
    let sessionsLast30Days: Int
    /// 平均每场报名人数
    let averageTurnout: Double

    var text: String {
        let turnout = Int(averageTurnout.rounded())
        return sessionsLast30Days == 0
            ? String(localized: "近 30 天还没开过场")
            : String(localized: "近 30 天 \(sessionsLast30Days) 场 · 平均每场 \(turnout) 人")
    }
}
