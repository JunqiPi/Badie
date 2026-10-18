import SwiftUI

/// 全屏匹配流程：提交请求 → 挂起等待 / 找到搭子（多方确认）→ 约成；或暂停、结束
struct MatchFlowView: View {
    @EnvironmentObject private var matchManager: MatchManager
    @State private var presentedPlayer: PlayerSheetItem?

    var body: some View {
        ZStack {
            switch matchManager.phase {
            case .submitting:
                SearchingView()
                    .transition(.opacity)
            case .failed(let message):
                failure(message)
            case .idle:
                if let ticket = matchManager.flowTicket {
                    content(for: ticket)
                } else {
                    SearchingView()
                }
            }
        }
        .animation(AppTheme.Motion.standard, value: matchManager.phase)
        .animation(AppTheme.Motion.standard, value: matchManager.flowTicket?.status)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(item: $presentedPlayer) { item in
            PlayerProfileSheet(userId: item.id, allowsInvite: false)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func content(for ticket: MatchTicket) -> some View {
        switch ticket.status {
        case .searching:
            TicketWaitingView(ticket: ticket)
                .transition(.opacity)
        case .offered, .matched:
            if let offer = matchManager.offer(for: ticket) {
                OfferView(ticket: ticket, offer: offer, presentedPlayer: $presentedPlayer)
                    .id(offer.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                TicketWaitingView(ticket: ticket)
            }
        case .paused, .expired, .cancelled:
            TicketEndedView(ticket: ticket)
                .transition(.opacity)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            EmptyStateView(icon: "exclamationmark.triangle.fill", title: String(localized: "没能发起请求"), message: message, tint: AppTheme.Colors.pink)
            Spacer()
            Button("返回") { matchManager.closeFlow() }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false
    @State private var rotation = 0.0
    @State private var statusIndex = 0
    @State private var orbiters: [User] = []

    private var statuses: [String] {
        let draft = matchManager.draft
        let levelText = draft.skillTolerance >= MatchRequest.anySkill
            ? String(localized: "所有水平")
            : String(localized: "水平 ±\(draft.skillTolerance) 级")
        return [
            String(localized: "正在查看 \(draft.courtIds.count) 个球馆附近的球友…"),
            String(localized: "筛选 \(levelText) 的球友…"),
            String(localized: "比对你们都有空的时间…"),
            String(localized: "只匹配也能去这些球馆的球友…")
        ]
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            HStack {
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) {
                    matchManager.closeFlow()
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

            Text("关掉也没关系，请求会在后台继续")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.7))
                .padding(.bottom, AppTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.lime.ignoresSafeArea())
        .onAppear {
            // 装饰用的头像：只用好友和公开了的同馆常客，不展示“附近的陌生人”
            orbiters = Array((friendManager.friends + friendManager.venueRegulars(limit: 6).map(\.user)).prefix(6))
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

// MARK: - 找到搭子：多方确认

/// 一个匹配提议。所有人确认才成局；有人没确认时显示“补位中”，不显示是谁。
struct OfferView: View {
    let ticket: MatchTicket
    let offer: MatchOffer
    @Binding var presentedPlayer: PlayerSheetItem?

    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var collided = false
    @State private var showDetails = false
    @State private var confirmsCancel = false

    private var me: User? { appState.currentUser }
    private var mySeat: MatchOffer.Seat? { offer.seat(of: ticket.userId) }
    private var isMatched: Bool { offer.gameId != nil }
    private var awaitsMe: Bool { offer.isOpen && mySeat?.response == .pending }

    /// 局中其他人（不含已离开的座位）
    private var others: [User] {
        offer.seats.filter { $0.userId != ticket.userId && !$0.isVacant }.compactMap { matchManager.user(id: $0.userId) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { matchManager.closeFlow() }
                Spacer()
                Text("\(offer.mode.title) · 匹配度 \(offer.compatibility)%")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.sm)

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    headline
                        .font(AppTheme.Typography.display)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, AppTheme.Spacing.md)
                        .accessibilityAddTraits(.isHeader)

                    collisionStage
                        .frame(height: offer.mode == .doubles ? 250 : 210)

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
        .confirmationDialog("取消这个约球请求？", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("取消请求", role: .destructive) { matchManager.cancelTicket(ticket.id) }
            Button("再等等", role: .cancel) {}
        } message: {
            Text("还没约成，取消不影响任何记录；其他人会继续帮 TA 们找人。")
        }
    }

    private var headline: Text {
        if isMatched { return Text(marking: String(localized: "约好*搭子*了！")) }
        if awaitsMe { return Text(marking: String(localized: "找到*搭子*了！")) }
        return Text(marking: String(localized: "等*大家*确认"))
    }

    // MARK: Collision animation

    private var collisionStage: some View {
        ZStack {
            if offer.mode == .singles, let me, let opponent = others.first {
                playerCard(me, title: String(localized: "我"), fill: AppTheme.Colors.surface)
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
            } else {
                doublesStage
            }
        }
    }

    private var doublesStage: some View {
        let vacant = Set(offer.seats.filter(\.isVacant).map(\.userId))
        return HStack(spacing: AppTheme.Spacing.md) {
            ForEach(Array(offer.teams.enumerated()), id: \.offset) { index, team in
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(team, id: \.self) { userId in
                        if vacant.contains(userId) {
                            vacantCard
                        } else if let user = matchManager.user(id: userId) {
                            Button {
                                if user.id != ticket.userId { presentedPlayer = PlayerSheetItem(id: user.id) }
                            } label: {
                                miniPlayerCard(user, isMe: user.id == ticket.userId,
                                               fill: index == 0 ? AppTheme.Colors.lavender : AppTheme.Colors.lime)
                            }
                            .buttonStyle(.plain)
                        }
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
            AvatarView(user: user, size: 60, )
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.onAccent)
                .lineLimit(1)
            LevelBadge(tier: user.displayTier)
        }
        .frame(width: 140, height: 170)
        .sticker(fill, radius: 22)
        .environment(\.colorScheme, .light)
    }

    private func miniPlayerCard(_ user: User, isMe: Bool, fill: Color) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            AvatarView(user: user, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? String(localized: "我") : user.nickname)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .lineLimit(1)
                LevelBadge(tier: user.displayTier, showsName: false, compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.sm)
        .frame(width: 132)
        .sticker(fill, radius: 16, shadow: AppTheme.Elevation.low)
    }

    /// 有人这次来不了：只显示“补位中”，不显示是谁
    private var vacantCard: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppTheme.Colors.surfaceMuted))
            Text("补位中…")
                .font(AppTheme.Typography.subheadlineBold)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.Colors.inkSecondary)
        .padding(AppTheme.Spacing.sm)
        .frame(width: 132)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(AppTheme.Colors.inkTertiary))
        .accessibilityLabel("有一个位置正在找人补上")
    }

    // MARK: Details

    private var details: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            if !isMatched {
                confirmationCard
            }
            playersCard
            VStack(spacing: 0) {
                InfoRow(icon: "clock.fill", tint: AppTheme.Colors.peach,
                        title: offer.slot.formattedFull,
                        subtitle: offer.commonOverlap.duration > offer.slot.duration
                            ? String(localized: "你们共同有空 \(offer.commonOverlap.formattedTimeRange)，已安排 \(offer.slot.formattedDuration)")
                            : String(localized: "你们都有空的 \(offer.slot.formattedDuration)"))
                InsetDivider()
                InfoRow(icon: "mappin.and.ellipse", tint: AppTheme.Colors.sky,
                        title: offer.court.name,
                        subtitle: offer.court.address)
                InsetDivider()
                InfoRow(icon: Money.icon(for: offer.cost.currencyCode), tint: AppTheme.Colors.butter,
                        title: offer.cost.perPerson == nil ? String(localized: "费用待定") : String(localized: "AA 约 \(offer.cost.perPersonText)"),
                        subtitle: offer.cost.breakdownText)
                if offer.mode == .doubles {
                    InsetDivider()
                    InfoRow(icon: "person.2.fill", tint: AppTheme.Colors.lavender,
                            title: String(localized: "已按水平平衡分队"),
                            subtitle: String(localized: "两队平均等级差不超过 1 级"))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        }
    }

    /// 确认进度：谁确认了、还在等谁；拒绝/超时的座位只显示“补位中”
    /// 黄底（轮到我确认）上用固定的深色字：深色模式下 ink 是浅色
    private var cardInk: Color { awaitsMe ? AppTheme.Colors.onAccent : AppTheme.Colors.ink }
    private var cardSecondary: Color { awaitsMe ? AppTheme.Colors.onAccent.opacity(0.75) : AppTheme.Colors.inkSecondary }

    private var confirmationCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("确认进度")
                        .font(AppTheme.Typography.headline)
                    Spacer()
                    Text("\(offer.acceptedCount)/\(offer.seats.count) 已确认")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(cardSecondary)
                }
                ForEach(Array(offer.seats.enumerated()), id: \.offset) { _, seat in
                    seatRow(seat)
                }
                Label(deadlineText(now: context.date), systemImage: "clock.badge.exclamationmark.fill")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(awaitsMe ? cardInk : cardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(cardInk)
            .padding(AppTheme.Spacing.lg)
            .sticker(awaitsMe ? AppTheme.Colors.butter : AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        }
    }

    private func deadlineText(now: Date) -> String {
        if awaitsMe, let seat = mySeat {
            return String(localized: "请在\(DateText.deadline(seat.respondBy, now: now))前确认（\(MatchTiming.remainingText(until: seat.respondBy, now: now))）")
        }
        return String(localized: "最晚\(DateText.deadline(offer.lockAt, now: now))前全部确认，否则自动取消，不计入任何记录")
    }

    @ViewBuilder
    private func seatRow(_ seat: MatchOffer.Seat) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if seat.isVacant {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(AppTheme.Colors.surfaceMuted))
                Text("一位球友这次来不了")
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(cardSecondary)
                Spacer()
                statusPill(String(localized: "补位中"), icon: "arrow.triangle.2.circlepath", fill: AppTheme.Colors.surfaceMuted)
            } else if let user = matchManager.user(id: seat.userId) {
                AvatarView(user: user, size: 32, )
                    .opensProfile(user.id, allowsInvite: false)
                Text(user.id == ticket.userId ? String(localized: "我") : user.nickname)
                    .font(AppTheme.Typography.subheadlineBold)
                    .lineLimit(1)
                Spacer()
                if !matchManager.isRemote || user.id == ticket.userId {
                    if seat.response == .accepted {
                        TagPill(text: String(localized: "已确认"), icon: "checkmark", fill: AppTheme.Colors.mint)
                    } else {
                        statusPill(String(localized: "等待确认"), icon: "hourglass", fill: AppTheme.Colors.surface)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusPill(_ text: String, icon: String, fill: Color) -> some View {
        TagPill(text: text, icon: icon, fill: fill, foreground: AppTheme.Colors.ink)
    }

    /// 其他球友：水平差、距离、靠谱徽章与球友印象（不显示任何评分数字）
    private var playersCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ForEach(others) { user in
                Button {
                    presentedPlayer = PlayerSheetItem(id: user.id)
                } label: {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        HStack(spacing: 6) {
                            Text(user.nickname)
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Text(subtitle(for: user))
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if user.isNewPlayer {
                                NewPlayerBadge()
                            } else if user.isReliable {
                                ReliableBadge()
                            }
                        }
                        PraiseTagsView(tags: Array(user.reputation.publicTags.prefix(2)), emptyText: nil)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看资料")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(for user: User) -> String {
        let level = SkillTier.differenceText((me?.displayTier ?? user.displayTier).steps(to: user.displayTier))
        guard let location = user.location else { return level }
        return "\(level) · \(DistanceFormatter.approximate(km: location.distanceKm(to: ticket.origin)))"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let gameId = offer.gameId {
                Button {
                    matchManager.closeFlow()
                    router.show(.game(id: gameId), in: .games)
                } label: {
                    Label("查看球局", systemImage: "ticket.fill")
                }
                .buttonStyle(.brutalPrimary)
                if let opponent = others.first {
                    Button("给 \(opponent.nickname) 发消息") {
                        matchManager.closeFlow()
                        router.show(.chat(userId: opponent.id), in: .messages)
                    }
                    .buttonStyle(TextActionStyle())
                }
            } else if awaitsMe {
                HStack(spacing: AppTheme.Spacing.md) {
                    Button("这次不行") {
                        Haptics.tap()
                        Task { await matchManager.respond(accept: false) }
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: false))
                    .frame(width: 128)
                    .disabled(matchManager.isResponding)
                    .accessibilityHint("不扣分，会继续帮你找其他人")

                    Button {
                        Task { await matchManager.respond(accept: true) }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            if matchManager.isResponding { LoadingDots() }
                            Text("确认约球")
                        }
                    }
                    .buttonStyle(.brutalPrimary)
                    .disabled(matchManager.isResponding)
                }
                Text("所有人都确认才成局，谁没确认不会告诉其他人。确认后，开赛前 2 小时内取消会计入履约记录。")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("好的，有消息通知我") { matchManager.closeFlow() }
                    .buttonStyle(.brutalPrimary)
                Button("取消请求") { confirmsCancel = true }
                    .buttonStyle(TextActionStyle())
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
    }

    private func animateIn() {
        if reduceMotion || !(awaitsMe || isMatched) {
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
