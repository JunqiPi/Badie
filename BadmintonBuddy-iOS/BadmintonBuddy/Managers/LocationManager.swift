import Foundation
import CoreLocation
import Combine

// MARK: - LocationManager (位置管理器)
/// 管理用户位置和附近球馆的发现
/// Requirements: 1.1, 1.2, 1.3, 1.4, 8.1
class LocationManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前用户位置
    @Published var currentLocation: CLLocation?
    
    /// 位置授权状态
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// 附近的球馆列表（基于用户出行半径）
    /// - Requirements: 8.1
    @Published var nearbyCourts: [BadmintonCourt] = []
    
    /// 用户偏好设置（包含出行半径）
    /// - Requirements: 8.1
    @Published var userPreferences: UserPreferences = .default
    
    /// 位置是否可用
    @Published var isLocationAvailable: Bool = false
    
    /// 上次位置更新时间
    @Published var lastLocationUpdate: Date?
    
    /// 位置错误信息
    @Published var locationError: LocationError?
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    
    /// 上次刷新球馆时的位置
    /// - Requirements: 3.3
    private var lastRefreshLocation: CLLocation?
    
    /// 地理围栏半径（英里）
    static let geofenceRadiusMiles: Double = 50.0
    
    /// 触发球馆刷新的最小位置变化（米）
    /// - Requirements: 3.3
    static let locationChangeThresholdMeters: Double = 500.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
        loadTravelRadiusFromUserDefaults()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100 // 100米更新一次
    }
    
    // MARK: - 出行半径持久化
    
    /// UserDefaults 存储键
    private static let travelRadiusKey = "userTravelRadiusKm"
    
    /// 从 UserDefaults 加载出行半径
    /// - Note: 如果保存的值无效或不存在，则使用默认值
    private func loadTravelRadiusFromUserDefaults() {
        let savedRadius = UserDefaults.standard.double(forKey: Self.travelRadiusKey)
        
        // 检查是否有保存的有效值（double 默认返回 0.0 如果键不存在）
        if savedRadius > 0 && userPreferences.isValidTravelRadius(savedRadius) {
            userPreferences.travelRadiusKm = savedRadius
            #if DEBUG
            print("[LocationManager] 已加载保存的出行半径: \(savedRadius) 公里")
            #endif
        } else {
            #if DEBUG
            print("[LocationManager] 使用默认出行半径: \(UserPreferences.defaultTravelRadius) 公里")
            #endif
        }
    }
    
    /// 保存出行半径到 UserDefaults
    /// - Parameter radius: 要保存的出行半径（公里）
    private func saveTravelRadiusToUserDefaults(_ radius: Double) {
        UserDefaults.standard.set(radius, forKey: Self.travelRadiusKey)
        UserDefaults.standard.synchronize()
        
        #if DEBUG
        print("[LocationManager] 已保存出行半径: \(radius) 公里")
        #endif
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
    
    // MARK: - 球馆过滤方法
    
    /// 根据用户出行半径过滤球馆
    /// - Parameter allCourts: 所有球馆列表
    /// - Returns: 在出行半径内的球馆列表，按距离排序（最近的在前）
    /// - Requirements: 8.2
    func filterCourtsByTravelRadius(allCourts: [BadmintonCourt]) -> [BadmintonCourt] {
        // 如果没有用户位置，返回空数组
        guard let userCoordinate = currentLocation?.coordinate else { return [] }
        
        // 将 CLLocationCoordinate2D 转换为 Coordinate 模型
        let userCoord = Coordinate(
            latitude: userCoordinate.latitude,
            longitude: userCoordinate.longitude
        )
        
        // 过滤出在出行半径内的球馆，并按距离排序（最近的在前）
        return allCourts
            .filter { court in
                // 只保留距离 <= 用户设置的出行半径的球馆
                court.distance(from: userCoord) <= userPreferences.travelRadiusKm
            }
            .sorted { court1, court2 in
                // 按距离升序排序（最近的在前）
                court1.distance(from: userCoord) < court2.distance(from: userCoord)
            }
    }
    
    // MARK: - 出行半径更新
    
    /// 更新用户出行半径
    /// - Parameter radiusKm: 新的出行半径（公里）
    /// - Returns: 更新是否成功（如果半径无效则返回 false）
    /// - Requirements: 1.2, 1.4
    @discardableResult
    func updateTravelRadius(_ radiusKm: Double) -> Bool {
        // 验证半径是否在有效范围内 [1.0, 50.0] 公里
        guard userPreferences.isValidTravelRadius(radiusKm) else {
            #if DEBUG
            print("[LocationManager] 无效的出行半径: \(radiusKm) 公里（有效范围: \(UserPreferences.minimumTravelRadius)-\(UserPreferences.maximumTravelRadius) 公里）")
            #endif
            return false
        }
        
        // 更新偏好设置
        userPreferences.travelRadiusKm = radiusKm
        
        // 持久化到 UserDefaults
        saveTravelRadiusToUserDefaults(radiusKm)
        
        // 刷新附近球馆列表
        refreshNearbyCourts()
        
        return true
    }
    
    /// 刷新附近球馆列表
    /// - Note: 使用模拟数据过滤球馆（实际应用中会从服务器获取）
    /// - Requirements: 8.4
    func refreshNearbyCourts() {
        // 使用模拟数据过滤球馆（实际应用中会从服务器获取）
        nearbyCourts = filterCourtsByTravelRadius(allCourts: BadmintonCourt.mockCourts)
        
        #if DEBUG
        print("[LocationManager] 已刷新附近球馆列表，找到 \(nearbyCourts.count) 个球馆（出行半径: \(userPreferences.travelRadiusKm) 公里）")
        #endif
    }
    
    // MARK: - 位置变化阈值检测
    
    /// 检查是否应该刷新附近球馆列表
    /// - Parameter newLocation: 新的位置
    /// - Returns: 如果位置变化超过阈值（500米）则返回 true
    /// - Requirements: 3.3
    func shouldRefreshCourts(newLocation: CLLocation) -> Bool {
        guard let lastLocation = lastRefreshLocation else {
            // 首次获取位置，应该刷新
            return true
        }
        
        let distance = newLocation.distance(from: lastLocation)
        return distance > Self.locationChangeThresholdMeters
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
        
        // 检查是否需要刷新附近球馆
        // - Requirements: 3.3
        if shouldRefreshCourts(newLocation: location) {
            lastRefreshLocation = location
            refreshNearbyCourts()
        }
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
