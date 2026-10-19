import SwiftUI

@main
@MainActor
struct BadieApp: App {
    @StateObject private var host = AppHost()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            let environment = host.environment
            RootView()
                .environmentObject(host)
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
                // 换了环境就从头建界面，不留旧环境的页面和状态
                .id(host.generation)
        }
    }
}
