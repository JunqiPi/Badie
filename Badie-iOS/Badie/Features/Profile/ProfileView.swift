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
                LargeTitleHeader(title: String(localized: "我的")) {
                    IconButton(systemName: "gearshape.fill", accessibilityLabel: String(localized: "设置")) {
                        router.open(.settings)
                    }
                }
                if let user = appState.currentUser {
                    Group {
                        if user.needsAssessment {
                            NoticeBanner(icon: "checklist",
                                         text: String(localized: "还没定级，现在暂按 Lv.\(SkillAssessment.provisionalLevel) 匹配"),
                                         actionTitle: String(localized: "去定级")) { router.open(.editProfile) }
                        }
                        identityCard(user)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            StatTile(value: "\(user.totalGames)", label: String(localized: "场次"))
                            StatTile(value: "\(Int(user.winRate.rounded()))%", label: String(localized: "胜率"))
                            StatTile(value: "\(user.attendance.reliabilityPercentage)%", label: String(localized: "履约率"))
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
                        LevelBadge(tier: user.displayTier)
                        if user.isReliable { ReliableBadge() }
                        if user.isNewPlayer { NewPlayerBadge() }
                        VerifiedBadge(status: user.verificationStatus)
                        if let mode = user.preferredMode {
                            TagPill(text: String(localized: "偏好\(mode.title)"), fill: .white)
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

    /// 本人看到客观记录（准时、水平校准）和别人看到的印象；球品分对任何人都不显示
    private func reputationCard(_ user: User) -> some View {
        let reputation = user.reputation
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("我的口碑")
                    .font(AppTheme.Typography.headline)
                Spacer()
                Text(reputation.evaluationCount == 0 ? String(localized: "还没有评价") : String(localized: "\(reputation.evaluationCount) 次匿名评价"))
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            if reputation.evaluationCount > 0 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    StatTile(value: reputation.punctualityText, label: String(localized: "准时到场"))
                    StatTile(value: reputation.deviationText, label: String(localized: "等级偏差"))
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("球友眼中的你")
                    .font(AppTheme.Typography.subheadlineBold)
                PraiseTagsView(tags: reputation.publicTags, emptyText: String(localized: "5 位以上球友评价后显示，每月更新一次"))
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if user.isNewPlayer {
                    Text("水平校准中 \(reputation.evaluationCount)/\(ReputationScore.newPlayerThreshold)")
                        .font(AppTheme.Typography.subheadlineBold)
                    ProgressBar(progress: Double(reputation.evaluationCount) / Double(ReputationScore.newPlayerThreshold))
                    Text(String(localized: "再打 \(ReputationScore.newPlayerThreshold - reputation.evaluationCount) 场并获得评价后，等级将按“问卷 \(selfPercent(user))% + 球友评价 \(100 - selfPercent(user))%”计算")
                         + (user.peerWeight > User.peerEvaluationWeight ? String(localized: "（你的等级待校准，球友评价占比更高）") : ""))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("综合等级 \(user.displayTier.text)")
                        .font(AppTheme.Typography.subheadlineBold)
                    ProgressBar(progress: Double(user.displayTier.index + 1) / Double(SkillTier.count))
                    Text(String(localized: "\(user.verifiedRating == nil ? String(localized: "问卷") : String(localized: "认证")) \(SkillTier(rating: user.baseRating).text) × \(selfPercent(user))% + 球友评价 \(SkillTier(rating: reputation.peerLevelAverage).text) × \(100 - selfPercent(user))%")
                         + (user.verifiedRating == nil ? "" : String(localized: "，不超过认证档位")))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            Label("球品评分只用于匹配排序，任何人（包括你自己）都看不到分数", systemImage: "eye.slash.fill")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppTheme.Colors.ink)
        .card()
    }

    private func selfPercent(_ user: User) -> Int {
        Int(((1 - user.peerWeight) * 100).rounded())
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
            MenuRow(icon: "person.2.fill", tint: AppTheme.Colors.lavender, title: String(localized: "我的球友"),
                    value: "\(friendManager.friends.count)", badge: friendManager.incomingRequests.count) {
                router.open(.friends)
            }
            InsetDivider()
            MenuRow(icon: "list.number", tint: AppTheme.Colors.lime, title: String(localized: "等级对照表"),
                    value: user.displayTier.text) {
                router.open(.levelGuide)
            }
            InsetDivider()
            MenuRow(icon: "clock.arrow.circlepath", tint: AppTheme.Colors.peach, title: String(localized: "历史球局"),
                    value: "\(matchManager.pastGames.count)") {
                router.open(.gameHistory)
            }
            InsetDivider()
            MenuRow(icon: "calendar.badge.clock", tint: AppTheme.Colors.butter, title: String(localized: "常用时间"),
                    value: "\(appState.backend.recurringSlots().count)/\(TimeSlotConstants.maximumRecurringSlots)") {
                router.open(.recurringSlots)
            }
            InsetDivider()
            MenuRow(icon: "location.circle.fill", tint: AppTheme.Colors.sky, title: String(localized: "出行范围"),
                    value: DistanceFormatter.radius(km: locationManager.preferences.travelRadiusKm)) {
                showRadius = true
            }
            InsetDivider()
            MenuRow(icon: "heart.fill", tint: AppTheme.Colors.pink, title: String(localized: "球馆与收藏"),
                    value: "\(locationManager.favoriteCourtIds.count)") {
                router.open(.courts)
            }
            InsetDivider()
            MenuRow(icon: "hand.raised.fill", tint: AppTheme.Colors.surfaceMuted, title: String(localized: "屏蔽名单"),
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

struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.Colors.surfaceMuted)
                Capsule()
                    .fill(AppTheme.Colors.lime)
                    .frame(width: max(12, proxy.size.width * CGFloat(min(max(progress, 0), 1))))
                Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
    }
}
