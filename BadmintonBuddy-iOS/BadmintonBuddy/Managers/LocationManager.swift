import Foundation
import CoreLocation
import Combine

// MARK: - LocationManager (位置管理器)
/// 管理用户位置和附近玩家的发现
/// Requirements: 1.1, 1.2, 1.3, 1.4
class LocationManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前用户位置
    @Published var currentLocation: CLLocation?
    
    /// 位置授权状态
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// 附近的玩家列表（50英里范围内）
    @Published var nearbyPlayers: [User] = []
    
    /// 位置是否可用
    @Published var isLocationAvailable: Bool = false
    
    /// 上次位置更新时间
    @Published var lastLocationUpdate: Date?
    
    /// 位置错误信息
    @Published var locationError: LocationError?
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    
    /// 地理围栏半径（英里）
    static let geofenceRadiusMiles: Double = 50.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100 // 100米更新一次
    }
    
    // MARK: - Public Methods
    
    /// 请求位置授权
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// 开始更新位置
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
    
    /// 停止更新位置
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    /// 检查位置是否在指定范围内
    /// - Parameters:
    ///   - location: 目标位置
    ///   - radiusMiles: 半径（英里）
    /// - Returns: 是否在范围内
    func isWithinRange(_ location: CLLocation, radiusMiles: Double) -> Bool {
        guard let currentLocation = currentLocation else { return false }
        let distanceMeters = currentLocation.distance(from: location)
        let distanceMiles = distanceMeters / 1609.344
        return distanceMiles <= radiusMiles
    }
    
    /// 过滤附近的玩家（50英里范围内）
    /// - Parameters:
    ///   - allUsers: 所有用户列表
    ///   - radiusMiles: 过滤半径（英里），默认50英里
    /// - Returns: 范围内的用户列表
    func filterNearbyPlayers(allUsers: [User], radiusMiles: Double = geofenceRadiusMiles) -> [User] {
        guard let currentLocation = currentLocation else { return [] }
        
        return allUsers.filter { user in
            guard let userCoordinate = user.location else { return false }
            let userLocation = CLLocation(
                latitude: userCoordinate.latitude,
                longitude: userCoordinate.longitude
            )
            return isWithinRange(userLocation, radiusMiles: radiusMiles)
        }
    }
    
    /// 更新附近玩家列表
    /// - Parameter allUsers: 所有用户列表
    func updateNearbyPlayers(allUsers: [User]) {
        nearbyPlayers = filterNearbyPlayers(allUsers: allUsers)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        lastLocationUpdate = Date()
        isLocationAvailable = true
        locationError = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .permissionDenied
                isLocationAvailable = false
            case .locationUnknown:
                locationError = .locationUnavailable
            default:
                locationError = .unknown(error.localizedDescription)
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
            isLocationAvailable = true
        case .denied, .restricted:
            locationError = .permissionDenied
            isLocationAvailable = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Location Errors

enum LocationError: Error, Equatable {
    case permissionDenied
    case locationUnavailable
    case servicesDisabled
    case unknown(String)
    
    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "需要位置权限才能找到附近的球友"
        case .locationUnavailable:
            return "位置暂时不可用，显示上次位置"
        case .servicesDisabled:
            return "请在设置中开启定位服务"
        case .unknown(let message):
            return message
        }
    }
}
