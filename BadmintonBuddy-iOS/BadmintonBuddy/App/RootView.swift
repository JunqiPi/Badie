import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var surveyManager: SurveyManager

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
                if appState.phase == .main { locationManager.start() }
            }
        }
        .onChange(of: appState.phase) { _, phase in
            if phase == .main { locationManager.start() }
        }
    }
}

// MARK: - 隐藏系统导航栏后仍保留右滑返回手势

extension UINavigationController: UIGestureRecognizerDelegate {
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
