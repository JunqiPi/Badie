import Foundation
import CoreLocation

// MARK: - 坐标模型
/// 地理坐标（WGS-84），用于距离计算与地理围栏
struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    static let earthRadiusKm = 6371.0088
    static let kilometersPerMile = 1.609344

    /// 默认城市中心（首发市场：洛杉矶圣盖博谷），在无定位权限时使用
    static let fallbackCenter = Coordinate(latitude: 34.0686, longitude: -118.0276)
    /// 北京（国内演示与测试用）
    static let beijing = Coordinate(latitude: 39.9219, longitude: 116.4433)

    /// Haversine 距离（公里）
    func distanceKm(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return Self.earthRadiusKm * c
    }

    /// Haversine 距离（英里）
    func distance(to other: Coordinate) -> Double {
        distanceKm(to: other) / Self.kilometersPerMile
    }

    /// 在当前坐标基础上按公里偏移（东为正 x，北为正 y），用于生成附近的模拟数据
    func offsetBy(eastKm: Double, northKm: Double) -> Coordinate {
        let deltaLat = northKm / 110.574
        let deltaLon = eastKm / (111.320 * cos(latitude * .pi / 180))
        return Coordinate(latitude: latitude + deltaLat, longitude: longitude + deltaLon)
    }

    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

// MARK: - 距离单位：跟随设备地区（美国、英国用英里，其他用公里）

enum DistanceUnit: String, Codable {
    case kilometers, miles

    static var current: DistanceUnit {
        switch Locale.current.measurementSystem {
        case .us, .uk: return .miles
        default: return .kilometers
        }
    }

    var title: String { self == .miles ? String(localized: "英里") : String(localized: "公里") }

    func value(fromKm km: Double) -> Double { self == .miles ? km / Coordinate.kilometersPerMile : km }
    func km(from value: Double) -> Double { self == .miles ? value * Coordinate.kilometersPerMile : value }
}

enum DistanceFormatter {
    /// 公里制：1 公里以内显示米；英里制：0.1 英里以内显示英尺，其余一位小数
    static func string(km: Double, unit: DistanceUnit = .current) -> String {
        switch unit {
        case .kilometers:
            if km < 1 {
                let meters = max(10, Int((km * 1000 / 10).rounded()) * 10)
                return String(localized: "\(meters) 米")
            }
            let value = String(format: "%.1f", km)
            return String(localized: "\(value) 公里")
        case .miles:
            let miles = km / Coordinate.kilometersPerMile
            if miles < 0.1 {
                let feet = max(50, Int((miles * 5280 / 50).rounded()) * 50)
                return String(localized: "\(feet) 英尺")
            }
            let value = String(format: "%.1f", miles)
            return String(localized: "\(value) 英里")
        }
    }

    /// 别人离我多远：只给大概范围（"5 英里内"），防止多点三角定位出对方住址
    static func approximate(km: Double, unit: DistanceUnit = .current) -> String {
        let bands: [Double] = unit == .miles ? [3, 5, 10, 25] : [5, 10, 20, 40]
        let value = unit.value(fromKm: km)
        let unitTitle = unit.title
        if let band = bands.first(where: { value <= $0 }) {
            let bandValue = Int(band)
            return String(localized: "\(bandValue) \(unitTitle)内")
        }
        let maxBand = Int(bands.last ?? 25)
        return String(localized: "\(maxBand) \(unitTitle)外")
    }

    /// 出行范围等整数距离："10 公里" / "6 英里"
    static func radius(km: Double, unit: DistanceUnit = .current) -> String {
        "\(Int(unit.value(fromKm: km).rounded())) \(unit.title)"
    }
}
