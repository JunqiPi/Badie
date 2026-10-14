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

                if locationManager.isDenied {
                    NoticeBanner(icon: "location.slash.fill", text: LocationError.permissionDenied.message,
                                 actionTitle: "去设置") { openSettings() }
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

                dateSection

                if let survey = surveyManager.pendingSurveys.first {
                    surveyBanner(survey)
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
        .refreshable {
            locationManager.refreshCourts()
            roomManager.reload()
            reloadPlayers()
        }
        .onAppear {
            reloadPlayers()
            prepareDraft()
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text("\(greeting)，\(appState.currentUser?.nickname ?? "球友")")
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                Spacer()
                IconButton(systemName: "bell.fill", accessibilityLabel: "通知", badge: inboxManager.unreadCount) {
                    router.open(.notifications)
                }
                Button {
                    router.select(.profile)
                } label: {
                    MyAvatarView(size: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("我的资料")
            }
            (Text("今晚，\n打") + Text(markedText: "一场") + Text("？"))
                .font(AppTheme.Typography.display)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityLabel("今晚，打一场？")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }

    // MARK: Match requests

    @ViewBuilder
    private var ticketsSection: some View {
        let open = matchManager.openTickets
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionTitle(title: "约球请求", detail: "\(open.count) 个进行中")
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
                    .font(AppTheme.Typography.overline)
                    .tracking(0.8)
                Spacer()
                Button("调整") { router.isMatchSetupPresented = true }
                    .font(AppTheme.Typography.footnoteBold)
                    .frame(minHeight: 32)
                    .accessibilityHint("修改模式、时间和球馆")
            }
            Text("按水平和时间\n自动帮你找搭子")
                .font(AppTheme.Typography.title2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                router.isMatchSetupPresented = true
            } label: {
                FlowLayout(spacing: 6) {
                    summaryChip(matchManager.draft.mode.title, icon: matchManager.draft.mode.icon)
                    summaryChip(draftTimeText, icon: "clock.fill")
                    summaryChip("\(matchManager.draft.courtIds.count) 个球馆", icon: "mappin")
                    summaryChip(toleranceText, icon: "chart.bar.fill")
                }
            }
            .buttonStyle(.plain)
            Button {
                startQuickMatch()
            } label: {
                ArrowButtonLabel(title: "开始匹配")
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
        guard let slot = matchManager.draft.slot else { return "选择时间" }
        let day = Calendar.current.isDateInToday(slot.date) ? "今天" : DateText.weekday(slot.date)
        return "\(day) \(slot.formattedTimeRange)"
    }

    private var toleranceText: String {
        matchManager.draft.skillTolerance >= MatchRequest.anySkill ? "不限水平" : "水平 ±\(matchManager.draft.skillTolerance)"
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: "哪天有空？", detail: "附近可约人数")
                .padding(.horizontal, AppTheme.Spacing.screen)
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
                counts: { matchManager.availableCount(on: $0, radiusKm: locationManager.preferences.travelRadiusKm) }
            )
        }
    }

    // MARK: Survey reminder

    private func surveyBanner(_ survey: PendingSurvey) -> some View {
        Button {
            router.open(.survey(pendingId: survey.id), in: .games)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                AvatarView(text: survey.opponentAvatarText, paletteIndex: survey.opponentAvatar.paletteIndex, size: 40)
                    .opensProfile(survey.opponentId, allowsInvite: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("给 \(survey.opponentNickname) 的球局打个分")
                        .font(AppTheme.Typography.headline)
                    Text("\(DateText.remaining(until: survey.expiresAt)) · 匿名汇总，帮社区更靠谱")
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

    // MARK: Public games

    private var publicGamesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: "附近球局", detail: "有场地缺人", actionTitle: "全部") {
                router.open(.publicGames)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            if roomManager.publicRooms.isEmpty {
                EmptyStateView(icon: "sportscourt", title: "附近暂时没有公开球局",
                               message: "订好场地却缺人？发起一个，附近球友会看到。",
                               tint: AppTheme.Colors.peach, actionTitle: "发起球局") {
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
            SectionTitle(title: "同馆常客", detail: regulars.isEmpty ? nil : "\(regulars.count) 人")
                .padding(.horizontal, AppTheme.Spacing.screen)
            if locationManager.favoriteCourtIds.isEmpty {
                NoticeBanner(icon: "heart.fill", text: "设置常去球馆后，这里会显示也常去那里的球友（对方开启了才会出现）。",
                             tint: AppTheme.Colors.surfaceMuted, actionTitle: "去设置") {
                    router.open(.courts)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
            } else if regulars.isEmpty {
                Text("还没有球友公开自己是这些球馆的常客")
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
                                VStack(spacing: 6) {
                                    AvatarView(user: entry.user, size: 58)
                                    Text(entry.user.nickname)
                                        .font(AppTheme.Typography.footnoteBold)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                        .lineLimit(1)
                                    LevelBadge(tier: entry.user.displayTier, showsName: false, compact: true)
                                    Text(VenueSearch.acronym(entry.venue.name).uppercased().isEmpty
                                         ? entry.venue.name : VenueSearch.acronym(entry.venue.name).uppercased())
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
            SectionTitle(title: "固定局", detail: groupManager.myGroups.isEmpty ? "不用再在群里接龙" : "\(groupManager.myGroups.count) 个球群",
                         actionTitle: "全部") {
                router.open(.groups)
            }
            if groupManager.mySessions.isEmpty {
                Button {
                    router.open(.groups)
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        IconTile(systemName: "person.3.fill", fill: AppTheme.Colors.lavender, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("找个固定局")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Text("每周固定时间和球馆，一键报名，满了自动候补")
                                .font(AppTheme.Typography.footnote)
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
        case .signedUp: return "已报名 · \(session.signedUp.count)/\(session.capacity) 人"
        case .waitlisted(let position): return "候补第 \(position) 位 · 有人退出自动递补"
        case .none: return "\(session.signedUp.count)/\(session.capacity) 人"
        }
    }

    // MARK: Courts map

    private var courtsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: "附近球馆", detail: "\(locationManager.nearbyCourts.count) 家",
                         actionTitle: "地图") {
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
