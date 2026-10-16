import Foundation

/// 随 App 打包的球馆目录（Resources 里的 JSON）。网页端构建和数据库种子读的也是这批文件。
enum VenueCatalog {
    private struct File: Decodable {
        /// 平台收录 / OSM 导入；政府开放数据的目录没有这个字段（它们的 source 是来源说明文字）
        let kind: VenueSource?
        let status: VenueStatus?
        let attribution: String?
        let venues: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let name: String
        let aliases: [String]?
        let lat: Double
        let lon: Double
        let street: String
        let unit: String?
        let city: String
        let region: String
        let postcode: String
        let country: String
        let tz: String
        let courts: Int?
        let price: Price?
        let priceNote: String?
        let phone: String?
        let web: String?
        let entrance: String?
        let status: VenueStatus?
        /// 坐标只精确到区（原始数据没有坐标），要先用 Apple 地图核对
        let approx: Bool?
        /// 条目自己的署名（如日本各区市的数据各自署名）
        let attr: String?
        let facility: VenueFacility?
        let playTimes: String?
        /// 核实日期，如 "2026-10-16"
        let checked: String?
    }

    private struct Price: Decodable {
        let perPerson: Int?
        let perCourtHour: Int?

        var pricing: VenuePricing {
            if let perPerson { return .dropIn(perPerson: perPerson) }
            if let perCourtHour { return .perCourtHour(perCourtHour) }
            return .unknown
        }
    }

    static func load(_ name: String, bundle: Bundle = .main) -> [BadmintonCourt] {
        bundle.url(forResource: name, withExtension: "json").map(decode) ?? []
    }

    static func decode(_ url: URL) -> [BadmintonCourt] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.venues.map { entry in
            var court = BadmintonCourt(
                id: entry.id, name: entry.name, aliases: entry.aliases ?? [],
                location: Coordinate(latitude: entry.lat, longitude: entry.lon),
                address: PostalAddress(street: entry.street, unit: entry.unit, city: entry.city, region: entry.region,
                                       postalCode: entry.postcode, countryCode: entry.country),
                timeZoneId: entry.tz, courtCount: entry.courts, pricing: entry.price?.pricing ?? .unknown,
                pricingNote: entry.priceNote, phone: entry.phone, website: entry.web, entranceNote: entry.entrance,
                source: file.kind ?? .openData,
                status: entry.approx == true ? .unconfirmed : (entry.status ?? file.status ?? .verified)
            )
            court.attribution = entry.attr ?? file.attribution
            court.needsLocationCheck = entry.approx == true ? true : nil
            court.facility = entry.facility
            court.playTimes = entry.playTimes
            court.checkedOn = entry.checked.flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle().year().month().day()) }
            return court
        }
    }
}
