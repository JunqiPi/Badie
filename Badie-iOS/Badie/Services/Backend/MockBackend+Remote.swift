import Foundation

// MARK: - 正式后端模式
/// 登录、资料、定级、收藏球馆走 Supabase；本地 db 只当缓存，界面照旧同步读取。
/// 还没接入服务器的功能在这个模式下隐藏，之后逐个补上
extension MockBackend {

    /// 自己的资料（profiles 表只能读到本人这一行）
    struct RemoteProfile: Decodable {
        let id: String
        let nickname: String
        let countryCode: String?
        let rating: Double
        let assessedAt: Date?
        let showOnBoards: Bool
        let challengePolicy: String
        let discoverable: Bool?
        let showAsRegular: Bool?
        let allowMessageRequests: Bool?
        let emailAlerts: Bool?
        let verifiedKind: String?
        let verifiedRating: Double?
        let avatarPath: String?
        let locale: String
        let gender: String?
        let createdAt: Date?
    }

    private struct FavoriteRow: Decodable {
        let venueId: String
    }

    func requireRemote() throws -> SupabaseClient {
        guard let remote else { throw RemoteError.notSignedIn }
        return remote
    }

    // MARK: 登录

    func remoteSendCode(email: String, captchaToken: String?) async throws {
        try await requireRemote().sendCode(email: Self.normalizedEmail(email), captchaToken: captchaToken)
    }

    /// 输入邮件里的 6 位码：type 是 email（验证码登录）、signup（确认注册的邮箱）或 recovery（重设密码）
    func remoteVerify(email: String, code: String, type: String = "email") async throws -> AuthOutcome {
        try await outcome(after: requireRemote().verify(email: Self.normalizedEmail(email), code: code, type: type))
    }

    /// 邮箱 + 密码注册：要先确认邮箱时返回 nil（确认码已发出）
    func remoteSignUp(email: String, password: String, captchaToken: String?) async throws -> AuthOutcome? {
        guard let session = try await requireRemote().signUp(email: Self.normalizedEmail(email), password: password, captchaToken: captchaToken)
        else { return nil }
        return try await outcome(after: session)
    }

    func remoteSignIn(email: String, password: String, captchaToken: String?) async throws -> AuthOutcome {
        try await outcome(after: requireRemote().signIn(email: Self.normalizedEmail(email), password: password, captchaToken: captchaToken))
    }

    func remoteSendPasswordReset(email: String, captchaToken: String?) async throws {
        try await requireRemote().sendPasswordReset(email: Self.normalizedEmail(email), captchaToken: captchaToken)
    }

    func remoteResendSignupCode(email: String, captchaToken: String?) async throws {
        try await requireRemote().resendSignupCode(email: Self.normalizedEmail(email), captchaToken: captchaToken)
    }

    func remoteUpdatePassword(_ password: String) async throws {
        try await requireRemote().updatePassword(password)
    }

    func remoteSignInWithApple(idToken: String, nonce: String) async throws -> AuthOutcome {
        try await outcome(after: requireRemote().signIn(provider: "apple", idToken: idToken, nonce: nonce))
    }

    func remoteSignInWithGoogle(idToken: String, nonce: String) async throws -> AuthOutcome {
        try await outcome(after: requireRemote().signIn(provider: "google", idToken: idToken, nonce: nonce))
    }

    /// 登录成功（密码、验证码、Apple、Google 都一样）：有资料就直接登录，没有就去填资料
    private func outcome(after session: RemoteSession) async throws -> AuthOutcome {
        await remoteRegisterPush()
        if let user = try await refreshRemoteProfile() { return .signedIn(user) }
        return .needsProfile(phone: session.email ?? "")
    }

    // MARK: 推送

    /// 登录状态下把这台设备的推送令牌报给服务器（开发版走 Apple 的 sandbox 环境）
    func remoteRegisterPush() async {
        guard let remote, remote.session != nil, let token = PushRegistry.shared.token else { return }
        #if DEBUG
        let kind = "apns_sandbox"
        #else
        let kind = "apns"
        #endif
        try? await remote.call("register_push", ["p_kind": kind, "p_token": token])
    }

    /// 退出登录前：这台设备不再收这个账号的推送
    func remoteUnregisterPush() async {
        guard let remote, remote.session != nil, let token = PushRegistry.shared.token else { return }
        try? await remote.call("unregister_push", ["p_token": token])
    }

    /// 第一次登录：建资料（含定级用的性别），做过问卷就保存定级。头像、常用时间目前只存在本机
    func remoteRegister(nickname: String, gender: Gender, avatar: Avatar, assessment: SkillAssessmentSummary?,
                        answers: [String: Int]) async throws -> User {
        let client = try requireRemote()
        guard let userId = client.session?.userId else { throw RemoteError.notSignedIn }
        try await client.insert("profiles", [
            "id": userId,
            "nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            "country_code": CountryInfo.deviceCountry.code,
            "gender": gender.serverJSON,
        ])
        if let assessment {
            try await client.call("save_assessment", ["p_rating": assessment.tier.rating, "p_answers": answers])
        }
        guard var user = try await refreshRemoteProfile() else { throw RemoteError.server("no_profile") }
        user.avatar = avatar
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }

    /// 启动时：钥匙串里有登录状态就刷新资料；登录失效或资料没建完就回到登录页。离线时先用缓存
    func restoreRemoteSession() async {
        guard let remote else { return }
        guard remote.session != nil else { return signOutLocally() }
        do {
            if try await refreshRemoteProfile() == nil { return signOutLocally() }
            await remoteRegisterPush()
        } catch RemoteError.notSignedIn {
            signOutLocally()
        } catch {
            // 网络问题：保持缓存里的登录状态
        }
    }

    /// 只清本地登录状态（服务器那边已经失效或从没登录过）
    func signOutLocally() {
        guard db.currentUserId != nil else { return }
        remoteIsAdmin = false
        remoteAvatarPath = nil
        remoteAvatarChecked = []
        db.currentUserId = nil
        saveNow()
        emit(.sessionChanged)
    }

    /// 注销：服务器删除账号和数据（以后的球局取消、球群交接），成功后清空本机缓存
    func remoteDeleteAccount() async throws {
        let remote = try requireRemote()
        // 用 Apple 登录过的账号：先请 Apple 撤销授权（Apple 的要求，要用户再确认一次拿授权码）。
        // 关掉弹窗或没撤销成功也照样注销，用户可以在 Apple 账户设置里自己停用
        if (try? await remote.signInMethods())?.contains("apple") == true,
           let code = try? await AppleSignIn().run().authorizationCode {
            try? await remote.invoke("apple-revoke", ["code": code])
        }
        // 照片文件先删掉（账号删了以后就没权限删了）
        if let path = remoteAvatarPath { try? await remote.removeFile("avatars", path: path) }
        try await remote.call("delete_account")
        await remote.signOut()
        store.erase()
        db = Database()
        saveNow()
        emit(.sessionChanged)
    }

    // MARK: 资料

    /// 读自己的资料和收藏写进缓存；还没建资料时返回 nil
    @discardableResult
    func refreshRemoteProfile() async throws -> User? {
        let client = try requireRemote()
        guard let session = client.session else { throw RemoteError.notSignedIn }
        let rows: [RemoteProfile] = try await client.select("profiles", query: "id=eq.\(session.userId)&select=*")
        guard let profile = rows.first else { return nil }
        let favorites: [FavoriteRow] = try await client.select("favorite_venues", query: "select=venue_id&order=created_at")
        db.favoriteCourtIds[profile.id] = favorites.map(\.venueId)
        // 写缓存之前查：缓存会通知界面刷新，设置页据此决定是否显示演示模式开关
        remoteIsAdmin = (try? await client.rpc("is_admin", as: Bool.self)) ?? false
        var user = cache(profile, email: session.email)
        try? await refreshRemoteVerification()
        remoteAvatarPath = profile.avatarPath
        await applyAvatar(profile.avatarPath, to: profile.id)
        user = db.users[profile.id] ?? user
        if profile.locale != Self.serverLocale {
            try? await client.update("profiles", query: "id=eq.\(profile.id)", ["locale": Self.serverLocale])
        }
        return user
    }

    private func cache(_ profile: RemoteProfile, email: String?) -> User {
        let tier = SkillTier(rating: profile.rating)
        var user = db.users[profile.id] ?? User(id: profile.id, nickname: profile.nickname, phone: email ?? "", selfReportedLevel: tier.level)
        user.nickname = profile.nickname
        user.selfReportedLevel = min(tier.level, SkillLevel.maxSelfSelectable)
        user.selfReportedRating = profile.rating
        if let assessedAt = profile.assessedAt {
            if user.assessment?.assessedAt != assessedAt {
                user.assessment = SkillAssessmentSummary(level: tier.level, needsCalibration: false, isReturning: false,
                                                         assessedAt: assessedAt, rating: profile.rating)
            }
        } else {
            user.assessment = nil
            user.assessmentSkippedAt = user.assessmentSkippedAt ?? Date()
        }
        if let createdAt = profile.createdAt { user.joinDate = createdAt }
        user.privacy.showsOnLeaderboards = profile.showOnBoards
        user.privacy.challengePolicy = ChallengePolicy(server: profile.challengePolicy)
        user.privacy.findableByNickname = profile.discoverable ?? true
        user.privacy.showsAsRegular = profile.showAsRegular ?? false
        user.privacy.allowsMessageRequests = profile.allowMessageRequests ?? true
        user.privacy.emailAlerts = profile.emailAlerts ?? false
        user.gender = Gender(server: profile.gender)
        if let kind = profile.verifiedKind.flatMap(VerificationStatus.init(server:)), let rating = profile.verifiedRating {
            user.applyVerification(kind, tier: SkillTier(rating: rating))
        } else {
            user.applyVerification(.unverified, tier: SkillTier(rating: profile.rating))
        }
        db.users[user.id] = user
        let signingIn = db.currentUserId != user.id
        db.currentUserId = user.id
        scheduleSave()
        emit(signingIn ? .sessionChanged : .userUpdated(user))
        if signingIn { Task { await refreshRemoteActivity() } }
        return user
    }

    /// 定级（注册后补测或 90 天后重测）
    @discardableResult
    func saveAssessment(_ result: SkillAssessmentResult, answers: [String: Int]) async throws -> User {
        guard let remote else { return try updateAssessment(result) }
        let tier = min(result.tier, SkillAssessment.maxTier)
        try await remote.call("save_assessment", ["p_rating": tier.rating, "p_answers": answers])
        guard var user = try await refreshRemoteProfile() else { throw RemoteError.notSignedIn }
        user.assessment?.needsCalibration = result.needsCalibration
        user.assessment?.isReturning = result.isReturning
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }

    /// 改了资料或隐私后同步到服务器；失败就按服务器的数据恢复
    func pushRemote(_ values: [String: Any]) {
        guard let remote, let userId = currentUserId else { return }
        Task {
            do {
                try await remote.update("profiles", query: "id=eq.\(userId)", values)
            } catch {
                _ = try? await refreshRemoteProfile()
            }
        }
    }

    /// 收藏或取消收藏球馆
    func pushRemoteFavorite(_ venueId: String, isFavorite: Bool) {
        guard let remote, let userId = currentUserId else { return }
        Task {
            do {
                if isFavorite {
                    try await remote.insert("favorite_venues", ["user_id": userId, "venue_id": venueId])
                } else {
                    try await remote.delete("favorite_venues", query: "user_id=eq.\(userId)&venue_id=eq.\(venueId)")
                }
            } catch {
                _ = try? await refreshRemoteProfile()
            }
        }
    }

    // MARK: Helpers

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidEmail(_ email: String) -> Bool {
        normalizedEmail(email).range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// 通知和邮件用 App 当前的界面语言（和服务器支持的语言一致）
    static var serverLocale: String {
        let supported = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "id", "ms", "th", "vi", "hi"]
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return supported.contains(language) ? language : "en"
    }
}

extension ChallengePolicy {
    /// 服务器的写法：similar 对应“水平相近”
    init(server value: String) {
        self = value == "similar" ? .similarLevel : ChallengePolicy(rawValue: value) ?? .similarLevel
    }

    var serverValue: String { self == .similarLevel ? "similar" : rawValue }
}
