import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - 位置与球馆

enum LocationError: Error, Equatable {
    case permissionDenied
    case locationUnavailable
    case unknown(String)

    var message: String {
        switch self {
        case .permissionDenied: return "未开启定位，显示的是示例城市的球馆"
        case .locationUnavailable: return "定位暂时不可用，显示上次位置"
        case .unknown(let message): return message
        }
    }
}

@MainActor
final class LocationManager: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastLocationUpdate: Date?
    @Published private(set) var locationError: LocationError?
    @Published private(set) var courts: [BadmintonCourt] = []
    @Published private(set) var isSearchingCourts = false
    @Published private(set) var favoriteCourtIds: [String] = []
    @Published var preferences: UserPreferences

    private let manager = CLLocationManager()
    private let backend: MockBackend
    private let defaults: UserDefaults
    private var lastSearchLocation: CLLocation?
    /// 截图/演示模式：不调用地图搜索，保证结果可复现
    var usesOnlyCuratedCourts = false

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
        courts = backend.db.knownCourts
        favoriteCourtIds = backend.favoriteCourtIds()
        backend.subscribe { [weak self] event in
            if case .sessionChanged = event {
                self?.favoriteCourtIds = self?.backend.favoriteCourtIds() ?? []
            }
        }
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

    /// 出行半径内的球馆，按距离排序
    var nearbyCourts: [BadmintonCourt] {
        let center = coordinate
        return courts
            .filter { $0.distance(from: center) <= preferences.travelRadiusKm }
            .sorted { $0.distance(from: center) < $1.distance(from: center) }
    }

    func court(id: String) -> BadmintonCourt? {
        courts.first { $0.id == id }
    }

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
            Task { await refreshCourts() }
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// 更新出行半径（1-50 公里）并持久化
    @discardableResult
    func updateTravelRadius(_ radius: Double) -> Bool {
        guard preferences.isValidTravelRadius(radius) else { return false }
        preferences.travelRadiusKm = radius
        defaults.set(radius, forKey: StorageKey.travelRadius)
        return true
    }

    // MARK: Court discovery

    /// 刷新附近球馆：北京附近使用收录球馆；其他城市用 Apple 地图搜索，搜索不到时使用示例球馆
    func refreshCourts() async {
        let center = coordinate
        let nearBeijing = center.distanceKm(to: .fallbackCenter) < 60
        var result: [BadmintonCourt] = nearBeijing ? BadmintonCourt.curatedBeijing : []

        if !usesOnlyCuratedCourts && isAuthorized {
            isSearchingCourts = true
            let found = await searchMapCourts(around: center)
            isSearchingCourts = false
            let existing = Set(result.map { "\($0.name)" })
            result += found.filter { !existing.contains($0.name) }
        }
        if result.count < 3 && !nearBeijing {
            result += BadmintonCourt.samples(around: center)
        }
        courts = result
        backend.updateKnownCourts(result)
    }

    private func searchMapCourts(around center: Coordinate) async -> [BadmintonCourt] {
        var found: [BadmintonCourt] = []
        let span = max(preferences.travelRadiusKm, 5) * 2000
        for query in ["羽毛球馆", "badminton"] {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: center.clCoordinate, latitudinalMeters: span, longitudinalMeters: span)
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems {
                let coordinate = Coordinate(item.placemark.coordinate)
                let name = item.name ?? "羽毛球馆"
                guard !found.contains(where: { $0.name == name }) else { continue }
                found.append(BadmintonCourt(
                    id: "map-\(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))",
                    name: name,
                    location: coordinate,
                    address: item.placemark.title ?? "地址待确认",
                    amenities: [],
                    operatingHours: .standard,
                    courtCount: 6,
                    pricePerHour: 50,
                    phone: item.phoneNumber,
                    source: .mapSearch
                ))
            }
            if found.count >= 3 { break }
        }
        return Array(found.prefix(15))
    }

    // MARK: Delegate handling (main actor)

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationError = nil
            manager.startUpdatingLocation()
        case .denied, .restricted:
            locationError = .permissionDenied
            Task { await refreshCourts() }
        default:
            break
        }
    }

    fileprivate func handleLocation(_ location: CLLocation) {
        currentLocation = location
        lastLocationUpdate = Date()
        locationError = nil
        backend.updateCurrentUserLocation(Coordinate(location.coordinate))
        if let last = lastSearchLocation, location.distance(from: last) < Self.refreshThresholdMeters {
            return
        }
        lastSearchLocation = location
        Task { await refreshCourts() }
    }

    fileprivate func handleFailure(_ error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            locationError = .permissionDenied
        } else {
            locationError = currentLocation == nil ? .unknown("暂时无法获取位置") : .locationUnavailable
        }
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.handleFailure(error)
        }
    }
}
