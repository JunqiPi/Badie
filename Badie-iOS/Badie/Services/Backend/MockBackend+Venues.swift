import Foundation

// MARK: - 球馆库：所有人共用的唯一标准
//
// 匹配、房间、球局只认球馆 ID。用户从 Apple 地图选中或手动添加的地点，
// 先查重（Place ID / 距离 + 名称），确认不是已有球馆后才入库，状态为“待确认”；
// 3 位不同球友确认（或在此签到打过球）后升级为“球友确认”。

extension MockBackend {

    /// 球馆库（不含已合并到别处的旧条目）
    var allVenues: [BadmintonCourt] {
        db.venues.values.filter { $0.mergedInto == nil } + OpenDataVenues.located.filter { db.venues[$0.id] == nil }
    }

    /// 库里的版本优先，其次是只读的开放数据目录
    func storedVenue(id: String) -> BadmintonCourt? {
        db.venues[id] ?? OpenDataVenues.byId[id]
    }

    /// 按 ID 取球馆；已合并的旧 ID 自动跳到保留的那一家
    func venue(id: String) -> BadmintonCourt? {
        var current = storedVenue(id: id)
        var hops = 0
        while let target = current?.mergedInto, let next = storedVenue(id: target), hops < 5 {
            current = next
            hops += 1
        }
        return current
    }

    /// 每人每天最多添加的球馆数（防刷）
    static let dailyVenueAddLimit = 3

    func venuesAddedToday(by userId: String, now: Date = Date()) -> Int {
        db.venues.values.filter { $0.addedBy == userId && now.timeIntervalSince($0.createdAt) < 24 * 3600 }.count
    }

    /// 半径内的球馆，按距离排序
    func venues(near center: Coordinate, radiusKm: Double) -> [BadmintonCourt] {
        allVenues
            .filter { $0.distance(from: center) <= radiusKm }
            .sorted { $0.distance(from: center) < $1.distance(from: center) }
    }

    /// 离某处最近的若干球馆（不限半径）
    func nearestVenues(to center: Coordinate, count: Int) -> [BadmintonCourt] {
        Array(allVenues.sorted { $0.distance(from: center) < $1.distance(from: center) }.prefix(count))
    }

    /// 模拟世界（机器人所在城市）附近、对外开放的球馆
    var worldVenues: [BadmintonCourt] {
        venues(near: db.worldCenter, radiusKm: 25).filter { $0.status != .unconfirmed }
    }

    /// 待确认的球馆被 2 位以上不同球友报告问题时，暂时不在搜索中出现，等待人工审核（添加者本人仍能看到）。单个报告不会让球馆下架
    var searchableVenues: [BadmintonCourt] {
        // 先数好每家球馆被几个人报告过，不用每家球馆都把报告翻一遍
        let reporters = Dictionary(grouping: db.venueReports, by: \.venueId).mapValues { Set($0.map(\.reporterId)).count }
        return allVenues.filter { venue in
            !(venue.status == .unconfirmed && venue.addedBy != currentUserId && reporters[venue.id, default: 0] >= 2)
        }
    }

    func searchVenues(_ query: String, near center: Coordinate, limit: Int = 20) -> [VenueSearch.Hit] {
        VenueSearch.search(searchableVenues, query: query, near: center, limit: limit)
    }

    func duplicates(for candidate: VenueCandidate) -> [VenueSearch.Duplicate] {
        VenueSearch.duplicates(name: candidate.name, location: candidate.location,
                               applePlaceId: candidate.applePlaceId, alternatePlaceIds: candidate.alternatePlaceIds,
                               in: allVenues)
    }

    /// 加入球馆库。
    /// - Place ID 相同：直接返回已有球馆，不重复创建
    /// - 200 米内名称相近：拒绝（只能选已有的），避免同一家出现多个条目、匹配被拆散
    /// - 同一栋楼但名称不同：允许（可能是不同场馆），标记给人工复核
    @discardableResult
    func addVenue(_ candidate: VenueCandidate, source: VenueSource, aliases: [String] = [], courtCount: Int? = nil,
                  entranceNote: String? = nil, now: Date = Date()) throws -> BadmintonCourt {
        let me = try requireUser()
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(name.count) else { throw BackendError.venueNameInvalid }
        guard candidate.address.isComplete else { throw BackendError.venueAddressIncomplete }
        let found = duplicates(for: candidate)
        if let existing = found.first(where: { $0.kind == .samePlace }) {
            return existing.venue
        }
        if let existing = found.first(where: { $0.kind.blocksAdding }) {
            throw BackendError.venueDuplicate(existingName: existing.venue.name)
        }
        guard venuesAddedToday(by: me.id, now: now) < Self.dailyVenueAddLimit else { throw BackendError.venueRateLimited }
        let cleanedAliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != name }
        let id: String
        if let placeId = candidate.applePlaceId, !placeId.isEmpty, db.venues["v-ap-\(placeId)"] == nil {
            id = "v-ap-\(placeId)"
        } else {
            id = "v-" + UUID().uuidString.prefix(8).lowercased()
        }
        var venue = BadmintonCourt(
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
            lastConfirmedAt: now,
            createdAt: now
        )
        if let neighbor = found.first(where: { $0.kind == .sameBuilding }) {
            venue.reviewFlag = "同一栋楼已有：\(neighbor.venue.name)"
        }
        db.venues[venue.id] = venue
        assignBotHomeVenues()
        scheduleSave()
        emit(.venuesChanged)
        return venue
    }

    /// 合并重复条目（审核操作）：旧条目指向保留的球馆，名称记为别名，确认人与收藏一并转过去
    func mergeVenue(_ duplicateId: String, into targetId: String) throws {
        guard duplicateId != targetId, var duplicate = storedVenue(id: duplicateId), var target = venue(id: targetId),
              target.id != duplicateId else { throw BackendError.venueNotFound }
        if duplicate.name != target.name && !target.aliases.contains(duplicate.name) {
            target.aliases.append(duplicate.name)
        }
        target.aliases = Array(Set(target.aliases + duplicate.aliases).subtracting([target.name])).sorted()
        for userId in duplicate.confirmedBy { target.addConfirmation(from: userId) }
        duplicate.mergedInto = target.id
        db.venues[duplicate.id] = duplicate
        db.venues[target.id] = target
        let keptId = target.id
        // 旧 ID 换成保留的 ID，并去掉因此产生的重复（保持原顺序）
        func redirected(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.map { $0 == duplicateId ? keptId : $0 }.filter { seen.insert($0).inserted }
        }
        for (userId, favorites) in db.favoriteCourtIds where favorites.contains(duplicateId) {
            db.favoriteCourtIds[userId] = redirected(favorites)
        }
        for (ticketId, ticket) in db.tickets where ticket.courtIds.contains(duplicateId) {
            db.tickets[ticketId]?.courtIds = redirected(ticket.courtIds)
        }
        scheduleSave()
        emit(.venuesChanged)
    }

    /// 球友确认“地址正确”
    func confirmVenue(_ id: String) throws {
        let me = try requireUser()
        guard var venue = storedVenue(id: id) else { throw BackendError.venueNotFound }
        venue.addConfirmation(from: me.id)
        db.venues[id] = venue
        scheduleSave()
        emit(.venuesChanged)
    }

    func hasConfirmed(_ id: String) -> Bool {
        guard let me = currentUserId else { return false }
        return storedVenue(id: id)?.confirmedBy.contains(me) ?? false
    }

    /// 报告球馆信息有误（位置不对、已关门、重复…）
    func reportVenue(_ id: String, issue: VenueIssue, detail: String = "") throws {
        let me = try requireUser()
        guard storedVenue(id: id) != nil else { throw BackendError.venueNotFound }
        db.venueReports.append(VenueReport(venueId: id, reporterId: me.id, issue: issue,
                                           detail: String(detail.prefix(200)), createdAt: Date()))
        scheduleSave()
    }

    /// 把这里设为常去球馆的人数（含模拟球友）
    func regularsCount(for venueId: String) -> Int {
        db.favoriteCourtIds.values.filter { $0.contains(venueId) }.count
    }

    /// 同上；正式后端向服务器查（失败时为 nil）
    func fetchRegularsCount(for venueId: String) async -> Int? {
        isRemote ? await remoteRegularsCount(for: venueId) : regularsCount(for: venueId)
    }

    /// 签到打过球的人自动算作确认了地址
    func confirmVenueFromCheckIns(_ game: Game) {
        guard var venue = storedVenue(id: game.court.id) else { return }
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
