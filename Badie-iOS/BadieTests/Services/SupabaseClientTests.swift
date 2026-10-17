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

    func testRestoreWithoutSessionSignsOutLocally() async {
        let backend = MockBackend(store: .inMemory, seedsWorld: false)
        backend.createAccount(phone: "+16265550123", nickname: "Old", level: 3, seedsDemoContent: false)
        backend.remote = client()
        await backend.restoreRemoteSession()
        XCTAssertNil(backend.currentUser, "钥匙串里没有登录状态：回到登录页")
    }
}
