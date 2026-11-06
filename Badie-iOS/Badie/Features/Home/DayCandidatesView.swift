import SwiftUI

/// 首页点某一天：这天附近在找人、和我水平对得上的球友，一张张卡片左右滑。
/// 右滑约 TA：单打直接发约球邀请，TA 确认就成局；双打先约 TA 一起开个局，再找另外两个人
struct DayCandidatesView: View {
    let day: Date

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [MockBackend.DayCandidate] = []
    @State private var isLoading = true
    @State private var drag: CGSize = .zero
    @State private var inviting: MockBackend.DayCandidate?
    /// 全屏页上面要自己弹资料页（首页那层弹不出来）
    @State private var profile: PlayerSheetItem?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if !cards.isEmpty {
                        Text("右滑约 TA，左滑跳过")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let card = cards.first {
                ZStack {
                    if cards.count > 1 {
                        cardView(cards[1]).scaleEffect(0.96).offset(y: 10).allowsHitTesting(false)
                    }
                    cardView(card)
                        .offset(x: drag.width, y: drag.height * 0.2)
                        .rotationEffect(.degrees(drag.width / 25))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { value in
                                    if value.translation.width > 110 { like(card) }
                                    else if value.translation.width < -110 { skip(card) }
                                    else { withAnimation(AppTheme.Motion.standard) { drag = .zero } }
                                }
                        )
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.screen)
                HStack(spacing: AppTheme.Spacing.xxl) {
                    roundButton("xmark", tint: AppTheme.Colors.surface, label: String(localized: "跳过")) { skip(card) }
                    roundButton("heart.fill", tint: AppTheme.Colors.lime, label: String(localized: "约 TA")) { like(card) }
                }
                .padding(.bottom, AppTheme.Spacing.lg)
            } else {
                Spacer()
                EmptyStateView(icon: "person.2", title: String(localized: "这天附近没有能约的球友了"),
                               message: String(localized: "发个约球请求，有人对得上会通知你。"),
                               actionTitle: String(localized: "发个约球请求")) { request() }
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $profile) { item in
            PlayerProfileSheet(userId: item.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .confirmationDialog(inviteTitle, isPresented: Binding(get: { inviting != nil }, set: { if !$0 { inviting = nil } }),
                            titleVisibility: .visible, presenting: inviting) { card in
            ForEach(card.venues, id: \.id) { venue in
                Button(String(localized: "在 \(venue.name)")) { invite(card, venueId: venue.id) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("TA 确认就成局。没确认的话，你的请求会接着帮你找人。")
        }
    }

    private var inviteTitle: String {
        guard let card = inviting else { return "" }
        return String(localized: "约 TA \(Self.inviteStart(for: card).formatted(date: .omitted, time: .shortened)) 打单打？")
    }

    // MARK: Card

    /// 一张铺满的卡片：上面是大照片（没传照片就是大头像），下面是等级、时间、球馆
    private func cardView(_ card: MockBackend.DayCandidate) -> some View {
        let user = friendManager.user(id: card.userId)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                AppTheme.Colors.surfaceMuted
                if let user, let photo = AvatarPhotos.image(userId: user.id, avatar: user.avatar) {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else if let user {
                    AvatarView(user: user, size: 140)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if let user {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        NicknameText(user: user)
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        LevelBadge(tier: user.displayTier)
                    }
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Label(card.mixed ? String(localized: "混双") : card.mode.title, systemImage: "figure.badminton")
                    Label("\(card.startsAt.formatted(date: .omitted, time: .shortened))–\(card.endsAt.formatted(date: .omitted, time: .shortened))",
                          systemImage: "clock")
                    ForEach(card.venues, id: \.id) { venue in
                        Label(venue.name, systemImage: "mappin.and.ellipse").lineLimit(1)
                    }
                    if card.recentNoShows > 0 {
                        Label(String(localized: "近 180 天爽约 \(card.recentNoShows) 次"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(AppTheme.Colors.ink)
                Button("看资料") { profile = PlayerSheetItem(id: card.userId) }
                    .buttonStyle(TextActionStyle())
            }
            .padding(AppTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private func roundButton(_ icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(AppTheme.Colors.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(tint))
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: Actions

    /// 没人可约：回到首页打开约球设置，日期就是这天
    private func request() {
        matchManager.draft.day = day
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            router.isMatchSetupPresented = true
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            cards = try await appState.backend.dayCandidates(on: day, center: locationManager.coordinate,
                                                             radiusKm: locationManager.preferences.travelRadiusKm)
        } catch {
            appState.showError(error)
        }
    }

    private func next(_ card: MockBackend.DayCandidate, toRight: Bool) {
        withAnimation(AppTheme.Motion.standard) {
            drag = CGSize(width: toRight ? 600 : -600, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            cards.removeAll { $0.id == card.id }
            drag = .zero
        }
    }

    private func skip(_ card: MockBackend.DayCandidate) {
        Haptics.selection()
        next(card, toRight: false)
        Task { await appState.backend.skipCandidate(card.ticketId) }
    }

    private func like(_ card: MockBackend.DayCandidate) {
        Haptics.tap()
        withAnimation(AppTheme.Motion.standard) { drag = .zero }
        if card.mode == .singles && !card.mixed {
            inviting = card
        } else {
            // 双打：先约 TA 一起开个局，再让附近的人补齐
            dismiss()
            router.open(.createRoom(.doubles, invitee: card.userId))
        }
    }

    private func invite(_ card: MockBackend.DayCandidate, venueId: String) {
        Task {
            do {
                try await appState.backend.inviteCandidate(card.ticketId, venueId: venueId, startsAt: Self.inviteStart(for: card))
                Haptics.success()
                appState.showToast(String(localized: "已发出邀请，TA 确认就成局"), style: .success)
                next(card, toRight: true)
            } catch {
                appState.showError(error)
            }
        }
    }

    /// 从 TA 的开始时间约 2 小时；今天的话至少半小时后、按半小时对齐
    static func inviteStart(for card: MockBackend.DayCandidate, now: Date = Date()) -> Date {
        let earliest = now.addingTimeInterval(30 * 60)
        guard card.startsAt < earliest else { return card.startsAt }
        let seconds = ceil(earliest.timeIntervalSince1970 / 1800) * 1800
        return Date(timeIntervalSince1970: seconds)
    }
}
