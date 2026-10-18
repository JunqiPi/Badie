import SwiftUI

/// 应用的全部状态对象
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
        if RemoteMode.isEnabled {
            let backend = MockBackend(store: .remoteCache, seedsWorld: false)
            backend.simulationEnabled = false
            backend.latencyEnabled = false
            backend.remote = SupabaseClient()
            backend.remote?.onSessionExpired = { [weak backend] in backend?.signOutLocally() }
            let environment = AppEnvironment(backend: backend)
            // 地图上找到的球馆服务器上没有，不能用来约球
            environment.locationManager.allowsMapSearch = false
            return environment
        }
        return AppEnvironment(backend: .shared)
    }
}

/// 正式后端开关。功能接入完之前默认关闭；用启动参数 `-BBRemote YES` 打开
enum RemoteMode {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "BBRemote") }
}

