import Foundation

// MARK: - 正式后端：球馆
/// 球馆目录随 App 打包（和服务器同一套 ID）；球友新加的球馆按位置从服务器拉取，存进本地缓存。
/// 添加、确认、报错走服务器的函数：查重、每人每天 3 家的上限、管理员审核都在服务器上
extension MockBackend {

    struct RemoteVenue: Decodable {
        struct Pricing: Decodable {
            let perPerson: Double?
            let perCourtHour: Double?
        }

        let id: String
        let name: String
        let aliases: [String]?
        let lat: Double
        let lon: Double
        let street: String?
        let unit: String?
        let city: String?
        let region: String?
        let postalCode: String?
        let countryCode: String
        let timeZoneId: String?
        let applePlaceId: String?
        let courtCount: Int?
        let pricing: Pricing?
        let pricingNote: String?
        let currencyCode: String?
        let phone: String?
        let website: String?
        let entranceNote: String?
        let source: String
        let status: String
        let createdAt: Date?
        let playTimes: String?
        let locationApproximate: Bool?
    }

    private struct NearbyRow: Decodable {
        let venue: RemoteVenue
    }

    /// 附近的球馆：同一片区域（5 公里内、半径不变大）10 分钟内只拉一次，有新球馆再通知界面
    func refreshRemoteVenues(near center: Coordinate, radiusKm: Double) {
        guard let remote else { return }
        if let last = remoteVenuesLoaded, last.center.distanceKm(to: center) < 5, last.radiusKm >= radiusKm,
           Date().timeIntervalSince(last.at) < 600 { return }
        remoteVenuesLoaded = (center, radiusKm, Date())
        Task {
            do {
                let rows: [NearbyRow] = try await remote.rpc("venues_near", [
                    "lat": center.latitude, "lng": center.longitude, "radius_km": radiusKm, "max_results": 200,
                ])
                let changed = rows.filter { $0.venue.locationApproximate != true }.map { cacheRemoteVenue($0.venue) }.contains(true)
                if changed {
                    scheduleSave()
                    emit(.venuesChanged)
                }
            } catch {
                remoteVenuesLoaded = nil
            }
        }
    }

    /// 打包目录里有的以目录为准（字段更全），没有的存进缓存；返回缓存有没有变
    @discardableResult
    func cacheRemoteVenue(_ remote: RemoteVenue) -> Bool {
        guard OpenDataVenues.byId[remote.id] == nil else { return false }
        var court = Self.court(remote)
        if let cached = db.venues[remote.id] {
            court.confirmedBy = cached.confirmedBy
            guard court != cached else { return false }
        }
        db.venues[remote.id] = court
        return true
    }

    static func court(_ remote: RemoteVenue) -> BadmintonCourt {
        let pricing: VenuePricing
        if let perPerson = remote.pricing?.perPerson {
            pricing = .dropIn(perPerson: Int(perPerson.rounded()))
        } else if let perCourtHour = remote.pricing?.perCourtHour {
            pricing = .perCourtHour(Int(perCourtHour.rounded()))
        } else {
            pricing = .unknown
        }
        var court = BadmintonCourt(
            id: remote.id, name: remote.name, aliases: remote.aliases ?? [],
            location: Coordinate(latitude: remote.lat, longitude: remote.lon),
            address: PostalAddress(street: remote.street ?? "", unit: remote.unit, city: remote.city ?? "", region: remote.region ?? "",
                                   postalCode: remote.postalCode ?? "", countryCode: remote.countryCode),
            timeZoneId: remote.timeZoneId, applePlaceId: remote.applePlaceId, courtCount: remote.courtCount, pricing: pricing,
            pricingNote: remote.pricingNote, currencyCode: remote.currencyCode, phone: remote.phone, website: remote.website,
            entranceNote: remote.entranceNote, source: VenueSource(server: remote.source),
            status: VenueStatus(rawValue: remote.status) ?? .unconfirmed, createdAt: remote.createdAt ?? Date()
        )
        court.playTimes = remote.playTimes
        return court
    }

    // MARK: 写

    func remoteAddVenue(_ candidate: VenueCandidate, source: VenueSource, aliases: [String], courtCount: Int?,
                        entranceNote: String?) async throws -> BadmintonCourt {
        let remote = try requireRemote()
        var args: [String: Any] = [
            "name": candidate.name, "lat": candidate.location.latitude, "lng": candidate.location.longitude,
            "street": candidate.address.street, "city": candidate.address.city, "region": candidate.address.region,
            "postal_code": candidate.address.postalCode, "country_code": candidate.address.countryCode,
            "source": source.serverValue, "datum": candidate.datum.rawValue, "aliases": aliases,
            "alternate_place_ids": candidate.alternatePlaceIds,
        ]
        let optional: [String: Any?] = [
            "unit": candidate.address.unit, "time_zone_id": candidate.timeZoneId, "apple_place_id": candidate.applePlaceId,
            "court_count": courtCount, "entrance_note": entranceNote, "phone": candidate.phone, "website": candidate.website,
        ]
        for (key, value) in optional {
            if let value { args[key] = value }
        }
        let added: RemoteVenue = try await remote.rpc("add_venue", args)
        cacheRemoteVenue(added)
        scheduleSave()
        emit(.venuesChanged)
        // 和已有球馆是同一地点时服务器返回那一家（可能在打包目录里）
        return venue(id: added.id) ?? Self.court(added)
    }

    func remoteConfirmVenue(_ id: String) async throws {
        let remote = try requireRemote()
        let confirmed: RemoteVenue = try await remote.rpc("confirm_venue", ["target": id])
        // 服务器不告诉别人确认过谁：本机记下“我确认过”，状态以服务器为准
        guard let me = currentUserId else { return }
        var venue = venue(id: id) ?? Self.court(confirmed)
        venue.addConfirmation(from: me)
        venue.status = VenueStatus(rawValue: confirmed.status) ?? venue.status
        db.venues[venue.id] = venue
        scheduleSave()
        emit(.venuesChanged)
    }

    func remoteReportVenue(_ id: String, issue: VenueIssue, detail: String) async throws {
        try await requireRemote().call("report_venue", ["target": id, "issue": issue.serverValue, "detail": String(detail.prefix(200))])
    }
}

/// 正式后端的球馆服务：读本地缓存（和模拟后端同一套），写走服务器
@MainActor
final class RemoteVenueService: VenueService {
    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
    }

    var allVenues: [BadmintonCourt] { backend.allVenues }
    func venue(id: String) -> BadmintonCourt? { backend.venue(id: id) }
    func venues(near center: Coordinate, radiusKm: Double) -> [BadmintonCourt] { backend.venues(near: center, radiusKm: radiusKm) }
    func nearestVenues(to center: Coordinate, count: Int) -> [BadmintonCourt] { backend.nearestVenues(to: center, count: count) }
    func searchVenues(_ query: String, near center: Coordinate, limit: Int) -> [VenueSearch.Hit] {
        backend.searchVenues(query, near: center, limit: limit)
    }
    func duplicates(for candidate: VenueCandidate) -> [VenueSearch.Duplicate] { backend.duplicates(for: candidate) }
    func hasConfirmed(_ id: String) -> Bool { backend.hasConfirmed(id) }
    func regularsCount(for venueId: String) -> Int { backend.regularsCount(for: venueId) }

    func addVenue(_ candidate: VenueCandidate, source: VenueSource, aliases: [String], courtCount: Int?,
                  entranceNote: String?, now: Date) async throws -> BadmintonCourt {
        try await backend.remoteAddVenue(candidate, source: source, aliases: aliases, courtCount: courtCount, entranceNote: entranceNote)
    }

    func confirmVenue(_ id: String) async throws {
        try await backend.remoteConfirmVenue(id)
    }

    func reportVenue(_ id: String, issue: VenueIssue, detail: String) async throws {
        try await backend.remoteReportVenue(id, issue: issue, detail: detail)
    }
}

extension VenueSource {
    init(server value: String) {
        switch value {
        case "apple_maps": self = .appleMaps
        case "open_street_map": self = .openStreetMap
        case "open_data": self = .openData
        default: self = VenueSource(rawValue: value) ?? .player
        }
    }

    var serverValue: String {
        switch self {
        case .appleMaps: return "apple_maps"
        case .openStreetMap: return "open_street_map"
        case .openData: return "open_data"
        default: return rawValue
        }
    }
}

extension VenueIssue {
    var serverValue: String {
        switch self {
        case .wrongLocation: return "wrong_location"
        case .closed: return "closed"
        case .duplicate: return "duplicate"
        case .notBadminton: return "not_badminton"
        case .other: return "other"
        }
    }
}
