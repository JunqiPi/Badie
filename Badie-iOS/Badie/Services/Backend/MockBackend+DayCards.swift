import Foundation

// MARK: - 首页按天看能约的人
/// 只有正式后端有：演示模式没有真人在找，返回空
extension MockBackend {

    struct DayCandidate: Identifiable, Equatable {
        struct Venue: Equatable {
            let id: String
            let name: String
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
        }

        struct Place: Decodable {
            let id: String
            let name: String
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
        guard let remote else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let items: [RemoteCandidate] = try await remote.rpc("day_candidates", [
            "p_from": Self.iso(start), "p_to": Self.iso(end),
            "p_lat": center.latitude, "p_lon": center.longitude, "p_radius_km": radiusKm,
        ])
        return items.map { item in
            // 存进缓存：卡片上的头像、资料页都从这里读
            cacheRemoteUser(id: item.user.id, nickname: item.user.nickname, rating: item.user.rating, tag: item.user.tag)
            return DayCandidate(ticketId: item.ticket, userId: item.user.id, mode: GameMode(server: item.mode), mixed: item.mixed,
                                startsAt: item.startsAt, endsAt: item.endsAt, recentNoShows: item.user.recentNoShows ?? 0,
                                venues: (item.venues ?? []).map { DayCandidate.Venue(id: $0.id, name: $0.name) })
        }
    }

    func skipCandidate(_ ticketId: String) async {
        try? await remote?.call("skip_candidate", ["p_ticket": ticketId])
    }

    /// 约 TA 打单打：服务器给我们俩发提议（我这边已确认），TA 确认就成局
    func inviteCandidate(_ ticketId: String, venueId: String, startsAt: Date) async throws {
        try await requireRemote().call("invite_ticket", ["p_ticket": ticketId, "p_venue": venueId, "p_starts_at": Self.iso(startsAt)])
        await refreshRemoteActivity()
    }
}
