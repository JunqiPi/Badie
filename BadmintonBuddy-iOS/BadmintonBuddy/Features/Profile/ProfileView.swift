import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var showRadius = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                LargeTitleHeader(title: "我的") {
                    IconButton(systemName: "gearshape.fill", accessibilityLabel: "设置") {
                        router.open(.settings)
                    }
                }
                if let user = appState.currentUser {
                    Group {
                        identityCard(user)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            StatTile(value: "\(user.totalGames)", label: "场次")
                            StatTile(value: "\(Int(user.winRate.rounded()))%", label: "胜率")
                            StatTile(value: "\(user.attendance.reliabilityPercentage)%", label: "履约率")
                        }
                        reputationCard(user)
                        attendanceCard(user)
                        menuCard(user)
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.tabBarClearance)
        }
        .sheet(isPresented: $showRadius) {
            TravelRadiusSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Identity

    private func identityCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.lg) {
                MyAvatarView(size: 76)
                    .background(Circle().fill(Color(hex: 0x17140F)).offset(x: 3, y: 4))
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.nickname)
                        .font(AppTheme.Typography.title2)
                    Text("ID \(user.shortId) · 加入 \(daysSince(user.joinDate)) 天")
                        .font(AppTheme.Typography.footnoteBold)
                        .opacity(0.7)
                    FlowLayout(spacing: 6) {
                        LevelBadge(level: user.displayLevel)
                        if user.isNewPlayer { NewPlayerBadge() }
                        VerifiedBadge(status: user.verificationStatus)
                        if let mode = user.preferredMode {
                            TagPill(text: "偏好\(mode.title)", fill: .white)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(AppTheme.Typography.subheadline)
            }
            Button("编辑资料") { router.open(.editProfile) }
                .buttonStyle(BrutalButtonStyle(kind: .accent(.white), size: .medium))
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .card(AppTheme.Colors.lavender, padding: AppTheme.Spacing.xl)
    }

    // MARK: Reputation

    private func reputationCard(_ user: User) -> some View {
        let reputation = user.reputation
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("球友口碑")
                    .font(AppTheme.Typography.headline)
                Spacer()
                Text(reputation.evaluationCount == 0 ? "还没有评价" : "\(reputation.evaluationCount) 人匿名评价")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            if reputation.evaluationCount > 0 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    StarsView(rating: reputation.averageCharacterRating, size: 18)
                    Text(reputation.characterText)
                        .scaledFont(size: 22, relativeTo: .title3)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(reputation.compositeScore)")
                            .scaledFont(size: 22, relativeTo: .title3)
                            .monospacedDigit()
                        Text("信誉分")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    StatTile(value: reputation.punctualityText, label: "准时率")
                    StatTile(value: reputation.deviationText, label: "水平偏差")
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if user.isNewPlayer {
                    Text("水平校准中 \(reputation.evaluationCount)/\(ReputationScore.newPlayerThreshold)")
                        .font(AppTheme.Typography.subheadlineBold)
                    ProgressBar(progress: Double(reputation.evaluationCount) / Double(ReputationScore.newPlayerThreshold))
                    Text("再打 \(ReputationScore.newPlayerThreshold - reputation.evaluationCount) 场并获得评价后，等级将按“自评 30% + 球友评价 70%”计算")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: "综合等级 Lv.%.1f", user.calculatedLevel))
                        .font(AppTheme.Typography.subheadlineBold)
                    ProgressBar(progress: user.calculatedLevel / 9)
                    Text("自评 Lv.\(user.selfReportedLevel) × 30% + 球友评价 Lv.\(String(format: "%.1f", reputation.peerLevelAverage)) × 70%")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
        }
        .foregroundStyle(AppTheme.Colors.ink)
        .card()
    }

    private func attendanceCard(_ user: User) -> some View {
        let record = user.attendance
        let standing = record.standing
        return HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            IconTile(systemName: standing == .good ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                     fill: standing == .good ? AppTheme.Colors.mint : AppTheme.Colors.pink, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("履约记录 · \(standing.title)")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text("完成 \(record.gamesPlayed) 场 · 爽约 \(record.noShows) 次 · 临时取消 \(record.lateCancellations) 次")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Text(standing.message)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Menu

    private func menuCard(_ user: User) -> some View {
        VStack(spacing: 0) {
            MenuRow(icon: "person.2.fill", tint: AppTheme.Colors.lavender, title: "我的球友",
                    value: "\(friendManager.friends.count)", badge: friendManager.incomingRequests.count) {
                router.open(.friends)
            }
            InsetDivider()
            MenuRow(icon: "clock.arrow.circlepath", tint: AppTheme.Colors.peach, title: "历史球局",
                    value: "\(matchManager.pastGames.count)") {
                router.open(.gameHistory)
            }
            InsetDivider()
            MenuRow(icon: "calendar.badge.clock", tint: AppTheme.Colors.butter, title: "常用时间",
                    value: "\(appState.backend.recurringSlots().count)/\(TimeSlotConstants.maximumRecurringSlots)") {
                router.open(.recurringSlots)
            }
            InsetDivider()
            MenuRow(icon: "location.circle.fill", tint: AppTheme.Colors.sky, title: "出行范围",
                    value: "\(Int(locationManager.preferences.travelRadiusKm)) 公里") {
                showRadius = true
            }
            InsetDivider()
            MenuRow(icon: "heart.fill", tint: AppTheme.Colors.pink, title: "球馆与收藏",
                    value: "\(locationManager.favoriteCourtIds.count)") {
                router.open(.courts)
            }
            InsetDivider()
            MenuRow(icon: "hand.raised.fill", tint: AppTheme.Colors.surfaceMuted, title: "屏蔽名单",
                    value: "\(messageManager.blockedUsers.count)") {
                router.open(.blockedUsers)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private func daysSince(_ date: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1)
    }
}

/// 进度条（贴纸风格）
struct ProgressBar: View {
    let progress: Double
    var fill: Color = AppTheme.Colors.lime

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.Colors.surfaceMuted)
                Capsule()
                    .fill(fill)
                    .frame(width: max(12, proxy.size.width * CGFloat(min(max(progress, 0), 1))))
                Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
    }
}
