import Foundation

// MARK: - 邀请局的大概时间
/// 附近的人里右滑约人：时间可以只说个大概（“周六下午”“这周末”“下周工作日晚上”），
/// 对方说好以后再在群聊里定具体几点。和服务器一致：一场固定 2 小时，时间按半小时对齐，按球馆当地时间算

/// 一天里的时段：上午 08–12、下午 14–18、晚上 18–22
enum Daypart: String, Codable, CaseIterable, Identifiable, Hashable {
    case morning, afternoon, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return String(localized: "上午")
        case .afternoon: return String(localized: "下午")
        case .evening: return String(localized: "晚上")
        }
    }

    /// 开始、结束（从 0 点算的分钟）
    var minutes: (start: Int, end: Int) {
        switch self {
        case .morning: return (8 * 60, 12 * 60)
        case .afternoon: return (14 * 60, 18 * 60)
        case .evening: return (18 * 60, 22 * 60)
        }
    }

    /// 一段时间（同一天，分钟）整个落在哪个时段里
    static func containing(start: Int, end: Int) -> Daypart? {
        allCases.first { start >= $0.minutes.start && end <= $0.minutes.end }
    }

    /// 和这段时间重叠最多的时段（“周六下午”这类标签用）；一点都不重叠是 nil
    static func best(start: Int, end: Int) -> Daypart? {
        var result: Daypart?
        var longest = 0
        for part in allCases {
            let overlap = min(end, part.minutes.end) - max(start, part.minutes.start)
            if overlap > longest {
                longest = overlap
                result = part
            }
        }
        return result
    }
}

/// 一段可以打球的时间：start–end 之间打 durationMinutes（2 小时）
struct PlayWindow: Codable, Hashable {
    var start: Date
    var end: Date
    /// 整场都要在这个时段里（跨天的窗口每天都一样）；nil = 什么时段都行
    var daypart: Daypart?
    var durationMinutes: Int

    init(start: Date, end: Date, daypart: Daypart? = nil, durationMinutes: Int = 120) {
        self.start = start
        self.end = end
        self.daypart = daypart
        self.durationMinutes = durationMinutes
    }

    var duration: TimeInterval { TimeInterval(durationMinutes * 60) }

    /// 窗口正好一场球那么长：就是定好的时间
    var isExact: Bool { abs(end.timeIntervalSince(start) - duration) < 1 }

    /// 最晚什么时候要定下来：邀请到这时没人回就失效，球局到这时没定时间就自动取消
    var deadline: Date { end.addingTimeInterval(-duration) }

    var slot: TimeSlot { TimeSlot(date: start, startTime: start, endTime: end) }

    var isSingleDay: Bool { Calendar.current.isDate(start, inSameDayAs: end.addingTimeInterval(-1)) }

    /// 显示用的时段：没指定时，同一天里整个落在某个时段的也算
    var displayDaypart: Daypart? {
        if let daypart { return daypart }
        guard isSingleDay else { return nil }
        let calendar = Calendar.current
        // 结束在第二天 0 点算 24:00
        let endMinute = calendar.isDate(start, inSameDayAs: end)
            ? Self.clockMinutes(end, calendar: calendar) : 24 * 60 + Self.clockMinutes(end, calendar: calendar)
        return Daypart.containing(start: Self.clockMinutes(start, calendar: calendar), end: endMinute)
    }

    /// 当天的钟点（从 0 点算的分钟）：按钟面算，夏令时切换那天也对
    static func clockMinutes(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 某天的某个钟点（分钟，24:00 = 第二天 0 点）：按钟面设置，夏令时切换那天也对
    static func time(on date: Date, minutes: Int, calendar: Calendar) -> Date? {
        guard minutes >= 24 * 60 else {
            return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)
        }
        guard let next = calendar.date(byAdding: .day, value: minutes / (24 * 60), to: calendar.startOfDay(for: date)) else { return nil }
        let rest = minutes % (24 * 60)
        return calendar.date(bySettingHour: rest / 60, minute: rest % 60, second: 0, of: next)
    }

    /// 最早能开始的时间：现在过 30 分钟后的下一个整半点（和服务器一致）
    static func earliestStart(now: Date) -> Date {
        now.addingTimeInterval(30 * 60).roundedUp(toMinutes: 30)
    }

    /// 能开始的时间：每半小时一个，整场都在窗口里、在时段里，不早于 earliestStart。
    /// 没指定时段的，只给 06:00 后开始、当天打完的
    func possibleStarts(now: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let earliest = Self.earliestStart(now: now)
        var result: [Date] = []
        var cursor = start.roundedUp(toMinutes: 30)
        var steps = 0
        while cursor.addingTimeInterval(duration) <= end, steps < 400 {
            if cursor >= earliest, fits(cursor, calendar: calendar) { result.append(cursor) }
            cursor = cursor.addingTimeInterval(30 * 60)
            steps += 1
        }
        return result
    }

    /// 现在还能不能约（至少有一个开始时间）
    func isPossible(now: Date = Date()) -> Bool { !possibleStarts(now: now).isEmpty }

    private func fits(_ begin: Date, calendar: Calendar) -> Bool {
        let startMinute = Self.clockMinutes(begin, calendar: calendar)
        let endMinute = startMinute + durationMinutes
        if let daypart { return startMinute >= daypart.minutes.start && endMinute <= daypart.minutes.end }
        return startMinute >= 6 * 60 && endMinute <= 24 * 60
    }

    // MARK: 常用的几种窗口

    /// 某一天里从 startMinutes 到 endMinutes（分钟）
    static func on(_ date: Date, startMinutes: Int, endMinutes: Int, daypart: Daypart? = nil) -> PlayWindow? {
        let calendar = Calendar.current
        guard endMinutes > startMinutes,
              let start = time(on: date, minutes: startMinutes, calendar: calendar),
              let end = time(on: date, minutes: endMinutes, calendar: calendar), end > start else { return nil }
        return PlayWindow(start: start, end: end, daypart: daypart)
    }

    /// 某一天的某个时段；nil = 都行（08–22）
    static func on(_ date: Date, daypart: Daypart?) -> PlayWindow? {
        let minutes: (start: Int, end: Int) = daypart?.minutes ?? (start: 8 * 60, end: 22 * 60)
        return on(date, startMinutes: minutes.start, endMinutes: minutes.end, daypart: daypart)
    }

    /// 从 firstDay 那天的时段开始到 lastDay 那天的时段结束（nil = 08–22）
    private static func span(from firstDay: Date, to lastDay: Date, daypart: Daypart?) -> PlayWindow? {
        let minutes: (start: Int, end: Int) = daypart?.minutes ?? (start: 8 * 60, end: 22 * 60)
        guard let first = on(firstDay, startMinutes: minutes.start, endMinutes: minutes.end),
              let last = on(lastDay, startMinutes: minutes.start, endMinutes: minutes.end) else { return nil }
        return PlayWindow(start: first.start, end: last.end, daypart: daypart)
    }

    /// 这周末：周六到周日（今天是周日也算这周末）；这周末来不及了就是下周末
    static func weekend(now: Date = Date(), daypart: Daypart?) -> PlayWindow? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let toSaturday = weekday == 1 ? -1 : 7 - weekday
        for extra in [0, 7] {
            guard let saturday = calendar.date(byAdding: .day, value: toSaturday + extra, to: today),
                  let sunday = calendar.date(byAdding: .day, value: 1, to: saturday),
                  let window = span(from: saturday, to: sunday, daypart: daypart) else { continue }
            if window.isPossible(now: now) { return window }
        }
        return nil
    }

    /// 下周工作日：下周一到周五（今天是周日，下周一就是明天）
    static func nextWeekdays(now: Date = Date(), daypart: Daypart?) -> PlayWindow? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let toMonday = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
        guard let monday = calendar.date(byAdding: .day, value: toMonday, to: today),
              let friday = calendar.date(byAdding: .day, value: 4, to: monday) else { return nil }
        return span(from: monday, to: friday, daypart: daypart)
    }

    /// 一段常用时间最近的一次：按半小时取整，不够 2 小时的往后延到 2 小时；
    /// 今天的已经开始了就从最早能开始的时间算，不够打一场就是下周的
    static func nextOccurrence(of slot: RecurringTimeSlot, now: Date = Date()) -> PlayWindow? {
        let calendar = Calendar.current
        let startMinutes = (slot.startMinutes + 29) / 30 * 30
        let endMinutes = min(24 * 60, max(slot.endMinutes / 30 * 30, startMinutes + 120))
        guard endMinutes - startMinutes >= 120 else { return nil }
        let earliest = earliestStart(now: now)
        let today = calendar.startOfDay(for: now)
        for offset in 0..<15 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  calendar.component(.weekday, from: day) == slot.dayOfWeek,
                  var window = on(day, startMinutes: startMinutes, endMinutes: endMinutes,
                                  daypart: Daypart.containing(start: startMinutes, end: endMinutes)) else { continue }
            if window.start < earliest { window.start = earliest }
            if window.end.timeIntervalSince(window.start) >= window.duration { return window }
        }
        return nil
    }

    /// 两人空闲时间的交集：接下来 7 天里第一段至少 2 小时的（演示模式用；正式后端由服务器算）
    static func firstOverlap(_ mine: [RecurringTimeSlot], _ theirs: [RecurringTimeSlot], now: Date = Date()) -> PlayWindow? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let earliest = earliestStart(now: now)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            var best: PlayWindow?
            for a in mine where a.dayOfWeek == weekday {
                for b in theirs where b.dayOfWeek == weekday {
                    let startMinutes = (max(a.startMinutes, b.startMinutes) + 29) / 30 * 30
                    let endMinutes = min(a.endMinutes, b.endMinutes) / 30 * 30
                    guard endMinutes - startMinutes >= 120,
                          var window = on(day, startMinutes: startMinutes, endMinutes: endMinutes,
                                          daypart: Daypart.containing(start: startMinutes, end: endMinutes)) else { continue }
                    if window.start < earliest { window.start = earliest }
                    guard window.end.timeIntervalSince(window.start) >= window.duration else { continue }
                    if best == nil || window.start < best!.start { best = window }
                }
            }
            if let best { return best }
        }
        return nil
    }
}

// MARK: - 邀请

/// 附近的人里发的邀请：谁约谁、轮到谁回、换过几次时间
struct LobbyInvite: Codable, Hashable {
    var fromId: String
    var toId: String
    /// 轮到谁回；说好、不了、过期以后没人要回（服务器给 null）
    var awaitingId: String?
    /// 换过几次时间
    var rounds: Int
    /// 过了这个时间没人回就失效
    var answerBy: Date

    func other(than userId: String?) -> String { fromId == userId ? toId : fromId }
}

// MARK: - 常用时间：服务器的格式

/// profiles.usual_times 里的一项：{"weekday": 1-7（1 = 周日）, "start": "HH:MM", "end": "HH:MM"}
struct ServerUsualTime: Codable, Hashable {
    var weekday: Int
    var start: String
    var end: String
}

extension RecurringTimeSlot {
    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }

    init?(server: ServerUsualTime) {
        guard (1...7).contains(server.weekday), let start = Self.minutes(server.start), let end = Self.minutes(server.end),
              start < end else { return nil }
        self.init(dayOfWeek: server.weekday, startHour: start / 60, startMinute: start % 60, endHour: end / 60, endMinute: end % 60)
    }

    var serverValue: ServerUsualTime {
        ServerUsualTime(weekday: dayOfWeek, start: Self.clock(startMinutes), end: Self.clock(endMinutes))
    }

    /// 发给服务器的 JSON
    var serverJSON: [String: Any] {
        ["weekday": dayOfWeek, "start": Self.clock(startMinutes), "end": Self.clock(endMinutes)]
    }

    /// "HH:MM" → 分钟（最多 24:00）
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0..<60).contains(minute), hour * 60 + minute <= 24 * 60 else { return nil }
        return hour * 60 + minute
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - 显示

/// 窗口的说法：大字“周六 下午”“这周末 · 下午”“下周工作日 · 晚上”，小字“14:00–18:00 之间”
enum WindowText {
    /// 今天、明天、6 天内写星期，再远写日期和星期
    static func dayName(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "今天") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "明天")
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0 && days < 7 { return DateText.weekday(date) }
        return "\(DateText.shortDay(date)) \(DateText.weekday(date))"
    }

    /// 哪几天：“周六”“这周末”“下周工作日”“周六–周一”
    static func days(_ window: PlayWindow, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: window.start)
        let last = calendar.startOfDay(for: window.end.addingTimeInterval(-1))
        if first == last { return dayName(window.start, now: now) }
        let today = calendar.startOfDay(for: now)
        let span = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        let ahead = calendar.dateComponents([.day], from: today, to: first).day ?? 0
        let firstWeekday = calendar.component(.weekday, from: first)
        if firstWeekday == 7 && span == 1 {
            return ahead < 7 ? String(localized: "这周末") : String(localized: "下周末")
        }
        if firstWeekday == 2 && span == 4 {
            return ahead > 0 ? String(localized: "下周工作日") : String(localized: "这周工作日")
        }
        return "\(dayName(first, now: now))–\(dayName(last, now: now))"
    }

    /// 大字：“周六 下午”“这周末 · 下午”“这周末”
    static func headline(_ window: PlayWindow, now: Date = Date()) -> String {
        let dayText = days(window, now: now)
        guard let part = window.displayDaypart else { return dayText }
        return window.isSingleDay ? "\(dayText) \(part.title)" : "\(dayText) · \(part.title)"
    }

    /// 带日期的标题（收到的邀请）：“周六 11/15 · 下午”；跨天的同 headline
    static func headlineWithDate(_ window: PlayWindow, now: Date = Date()) -> String {
        guard window.isSingleDay else { return headline(window, now: now) }
        let day = "\(DateText.weekday(window.start)) \(DateText.shortDay(window.start))"
        guard let part = window.displayDaypart else { return day }
        return "\(day) · \(part.title)"
    }

    /// 时间范围：“14:00–18:00”；跨天：“11/15–11/16 14:00–18:00”，没有时段的写全：“11/15 08:00 – 11/16 22:00”
    static func range(_ window: PlayWindow) -> String {
        if window.isSingleDay {
            return "\(DateText.time(window.start))–\(DateText.time(window.end))"
        }
        let calendar = Calendar.current
        let lastDay = window.end.addingTimeInterval(-1)
        if let part = window.daypart {
            let firstDay = calendar.startOfDay(for: window.start)
            let from = calendar.date(byAdding: .minute, value: part.minutes.start, to: firstDay) ?? window.start
            let to = calendar.date(byAdding: .minute, value: part.minutes.end, to: firstDay) ?? window.end
            return "\(DateText.shortDay(window.start))–\(DateText.shortDay(lastDay)) \(DateText.time(from))–\(DateText.time(to))"
        }
        return "\(DateText.shortDay(window.start)) \(DateText.time(window.start)) – \(DateText.shortDay(lastDay)) \(DateText.time(window.end))"
    }

    /// “14:00–18:00 之间”
    static func between(_ window: PlayWindow) -> String {
        String(localized: "\(range(window)) 之间")
    }

    /// 选时间时的小字：“14:00–18:00 之间打 2 小时”；正好 2 小时的就是“14:00–16:00”
    static func caption(_ window: PlayWindow) -> String {
        window.isExact ? range(window) : String(localized: "\(range(window)) 之间打 2 小时")
    }
}

/// 空闲时间的说法：卡片上的小标签“周六下午”，资料页上归纳成一行“工作日晚上 · 周末下午”
enum UsualTimeText {
    /// 周一排第一
    private static func order(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    private static func daypart(of slot: RecurringTimeSlot) -> Daypart? {
        Daypart.best(start: slot.startMinutes, end: slot.endMinutes)
    }

    /// 小标签：“周六下午”；不在任何时段里的写开始时间：“周二 07:00”
    static func chip(_ slot: RecurringTimeSlot) -> String {
        let day = slot.dayOfWeekName
        if let part = daypart(of: slot) {
            return String(localized: "\(day)\(part.title)", comment: "星期 + 时段，如“周六下午”")
        }
        return "\(day) \(RecurringTimeSlot.clock(slot.startMinutes))"
    }

    /// 按最近的一次排：最先能约的在前
    static func sortedByNext(_ slots: [RecurringTimeSlot], now: Date = Date()) -> [RecurringTimeSlot] {
        slots.sorted { a, b in
            let x = PlayWindow.nextOccurrence(of: a, now: now)?.start ?? .distantFuture
            let y = PlayWindow.nextOccurrence(of: b, now: now)?.start ?? .distantFuture
            return x < y
        }
    }

    /// 一行：“工作日晚上 · 周末下午”，最多两段，多了加“等”。没有空闲时间是 nil
    static func summary(_ slots: [RecurringTimeSlot]) -> String? {
        guard !slots.isEmpty else { return nil }
        var keys: [String] = []
        var days: [String: Set<Int>] = [:]
        var parts: [String: Daypart] = [:]
        let sorted = slots.sorted { (order($0.dayOfWeek), $0.startMinutes) < (order($1.dayOfWeek), $1.startMinutes) }
        for slot in sorted {
            let part = daypart(of: slot)
            let key = part?.rawValue ?? RecurringTimeSlot.clock(slot.startMinutes)
            if days[key] == nil { keys.append(key) }
            days[key, default: []].insert(slot.dayOfWeek)
            parts[key] = part
        }
        let phrases = keys.map { key -> String in
            let dayText = daysText(days[key] ?? [])
            if let part = parts[key] {
                return String(localized: "\(dayText)\(part.title)", comment: "星期 + 时段，如“周六下午”")
            }
            return "\(dayText) \(key)"
        }
        let shown = phrases.prefix(2).joined(separator: " · ")
        return phrases.count > 2 ? String(localized: "\(shown) 等") : shown
    }

    /// 周一到周五全有：“工作日”；周六周日：“周末”；七天：“每天”；其他列出来
    static func daysText(_ days: Set<Int>) -> String {
        if days == Set(1...7) { return String(localized: "每天") }
        if days == Set(2...6) { return String(localized: "工作日") }
        if days == [1, 7] { return String(localized: "周末") }
        return days.sorted { order($0) < order($1) }
            .map { RecurringTimeSlot.weekdayNames[$0 - 1] }
            .joined(separator: String(localized: "、", comment: "名单分隔符"))
    }
}
