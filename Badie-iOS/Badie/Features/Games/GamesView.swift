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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                LargeTitleHeader(title: String(localized: "球局"), subtitle: String(localized: "我的约球与房间")) {
                    IconButton(systemName: "clock.arrow.circlepath", accessibilityLabel: String(localized: "历史球局")) {
                        router.open(.gameHistory)
                    }
                }

                quickActions
                    .padding(.horizontal, AppTheme.Spacing.screen)

                if !surveyManager.pendingSurveys.isEmpty {
                    Button {
                        router.open(.surveys)
                    } label: {
                        NoticeBanner(icon: "star.bubble.fill",
                                     text: String(localized: "有 \(surveyManager.pendingSurveys.count) 位球友等你评价，48 小时内有效"),
                                     tint: AppTheme.Colors.pink)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }

                if !matchManager.openTickets.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(title: String(localized: "等待匹配"), detail: String(localized: "所有人确认后会出现在下面"))
                        ForEach(matchManager.openTickets) { ticket in
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

                if !groupManager.mySessions.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(title: String(localized: "我报名的固定局"), detail: String(localized: "开场前 2 小时内退出算临时取消"))
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

                if !roomManager.myRooms.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(title: String(localized: "我的房间"), detail: String(localized: "\(roomManager.myRooms.count) 个进行中"))
                        ForEach(roomManager.myRooms) { room in
                            Button {
                                router.open(.room(id: room.id))
                            } label: {
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
                            .buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SegmentedSticker(options: Segment.allCases, selection: $segment, title: { $0.title }) { option in
                        option == .upcoming ? matchManager.upcomingGames.count : 0
                    }
                    gamesList
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.tabBarClearance)
        }
        .refreshable {
            matchManager.reloadGames()
            roomManager.reload()
            surveyManager.refresh()
        }
    }

    private var quickActions: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            quickAction(icon: "sportscourt.fill", title: String(localized: "发起球局"), subtitle: String(localized: "有场地缺人"), tint: AppTheme.Colors.peach) {
                router.open(.createRoom(nil, invitee: nil))
            }
            quickAction(icon: "person.3.fill", title: String(localized: "固定局"), subtitle: String(localized: "每周固定的球群"), tint: AppTheme.Colors.sky) {
                router.open(.groups)
            }
            quickAction(icon: "number", title: String(localized: "房间码"), subtitle: String(localized: "房间码或群号"), tint: AppTheme.Colors.lavender) {
                router.open(.joinRoom(code: nil))
            }
        }
    }

    private func quickAction(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(AppTheme.Typography.headline)
                Text(subtitle)
                    .font(AppTheme.Typography.caption)
                    .opacity(0.75)
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.lg)
            .sticker(tint, radius: AppTheme.Radius.lg)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var gamesList: some View {
        let games = segment == .upcoming ? matchManager.upcomingGames : Array(matchManager.pastGames.prefix(20))
        if games.isEmpty {
            EmptyStateView(
                icon: segment == .upcoming ? "calendar.badge.plus" : "clock",
                title: segment == .upcoming ? String(localized: "还没有约好的球局") : String(localized: "还没有打过的球局"),
                message: segment == .upcoming ? String(localized: "快速匹配一个搭子，或者发起球局招募附近球友。") : String(localized: "打完的球局和结果会出现在这里。"),
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
