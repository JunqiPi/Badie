import Foundation

// MARK: - 自动补充球馆：核对开放数据的位置、收录 Apple 地图上的羽毛球馆

extension MockBackend {

    /// 附近还没用 Apple 地图核对过位置的开放数据场馆（没找到的 30 天后再试）
    func venuesAwaitingLocationCheck(near center: Coordinate, radiusKm: Double = 30, limit: Int = 10,
                                     now: Date = Date()) -> [BadmintonCourt] {
        let retryAfter: TimeInterval = 30 * 86400
        let pending = OpenDataVenues.all.filter { venue in
            venue.needsLocationCheck == true && db.venues[venue.id] == nil
                && venue.distance(from: center) <= radiusKm
                && db.locationChecks[venue.id].map { now.timeIntervalSince($0) > retryAfter } ?? true
        }
        return Array(pending.sorted { $0.distance(from: center) < $1.distance(from: center) }.prefix(limit))
    }

    /// 记录核对结果：找到就采用 Apple 地图的坐标和地址并开始显示，没找到就过一段时间再试
    func applyLocationCheck(venueId: String, match: VenueCandidate?, now: Date = Date()) {
        guard var venue = OpenDataVenues.byId[venueId] else { return }
        guard let match else {
            db.locationChecks[venueId] = now
            scheduleSave()
            return
        }
        venue.location = match.location
        venue.datum = match.datum
        venue.applePlaceId = match.applePlaceId
        if match.address.isComplete { venue.postalAddress = match.address }
        venue.needsLocationCheck = nil
        db.venues[venueId] = venue
        db.locationChecks[venueId] = nil
        scheduleSave()
        emit(.venuesChanged)
    }

    /// Apple 地图上名称明显是羽毛球场地、且不和已有球馆重复的地点，直接收录为“待确认”
    @discardableResult
    func importDiscoveredVenues(_ candidates: [VenueCandidate], now: Date = Date()) -> [BadmintonCourt] {
        var added: [BadmintonCourt] = []
        for candidate in candidates where BadmintonKeywords.looksLikeBadmintonVenue(candidate.name) && candidate.address.isComplete {
            guard duplicates(for: candidate).isEmpty else { continue }
            let id = candidate.applePlaceId.map { "v-ap-\($0)" } ?? "v-" + UUID().uuidString.prefix(8).lowercased()
            guard db.venues[id] == nil else { continue }
            let venue = BadmintonCourt(
                id: id, name: candidate.name, location: candidate.location, datum: candidate.datum,
                address: candidate.address, timeZoneId: candidate.timeZoneId, applePlaceId: candidate.applePlaceId,
                phone: candidate.phone, website: candidate.website, source: .appleMaps, status: .unconfirmed, createdAt: now
            )
            db.venues[id] = venue
            added.append(venue)
        }
        if !added.isEmpty {
            scheduleSave()
            emit(.venuesChanged)
        }
        return added
    }
}
