import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - 位置与球馆

enum LocationError: Error, Equatable {
    case permissionDenied

    var message: String { String(localized: "未开启定位，距离按默认城市计算；可直接搜索球馆") }
}

@MainActor
final class LocationManager: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    /// 出行范围内的球馆（来自平台球馆库），按距离排序
    @Published private(set) var nearbyCourts: [BadmintonCourt] = []
    @Published private(set) var favoriteCourtIds: [String] = []
    @Published var preferences: UserPreferences

    private let manager = CLLocationManager()
    private let backend: MockBackend
    private let defaults: UserDefaults
    private var lastRefreshLocation: CLLocation?
    /// 截图/演示模式：不调用 Apple 地图搜索，保证结果可复现
    var allowsMapSearch = true

    /// 位置变化超过 500 米时刷新附近球馆
    static let refreshThresholdMeters: CLLocationDistance = 500

    init(backend: MockBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        let savedRadius = defaults.double(forKey: StorageKey.travelRadius)
        var preferences = UserPreferences.default
        if preferences.isValidTravelRadius(savedRadius) {
            preferences.travelRadiusKm = savedRadius
        }
        self.preferences = preferences
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        favoriteCourtIds = backend.favoriteCourtIds()
        backend.subscribe { [weak self] event in
            switch event {
            case .sessionChanged:
                self?.favoriteCourtIds = self?.backend.favoriteCourtIds() ?? []
                self?.refreshCourts()
            case .venuesChanged:
                self?.refreshCourts()
            default:
                break
            }
        }
        refreshCourts()
    }

    // MARK: Derived

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 用于计算距离的坐标：有定位用定位，否则用模拟世界中心
    var coordinate: Coordinate {
        if let currentLocation { return Coordinate(currentLocation.coordinate) }
        return backend.db.worldCenter
    }

    func court(id: String) -> BadmintonCourt? {
        backend.venue(id: id)
    }

    func courts(ids: [String]) -> [BadmintonCourt] {
        ids.compactMap { backend.venue(id: $0) }
    }

    /// 常去球馆（收藏），按距离排序
    var favoriteCourts: [BadmintonCourt] {
        courts(ids: favoriteCourtIds).sorted { $0.distance(from: coordinate) < $1.distance(from: coordinate) }
    }

    var distanceUnit: DistanceUnit { .current }

    /// "10 公里内" / "6 英里内"
    var radiusText: String { String(localized: "\(DistanceFormatter.radius(km: preferences.travelRadiusKm))内") }

    func isFavorite(_ courtId: String) -> Bool { favoriteCourtIds.contains(courtId) }

    func toggleFavorite(_ courtId: String) {
        backend.toggleFavoriteCourt(courtId)
        favoriteCourtIds = backend.favoriteCourtIds()
    }

    // MARK: Permission & updates

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        switch authorizationStatus {
        case .notDetermined:
            requestAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            refreshCourts()
        }
    }

    /// 更新出行半径（1-50 公里）并持久化
    @discardableResult
    func updateTravelRadius(_ radius: Double) -> Bool {
        guard preferences.isValidTravelRadius(radius) else { return false }
        preferences.travelRadiusKm = radius
        defaults.set(radius, forKey: StorageKey.travelRadius)
        refreshCourts()
        return true
    }

    // MARK: Court discovery

    /// 从平台球馆库刷新出行范围内的球馆
    func refreshCourts() {
        nearbyCourts = backend.venues(near: coordinate, radiusKm: preferences.travelRadiusKm)
    }

    // MARK: Delegate handling (main actor)

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            refreshCourts()
        default:
            break
        }
    }

    fileprivate func handleLocation(_ location: CLLocation) {
        currentLocation = location
        backend.updateCurrentUserLocation(Coordinate(location.coordinate))
        if let last = lastRefreshLocation, location.distance(from: last) < Self.refreshThresholdMeters {
            return
        }
        lastRefreshLocation = location
        refreshCourts()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handleLocation(location)
        }
    }
}
