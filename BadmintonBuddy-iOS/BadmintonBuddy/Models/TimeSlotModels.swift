//
//  TimeSlotModels.swift
//  BadmintonBuddy
//
//  时间段模型，用于基于时间的玩家匹配
//  - Requirements: 4.2, 4.3
//

import Foundation

// MARK: - 时间段验证常量

/// 时间段验证常量
/// - Requirements: 4.2
enum TimeSlotConstants {
    /// 最小时长：1小时（3600秒）
    static let minimumDuration: TimeInterval = 3600
    
    /// 最大时长：8小时（28800秒）
    static let maximumDuration: TimeInterval = 28800
    
    /// 最小重叠时长：30分钟（1800秒）
    /// - Requirements: 4.3
    static let minimumOverlapDuration: TimeInterval = 1800
    
    /// 可选择的最大天数：14天
    /// - Requirements: 4.1
    static let maximumDaysAhead: Int = 14
    
    /// 最大可保存的周期性时间段数量
    /// - Requirements: 4.8
    static let maximumRecurringSlots: Int = 5
}

// MARK: - 时间段模型

/// 时间段模型，表示用户可用的游戏时间
/// - Requirements: 4.2, 4.3
struct TimeSlot: Codable, Equatable, Hashable {
    /// 日期
    let date: Date
    
    /// 开始时间
    let startTime: Date
    
    /// 结束时间
    let endTime: Date
    
    // MARK: - 计算属性
    
    /// 时间段时长（秒）
    /// - Returns: 结束时间与开始时间的差值
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    /// 时长是否有效（1-8小时）
    /// - Requirements: 4.2
    var isValidDuration: Bool {
        duration >= TimeSlotConstants.minimumDuration &&
        duration <= TimeSlotConstants.maximumDuration
    }
    
    /// 格式化的时长显示（小时和分钟）
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if minutes == 0 {
            return "\(hours)小时"
        } else if hours == 0 {
            return "\(minutes)分钟"
        } else {
            return "\(hours)小时\(minutes)分钟"
        }
    }
    
    /// 格式化的时间范围显示
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    /// 格式化的日期显示
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
    
    // MARK: - 重叠计算
    
    /// 计算与另一个时间段的重叠部分
    /// - Parameter other: 另一个时间段
    /// - Returns: 重叠的时间段，如果重叠时长少于30分钟则返回nil
    /// - Requirements: 4.3
    func overlaps(with other: TimeSlot) -> TimeSlot? {
        // 检查是否在同一天
        guard Calendar.current.isDate(date, inSameDayAs: other.date) else {
            return nil
        }
        
        // 计算重叠的开始和结束时间
        let overlapStart = max(startTime, other.startTime)
        let overlapEnd = min(endTime, other.endTime)
        
        // 检查是否有有效重叠（结束时间必须大于开始时间）
        guard overlapEnd > overlapStart else {
            return nil
        }
        
        // 计算重叠时长
        let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
        
        // 检查重叠时长是否满足最小要求（30分钟）
        guard overlapDuration >= TimeSlotConstants.minimumOverlapDuration else {
            return nil
        }
        
        // 返回重叠的时间段
        return TimeSlot(date: date, startTime: overlapStart, endTime: overlapEnd)
    }
    
    /// 检查是否与另一个时间段有任何重叠
    /// - Parameter other: 另一个时间段
    /// - Returns: 是否有重叠
    func hasOverlap(with other: TimeSlot) -> Bool {
        overlaps(with: other) != nil
    }
    
    // MARK: - 验证方法
    
    /// 验证时间段是否有效
    /// - Returns: 验证结果，包含错误信息（如果有）
    func validate() -> TimeSlotValidationResult {
        // 检查结束时间是否在开始时间之后
        guard endTime > startTime else {
            return .invalid(reason: "结束时间必须在开始时间之后")
        }
        
        // 检查时长是否满足最小要求
        guard duration >= TimeSlotConstants.minimumDuration else {
            return .invalid(reason: "时间段至少需要1小时")
        }
        
        // 检查时长是否超过最大限制
        guard duration <= TimeSlotConstants.maximumDuration else {
            return .invalid(reason: "时间段不能超过8小时")
        }
        
        // 检查日期是否在有效范围内（今天到14天后）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let slotDate = calendar.startOfDay(for: date)
        
        guard slotDate >= today else {
            return .invalid(reason: "不能选择过去的日期")
        }
        
        if let maxDate = calendar.date(byAdding: .day, value: TimeSlotConstants.maximumDaysAhead, to: today) {
            guard slotDate <= maxDate else {
                return .invalid(reason: "只能选择未来14天内的日期")
            }
        }
        
        return .valid
    }
    
    // MARK: - 便捷初始化器
    
    /// 创建今天的时间段
    /// - Parameters:
    ///   - startHour: 开始小时 (0-23)
    ///   - startMinute: 开始分钟 (0-59)
    ///   - endHour: 结束小时 (0-23)
    ///   - endMinute: 结束分钟 (0-59)
    /// - Returns: 时间段，如果参数无效则返回nil
    static func today(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) -> TimeSlot? {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        guard let startTime = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: today),
              let endTime = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: today) else {
            return nil
        }
        
        return TimeSlot(date: today, startTime: startTime, endTime: endTime)
    }
    
    /// 创建指定日期的时间段
    /// - Parameters:
    ///   - date: 日期
    ///   - startHour: 开始小时 (0-23)
    ///   - startMinute: 开始分钟 (0-59)
    ///   - endHour: 结束小时 (0-23)
    ///   - endMinute: 结束分钟 (0-59)
    /// - Returns: 时间段，如果参数无效则返回nil
    static func on(date: Date, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) -> TimeSlot? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        guard let startTime = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart),
              let endTime = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayStart) else {
            return nil
        }
        
        return TimeSlot(date: dayStart, startTime: startTime, endTime: endTime)
    }
}

// MARK: - 时间段验证结果

/// 时间段验证结果
enum TimeSlotValidationResult: Equatable {
    case valid
    case invalid(reason: String)
    
    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
    
    var errorMessage: String? {
        if case .invalid(let reason) = self {
            return reason
        }
        return nil
    }
}

// MARK: - 周期性时间段模型

/// 周期性时间段模型，用于保存用户的常用游戏时间偏好
/// - Requirements: 4.8
struct RecurringTimeSlot: Identifiable, Codable, Equatable, Hashable {
    /// 唯一标识符
    let id: String
    
    /// 星期几 (1 = 周日, 2 = 周一, ..., 7 = 周六)
    /// - Note: 遵循 Calendar.component(.weekday) 的约定
    let dayOfWeek: Int
    
    /// 开始时间（仅小时和分钟）
    let startTime: DateComponents
    
    /// 结束时间（仅小时和分钟）
    let endTime: DateComponents
    
    /// 是否启用
    var isActive: Bool
    
    // MARK: - 计算属性
    
    /// 星期几的中文名称
    var dayOfWeekName: String {
        switch dayOfWeek {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return "未知"
        }
    }
    
    /// 格式化的时间范围显示
    var formattedTimeRange: String {
        let startHour = startTime.hour ?? 0
        let startMinute = startTime.minute ?? 0
        let endHour = endTime.hour ?? 0
        let endMinute = endTime.minute ?? 0
        
        return String(format: "%02d:%02d - %02d:%02d", startHour, startMinute, endHour, endMinute)
    }
    
    /// 完整的显示文本
    var displayText: String {
        "\(dayOfWeekName) \(formattedTimeRange)"
    }
    
    /// 计算时长（分钟）
    var durationMinutes: Int {
        let startMinutes = (startTime.hour ?? 0) * 60 + (startTime.minute ?? 0)
        let endMinutes = (endTime.hour ?? 0) * 60 + (endTime.minute ?? 0)
        return endMinutes - startMinutes
    }
    
    /// 时长是否有效（1-8小时）
    var isValidDuration: Bool {
        let durationSeconds = TimeInterval(durationMinutes * 60)
        return durationSeconds >= TimeSlotConstants.minimumDuration &&
               durationSeconds <= TimeSlotConstants.maximumDuration
    }
    
    // MARK: - 初始化器
    
    /// 创建周期性时间段
    /// - Parameters:
    ///   - id: 唯一标识符（默认自动生成UUID）
    ///   - dayOfWeek: 星期几 (1-7)
    ///   - startHour: 开始小时 (0-23)
    ///   - startMinute: 开始分钟 (0-59)
    ///   - endHour: 结束小时 (0-23)
    ///   - endMinute: 结束分钟 (0-59)
    ///   - isActive: 是否启用（默认true）
    init(
        id: String = UUID().uuidString,
        dayOfWeek: Int,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        isActive: Bool = true
    ) {
        self.id = id
        self.dayOfWeek = min(max(dayOfWeek, 1), 7)
        self.startTime = DateComponents(hour: startHour, minute: startMinute)
        self.endTime = DateComponents(hour: endHour, minute: endMinute)
        self.isActive = isActive
    }
    
    /// 完整初始化器
    init(
        id: String,
        dayOfWeek: Int,
        startTime: DateComponents,
        endTime: DateComponents,
        isActive: Bool
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
    }
    
    // MARK: - 转换方法
    
    /// 将周期性时间段转换为指定日期的具体时间段
    /// - Parameter referenceDate: 参考日期（用于确定具体的日期）
    /// - Returns: 具体的时间段，如果转换失败则返回nil
    func toTimeSlot(for referenceDate: Date = Date()) -> TimeSlot? {
        let calendar = Calendar.current
        
        // 找到参考日期所在周的对应星期几
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        components.weekday = dayOfWeek
        
        guard let targetDate = calendar.date(from: components) else {
            return nil
        }
        
        let dayStart = calendar.startOfDay(for: targetDate)
        
        guard let startDate = calendar.date(
            bySettingHour: startTime.hour ?? 0,
            minute: startTime.minute ?? 0,
            second: 0,
            of: dayStart
        ),
        let endDate = calendar.date(
            bySettingHour: endTime.hour ?? 0,
            minute: endTime.minute ?? 0,
            second: 0,
            of: dayStart
        ) else {
            return nil
        }
        
        return TimeSlot(date: dayStart, startTime: startDate, endTime: endDate)
    }
    
    /// 获取下一个匹配此周期性时间段的具体时间段
    /// - Parameter from: 起始日期（默认为当前时间）
    /// - Returns: 下一个匹配的时间段
    func nextOccurrence(from: Date = Date()) -> TimeSlot? {
        let calendar = Calendar.current
        var currentDate = from
        
        // 最多搜索14天
        for _ in 0..<TimeSlotConstants.maximumDaysAhead {
            let weekday = calendar.component(.weekday, from: currentDate)
            
            if weekday == dayOfWeek {
                if let slot = toTimeSlot(for: currentDate) {
                    // 如果是今天，检查时间是否已过
                    if calendar.isDateInToday(currentDate) {
                        if slot.endTime > from {
                            return slot
                        }
                    } else {
                        return slot
                    }
                }
            }
            
            // 移动到下一天
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) {
                currentDate = nextDay
            } else {
                break
            }
        }
        
        return nil
    }
}

// MARK: - 周期性时间段管理器扩展

/// 周期性时间段集合的验证扩展
extension Array where Element == RecurringTimeSlot {
    /// 检查是否可以添加新的周期性时间段
    /// - Requirements: 4.8
    var canAddMore: Bool {
        count < TimeSlotConstants.maximumRecurringSlots
    }
    
    /// 剩余可添加的数量
    var remainingSlots: Int {
        max(0, TimeSlotConstants.maximumRecurringSlots - count)
    }
    
    /// 获取所有启用的时间段
    var activeSlots: [RecurringTimeSlot] {
        filter { $0.isActive }
    }
}
