import SwiftUI

/// 我自己的卡片：和发现页“附近的人”同一张卡（常去的球馆、空闲时间）。
/// “我的”页上不写距离；预览里写我到常去球馆的距离，和别人刷到时一样
struct MyCard: View {
    let user: User
    let slots: [RecurringTimeSlot]
    var showsDistance = false
    var onTap: (() -> Void)?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        NearbyCardView(user: user, card: card, onProfile: onTap)
    }

    private var card: MockBackend.NearbyPlayer {
        let venues = locationManager.favoriteCourts.prefix(1).map { court in
            MockBackend.DayCandidate.Venue(id: court.id, name: court.name,
                                           km: showsDistance ? court.distance(from: locationManager.coordinate) : nil)
        }
        return MockBackend.NearbyPlayer(userId: user.id, recentNoShows: appState.strikes?.recent ?? 0,
                                        preferredMode: user.preferredMode, venues: venues, sharedVenues: 0,
                                        usualTimes: slots.activeSlots)
    }
}

/// 别人在发现页刷到我时看到的样子：卡片 + 下面三个按不了的按钮 + 一句话
struct MyCardPreviewContent: View {
    let user: User
    let slots: [RecurringTimeSlot]

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            MyCard(user: user, slots: slots, showsDistance: true)
                .frame(maxHeight: .infinity)
            // 和真卡片一样的三个按钮，预览里按不了
            HStack(spacing: AppTheme.Spacing.xl) {
                RoundActionLabel(icon: "xmark", tint: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
                RoundActionLabel(icon: "heart.fill", tint: AppTheme.Colors.lime, size: 80)
                RoundActionLabel(icon: "star.fill", tint: AppTheme.Colors.butter)
            }
            .opacity(0.35)
            .accessibilityHidden(true)
            Text("别人在首页刷到你时，看到的就是这张卡片")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// 全屏看自己的卡片（“我的”页点卡片）
struct MyCardPreview: View {
    let user: User
    let slots: [RecurringTimeSlot]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                Text("我的卡片")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.top, AppTheme.Spacing.md)
            MyCardPreviewContent(user: user, slots: slots)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
