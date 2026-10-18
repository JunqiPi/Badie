import Foundation

// MARK: - 正式后端：同馆常客与球群消息请求
/// 常客由服务器按共同收藏的球馆算，只含本人开启了的；“人常去”是收藏人数。
/// 消息请求：同球群可以发一条，对方接受或回复后才能继续聊（规则在服务器上，见 messagePermission）
extension MockBackend {

    /// 资料页上服务器给的“能不能私信”：friends / open / requested / request / new_account / none
    struct RemoteMessageOption: Decodable, Hashable {
        let status: String
        let group: String?
    }

    private struct RemoteRegular: Decodable {
        struct Venue: Decodable {
            let id: String
        }

        let id: String
        let nickname: String
        let rating: Double
        let venue: Venue
    }

    private struct RegularCount: Decodable {
        let regulars: Int
    }

    // MARK: 同馆常客

    /// 拉取同馆常客写进缓存（5 分钟内只拉一次）；venueRegulars 读缓存
    func refreshRemoteRegulars(force: Bool = false) async throws {
        guard let remote else { return }
        if !force, let last = remoteRegularsLoadedAt, Date().timeIntervalSince(last) < 300 { return }
        remoteRegularsLoadedAt = Date()
        let rows: [RemoteRegular] = try await remote.rpc("venue_regulars")
        remoteRegulars = rows.compactMap { row in
            cacheRemoteUser(id: row.id, nickname: row.nickname, rating: row.rating)
            guard let user = db.users[row.id], let venue = venue(id: row.venue.id) else { return nil }
            return VenueRegular(user: user, venue: venue)
        }
        emit(.friendsChanged)
    }

    /// 这家球馆有多少人设为常去（只是人数，不暴露是谁）
    func remoteRegularsCount(for venueId: String) async -> Int? {
        guard let remote,
              let rows: [RegularCount] = try? await remote.select("venue_regular_counts", query: "venue_id=eq.\(venueId)&select=regulars")
        else { return nil }
        return rows.first?.regulars ?? 0
    }

    // MARK: 消息请求

    /// 正式后端的私信规则：请求状态看会话列表，能不能发请求看资料页（服务器给的）
    func remoteMessagePermission(with userId: String, me: String, now: Date) -> MessagePermission {
        if let thread = db.threads[MessageThread.id(for: me, userId)], thread.isPendingRequest {
            return thread.requestFrom == me ? .pendingRequest : .allowed
        }
        if let game = sharedOpenGame(with: userId, now: now) { return .gameChat(gameId: game.id) }
        guard let option = remoteMessageOptions[userId] else { return .friendsOnly }
        switch option.status {
        case "friends", "open": return .allowed
        case "requested": return .pendingRequest
        case "request": return .request(groupName: option.group ?? "")
        case "new_account": return .newAccount
        default: return .friendsOnly
        }
    }

    /// 私信会话在服务器上存在或者可以开始（球友、请求、可以发请求）时才去拉
    func canOpenRemoteThread(_ threadId: String) -> Bool {
        guard db.threads[threadId] == nil, let target = serverThread(threadId), target.kind == "dm" else { return true }
        switch messagePermission(with: target.id) {
        case .allowed, .request, .pendingRequest: return true
        case .gameChat, .friendsOnly, .newAccount, .blocked: return false
        }
    }

    /// 接受或忽略收到的请求；忽略只是不再显示，对方仍看到“等待接受”
    func remoteRespondMessageRequest(from userId: String, accept: Bool) {
        runRemote {
            try await $0.call("respond_message_request", ["p_user": userId, "p_accept": accept])
        }
        if accept {
            remoteMessageOptions[userId] = RemoteMessageOption(status: "open", group: nil)
        }
    }
}
