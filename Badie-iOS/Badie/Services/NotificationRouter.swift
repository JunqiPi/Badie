import Foundation
import UserNotifications

/// 处理通知（本地提醒和服务器推送）：前台也展示；点了打开对应页面
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    weak var router: Router?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        // 本地提醒带 gameId；服务器推送带 link（和网页同一个地址）
        let target: (route: Route, tab: MainTab)
        if let gameId = info["gameId"] as? String {
            target = (.game(id: gameId), .games)
        } else if let link = info["link"] as? String {
            target = PushRegistry.route(for: link)
        } else {
            return
        }
        await MainActor.run {
            self.router?.show(target.route, in: target.tab)
        }
    }
}
