import Foundation

// MARK: - 球馆设施

enum CourtAmenity: String, Codable, CaseIterable, Hashable {
    case parking = "停车场"
    case shower = "淋浴"
    case locker = "储物柜"
    case rental = "器材租赁"
    case cafe = "餐饮"
    case airConditioning = "空调"

    var icon: String {
        switch self {
        case .parking: return "car.fill"
        case .shower: return "shower.fill"
        case .locker: return "lock.fill"
        case .rental: return "bag.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .airConditioning: return "snowflake"
        }
    }
}

// MARK: - 营业时间

struct OperatingHours: Codable, Hashable {
    /// 开门时间（小时与分钟）
    let openTime: DateComponents
    /// 关门时间（小时与分钟）
    let closeTime: DateComponents
    /// 营业日（1=周日 … 7=周六，与 Calendar.weekday 一致）
    let daysOpen: [Int]

    init(openHour: Int, openMinute: Int, closeHour: Int, closeMinute: Int, daysOpen: [Int]) {
        self.openTime = DateComponents(hour: openHour, minute: openMinute)
        self.closeTime = DateComponents(hour: closeHour, minute: closeMinute)
        self.daysOpen = daysOpen
    }

    var openMinutes: Int { (openTime.hour ?? 0) * 60 + (openTime.minute ?? 0) }
    var closeMinutes: Int { (closeTime.hour ?? 0) * 60 + (closeTime.minute ?? 0) }

    var formattedTimeRange: String {
        String(format: "%02d:%02d – %02d:%02d",
               openTime.hour ?? 0, openTime.minute ?? 0,
               closeTime.hour ?? 0, closeTime.minute ?? 0)
    }

    var formattedDaysOpen: String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let days = daysOpen.sorted()
        if days.count == 7 { return "每天" }
        if days == [2, 3, 4, 5, 6] { return "周一至周五" }
        if days == [1, 7] { return "周末" }
        return days.compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }.joined(separator: "、")
    }

    /// 指定时刻是否营业
    func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard daysOpen.contains(weekday) else { return false }
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minutes >= openMinutes && minutes < closeMinutes
    }

    /// 时间段是否完全落在营业时间内
    func covers(_ slot: TimeSlot, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: slot.startTime)
        guard daysOpen.contains(weekday) else { return false }
        let start = calendar.component(.hour, from: slot.startTime) * 60 + calendar.component(.minute, from: slot.startTime)
        let endDate = slot.endTime
        var end = calendar.component(.hour, from: endDate) * 60 + calendar.component(.minute, from: endDate)
        if !calendar.isDate(endDate, inSameDayAs: slot.startTime) { end += 24 * 60 }
        return start >= openMinutes && end <= closeMinutes
    }

    static let standard = OperatingHours(openHour: 8, openMinute: 0, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7))
}

// MARK: - 球馆

enum CourtSource: String, Codable, Hashable {
    /// 平台收录（含价格、设施等完整信息）
    case curated
    /// 来自 Apple 地图搜索，价格与营业时间为估算
    case mapSearch
    /// 无定位/无搜索结果时生成的示例球馆
    case sample
}

struct BadmintonCourt: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let location: Coordinate
    let address: String
    let amenities: [CourtAmenity]
    let operatingHours: OperatingHours
    let courtCount: Int
    /// 每片场地每小时价格（元）
    let pricePerHour: Int
    let phone: String?
    let source: CourtSource

    init(
        id: String = UUID().uuidString,
        name: String,
        location: Coordinate,
        address: String,
        amenities: [CourtAmenity] = [],
        operatingHours: OperatingHours = .standard,
        courtCount: Int = 1,
        pricePerHour: Int = 60,
        phone: String? = nil,
        source: CourtSource = .curated
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.address = address
        self.amenities = amenities
        self.operatingHours = operatingHours
        self.courtCount = max(1, courtCount)
        self.pricePerHour = max(0, pricePerHour)
        self.phone = phone
        self.source = source
    }

    var formattedCourtCount: String { "\(courtCount) 片场地" }

    var isEstimatedInfo: Bool { source != .curated }

    /// 到用户的距离（公里）
    func distance(from coordinate: Coordinate) -> Double {
        location.distanceKm(to: coordinate)
    }

    func formattedDistance(from coordinate: Coordinate) -> String {
        DistanceFormatter.string(km: distance(from: coordinate))
    }
}

// MARK: - 收录球馆（北京示例数据）

extension BadmintonCourt {
    static let curatedBeijing: [BadmintonCourt] = [
        BadmintonCourt(
            id: "court-001",
            name: "朝阳体育中心羽毛球馆",
            location: Coordinate(latitude: 39.9219, longitude: 116.4433),
            address: "北京市朝阳区工体北路4号",
            amenities: [.parking, .shower, .locker, .cafe, .airConditioning],
            operatingHours: OperatingHours(openHour: 7, openMinute: 0, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 12,
            pricePerHour: 80,
            phone: "010-65012345"
        ),
        BadmintonCourt(
            id: "court-002",
            name: "海淀羽毛球训练基地",
            location: Coordinate(latitude: 39.9847, longitude: 116.3046),
            address: "北京市海淀区中关村南大街27号",
            amenities: [.parking, .shower, .locker, .rental, .airConditioning],
            operatingHours: OperatingHours(openHour: 8, openMinute: 0, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 8,
            pricePerHour: 60
        ),
        BadmintonCourt(
            id: "court-003",
            name: "望京羽毛球俱乐部",
            location: Coordinate(latitude: 40.0028, longitude: 116.4716),
            address: "北京市朝阳区望京西路50号",
            amenities: [.shower, .locker, .rental, .cafe],
            operatingHours: OperatingHours(openHour: 9, openMinute: 0, closeHour: 23, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 6,
            pricePerHour: 70
        ),
        BadmintonCourt(
            id: "court-004",
            name: "东城体育馆路羽毛球馆",
            location: Coordinate(latitude: 39.8808, longitude: 116.4192),
            address: "北京市东城区体育馆路2号",
            amenities: [.parking, .shower, .locker, .rental, .cafe, .airConditioning],
            operatingHours: OperatingHours(openHour: 6, openMinute: 30, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 16,
            pricePerHour: 90
        ),
        BadmintonCourt(
            id: "court-005",
            name: "通州运河羽毛球馆",
            location: Coordinate(latitude: 39.9087, longitude: 116.6569),
            address: "北京市通州区运河西大街88号",
            amenities: [.parking, .shower, .airConditioning],
            operatingHours: .standard,
            courtCount: 10,
            pricePerHour: 45
        ),
        BadmintonCourt(
            id: "court-006",
            name: "三里屯社区体育中心",
            location: Coordinate(latitude: 39.9334, longitude: 116.4551),
            address: "北京市朝阳区三里屯路19号",
            amenities: [.locker, .airConditioning],
            operatingHours: OperatingHours(openHour: 9, openMinute: 0, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 4,
            pricePerHour: 50
        )
    ]

    /// 在任意城市生成示例球馆（无定位权限或地图搜索无结果时使用）
    static func samples(around center: Coordinate) -> [BadmintonCourt] {
        let templates: [(String, Double, Double, Int, Int, [CourtAmenity])] = [
            ("飞羽运动中心", 1.2, 0.8, 10, 60, [.parking, .shower, .locker, .airConditioning]),
            ("城市全民健身馆", -2.1, 1.6, 8, 45, [.parking, .locker]),
            ("星火羽毛球馆", 3.4, -1.9, 6, 55, [.shower, .rental, .airConditioning]),
            ("大学城体育馆", -3.8, -2.7, 12, 35, [.parking, .rental]),
            ("滨江羽毛球俱乐部", 5.6, 2.9, 7, 70, [.parking, .shower, .locker, .cafe, .airConditioning]),
            ("社区活动中心羽毛球场", -0.6, -1.1, 3, 30, [.locker])
        ]
        return templates.enumerated().map { index, item in
            BadmintonCourt(
                id: "sample-\(index)",
                name: item.0,
                location: center.offsetBy(eastKm: item.1, northKm: item.2),
                address: "距你约 \(DistanceFormatter.string(km: hypot(item.1, item.2)))（示例地址）",
                amenities: item.5,
                operatingHours: .standard,
                courtCount: item.3,
                pricePerHour: item.4,
                source: .sample
            )
        }
    }

    static let mock = curatedBeijing[0]
}

// MARK: - 用户偏好

struct UserPreferences: Codable, Hashable {
    /// 出行半径（公里）
    var travelRadiusKm: Double

    static let defaultTravelRadius: Double = 10
    static let minimumTravelRadius: Double = 1
    static let maximumTravelRadius: Double = 50

    static let `default` = UserPreferences(travelRadiusKm: defaultTravelRadius)

    func isValidTravelRadius(_ radius: Double) -> Bool {
        radius >= Self.minimumTravelRadius && radius <= Self.maximumTravelRadius
    }
}
