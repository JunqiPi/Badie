import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var inboxManager: InboxManager
    @EnvironmentObject private var groupManager: GroupManager

    @State private var regulars: [VenueRegular] = []
    @State private var weeklyStanding: WeeklyStanding?
    @State private var pendingChallenges = 0

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                header
                    .padding(.horizontal, AppTheme.Spacing.screen)

                dateSection

                updates
                    .padding(.horizontal, AppTheme.Spacing.screen)

                if locationManager.isDenied {
                    NoticeBanner(icon: "location.slash.fill", text: LocationError.permissionDenied.message,
                                 actionTitle: String(localized: "去设置")) { openSettings() }
                        .padding(.horizontal, AppTheme.Spacing.screen)
                }

                if let game = matchManager.nextGame {
                    Button {
                        router.open(.game(id: game.id), in: .games)
                    } label: {
                        GameTicketCard(game: game, players: players(of: game), currentUserId: appState.currentUser?.id, compact: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }

                ticketsSection

                quickMatchCard
                    .padding(.horizontal, AppTheme.Spacing.screen)

                if let survey = surveyManager.pendingSurveys.first {
                    surveyBanner(survey)
                        .padding(.horizontal, AppTheme.Spacing.screen)
                }

                if let weeklyStanding {
                    weeklyCard(weeklyStanding)
                        .padding(.horizontal, AppTheme.Spacing.screen)
                }

                groupsSection
                    .padding(.horizontal, AppTheme.Spacing.screen)
                publicGamesSection
                playersSection
                courtsSection
                    .padding(.horizontal, AppTheme.Spacing.screen)
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.tabBarClearance)
        }
        // 下拉刷新只给首页这一屏（放在弹出的全屏页之前，不然卡片页和筛选页也会跟着下拉刷新）
        .refreshesEverything {
            reloadPlayers()
            reloadRankings()
        }
        .fullScreenCover(isPresented: $appState.showsDayCards) {
            DayCandidatesView(day: matchManager.draft.day)
        }
        .task {
            await friendManager.refreshRegulars()
            reloadPlayers()
        }
        .onAppear {
            reloadPlayers()
            prepareDraft()
            reloadRankings()
        }
        .onChange(of: matchManager.games) { _, _ in
            reloadRankings()
        }
        .onChange(of: matchManager.rankingsRevision) { _, _ in
            reloadRankings()
        }
        .onChange(of: inboxManager.unreadCount) { _, _ in
            reloadRankings()
        }
        .onChange(of: locationManager.nearbyCourts) { _, _ in
            prepareDraft()
            reloadPlayers()
        }
        .onChange(of: locationManager.favoriteCourtIds) { _, _ in
            reloadPlayers()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    router.select(.profile)
                } label: {
                    MyAvatarView(size: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("我的资料")
                Spacer()
                IconButton(systemName: "trophy.fill", accessibilityLabel: String(localized: "排行榜")) {
                    router.open(.leaderboard)
                }
                IconButton(systemName: "bell.fill", accessibilityLabel: String(localized: "通知"), badge: inboxManager.unreadCount) {
                    router.open(.notifications)
                }
            }
            Text(marking: String(localized: "今晚，\n打*一场*？"))
                .font(AppTheme.Typography.display)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityLabel("今晚，打一场？")
                .accessibilityAddTraits(.isHeader)
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

    // MARK: Date strip

    private var dateSection: some View {
        DateStrip(
            days: days,
            selection: Binding(
                get: { matchManager.draft.day },
                set: { day in
                    matchManager.draft.day = day
                    if !matchManager.draft.validation.isValid, Calendar.current.isDateInToday(day) {
                        matchManager.draft.apply(TimeSlot.suggestedDefault())
                    }
                }
            ),
            counts: { matchManager.availableCount(on: $0, radiusKm: locationManager.preferences.travelRadiusKm) },
            onTap: { _ in appState.showsDayCards = true }
        )
    }

    // MARK: Survey reminder

    private func surveyBanner(_ survey: PendingSurvey) -> some View {
        Button {
            router.open(.survey(pendingId: survey.id), in: .games)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                AvatarView(avatar: survey.opponentAvatar, userId: survey.opponentId, text: survey.opponentAvatarText, size: 40)
                    .opensProfile(survey.opponentId, allowsInvite: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("评价 \(survey.opponentNickname)")
                        .font(AppTheme.Typography.headline)
                    Text(DateText.remaining(until: survey.expiresAt))
                        .font(AppTheme.Typography.footnote)
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            .padding(AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.pink, radius: AppTheme.Radius.lg)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
    }

    // MARK: 约球动态

    private var navigator: InboxNavigator {
        InboxNavigator(router: router, inboxManager: inboxManager, roomManager: roomManager, surveyManager: surveyManager,
                       appState: appState, matchManager: matchManager)
    }

    /// 没看过的约球消息（取消、邀请、约成……）按种类归在一起，最早出现的种类排前面
    private var actionableUpdates: [(kind: InboxItem.Kind, items: [InboxItem])] {
        let unread = inboxManager.items.filter { !$0.isRead && $0.kind.isActionable && $0.kind != .challenge }
        var order: [InboxItem.Kind] = []
        var grouped: [InboxItem.Kind: [InboxItem]] = [:]
        for item in unread {
            if grouped[item.kind] == nil { order.append(item.kind) }
            grouped[item.kind, default: []].append(item)
        }
        return order.map { (kind: $0, items: grouped[$0] ?? []) }
    }

    /// 待办：一排带数字的小标签（挑战 1、好友申请 1……）。只有一条就直接打开，多条去通知中心
    @ViewBuilder
    private var updates: some View {
        let groups = actionableUpdates
        if pendingChallenges > 0 || !groups.isEmpty {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                if pendingChallenges > 0 {
                    CountPill(icon: "flag.2.crossed.fill", title: String(localized: "挑战"), count: pendingChallenges) {
                        router.open(.challenges)
                    }
                }
                ForEach(groups, id: \.kind) { group in
                    CountPill(icon: group.kind.icon, title: pillTitle(group.kind), count: group.items.count) {
                        if group.items.count == 1, let item = group.items.first {
                            navigator.open(item)
                        } else {
                            router.open(.notifications)
                        }
                    }
                }
            }
        }
    }

    private func pillTitle(_ kind: InboxItem.Kind) -> String {
        switch kind {
        case .friendRequest: return String(localized: "好友申请")
        case .matchOffer: return String(localized: "待确认")
        case .gameConfirmed: return String(localized: "已约成")
        case .roomInvite: return String(localized: "邀请")
        case .roomJoined: return String(localized: "有人加入")
        case .waitlistPromoted: return String(localized: "候补转正")
        case .messageRequest: return String(localized: "消息请求")
        case .gameCancelled: return String(localized: "已取消")
        case .kicked: return String(localized: "被移出")
        case .roomClosed: return String(localized: "球局关闭")
        case .challenge: return String(localized: "挑战")
        default: return String(localized: "通知")
        }
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

    // MARK: Groups

    /// 我的固定局（已报名 / 候补）+ 找球群入口
    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: String(localized: "固定局"), detail: groupManager.myGroups.isEmpty ? nil : String(localized: "\(groupManager.myGroups.count) 个球群"),
                         actionTitle: String(localized: "全部")) {
                router.open(.groups)
            }
            if groupManager.mySessions.isEmpty {
                Button {
                    router.open(.groups)
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        IconTile(systemName: "person.3.fill", fill: AppTheme.Colors.lavender, size: 44)
                        Text("找个固定局")
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                    .padding(AppTheme.Spacing.lg)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            } else {
                ForEach(groupManager.mySessions.prefix(2)) { session in
                    if let group = groupManager.group(id: session.groupId) {
                        Button {
                            router.open(.group(id: group.id))
                        } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                IconTile(systemName: "calendar.badge.checkmark", fill: AppTheme.Colors.lime, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(AppTheme.Typography.overline)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                    Text(session.slot.formattedFull)
                                        .font(AppTheme.Typography.headline)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                    Text(sessionStatus(session))
                                        .font(AppTheme.Typography.footnoteBold)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                            }
                            .padding(AppTheme.Spacing.lg)
                            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            }
        }
    }

    private func sessionStatus(_ session: GroupSession) -> String {
        switch session.status(of: appState.currentUser?.id ?? "") {
        case .signedUp: return String(localized: "已报名 · \(session.signedUp.count)/\(session.capacity) 人")
        case .waitlisted(let position): return String(localized: "候补第 \(position) 位")
        case .none: return String(localized: "\(session.signedUp.count)/\(session.capacity) 人")
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
        let backend = appState.backend
        guard let me = appState.currentUser?.id else {
            weeklyStanding = nil
            pendingChallenges = 0
            return
        }
        let week = Rankings.week(containing: Date())
        weeklyStanding = WeeklyStanding(backend: backend, userId: me, week: week,
                                        entries: backend.weeklyLeaderboard(week: week))
        pendingChallenges = backend.challenges()
            .filter { $0.targetId == me && $0.status == .pending && !$0.isExpired() }
            .count
    }

    private func reloadPlayers() {
        regulars = friendManager.venueRegulars(limit: 12)
    }

    private func prepareDraft() {
        matchManager.prepareDraft(
            user: appState.currentUser,
            nearbyCourts: locationManager.nearbyCourts,
            recurring: appState.backend.recurringSlots(),
            favorites: locationManager.favoriteCourts.map(\.id),
            isValidCourt: { locationManager.court(id: $0) != nil }
        )
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 小地图（不可交互，点击进入球馆页）

struct CourtsMiniMap: View {
    let courts: [BadmintonCourt]
    let center: Coordinate
    var selectedIds: Set<String> = []

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: center.clCoordinate, latitudinalMeters: 14_000, longitudinalMeters: 14_000)),
            interactionModes: []) {
            ForEach(courts) { court in
                Annotation(court.name, coordinate: court.location.clCoordinate, anchor: .bottom) {
                    CourtPin(isSelected: selectedIds.contains(court.id))
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }
}

struct CourtPin: View {
    var isSelected = false
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "figure.badminton")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(AppTheme.Colors.onAccent)
            .frame(width: size, height: size)
            .background(Circle().fill(isSelected ? AppTheme.Colors.lime : AppTheme.Colors.sky))
            .overlay(Circle().strokeBorder(Color(hex: 0x17140F), lineWidth: 2))
            .background(Circle().fill(Color(hex: 0x17140F)).offset(x: 1.5, y: 2))
            .scaleEffect(isSelected ? 1.15 : 1)
    }
}
