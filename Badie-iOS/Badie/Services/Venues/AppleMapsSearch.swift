import Foundation
import MapKit
import Combine

// MARK: - 地图上找到、尚未进入平台球馆库的地点

struct VenueCandidate: Identifiable, Hashable {
    var id: String { applePlaceId ?? "\(location.latitude),\(location.longitude)|\(name)" }
    var name: String
    var location: Coordinate
    var address: PostalAddress
    var applePlaceId: String?
    /// 同一地点的其他 Place ID（Apple 允许多个 ID 指向同一地点）
    var alternatePlaceIds: [String] = []
    var timeZoneId: String?
    var phone: String?
    var website: String?

    /// 中国大陆的地图数据可能是 GCJ-02（Apple 不提供判断接口，按国家保守处理）
    var datum: CoordinateDatum { address.countryCode == "CN" ? .gcj02 : .wgs84 }
}

extension VenueCandidate {
    /// 从 Apple 地图结果构造（地址按字段拆开，便于按国家格式化与搜索）
    init(mapItem item: MKMapItem) {
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let country = placemark.isoCountryCode ?? CountryInfo.defaultCountry.code
        let isEastAsian = CountryInfo.info(for: country).addressStyle == .largeToSmall
        let address = PostalAddress(
            // 东亚地址门牌在街道后面
            street: isEastAsian
                ? [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined()
                : (street.isEmpty ? (placemark.name ?? "") : street),
            city: isEastAsian ? (placemark.subLocality ?? placemark.locality ?? "") : (placemark.locality ?? placemark.subLocality ?? ""),
            region: isEastAsian ? (placemark.locality ?? placemark.administrativeArea ?? "") : (placemark.administrativeArea ?? ""),
            postalCode: placemark.postalCode ?? "",
            countryCode: country
        )
        var placeId: String?
        var alternates: [String] = []
        if #available(iOS 18.0, *) {
            placeId = item.identifier?.rawValue
            alternates = item.alternateIdentifiers.map(\.rawValue)
        }
        self.init(
            name: item.name ?? address.streetLine,
            location: Coordinate(placemark.coordinate),
            address: address,
            applePlaceId: placeId,
            alternatePlaceIds: alternates,
            timeZoneId: item.timeZone?.identifier,
            phone: item.phoneNumber,
            website: item.url?.absoluteString
        )
    }
}

// MARK: - Apple 地图搜索（输入联想 + 解析 + 反向地理编码）

@MainActor
final class AppleMapsSearch: NSObject, ObservableObject {
    /// 输入联想结果：title 是名称，subtitle 是地址
    @Published private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    /// - Parameter addressesOnly: 添加球馆时搜索地址；选择球馆时搜索地点
    init(addressesOnly: Bool = false) {
        super.init()
        completer.delegate = self
        completer.resultTypes = addressesOnly ? .address : .pointOfInterest
    }

    func update(query: String, near center: Coordinate, radiusKm: Double = 40) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completer.cancel()
            completions = []
            return
        }
        completer.region = MKCoordinateRegion(center: center.clCoordinate,
                                              latitudinalMeters: radiusKm * 2000, longitudinalMeters: radiusKm * 2000)
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.cancel()
        completions = []
    }

    /// 把联想结果解析成完整地点（坐标、结构化地址、Place ID）
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> VenueCandidate {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { throw BackendError.venueNotFound }
        return VenueCandidate(mapItem: item)
    }

    /// 按关键词搜索附近地点（粘贴链接后用名称找回地点、或“附近的羽毛球馆”建议）
    static func search(_ query: String, near center: Coordinate, radiusKm: Double = 40, limit: Int = 8) async -> [VenueCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: center.clCoordinate,
                                            latitudinalMeters: radiusKm * 2000, longitudinalMeters: radiusKm * 2000)
        // Apple 对搜索有未公开的频率限制（开发者观察约 60 秒 50 次），被限流时直接放弃这次建议
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(limit).map(VenueCandidate.init(mapItem:))
    }

    /// 附近的羽毛球场地：同时用英文和当地叫法搜（Apple 地图没有羽毛球分类，只能按名称匹配），合并去重后按距离排序
    static func searchBadmintonVenues(near center: Coordinate, countryCode: String, radiusKm: Double = 40,
                                      limit: Int = 12) async -> [VenueCandidate] {
        let queries = BadmintonKeywords.queries(for: countryCode)
        let batches = await withTaskGroup(of: [VenueCandidate].self) { group in
            for query in queries {
                group.addTask { await AppleMapsSearch.search(query, near: center, radiusKm: radiusKm, limit: limit) }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        var merged: [VenueCandidate] = []
        for candidate in batches.sorted(by: { $0.location.distanceKm(to: center) < $1.location.distanceKm(to: center) }) {
            let isDuplicate = merged.contains {
                $0.id == candidate.id || $0.location.distanceKm(to: candidate.location) < 0.08
            }
            if !isDuplicate { merged.append(candidate) }
        }
        return Array(merged.prefix(limit))
    }

    /// 通过 Apple Place ID 取回地点（iOS 18+）
    static func mapItem(placeId: String) async -> MKMapItem? {
        guard #available(iOS 18.0, *) else { return nil }
        let identifier: MKMapItem.Identifier? = MKMapItem.Identifier(rawValue: placeId)
        guard let identifier else { return nil }
        return try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
    }

    /// 放图钉时把坐标转成地址
    static func reverseGeocode(_ coordinate: Coordinate) async -> VenueCandidate? {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(coordinate.clLocation).first else { return nil }
        let item = MKMapItem(placemark: MKPlacemark(placemark: placemark))
        var candidate = VenueCandidate(mapItem: item)
        // 图钉坐标来自设备定位/地图中心，按 WGS-84 处理
        candidate.location = coordinate
        candidate.timeZoneId = placemark.timeZone?.identifier
        candidate.name = ""
        return candidate
    }

    /// 展开地图短链（只读取跳转后的地址，不下载页面内容）
    static func expand(_ url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return response.url
    }
}

extension AppleMapsSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = Array(results.prefix(8))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }
}

// MARK: - 各地对羽毛球场地的叫法

enum BadmintonKeywords {
    /// 最多 3 个搜索词：英文 + 当地常用叫法（印尼的 GOR、越南的 sân cầu lông 等名称里往往没有 “badminton”）
    static func queries(for countryCode: String) -> [String] {
        let local: [String]
        switch countryCode.uppercased() {
        case "CN": local = ["羽毛球馆", "羽毛球"]
        case "TW", "HK": local = ["羽球館", "羽毛球"]
        case "JP": local = ["バドミントン"]
        case "KR": local = ["배드민턴"]
        case "ID": local = ["bulu tangkis", "GOR badminton"]
        case "MY": local = ["dewan badminton", "badminton court"]
        case "TH": local = ["แบดมินตัน"]
        case "VN": local = ["sân cầu lông"]
        case "IN": local = ["badminton court", "बैडमिंटन"]
        case "DK": local = ["badmintonhal", "badmintonklub"]
        case "DE": local = ["Badmintonhalle"]
        case "FR": local = ["club de badminton"]
        default: local = ["badminton court"]
        }
        return Array((["badminton"] + local).prefix(3))
    }

    private static let nameWords = ["badminton", "羽毛球", "羽球", "バドミントン", "배드민턴", "แบดมินตัน",
                                    "cầu lông", "cau long", "bulu tangkis", "बैडमिंटन"]

    /// 名称明显是羽毛球场地（自动收录只认名称，不猜综合体育馆）
    static func looksLikeBadmintonVenue(_ name: String) -> Bool {
        let lower = name.lowercased()
        return nameWords.contains { lower.contains($0) } || name.range(of: #"\bGOR\b"#, options: .regularExpression) != nil
    }
}
