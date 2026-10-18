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

        /// 路径里有随机部分时按前缀匹配
        func onPrefix(_ prefix: String, status: Int = 200, _ body: String) {
            routes.append((prefix + "*", status, body))
        }

        func handle(_ request: URLRequest) -> (Data, URLResponse) {
            requests.append(request)
            let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
            var status = 404
            var body = #"{"message":"not_found"}"#
            if let index = routes.firstIndex(where: { $0.key == key || ($0.key.hasSuffix("*") && key.hasPrefix(String($0.key.dropLast()))) }) {
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

    func testCaptchaTokenGoesWithTheCodeRequest() async throws {
        server.on("POST /auth/v1/otp", "{}")
        server.on("POST /auth/v1/otp", "{}")
        server.on("POST /auth/v1/otp", status: 400, #"{"code":400,"error_code":"captcha_failed","msg":"captcha protection: request disallowed"}"#)
        let client = client()
        try await client.sendCode(email: "alex@example.com", captchaToken: "turnstile-token")
        try await client.sendCode(email: "alex@example.com", captchaToken: "")

        let security = server.json(0)["gotrue_meta_security"] as? [String: Any]
        XCTAssertEqual(security?["captcha_token"] as? String, "turnstile-token")
        XCTAssertNil(server.json(1)["gotrue_meta_security"], "网站没开启人机验证时不带")
        do {
            try await client.sendCode(email: "alex@example.com", captchaToken: nil)
            XCTFail("应该报错")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, RemoteError.server("captcha_failed").errorDescription)
        }
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
        // 当作已登录（不是刚登录），免得登录后的后台刷新混进后面的请求
        backend.db.currentUserId = userId
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

    func testScoresAndCourtFeesSyncWithServer() async throws {
        let backend = try await signedInBackend()
        let iso = { (offset: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)) }
        let paidPlayers = players().replacingOccurrences(of: #""reviewed":false}]"#, with: #""reviewed":false,"paid":true}]"#)
        let games = #"[{"id":"g1","mode":"singles","starts_at":"\#(iso(-3 * 3600))","ends_at":"\#(iso(-3600))","status":"scheduled","venue":\#(venue),"host_id":"\#(userId)","my_team":1,"checked_in":true,"my_report":{"outcome":"team1","score":"21:15 21:18"},"result":{"status":"awaiting","outcome":null},"score":"21:15 21:18","review_until":"\#(iso(47 * 3600))","players":\#(paidPlayers)}]"#
        server.on("POST /rest/v1/rpc/my_matchmaking", "[]")
        server.on("POST /rest/v1/rpc/my_games", games)
        await backend.refreshRemoteActivity()

        let game = try XCTUnwrap(backend.game(id: "g1"))
        XCTAssertEqual(game.hostId, userId, "房间开的局：服务器给的发起人")
        XCTAssertTrue(game.hasPaid(blake))
        XCTAssertFalse(game.hasPaid(userId))
        XCTAssertEqual(game.report(by: userId)?.score, "21:15 21:18")
        XCTAssertEqual(game.result?.score, "21:15 21:18")

        // 发起人替别人标记：本地马上变，再同步到服务器
        server.requests = []
        server.on("POST /rest/v1/rpc/mark_paid", "")
        backend.togglePaid(gameId: "g1", userId: blake)
        XCTAssertFalse(backend.game(id: "g1")?.hasPaid(blake) ?? true)
        await waitFor { !self.server.requests.isEmpty }
        let mark = server.json(0)
        XCTAssertEqual(mark["p_user"] as? String, blake)
        XCTAssertEqual(mark["p_paid"] as? Bool, false)

        server.requests = []
        server.on("POST /rest/v1/rpc/report_result", #""awaiting""#)
        try await backend.reportResult(gameId: "g1", didWin: false, score: "18:21")
        XCTAssertEqual(server.json(0)["p_outcome"] as? String, "team2")
        XCTAssertEqual(server.json(0)["p_score"] as? String, "18:21")

        XCTAssertTrue(GameResult.isValidScore(""))
        XCTAssertTrue(GameResult.isValidScore("21:18, 19-21 / 21:15"))
        XCTAssertFalse(GameResult.isValidScore("我们赢了"))
        XCTAssertFalse(GameResult.isValidScore(String(repeating: "1", count: 41)))
    }

    func testLastMinuteRequestsComeFromServer() async throws {
        let backend = try await signedInBackend()
        let iso = { (offset: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)) }
        let offer = #"{"id":"o2","starts_at":"\#(iso(3600))","ends_at":"\#(iso(3 * 3600))","respond_by":"\#(iso(600))","my_response":"pending","lock_at":"\#(iso(2400))","venue":\#(venue),"accepted":1,"players":\#(players())}"#
        server.on("POST /rest/v1/rpc/my_matchmaking",
                  #"[{"id":"t2","mode":"singles","starts_at":"\#(iso(3600))","ends_at":"\#(iso(3 * 3600))","status":"offered","skill_tolerance":1,"auto_accept":false,"lock_at":"\#(iso(2400))","last_minute":true,"game_id":null,"venues":[\#(venue)],"offer":\#(offer)}]"#)
        server.on("POST /rest/v1/rpc/my_games", "[]")
        await backend.refreshRemoteActivity()

        let ticket = try XCTUnwrap(backend.myTickets().first)
        XCTAssertTrue(ticket.isLastMinute, "服务器标的临时局")
        let match = try XCTUnwrap(backend.offer(id: "o2"))
        XCTAssertTrue(match.isLastMinute)
        XCTAssertEqual(match.lockAt.timeIntervalSinceNow, 2400, accuracy: 2, "锁定时间用服务器给的（开赛前 20 分钟）")
    }

    func testPoolCountsComeFromServer() async throws {
        let backend = try await signedInBackend()
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(2 * 86400))
        server.on("POST /rest/v1/rpc/pool_by_day", #"{"\#(MockBackend.dayKey(day))":4}"#)
        XCTAssertEqual(backend.availableCount(on: day, radiusKm: 15), 0, "先返回缓存，后台去拉")
        await waitFor { backend.availableCount(on: day, radiusKm: 15) == 4 }
        XCTAssertEqual(backend.availableCount(on: day, radiusKm: 15), 4)
        XCTAssertEqual(server.json(0)["p_radius_km"] as? Double, 15)
        XCTAssertEqual(server.json(0)["p_tz"] as? String, TimeZone.current.identifier)

        server.on("POST /rest/v1/rpc/ticket_pool", #"{"available":3,"compatible":1}"#)
        _ = backend.poolSummary(for: "t1")
        await waitFor { backend.poolSummary(for: "t1").available == 3 }
        XCTAssertEqual(backend.poolSummary(for: "t1").compatible, 1)
        XCTAssertEqual(server.requests.count, 2, "1 分钟内不重复拉")
    }

    func testPlayerSearchGoesToServer() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/find_players",
                  #"[{"id":"\#(blake)","nickname":"Blake","rating":4.33,"mutual_friends":1,"relationship":"requested"}]"#)
        let found = try await backend.remoteFindPlayers("bla")
        XCTAssertEqual(found.map(\.nickname), ["Blake"])
        XCTAssertEqual(server.json(0)["p_query"] as? String, "bla")
        XCTAssertTrue(backend.hasPendingRequest(to: blake), "在别处申请过的也显示等待通过")

        server.on("POST /rest/v1/rpc/find_players", status: 400, #"{"code":"54000","details":null,"hint":null,"message":"too_many_searches"}"#)
        do {
            _ = try await backend.remoteFindPlayers("bla")
            XCTFail("限速要报错")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, RemoteError.server("too_many_searches").errorDescription)
        }
    }

    func testOldPrivacySettingsStillDecode() throws {
        let old = #"{"showsAsRegular":true,"allowsMessageRequests":false,"challengePolicy":"friends","showsOnLeaderboards":false}"#
        let privacy = try JSONDecoder().decode(PrivacySettings.self, from: Data(old.utf8))
        XCTAssertTrue(privacy.showsAsRegular)
        XCTAssertFalse(privacy.showsOnLeaderboards)
        XCTAssertTrue(privacy.findableByNickname, "旧数据里没有的开关用默认值")
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

    func testMessageRequestsFollowTheServer() async throws {
        let backend = try await signedInBackend()
        let casey = "6f1c2c3e-0000-4000-8000-000000000003"
        // Casey 发来的请求在会话列表里；Blake 的资料页说可以发一条请求
        server.on("POST /rest/v1/rpc/my_friends", #"{"friends":[],"requests":[]}"#)
        server.on("POST /rest/v1/rpc/my_threads",
                  #"[{"kind":"dm","id":"\#(casey)","starts_at":null,"venue":null,"tz":null,"name":"Casey","access":"open","request":"incoming","last":{"body":"Hi from the club","created_at":"2026-10-17T12:00:00+00:00","mine":false},"unread":1}]"#)
        server.on("GET /rest/v1/notifications",
                  #"[{"id":9,"kind":"message_request","title":"Casey wants to chat","body":"…","link":"/app/messages/dm/\#(casey)/","created_at":"2026-10-17T12:00:00+00:00","read_at":null}]"#)
        try await backend.refreshRemoteSocial()
        XCTAssertEqual(backend.incomingMessageRequests().map(\.id), [MessageThread.id(for: userId, casey)])
        XCTAssertEqual(backend.messagePermission(with: casey), .allowed, "回复就算接受")
        XCTAssertEqual(backend.inbox().first?.kind, .messageRequest)
        XCTAssertEqual(backend.inbox().first?.relatedId, casey, "点开去和 TA 的会话")

        server.on("POST /rest/v1/rpc/player_card",
                  #"{"id":"\#(blake)","nickname":"Blake","rating":4.33,"tags":[],"win_rate":null,"challenge":"hidden","message":{"status":"request","group":"Sunday Club"}}"#)
        await backend.refreshRemotePlayer(blake)
        XCTAssertEqual(backend.messagePermission(with: blake), .request(groupName: "Sunday Club"))

        // 接受：先改本地，再告诉服务器
        server.requests = []
        server.on("POST /rest/v1/rpc/respond_message_request", "")
        backend.acceptMessageRequest(threadId: MessageThread.id(for: userId, casey))
        XCTAssertTrue(backend.incomingMessageRequests().isEmpty)
        await waitFor { !self.server.requests.isEmpty }
        XCTAssertEqual(server.json(0)["p_user"] as? String, casey)
        XCTAssertEqual(server.json(0)["p_accept"] as? Bool, true)
    }

    func testRegularsAndPrivacyComeFromServer() async throws {
        let backend = try await signedInBackend()
        XCTAssertFalse(backend.currentUser?.privacy.showsAsRegular ?? true, "常客默认不显示")
        XCTAssertTrue(backend.currentUser?.privacy.allowsMessageRequests ?? false)

        server.on("POST /rest/v1/rpc/venues_near", #"[{"venue":\#(venueJSON()),"distance_m":1200}]"#)
        backend.refreshRemoteVenues(near: Coordinate(latitude: 34.14, longitude: -118.13), radiusKm: 25)
        await waitFor { backend.venue(id: "v-1a2b3c4d") != nil }
        server.on("POST /rest/v1/rpc/venue_regulars",
                  #"[{"id":"\#(blake)","nickname":"Blake","rating":4.33,"venue":{"id":"v-1a2b3c4d","name":"Pasadena Badminton"}}]"#)
        try await backend.refreshRemoteRegulars(force: true)
        XCTAssertEqual(backend.venueRegulars().map(\.user.nickname), ["Blake"])
        XCTAssertEqual(backend.venueRegulars().first?.venue.id, "v-1a2b3c4d")

        server.on("GET /rest/v1/venue_regular_counts", #"[{"regulars":7}]"#)
        let count = await backend.fetchRegularsCount(for: "v-1a2b3c4d")
        XCTAssertEqual(count, 7)

        server.requests = []
        server.on("PATCH /rest/v1/profiles", "")
        var privacy = try XCTUnwrap(backend.currentUser?.privacy)
        privacy.showsAsRegular = true
        privacy.allowsMessageRequests = false
        backend.updatePrivacy(privacy)
        await waitFor { !self.server.requests.isEmpty }
        XCTAssertEqual(server.json(0)["show_as_regular"] as? Bool, true)
        XCTAssertEqual(server.json(0)["allow_message_requests"] as? Bool, false)
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

    private func groupPage(myStatus: String) -> String {
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86400))
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86400 + 7200))
        return #"{"id":"grp1","name":"Thu doubles","summary":"Friendly","level_min":3,"level_max":5,"join_policy":"approval","venue":{"id":"v-test-court","name":"Test Court","city":"Irvine","tz":"America/Los_Angeles"},"schedules":[{"weekday":4,"start":1170,"end":1320,"capacity":8,"fee":"$12"}],"activity":{"sessions":6,"average":7.5},"my_role":"owner","invite_code":"ABC2LX","sessions":[{"id":"s1","starts_at":"\#(start)","ends_at":"\#(end)","capacity":8,"cancelled":false,"confirmed":1,"waitlist":0,"my_status":"\#(myStatus)","players":[{"id":"\#(userId)","nickname":"Alex","waitlisted":false}]}],"members":[{"id":"\#(userId)","nickname":"Alex","rating":4,"role":"owner"},{"id":"\#(blake)","nickname":"Blake","rating":4.33,"role":"member"}],"pending":[{"id":"6f1c2c3e-0000-4000-8000-000000000003","nickname":"Casey","rating":3,"role":null}]}"#
    }

    func testGroupsComeFromServer() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/group_page", groupPage(myStatus: "confirmed"))
        try await backend.loadRemoteGroup("grp1")

        let group = try XCTUnwrap(backend.group(id: "grp1"))
        XCTAssertEqual(group.ownerId, userId)
        XCTAssertEqual(Set(group.memberIds), [userId, blake])
        XCTAssertTrue(group.isOrganizer(userId))
        XCTAssertEqual(group.pendingIds, ["6f1c2c3e-0000-4000-8000-000000000003"])
        XCTAssertEqual(group.inviteCode, "ABC2LX")
        XCTAssertEqual(group.joinPolicy, .approval)
        XCTAssertEqual(group.levelRange, 3...5)
        XCTAssertEqual(group.schedules.first?.weekday, 5, "服务器 4 = 周四；本地 1 = 周日，所以周四是 5")
        XCTAssertEqual(group.schedules.first?.feeNote, "$12")
        XCTAssertEqual(backend.activity(of: "grp1").sessionsLast30Days, 6)
        XCTAssertEqual(backend.myGroups().map(\.id), ["grp1"])
        XCTAssertEqual(backend.mySessions().map(\.id), ["s1"])
        XCTAssertEqual(backend.session(id: "s1")?.status(of: userId), .signedUp)
        XCTAssertNotNil(backend.venue(id: "v-test-court"), "服务器上的球馆进本地库")
    }

    func testGroupActionsCallTheServer() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/group_page", groupPage(myStatus: "confirmed"))
        try await backend.loadRemoteGroup("grp1")

        server.requests = []
        server.on("POST /rest/v1/rpc/sign_up_session", #""waitlisted""#)
        server.on("POST /rest/v1/rpc/group_page", groupPage(myStatus: "waitlisted:2")
            .replacingOccurrences(of: #""waitlist":0"#, with: #""waitlist":2"#)
            .replacingOccurrences(of: #""players":[{"id":"\#(userId)","nickname":"Alex","waitlisted":false}]"#, with: #""players":null"#))
        let result = try await backend.remoteSignUp(sessionId: "s1")
        XCTAssertEqual(server.json(0)["p_session"] as? String, "s1")
        XCTAssertEqual(result, .waitlisted(position: 2), "看不到名单时按 my_status 放我的位置")

        server.requests = []
        server.on("POST /rest/v1/rpc/create_group", #""grp1""#)
        server.on("POST /rest/v1/rpc/group_page", groupPage(myStatus: "confirmed"))
        let schedule = GroupSchedule(id: "s", weekday: 5, startMinutes: 19 * 60 + 30, endMinutes: 22 * 60, capacity: 8, feeNote: nil)
        _ = try await backend.remoteCreateGroup(name: " Thu doubles ", venueId: "v-test-court", schedules: [schedule],
                                                levelRange: 3...5, joinPolicy: .approval, summary: "")
        let create = server.json(0)
        XCTAssertEqual(create["p_name"] as? String, "Thu doubles")
        XCTAssertEqual(create["p_policy"] as? String, "approval")
        let schedules = try XCTUnwrap(create["p_schedules"] as? [[String: Any]])
        XCTAssertEqual(schedules.first?["weekday"] as? Int, 4, "本地周四 5 → 服务器 4")
        XCTAssertEqual(schedules.first?["start"] as? Int, 1170)

        server.on("POST /rest/v1/rpc/find_group", "null")
        let missing = try await backend.remoteFindGroup(code: "ZZZZZZ")
        XCTAssertNil(missing)
    }

    /// 后台拉取的榜单：等它写进缓存
    private func waitFor(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: 球局（房间）

    private let roomId = "8d1c2c3e-0000-4000-8000-0000000000aa"

    /// room_page / my_rooms / rooms_near 的一条；members 为 nil 时是外人看到的样子
    private func roomJSON(status: String = "open", reason: String = "null", owner: String? = nil, myStatus: String = "owner",
                          code: String = #""ABC234""#, members: String? = nil, going: Int = 2, waitlist: Int = 0) -> String {
        let host = owner ?? userId
        let other = host == userId ? blake : userId
        let list = members ?? #"[{"id":"\#(host)","nickname":"Host","rating":4,"waitlisted":false,"me":\#(host == userId)},{"id":"\#(other)","nickname":"Other","rating":4.33,"waitlisted":false,"me":\#(other == userId)}]"#
        return #"{"id":"\#(roomId)","mode":"doubles","visibility":"public","status":"\#(status)","closed_reason":\#(reason),"game_id":null,"starts_at":"2026-10-25T02:00:00+00:00","ends_at":"2026-10-25T04:00:00+00:00","level_min":3,"level_max":5,"tags":["casual","not_a_tag"],"note":"Court 3","capacity":4,"going":\#(going),"waitlist":\#(waitlist),"last_activity_at":"2026-10-18T02:00:00+00:00","owner":{"id":"\#(host)","nickname":"Host","rating":4},"venue":\#(venue),"my_status":\#(myStatus == "null" ? "null" : "\"\(myStatus)\""),"code":\#(code),"members":\#(list)}"#
    }

    func testMyRoomsComeFromServer() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/my_rooms", "[\(roomJSON(owner: blake, myStatus: "member"))]")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(owner: blake, myStatus: "member"))
        try await backend.refreshRemoteRooms()

        let room = try XCTUnwrap(backend.myOpenRooms().first)
        XCTAssertEqual(room.code, "ABC234")
        XCTAssertEqual(room.ownerId, blake)
        XCTAssertEqual(room.participants.map(\.userId), [blake, userId])
        XCTAssertEqual(room.visibility, .publicListing)
        XCTAssertEqual(room.levelRange, 3...5)
        XCTAssertEqual(room.tags, [.casual], "不认识的标签跳过")
        XCTAssertEqual(room.court?.name, "Test Court")
        XCTAssertEqual(room.slot?.startTime, ISO8601DateFormatter().date(from: "2026-10-25T02:00:00Z"))

        // 房主解散后不在“我的房间”里了：再拉一次，提示房间已关闭
        var notices: [String] = []
        backend.subscribe { event in
            if case .roomClosed(let code, let reason) = event { notices.append("\(code) \(reason)") }
        }
        server.on("POST /rest/v1/rpc/my_rooms", "[]")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(status: "closed", reason: #""owner_closed""#, owner: blake, myStatus: "member"))
        try await backend.refreshRemoteRooms()
        XCTAssertEqual(backend.room(id: roomId)?.status, .closed(.ownerClosed))
        XCTAssertTrue(backend.myOpenRooms().isEmpty)
        XCTAssertEqual(notices, ["ABC234 ownerClosed"])
    }

    func testNearbyRoomsHideWhoIsPlaying() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/rooms_near", "[\(roomJSON(owner: blake, myStatus: "null", code: "null", members: "null", going: 3, waitlist: 1))]")
        XCTAssertTrue(backend.publicRooms(radiusKm: 30).isEmpty, "先返回缓存（空），后台去拉")
        await waitFor { !backend.publicRooms(radiusKm: 30).isEmpty }

        let room = try XCTUnwrap(backend.publicRooms(radiusKm: 30).first)
        XCTAssertEqual(room.code, "", "外人拿不到房间码")
        XCTAssertEqual(room.participants.count, 3)
        XCTAssertEqual(room.participants.first?.userId, blake, "房主是谁看得到")
        XCTAssertEqual(room.participants.filter(\.isAnonymous).count, 2, "其他人只占位")
        XCTAssertEqual(room.waitlist.count, 1)
        XCTAssertEqual(server.requests.count, 1, "60 秒内同一位置不重复拉")
    }

    func testRoomActionsCallTheServer() async throws {
        let backend = try await signedInBackend()
        var draft = RoomDraft()
        draft.visibility = .privateRoom
        draft.tags = [.casual, .coaching]
        draft.levelRange = 2...6
        draft.note = "  Court 3 "
        server.on("POST /rest/v1/rpc/create_room", #""\#(roomId)""#)
        server.on("POST /rest/v1/rpc/room_page", roomJSON())
        let created = try await backend.remoteCreateRoom(draft)
        XCTAssertEqual(created.id, roomId)
        let body = server.json(0)
        XCTAssertEqual(body["p_visibility"] as? String, "private")
        XCTAssertEqual(body["p_tags"] as? [String], ["casual", "coaching"])
        XCTAssertEqual(body["p_level_min"] as? Int, 2)
        XCTAssertEqual(body["p_note"] as? String, "Court 3")
        XCTAssertTrue(body["p_venue"] is NSNull, "私密局可以先不定球馆")
        XCTAssertTrue(body["p_starts_at"] is NSNull)

        server.requests = []
        server.on("POST /rest/v1/rpc/join_room_code", status: 400, #"{"code":"P0002","details":null,"hint":null,"message":"room_not_found"}"#)
        do {
            _ = try await backend.remoteJoinRoom(code: "ZZZZZZ")
            XCTFail("找不到房间要报错")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, BackendError.roomNotFound.localizedDescription)
        }

        // 自己退出不算“被移出”
        var kicked = false
        backend.subscribe { event in if case .kicked = event { kicked = true } }
        server.on("POST /rest/v1/rpc/leave_room", "null")
        server.on("POST /rest/v1/rpc/room_page", roomJSON(owner: blake, myStatus: "null", code: "null", members: "null", going: 1))
        backend.db.rooms[roomId]?.ownerId = blake
        try await backend.remoteLeaveRoom(id: roomId)
        XCTAssertFalse(kicked)
        XCTAssertFalse(backend.room(id: roomId)?.contains(userId) ?? true)
    }

    func testRankingsComeFromServer() async throws {
        let backend = try await signedInBackend()
        let week = Rankings.week(containing: Date())
        let weekly = #"{"week_starts":"2026-10-12T00:00:00+00:00","entries":[{"id":"\#(blake)","nickname":"Blake","rating":4.33,"rank":1,"points":45,"games":3,"wins":2,"me":false}],"me":null,"progress":{"games":1,"opponents":1,"points":10},"eligible":true}"#
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        XCTAssertTrue(backend.weeklyLeaderboard(week: week).isEmpty, "先返回缓存（空），后台去拉")
        await waitFor { !backend.weeklyLeaderboard(week: week).isEmpty }
        let entry = try XCTUnwrap(backend.weeklyLeaderboard(week: week).first)
        XCTAssertEqual(entry.userId, blake)
        XCTAssertEqual(entry.score, 45)
        XCTAssertEqual(server.json(0)["p_scope"] as? String, "global")
        let score = backend.weeklyScore(for: userId, week: week)
        XCTAssertEqual(score.points, 10)
        XCTAssertEqual(score.games, 1)
        XCTAssertEqual(server.json(0)["p_offset"] as? Int, 0)

        // 上周单独拉一份（p_offset = 1）；更早的服务器不提供
        server.requests = []
        server.on("POST /rest/v1/rpc/weekly_board", weekly)
        let lastWeek = Rankings.week(containing: week.start.addingTimeInterval(-1))
        _ = backend.weeklyLeaderboard(week: lastWeek)
        await waitFor { !backend.weeklyLeaderboard(week: lastWeek).isEmpty }
        XCTAssertEqual(server.json(0)["p_offset"] as? Int, 1)
        let older = Rankings.week(containing: lastWeek.start.addingTimeInterval(-1))
        XCTAssertTrue(backend.weeklyLeaderboard(week: older).isEmpty, "服务器只有本周和上周")

        let venueBoard = #"{"venue":{"id":"v1","name":"Court","city":"Irvine"},"bands":[{"band":2,"entries":[{"id":"\#(blake)","nickname":"Blake","rating":4.33,"rank":1,"games":5,"wins":3,"me":false}]}]}"#
        server.on("POST /rest/v1/rpc/venue_board", venueBoard)
        let month = Rankings.month(containing: Date())
        _ = backend.venueLeaderboard(venueId: "v1", month: month)
        await waitFor { !backend.venueLeaderboard(venueId: "v1", month: month).isEmpty }
        let band = try XCTUnwrap(backend.venueLeaderboard(venueId: "v1", month: month).first)
        XCTAssertEqual(band.bracket, .intermediate)
        XCTAssertEqual(band.entries.first?.score, 5, "场馆榜按场次")
        let lastMonth = Rankings.month(containing: month.start.addingTimeInterval(-1))
        server.requests = []
        server.on("POST /rest/v1/rpc/venue_board", venueBoard)
        _ = backend.venueLeaderboard(venueId: "v1", month: lastMonth)
        await waitFor { !backend.venueLeaderboard(venueId: "v1", month: lastMonth).isEmpty }
        XCTAssertEqual(server.json(0)["p_offset"] as? Int, 1, "上月")

        server.on("POST /rest/v1/rpc/my_record", #"{"games":6,"wins":4,"opponents":3,"gap":0.5,"public":true,"losses":2,"games_played":7,"no_shows":0,"late_cancels":0}"#)
        _ = backend.winRate(for: userId, month: month)
        await waitFor { backend.winRate(for: self.userId, month: month).games > 0 }
        XCTAssertEqual(backend.winRate(for: userId, month: month).percentage, 67)
    }

    func testChallengesComeFromServer() async throws {
        let backend = try await signedInBackend()
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 + 3600))
        let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(40 * 3600))
        server.on("POST /rest/v1/rpc/my_challenges",
                  #"{"incoming":[{"id":"c1","starts_at":"\#(start)","ends_at":"\#(end)","message":"Best of three?","expires_at":"\#(expires)","venue":{"name":"Court","tz":null},"player":{"id":"\#(blake)","nickname":"Blake","rating":4.33}}],"outgoing":[{"id":"c2","starts_at":"\#(start)","ends_at":"\#(end)","game_id":null,"status":"not_happening","venue":{"name":"Court","tz":null},"player":{"id":"\#(blake)","nickname":"Blake","rating":4.33}}]}"#)
        try await backend.refreshRemoteChallenges()
        let incoming = try XCTUnwrap(backend.challenges().first { $0.id == "c1" })
        XCTAssertEqual(incoming.challengerId, blake)
        XCTAssertEqual(incoming.targetId, userId)
        XCTAssertEqual(incoming.status, .pending)
        XCTAssertEqual(incoming.message, "Best of three?")
        XCTAssertEqual(backend.challenges().first { $0.id == "c2" }?.status, .expired, "没成行")

        server.on("POST /rest/v1/rpc/player_card",
                  #"{"id":"\#(blake)","nickname":"Blake","rating":4.33,"tags":["friendly","fair_play"],"win_rate":{"games":5,"wins":4,"opponents":3,"gap":0,"public":true},"challenge":"friends_only"}"#)
        _ = await backend.refreshRemotePlayer(blake)
        XCTAssertEqual(backend.challengeAvailability(for: blake), .friendsOnly)
        XCTAssertEqual(backend.winRate(for: blake, month: Rankings.month(containing: Date())).wins, 4)
        XCTAssertEqual(backend.user(id: blake)?.reputation.publicTags, [.friendly, .fairPlay])

        server.requests = []
        server.on("POST /rest/v1/rpc/send_challenge", #""c3""#)
        server.on("POST /rest/v1/rpc/my_challenges", #"{"incoming":[],"outgoing":[]}"#)
        let court = BadmintonCourt(id: "v1", name: "Court", location: Coordinate(latitude: 0, longitude: 0),
                                   address: PostalAddress(street: "", city: "", region: "", countryCode: "US"))
        let slot = TimeSlot(date: Date(), startTime: Date().addingTimeInterval(86400), endTime: Date().addingTimeInterval(90000))
        _ = try? await backend.sendChallenge(to: blake, court: court, slot: slot, message: " Rematch? ")
        XCTAssertEqual(server.json(0)["p_target"] as? String, blake)
        XCTAssertEqual(server.json(0)["p_venue"] as? String, "v1")
        XCTAssertEqual(server.json(0)["p_message"] as? String, "Rematch?")
        XCTAssertTrue(server.json(0)["p_partner"] is NSNull, "单打不带搭档")

        // 双打：发起时带搭档，接受时选自己的搭档
        let casey = "6f1c2c3e-0000-4000-8000-000000000003"
        server.requests = []
        server.on("POST /rest/v1/rpc/send_challenge", #""c4""#)
        server.on("POST /rest/v1/rpc/my_challenges",
                  #"{"incoming":[{"id":"c5","starts_at":"\#(start)","ends_at":"\#(end)","message":"","expires_at":"\#(expires)","mode":"doubles","venue":{"name":"Court","tz":null},"player":{"id":"\#(blake)","nickname":"Blake","rating":4.33},"partner":{"id":"\#(casey)","nickname":"Casey","rating":4}}],"outgoing":[]}"#)
        _ = try? await backend.sendChallenge(to: blake, court: court, slot: slot, message: "", partnerId: casey)
        XCTAssertEqual(server.json(0)["p_partner"] as? String, casey)
        let doubles = try XCTUnwrap(backend.challenges().first { $0.id == "c5" })
        XCTAssertEqual(doubles.mode, .doubles)
        XCTAssertEqual(doubles.challengerPartnerId, casey)
        XCTAssertEqual(backend.user(id: casey)?.nickname, "Casey")

        server.requests = []
        server.on("POST /rest/v1/rpc/respond_challenge", "null")
        _ = try? await backend.respondToChallenge(id: "c5", accept: true, partnerId: "dana")
        XCTAssertEqual(server.json(0)["p_partner"] as? String, "dana")
    }

    func testVerificationGoesThroughTheServer() async throws {
        let backend = try await signedInBackend()
        let created = "2026-10-17T10:00:00+00:00"
        server.on("POST /rest/v1/rpc/request_verification", #""v1""#)
        server.on("POST /rest/v1/rpc/my_verification",
                  #"{"id":"v1","kind":"tournament","claimed_rating":7,"evidence":"https://usab.tournamentsoftware.com/x","name_on_record":"Alex Chen","note":"","status":"pending","created_at":"\#(created)","reviewed_at":null,"review_note":null,"approved_rating":null}"#)
        let request = try await backend.sendVerificationRequest(kind: .tournament, tier: SkillTier(level: 7),
                                                                evidenceURL: " usab.tournamentsoftware.com/x ", nameOnRecord: "Alex Chen", note: "")
        let body = server.json(0)
        XCTAssertEqual(body["p_kind"] as? String, "tournament")
        XCTAssertEqual(body["p_rating"] as? Double ?? 0, 7, accuracy: 0.01)
        XCTAssertEqual(body["p_evidence"] as? String, "usab.tournamentsoftware.com/x")
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(backend.myVerificationRequest()?.kind, .tournament)

        // 审核通过后：资料里带着认证类型和档位
        let profile = #"{"id":"\#(userId)","nickname":"Alex","country_code":"US","rating":7,"assessed_at":null,"show_on_boards":true,"challenge_policy":"everyone","verified_kind":"tournament","verified_rating":7,"locale":"\#(MockBackend.serverLocale)"}"#
        server.on("GET /rest/v1/profiles", "[\(profile)]")
        server.on("GET /rest/v1/favorite_venues", "[]")
        server.on("POST /rest/v1/rpc/my_verification", "null")
        try await backend.refreshRemoteProfile()
        XCTAssertEqual(backend.currentUser?.verificationStatus, .tournament)
        XCTAssertEqual(backend.currentUser?.displayTier, SkillTier(level: 7), "认证后不受 7− 的上限限制")

        // 别人的资料页：认证过的人按服务器的档位显示
        server.on("POST /rest/v1/rpc/player_card",
                  #"{"id":"\#(blake)","nickname":"Blake","rating":8,"tags":[],"win_rate":null,"challenge":"hidden","verified":"national"}"#)
        await backend.refreshRemotePlayer(blake)
        XCTAssertEqual(backend.user(id: blake)?.verificationStatus, .national)
        XCTAssertEqual(backend.user(id: blake)?.displayTier, SkillTier(level: 8))
    }

    func testAvatarPhotosGoThroughStorage() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/set_avatar", "")
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let pathPattern = #"^/storage/v1/object/avatars/\#(userId)/[0-9a-f-]{36}\.jpg$"#
        // 上传：路径是 <我的 id>/<随机>.jpg，然后换上
        server.onPrefix("POST /storage/v1/object/avatars/\(userId)/", "{}")
        let user = try await backend.uploadAvatarPhoto(jpeg)
        let upload = try XCTUnwrap(server.requests.first)
        XCTAssertNotNil(upload.url?.path.range(of: pathPattern, options: .regularExpression))
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(upload.httpBody, jpeg)
        let path = String(upload.url!.path.dropFirst("/storage/v1/object/avatars/".count))
        XCTAssertEqual(server.json(1)["p_path"] as? String, path)
        XCTAssertNotNil(user.avatar.photoVersion)

        // 别人的照片：见到了就批量查地址，下载后显示
        server.requests = []
        server.on("POST /rest/v1/rpc/avatars", #"[{"id":"\#(blake)","path":"\#(blake)/0f0e0d0c-0000-4000-8000-000000000001.jpg"}]"#)
        server.on("GET /storage/v1/object/public/avatars/\(blake)/0f0e0d0c-0000-4000-8000-000000000001.jpg", "JPEG")
        backend.cacheRemoteUser(id: blake, nickname: "Blake", rating: 4)
        await waitFor { backend.user(id: self.blake)?.avatar.photoVersion != nil }
        XCTAssertEqual(server.json(0)["p_users"] as? [String], [blake])
        XCTAssertEqual(backend.db.avatarPhotos[blake], Data("JPEG".utf8))
        backend.cacheRemoteUser(id: blake, nickname: "Blake", rating: 4)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(server.requests.count, 2, "同一个人这次启动只查一次")
    }

    func testAdminFlagComesFromServer() async throws {
        let backend = try await signedInBackend()
        XCTAssertFalse(backend.remoteIsAdmin, "查不到（这里是 404）就当普通用户")

        server.on("GET /rest/v1/profiles", #"[{"id":"\#(userId)","nickname":"Alex","country_code":"US","rating":4,"assessed_at":null,"show_on_boards":true,"challenge_policy":"everyone","locale":"\#(MockBackend.serverLocale)"}]"#)
        server.on("GET /rest/v1/favorite_venues", "[]")
        server.on("POST /rest/v1/rpc/is_admin", "true")
        try await backend.refreshRemoteProfile()
        XCTAssertTrue(backend.remoteIsAdmin)

        backend.signOutLocally()
        XCTAssertFalse(backend.remoteIsAdmin, "退出登录后不再是管理员")
    }

    func testDeletingTheAccountClearsTheCache() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/delete_account", "")
        server.on("POST /auth/v1/logout", status: 204, "")
        try await backend.remoteDeleteAccount()
        XCTAssertEqual(server.requests.first?.url?.path, "/rest/v1/rpc/delete_account")
        XCTAssertNil(backend.currentUser)
        XCTAssertNil(backend.remote?.session, "本机的登录也清掉")
        XCTAssertTrue(backend.db.users.isEmpty, "缓存里不留这个账号的数据")
    }

    // MARK: Venues

    private func venueJSON(id: String = "v-1a2b3c4d", status: String = "unconfirmed") -> String {
        #"{"id":"\#(id)","name":"Pasadena Rec Gym","aliases":[],"lat":34.15,"lon":-118.14,"street":"1 Colorado Blvd","unit":null,"city":"Pasadena","region":"CA","postal_code":"91101","country_code":"US","time_zone_id":"America/Los_Angeles","apple_place_id":"I123","court_count":4,"pricing":{"perPerson":8},"pricing_note":null,"currency_code":"USD","phone":null,"website":null,"entrance_note":null,"source":"apple_maps","status":"\#(status)","created_at":"2026-10-18T02:00:00+00:00","play_times":null,"location_approximate":false}"#
    }

    func testNearbyVenuesComeFromServer() async throws {
        let backend = try await signedInBackend()
        server.on("POST /rest/v1/rpc/venues_near", #"[{"venue":\#(venueJSON()),"distance_m":1200}]"#)
        let center = Coordinate(latitude: 34.14, longitude: -118.13)
        backend.refreshRemoteVenues(near: center, radiusKm: 25)
        await waitFor { backend.venue(id: "v-1a2b3c4d") != nil }

        let venue = try XCTUnwrap(backend.venue(id: "v-1a2b3c4d"), "球友新加的球馆从服务器拉下来")
        XCTAssertEqual(venue.postalAddress.city, "Pasadena")
        XCTAssertEqual(venue.source, .appleMaps)
        XCTAssertEqual(venue.pricing, .dropIn(perPerson: 8))
        XCTAssertEqual(server.json(0)["radius_km"] as? Double, 25)

        backend.refreshRemoteVenues(near: center, radiusKm: 25)
        XCTAssertEqual(server.requests.count, 1, "同一片区域 10 分钟内不重复拉")
    }

    func testAddingConfirmingAndReportingVenuesCallTheServer() async throws {
        let backend = try await signedInBackend()
        let venues = RemoteVenueService(backend: backend)
        let candidate = VenueCandidate(name: "Pasadena Rec Gym", location: Coordinate(latitude: 34.15, longitude: -118.14),
                                       address: PostalAddress(street: "1 Colorado Blvd", city: "Pasadena", region: "CA",
                                                              postalCode: "91101", countryCode: "US"),
                                       applePlaceId: "I123", timeZoneId: "America/Los_Angeles")

        server.on("POST /rest/v1/rpc/add_venue", venueJSON())
        let added = try await venues.addVenue(candidate, source: .appleMaps, aliases: ["Pasadena Rec"], courtCount: 4,
                                              entranceNote: nil, now: Date())
        XCTAssertEqual(added.id, "v-1a2b3c4d")
        let body = server.json(0)
        XCTAssertEqual(body["source"] as? String, "apple_maps")
        XCTAssertEqual(body["apple_place_id"] as? String, "I123")
        XCTAssertEqual(body["court_count"] as? Int, 4)
        XCTAssertNil(body["entrance_note"], "没填的字段不传，用服务器的默认值")
        XCTAssertNotNil(backend.venue(id: "v-1a2b3c4d"))

        server.on("POST /rest/v1/rpc/add_venue", status: 409, #"{"code":"23505","details":"Old Gym","hint":null,"message":"venue_duplicate"}"#)
        do {
            _ = try await venues.addVenue(candidate, source: .player, aliases: [], courtCount: nil, entranceNote: nil, now: Date())
            XCTFail("疑似重复要报错")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, RemoteError.server("venue_duplicate").errorDescription)
        }

        server.on("POST /rest/v1/rpc/confirm_venue", venueJSON(status: "confirmed"))
        try await venues.confirmVenue("v-1a2b3c4d")
        XCTAssertTrue(venues.hasConfirmed("v-1a2b3c4d"))
        XCTAssertEqual(backend.venue(id: "v-1a2b3c4d")?.status, .confirmed)

        server.on("POST /rest/v1/rpc/report_venue", "")
        try await venues.reportVenue("v-1a2b3c4d", issue: .notBadminton, detail: "")
        XCTAssertEqual(server.json(3)["issue"] as? String, "not_badminton")
    }

    func testRestoreWithoutSessionSignsOutLocally() async {
        let backend = MockBackend(store: .inMemory, seedsWorld: false)
        backend.createAccount(phone: "+16265550123", nickname: "Old", level: 3, seedsDemoContent: false)
        backend.remote = client()
        await backend.restoreRemoteSession()
        XCTAssertNil(backend.currentUser, "钥匙串里没有登录状态：回到登录页")
    }
}
