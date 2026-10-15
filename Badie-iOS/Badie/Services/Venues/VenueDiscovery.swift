import Foundation

/// 用户到了一个新地方时跑一次（同一片区域 6 小时内不重复）：
/// 1. 附近只知道大概位置的开放数据场馆，用名称在 Apple 地图上找到对应地点，核对后才显示
/// 2. 出行范围内收录的球馆太少时，用当地叫法搜 Apple 地图，名称明显是羽毛球场地的直接收录
@MainActor
enum VenueDiscovery {
    private static var lastRun: (center: Coordinate, date: Date)?

    static func run(backend: MockBackend, near center: Coordinate, now: Date = Date()) async {
        if let last = lastRun, last.center.distanceKm(to: center) < 5, now.timeIntervalSince(last.date) < 6 * 3600 { return }
        lastRun = (center, now)

        for venue in backend.venuesAwaitingLocationCheck(near: center) {
            let results = await AppleMapsSearch.search(venue.name, near: venue.location, radiusKm: 10, limit: 5)
            backend.applyLocationCheck(venueId: venue.id, match: results.first { isSamePlace($0.name, venue.name) })
        }
        if backend.venues(near: center, radiusKm: 15).count < 8 {
            let found = await AppleMapsSearch.searchBadmintonVenues(near: center, countryCode: backend.currentCountryCode)
            backend.importDiscoveredVenues(found)
        }
    }

    /// 名称是否指同一个地方：去掉空格后互相包含（韩文、日文名常有空格差异），或分词相似
    nonisolated static func isSamePlace(_ a: String, _ b: String) -> Bool {
        let compactA = VenueSearch.normalize(a).replacingOccurrences(of: " ", with: "")
        let compactB = VenueSearch.normalize(b).replacingOccurrences(of: " ", with: "")
        if min(compactA.count, compactB.count) >= 3, compactA.contains(compactB) || compactB.contains(compactA) { return true }
        return VenueSearch.nameSimilarity(a, b) >= 0.6
    }
}
