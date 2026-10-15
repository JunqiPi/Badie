import Foundation

// MARK: - 球馆设施

enum CourtAmenity: String, Codable, CaseIterable, Hashable {
    case parking = "停车场"
    case shower = "淋浴"
    case locker = "储物柜"
    case rental = "器材租赁"
    case cafe = "餐饮"
    case airConditioning = "空调"

    /// 显示文字（rawValue 已持久化，不能改；显示走这里以便本地化）
    var title: String {
        switch self {
        case .parking: return String(localized: "停车场")
        case .shower: return String(localized: "淋浴")
        case .locker: return String(localized: "储物柜")
        case .rental: return String(localized: "器材租赁")
        case .cafe: return String(localized: "餐饮")
        case .airConditioning: return String(localized: "空调")
        }
    }

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
    /// 开 / 关门时间，只用 hour、minute
    let openTime: DateComponents
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
        let days = daysOpen.sorted()
        if days.count == 7 { return String(localized: "每天") }
        if days == [2, 3, 4, 5, 6] { return String(localized: "周一至周五") }
        if days == [1, 7] { return String(localized: "周末") }
        return days.compactMap { (1...7).contains($0) ? RecurringTimeSlot.weekdayNames[$0 - 1] : nil }.formatted(.list(type: .and))
    }

    /// 时间段是否完全落在营业时间内（跨午夜结束的按 24 点之后计）
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

// MARK: - 结构化地址

/// 分字段存储，按国家习惯（AddressStyle）格式化
struct PostalAddress: Codable, Hashable {
    /// 门牌与街道，如 "10410 Valley Blvd"、"工体北路4号"
    var street: String
    /// 单元/楼层/场馆内位置，如 "Unit B"
    var unit: String?
    /// 城市（大陆地址里是区县）
    var city: String
    /// 州/省（大陆地址里是省市），如 "CA"、"北京市"
    var region: String
    var postalCode: String
    /// ISO 3166-1 alpha-2，如 "US"
    var countryCode: String

    init(street: String, unit: String? = nil, city: String, region: String, postalCode: String = "", countryCode: String) {
        self.street = street.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = (trimmedUnit?.isEmpty ?? true) ? nil : trimmedUnit
        self.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        self.postalCode = postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = countryCode.uppercased()
    }

    var style: AddressStyle { CountryInfo.info(for: countryCode).addressStyle }

    /// 第一行：街道 + 单元（"10410 Valley Blvd, Unit B"）
    var streetLine: String {
        switch style {
        case .smallToLarge: return [street, unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        case .largeToSmall: return street + (unit ?? "")
        }
    }

    /// 第二行：城市 州 邮编（"El Monte, CA 91731"）
    var cityLine: String {
        switch style {
        case .smallToLarge:
            let regionPart = [region, postalCode].filter { !$0.isEmpty }.joined(separator: " ")
            return [city, regionPart].filter { !$0.isEmpty }.joined(separator: ", ")
        case .largeToSmall:
            return region == city ? region : region + city
        }
    }

    /// 列表用的紧凑地址：街道 + 城市 + 州（省略邮编与国家），足够分辨同名球馆
    var compactLine: String {
        switch style {
        case .smallToLarge:
            return [streetLine, city, region].filter { !$0.isEmpty }.joined(separator: ", ")
        case .largeToSmall:
            return (region == city ? "" : city) + streetLine
        }
    }

    var singleLine: String {
        switch style {
        case .smallToLarge:
            return [streetLine, cityLine].filter { !$0.isEmpty }.joined(separator: ", ")
        case .largeToSmall:
            return cityLine + streetLine
        }
    }

    /// 至少要有街道和城市，才能让别人确认位置
    var isComplete: Bool { !street.isEmpty && !city.isEmpty }
}

// MARK: - 球馆来源、可信度、价格

enum VenueSource: String, Codable, Hashable {
    /// 平台收录：经过人工核对
    case curated
    /// 用户从 Apple 地图结果中选择后加入
    case appleMaps
    /// 用户手动添加（放图钉/输入地址/粘贴地图链接）
    case player
    /// 按城市从 OpenStreetMap 导入（未实地核实）
    case openStreetMap
    /// 各地政府开放数据（见 OpenDataVenues）
    case openData
}

enum VenueStatus: String, Codable, Hashable {
    /// 平台核实
    case verified
    /// 至少 3 位不同球友确认过（或在此签到打过球）
    case confirmed
    /// 新加入，等待确认
    case unconfirmed

    var title: String {
        switch self {
        case .verified: return String(localized: "已核实")
        case .confirmed: return String(localized: "球友确认")
        case .unconfirmed: return String(localized: "待确认")
        }
    }

    var icon: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .confirmed: return "person.2.fill"
        case .unconfirmed: return "questionmark.circle.fill"
        }
    }
}

/// 收费方式：国内多为“按场地小时”，美国俱乐部常见“按人次 drop-in”
enum VenuePricing: Codable, Hashable {
    case perCourtHour(Int)
    case dropIn(perPerson: Int)
    case unknown

    func text(currency: String) -> String {
        switch self {
        case .perCourtHour(let price):
            let amount = Money.format(price, currency: currency)
            return String(localized: "\(amount)/场·时")
        case .dropIn(let price):
            let amount = Money.format(price, currency: currency)
            return String(localized: "\(amount)/人次")
        case .unknown: return String(localized: "价格未知")
        }
    }

    var isKnown: Bool { if case .unknown = self { return false } else { return true } }
}

/// 坐标系：国际通用 WGS-84；中国大陆地图数据（高德/Apple 地图在大陆）为 GCJ-02
enum CoordinateDatum: String, Codable, Hashable {
    case wgs84
    case gcj02
}

// MARK: - 球馆

struct BadmintonCourt: Identifiable, Codable, Hashable {
    /// 平台内的唯一 ID：匹配、房间、球局都只比较这个 ID，不比较名字或坐标
    let id: String
    var name: String
    /// 别名与简称（"LABC"、中文俗称），用于搜索
    var aliases: [String]
    var location: Coordinate
    /// 坐标来源的坐标系；导航到高德/百度时据此传参
    var datum: CoordinateDatum
    var postalAddress: PostalAddress
    /// IANA 时区，如 "America/Los_Angeles"；营业时间按球馆当地时间判断
    var timeZoneId: String?
    /// Apple 地图 Place ID（iOS 18+ 可获得，长期有效），用于去重与打开地点卡片
    var applePlaceId: String?
    var amenities: [CourtAmenity]
    /// nil = 营业时间未知
    var operatingHours: OperatingHours?
    /// nil = 场地数未知
    var courtCount: Int?
    var pricing: VenuePricing
    /// 价格说明（如“散客 $15/人次 · 包场 $28/场·时”）
    var pricingNote: String?
    var currencyCode: String
    var phone: String?
    var website: String?
    /// 入口/楼层/停车说明（与地址分开，如“后门进，2 楼”）
    var entranceNote: String?
    var source: VenueSource
    var status: VenueStatus
    var addedBy: String?
    /// 确认过地址的球友（去重后的用户 ID）
    var confirmedBy: [String]
    /// 最近一次有人确认/签到的时间（信息新鲜度）
    var lastConfirmedAt: Date?
    var createdAt: Date
    /// 重复条目合并后指向保留的球馆：旧 ID 的收藏、房间、请求继续有效
    var mergedInto: String?
    /// 需要人工看一眼的原因（如“同一栋楼已有另一家球馆”）；不影响使用
    var reviewFlag: String?
    /// 开放数据要求的署名（详情页显示）
    var attribution: String?

    /// 达到这个人数的确认后，状态从“待确认”变为“球友确认”
    static let confirmationsNeeded = 3

    init(
        id: String = "v-" + UUID().uuidString.prefix(8).lowercased(),
        name: String,
        aliases: [String] = [],
        location: Coordinate,
        datum: CoordinateDatum = .wgs84,
        address: PostalAddress,
        timeZoneId: String? = nil,
        applePlaceId: String? = nil,
        amenities: [CourtAmenity] = [],
        operatingHours: OperatingHours? = nil,
        courtCount: Int? = nil,
        pricing: VenuePricing = .unknown,
        pricingNote: String? = nil,
        currencyCode: String? = nil,
        phone: String? = nil,
        website: String? = nil,
        entranceNote: String? = nil,
        source: VenueSource = .curated,
        status: VenueStatus = .verified,
        addedBy: String? = nil,
        confirmedBy: [String] = [],
        lastConfirmedAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_767_225_600)
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliases = aliases
        self.location = location
        self.datum = datum
        self.postalAddress = address
        self.timeZoneId = timeZoneId
        self.applePlaceId = applePlaceId
        self.amenities = amenities
        self.operatingHours = operatingHours
        self.courtCount = courtCount.map { max(1, $0) }
        self.pricing = pricing
        self.pricingNote = pricingNote
        self.currencyCode = currencyCode ?? CountryInfo.info(for: address.countryCode).currencyCode
        self.phone = phone
        self.website = website
        let note = entranceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entranceNote = (note?.isEmpty ?? true) ? nil : note
        self.source = source
        self.status = status
        self.addedBy = addedBy
        self.confirmedBy = confirmedBy
        self.lastConfirmedAt = lastConfirmedAt
        self.createdAt = createdAt
    }

    /// 单行完整地址
    var address: String { postalAddress.singleLine }
    var countryCode: String { postalAddress.countryCode }
    var country: CountryInfo { CountryInfo.info(for: countryCode) }

    /// 球馆当地日历（营业时间、球局时间都按当地时间计算）
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneId.flatMap(TimeZone.init(identifier:)) ?? .current
        return calendar
    }

    /// 球馆所在时区与设备不同（如出差）时，用于在时间旁标注
    var timeZoneAbbreviation: String? {
        guard let zone = timeZoneId.flatMap(TimeZone.init(identifier:)),
              zone.secondsFromGMT() != TimeZone.current.secondsFromGMT() else { return nil }
        return zone.abbreviation()
    }

    var pricingText: String { pricing.text(currency: currencyCode) }

    /// 该时段是否营业；营业时间未知时视为可用（无法判断）
    func isOpen(for slot: TimeSlot) -> Bool {
        operatingHours?.covers(slot, calendar: calendar) ?? true
    }

    var hoursText: String { operatingHours?.formattedTimeRange ?? String(localized: "营业时间未知") }

    /// 到用户的距离（公里）
    func distance(from coordinate: Coordinate) -> Double {
        location.distanceKm(to: coordinate)
    }

    func formattedDistance(from coordinate: Coordinate) -> String {
        DistanceFormatter.string(km: distance(from: coordinate))
    }

    /// 记录一位球友的确认；够数后升级为“球友确认”
    mutating func addConfirmation(from userId: String, at date: Date = Date()) {
        lastConfirmedAt = max(lastConfirmedAt ?? .distantPast, date)
        guard !confirmedBy.contains(userId) else { return }
        confirmedBy.append(userId)
        if status == .unconfirmed && confirmedBy.count >= Self.confirmationsNeeded {
            status = .confirmed
        }
    }
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
