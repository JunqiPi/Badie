import AuthenticationServices
import Combine
import SwiftUI

// MARK: - 外观设置

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .light: return String(localized: "浅色")
        case .dark: return String(localized: "深色")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 轻提示

struct Toast: Identifiable, Equatable {
    enum Style { case info, success, error }

    let id = UUID()
    let message: String
    var style: Style = .info
}

/// 用于 sheet(item:) 的球友资料弹窗标识
struct PlayerSheetItem: Identifiable, Hashable {
    let id: String
}

// MARK: - 全局会话状态

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case launching
        case onboarding
        case main
    }

    @Published var phase: Phase = .launching
    @Published private(set) var currentUser: User?
    @Published var toast: Toast?
    @Published var presentedPlayer: PlayerSheetItem?
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    let backend: MockBackend
    /// 球馆库（界面只通过接口访问，便于换成正式后端）
    /// 正式后端：读本地缓存、写走服务器；模拟后端直接用自己
    private(set) lazy var venueService: any VenueService = backend.isRemote ? RemoteVenueService(backend: backend) : backend
    /// 截图/演示模式下跳过启动动画
    var skipsSplash = false
    /// 登录流程的起始步骤（演示模式可直接打开手机号页）
    var onboardingInitialStep: OnboardingStep = .welcome
    /// 演示/截图：注册时预填的定级答案
    var onboardingDemoAnswers: [String: Int] = [:]
    #if DEBUG
    /// 演示/截图：认证申请页预填的内容
    var verificationDemo: (kind: VerificationStatus, tier: SkillTier, link: String, name: String, note: String)?
    /// 演示/截图：等级对照表打开时滚到哪一级
    var guideScrollLevel: Int?
    #endif

    private static let appearanceKey = "appearance"
    private var toastTask: Task<Void, Never>?

    init(backend: MockBackend) {
        self.backend = backend
        self.appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "") ?? .system
        self.currentUser = backend.currentUser
        backend.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    /// 启动动画结束后决定进入哪个流程
    func finishLaunch() {
        currentUser = backend.currentUser
        withAnimation(AppTheme.Motion.gentle) {
            phase = currentUser == nil ? .onboarding : .main
        }
        // 正式后端：先用缓存进入，再在后台核对登录状态和资料
        if backend.isRemote { Task { await backend.restoreRemoteSession() } }
    }

    /// 正式后端用邮箱登录，演示环境用手机号
    var isRemote: Bool { backend.isRemote }

    /// 管理员可以在设置里打开演示模式
    var isAdmin: Bool { backend.remoteIsAdmin }

    private func handle(_ event: BackendEvent) {
        switch event {
        case .sessionChanged:
            currentUser = backend.currentUser
            if phase != .launching {
                withAnimation(AppTheme.Motion.gentle) {
                    phase = currentUser == nil ? .onboarding : .main
                }
            }
        case .userUpdated(let user):
            if user.id == currentUser?.id { currentUser = user }
        case .remoteFailed(let message):
            showToast(message, style: .error)
        default:
            break
        }
    }

    // MARK: Auth

    func requestCode(phone: String) async throws -> String {
        try await backend.requestCode(phone: phone)
    }

    func verify(phone: String, code: String) async throws -> AuthOutcome {
        try await backend.verify(phone: phone, code: code)
    }

    func requestCode(email: String, captchaToken: String?) async throws {
        try await backend.remoteSendCode(email: email, captchaToken: captchaToken)
    }

    func verify(email: String, code: String) async throws -> AuthOutcome {
        try await backend.remoteVerify(email: email, code: code)
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthOutcome {
        try await backend.remoteSignInWithApple(idToken: idToken, nonce: nonce)
    }

    /// Google：在系统浏览器里登录（和 Safari 共用登录状态），带着一次性的 code 跳回来再换登录状态。
    /// 在对方页面取消了返回 nil
    func signInWithGoogle(_ browser: WebAuthenticationSession) async throws -> AuthOutcome? {
        let verifier = SocialSignIn.randomString()
        guard let url = try backend.requireRemote().authorizeURL(provider: "google", redirect: SocialSignIn.redirect,
                                                                 challenge: SocialSignIn.pkceChallenge(verifier)) else { return nil }
        let callback = try await browser.authenticate(using: url, callbackURLScheme: SocialSignIn.callbackScheme,
                                                      preferredBrowserSession: .shared)
        guard let code = SocialSignIn.code(from: callback) else { return nil }
        return try await backend.remoteSignInWithGoogle(code: code, verifier: verifier)
    }

    /// 后台开了的第三方登录（apple / google）；离线或演示模式下是空的
    func socialProviders() async -> Set<String> {
        guard backend.isRemote, let remote = try? backend.requireRemote() else { return [] }
        return await remote.enabledProviders()
    }

    func registerRemote(nickname: String, gender: Gender, avatar: Avatar, assessment: SkillAssessmentSummary?,
                        answers: [String: Int]) async throws {
        _ = try await backend.remoteRegister(nickname: nickname, gender: gender, avatar: avatar, assessment: assessment, answers: answers)
        showToast(String(localized: "注册成功，欢迎加入 🏸"), style: .success)
    }

    func register(
        phone: String,
        nickname: String,
        gender: Gender,
        avatar: Avatar,
        level: Int,
        preferredMode: GameMode?,
        recurringSlots: [RecurringTimeSlot],
        location: Coordinate?,
        assessment: SkillAssessmentSummary? = nil
    ) async throws {
        _ = try await backend.register(
            phone: phone, nickname: nickname, gender: gender, avatar: avatar, level: level,
            preferredMode: preferredMode, recurringSlots: recurringSlots, location: location, assessment: assessment
        )
        showToast(String(localized: "注册成功，欢迎加入 🏸"), style: .success)
    }

    func updateProfile(_ user: User) async -> Bool {
        do {
            currentUser = try await backend.updateProfile(user)
            showToast(String(localized: "资料已保存"), style: .success)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func signOut() {
        backend.signOut()
    }

    func deleteAccount() {
        guard backend.isRemote else {
            backend.deleteAccount()
            showToast(String(localized: "账号与数据已删除"))
            return
        }
        Task {
            do {
                try await backend.remoteDeleteAccount()
                showToast(String(localized: "账号与数据已删除"))
            } catch {
                showError(error)
            }
        }
    }

    func resetDemoData() {
        backend.resetAll()
        showToast(String(localized: "演示数据已重置"))
    }

    // MARK: UI helpers

    func showToast(_ message: String, style: Toast.Style = .info) {
        toastTask?.cancel()
        withAnimation(AppTheme.Motion.standard) {
            toast = Toast(message: message, style: style)
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(AppTheme.Motion.gentle) {
                self?.toast = nil
            }
        }
        switch style {
        case .success: Haptics.success()
        case .error: Haptics.error()
        case .info: break
        }
    }

    func showError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showToast(message, style: .error)
    }

    func showPlayer(_ userId: String) {
        guard userId != currentUser?.id else { return }
        guard backend.isRemote else {
            if backend.user(id: userId) != nil { presentedPlayer = PlayerSheetItem(id: userId) }
            return
        }
        // 正式后端：先用缓存打开，同时拉取最新资料；没见过的人拉到了再打开
        if backend.user(id: userId) != nil { presentedPlayer = PlayerSheetItem(id: userId) }
        Task {
            if await backend.refreshRemotePlayer(userId) != nil, presentedPlayer == nil {
                presentedPlayer = PlayerSheetItem(id: userId)
            }
        }
    }
}
