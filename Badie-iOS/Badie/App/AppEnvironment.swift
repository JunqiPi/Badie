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
        return DemoMode.isEnabled ? makeDemo() : makeLive()
    }

    /// 正式后端（Supabase，与网页共用），本地数据库只当缓存
    static func makeLive() -> AppEnvironment {
        let backend = MockBackend(store: .remoteCache, seedsWorld: false)
        backend.simulationEnabled = false
        backend.latencyEnabled = false
        backend.remote = SupabaseClient()
        backend.remote?.onSessionExpired = { [weak backend] in backend?.signOutLocally() }
        // 推送：拿到设备令牌就报给服务器（没登录时先记着，登录后再报）
        PushRegistry.shared.onToken = { [weak backend] _ in Task { await backend?.remoteRegisterPush() } }
        Task { await PushRegistry.shared.refresh() }
        return AppEnvironment(backend: backend)
    }

    /// 演示模式：本机模拟的球友和球局，所有功能都能用；第一次打开时直接用演示账号进入
    static func makeDemo() -> AppEnvironment {
        let backend = MockBackend.shared
        if backend.currentUser == nil && backend.db.accounts.isEmpty {
            backend.createAccount(phone: "+16265550123", nickname: MockBackend.demoNickname, gender: .male, avatar: Avatar(symbol: "", paletteIndex: 4), level: 4,
                                  preferredMode: .doubles, location: Coordinate.fallbackCenter)
        }
        return AppEnvironment(backend: backend)
    }
}

/// 演示模式开关：只有管理员能在设置里打开，其他人一直用正式后端。
/// 开发时也可以用启动参数 `-BBDemo YES` 直接进入
enum DemoMode {
    private static let key = "BBDemo"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// 持有当前这套环境。打开或关闭演示模式时整套换掉：
/// 界面从头重建，旧管理器的后台循环（都是弱引用）随旧对象释放而停止
@MainActor
final class AppHost: ObservableObject {
    @Published private(set) var environment: AppEnvironment
    /// 每换一次环境加一，用作根视图的 id
    private(set) var generation = 0

    init() {
        environment = AppEnvironment.makeForLaunch()
    }

    func setDemoMode(_ isOn: Bool) {
        guard DemoMode.isEnabled != isOn else { return }
        DemoMode.isEnabled = isOn
        generation += 1
        environment = isOn ? .makeDemo() : .makeLive()
    }
}
