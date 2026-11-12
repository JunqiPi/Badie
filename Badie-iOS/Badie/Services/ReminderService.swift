import Foundation
import UserNotifications

/// 球局本地提醒：开赛前 1 天、2 小时、15 分钟（多次提醒能显著降低爽约率）
@MainActor
enum ReminderService {
    private static let offsets: [(id: String, seconds: TimeInterval, title: String)] = [
        ("1d", 24 * 3600, String(localized: "明天有球局")),
        ("2h", 2 * 3600, String(localized: "2 小时后开打")),
        ("15m", 15 * 60, String(localized: "快到了，记得签到"))
    ]

    static func requestAuthorization() async -> Bool {
        #if DEBUG
        // 截图、设计走查（-BBDemoScreen 启动）不弹通知权限框，免得挡住画面
        if UserDefaults.standard.string(forKey: "BBDemoScreen") != nil { return false }
        #endif
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// 为球局安排提醒，返回实际安排的条数
    @discardableResult
    static func schedule(for game: Game, now: Date = Date()) async -> Int {
        guard await requestAuthorization() else { return 0 }
        cancel(gameId: game.id)
        let center = UNUserNotificationCenter.current()
        var count = 0
        for offset in offsets {
            let fireDate = game.slot.startTime.addingTimeInterval(-offset.seconds)
            let interval = fireDate.timeIntervalSince(now)
            guard interval > 5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = offset.title
            content.body = "\(game.slot.formattedFull) · \(game.court.name)"
            content.sound = .default
            content.userInfo = ["gameId": game.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: identifier(game.id, offset.id), content: content, trigger: trigger)
            if (try? await center.add(request)) != nil {
                count += 1
            }
        }
        return count
    }

    /// 开始时间变了（没定时间的球局定好了）：之前开着提醒的按新时间重排；没开过的不动，也不弹授权
    static func rescheduleIfPending(for game: Game) async {
        let ids = Set(offsets.map { identifier(game.id, $0.id) })
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard pending.contains(where: { ids.contains($0.identifier) }) else { return }
        await schedule(for: game)
    }

    static func cancel(gameId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: offsets.map { identifier(gameId, $0.id) }
        )
    }

    private static func identifier(_ gameId: String, _ suffix: String) -> String {
        "game-\(gameId)-\(suffix)"
    }
}
