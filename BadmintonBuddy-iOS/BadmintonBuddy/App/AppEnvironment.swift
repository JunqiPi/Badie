import SwiftUI

/// 应用的全部状态对象（App 启动、SwiftUI 预览共用）
@MainActor
struct AppEnvironment {
    let backend: MockBackend
    let appState: AppState
    let router: Router
    let locationManager: LocationManager
    let matchManager: MatchManager
    let friendManager: FriendManager
    let messageManager: MessageManager
    let roomManager: RoomManager
    let surveyManager: SurveyManager
    let inboxManager: InboxManager
    let groupManager: GroupManager

    init(backend: MockBackend) {
        self.backend = backend
        appState = AppState(backend: backend)
        router = Router()
        locationManager = LocationManager(backend: backend)
        matchManager = MatchManager(backend: backend)
        friendManager = FriendManager(backend: backend)
        messageManager = MessageManager(backend: backend)
        roomManager = RoomManager(backend: backend)
        surveyManager = SurveyManager(backend: backend)
        inboxManager = InboxManager(backend: backend)
        groupManager = GroupManager(backend: backend)
    }

    /// 正常启动；DEBUG 构建中支持 `-BBDemoScreen <name>` 直接打开某个页面（用于截图与设计走查）
    static func makeForLaunch() -> AppEnvironment {
        #if DEBUG
        if let screen = UserDefaults.standard.string(forKey: "BBDemoScreen") {
            return DemoLauncher.makeEnvironment(screen: screen)
        }
        #endif
        return AppEnvironment(backend: .shared)
    }

    /// 预览使用：内存数据库 + 已登录的演示用户
    static func preview(signedIn: Bool = true) -> AppEnvironment {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        if signedIn {
            backend.createAccount(phone: "+16265550123", nickname: "阿杰", avatar: Avatar(symbol: "", paletteIndex: 0), level: 4, preferredMode: .doubles)
        }
        let environment = AppEnvironment(backend: backend)
        environment.appState.phase = signedIn ? .main : .onboarding
        return environment
    }
}

extension View {
    /// 注入所有环境对象
    func injecting(_ environment: AppEnvironment) -> some View {
        self
            .environmentObject(environment.appState)
            .environmentObject(environment.router)
            .environmentObject(environment.locationManager)
            .environmentObject(environment.matchManager)
            .environmentObject(environment.friendManager)
            .environmentObject(environment.messageManager)
            .environmentObject(environment.roomManager)
            .environmentObject(environment.surveyManager)
            .environmentObject(environment.inboxManager)
            .environmentObject(environment.groupManager)
    }
}
