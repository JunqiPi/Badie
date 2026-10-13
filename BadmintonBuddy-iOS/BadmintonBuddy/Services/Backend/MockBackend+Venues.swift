import Foundation

// MARK: - 球馆库：所有人共用的唯一标准
//
// 匹配、房间、球局只认球馆 ID。用户从 Apple 地图选中或手动添加的地点，
// 先查重（Place ID / 距离 + 名称），确认不是已有球馆后才入库，状态为“待确认”；
// 3 位不同球友确认（或在此签到打过球）后升级为“球友确认”。

extension MockBackend {

    var allVenues: [BadmintonCourt] { Array(db.venues.values) }

    func venue(id: String) -> BadmintonCourt? { db.venues[id] }

    /// 半径内的球馆，按距离排序
    func venues(near center: Coordinate, radiusKm: Double) -> [BadmintonCourt] {
        db.venues.values
            .filter { $0.distance(from: center) <= radiusKm }
            .sorted { $0.distance(from: center) < $1.distance(from: center) }
    }

    /// 离某处最近的若干球馆（不限半径）
    func nearestVenues(to center: Coordinate, count: Int) -> [BadmintonCourt] {
        Array(db.venues.values.sorted { $0.distance(from: center) < $1.distance(from: center) }.prefix(count))
    }

    /// 模拟世界（机器人所在城市）附近、对外开放的球馆
    var worldVenues: [BadmintonCourt] {
        venues(near: db.worldCenter, radiusKm: 25).filter { $0.status != .unconfirmed }
    }

    func searchVenues(_ query: String, near center: Coordinate, limit: Int = 20) -> [VenueSearch.Hit] {
        VenueSearch.search(allVenues.filter { !isHiddenPendingReview($0) }, query: query, near: center, limit: limit)
    }

    /// 待确认的球馆被 2 位以上不同球友报告问题时，暂时不在搜索中出现，等待人工审核
    /// （添加者本人仍能看到）。单个报告不会让球馆下架。
    func isHiddenPendingReview(_ venue: BadmintonCourt) -> Bool {
        guard venue.status == .unconfirmed, venue.addedBy != currentUserId else { return false }
        let reporters = Set(db.venueReports.filter { $0.venueId == venue.id }.map(\.reporterId))
        return reporters.count >= 2
    }

    func duplicates(for candidate: VenueCandidate) -> [VenueSearch.Duplicate] {
        VenueSearch.duplicates(name: candidate.name, location: candidate.location,
                               applePlaceId: candidate.applePlaceId, alternatePlaceIds: candidate.alternatePlaceIds,
                               in: allVenues)
    }

    /// 加入球馆库。Place ID 已存在时直接返回已有球馆，不会重复创建。
    @discardableResult
    func addVenue(_ candidate: VenueCandidate, source: VenueSource, aliases: [String] = [], courtCount: Int? = nil,
                  entranceNote: String? = nil) throws -> BadmintonCourt {
        let me = try requireUser()
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(name.count) else { throw BackendError.venueNameInvalid }
        guard candidate.address.isComplete else { throw BackendError.venueAddressIncomplete }
        if let existing = duplicates(for: candidate).first(where: { $0.kind == .samePlace }) {
            return existing.venue
        }
        let cleanedAliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != name }
        let id: String
        if let placeId = candidate.applePlaceId, !placeId.isEmpty, db.venues["v-ap-\(placeId)"] == nil {
            id = "v-ap-\(placeId)"
        } else {
            id = "v-" + UUID().uuidString.prefix(8).lowercased()
        }
        let venue = BadmintonCourt(
            id: id,
            name: name,
            aliases: Array(Set(cleanedAliases)).sorted(),
            location: candidate.location,
            datum: candidate.datum,
            address: candidate.address,
            timeZoneId: candidate.timeZoneId,
            applePlaceId: candidate.applePlaceId,
            courtCount: courtCount,
            phone: candidate.phone,
            website: candidate.website,
            entranceNote: entranceNote.map { String($0.prefix(80)) },
            source: source,
            status: .unconfirmed,
            addedBy: me.id,
            confirmedBy: [me.id],
            lastConfirmedAt: Date(),
            createdAt: Date()
        )
        db.venues[venue.id] = venue
        assignBotHomeVenues()
        scheduleSave()
        emit(.venuesChanged)
        return venue
    }

    /// 球友确认“地址正确”
    func confirmVenue(_ id: String) throws {
        let me = try requireUser()
        guard var venue = db.venues[id] else { throw BackendError.venueNotFound }
        venue.addConfirmation(from: me.id)
        db.venues[id] = venue
        scheduleSave()
        emit(.venuesChanged)
    }

    func hasConfirmed(_ id: String) -> Bool {
        guard let me = currentUserId else { return false }
        return db.venues[id]?.confirmedBy.contains(me) ?? false
    }

    /// 报告球馆信息有误（位置不对、已关门、重复…）
    func reportVenue(_ id: String, issue: VenueIssue, detail: String = "") throws {
        let me = try requireUser()
        guard db.venues[id] != nil else { throw BackendError.venueNotFound }
        db.venueReports.append(VenueReport(venueId: id, reporterId: me.id, issue: issue,
                                           detail: String(detail.prefix(200)), createdAt: Date()))
        scheduleSave()
    }

    /// 把这里设为常去球馆的人数（含模拟球友）
    func regularsCount(for venueId: String) -> Int {
        db.favoriteCourtIds.values.filter { $0.contains(venueId) }.count
    }

    /// 签到打过球的人自动算作确认了地址
    func confirmVenueFromCheckIns(_ game: Game) {
        guard var venue = db.venues[game.court.id] else { return }
        for userId in game.checkIns.keys.sorted() {
            venue.addConfirmation(from: userId)
        }
        db.venues[venue.id] = venue
    }

    /// 模拟球友的常去球馆：离自己最近的 1–2 家（30 公里内）
    func assignBotHomeVenues() {
        let pool = worldVenues
        for (id, _) in db.bots {
            guard let location = db.users[id]?.location else { continue }
            let nearest = pool
                .filter { $0.distance(from: location) <= 30 }
                .sorted { $0.distance(from: location) < $1.distance(from: location) }
            let count = abs(id.stableHash) % 3 == 0 ? 1 : 2
            db.favoriteCourtIds[id] = nearest.prefix(count).map(\.id)
        }
    }
}
