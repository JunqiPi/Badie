import SwiftUI

/// 全屏匹配流程：搜索中 → 找到搭子 / 没找到（给出放宽建议）
struct MatchFlowView: View {
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @State private var presentedPlayer: PlayerSheetItem?

    var body: some View {
        ZStack {
            switch matchManager.phase {
            case .searching, .idle:
                SearchingView()
                    .transition(.opacity)
            case .results:
                if let proposal = matchManager.currentProposal {
                    MatchFoundView(proposal: proposal, presentedPlayer: $presentedPlayer)
                        .id(proposal.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            case .empty:
                NoMatchView()
                    .transition(.opacity)
            case .failed(let message):
                failure(message)
            }
        }
        .animation(AppTheme.Motion.standard, value: matchManager.phase)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(item: $presentedPlayer) { item in
            PlayerProfileSheet(userId: item.id, allowsInvite: false)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            EmptyStateView(icon: "exclamationmark.triangle.fill", title: "匹配没有完成", message: message, tint: AppTheme.Colors.pink)
            Spacer()
            Button("返回") { matchManager.cancelSearch() }
                .buttonStyle(.brutalSecondary)
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
        }
    }
}

// MARK: - 搜索中

struct SearchingView: View {
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false
    @State private var rotation = 0.0
    @State private var statusIndex = 0
    @State private var orbiters: [User] = []

    private var statuses: [String] {
        let draft = matchManager.draft
        return [
            "正在查看 \(draft.courtIds.count) 个球馆附近的球友…",
            "筛选 \(draft.skillTolerance >= MatchRequest.anySkill ? "所有水平" : "水平 ±\(draft.skillTolerance) 级") 的球友…",
            "比对你们都有空的时间…",
            "优先推荐准时率高的球友…"
        ]
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            HStack {
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "取消匹配") {
                    matchManager.cancelSearch()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)

            Spacer(minLength: 0)

            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Color(hex: 0x17140F).opacity(0.5), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulse ? 2.1 : 0.9)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(ring) * 0.7),
                            value: pulse
                        )
                }
                ForEach(Array(orbiters.prefix(6).enumerated()), id: \.element.id) { index, user in
                    let angle = Double(index) / 6 * 2 * .pi + rotation
                    AvatarView(user: user, size: 40)
                        .offset(x: CGFloat(cos(angle)) * 120, y: CGFloat(sin(angle)) * 120)
                }
                MyAvatarView(size: 96)
                    .background(Circle().fill(Color(hex: 0x17140F)).offset(x: 3, y: 4))
            }
            .frame(height: 300)
            .accessibilityHidden(true)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("正在找搭子")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                Text(statuses[statusIndex % statuses.count])
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .id(statusIndex)
                    .transition(.opacity)
                if let slot = matchManager.draft.slot {
                    HStack(spacing: 6) {
                        TagPill(text: matchManager.draft.mode.title, icon: matchManager.draft.mode.icon, fill: .white)
                        TagPill(text: slot.formattedFull, icon: "clock.fill", fill: .white)
                    }
                    .padding(.top, AppTheme.Spacing.xs)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button("取消匹配") { matchManager.cancelSearch() }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium, fullWidth: false))
                .padding(.bottom, AppTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.lime.ignoresSafeArea())
        .onAppear {
            orbiters = friendManager.nearbyPlayers(radiusKm: locationManager.preferences.travelRadiusKm, limit: 6)
            pulse = true
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if !reduceMotion { rotation += 0.012 }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation(AppTheme.Motion.gentle) { statusIndex += 1 }
            }
        }
    }
}

// MARK: - 找到搭子

struct MatchFoundView: View {
    let proposal: MatchProposal
    @Binding var presentedPlayer: PlayerSheetItem?

    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var collided = false
    @State private var showDetails = false
    @State private var confirmedGame: Game?

    private var me: User? { appState.currentUser }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") {
                    matchManager.cancelSearch()
                }
                Spacer()
                Text("\(proposal.mode.title) · 匹配度 \(proposal.compatibility)%")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.sm)

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    (Text(confirmedGame == nil ? "找到" : "约好") + Text(markedText: "搭子") + Text("了！"))
                        .font(AppTheme.Typography.display)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .padding(.top, AppTheme.Spacing.md)
                        .accessibilityAddTraits(.isHeader)

                    collisionStage
                        .frame(height: proposal.mode == .doubles ? 250 : 210)

                    if showDetails {
                        details
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }

            if showDetails {
                actions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear(perform: animateIn)
    }

    // MARK: Collision animation

    private var collisionStage: some View {
        ZStack {
            if proposal.mode == .singles, let me, let opponent = proposal.primary?.user {
                playerCard(me, title: "我", fill: AppTheme.Colors.surface)
                    .rotationEffect(.degrees(collided ? -7 : -20))
                    .offset(x: collided ? -82 : -260, y: 0)
                Button {
                    presentedPlayer = PlayerSheetItem(id: opponent.id)
                } label: {
                    playerCard(opponent, title: opponent.nickname, fill: AppTheme.Colors.lime)
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(collided ? 7 : 20))
                .offset(x: collided ? 82 : 260, y: 0)
                .accessibilityHint("查看对方资料")
                StarburstBadge(text: "VS", size: 76)
                    .scaleEffect(collided ? 1 : 0.1)
                    .opacity(collided ? 1 : 0)
                    .offset(y: 66)
            } else if let me {
                doublesStage(me: me)
            }
        }
    }

    private func doublesStage(me: User) -> some View {
        let lookup = Dictionary(uniqueKeysWithValues: ([me] + proposal.others.map(\.user)).map { ($0.id, $0) })
        let teams = proposal.teams.map { $0.compactMap { lookup[$0] } }
        return HStack(spacing: AppTheme.Spacing.md) {
            ForEach(Array(teams.enumerated()), id: \.offset) { index, team in
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(team) { user in
                        Button {
                            if user.id != me.id { presentedPlayer = PlayerSheetItem(id: user.id) }
                        } label: {
                            miniPlayerCard(user, isMe: user.id == me.id, fill: index == 0 ? AppTheme.Colors.lavender : AppTheme.Colors.lime)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .rotationEffect(.degrees(collided ? (index == 0 ? -4 : 4) : 0))
                .offset(x: collided ? 0 : (index == 0 ? -240 : 240))
                if index == 0 {
                    StarburstBadge(text: "VS", size: 64)
                        .scaleEffect(collided ? 1 : 0.1)
                        .opacity(collided ? 1 : 0)
                }
            }
        }
    }

    private func playerCard(_ user: User, title: String, fill: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            AvatarView(user: user, size: 60, image: user.id == me?.id ? AvatarStore.image(for: user.id) : nil)
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.onAccent)
                .lineLimit(1)
            LevelBadge(level: user.displayLevel)
        }
        .frame(width: 140, height: 170)
        .sticker(fill, radius: 22)
        .environment(\.colorScheme, .light)
    }

    private func miniPlayerCard(_ user: User, isMe: Bool, fill: Color) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            AvatarView(user: user, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "我" : user.nickname)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .lineLimit(1)
                LevelBadge(level: user.displayLevel, showsName: false, compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.sm)
        .frame(width: 132)
        .sticker(fill, radius: 16, shadow: AppTheme.Elevation.low)
    }

    // MARK: Details

    private var details: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            if let candidate = proposal.primary {
                reputationRow(candidate)
            }
            VStack(spacing: 0) {
                InfoRow(icon: "clock.fill", tint: AppTheme.Colors.peach,
                        title: proposal.slot.formattedFull,
                        subtitle: proposal.commonOverlap.duration > proposal.slot.duration
                            ? "你们共同有空 \(proposal.commonOverlap.formattedTimeRange)，已安排 \(proposal.slot.formattedDuration)"
                            : "你们都有空的 \(proposal.slot.formattedDuration)")
                InsetDivider()
                InfoRow(icon: "mappin.and.ellipse", tint: AppTheme.Colors.sky,
                        title: proposal.court.name,
                        subtitle: "\(proposal.court.formattedCourtCount) · \(proposal.court.operatingHours.formattedTimeRange)")
                InsetDivider()
                InfoRow(icon: "yensign.circle.fill", tint: AppTheme.Colors.butter,
                        title: "AA 约 ¥\(proposal.cost.perPerson) / 人",
                        subtitle: proposal.cost.breakdownText)
                if proposal.mode == .doubles {
                    InsetDivider()
                    InfoRow(icon: "person.2.fill", tint: AppTheme.Colors.lavender,
                            title: "已按水平平衡分队",
                            subtitle: "两队平均等级差不超过 1 级")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        }
    }

    private func reputationRow(_ candidate: MatchCandidate) -> some View {
        let reputation = candidate.user.reputation
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text(candidate.user.nickname)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text("\(candidate.formattedSkillDifference) · \(DistanceFormatter.string(km: candidate.distanceKm))")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                if candidate.user.isNewPlayer { NewPlayerBadge() }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                StatTile(value: reputation.punctualityText, label: "准时率")
                StatTile(value: reputation.characterText, label: "球品 ★")
                StatTile(value: "\(candidate.user.attendance.reliabilityPercentage)%", label: "履约率")
            }
            Text(candidate.user.isNewPlayer
                 ? "评价不足 5 次，等级为自评，仅供参考"
                 : "基于 \(reputation.evaluationCount) 位球友的匿名评价")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let game = confirmedGame {
                Button {
                    matchManager.finishFlow()
                    router.show(.game(id: game.id), in: .games)
                } label: {
                    Label("查看球局", systemImage: "ticket.fill")
                }
                .buttonStyle(.brutalPrimary)
                if let opponent = proposal.primary?.user {
                    Button("给 \(opponent.nickname) 发消息") {
                        matchManager.finishFlow()
                        router.show(.chat(userId: opponent.id), in: .messages)
                    }
                    .buttonStyle(TextActionStyle())
                }
            } else {
                HStack(spacing: AppTheme.Spacing.md) {
                    Button("换一个") {
                        Haptics.tap()
                        matchManager.declineCurrent()
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: false))
                    .frame(width: 120)
                    .accessibilityHint("跳过这个方案，看看其他球友")

                    Button {
                        Task {
                            if let game = await matchManager.confirmCurrent() {
                                Haptics.success()
                                withAnimation(AppTheme.Motion.bouncy) { confirmedGame = game }
                            }
                        }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            if matchManager.isConfirming { LoadingDots() }
                            Text("确认约球")
                        }
                    }
                    .buttonStyle(.brutalPrimary)
                    .disabled(matchManager.isConfirming)
                }
                Text("确认后会通知对方，开赛前 2 小时内取消将计入履约记录")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
    }

    private func animateIn() {
        if reduceMotion {
            collided = true
            showDetails = true
            return
        }
        withAnimation(.easeOut(duration: AppTheme.Motion.collision)) {
            collided = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(AppTheme.Motion.collision * 1_000_000_000))
            Haptics.impact()
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(AppTheme.Motion.standard) { showDetails = true }
        }
    }
}

// MARK: - 没有找到

struct NoMatchView: View {
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            HStack {
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") { matchManager.cancelSearch() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("这个时间段\n暂时没有合适的搭子")
                            .font(AppTheme.Typography.title)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("我们算过了，下面这些调整能找到人：")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                    if matchManager.suggestions.isEmpty {
                        NoticeBanner(icon: "lightbulb.fill", text: "附近球友这几天都比较忙，试试发起公开球局，让大家来找你。")
                    } else {
                        VStack(spacing: AppTheme.Spacing.md) {
                            ForEach(matchManager.suggestions) { suggestion in
                                Button {
                                    Haptics.tap()
                                    matchManager.apply(suggestion)
                                } label: {
                                    HStack(spacing: AppTheme.Spacing.md) {
                                        IconTile(systemName: suggestion.icon, fill: AppTheme.Colors.lime, size: 44)
                                        Text(suggestion.title)
                                            .font(AppTheme.Typography.headline)
                                            .foregroundStyle(AppTheme.Colors.ink)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 15, weight: .heavy))
                                            .foregroundStyle(AppTheme.Colors.ink)
                                    }
                                    .padding(AppTheme.Spacing.lg)
                                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("或者")
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                        Button {
                            matchManager.cancelSearch()
                            router.open(.createRoom(matchManager.draft.mode, invitee: nil), in: .games)
                        } label: {
                            ArrowButtonLabel(title: "发起公开球局，让球友来找你")
                        }
                        .buttonStyle(.brutalInverse)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
            }
        }
    }
}
