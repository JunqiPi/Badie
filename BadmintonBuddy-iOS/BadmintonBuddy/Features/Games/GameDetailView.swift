import SwiftUI

struct GameDetailView: View {
    let gameId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var messageManager: MessageManager

    @State private var showNavigationChoices = false
    @State private var showCalendar = false
    @State private var showCancelConfirm = false
    @State private var showCompleteSheet = false
    @State private var isWorking = false

    private var game: Game? { matchManager.game(id: gameId) }
    private var me: String? { appState.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "球局详情") {
                if let game {
                    Menu {
                        ShareLink(item: game.shareText) {
                            Label("分享球局", systemImage: "square.and.arrow.up")
                        }
                        if game.isUpcoming() {
                            Button {
                                showCalendar = true
                            } label: {
                                Label("加入日历", systemImage: "calendar.badge.plus")
                            }
                            Button(role: .destructive) {
                                showCancelConfirm = true
                            } label: {
                                Label("取消球局", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .frame(width: 44, height: 44)
                            .sticker(AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
                    }
                    .accessibilityLabel("更多操作")
                }
            }
            if let game {
                content(game)
            } else {
                Spacer()
                EmptyStateView(icon: "questionmark.folder", title: "球局不存在或已被删除")
                Spacer()
            }
        }
        .sheet(isPresented: $showCalendar) {
            if let game {
                CalendarEventEditor(game: game) { showCalendar = false }
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showCompleteSheet) {
            if let game {
                CompleteGameSheet(game: game) { didWin, score in
                    Task { await complete(game, didWin: didWin, score: score) }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("选择导航方式", isPresented: $showNavigationChoices, titleVisibility: .visible) {
            if let game {
                ForEach(MapsLauncher.apps(for: game.court)) { app in
                    Button(app.title) {
                        Task {
                            let opened = await MapsLauncher.open(game.court, with: app)
                            if !opened { appState.showToast("未安装\(app.title)", style: .error) }
                        }
                    }
                }
            }
        }
        .alert(cancelTitle, isPresented: $showCancelConfirm) {
            Button("再想想", role: .cancel) {}
            Button("确认取消", role: .destructive) {
                Task { await cancel() }
            }
        } message: {
            Text(cancelMessage)
        }
    }

    // MARK: Content

    private func content(_ game: Game) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                GameTicketCard(game: game, players: players(game), currentUserId: me)

                if game.status == .cancelled {
                    NoticeBanner(icon: "xmark.octagon.fill",
                                 text: cancelledText(game),
                                 tint: AppTheme.Colors.surfaceMuted)
                }

                if game.status == .confirmed {
                    actionGrid(game)
                }

                venueCard(game)

                if game.status == .confirmed {
                    checkInCard(game)
                }

                if game.mode == .doubles {
                    teamsCard(game)
                }

                costCard(game)

                if game.status == .confirmed {
                    completeSection(game)
                }

                if game.status == .completed {
                    resultSection(game)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xxxl)
        }
    }

    // MARK: Venue

    /// 球馆：完整地址 + 入口说明 + 球馆详情入口（地址是到场前最常被问的问题）
    private func venueCard(_ game: Game) -> some View {
        let venue = appState.backend.venue(id: game.court.id) ?? game.court
        return Button {
            router.open(.venue(id: venue.id))
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(venue.name)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                    VenueStatusBadge(status: venue.status)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
                Text(venue.address)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = venue.entranceNote {
                    Label(note, systemImage: "door.left.hand.open")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let zone = venue.timeZoneAbbreviation {
                    Label("时间为球馆当地时间（\(zone)）", systemImage: "globe")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityHint("查看球馆详情、地图与导航")
    }

    // MARK: Actions grid

    private func actionGrid(_ game: Game) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            actionTile(icon: "location.north.line.fill", title: "导航", tint: AppTheme.Colors.sky) {
                showNavigationChoices = true
            }
            // 球局群聊：所有人一起沟通，不需要先加好友；赛后 48 小时关闭
            actionTile(icon: "bubble.left.and.bubble.right.fill", title: "群聊", tint: AppTheme.Colors.lavender) {
                if let threadId = messageManager.gameChatId(for: game.id) {
                    router.open(.groupChat(threadId: threadId))
                }
            }
            actionTile(icon: game.reminderEnabled ? "bell.badge.fill" : "bell.fill",
                       title: game.reminderEnabled ? "已提醒" : "提醒",
                       tint: game.reminderEnabled ? AppTheme.Colors.lime : AppTheme.Colors.butter) {
                Task {
                    let target = !game.reminderEnabled
                    let ok = await matchManager.setReminder(game, enabled: target)
                    if ok {
                        appState.showToast(target ? "将在开赛前 1 天、2 小时、15 分钟提醒你" : "已关闭提醒", style: .success)
                    } else {
                        appState.showToast("请在系统设置中允许通知", style: .error)
                    }
                }
            }
            ShareLink(item: game.shareText) {
                tileLabel(icon: "square.and.arrow.up.fill", title: "分享", tint: AppTheme.Colors.pink)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func actionTile(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tileLabel(icon: icon, title: title, tint: tint)
        }
        .buttonStyle(PressableStyle())
    }

    private func tileLabel(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.Colors.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .sticker(tint, radius: 16, shadow: AppTheme.Elevation.low)
            Text(title)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    // MARK: Check-in

    private func checkInCard(_ game: Game) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("到场签到")
                        .font(AppTheme.Typography.headline)
                    Spacer()
                    Text("\(game.checkIns.count)/\(game.playerIds.count) 已到")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                .foregroundStyle(AppTheme.Colors.ink)
                ForEach(players(game)) { player in
                    HStack(spacing: AppTheme.Spacing.md) {
                        AvatarView(user: player, size: 32)
                            .opensProfile(player.id)
                        Text(player.id == me ? "我" : player.nickname)
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Spacer()
                        if let time = game.checkIns[player.id] {
                            TagPill(text: "\(DateText.time(time)) 已到", icon: "checkmark", fill: AppTheme.Colors.mint)
                        } else {
                            Text("未签到")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkTertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let me, !game.hasCheckedIn(me) {
                    Button {
                        Task { await checkIn(game) }
                    } label: {
                        Label(game.canCheckIn(now: now) ? "我已到场 · 签到" : "开赛前 30 分钟开放签到", systemImage: "mappin.circle.fill")
                    }
                    .buttonStyle(.brutal(.primary, size: .medium))
                    .disabled(!game.canCheckIn(now: now) || isWorking)
                    Text("签到记录会计入履约率，爽约和临时取消会被记录")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
            }
            .card()
        }
    }

    // MARK: Teams

    private func teamsCard(_ game: Game) -> some View {
        let lookup = Dictionary(uniqueKeysWithValues: players(game).map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("分组")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                ForEach(Array(game.teams.enumerated()), id: \.offset) { index, team in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(index == 0 ? "A 队" : "B 队")
                            .font(AppTheme.Typography.overline)
                        ForEach(team, id: \.self) { userId in
                            if let user = lookup[userId] {
                                HStack(spacing: 6) {
                                    AvatarView(user: user, size: 26)
                                        .opensProfile(user.id)
                                    Text(user.id == me ? "我" : user.nickname)
                                        .font(AppTheme.Typography.footnoteBold)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(user.displayTier.text)
                                        .font(AppTheme.Typography.caption)
                                }
                            }
                        }
                    }
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sticker(index == 0 ? AppTheme.Colors.lavender : AppTheme.Colors.lime, radius: 16, shadow: .zero)
                    if index == 0 {
                        Text("VS")
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.ink)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Cost

    private func costCard(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("AA 费用")
                    .font(AppTheme.Typography.headline)
                Spacer()
                if let perPerson = game.cost.perPerson {
                    Text(game.cost.money(perPerson))
                        .scaledFont(size: 26, relativeTo: .title2)
                        .monospacedDigit()
                    Text("/人")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                } else {
                    Text("待定")
                        .font(AppTheme.Typography.headline)
                }
            }
            .foregroundStyle(AppTheme.Colors.ink)
            Text(game.cost.breakdownText + " · 平台不收服务费")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if game.court.status == .unconfirmed || !game.court.pricing.isKnown {
                Text("价格以球馆实际收费为准")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            InsetDivider()
            ForEach(players(game)) { player in
                let paid = game.hasPaid(player.id)
                let canToggle = player.id == me || game.hostId == me
                HStack(spacing: AppTheme.Spacing.md) {
                    AvatarView(user: player, size: 30)
                        .opensProfile(player.id)
                    Text(player.id == me ? "我" : player.nickname)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if player.id == game.hostId {
                        TagPill(text: "发起人", fill: AppTheme.Colors.butter)
                    }
                    Spacer()
                    Button {
                        Haptics.selection()
                        matchManager.togglePaid(game, userId: player.id)
                    } label: {
                        TagPill(text: paid ? "已付" : "待付", icon: paid ? "checkmark" : nil,
                                fill: paid ? AppTheme.Colors.mint : AppTheme.Colors.surface,
                                foreground: paid ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canToggle || game.status == .cancelled)
                    .accessibilityLabel("\(player.nickname) \(paid ? "已付" : "待付")")
                    .accessibilityHint(canToggle ? "点按切换付款状态" : "")
                }
            }
        }
        .card()
    }

    // MARK: Complete

    private func completeSection(_ game: Game) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let canComplete = game.canComplete(now: context.date)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Button {
                    showCompleteSheet = true
                } label: {
                    Label("结束球局并记录结果", systemImage: "flag.checkered")
                }
                .buttonStyle(.brutal(.inverse, size: .medium))
                .disabled(!canComplete)
                Text(canComplete ? "结束后可以给球友匿名评价，互评都提交后才会计入口碑" : "球局开始后才能结束 · \(DateText.countdown(to: game.slot.startTime, now: context.date))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
    }

    private func resultSection(_ game: Game) -> some View {
        let pending = surveyManager.pending(forGame: game.id)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let result = game.result {
                HStack {
                    Text(result.didWin == true ? "🎉 赢下了这场" : (result.didWin == false ? "惜败，下次再来" : "球局已完成"))
                        .font(AppTheme.Typography.headline)
                    Spacer()
                    if !result.score.isEmpty {
                        Text(result.score)
                            .font(AppTheme.Typography.footnoteBold)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(AppTheme.Colors.ink)
                .card(AppTheme.Colors.surface)
            }
            if !pending.isEmpty {
                SectionTitle(title: "待评价", detail: DateText.remaining(until: pending[0].expiresAt))
                ForEach(pending) { survey in
                    Button {
                        router.open(.survey(pendingId: survey.id))
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            AvatarView(text: survey.opponentAvatarText, paletteIndex: survey.opponentAvatar.paletteIndex, size: 40)
                                .opensProfile(survey.opponentId)
                            Text("评价 \(survey.opponentNickname)")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppTheme.Colors.inkTertiary)
                        }
                        .padding(AppTheme.Spacing.md)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
            Button {
                let invitee = game.otherPlayerIds(excluding: me ?? "").first
                router.open(.createRoom(game.mode, invitee: invitee))
            } label: {
                Label("和他们再约一场", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.brutal(.primary, size: .medium))
        }
    }

    // MARK: Helpers

    private func players(_ game: Game) -> [User] {
        game.playerIds.compactMap { friendManager.user(id: $0) }
    }

    private func cancelledText(_ game: Game) -> String {
        let who = game.cancelledBy == me ? "你" : (game.cancelledBy.flatMap { friendManager.user(id: $0)?.nickname } ?? "球友")
        return "\(who)已取消这场球局" + (game.cancelledLate ? "（开赛前 2 小时内，计为临时取消）" : "")
    }

    private var cancelTitle: String {
        guard let game else { return "取消球局？" }
        return game.isLateCancellation() ? "现在取消会记为临时取消" : "确定取消球局吗？"
    }

    private var cancelMessage: String {
        guard let game else { return "" }
        if game.isLateCancellation() {
            return "距开赛不到 2 小时，取消会计入你的履约记录，并通知其他球友。多次临时取消后，约球需要先付 AA。"
        }
        return "会通知其他球友。开赛 2 小时前取消不影响履约记录。"
    }

    private func cancel() async {
        guard let game else { return }
        do {
            try await matchManager.cancel(game)
            appState.showToast("已取消，已通知其他球友")
        } catch {
            appState.showError(error)
        }
    }

    private func checkIn(_ game: Game) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await matchManager.checkIn(game)
            appState.showToast("签到成功，打得开心！", style: .success)
        } catch {
            appState.showError(error)
        }
    }

    private func complete(_ game: Game, didWin: Bool?, score: String) async {
        showCompleteSheet = false
        do {
            try await matchManager.complete(game, didWin: didWin, score: score)
            appState.showToast("球局已完成，去给球友评个分吧", style: .success)
            if let first = surveyManager.pending(forGame: game.id).first {
                router.open(.survey(pendingId: first.id))
            }
        } catch {
            appState.showError(error)
        }
    }
}

// MARK: - 结束球局

struct CompleteGameSheet: View {
    enum Outcome: String, CaseIterable {
        case win = "赢了"
        case lose = "输了"
        case skip = "不记录"
    }

    let game: Game
    let onComplete: (Bool?, String) -> Void

    @State private var outcome: Outcome = .skip
    @State private var score = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text("结束球局")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(game.mode == .doubles ? "你所在的队伍" : "比赛结果")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                SegmentedSticker(options: Outcome.allCases, selection: $outcome, title: { $0.rawValue })
            }
            BrutalTextField(label: "比分（可选）", placeholder: "如 21:18 19:21 21:15", text: $score,
                            keyboard: .numbersAndPunctuation, characterLimit: 40)
            Spacer(minLength: 0)
            Button("完成并去评价") {
                let didWin: Bool?
                switch outcome {
                case .win: didWin = true
                case .lose: didWin = false
                case .skip: didWin = nil
                }
                onComplete(didWin, score)
            }
            .buttonStyle(.brutalPrimary)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
