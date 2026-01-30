//
//  CourtModels.swift
//  BadmintonBuddy
//
//  球馆相关数据模型，用于基于球馆的匹配系统
//  - Requirements: 2.1, 2.2, 2.4
//

import Foundation

// MARK: - 球馆设施枚举

/// 球馆设施类型
/// - Requirements: 2.1
enum CourtAmenity: String, Codable, CaseIterable, Hashable {
    case parking = "停车场"
    case shower = "淋浴"
    case locker = "储物柜"
    case rental = "器材租赁"
    case cafe = "餐饮"
    case airConditioning = "空调"
    
    /// 设施图标
    var icon: String {
        switch self {
        case .parking: return "car.fill"
        case .shower: return "shower.fill"
        case .locker: return "lock.fill"
        case .rental: return "sportscourt.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .airConditioning: return "air.conditioner.horizontal.fill"
        }
    }
}

// MARK: - 营业时间模型

/// 球馆营业时间
/// - Requirements: 2.1
struct OperatingHours: Codable, Equatable, Hashable {
    /// 开门时间（小时和分钟）
    let openTime: DateComponents
    
    /// 关门时间（小时和分钟）
    let closeTime: DateComponents
    
    /// 营业日（1=周日, 2=周一, ..., 7=周六）
    /// - Note: 遵循 Calendar.component(.weekday) 的约定
    let daysOpen: [Int]
    
    // MARK: - 计算属性
    
    /// 格式化的营业时间显示
    var formattedTimeRange: String {
        let openHour = openTime.hour ?? 0
        let openMinute = openTime.minute ?? 0
        let closeHour = closeTime.hour ?? 0
        let closeMinute = closeTime.minute ?? 0
        
        return String(format: "%02d:%02d - %02d:%02d", openHour, openMinute, closeHour, closeMinute)
    }
    
    /// 营业日的中文显示
    var formattedDaysOpen: String {
        let dayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let sortedDays = daysOpen.sorted()
        
        // 检查是否每天营业
        if sortedDays.count == 7 {
            return "每天"
        }
        
        // 检查是否工作日营业
        if sortedDays == [2, 3, 4, 5, 6] {
            return "周一至周五"
        }
        
        // 检查是否周末营业
        if sortedDays == [1, 7] {
            return "周末"
        }
        
        // 其他情况，列出具体日期
        return sortedDays.compactMap { day in
            guard day >= 1 && day <= 7 else { return nil }
            return dayNames[day - 1]
        }.joined(separator: "、")
    }
    
    // MARK: - 方法
    
    /// 检查指定时间是否在营业时间内
    /// - Parameter date: 要检查的时间
    /// - Returns: 是否在营业时间内
    func isOpen(at date: Date) -> Bool {
        let calendar = Calendar.current
        
        // 检查是否在营业日
        let weekday = calendar.component(.weekday, from: date)
        guard daysOpen.contains(weekday) else {
            return false
        }
        
        // 获取当前时间的小时和分钟
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentTotalMinutes = currentHour * 60 + currentMinute
        
        // 计算营业时间的分钟数
        let openTotalMinutes = (openTime.hour ?? 0) * 60 + (openTime.minute ?? 0)
        let closeTotalMinutes = (closeTime.hour ?? 0) * 60 + (closeTime.minute ?? 0)
        
        // 检查是否在营业时间范围内
        return currentTotalMinutes >= openTotalMinutes && currentTotalMinutes < closeTotalMinutes
    }
    
    // MARK: - 便捷初始化器
    
    /// 创建营业时间
    /// - Parameters:
    ///   - openHour: 开门小时 (0-23)
    ///   - openMinute: 开门分钟 (0-59)
    ///   - closeHour: 关门小时 (0-23)
    ///   - closeMinute: 关门分钟 (0-59)
    ///   - daysOpen: 营业日数组 (1-7)
    init(
        openHour: Int,
        openMinute: Int,
        closeHour: Int,
        closeMinute: Int,
        daysOpen: [Int]
    ) {
        self.openTime = DateComponents(hour: openHour, minute: openMinute)
        self.closeTime = DateComponents(hour: closeHour, minute: closeMinute)
        self.daysOpen = daysOpen
    }
    
    /// 完整初始化器
    init(openTime: DateComponents, closeTime: DateComponents, daysOpen: [Int]) {
        self.openTime = openTime
        self.closeTime = closeTime
        self.daysOpen = daysOpen
    }
    
    // MARK: - 预设营业时间
    
    /// 标准营业时间（每天 08:00-22:00）
    static let standard = OperatingHours(
        openHour: 8,
        openMinute: 0,
        closeHour: 22,
        closeMinute: 0,
        daysOpen: [1, 2, 3, 4, 5, 6, 7]
    )
    
    /// 工作日营业时间（周一至周五 09:00-21:00）
    static let weekdaysOnly = OperatingHours(
        openHour: 9,
        openMinute: 0,
        closeHour: 21,
        closeMinute: 0,
        daysOpen: [2, 3, 4, 5, 6]
    )
}

// MARK: - 羽毛球馆模型

/// 羽毛球馆/场地模型
/// - Requirements: 2.1, 2.2, 2.4
struct BadmintonCourt: Identifiable, Codable, Equatable, Hashable {
    /// 唯一标识符
    let id: String
    
    /// 球馆名称
    let name: String
    
    /// 球馆位置坐标
    let location: Coordinate
    
    /// 球馆地址
    let address: String
    
    /// 球馆设施列表
    let amenities: [CourtAmenity]
    
    /// 营业时间
    let operatingHours: OperatingHours
    
    /// 球场数量
    let courtCount: Int
    
    // MARK: - 计算属性
    
    /// 设施数量
    var amenityCount: Int {
        amenities.count
    }
    
    /// 是否有停车场
    var hasParking: Bool {
        amenities.contains(.parking)
    }
    
    /// 是否有淋浴设施
    var hasShower: Bool {
        amenities.contains(.shower)
    }
    
    /// 格式化的球场数量显示
    var formattedCourtCount: String {
        "\(courtCount)片场地"
    }
    
    // MARK: - 距离计算
    
    /// 计算从用户位置到球馆的距离（公里）
    /// - Parameter userLocation: 用户当前位置坐标
    /// - Returns: 距离（公里）
    /// - Requirements: 2.4
    func distance(from userLocation: Coordinate) -> Double {
        // 使用 Coordinate 的 distance(to:) 方法计算距离（英里）
        let distanceInMiles = location.distance(to: userLocation)
        // 转换为公里（1英里 ≈ 1.60934公里）
        return distanceInMiles * 1.60934
    }
    
    /// 格式化的距离显示
    /// - Parameter userLocation: 用户当前位置坐标
    /// - Returns: 格式化的距离字符串
    func formattedDistance(from userLocation: Coordinate) -> String {
        let dist = distance(from: userLocation)
        if dist < 1 {
            return String(format: "%.0f 米", dist * 1000)
        } else {
            return String(format: "%.1f 公里", dist)
        }
    }
    
    // MARK: - 初始化器
    
    /// 创建球馆
    /// - Parameters:
    ///   - id: 唯一标识符（默认自动生成UUID）
    ///   - name: 球馆名称
    ///   - location: 球馆位置坐标
    ///   - address: 球馆地址
    ///   - amenities: 球馆设施列表
    ///   - operatingHours: 营业时间
    ///   - courtCount: 球场数量
    init(
        id: String = UUID().uuidString,
        name: String,
        location: Coordinate,
        address: String,
        amenities: [CourtAmenity] = [],
        operatingHours: OperatingHours = .standard,
        courtCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.address = address
        self.amenities = amenities
        self.operatingHours = operatingHours
        self.courtCount = max(1, courtCount)
    }
}

// MARK: - Mock 数据

extension BadmintonCourt {
    /// 模拟球馆数据（北京地区）
    /// - Requirements: 3.1
    static let mockCourts: [BadmintonCourt] = [
        BadmintonCourt(
            id: "court-001",
            name: "朝阳区体育中心羽毛球馆",
            location: Coordinate(latitude: 39.9219, longitude: 116.4433),
            address: "北京市朝阳区工体北路4号",
            amenities: [.parking, .shower, .locker, .cafe, .airConditioning],
            operatingHours: OperatingHours(
                openHour: 7,
                openMinute: 0,
                closeHour: 22,
                closeMinute: 0,
                daysOpen: [1, 2, 3, 4, 5, 6, 7]
            ),
            courtCount: 12
        ),
        BadmintonCourt(
            id: "court-002",
            name: "海淀区羽毛球训练基地",
            location: Coordinate(latitude: 39.9847, longitude: 116.3046),
            address: "北京市海淀区中关村南大街27号",
            amenities: [.parking, .shower, .locker, .rental, .airConditioning],
            operatingHours: OperatingHours(
                openHour: 8,
                openMinute: 0,
                closeHour: 21,
                closeMinute: 30,
                daysOpen: [1, 2, 3, 4, 5, 6, 7]
            ),
            courtCount: 8
        ),
        BadmintonCourt(
            id: "court-003",
            name: "望京羽毛球俱乐部",
            location: Coordinate(latitude: 40.0028, longitude: 116.4716),
            address: "北京市朝阳区望京西路50号",
            amenities: [.shower, .locker, .rental, .cafe],
            operatingHours: OperatingHours(
                openHour: 9,
                openMinute: 0,
                closeHour: 22,
                closeMinute: 0,
                daysOpen: [1, 2, 3, 4, 5, 6, 7]
            ),
            courtCount: 6
        ),
        BadmintonCourt(
            id: "court-004",
            name: "国家体育总局训练馆",
            location: Coordinate(latitude: 39.9908, longitude: 116.3892),
            address: "北京市东城区体育馆路2号",
            amenities: [.parking, .shower, .locker, .rental, .cafe, .airConditioning],
            operatingHours: OperatingHours(
                openHour: 6,
                openMinute: 30,
                closeHour: 21,
                closeMinute: 0,
                daysOpen: [2, 3, 4, 5, 6]  // 仅工作日
            ),
            courtCount: 16
        ),
        BadmintonCourt(
            id: "court-005",
            name: "通州运河羽毛球馆",
            location: Coordinate(latitude: 39.9087, longitude: 116.6569),
            address: "北京市通州区运河西大街88号",
            amenities: [.parking, .shower, .airConditioning],
            operatingHours: .standard,
            courtCount: 10
        )
    ]
    
    /// 单个模拟球馆（用于预览）
    static let mock = mockCourts[0]
}


// MARK: - 用户偏好设置模型

/// 用户偏好设置，包含出行半径等配置
/// - Requirements: 1.1, 1.3
struct UserPreferences: Codable, Equatable {
    /// 用户愿意出行的最大距离（公里）
    /// - 默认值: 10.0 公里
    /// - 有效范围: 1.0 - 50.0 公里
    var travelRadiusKm: Double
    
    // MARK: - 常量
    
    /// 默认出行半径（公里）
    /// - Requirements: 1.1
    static let defaultTravelRadius: Double = 10.0
    
    /// 最小出行半径（公里）
    /// - Requirements: 1.3
    static let minimumTravelRadius: Double = 1.0
    
    /// 最大出行半径（公里）
    /// - Requirements: 1.3
    static let maximumTravelRadius: Double = 50.0
    
    // MARK: - 预设实例
    
    /// 默认用户偏好设置
    static let `default` = UserPreferences(travelRadiusKm: defaultTravelRadius)
    
    // MARK: - 验证方法
    
    /// 验证出行半径是否在有效范围内
    /// - Parameter radius: 要验证的出行半径（公里）
    /// - Returns: 如果半径在 [1.0, 50.0] 范围内返回 true，否则返回 false
    /// - Requirements: 1.3
    func isValidTravelRadius(_ radius: Double) -> Bool {
        radius >= Self.minimumTravelRadius && radius <= Self.maximumTravelRadius
    }
    
    // MARK: - 初始化器
    
    /// 创建用户偏好设置
    /// - Parameter travelRadiusKm: 出行半径（公里），默认为 10.0
    init(travelRadiusKm: Double = UserPreferences.defaultTravelRadius) {
        self.travelRadiusKm = travelRadiusKm
    }
}
