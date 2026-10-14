import Foundation

// MARK: - 时间段常量

enum TimeSlotConstants {
    /// 最短 1 小时
    static let minimumDuration: TimeInterval = 3600
    /// 最长 8 小时
    static let maximumDuration: TimeInterval = 8 * 3600
    /// 匹配所需最小重叠 30 分钟
    static let minimumOverlapDuration: TimeInterval = 1800
    /// 可选择未来 14 天
    static let maximumDaysAhead = 14
    /// 最多保存 5 个常用时间
    static let maximumRecurringSlots = 5
    /// 一场球的默认时长上限（匹配结果截取）
    static let defaultGameDuration: TimeInterval = 2 * 3600
}

// MARK: - 时间段

struct TimeSlot: Codable, Hashable {
    /// 所在日期（当天 0 点）
    let date: Date
    let startTime: Date
    let endTime: Date

    init(date: Date, startTime: Date, endTime: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.startTime = startTime
        self.endTime = endTime
    }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    var isValidDuration: Bool {
        duration >= TimeSlotConstants.minimumDuration && duration <= TimeSlotConstants.maximumDuration
    }

    var formattedDuration: String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(hours) 小时" }
        if hours == 0 { return "\(minutes) 分钟" }
        return "\(hours) 小时 \(minutes) 分"
    }

    var formattedTimeRange: String {
        "\(DateText.time(startTime))–\(DateText.time(endTime))"
    }

    /// 例："今天" / "明天" / "10月15日 周三"
    var formattedDate: String { DateText.relativeDay(date) }

    var formattedFull: String { "\(formattedDate) \(formattedTimeRange)" }

    /// 计算与另一时间段的重叠；重叠不足 30 分钟返回 nil
    func overlaps(with other: TimeSlot) -> TimeSlot? {
        let start = max(startTime, other.startTime)
        let end = min(endTime, other.endTime)
        guard end > start, end.timeIntervalSince(start) >= TimeSlotConstants.minimumOverlapDuration else {
            return nil
        }
        return TimeSlot(date: start, startTime: start, endTime: end)
    }

    func hasOverlap(with other: TimeSlot) -> Bool {
        overlaps(with: other) != nil
    }

    func contains(_ moment: Date) -> Bool {
        moment >= startTime && moment < endTime
    }

    /// 截取为一场球的时长（默认最多 2 小时），并对齐到整半小时
    func trimmedForGame(maxDuration: TimeInterval = TimeSlotConstants.defaultGameDuration) -> TimeSlot {
        let alignedStart = startTime.roundedUp(toMinutes: 30)
        let start = alignedStart < endTime ? alignedStart : startTime
        let end = min(endTime, start.addingTimeInterval(maxDuration))
        return TimeSlot(date: start, startTime: start, endTime: end)
    }

    /// 向前/向后扩展（用于“放宽时间”建议）
    func expanded(byHours hours: Double) -> TimeSlot {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: startTime)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? endTime
        let newStart = max(dayStart.addingTimeInterval(6 * 3600), startTime.addingTimeInterval(-hours * 3600))
        let newEnd = min(dayEnd, endTime.addingTimeInterval(hours * 3600))
        var slot = TimeSlot(date: date, startTime: newStart, endTime: newEnd)
        if slot.duration > TimeSlotConstants.maximumDuration {
            slot = TimeSlot(date: date, startTime: newStart, endTime: newStart.addingTimeInterval(TimeSlotConstants.maximumDuration))
        }
        return slot
    }

    func validate(now: Date = Date()) -> TimeSlotValidationResult {
        guard endTime > startTime else { return .invalid(reason: "结束时间需要晚于开始时间") }
        guard duration >= TimeSlotConstants.minimumDuration else { return .invalid(reason: "至少需要 1 小时") }
        guard duration <= TimeSlotConstants.maximumDuration else { return .invalid(reason: "最长 8 小时") }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        guard day >= today else { return .invalid(reason: "不能选择过去的日期") }
        if let maxDate = calendar.date(byAdding: .day, value: TimeSlotConstants.maximumDaysAhead, to: today), day > maxDate {
            return .invalid(reason: "只能选择未来 14 天内")
        }
        guard endTime > now else { return .invalid(reason: "这个时间段已经过去了") }
        return .valid
    }

    /// 指定日期的时间段
    static func on(_ date: Date, startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0) -> TimeSlot? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) else { return nil }
        let end: Date?
        if endHour >= 24 {
            end = calendar.date(byAdding: .day, value: 1, to: day)
        } else {
            end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day)
        }
        guard let end else { return nil }
        return TimeSlot(date: day, startTime: start, endTime: end)
    }

    static func today(startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0) -> TimeSlot? {
        on(Date(), startHour: startHour, startMinute: startMinute, endHour: endHour, endMinute: endMinute)
    }

    /// 默认推荐：今晚 19-21 点；若已过 20 点则为明晚
    static func suggestedDefault(now: Date = Date()) -> TimeSlot {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        if hour < 18, let slot = on(now, startHour: 19, endHour: 21) { return slot }
        if hour < 20 {
            let start = now.roundedUp(toMinutes: 30).addingTimeInterval(30 * 60)
            let end = min(start.addingTimeInterval(2 * 3600), calendar.startOfDay(for: now).addingTimeInterval(23 * 3600 + 1800))
            if end.timeIntervalSince(start) >= TimeSlotConstants.minimumDuration {
                return TimeSlot(date: now, startTime: start, endTime: end)
            }
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return on(tomorrow, startHour: 19, endHour: 21) ?? TimeSlot(date: tomorrow, startTime: tomorrow, endTime: tomorrow.addingTimeInterval(7200))
    }
}

enum TimeSlotValidationResult: Equatable {
    case valid
    case invalid(reason: String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

// MARK: - 常用时间（周期性）

struct RecurringTimeSlot: Identifiable, Codable, Hashable {
    let id: String
    /// 1 = 周日 … 7 = 周六
    var dayOfWeek: Int
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        dayOfWeek: Int,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.dayOfWeek = min(max(dayOfWeek, 1), 7)
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.isActive = isActive
    }

    static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var dayOfWeekName: String {
        (1...7).contains(dayOfWeek) ? Self.weekdayNames[dayOfWeek - 1] : "未知"
    }

    var formattedTimeRange: String {
        String(format: "%02d:%02d–%02d:%02d", startHour, startMinute, endHour, endMinute)
    }

    var displayText: String { "\(dayOfWeekName) \(formattedTimeRange)" }

    var durationMinutes: Int {
        (endHour * 60 + endMinute) - (startHour * 60 + startMinute)
    }

    var isValidDuration: Bool {
        let seconds = TimeInterval(durationMinutes * 60)
        return seconds >= TimeSlotConstants.minimumDuration && seconds <= TimeSlotConstants.maximumDuration
    }

    /// 从 from 开始（含当天）找到下一次出现的具体时间段
    func nextOccurrence(from now: Date = Date()) -> TimeSlot? {
        let calendar = Calendar.current
        for offset in 0..<TimeSlotConstants.maximumDaysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            guard calendar.component(.weekday, from: day) == dayOfWeek else { continue }
            guard let slot = TimeSlot.on(day, startHour: startHour, startMinute: startMinute, endHour: endHour, endMinute: endMinute) else { continue }
            if slot.endTime > now { return slot }
        }
        return nil
    }
}

extension Array where Element == RecurringTimeSlot {
    var canAddMore: Bool { count < TimeSlotConstants.maximumRecurringSlots }
    var remainingSlots: Int { Swift.max(0, TimeSlotConstants.maximumRecurringSlots - count) }
    var activeSlots: [RecurringTimeSlot] { filter { $0.isActive } }
}

// MARK: - 日期文本

enum DateText {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "今天 · \(weekday(date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 · \(weekday(date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 · \(weekday(date))"
        }
        return dayFormatter.string(from: date)
    }

    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }

    /// 截止时间：“今天 17:00” / “明天 09:00” / “周五 09:00”
    static func deadline(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "今天 \(time(date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(time(date))"
        }
        return "\(weekday(date)) \(time(date))"
    }

    static func weekday(_ date: Date) -> String {
        RecurringTimeSlot.weekdayNames[Calendar.current.component(.weekday, from: date) - 1]
    }

    /// 消息列表等使用的简短时间：今天显示时刻，否则显示日期
    static func compact(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天"
        }
        return shortDay(date)
    }

    /// 过去时间的相对描述："刚刚" / "3 小时前" / "5 天前" / "2 个月前"
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<3600: return "刚刚"
        case ..<86400: return "\(seconds / 3600) 小时前"
        case ..<(30 * 86400): return "\(seconds / 86400) 天前"
        case ..<(365 * 86400): return "\(seconds / (30 * 86400)) 个月前"
        default: return "\(seconds / (365 * 86400)) 年前"
        }
    }

    /// 倒计时描述，例如 "还有 2 小时 15 分"
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "已开始" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "还有 \(days) 天" + (hours > 0 ? " \(hours) 小时" : "") }
        if hours > 0 { return "还有 \(hours) 小时" + (minutes > 0 ? " \(minutes) 分" : "") }
        return "还有 \(max(1, minutes)) 分钟"
    }

    /// 剩余时间（用于问卷截止等）
    static func remaining(until date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "已截止" }
        let hours = seconds / 3600
        if hours >= 1 { return "剩 \(hours) 小时" }
        return "剩 \(max(1, seconds / 60)) 分钟"
    }
}

extension Date {
    /// 向上取整到指定分钟粒度
    func roundedUp(toMinutes step: Int) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: self)
        let second = calendar.component(.second, from: self)
        let remainder = minute % step
        if remainder == 0 && second == 0 { return self }
        let add = (step - remainder) * 60 - second
        return addingTimeInterval(TimeInterval(add))
    }
}
