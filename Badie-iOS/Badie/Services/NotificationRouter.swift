import Foundation
import UserNotifications

/// 处理通知（本地提醒和服务器推送）：前台也展示；点了打开对应页面
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    weak var router: Router?
    weak var messages: MessageManager?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // 新消息：不等定时刷新，马上拉会话列表和正开着的会话；正开着这个会话就不再弹
        if let link = notification.request.content.userInfo["link"] as? String, link.contains("/messages/") {
            await MainActor.run { messages?.refreshNow() }
            let route = PushRegistry.route(for: link).route
            if await MainActor.run(body: { router?.isShowing(route) ?? false }) { return [] }
        }
        return [.banner, .sound, .list]
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
