import SwiftUI

/// 全屏看自己的卡片：和别人在首页刷到的一样。时间地点用我下一个约球请求的，没有就用示例
struct MyCardPreview: View {
    let user: User

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我的卡片")
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text("别人刷到你时就是这样")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)

            DayCardView(user: user, details: details)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.screen)

            // 和真卡片一样的两个按钮，预览里按不了
            HStack(spacing: AppTheme.Spacing.xxl) {
                ForEach([("xmark", AppTheme.Colors.surface), ("heart.fill", AppTheme.Colors.lime)], id: \.0) { icon, tint in
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(AppTheme.Colors.ink)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(tint))
                        .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                }
            }
            .opacity(0.35)
            .accessibilityHidden(true)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private var details: DayCardView.Details {
        if let ticket = matchManager.tickets.filter(\.isActive).min(by: { $0.slot.startTime < $1.slot.startTime }) {
            return .init(mode: ticket.mode.title, startsAt: ticket.slot.startTime, endsAt: ticket.slot.endTime,
                         venues: ticket.courtIds.prefix(2).compactMap { appState.backend.venue(id: $0)?.name })
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .hour, value: 19, to: today) ?? today
        return .init(mode: (user.preferredMode ?? .singles).title, startsAt: start, endsAt: start.addingTimeInterval(2 * 3600),
                     venues: [String(localized: "附近的球馆")])
    }
}
