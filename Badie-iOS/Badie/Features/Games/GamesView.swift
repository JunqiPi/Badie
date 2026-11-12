import SwiftUI

struct GamesView: View {
    enum Segment: String, CaseIterable {
        case upcoming = "即将开始"
        case past = "已结束"

        var title: String {
            switch self {
            case .upcoming: return String(localized: "即将开始")
            case .past: return String(localized: "已结束")
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var segment: Segment = .upcoming
    @State private var regulars: [VenueRegular] = []
    @State private var weeklyStanding: WeeklyStanding?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                LargeTitleHeader(title: String(localized: "球局")) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        IconButton(systemName: "flag.2.crossed", accessibilityLabel: String(localized: "挑战")) {
                            router.open(.challenges)
                        }
                        IconButton(systemName: "clock.arrow.circlepath", accessibilityLabel: String(localized: "历史球局")) {
                            router.open(.gameHistory)
                        }
                    }
                }

                todoPills

                if let game = matchManager.nextGame {
                    Button {
                        router.open(.game(id: game.id))
                    } label: {
                        GameTicketCard(game: game, players: players(of: game), currentUserId: appState.currentUser?.id, compact: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }

                ticketsSection

                myRoomsSection

                quickMatchCard
                    .padding(.horizontal, AppTheme.Spacing.screen)

                quickActions
                    .padding(.horizontal, AppTheme.Spacing.screen)

                publicGamesSection

                myGroupsSection

                mySessionsSection

                if let weeklyStanding {
                    weeklyCard(weeklyStanding)
                        .padding(.horizontal, AppTheme.Spacing.screen)
                }

                playersSection

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SegmentedSticker(options: Segment.allCases, selection: $segment, title: { $0.title }) { option in
                        option == .upcoming ? matchManager.upcomingGames.count : 0
                    }
                    gamesList
                }
                .padding(.horizontal, AppTheme.Spacing.screen)

                courtsSection
                    .padding(.horizontal, AppTheme.Spacing.screen)
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.tabBarClearance)
        }
        .refreshesEverything {
            reloadPlayers()
            reloadRankings()
        }
        .task {
            await friendManager.refreshRegulars()
            reloadPlayers()
        }
        .onAppear {
            reloadPlayers()
            reloadRankings()
        }
        .onChange(of: matchManager.games) { _, _ in
            reloadRankings()
        }
        .onChange(of: matchManager.rankingsRevision) { _, _ in
            reloadRankings()
        }
        .onChange(of: locationManager.nearbyCourts) { _, _ in
            reloadPlayers()
        }
        .onChange(of: locationManager.favoriteCourtIds) { _, _ in
            reloadPlayers()
        }
    }

    // MARK: 待办、球群、房间

    @ViewBuilder
    private var todoPills: some View {
        if pendingChallengeCount > 0 || !surveyManager.pendingSurveys.isEmpty {
            // 待办：带数字的小标签
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                if pendingChallengeCount > 0 {
                    CountPill(icon: "flag.2.crossed.fill", title: String(localized: "挑战"), count: pendingChallengeCount) {
                        router.open(.challenges)
                    }
                }
                if !surveyManager.pendingSurveys.isEmpty {
                    CountPill(icon: "star.bubble.fill", title: String(localized: "待评价"), count: surveyManager.pendingSurveys.count) {
                        router.open(.surveys)
                    }
                    RulesButton(title: String(localized: "待评价"), points: [String(localized: "打完 48 小时内可以评价")])
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }

    @ViewBuilder
    private var myGroupsSection: some View {
        if !groupManager.myGroups.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionTitle(title: String(localized: "我的球群"), detail: "\(groupManager.myGroups.count)")
                ForEach(groupManager.myGroups) { group in
                    Button {
                        router.open(.group(id: group.id))
                    } label: {
                        GroupCard(group: group, venue: groupManager.venue(of: group), activity: groupManager.activity(of: group.id))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }

    @ViewBuilder
    private var mySessionsSection: some View {
        if !groupManager.mySessions.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text("我报名的固定局")
                        .font(AppTheme.Typography.title3)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    RulesButton(title: String(localized: "我报名的固定局"),
                                points: [String(localized: "开场前 2 小时内退出算临时取消")])
                    Spacer(minLength: 0)
                }
                ForEach(groupManager.mySessions) { session in
                    if let group = groupManager.group(id: session.groupId) {
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                router.open(.group(id: group.id))
                            } label: {
                                Label(group.name, systemImage: "person.3.fill")
                                    .font(AppTheme.Typography.footnoteBold)
                                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                            }
                            .buttonStyle(.plain)
                            SessionRow(session: session, userId: appState.currentUser?.id ?? "") {
                                router.open(.group(id: group.id))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }

    @ViewBuilder
    private var myRoomsSection: some View {
        if !roomManager.myRooms.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionTitle(title: String(localized: "我的房间"), detail: String(localized: "\(roomManager.myRooms.count) 个进行中"))
                ForEach(roomManager.myRooms) { room in
                    Button {
                        router.open(.room(id: room.id))
                    } label: {
                        if room.invite != nil {
                            // 附近的人里的邀请：和谁、大概什么时候、轮到谁
                            InviteRoomCard(room: room, currentUserId: appState.currentUser?.id)
                        } else {
                            PublicRoomCard(room: room,
                                           distanceText: room.court.map { $0.formattedDistance(from: locationManager.coordinate) },
                                           currentUserId: appState.currentUser?.id, width: nil)
                                .overlay(alignment: .topTrailing) {
                                    if room.visibility == .privateRoom {
                                        TagPill(text: String(localized: "私密 · \(room.code)"), icon: "lock.fill", fill: AppTheme.Colors.butter)
                                            .offset(x: -12, y: -10)
                                    }
                                }
                        }
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }

    // MARK: Match requests

    @ViewBuilder
    private var ticketsSection: some View {
        let open = matchManager.openTickets
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionTitle(title: String(localized: "约球请求"), detail: String(localized: "\(open.count) 个进行中"))
                ForEach(open) { ticket in
                    Button {
                        matchManager.openTicket(ticket.id)
                    } label: {
                        TicketStatusCard(ticket: ticket, offer: matchManager.offer(for: ticket))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }

    // MARK: Quick match

    private var quickMatchCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("快速约球")
                    .font(AppTheme.Typography.title2)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("调整") { router.isMatchSetupPresented = true }
                    .font(AppTheme.Typography.footnoteBold)
                    .frame(minHeight: 32)
                    .accessibilityHint("修改模式、时间和球馆")
            }
            Button {
                router.isMatchSetupPresented = true
            } label: {
                FlowLayout(spacing: 6) {
                    summaryChip(matchManager.draft.mode.title, icon: matchManager.draft.mode.icon)
                    summaryChip(draftTimeText, icon: "clock.fill")
                    summaryChip(String(localized: "\(matchManager.draft.courtIds.count) 个球馆"), icon: "mappin")
                    summaryChip(toleranceText, icon: "chart.bar.fill")
                }
            }
            .buttonStyle(.plain)
            Button {
                startQuickMatch()
            } label: {
                ArrowButtonLabel(title: String(localized: "开始匹配"))
            }
            .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .large))
            .accessibilityHint("用当前设置立即寻找球友")
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .card(AppTheme.Colors.lime, padding: AppTheme.Spacing.xl)
    }

    private func summaryChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .lineLimit(1)
        }
        .font(AppTheme.Typography.footnoteBold)
        .foregroundStyle(AppTheme.Colors.onAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().strokeBorder(Color(hex: 0x17140F), lineWidth: 1.5))
    }

    private var draftTimeText: String {
        guard let slot = matchManager.draft.slot else { return String(localized: "选择时间") }
        let day = Calendar.current.isDateInToday(slot.date) ? String(localized: "今天") : DateText.weekday(slot.date)
        return "\(day) \(slot.formattedTimeRange)"
    }

    private var toleranceText: String {
        matchManager.draft.skillTolerance >= MatchRequest.anySkill ? String(localized: "不限水平") : String(localized: "水平 ±\(matchManager.draft.skillTolerance)")
    }

    private func startQuickMatch() {
        guard let user = appState.currentUser else { return }
        guard matchManager.draft.canSearch else {
            router.isMatchSetupPresented = true
            return
        }
        Haptics.impact()
        matchManager.startSearch(user: user, location: locationManager.coordinate,
                                 courts: locationManager.courts(ids: matchManager.draft.courtIds),
                                 radiusKm: locationManager.preferences.travelRadiusKm)
    }

    // MARK: Weekly leaderboard

    private func weeklyCard(_ standing: WeeklyStanding) -> some View {
        Button {
            router.open(.leaderboard)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "trophy.fill", fill: AppTheme.Colors.butter, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本周排行")
                        .font(AppTheme.Typography.overline)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    Text(weeklyText(standing))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            .padding(AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看本周排行")
    }

    /// 还没达到上榜门槛：只说差几场，门槛写在排行榜的规则里
    private func weeklyText(_ standing: WeeklyStanding) -> String {
        if standing.absenceReason == nil, standing.rank == nil, !standing.isQualified, standing.isCurrentWeek {
            return String(localized: "差 \(standing.gamesNeeded) 场上榜")
        }
        return standing.summary
    }

    // MARK: Public games

    private var publicGamesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: String(localized: "附近球局"), actionTitle: String(localized: "全部")) {
                router.open(.publicGames)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            if roomManager.publicRooms.isEmpty {
                EmptyStateView(icon: "sportscourt", title: String(localized: "附近暂时没有公开球局"),
                               tint: AppTheme.Colors.peach, actionTitle: String(localized: "发起球局")) {
                    router.open(.createRoom(nil, invitee: nil), in: .games)
                }
                .card()
                .padding(.horizontal, AppTheme.Spacing.screen)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        ForEach(roomManager.publicRooms) { room in
                            Button {
                                router.open(.room(id: room.id))
                            } label: {
                                PublicRoomCard(room: room, distanceText: room.court.map { $0.formattedDistance(from: locationManager.coordinate) },
                                               currentUserId: appState.currentUser?.id)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Nearby players

    /// 同馆常客：和我常去同一家球馆、并且本人开启了展示的球友（不按距离、不显示在线状态）
    @ViewBuilder
    private var playersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
                Text("同馆常客")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                if !regulars.isEmpty {
                    Text("\(regulars.count) 人")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                RulesButton(title: String(localized: "同馆常客"), points: [
                    String(localized: "设置常去球馆后，这里显示也常去那里的球友"),
                    String(localized: "对方开启了展示才会出现"),
                    String(localized: "不按距离排，也不显示在线状态")
                ])
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            if locationManager.favoriteCourtIds.isEmpty {
                Button {
                    router.open(.courts)
                } label: {
                    Label("设置常去球馆", systemImage: "heart.fill")
                }
                .buttonStyle(.brutal(.secondary, size: .small, fullWidth: false))
                .padding(.horizontal, AppTheme.Spacing.screen)
            } else if regulars.isEmpty {
                Text("暂时没有常客")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .padding(.horizontal, AppTheme.Spacing.screen)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        ForEach(regulars) { entry in
                            Button {
                                appState.showPlayer(entry.user.id)
                            } label: {
                                let acronym = VenueSearch.acronym(entry.venue.name).uppercased()
                                VStack(spacing: 6) {
                                    AvatarView(user: entry.user, size: 58)
                                    Text(entry.user.nickname)
                                        .font(AppTheme.Typography.footnoteBold)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                        .lineLimit(1)
                                    LevelBadge(tier: entry.user.displayTier, showsName: false, compact: true)
                                    Text(acronym.isEmpty ? entry.venue.name : acronym)
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("\(entry.user.nickname)，\(entry.user.displayLevelText)，常去\(entry.venue.name)")
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: Courts map

    private var courtsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: String(localized: "附近球馆"), detail: String(localized: "\(locationManager.nearbyCourts.count) 家"),
                         actionTitle: String(localized: "地图")) {
                router.open(.courts)
            }
            Button {
                router.open(.courts)
            } label: {
                CourtsMiniMap(courts: locationManager.nearbyCourts, center: locationManager.coordinate,
                              selectedIds: Set(matchManager.draft.courtIds))
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityLabel("附近 \(locationManager.nearbyCourts.count) 家球馆，打开地图")
        }
    }

    // MARK: Helpers

    private func players(of game: Game) -> [User] {
        game.playerIds.compactMap { friendManager.user(id: $0) }
    }

    private func reloadRankings() {
        guard let me = appState.currentUser?.id else {
            weeklyStanding = nil
            return
        }
        let backend = appState.backend
        let week = Rankings.week(containing: Date())
        weeklyStanding = WeeklyStanding(backend: backend, userId: me, week: week,
                                        entries: backend.weeklyLeaderboard(week: week))
    }

    private func reloadPlayers() {
        regulars = friendManager.venueRegulars(limit: 12)
    }

    /// 别人发给我、还没回应的挑战（挑战变化会刷新 matchManager，从而重绘）
    private var pendingChallengeCount: Int {
        guard let me = appState.currentUser?.id else { return 0 }
        return appState.backend.challenges().filter { $0.targetId == me && $0.status == .pending }.count
    }

    private var quickActions: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            quickAction(icon: "sportscourt.fill", title: String(localized: "发起球局"), tint: AppTheme.Colors.peach) {
                router.open(.createRoom(nil, invitee: nil))
            }
            quickAction(icon: "person.3.fill", title: String(localized: "球群"), tint: AppTheme.Colors.sky) {
                router.open(.groups)
            }
            quickAction(icon: "number", title: String(localized: "房间码"), tint: AppTheme.Colors.lavender) {
                router.open(.joinRoom(code: nil))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func quickAction(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                // 英文等长一点的语言排两行；三块按最高的那块对齐
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.lg)
            .sticker(tint, radius: AppTheme.Radius.lg)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var gamesList: some View {
        // 下一场已经在最上面了，这里不再列
        let games = segment == .upcoming ? Array(matchManager.upcomingGames.dropFirst()) : Array(matchManager.pastGames.prefix(20))
        if games.isEmpty && segment == .upcoming && matchManager.nextGame != nil {
            EmptyView()
        } else if games.isEmpty {
            EmptyStateView(
                icon: segment == .upcoming ? "calendar.badge.plus" : "clock",
                title: segment == .upcoming ? String(localized: "还没有约好的球局") : String(localized: "还没有打过的球局"),
                tint: AppTheme.Colors.sky,
                actionTitle: segment == .upcoming ? String(localized: "快速匹配") : nil,
                action: segment == .upcoming ? { router.isMatchSetupPresented = true } : nil
            )
            .card()
        } else {
            VStack(spacing: AppTheme.Spacing.md) {
                ForEach(games) { game in
                    Button {
                        router.open(.game(id: game.id))
                    } label: {
                        GameRowCard(game: game, players: game.playerIds.compactMap { friendManager.user(id: $0) },
                                    currentUserId: appState.currentUser?.id,
                                    pendingSurveyCount: surveyManager.pending(forGame: game.id).count)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
    }
}

// MARK: - 历史球局

struct GameHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var surveyManager: SurveyManager

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "历史球局"))
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    let me = appState.currentUser
                    HStack(spacing: AppTheme.Spacing.sm) {
                        StatTile(value: "\(me?.totalGames ?? 0)", label: String(localized: "总场次"))
                        StatTile(value: "\(me?.wins ?? 0)", label: String(localized: "胜场"))
                        StatTile(value: "\(me?.attendance.reliabilityPercentage ?? 100)%", label: String(localized: "履约率"))
                    }
                    if matchManager.pastGames.isEmpty {
                        EmptyStateView(icon: "clock", title: String(localized: "还没有历史球局"))
                    }
                    ForEach(matchManager.pastGames) { game in
                        Button {
                            router.open(.game(id: game.id))
                        } label: {
                            GameRowCard(game: game, players: game.playerIds.compactMap { friendManager.user(id: $0) },
                                        currentUserId: me?.id,
                                        pendingSurveyCount: surveyManager.pending(forGame: game.id).count)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
}
