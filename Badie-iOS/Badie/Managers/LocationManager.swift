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
                self?.backfillFavoriteIfNeeded()
            case .userUpdated:
                // 启动时从服务器刷新资料会顺便读常去球馆，这里跟上
                guard let self else { return }
                let favorites = self.backend.favoriteCourtIds()
                if favorites != self.favoriteCourtIds { self.favoriteCourtIds = favorites }
                self.backfillFavoriteIfNeeded()
            case .venuesChanged:
                self?.refreshCourts()
                self?.backfillFavoriteIfNeeded()
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

    /// 出行范围内离我最近的球馆。只在拿到真实定位时给，没定位时不按默认城市猜
    var nearestCourtToUser: BadmintonCourt? {
        guard let currentLocation else { return nil }
        return BadmintonCourt.nearest(in: nearbyCourts, to: Coordinate(currentLocation.coordinate),
                                      withinKm: preferences.travelRadiusKm)
    }

    // MARK: 老用户补常去球馆

    /// 附近的人按常去球馆找人：以前注册时没选常去球馆的人，替他收藏最近的一家。
    /// 每个账号只做一次（记在本机），之后自己全删了也不再补。
    /// 注册最后一步保存期间暂停，免得和用户自己选的球馆一起加上
    var holdsFavoriteBackfill = false

    private static func favoriteBackfillKey(_ userId: String) -> String { "BadieFavoriteBackfill.\(userId)" }

    /// 这个账号不用再自动补（注册时已经选过）
    func markFavoriteBackfillDone() {
        guard let userId = backend.currentUserId else { return }
        defaults.set(true, forKey: Self.favoriteBackfillKey(userId))
    }

    private func backfillFavoriteIfNeeded() {
        guard !holdsFavoriteBackfill, let userId = backend.currentUserId else { return }
        let key = Self.favoriteBackfillKey(userId)
        let nearest = nearestCourtToUser
        let decision = FavoriteBackfill.decide(isRemote: backend.isRemote,
                                               favoritesLoaded: backend.remoteFavoritesLoadedFor == userId,
                                               hasFavorites: !backend.favoriteCourtIds().isEmpty,
                                               alreadyDone: defaults.bool(forKey: key),
                                               hasNearbyCourt: nearest != nil)
        switch decision {
        case .wait:
            break
        case .markDone:
            defaults.set(true, forKey: key)
        case .pick:
            guard let nearest else { return }
            defaults.set(true, forKey: key)
            toggleFavorite(nearest.id)
        }
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
        // 正式后端：球友新加的球馆在服务器上，拉到了会再通知（venuesChanged）
        if backend.isRemote { backend.refreshRemoteVenues(near: coordinate, radiusKm: preferences.travelRadiusKm) }
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
        backfillFavoriteIfNeeded()
        // 后台发现会把 Apple 地图上的场地直接放进本机球馆库；正式后端只收球友确认过再提交的
        guard allowsMapSearch, !backend.isRemote else { return }
        Task {
            await VenueDiscovery.run(backend: backend, near: Coordinate(location.coordinate))
            refreshCourts()
        }
    }
}

// MARK: - 自动选常去球馆

extension BadmintonCourt {
    /// 范围内离 center 最近的一家；优先已确认的球馆，范围内一家都没有就返回 nil
    static func nearest(in courts: [BadmintonCourt], to center: Coordinate, withinKm radiusKm: Double) -> BadmintonCourt? {
        let inRange = courts.filter { $0.distance(from: center) <= radiusKm }
        // 先挑核实过的，再挑室内的，都没有才用露天场地
        let listed = inRange.filter { $0.status != .unconfirmed }
        let indoor = inRange.filter { $0.facility != .outdoor }
        let pool = !listed.isEmpty ? listed : !indoor.isEmpty ? indoor : inRange
        return pool.min { $0.distance(from: center) < $1.distance(from: center) }
    }
}

/// 老用户补常去球馆：什么时候替他选
enum FavoriteBackfill {
    enum Decision: Equatable {
        /// 现在不动（演示后端、做过了、还没读到服务器上的收藏、还不知道附近的球馆）
        case wait
        /// 已经有常去球馆：记下来，以后全删了也不补
        case markDone
        /// 收藏最近的一家
        case pick
    }

    static func decide(isRemote: Bool, favoritesLoaded: Bool, hasFavorites: Bool, alreadyDone: Bool,
                       hasNearbyCourt: Bool) -> Decision {
        guard isRemote, !alreadyDone, favoritesLoaded else { return .wait }
        if hasFavorites { return .markDone }
        return hasNearbyCourt ? .pick : .wait
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
