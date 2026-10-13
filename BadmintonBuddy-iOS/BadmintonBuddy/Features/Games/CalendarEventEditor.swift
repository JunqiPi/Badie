import SwiftUI
import EventKit
import EventKitUI

/// 系统“添加日程”编辑页（iOS 17 起由系统进程展示，无需日历读取权限）
struct CalendarEventEditor: UIViewControllerRepresentable {
    let game: Game
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "🏸 \(game.mode.title)球局"
        event.startDate = game.slot.startTime
        event.endDate = game.slot.endTime
        event.location = "\(game.court.name) \(game.court.address)"
        event.notes = game.shareText
        event.addAlarm(EKAlarm(relativeOffset: -2 * 3600))
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish()
        }
    }
}
