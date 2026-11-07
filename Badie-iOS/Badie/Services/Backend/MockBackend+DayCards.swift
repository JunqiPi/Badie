import Foundation

// MARK: - 首页按天看能约的人
/// 正式后端：服务器列出这天附近在找人、我能约的请求。演示模式：用示例球友当天有空的时间段
extension MockBackend {

    struct DayCandidate: Identifiable, Equatable {
        struct Venue: Equatable {
            let id: String
            let name: String
            /// 离我多远（公里）
            var km: Double? = nil
        }

        let ticketId: String
        let userId: String
        let mode: GameMode
        let mixed: Bool
        let startsAt: Date
        let endsAt: Date
        let recentNoShows: Int
        let venues: [Venue]

        var id: String { ticketId }
    }

    private struct RemoteCandidate: Decodable {
        struct Person: Decodable {
            let id: String
            let nickname: String
            let tag: Int?
            let rating: Double
            let recentNoShows: Int?
            let avatar: String?
            let cardColor: String?
            let cardPhoto: String?
        }

        struct Place: Decodable {
            let id: String
            let name: String
            let km: Double?
        }

        let ticket: String
        let mode: String
        let mixed: Bool
        let startsAt: Date
        let endsAt: Date
        let user: Person
        let venues: [Place]?
    }

    func dayCandidates(on day: Date, center: Coordinate, radiusKm: Double) async throws -> [DayCandidate] {
        guard let remote else { return demoDayCandidates(on: day, center: center, radiusKm: radiusKm) }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let items: [RemoteCandidate] = try await remote.rpc("day_candidates", [
            "p_from": Self.iso(start), "p_to": Self.iso(end),
            "p_lat": center.latitude, "p_lon": center.longitude, "p_radius_km": radiusKm,
        ])
        for item in items {
            // 存进缓存：卡片上的头像、背景、资料页都从这里读
            cacheRemoteUser(id: item.user.id, nickname: item.user.nickname, rating: item.user.rating, tag: item.user.tag)
            applyCardColor(item.user.cardColor, to: item.user.id)
        }
        // 前两张的照片先下好再显示，后面的边刷边下
        for item in items.prefix(2) {
            await applyAvatar(item.user.avatar, to: item.user.id)
            await applyCardPhoto(item.user.cardPhoto, to: item.user.id)
        }
        let rest = Array(items.dropFirst(2))
        Task {
            for item in rest {
                await applyAvatar(item.user.avatar, to: item.user.id)
                await applyCardPhoto(item.user.cardPhoto, to: item.user.id)
            }
            emit(.friendsChanged)
        }
        return items.map { item in
            DayCandidate(ticketId: item.ticket, userId: item.user.id, mode: GameMode(server: item.mode), mixed: item.mixed,
                                startsAt: item.startsAt, endsAt: item.endsAt, recentNoShows: item.user.recentNoShows ?? 0,
                                venues: (item.venues ?? []).map { DayCandidate.Venue(id: $0.id, name: $0.name, km: $0.km) })
        }
    }

    private func demoDayCandidates(on day: Date, center: Coordinate, radiusKm: Double, now: Date = Date()) -> [DayCandidate] {
        let blocked = blockedIds()
        let courts = venues(near: center, radiusKm: radiusKm)
        let people = db.bots.keys.sorted().compactMap { id -> DayCandidate? in
            guard !blocked.contains(id), let user = db.users[id], let location = user.location, location.distanceKm(to: center) <= radiusKm,
                  let slot = availability(for: id, on: day).first(where: { $0.endTime > now.addingTimeInterval(3600) }) else { return nil }
            let near = courts.sorted { $0.location.distanceKm(to: location) < $1.location.distanceKm(to: location) }.prefix(2)
            guard !near.isEmpty else { return nil }
            return DayCandidate(ticketId: "demo-\(id)", userId: id, mode: user.preferredMode ?? .singles, mixed: false,
                                startsAt: max(slot.startTime, now), endsAt: slot.endTime, recentNoShows: 0,
                                venues: near.map { DayCandidate.Venue(id: $0.id, name: $0.name, km: $0.location.distanceKm(to: center)) })
        }
        return Array(people.prefix(12))
    }

    func skipCandidate(_ ticketId: String) async {
        try? await remote?.call("skip_candidate", ["p_ticket": ticketId])
    }

    /// 约 TA 打双打：服务器替我开一个公开的双打局（TA 的时间、这家球馆）并邀请 TA，附近的人可以加入补齐
    func inviteDoublesCandidate(_ ticketId: String, venueId: String, startsAt: Date) async throws {
        guard isRemote else { return }
        let _: String = try await requireRemote().rpc("invite_doubles", ["p_ticket": ticketId, "p_venue": venueId, "p_starts_at": Self.iso(startsAt)])
        await refreshRemoteActivity()
    }

    /// 约 TA 打单打：服务器给我们俩发提议（我这边已确认），TA 确认就成局
    func inviteCandidate(_ ticketId: String, venueId: String, startsAt: Date) async throws {
        guard isRemote else { return }
        try await requireRemote().call("invite_ticket", ["p_ticket": ticketId, "p_venue": venueId, "p_starts_at": Self.iso(startsAt)])
        await refreshRemoteActivity()
    }
}
