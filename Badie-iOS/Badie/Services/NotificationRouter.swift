import Foundation
import UserNotifications

/// 处理通知（本地提醒和服务器推送）：前台也展示；点了打开对应页面
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    private weak var router: Router?
    private weak var messages: MessageManager?
    /// 冷启动时点的通知比界面先到：先记下，界面好了再打开
    private var pending: (route: Route, tab: MainTab)?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    @MainActor
    func attach(router: Router, messages: MessageManager) {
        self.router = router
        self.messages = messages
        if let pending {
            router.show(pending.route, in: pending.tab)
            self.pending = nil
        }
    }

    // 用完成回调的写法并在主线程回调：async 写法会在后台线程结束，点通知时直接崩溃

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let link = notification.request.content.userInfo["link"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // 新消息：马上拉会话列表和正开着的会话；正开着这个会话就不再弹
                if let link, link.contains("/messages/") {
                    self.messages?.refreshNow()
                    if self.router?.isShowing(PushRegistry.route(for: link).route) == true {
                        return completionHandler([])
                    }
                }
                completionHandler([.banner, .sound, .list])
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        // 本地提醒带 gameId；服务器推送带 link（和网页同一个地址）
        var target: (route: Route, tab: MainTab)?
        if let gameId = info["gameId"] as? String {
            target = (.game(id: gameId), .games)
        } else if let link = info["link"] as? String {
            target = PushRegistry.route(for: link)
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let target {
                    if let router = self.router { router.show(target.route, in: target.tab) } else { self.pending = target }
                }
                completionHandler()
            }
        }
    }
}
