import XCTest
@testable import Badie

/// 正式后端客户端：请求格式、登录状态、换令牌、错误码，以及注册流程写进本地缓存（用假服务器，不联网）
@MainActor
final class SupabaseClientTests: XCTestCase {

    /// 按“方法 路径”依次回应；没配的请求回 404
    private final class FakeServer {
        var requests: [URLRequest] = []
        private var routes: [(key: String, status: Int, body: String)] = []

        func on(_ key: String, status: Int = 200, _ body: String) {
            routes.append((key, status, body))
        }

        func handle(_ request: URLRequest) -> (Data, URLResponse) {
            requests.append(request)
            let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
            var status = 404
            var body = #"{"message":"not_found"}"#
            if let index = routes.firstIndex(where: { $0.key == key }) {
                (status, body) = (routes[index].status, routes[index].body)
                routes.remove(at: index)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        func json(_ index: Int) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: requests[index].httpBody ?? Data())) as? [String: Any] ?? [:]
        }
    }

    private var server: FakeServer!
    private let userId = "6f1c2c3e-0000-4000-8000-000000000001"

    override func setUp() async throws {
        try await super.setUp()
        server = FakeServer()
    }

    private func client(session: RemoteSession? = nil) -> SupabaseClient {
        let server = server!
        return SupabaseClient(storage: SessionStorage(load: { session }, save: { _ in }),
                              transport: { request in server.handle(request) })
    }

    private func token(_ access: String, expiresIn: Int = 3600) -> String {
        #"{"access_token":"\#(access)","refresh_token":"r-\#(access)","expires_in":\#(expiresIn),"token_type":"bearer","user":{"id":"\#(userId)","email":"alex@example.com"}}"#
    }

    private func session(expiresIn seconds: TimeInterval) -> RemoteSession {
        RemoteSession(accessToken: "old", refreshToken: "r-old", expiresAt: Date().addingTimeInterval(seconds), userId: userId, email: "alex@example.com")
    }

    // MARK: Client

    func testParsesPostgresTimestamps() throws {
        let expected = try XCTUnwrap(RemoteJSON.parseDate("2026-10-18T02:00:00Z"))
        XCTAssertEqual(RemoteJSON.parseDate("2026-10-18T02:00:00+00:00"), expected)
        XCTAssertEqual(RemoteJSON.parseDate("2026-10-18T02:00:00+00"), expected)
        XCTAssertEqual(RemoteJSON.parseDate("2026-10-17T19:00:00-07:00"), expected)
        let fractional = try XCTUnwrap(RemoteJSON.parseDate("2026-10-18T02:00:00.123456+00:00"))
        XCTAssertEqual(fractional.timeIntervalSince(expected), 0.123, accuracy: 0.001)
        XCTAssertNil(RemoteJSON.parseDate("tomorrow"))
    }

    func testVerifySendsCodeAndKeepsSession() async throws {
        server.on("POST /auth/v1/verify", token("fresh"))
        let client = client()
        let session = try await client.verify(email: "alex@example.com", code: "123456")

        XCTAssertEqual(session.userId, userId)
        XCTAssertEqual(client.session?.accessToken, "fresh")
        let request = server.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), SupabaseConfig.publishableKey)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "登录前不带用户令牌")
        XCTAssertEqual(server.json(0)["type"] as? String, "email")
        XCTAssertEqual(server.json(0)["token"] as? String, "123456")
    }

    func testDatabaseErrorBecomesReadableMessage() async throws {
        server.on("POST /rest/v1/rpc/submit_ticket", status: 400, #"{"code":"22023","message":"too_soon","details":null,"hint":null}"#)
        let client = client(session: session(expiresIn: 3600))
        do {
            try await client.call("submit_ticket", ["p_mode": "doubles"])
            XCTFail("应该报错")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .server("too_soon"))
            XCTAssertNotEqual(error.errorDescription, RemoteError.server("unknown").errorDescription, "有专门的提示")
        }
        XCTAssertEqual(server.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer old")
    }

    func testExpiringTokenIsRefreshedFirst() async throws {
        server.on("POST /auth/v1/token", token("new"))
        server.on("POST /rest/v1/rpc/my_record", "{}")
        let client = client(session: session(expiresIn: 30))
        try await client.call("my_record")

        XCTAssertEqual(server.requests.map { $0.url?.path }, ["/auth/v1/token", "/rest/v1/rpc/my_record"])
        XCTAssertEqual(server.json(0)["refresh_token"] as? String, "r-old")
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(client.session?.accessToken, "new")
    }

    func testRevokedRefreshTokenSignsOut() async throws {
        server.on("POST /auth/v1/token", status: 400, #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#)
        let client = client(session: session(expiresIn: -10))
        var expired = false
        client.onSessionExpired = { expired = true }
        do {
            try await client.call("my_record")
            XCTFail("应该要求重新登录")
        } catch {
            XCTAssertEqual(error as? RemoteError, .notSignedIn)
        }
        XCTAssertNil(client.session)
        XCTAssertTrue(expired)
    }

    func testNetworkFailureIsReported() async throws {
        let client = SupabaseClient(storage: .memory, transport: { _ in throw URLError(.notConnectedToInternet) })
        do {
            try await client.sendCode(email: "alex@example.com")
            XCTFail("应该报网络错误")
        } catch {
            XCTAssertEqual(error as? RemoteError, .network)
        }
    }

    // MARK: Backend in remote mode

    func testSignUpCreatesProfileAndCachesIt() async throws {
        let backend = MockBackend(store: .inMemory, seedsWorld: false)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        backend.remote = client()
        let profile = #"{"id":"\#(userId)","nickname":"Alex","country_code":"US","rating":4.33,"self_rating":4.33,"assessed_at":"2026-10-17T23:17:25.123456+00:00","show_on_boards":true,"challenge_policy":"similar","locale":"\#(MockBackend.serverLocale)","created_at":"2026-10-17T23:17:25+00:00"}"#

        server.on("POST /auth/v1/verify", token("fresh"))
        server.on("GET /rest/v1/profiles", "[]")
        let outcome = try await backend.remoteVerify(email: " Alex@Example.com ", code: "123456")
        XCTAssertEqual(outcome, .needsProfile(phone: "alex@example.com"))
        XCTAssertEqual(server.json(0)["email"] as? String, "alex@example.com", "邮箱统一小写、去空格")
        XCTAssertNil(backend.currentUser)

        server.on("POST /rest/v1/profiles", status: 201, "")
        server.on("POST /rest/v1/rpc/save_assessment", profile)
        server.on("GET /rest/v1/profiles", "[\(profile)]")
        server.on("GET /rest/v1/favorite_venues", #"[{"venue_id":"v-us-ca-labc"}]"#)
        let assessment = SkillAssessmentSummary(level: 4, needsCalibration: false, isReturning: false, assessedAt: Date(), rating: 4.33)
        let user = try await backend.remoteRegister(nickname: " Alex ", gender: .unspecified, avatar: Avatar(symbol: "🏸", paletteIndex: 2),
                                                    assessment: assessment, answers: ["clear": 3])

        XCTAssertEqual(server.json(2)["nickname"] as? String, "Alex")
        XCTAssertEqual(server.json(2)["id"] as? String, userId)
        XCTAssertEqual(server.json(3)["p_rating"] as? Double ?? 0, 4.33, accuracy: 0.01)
        XCTAssertEqual(user.id, userId)
        XCTAssertEqual(backend.currentUser?.nickname, "Alex")
        XCTAssertEqual(backend.currentUser?.avatar.symbol, "🏸", "头像先存在本机")
        XCTAssertEqual(backend.currentUser?.privacy.challengePolicy, .similarLevel)
        XCTAssertEqual(backend.currentUser?.assessment?.tier, SkillTier(rating: 4.33))
        XCTAssertEqual(backend.favoriteCourtIds(), ["v-us-ca-labc"])
    }

    /// 已登录、资料已建好的正式后端
    private func signedInBackend() async throws -> MockBackend {
        let backend = MockBackend(store: .inMemory, seedsWorld: false)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        backend.remote = client(session: session(expiresIn: 3600))
        let profile = #"{"id":"\#(userId)","nickname":"Alex","country_code":"US","rating":4,"assessed_at":null,"show_on_boards":true,"challenge_policy":"everyone","locale":"\#(MockBackend.serverLocale)"}"#
        server.on("GET /rest/v1/profiles", "[\(profile)]")
        server.on("GET /rest/v1/favorite_venues", "[]")
        try await backend.refreshRemoteProfile()
        server.requests = []
        return backend
    }

    private let blake = "6f1c2c3e-0000-4000-8000-000000000002"

    private func players(blakeReviewed: Bool = false) -> String {
        #"[{"id":"\#(userId)","nickname":"Alex","rating":4,"team":1,"me":true,"checked_in":true,"reviewed":false},{"id":"\#(blake)","nickname":"Blake","rating":4.33,"team":2,"me":false,"checked_in":false,"reviewed":\#(blakeReviewed)}]"#
    }

    private let venue = #"{"id":"v-test-court","name":"Test Court","city":"Irvine","street":"1 Main St","tz":"America/Los_Angeles","lat":33.68,"lon":-117.8,"country":"US","pricing":{"perPerson":12}}"#

    func testMatchmakingAndGamesComeFromServer() async throws {
        let backend = try await signedInBackend()
        let start = "2026-10-20T02:00:00+00:00", end = "2026-10-20T04:00:00+00:00"
        let offer = #"{"id":"o1","starts_at":"\#(start)","ends_at":"\#(end)","respond_by":"2026-10-19T20:00:00+00:00","my_response":"accepted","venue":\#(venue),"accepted":2,"players":\#(players())}"#
        server.on("POST /rest/v1/rpc/my_matchmaking",
                  #"[{"id":"t1","mode":"singles","starts_at":"\#(start)","ends_at":"\#(end)","status":"offered","skill_tolerance":1,"auto_accept":false,"lock_at":"2026-10-20T00:00:00+00:00","game_id":null,"venues":[\#(venue)],"offer":\#(offer)}]"#)
        let iso = { (offset: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)) }
        server.on("POST /rest/v1/rpc/my_games",
                  #"[{"id":"g1","mode":"singles","starts_at":"\#(iso(-3 * 3600))","ends_at":"\#(iso(-3600))","status":"scheduled","venue":\#(venue),"my_team":1,"checked_in":true,"my_report":{"outcome":"team1"},"result":{"status":"verified","outcome":"team1"},"review_until":"\#(iso(47 * 3600))","players":\#(players())}]"#)
        await backend.refreshRemoteActivity()

        let ticket = try XCTUnwrap(backend.myTickets().first)
        XCTAssertEqual(ticket.status, .offered(offerId: "o1"))
        XCTAssertEqual(ticket.mode, .singles)
        XCTAssertEqual(ticket.courtIds, ["v-test-court"])
        let match = try XCTUnwrap(backend.offer(id: "o1"))
        XCTAssertEqual(match.teams, [[userId], [blake]])
        XCTAssertEqual(match.acceptedCount, 2, "两人都确认了")
        XCTAssertEqual(match.court.name, "Test Court", "本地球馆库里没有：用服务器给的信息")
        XCTAssertEqual(backend.user(id: blake)?.nickname, "Blake", "同局球友进缓存")

        let game = try XCTUnwrap(backend.game(id: "g1"))
        XCTAssertEqual(game.status, .completed, "我已经报过赛果")
        XCTAssertTrue(game.hasCheckedIn(userId))
        XCTAssertFalse(game.hasCheckedIn(blake))
        XCTAssertEqual(game.resultStatus(), .verified(winningTeam: 0))
        XCTAssertEqual(game.result?.didWin, true)
        let survey = try XCTUnwrap(backend.pendingSurveys().first)
        XCTAssertEqual(survey.opponentId, blake)
        XCTAssertEqual(survey.matchId, "g1")
    }

    func testActionsCallTheServer() async throws {
        let backend = try await signedInBackend()
        let refresh = {
            self.server.on("POST /rest/v1/rpc/my_matchmaking", "[]")
            self.server.on("POST /rest/v1/rpc/my_games", "[]")
        }
        let slot = TimeSlot(date: Date(), startTime: Date().addingTimeInterval(4 * 3600), endTime: Date().addingTimeInterval(6 * 3600))
        server.on("POST /rest/v1/rpc/submit_ticket", #""t-new""#)
        refresh()
        do {
            _ = try await backend.submitTicket(mode: .doubles, slot: slot, courtIds: ["v-a", "v-b"], skillTolerance: 2, radiusKm: 10,
                                               origin: Coordinate.fallbackCenter, autoAccept: true)
        } catch {
            // 刷新后列表是空的：找不到新请求属正常（这里只看请求格式）
        }
        let submit = server.json(0)
        XCTAssertEqual(submit["p_mode"] as? String, "doubles")
        XCTAssertEqual(submit["p_venue_ids"] as? [String], ["v-a", "v-b"])
        XCTAssertEqual(submit["p_skill_tolerance"] as? Int, 2)
        XCTAssertEqual(submit["p_auto_accept"] as? Bool, true)
        XCTAssertNotNil(RemoteJSON.parseDate(submit["p_starts_at"] as? String ?? ""))

        server.requests = []
        server.on("POST /rest/v1/rpc/respond_offer", "")
        refresh()
        try await backend.respond(toOffer: "o1", accept: false)
        XCTAssertEqual(server.json(0)["p_offer"] as? String, "o1")
        XCTAssertEqual(server.json(0)["p_accept"] as? Bool, false)

        server.requests = []
        server.on("POST /rest/v1/rpc/review_player", "")
        refresh()
        let pending = PendingSurvey(id: "g1|b", matchId: "g1", evaluatorId: userId, opponentId: blake, opponentNickname: "Blake",
                                    opponentLevel: 4, opponentAvatar: .default(for: blake), courtName: "Test Court", matchDate: Date(),
                                    expiresAt: Date().addingTimeInterval(3600), opponentRating: 4.33)
        try await backend.remoteSubmitSurvey(pending, skillRating: 4, attendance: .late, tags: [.fairPlay, .greatPartner],
                                             issues: [.unpaid], wantsRematch: true)
        let review = server.json(0)
        XCTAssertEqual(review["p_level"] as? String, "lower", "选的档位比对方显示的低")
        XCTAssertEqual(review["p_attendance"] as? String, "late")
        XCTAssertEqual(review["p_tags"] as? [String], ["fair_play", "great_partner"])
        XCTAssertEqual(review["p_issues"] as? [String], ["unpaid"])
        XCTAssertEqual(review["p_play_again"] as? Bool, true)
    }

    func testFriendsThreadsAndNotificationsComeFromServer() async throws {
        let backend = try await signedInBackend()
        let casey = "6f1c2c3e-0000-4000-8000-000000000003"
        server.on("POST /rest/v1/rpc/my_friends",
                  #"{"friends":[{"id":"\#(blake)","nickname":"Blake","rating":4.33}],"requests":[{"id":"\#(casey)","nickname":"Casey","rating":3,"created_at":"2026-10-17T10:00:00+00:00"}]}"#)
        server.on("POST /rest/v1/rpc/my_threads",
                  #"[{"kind":"dm","id":"\#(blake)","starts_at":null,"venue":null,"tz":null,"name":"Blake","access":"open","last":{"body":"See you","created_at":"2026-10-17T12:00:00+00:00","mine":false},"unread":2},{"kind":"game","id":"g1","starts_at":"2026-10-17T18:00:00+00:00","venue":"Test Court","tz":null,"name":null,"access":"open","last":{"body":"On my way","created_at":"2026-10-17T17:50:00+00:00","mine":true},"unread":0}]"#)
        server.on("GET /rest/v1/notifications",
                  #"[{"id":7,"kind":"friend_request","title":"Friend request","body":"Casey wants to be friends.","link":"/app/players/\#(casey)/","created_at":"2026-10-17T10:00:00+00:00","read_at":null},{"id":6,"kind":"review","title":"How was your game?","body":"…","link":"/app/games/g1/","created_at":"2026-10-17T09:00:00+00:00","read_at":"2026-10-17T09:30:00+00:00"}]"#)
        try await backend.refreshRemoteSocial()

        XCTAssertEqual(backend.friends().map(\.id), [blake])
        XCTAssertTrue(backend.isFriend(blake))
        XCTAssertEqual(backend.incomingRequests().map(\.fromUserId), [casey])
        XCTAssertEqual(backend.user(id: casey)?.nickname, "Casey")
        XCTAssertEqual(backend.messagePermission(with: blake), .allowed)
        XCTAssertEqual(backend.messagePermission(with: casey), .friendsOnly, "正式后端：私信只发给球友")

        let dm = MessageThread.id(for: userId, blake)
        XCTAssertEqual(backend.thread(id: dm)?.unreadCount(for: userId), 2)
        XCTAssertEqual(backend.thread(id: dm)?.lastMessage?.senderId, blake)
        XCTAssertEqual(backend.thread(id: "game-g1")?.lastMessage?.senderId, userId)
        XCTAssertEqual(backend.totalUnread(), 2)

        let inbox = backend.inbox()
        XCTAssertEqual(inbox.map(\.kind), [.friendRequest, .surveyDue])
        XCTAssertEqual(inbox.first?.relatedId, casey, "点开去对方资料")
        XCTAssertEqual(inbox.last?.relatedId, "g1")
        XCTAssertEqual(inbox.map(\.isRead), [false, true])

        // 接受申请：按对方的 ID 调用
        server.requests = []
        server.on("POST /rest/v1/rpc/respond_friend_request", "")
        server.on("POST /rest/v1/rpc/my_friends", #"{"friends":[],"requests":[]}"#)
        server.on("POST /rest/v1/rpc/my_threads", "[]")
        server.on("GET /rest/v1/notifications", "[]")
        let request = try XCTUnwrap(backend.incomingRequests().first)
        try await backend.respond(to: request.id, accept: true)
        XCTAssertEqual(server.json(0)["p_user"] as? String, casey)
        XCTAssertEqual(server.json(0)["p_accept"] as? Bool, true)
    }

    func testOpeningAndSendingInAThread() async throws {
        let backend = try await signedInBackend()
        let thread = #"{"access":"open","friend":true,"game":null,"group":null,"members":[{"id":"\#(userId)","nickname":"Alex","me":true},{"id":"\#(blake)","nickname":"Blake","me":false}],"messages":[{"id":1,"body":"Hi","created_at":"2026-10-17T12:00:00+00:00","sender":"\#(blake)","mine":false},{"id":2,"body":"Hello","created_at":"2026-10-17T12:01:00+00:00","sender":"\#(userId)","mine":true}]}"#
        server.on("POST /rest/v1/rpc/send_message", "")
        server.on("POST /rest/v1/rpc/open_thread", thread)
        let sent = try await backend.sendMessage("  Hello  ", to: blake)

        XCTAssertEqual(server.json(0)["p_kind"] as? String, "dm")
        XCTAssertEqual(server.json(0)["p_id"] as? String, blake)
        XCTAssertEqual(server.json(0)["p_body"] as? String, "Hello")
        XCTAssertEqual(sent.content, "Hello")
        let dm = MessageThread.id(for: userId, blake)
        XCTAssertEqual(backend.messages(threadId: dm).map(\.content), ["Hi", "Hello"])
        XCTAssertEqual(backend.messages(threadId: dm).first?.senderId, blake)

        server.requests = []
        server.on("POST /rest/v1/rpc/send_message", "")
        server.on("POST /rest/v1/rpc/open_thread", thread)
        _ = try await backend.sendGroupMessage("Court 3", threadId: "game-g1")
        XCTAssertEqual(server.json(0)["p_kind"] as? String, "game")
        XCTAssertEqual(server.json(0)["p_id"] as? String, "g1")
    }

    func testRestoreWithoutSessionSignsOutLocally() async {
        let backend = MockBackend(store: .inMemory, seedsWorld: false)
        backend.createAccount(phone: "+16265550123", nickname: "Old", level: 3, seedsDemoContent: false)
        backend.remote = client()
        await backend.restoreRemoteSession()
        XCTAssertNil(backend.currentUser, "钥匙串里没有登录状态：回到登录页")
    }
}
