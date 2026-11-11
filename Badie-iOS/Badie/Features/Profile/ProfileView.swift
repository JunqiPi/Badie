import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var showRadius = false
    @State private var showFriendLink = false
    @State private var showHelp = false
    @State private var showTips = false
    @State private var showsSupport = false
    @State private var showReputation = false

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
                        todoPills(user)
                        identityCard(user)
                        statsRow(user)
                        menuCard(user)
                        moreCard
                        supportCard
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.tabBarClearance)
        }
            .refreshesEverything()
        .sheet(isPresented: $showRadius) {
            TravelRadiusSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
                .presentationDragIndicator(.visible)
        }
        .task { showsSupport = await TipJar.isAvailable() }
        .sheet(isPresented: $showTips) {
            TipJarSheet()
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFriendLink) {
            FriendLinkSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showReputation) {
            ReputationSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 待处理（没定级、爽约）

    @ViewBuilder
    private func todoPills(_ user: User) -> some View {
        let strikes: MyStrikes? = appState.strikes.flatMap { ($0.recent > 0 || $0.suspendedUntil != nil) ? $0 : nil }
        if user.needsAssessment || strikes != nil {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                if user.needsAssessment {
                    CountPill(icon: "checklist", title: String(localized: "去定级"), count: 0) {
                        router.open(.editProfile)
                    }
                }
                if let strikes {
                    CountPill(icon: "exclamationmark.triangle.fill",
                              title: strikes.suspendedUntil?.suspensionText ?? String(localized: "爽约"),
                              count: strikes.suspendedUntil == nil ? strikes.recent : 0) {
                        appState.showsStrikes = true
                    }
                }
            }
        }
    }

    // MARK: Identity

    /// 整张卡点进编辑资料
    private func identityCard(_ user: User) -> some View {
        Button { router.open(.editProfile) } label: {
            HStack(spacing: AppTheme.Spacing.lg) {
                MyAvatarView(size: 64)
                    .background(Circle().fill(Color(hex: 0x17140F)).offset(x: 3, y: 4))
                    .overlay(alignment: .bottomTrailing) {
                        if user.avatar.photoVersion == nil { CameraBadge().scaleEffect(0.7) }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    FlowLayout(spacing: 6) {
                        LevelBadge(tier: user.displayTier)
                        if user.isReliable { ReliableBadge() }
                        if user.isNewPlayer { NewPlayerBadge() }
                        VerifiedBadge(status: user.verificationStatus)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(AppTheme.Colors.lavender, padding: AppTheme.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(Text("编辑资料"))
    }

    // MARK: 三个数字：场次 / 到场 / 胜率

    private func statsRow(_ user: User) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            StatTile(value: "\(user.totalGames)", label: String(localized: "场次"))
            StatTile(value: "\(user.attendance.reliabilityPercentage)%", label: String(localized: "到场"))
            winRateTile(user)
        }
    }

    /// 本月胜率：场数不够时显示“–”；怎么算、赢输几局都在“?”里
    private func winRateTile(_ user: User) -> some View {
        let month = Rankings.month(containing: Date())
        let rate = appState.backend.winRate(for: user.id, month: month)
        let previous = appState.backend.winRate(for: user.id, month: Rankings.month(containing: month.start.addingTimeInterval(-86400)))
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: rate.isPublic ? "\(rate.percentage)%" : "–")
                .scaledFont(size: 24, relativeTo: .title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 0) {
                Text("胜率")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                RulesButton(title: String(localized: "本月胜率"), points: winRatePoints(rate, previous: previous))
                    .padding(.vertical, -8)
                    .padding(.horizontal, -4)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func winRatePoints(_ rate: Rankings.WinRate, previous: Rankings.WinRate) -> [String] {
        var points: [String] = []
        if rate.isPublic {
            points.append(String(localized: "赢 \(rate.wonRounds) 局 · 输 \(rate.playedRounds - rate.wonRounds) 局"))
        } else {
            points.append(String(localized: "本月已确认 \(rate.games) 场，满 \(Rankings.winRateMinimumGames) 场显示胜率"))
        }
        if rate.games > 0 {
            points.append(String(localized: "\(rate.games) 场 · \(rate.opponents) 位不同对手 · \(opponentStrengthText(rate.averageGap))"))
        }
        if previous.isPublic {
            points.append(String(localized: "上月 \(previous.percentage)%"))
        }
        points.append(String(localized: "只算双方都确认的比赛，每月 1 日重新计算；同一对手每月最多计入 \(Rankings.monthlySameOpponentCap) 场"))
        return points
    }

    private func opponentStrengthText(_ gap: Double) -> String {
        let levels = String(format: "%.1f", abs(gap))
        if gap > 0.3 { return String(localized: "对手平均比你强 \(levels) 级") }
        if gap < -0.3 { return String(localized: "对手平均比你弱 \(levels) 级") }
        return String(localized: "对手和你水平相当")
    }

    // MARK: Menu

    private func menuCard(_ user: User) -> some View {
        let evaluations = user.reputation.evaluationCount
        return VStack(spacing: 0) {
            MenuRow(icon: "star.fill", tint: AppTheme.Colors.lime, title: String(localized: "口碑"),
                    value: evaluations == 0 ? nil : String(localized: "\(evaluations) 次评价")) {
                showReputation = true
            }
            InsetDivider()
            MenuRow(icon: "person.2.fill", tint: AppTheme.Colors.sky, title: String(localized: "我的球友"),
                    value: "\(friendManager.friends.count)", badge: friendManager.incomingRequests.count) {
                router.open(.friends)
            }
            InsetDivider()
            MenuRow(icon: "trophy.fill", tint: AppTheme.Colors.butter, title: String(localized: "排行榜")) {
                router.open(.leaderboard)
            }
            let incomingChallenges = appState.backend.challenges().filter { $0.targetId == user.id && $0.status == .pending }.count
            if incomingChallenges > 0 {
                InsetDivider()
                MenuRow(icon: "flag.2.crossed.fill", tint: AppTheme.Colors.pink, title: String(localized: "挑战"),
                        badge: incomingChallenges) {
                    router.open(.challenges)
                }
            }
            if user.friendLink != nil {
                InsetDivider()
                MenuRow(icon: "qrcode", tint: AppTheme.Colors.peach, title: String(localized: "加球友链接")) {
                    showFriendLink = true
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private var moreCard: some View {
        VStack(spacing: 0) {
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
            MenuRow(icon: "location.circle.fill", tint: AppTheme.Colors.sky, title: String(localized: "附近范围"),
                    value: DistanceFormatter.radius(km: locationManager.preferences.travelRadiusKm)) {
                showRadius = true
            }
            InsetDivider()
            MenuRow(icon: "heart.fill", tint: AppTheme.Colors.pink, title: String(localized: "球馆与收藏"),
                    value: "\(locationManager.favoriteCourtIds.count)") {
                router.open(.courts)
            }
            InsetDivider()
            MenuRow(icon: "list.number", tint: AppTheme.Colors.lime, title: String(localized: "等级对照表")) {
                router.open(.levelGuide)
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

    private var supportCard: some View {
        VStack(spacing: 0) {
            MenuRow(icon: "questionmark.bubble.fill", tint: AppTheme.Colors.mint, title: String(localized: "帮助与反馈")) {
                showHelp = true
            }
            if showsSupport {
                InsetDivider()
                MenuRow(icon: "cup.and.saucer.fill", tint: AppTheme.Colors.pink, title: String(localized: "支持 Badie")) {
                    showTips = true
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }
}

// MARK: - 我的口碑（“我的”页的一行点进来）

/// 本人看到客观记录（准时、水平校准、履约）和别人看到的印象；球品分对任何人都不显示
private struct ReputationSheet: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            if let user = appState.currentUser {
                content(user)
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.top, AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func content(_ user: User) -> some View {
        let reputation = user.reputation
        let record = user.attendance
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("我的口碑")
                    .font(AppTheme.Typography.title2)
                    .accessibilityAddTraits(.isHeader)
                RulesButton(title: String(localized: "口碑怎么算"), points: points(user))
                Spacer(minLength: 0)
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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("球友眼中的你")
                    .font(AppTheme.Typography.subheadlineBold)
                PraiseTagsView(tags: reputation.publicTags, emptyText: String(localized: "暂无印象"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(shadow: .zero)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if user.isNewPlayer {
                    Text("水平校准中 \(reputation.evaluationCount)/\(ReputationScore.newPlayerThreshold)")
                        .font(AppTheme.Typography.subheadlineBold)
                    ProgressBar(progress: Double(reputation.evaluationCount) / Double(ReputationScore.newPlayerThreshold))
                } else {
                    Text("综合等级 \(user.displayTier.text)")
                        .font(AppTheme.Typography.subheadlineBold)
                    ProgressBar(progress: Double(user.displayTier.index + 1) / Double(SkillTier.count))
                }
            }
            .card(shadow: .zero)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("履约记录 · \(record.standing.title)")
                    .font(AppTheme.Typography.subheadlineBold)
                Text("完成 \(record.gamesPlayed) 场 · 爽约 \(record.noShows) 次 · 临时取消 \(record.lateCancellations) 次")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(shadow: .zero)
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(AppTheme.Colors.ink)
    }

    /// 原来写在卡片上的说明都收到这里
    private func points(_ user: User) -> [String] {
        let reputation = user.reputation
        var points: [String] = [String(localized: "球友印象在 5 位以上球友评价后显示，每月更新一次")]
        if user.isNewPlayer {
            points.append(String(localized: "再打 \(ReputationScore.newPlayerThreshold - reputation.evaluationCount) 场并获得评价后，等级将按“问卷 \(selfPercent(user))% + 球友评价 \(100 - selfPercent(user))%”计算")
                          + (user.peerWeight > User.peerEvaluationWeight ? String(localized: "（你的等级待校准，球友评价占比更高）") : ""))
        } else {
            points.append(String(localized: "\(user.verifiedRating == nil ? String(localized: "问卷") : String(localized: "认证")) \(SkillTier(rating: user.baseRating).text) × \(selfPercent(user))% + 球友评价 \(SkillTier(rating: reputation.peerLevelAverage).text) × \(100 - selfPercent(user))%")
                          + (user.verifiedRating == nil ? "" : String(localized: "，不超过认证档位")))
        }
        points.append(user.attendance.standing.message)
        points.append(String(localized: "球品评分只用于匹配排序，任何人（包括你自己）都看不到分数"))
        return points
    }

    private func selfPercent(_ user: User) -> Int {
        Int(((1 - user.peerWeight) * 100).rounded())
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
