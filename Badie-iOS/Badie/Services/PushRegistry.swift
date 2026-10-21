import UIKit
import UserNotifications

/// 苹果推送（APNs，免费）：允许了通知就向苹果要这台设备的令牌，登录状态下交给服务器。
/// 服务器有新通知时推过来（约球提醒主要靠它；邮件要用户自己在设置里打开）
@MainActor
final class PushRegistry {
    static let shared = PushRegistry()

    /// 设备令牌（十六进制）；每次启动苹果都会给，可能会变
    private(set) var token: String?
    /// 拿到令牌后要做的事（正式后端模式下：报给服务器）
    var onToken: ((String) -> Void)?

    /// 每次启动、登录后：已经允许通知的，重新要一次令牌
    func refresh() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// 发出约球请求后：配上了要第一时间知道。没问过就问一次，拒绝过的不再打扰
    func askAfterRequest() async {
        guard await ReminderService.requestAuthorization() else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        onToken?(hex)
    }

    /// 推送里带的网址（/app/games/<id>/ 这种）和点开的 badie.rsvp 链接（https://badie.rsvp/join/?code=… 这种），
    /// 网页和 App 共用一套地址，对应 App 里的页面
    nonisolated static func route(for link: String) -> (route: Route, tab: MainTab) {
        let components = URLComponents(string: link)
        let parts = (components?.path ?? link).split(separator: "/").map(String.init).filter { $0 != "app" }
        let id = parts.count > 1 ? parts[1] : nil
        switch (parts.first, id) {
        case ("games", let id?): return (.game(id: id), .games)
        case ("rooms", let id?): return (.room(id: id), .games)
        case ("groups", let id?): return (.group(id: id), .games)
        case ("join", _): return (.joinRoom(code: components?.queryItems?.first { $0.name == "code" }?.value), .games)
        case ("challenges", _): return (.challenges, .games)
        default: return (.notifications, .home)
        }
    }
}

/// 苹果把设备令牌交给这里（SwiftUI 的 App 要用 UIApplicationDelegateAdaptor 才收得到）
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistry.shared.didRegister(deviceToken)
    }
}
