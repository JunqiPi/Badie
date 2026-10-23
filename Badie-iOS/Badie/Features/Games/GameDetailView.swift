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
    @State private var resultSheet: ResultSheetPurpose?
    @State private var isWorking = false

    private var game: Game? { matchManager.game(id: gameId) }
    private var me: String? { appState.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "球局详情")) {
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
                EmptyStateView(icon: "questionmark.folder", title: String(localized: "球局不存在或已被删除"))
                Spacer()
            }
        }
        .sheet(isPresented: $showCalendar) {
            if let game {
                CalendarEventEditor(game: game) { showCalendar = false }
                    .ignoresSafeArea()
            }
        }
        .sheet(item: $resultSheet) { purpose in
            if let game {
                CompleteGameSheet(game: game, isConfirming: purpose == .confirm,
                                  initialOutcome: purpose == .confirm ? suggestedOutcome(game) : nil) { outcome, score in
                    Task {
                        if purpose == .confirm {
                            await confirmResult(game, outcome: outcome, score: score)
                        } else {
                            await complete(game, didWin: outcome.didWin, score: score)
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("选择导航方式", isPresented: $showNavigationChoices, titleVisibility: .visible) {
            if let game {
                ForEach(MapsLauncher.apps(for: game.court)) { app in
                    Button(app.title) {
                        Task {
                            let opened = await MapsLauncher.open(game.court, with: app)
                            if !opened { appState.showToast(String(localized: "未安装\(app.title)"), style: .error) }
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
            actionTile(icon: "location.north.line.fill", title: String(localized: "导航"), tint: AppTheme.Colors.sky) {
                showNavigationChoices = true
            }
            // 球局群聊：所有人一起沟通，不需要先加好友；赛后 48 小时关闭
            actionTile(icon: "bubble.left.and.bubble.right.fill", title: String(localized: "群聊"), tint: AppTheme.Colors.lavender) {
                if let threadId = messageManager.gameChatId(for: game.id) {
                    router.open(.groupChat(threadId: threadId))
                }
            }
            actionTile(icon: game.reminderEnabled ? "bell.badge.fill" : "bell.fill",
                       title: game.reminderEnabled ? String(localized: "已提醒") : String(localized: "提醒"),
                       tint: game.reminderEnabled ? AppTheme.Colors.lime : AppTheme.Colors.butter) {
                Task {
                    let target = !game.reminderEnabled
                    let ok = await matchManager.setReminder(game, enabled: target)
                    if ok {
                        appState.showToast(target ? String(localized: "将在开赛前 1 天、2 小时、15 分钟提醒你") : String(localized: "已关闭提醒"), style: .success)
                    } else {
                        appState.showToast(String(localized: "请在系统设置中允许通知"), style: .error)
                    }
                }
            }
            ShareLink(item: game.shareText) {
                tileLabel(icon: "square.and.arrow.up.fill", title: String(localized: "分享"), tint: AppTheme.Colors.pink)
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
                        Text(player.id == me ? String(localized: "我") : player.nickname)
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Spacer()
                        if let time = game.checkIns[player.id] {
                            TagPill(text: String(localized: "\(DateText.time(time)) 已到"), icon: "checkmark", fill: AppTheme.Colors.mint)
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
                        Label(game.canCheckIn(now: now) ? String(localized: "我已到场 · 签到") : String(localized: "开赛前 30 分钟开放签到"), systemImage: "mappin.circle.fill")
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
                        Text(index == 0 ? String(localized: "A 队") : String(localized: "B 队"))
                            .font(AppTheme.Typography.overline)
                        ForEach(team, id: \.self) { userId in
                            if let user = lookup[userId] {
                                HStack(spacing: 6) {
                                    AvatarView(user: user, size: 26)
                                        .opensProfile(user.id)
                                    Text(user.id == me ? String(localized: "我") : user.nickname)
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
            Text("\(game.cost.breakdownText) · 平台不收服务费")
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
                    Text(player.id == me ? String(localized: "我") : player.nickname)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if player.id == game.hostId {
                        TagPill(text: String(localized: "发起人"), fill: AppTheme.Colors.butter)
                    }
                    Spacer()
                    Button {
                        Haptics.selection()
                        matchManager.togglePaid(game, userId: player.id)
                    } label: {
                        TagPill(text: paid ? String(localized: "已付") : String(localized: "待付"), icon: paid ? "checkmark" : nil,
                                fill: paid ? AppTheme.Colors.mint : AppTheme.Colors.surface,
                                foreground: paid ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canToggle || game.status == .cancelled)
                    .accessibilityLabel("\(player.nickname) \(paid ? String(localized: "已付") : String(localized: "待付"))")
                    .accessibilityHint(canToggle ? String(localized: "点按切换付款状态") : "")
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
                    resultSheet = .complete
                } label: {
                    Label("结束球局并记录结果", systemImage: "flag.checkered")
                }
                .buttonStyle(.brutal(.inverse, size: .medium))
                .disabled(!canComplete)
                Text(canComplete ? String(localized: "结束后可以给球友匿名评价，互评都提交后才会计入口碑") : String(localized: "球局开始后才能结束 · \(DateText.countdown(to: game.slot.startTime, now: context.date))"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
    }

    private func resultSection(_ game: Game) -> some View {
        let pending = surveyManager.pending(forGame: game.id)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            resultCard(game)
            if !pending.isEmpty {
                SectionTitle(title: String(localized: "待评价"), detail: DateText.remaining(until: pending[0].expiresAt))
                ForEach(pending) { survey in
                    Button {
                        router.open(.survey(pendingId: survey.id))
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            AvatarView(avatar: survey.opponentAvatar, userId: survey.opponentId, text: survey.opponentAvatarText, size: 40)
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

    // MARK: Result confirmation

    private func resultCard(_ game: Game) -> some View {
        let status = game.resultStatus()
        let outcome = game.resultOutcome(for: me)
        let score = game.reportedScore(by: me)
        let hasReported = me.flatMap { game.report(by: $0) } != nil
        let isPlayer = me.flatMap { game.team(of: $0) } != nil
        // 早期没有申报记录的球局不参与确认
        let hasReports = !game.resultReports.isEmpty
        let canReport = hasReports && isPlayer && game.acceptsResultReports()
        let claims = otherClaims(game)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text(resultHeadline(status: status, outcome: outcome))
                    .font(AppTheme.Typography.headline)
                Spacer()
                if !score.isEmpty {
                    Text(score)
                        .font(AppTheme.Typography.footnoteBold)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(AppTheme.Colors.ink)
            if hasReports {
                NoticeBanner(icon: resultIcon(status), text: resultStatusText(game, status: status, hasReported: hasReported),
                             tint: resultTint(status))
            }
            if (canReport || status == .disputed), !claims.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                        Text(claim)
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
            }
            if canReport {
                Button {
                    resultSheet = .confirm
                } label: {
                    Label(hasReported ? String(localized: "修改赛果") : String(localized: "确认赛果"), systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.brutal(.primary, size: .medium))
            }
        }
        .card(AppTheme.Colors.surface)
    }

    private func resultHeadline(status: ResultStatus, outcome: Bool?) -> String {
        if status == .friendly { return String(localized: "友谊局") }
        switch outcome {
        case true?: return String(localized: "赢下了这场")
        case false?: return String(localized: "惜败，下次再来")
        case nil: return String(localized: "球局已完成")
        }
    }

    private func resultStatusText(_ game: Game, status: ResultStatus, hasReported: Bool) -> String {
        switch status {
        case .awaiting:
            let left = confirmationTimeLeft(game)
            return hasReported ? String(localized: "已提交，等对方确认（\(left)）") : String(localized: "等你确认赛果（\(left)）")
        case .verified:
            return String(localized: "赛果已确认 · 计入本月胜率")
        case .disputed where game.acceptsResultReports():
            return String(localized: "双方说法不一致：任何一方改成一致就照常计入（\(confirmationTimeLeft(game))）")
        case .disputed:
            return String(localized: "双方说法不一致，本场不计入胜率")
        case .friendly:
            return String(localized: "友谊局，不计胜负")
        case .unsure:
            return String(localized: "有一方记不清，本场不计入胜率")
        case .expired:
            return String(localized: "没有在 7 天内确认，本场不计入")
        }
    }

    private func resultIcon(_ status: ResultStatus) -> String {
        switch status {
        case .awaiting: return "hourglass"
        case .verified: return "checkmark.seal.fill"
        case .disputed: return "exclamationmark.triangle.fill"
        case .friendly: return "hand.wave.fill"
        case .unsure: return "questionmark.circle.fill"
        case .expired: return "clock.badge.xmark"
        }
    }

    private func resultTint(_ status: ResultStatus) -> Color {
        switch status {
        case .awaiting: return AppTheme.Colors.butter
        case .verified: return AppTheme.Colors.mint
        case .disputed: return AppTheme.Colors.pink
        case .friendly: return AppTheme.Colors.sky
        case .unsure, .expired: return AppTheme.Colors.surfaceMuted
        }
    }

    /// 例如“还剩 3 天”；不足一天时显示小时 / 分钟
    private func confirmationTimeLeft(_ game: Game) -> String {
        let deadline = game.resultDeadline
        let seconds = deadline.timeIntervalSinceNow
        guard seconds >= 86400 else { return DateText.remaining(until: deadline) }
        let days = Int((seconds / 86400).rounded(.up))
        return String(localized: "还剩 \(days) 天")
    }

    /// 其他球员各自报的结果（以我方视角描述）
    private func otherClaims(_ game: Game) -> [String] {
        guard let me, let mine = game.team(of: me) else { return [] }
        return game.resultReports.filter { $0.reporterId != me }.map { report in
            let name = friendManager.user(id: report.reporterId)?.nickname ?? String(localized: "球友")
            if report.unsure { return String(localized: "\(name)：记不清了") }
            guard let winner = report.winningTeam else { return String(localized: "\(name) 报：友谊局，不计胜负") }
            return winner == mine ? String(localized: "\(name) 报：我方赢") : String(localized: "\(name) 报：我方输")
        }
    }

    // MARK: Helpers

    private func players(_ game: Game) -> [User] {
        game.playerIds.compactMap { friendManager.user(id: $0) }
    }

    private func cancelledText(_ game: Game) -> String {
        let who = game.cancelledBy == me ? String(localized: "你") : (game.cancelledBy.flatMap { friendManager.user(id: $0)?.nickname } ?? String(localized: "球友"))
        return String(localized: "\(who)已取消这场球局") + (game.cancelledLate ? String(localized: "（开赛前 2 小时内，计为临时取消）") : "")
    }

    private var cancelTitle: String {
        guard let game else { return String(localized: "取消球局？") }
        return game.isLateCancellation() ? String(localized: "现在取消会记为临时取消") : String(localized: "确定取消球局吗？")
    }

    private var cancelMessage: String {
        guard let game else { return "" }
        if game.isLateCancellation() {
            return String(localized: "距开赛不到 2 小时，取消会计入你的履约记录，并通知其他球友。多次临时取消后，约球需要先付 AA。")
        }
        return String(localized: "会通知其他球友。开赛 2 小时前取消不影响履约记录。")
    }

    private func cancel() async {
        guard let game else { return }
        do {
            try await matchManager.cancel(game)
            appState.showToast(String(localized: "已取消，已通知其他球友"))
        } catch {
            appState.showError(error)
        }
    }

    private func checkIn(_ game: Game) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await matchManager.checkIn(game)
            appState.showToast(String(localized: "签到成功，打得开心。"), style: .success)
        } catch {
            appState.showError(error)
        }
    }

    private func complete(_ game: Game, didWin: Bool?, score: String) async {
        resultSheet = nil
        do {
            try await matchManager.complete(game, didWin: didWin, score: score)
            appState.showToast(String(localized: "球局已完成，去给球友评分"), style: .success)
            if let first = surveyManager.pending(forGame: game.id).first {
                router.open(.survey(pendingId: first.id))
            }
        } catch {
            appState.showError(error)
        }
    }

    private func confirmResult(_ game: Game, outcome: CompleteGameSheet.Outcome, score: String) async {
        resultSheet = nil
        do {
            if outcome == .unsure {
                try await appState.backend.reportResultUnsure(gameId: game.id)
                appState.showToast(String(localized: "好的，这场不计入胜率"))
            } else {
                try await appState.backend.reportResult(gameId: game.id, didWin: outcome.didWin, score: score)
                appState.showToast(String(localized: "已提交，双方一致后计入胜率"), style: .success)
            }
        } catch {
            appState.showError(error)
        }
    }

    /// 预选：我上次报的，否则别人报的（换成我方视角）
    private func suggestedOutcome(_ game: Game) -> CompleteGameSheet.Outcome? {
        guard let me, let mine = game.team(of: me),
              let report = game.report(by: me) ?? game.resultReports.first(where: { !$0.unsure }) else { return nil }
        if report.unsure { return .unsure }
        guard let winner = report.winningTeam else { return .friendly }
        return winner == mine ? .win : .lose
    }
}

private enum ResultSheetPurpose: String, Identifiable {
    case complete, confirm

    var id: String { rawValue }
}

// MARK: - 结束球局 / 确认赛果

struct CompleteGameSheet: View {
    enum Outcome: CaseIterable, Identifiable {
        case win, lose, friendly, unsure

        var id: Self { self }

        var title: String {
            switch self {
            case .win: return String(localized: "我方赢了")
            case .lose: return String(localized: "我方输了")
            case .friendly: return String(localized: "友谊局，不计胜负")
            case .unsure: return String(localized: "记不清了")
            }
        }

        var icon: String {
            switch self {
            case .win: return "trophy.fill"
            case .lose: return "arrow.uturn.down"
            case .friendly: return "hand.wave.fill"
            case .unsure: return "questionmark.circle"
            }
        }

        var didWin: Bool? {
            switch self {
            case .win: return true
            case .lose: return false
            case .friendly, .unsure: return nil
            }
        }
    }

    let game: Game
    /// 别人已结束球局，我来确认 / 修改赛果
    var isConfirming = false
    var initialOutcome: Outcome?
    let onComplete: (Outcome, String) -> Void

    @State private var outcome: Outcome?
    @State private var score = ""

    private var scoreIsValid: Bool { GameResult.isValidScore(score) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                Text(isConfirming ? String(localized: "确认赛果") : String(localized: "结束球局"))
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.top, AppTheme.Spacing.xl)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("这场的结果")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    ForEach(isConfirming ? Outcome.allCases : [.win, .lose, .friendly]) { option in
                        optionRow(option)
                    }
                }
                if outcome != .unsure {
                    BrutalTextField(label: String(localized: "比分（可选）"), placeholder: String(localized: "如 21:18 19:21 21:15"), text: $score,
                                    keyboard: .numbersAndPunctuation,
                                    errorText: scoreIsValid ? nil : String(localized: "比分只能填数字，如 21:18 19:21。"),
                                    characterLimit: 40)
                }
                Label("打了好几局就按赢得多的一方算。双方一致才计入胜率；记不清就选“记不清了”，不算分歧", systemImage: "checkmark.shield")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
        .safeAreaInset(edge: .bottom) {
            Button(isConfirming ? String(localized: "提交赛果") : String(localized: "完成并去评价")) {
                guard let outcome else { return }
                onComplete(outcome, outcome == .unsure ? "" : score)
            }
            .buttonStyle(.brutalPrimary)
            .disabled(outcome == nil || (outcome != .unsure && !scoreIsValid))
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.lg)
            .background(AppTheme.Colors.canvas)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { outcome = outcome ?? initialOutcome }
    }

    private func optionRow(_ option: Outcome) -> some View {
        let selected = outcome == option
        return Button {
            Haptics.selection()
            outcome = option
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 24)
                Text(option.title)
                    .font(AppTheme.Typography.bodyBold)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundStyle(selected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 52)
            .sticker(selected ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.md,
                     shadow: selected ? AppTheme.Elevation.low : .zero)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
