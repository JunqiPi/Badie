import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var friendManager: FriendManager

    var body: some View {
        ZStack {
            AppTheme.Colors.canvas.ignoresSafeArea()
            switch appState.phase {
            case .launching:
                SplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingFlow()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                ToastView(toast: toast)
                    .padding(.top, AppTheme.Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { appState.toast = nil }
                    .zIndex(10)
            }
        }
        .tint(AppTheme.Colors.ink)
        .preferredColorScheme(appState.appearance.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                surveyManager.refresh()
                if appState.phase == .main {
                    messageManager.refreshNow()
                    appState.refreshStrikes()
                    locationManager.start()
                }
            }
        }
        .onChange(of: appState.phase) { _, phase in
            switch phase {
            case .main:
                locationManager.start()
                appState.refreshStrikes()
            case .onboarding: router.reset()
            case .launching: break
            }
        }
        .onAppear {
            NotificationRouter.shared.router = router
            NotificationRouter.shared.messages = messageManager
        }
        // 点开 badie.rsvp 的链接（邀请、邮件里的球局）直接进 App 里对应的页面；哪些地址进 App 见网站的 apple-app-site-association
        .onOpenURL { url in
            guard url.host() == "badie.rsvp" else { return }
            // 加球友链接：/add/<码>/，找到人就打开他的资料（在那里加球友）
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.first == "add", parts.count > 1 {
                return openFriendLink(parts[1])
            }
            let target = PushRegistry.route(for: url.absoluteString)
            router.show(target.route, in: target.tab)
        }
    }

    private func openFriendLink(_ code: String) {
        Task {
            do {
                if let userId = try await friendManager.openFriendLink(code) {
                    if userId == appState.currentUser?.id {
                        appState.showToast(String(localized: "这是你自己的加球友链接"))
                    }
                    appState.showPlayer(userId)
                } else {
                    appState.showToast(String(localized: "这个加球友链接已失效"), style: .error)
                }
            } catch {
                appState.showToast((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, style: .error)
            }
        }
    }
}

// MARK: - 隐藏系统导航栏后仍保留右滑返回手势

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - 页面统一外观

extension View {
    /// 隐藏系统导航栏、使用画布背景（自定义 ScreenHeader）
    func screenChrome() -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
