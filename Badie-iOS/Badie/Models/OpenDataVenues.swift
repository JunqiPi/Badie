import Foundation

// MARK: - 各地政府开放数据里的羽毛球馆
//
// 由 scripts/build_open_data_venues.py 生成的 venues-XX.json（香港康文署、新加坡 SportSG、
// 台湾运动部、英格兰 Sport England）。只读、随 App 发布，不写进本地数据库；
// 球友确认、签到或纠错时才复制一份进库（库里的版本优先）。

enum OpenDataVenues {
    private struct Catalog: Decodable {
        let attribution: String
        let venues: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let name: String
        let aliases: [String]?
        let lat: Double
        let lon: Double
        let street: String
        let city: String
        let region: String
        let postcode: String
        let country: String
        let tz: String
        let courts: Int?
        let phone: String?
        let web: String?
        /// 坐标只精确到区（原始数据没有坐标），要先用 Apple 地图核对
        let approx: Bool?
        /// 条目自己的署名（如日本各区市的数据各自署名）
        let attr: String?
    }

    static let all: [BadmintonCourt] = load()
    /// 位置可信、可以直接显示的
    static let located: [BadmintonCourt] = all.filter { $0.needsLocationCheck != true }
    static let byId: [String: BadmintonCourt] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static func load(bundle: Bundle = .main) -> [BadmintonCourt] {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("venues-") }
        return urls.flatMap { url -> [BadmintonCourt] in
            guard let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
            return catalog.venues.map { entry in
                var court = BadmintonCourt(
                    id: entry.id, name: entry.name, aliases: entry.aliases ?? [],
                    location: Coordinate(latitude: entry.lat, longitude: entry.lon),
                    address: PostalAddress(street: entry.street, city: entry.city, region: entry.region,
                                           postalCode: entry.postcode, countryCode: entry.country),
                    timeZoneId: entry.tz, courtCount: entry.courts, phone: entry.phone, website: entry.web,
                    source: .openData, status: entry.approx == true ? .unconfirmed : .verified
                )
                court.attribution = entry.attr ?? catalog.attribution
                court.needsLocationCheck = entry.approx == true ? true : nil
                return court
            }
        }
    }
}
