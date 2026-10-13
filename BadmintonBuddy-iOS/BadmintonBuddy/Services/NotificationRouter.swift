import Foundation
import UserNotifications

/// 处理本地通知：前台也展示提醒；点按提醒打开对应球局
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
        guard let gameId = response.notification.request.content.userInfo["gameId"] as? String else { return }
        await MainActor.run {
            self.router?.show(.game(id: gameId), in: .games)
        }
    }
}
