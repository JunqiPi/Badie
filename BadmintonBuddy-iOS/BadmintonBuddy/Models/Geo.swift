import Foundation
import CoreLocation

// MARK: - 坐标模型
/// 地理坐标（WGS-84），用于距离计算与地理围栏
struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    static let earthRadiusKm = 6371.0088
    static let kilometersPerMile = 1.609344

    /// 默认城市中心（北京·工体），在无定位权限时使用
    static let fallbackCenter = Coordinate(latitude: 39.9219, longitude: 116.4433)

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

enum DistanceFormatter {
    /// 1 公里以内显示米，否则显示一位小数公里
    static func string(km: Double) -> String {
        if km < 1 {
            return "\(max(10, Int((km * 1000 / 10).rounded()) * 10)) 米"
        }
        return String(format: "%.1f 公里", km)
    }
}
