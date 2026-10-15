import SwiftUI

// MARK: - 挑战列表（收到的 / 发出的）

struct ChallengesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    /// 挑战变化会发 .gamesChanged，MatchManager 随之刷新，借它触发重绘
    @EnvironmentObject private var matchManager: MatchManager

    @State private var workingId: String?

    var body: some View {
        let me = appState.currentUser?.id ?? ""
        let all = appState.backend.challenges()
        // 待回应的排在前面（列表本身已按时间新到旧）
        let incoming = all.filter { $0.targetId == me && $0.status == .pending }
            + all.filter { $0.targetId == me && $0.status != .pending }
        let outgoing = all.filter { $0.challengerId == me }

        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "挑战"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    if all.isEmpty {
                        EmptyStateView(icon: "flag.2.crossed.fill",
                                       title: String(localized: "还没有挑战"),
                                       message: String(localized: "点任意球友头像就能发起单打挑战。"),
                                       tint: AppTheme.Colors.peach)
                            .card()
                    } else {
                        if !incoming.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                SectionTitle(title: String(localized: "收到的"))
                                ForEach(incoming) { challenge in
                                    ChallengeRow(challenge: challenge, otherId: challenge.challengerId) {
                                        incomingTrailing(challenge)
                                    }
                                }
                            }
                        }
                        if !outgoing.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                SectionTitle(title: String(localized: "发出的"))
                                ForEach(outgoing) { challenge in
                                    ChallengeRow(challenge: challenge, otherId: challenge.targetId) {
                                        outgoingTrailing(challenge)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func incomingTrailing(_ challenge: Challenge) -> some View {
        switch challenge.status {
        case .pending:
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("还剩 \(Self.remaining(until: challenge.expiresAt))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button("不了") { respond(challenge, accept: false) }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                    Button("接受") { respond(challenge, accept: true) }
                        .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small))
                }
                .disabled(workingId != nil)
            }
        case .accepted:
            acceptedLine(challenge)
        case .declined:
            statusText(String(localized: "已婉拒"))
        case .expired, .withdrawn:
            statusText(String(localized: "未成行"))
        }
    }

    @ViewBuilder
    private func outgoingTrailing(_ challenge: Challenge) -> some View {
        switch challenge.status {
        case .pending:
            HStack {
                statusText(String(localized: "等待回应 · 还剩 \(Self.remaining(until: challenge.expiresAt))"))
                Spacer()
                Button("撤回") {
                    appState.backend.withdrawChallenge(id: challenge.id)
                    appState.showToast(String(localized: "已撤回"))
                }
                .buttonStyle(TextActionStyle())
            }
        case .accepted:
            acceptedLine(challenge)
        // 对发起人不区分“被拒”和“过期”
        case .declined, .expired, .withdrawn:
            statusText(String(localized: "未成行"))
        }
    }

    private func acceptedLine(_ challenge: Challenge) -> some View {
        HStack {
            TagPill(text: String(localized: "已接受"), icon: "checkmark", fill: AppTheme.Colors.lime)
            Spacer()
            if let gameId = challenge.gameId {
                Button("查看球局") { router.open(.game(id: gameId)) }
                    .buttonStyle(TextActionStyle())
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Typography.footnoteBold)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
    }

    // MARK: Actions

    private func respond(_ challenge: Challenge, accept: Bool) {
        workingId = challenge.id
        Task {
            defer { workingId = nil }
            do {
                let game = try await appState.backend.respondToChallenge(id: challenge.id, accept: accept)
                if accept {
                    Haptics.success()
                    appState.showToast(String(localized: "已接受，球局已加入你的日程"), style: .success)
                    if let game { router.open(.game(id: game.id)) }
                } else {
                    appState.showToast(String(localized: "已婉拒，对方不会收到通知"))
                }
            } catch {
                appState.showError(error)
            }
        }
    }

    /// “31 小时” / “40 分钟”
    static func remaining(until date: Date, now: Date = Date()) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 60 {
            let hours = minutes / 60
            return String(localized: "\(hours) 小时")
        }
        return String(localized: "\(minutes) 分钟")
    }
}

private struct ChallengeRow<Trailing: View>: View {
    let challenge: Challenge
    let otherId: String
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager

    var body: some View {
        let other = friendManager.user(id: otherId)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Button {
                    appState.showPlayer(otherId)
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        if let other {
                            AvatarView(user: other, size: 44)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other?.nickname ?? String(localized: "球友"))
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            if let other {
                                LevelBadge(tier: other.displayTier)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看个人资料")
                Spacer(minLength: 0)
                TagPill(text: String(localized: "单打"), icon: "flag.2.crossed.fill", fill: AppTheme.Colors.peach)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(challenge.slot.formattedFull, systemImage: "calendar")
                Label(challenge.court.name, systemImage: "mappin.and.ellipse")
                    .lineLimit(1)
            }
            .font(AppTheme.Typography.footnote)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
            if !challenge.message.isEmpty {
                Text("“\(challenge.message)”")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            trailing()
        }
        .card(AppTheme.Colors.surface, shadow: .zero)
    }
}

// MARK: - 发起挑战

struct ChallengeComposer: View {
    let targetId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var courtId: String?
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var startMinutes = 19 * 60
    @State private var endMinutes = 21 * 60
    @State private var message = ""
    @State private var showCourtPicker = false
    @State private var isSending = false
    @State private var didSetup = false

    private var target: User? { friendManager.user(id: targetId) }

    private var court: BadmintonCourt? { courtId.flatMap { locationManager.court(id: $0) } }

    private var slot: TimeSlot? {
        TimeSlot.on(day, startHour: startMinutes / 60, startMinute: startMinutes % 60,
                    endHour: endMinutes / 60, endMinute: endMinutes % 60)
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<TimeSlotConstants.maximumDaysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// 常去球馆在前，再补附近的
    private var suggestedCourts: [BadmintonCourt] {
        var list: [BadmintonCourt] = []
        if let court, !locationManager.favoriteCourts.contains(where: { $0.id == court.id }) { list.append(court) }
        for candidate in locationManager.favoriteCourts + locationManager.nearbyCourts
        where !list.contains(where: { $0.id == candidate.id }) {
            list.append(candidate)
        }
        return Array(list.prefix(6))
    }

    private var validationMessage: String? {
        if court == nil { return String(localized: "选一个球馆") }
        guard let slot else { return String(localized: "时间无效") }
        return slot.validate().errorMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("向 \(target?.nickname ?? String(localized: "TA")) 发起单打挑战")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    group(String(localized: "球馆")) {
                        FlowLayout(spacing: AppTheme.Spacing.sm) {
                            ForEach(suggestedCourts) { option in
                                ChoiceChip(title: option.name, icon: locationManager.isFavorite(option.id) ? "heart.fill" : nil,
                                           isSelected: courtId == option.id) {
                                    courtId = option.id
                                }
                            }
                            ChoiceChip(title: String(localized: "其他球馆"), icon: "magnifyingglass", isSelected: false) {
                                showCourtPicker = true
                            }
                        }
                        if let court {
                            Text("\(court.address) · \(court.formattedDistance(from: locationManager.coordinate))")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    group(String(localized: "时间")) {
                        DateStrip(days: days, selection: $day)
                            .padding(.horizontal, -AppTheme.Spacing.screen)
                        HStack(spacing: AppTheme.Spacing.md) {
                            TimeStepper(title: String(localized: "开始"), minutes: $startMinutes, range: (6 * 60)...(23 * 60))
                            TimeStepper(title: String(localized: "结束"), minutes: $endMinutes, range: (7 * 60)...(24 * 60))
                        }
                        if let error = slot?.validate().errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.danger)
                        }
                    }

                    BrutalTextField(label: String(localized: "留言（可选）"),
                                    placeholder: String(localized: "说一句，比如：打三局两胜？"),
                                    text: $message, characterLimit: Challenge.messageLimit, axis: .vertical)
                        .onChange(of: message) { _, newValue in
                            if newValue.count > Challenge.messageLimit {
                                message = String(newValue.prefix(Challenge.messageLimit))
                            }
                        }

                    Text("对方 48 小时内可以接受；没回应会自动过期。被拒绝也只会显示“未成行”。接受后生成一场单打，双方确认赛果后计入排行。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }

            Button {
                Task { await send() }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isSending { LoadingDots() }
                    Text("发出挑战")
                }
            }
            .buttonStyle(.brutalPrimary)
            .disabled(validationMessage != nil || isSending)
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
            .overlay(alignment: .top) { InsetDivider() }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showCourtPicker) {
            CourtPickerSheet(selectedId: $courtId, slot: slot)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: setup)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        let suggested = TimeSlot.suggestedDefault()
        let calendar = Calendar.current
        day = calendar.startOfDay(for: suggested.startTime)
        startMinutes = calendar.component(.hour, from: suggested.startTime) * 60 + calendar.component(.minute, from: suggested.startTime)
        endMinutes = min(24 * 60, startMinutes + 120)
        courtId = locationManager.favoriteCourts.first?.id ?? locationManager.nearbyCourts.first?.id
    }

    private func send() async {
        guard let court, let slot else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await appState.backend.sendChallenge(to: targetId, court: court, slot: slot, message: message)
            Haptics.success()
            appState.showToast(String(localized: "挑战已发出"), style: .success)
            dismiss()
        } catch {
            appState.showError(error)
        }
    }
}
