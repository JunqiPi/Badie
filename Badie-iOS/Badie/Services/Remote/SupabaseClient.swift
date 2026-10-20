import Foundation
import Security

// MARK: - 正式后端（Supabase）

/// 服务器地址和 publishable key。这个 key 本来就是公开的（网页里也有），数据靠数据库的行级权限和函数里的校验保护；
/// secret key 绝不放进 App
enum SupabaseConfig {
    static let url = "https://yeffnjdpjejlplqryjfx.supabase.co"
    static let publishableKey = "sb_publishable_oTHxEWYt2Gg8omKs98IHoQ_jNM0Blig"
    /// 网站上的人机验证页（见 web/src/pages/captcha.astro）
    static let captchaPage = URL(string: "https://badie.rsvp/captcha/")!
}

/// 登录状态（存在钥匙串里，App 重开后仍保持登录）
struct RemoteSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String?
}

/// 服务器返回的错误：数据库函数抛出的错误名（too_soon 等）、登录服务的错误码，或网络问题
enum RemoteError: LocalizedError, Equatable {
    case server(String)
    case network
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .network: return String(localized: "请检查网络后重试。")
        case .notSignedIn: return BackendError.notSignedIn.errorDescription
        case .server(let code): return Self.message(for: code)
        }
    }

    private static func message(for code: String) -> String {
        switch code {
        // 登录
        case "otp_expired", "otp_disabled": return String(localized: "验证码无效。请查看最新的一封邮件，或重新发送。")
        case "over_email_send_rate_limit", "over_request_rate_limit": return String(localized: "尝试次数过多，请等一分钟再试。")
        case "email_address_invalid", "validation_failed": return String(localized: "邮箱地址好像不对。")
        case "captcha_failed": return String(localized: "人机验证没有通过，请再试一次。")
        case "invalid_credentials": return String(localized: "邮箱或密码不对。以前用验证码登录的，点“忘记密码？”设置一个密码。")
        case "user_already_exists", "email_exists": return String(localized: "这个邮箱已经注册过了，请登录，或找回密码。")
        case "email_not_confirmed": return String(localized: "请先确认邮箱：输入注册时邮件里的验证码，或重新发送。")
        case "weak_password": return String(localized: "密码至少要 8 位。")
        case "same_password": return String(localized: "和现在的密码一样，请换一个新的。")
        case "venue_name_invalid": return BackendError.venueNameInvalid.localizedDescription
        case "venue_address_incomplete": return BackendError.venueAddressIncomplete.localizedDescription
        case "venue_rate_limited": return BackendError.venueRateLimited.localizedDescription
        case "venue_duplicate": return String(localized: "球馆库里已有这家球馆，请直接选择它。")
        // 约球
        case "too_soon": return String(localized: "开始时间至少要在 30 分钟后。")
        case "too_far": return String(localized: "最多只能提前两周安排。")
        case "invalid_slot": return String(localized: "时间范围请选 1–8 小时。")
        case "invalid_venues": return String(localized: "请选 1–3 个球馆。")
        case "too_many_requests": return String(localized: "你已有 5 个进行中的约球请求，先取消一个吧。")
        case "overlapping": return String(localized: "这个时间你已经有约球请求或球局了。")
        case "offer_closed": return String(localized: "这次匹配已失效。")
        case "not_active": return String(localized: "这个约球请求已结束。")
        case "not_paused": return String(localized: "这个约球请求已无法恢复。")
        case "cannot_cancel": return String(localized: "这场球局已经不能取消了。")
        case "cannot_check_in": return String(localized: "开始前 30 分钟才能签到。")
        case "cannot_report": return String(localized: "从球局开始到结束后 7 天内，都可以填报赛果。")
        case "result_locked": return String(localized: "双方已经确认了这个赛果。")
        case "invalid_score": return String(localized: "比分只能填数字，如 21:18 19:21。")
        case "retake_too_soon": return String(localized: "距上次测试满 90 天后，才能重新测试。")
        // 评价、球友、私信
        case "cannot_review": return String(localized: "评价在球局结束后 48 小时内开放。")
        case "already_reviewed": return String(localized: "你已经评价过这位球友了。")
        case "chat_closed": return String(localized: "这个聊天已关闭。")
        case "invalid_message": return String(localized: "请先输入消息（最多 1000 字）。")
        case "too_many_messages": return String(localized: "发消息太频繁了，请稍等一分钟。")
        case "not_allowed": return String(localized: "只能对匹配过的球友进行这个操作。")
        case "blocked": return String(localized: "请先解除对这位球友的屏蔽。")
        case "no_request": return String(localized: "这条好友申请已失效。")
        case "no_contact_info": return String(localized: "请不要包含电话或链接。")
        // 球群
        case "invalid_schedule": return String(localized: "请添加 1–3 个每周场次。")
        case "too_many_groups": return String(localized: "你的球群数量已达上限。")
        case "group_not_found": return String(localized: "没有找到这个球群。")
        case "level_out_of_range": return String(localized: "你的水平不在 TA 接受的范围内。")
        case "gender_restricted": return String(localized: "这个只限男生或只限女生。")
        case "owner_cannot_leave": return String(localized: "群主不能退出自己的球群。")
        case "not_organizer": return String(localized: "只有组织者才能这样操作。")
        case "not_member": return String(localized: "请先加入球群。")
        case "session_closed": return String(localized: "本场已关闭。")
        // 挑战
        case "challenge_closed": return String(localized: "这个挑战已失效。")
        case "friends_only": return String(localized: "TA 只接受球友的挑战。")
        case "already_pending": return String(localized: "你已经挑战过 TA 了，等 TA 回复吧。")
        case "cooldown": return String(localized: "距上次挑战满一周后，才能再挑战 TA。")
        case "too_many_outgoing": return String(localized: "同时最多只能有 3 个待回复的挑战。")
        case "invalid_partner": return String(localized: "请选一位那段时间有空的球友当搭档。")
        case "invalid_avatar": return String(localized: "照片上传失败，请重试。")
        // 高水平认证
        case "invalid_evidence": return String(localized: "链接格式不对，请复制完整的网页地址")
        case "invalid_level": return String(localized: "这类证据不能认证这个等级。")
        case "invalid_name": return String(localized: "请填写成绩或证书上的姓名")
        case "verification_pending": return String(localized: "你已有一份申请在审核中。")
        case "too_many_verifications": return String(localized: "30 天内最多申请 3 次。")
        case "daily_limit": return String(localized: "今天的挑战次数已用完。")
        case "target_busy": return String(localized: "TA 待处理的挑战太多了，请稍后再试。")
        case "admin_account": return String(localized: "管理员账号不能在这里注销，请先让其他管理员撤掉你的权限。")
        // 球局（房间）
        case "already_started": return String(localized: "开始时间已经过了，请重新选择。")
        case "missing_details": return String(localized: "公开球局需要设置球馆和时间")
        case "invalid_level_range": return String(localized: "最低水平不能高于最高水平。")
        case "too_many_rooms": return String(localized: "进行中的房间太多了，先结束或解散一个吧。")
        case "room_not_found": return BackendError.roomNotFound.localizedDescription
        case "room_closed": return BackendError.roomClosed.localizedDescription
        case "room_full": return BackendError.roomFull.localizedDescription
        case "not_room_owner": return BackendError.notRoomOwner.localizedDescription
        case "not_enough_players": return String(localized: "人还没齐，满员后才能开始。")
        case "too_many_invites": return String(localized: "一次最多邀请 10 位好友。")
        case "too_many_searches": return String(localized: "搜索太频繁了，过几分钟再试。")
        default: return String(localized: "出了点问题，请重试。")
        }
    }
}

/// 调用 Supabase：邮箱验证码 / Apple / Google 登录（Auth）+ 数据库函数和表（REST）。只用 URLSession，不引第三方库
@MainActor
final class SupabaseClient {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private(set) var session: RemoteSession? {
        didSet { storage.save(session) }
    }
    /// 登录失效（refresh token 被吊销或过期）时通知外面退回登录页
    var onSessionExpired: (@MainActor () -> Void)?

    private let storage: SessionStorage
    private let transport: Transport
    private var refreshing: Task<RemoteSession, Error>?

    init(storage: SessionStorage = .keychain, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.storage = storage
        self.transport = transport
        session = storage.load()
    }

    // MARK: 登录

    /// 发 6 位验证码到邮箱（没注册过的邮箱会自动建账号）
    /// 发验证码邮件；开启了人机验证时要带上 Turnstile 令牌
    func sendCode(email: String, captchaToken: String? = nil) async throws {
        _ = try await send("auth/v1/otp", body: withCaptcha(["email": email, "create_user": true], captchaToken), authorized: false)
    }

    /// 输入邮件里的 6 位码：type 是 email（验证码登录）、signup（确认注册的邮箱）或 recovery（重设密码）
    func verify(email: String, code: String, type: String = "email") async throws -> RemoteSession {
        let data = try await send("auth/v1/verify", body: ["type": type, "email": email, "token": code], authorized: false)
        let next = try RemoteJSON.session(from: data)
        session = next
        return next
    }

    /// 邮箱 + 密码注册：服务器把 6 位确认码发到邮箱，确认后才能登录（返回 nil）。
    /// 邮箱已注册时，服务器要么报 user_already_exists，要么（防止探测邮箱）返回没有登录方式的账号，两种都当作已注册
    func signUp(email: String, password: String, captchaToken: String? = nil) async throws -> RemoteSession? {
        let data = try await send("auth/v1/signup", body: withCaptcha(["email": email, "password": password], captchaToken), authorized: false)
        if let next = try? RemoteJSON.session(from: data) {
            session = next
            return next
        }
        struct Account: Decodable {
            struct Identity: Decodable {}
            let identities: [Identity]?
        }
        if (try? RemoteJSON.decode(Account.self, from: data))?.identities?.isEmpty == true { throw RemoteError.server("user_already_exists") }
        return nil
    }

    func signIn(email: String, password: String, captchaToken: String? = nil) async throws -> RemoteSession {
        let data = try await send("auth/v1/token?grant_type=password",
                                  body: withCaptcha(["email": email, "password": password], captchaToken), authorized: false)
        let next = try RemoteJSON.session(from: data)
        session = next
        return next
    }

    /// 忘记密码：发 6 位重设码（邮箱没注册也一样返回成功，不让人探测）
    func sendPasswordReset(email: String, captchaToken: String? = nil) async throws {
        _ = try await send("auth/v1/recover", body: withCaptcha(["email": email], captchaToken), authorized: false)
    }

    /// 注册确认码没收到：重发
    func resendSignupCode(email: String, captchaToken: String? = nil) async throws {
        _ = try await send("auth/v1/resend", body: withCaptcha(["type": "signup", "email": email], captchaToken), authorized: false)
    }

    /// 设置或修改密码（已登录）
    func updatePassword(_ password: String) async throws {
        _ = try await send("auth/v1/user", method: "PUT", body: ["password": password])
    }

    /// 开启了人机验证时，登录服务的请求都要带上 Turnstile 令牌
    private func withCaptcha(_ body: [String: Any], _ captchaToken: String?) -> [String: Any] {
        guard let captchaToken, !captchaToken.isEmpty else { return body }
        return body.merging(["gotrue_meta_security": ["captcha_token": captchaToken]]) { current, _ in current }
    }

    /// Sign in with Apple（原生）：把 Apple 给的身份令牌和原始 nonce 交给 Supabase 换登录状态
    func signIn(provider: String, idToken: String, nonce: String) async throws -> RemoteSession {
        let data = try await send("auth/v1/token?grant_type=id_token",
                                  body: ["provider": provider, "id_token": idToken, "nonce": nonce], authorized: false)
        let next = try RemoteJSON.session(from: data)
        session = next
        return next
    }

    /// 网页式登录（Google）：系统浏览器里登录完带回一次性的 code，用 PKCE 的 verifier 换登录状态
    func authorizeURL(provider: String, redirect: String, challenge: String) -> URL? {
        var components = URLComponents(string: SupabaseConfig.url + "/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirect),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components?.url
    }

    func exchange(code: String, verifier: String) async throws -> RemoteSession {
        let data = try await send("auth/v1/token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier], authorized: false)
        let next = try RemoteJSON.session(from: data)
        session = next
        return next
    }

    /// 后台开了哪些第三方登录（公开接口）；没开的不显示按钮
    func enabledProviders() async -> Set<String> {
        struct Settings: Decodable { let external: [String: Bool] }
        guard let data = try? await send("auth/v1/settings", method: "GET", authorized: false),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return [] }
        return Set(settings.external.filter { $0.value }.keys)
    }

    /// 这个账号用过哪些方式登录（email / apple / google）
    func signInMethods() async throws -> [String] {
        struct User: Decodable {
            struct Meta: Decodable { let providers: [String]? }
            let appMetadata: Meta
        }
        return try RemoteJSON.decode(User.self, from: try await send("auth/v1/user", method: "GET")).appMetadata.providers ?? []
    }

    /// 调服务器函数：POST /functions/v1/<name>
    func invoke(_ function: String, _ body: [String: Any]) async throws {
        _ = try await send("functions/v1/\(function)", body: body)
    }

    func signOut() async {
        if session != nil { _ = try? await send("auth/v1/logout", body: [:]) }
        session = nil
    }

    // MARK: 数据

    /// 调数据库函数：POST /rest/v1/rpc/<name>
    func rpc<T: Decodable>(_ name: String, _ args: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        try RemoteJSON.decode(T.self, from: try await send("rest/v1/rpc/\(name)", body: args))
    }

    /// 调没有返回值的数据库函数
    func call(_ name: String, _ args: [String: Any] = [:]) async throws {
        _ = try await send("rest/v1/rpc/\(name)", body: args)
    }

    /// 读表：GET /rest/v1/<table>?<query>（只能读到行级权限允许的行）
    func select<T: Decodable>(_ table: String, query: String, as type: T.Type = T.self) async throws -> T {
        try RemoteJSON.decode(T.self, from: try await send("rest/v1/\(table)?\(query)", method: "GET"))
    }

    func insert(_ table: String, _ row: [String: Any]) async throws {
        _ = try await send("rest/v1/\(table)", body: row)
    }

    func update(_ table: String, query: String, _ values: [String: Any]) async throws {
        _ = try await send("rest/v1/\(table)?\(query)", method: "PATCH", body: values)
    }

    func delete(_ table: String, query: String) async throws {
        _ = try await send("rest/v1/\(table)?\(query)", method: "DELETE")
    }

    // MARK: 文件（头像照片）

    /// 上传到存储桶：POST /storage/v1/object/<bucket>/<path>
    func upload(_ bucket: String, path: String, data: Data, contentType: String) async throws {
        _ = try await send("storage/v1/object/\(bucket)/\(path)", rawBody: data, contentType: contentType)
    }

    func removeFile(_ bucket: String, path: String) async throws {
        _ = try await send("storage/v1/object/\(bucket)/\(path)", method: "DELETE")
    }

    /// 下载公开桶里的文件（不需要登录）
    func download(_ bucket: String, path: String) async throws -> Data {
        try await send("storage/v1/object/public/\(bucket)/\(path)", method: "GET", authorized: false)
    }

    // MARK: 请求

    private func send(_ path: String, method: String = "POST", body: [String: Any]? = nil, rawBody: Data? = nil, contentType: String? = nil,
                      authorized: Bool = true) async throws -> Data {
        guard let url = URL(string: SupabaseConfig.url + "/" + path) else { throw RemoteError.server("bad_url") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            request.setValue("Bearer \(try await validSession().accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if let rawBody {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = rawBody
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw RemoteError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw RemoteError.server(RemoteJSON.errorCode(from: data, status: status)) }
        return data
    }

    /// 访问令牌快过期时先换新的（同时只换一次）；refresh token 失效就算退出登录
    private func validSession() async throws -> RemoteSession {
        guard let current = session else { throw RemoteError.notSignedIn }
        if current.expiresAt > Date().addingTimeInterval(60) { return current }
        if let refreshing { return try await refreshing.value }
        let task = Task { () throws -> RemoteSession in
            let data = try await self.send("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken],
                                           authorized: false)
            return try RemoteJSON.session(from: data)
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let next = try await task.value
            session = next
            return next
        } catch RemoteError.server(_) {
            session = nil
            onSessionExpired?()
            throw RemoteError.notSignedIn
        }
    }
}

// MARK: - 登录状态的存放

struct SessionStorage {
    var load: () -> RemoteSession?
    var save: (RemoteSession?) -> Void

    static let keychain = SessionStorage(
        load: { Keychain.read(account: "supabase-session").flatMap { try? JSONDecoder().decode(RemoteSession.self, from: $0) } },
        save: { session in Keychain.write(session.flatMap { try? JSONEncoder().encode($0) }, account: "supabase-session") }
    )

    /// 测试用：不碰钥匙串
    static var memory: SessionStorage { SessionStorage(load: { nil }, save: { _ in }) }
}

enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.badie.app", kSecAttrAccount as String: account]
    }

    static func read(account: String) -> Data? {
        var item: CFTypeRef?
        var search = query(account)
        search[kSecReturnData as String] = true
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// data 为 nil 时删除
    static func write(_ data: Data?, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let data else { return }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

// MARK: - JSON

/// 服务器的 JSON：字段是 snake_case，时间是 Postgres 的 ISO 8601（可能带 1–6 位小数秒）
enum RemoteJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "不是时间：\(text)")
            }
            return date
        }
        return decoder
    }()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[Supabase] 解析 \(T.self) 失败：\(error)")
            #endif
            throw RemoteError.server("bad_response")
        }
    }

    static func parseDate(_ text: String) -> Date? {
        // ISO8601DateFormatter 只认 3 位小数秒；Postgres 时区写成 +00:00 或 +00
        var value = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        if value.range(of: #"[+-]\d\d$"#, options: .regularExpression) != nil { value += ":00" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct TokenResponse: Decodable {
        struct AuthUser: Decodable {
            let id: String
            let email: String?
        }

        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: AuthUser
    }

    static func session(from data: Data) throws -> RemoteSession {
        let token = try decode(TokenResponse.self, from: data)
        return RemoteSession(accessToken: token.accessToken, refreshToken: token.refreshToken,
                             expiresAt: Date().addingTimeInterval(token.expiresIn), userId: token.user.id, email: token.user.email)
    }

    /// 错误码：数据库函数用 message（too_soon），登录服务用 error_code，都没有就按 HTTP 状态
    static func errorCode(from data: Data, status: Int) -> String {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        for key in ["error_code", "message", "error"] {
            if let code = body[key] as? String, !code.isEmpty { return code }
        }
        return "http_\(status)"
    }
}
