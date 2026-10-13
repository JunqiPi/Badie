import SwiftUI

/// 主框架：四个标签页各自一条导航栈 + 悬浮标签栏 + 中间“+”创建按钮
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var pendingCreateAction: CreateAction?

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(MainTab.allCases) { tab in
                NavigationStack(path: router.binding(for: tab)) {
                    rootView(for: tab)
                        .screenChrome()
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route)
                                .screenChrome()
                        }
                }
                .opacity(router.selectedTab == tab ? 1 : 0)
                .allowsHitTesting(router.selectedTab == tab)
                .accessibilityHidden(router.selectedTab != tab)
            }

            if router.isTabBarVisible {
                FloatingTabBar(badges: badges) {
                    router.isCreateMenuPresented = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Motion.standard, value: router.isTabBarVisible)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $router.isCreateMenuPresented, onDismiss: runPendingCreateAction) {
            CreateMenuSheet { action in
                pendingCreateAction = action
                router.isCreateMenuPresented = false
            }
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $router.isMatchSetupPresented) {
            MatchSetupView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: $matchManager.isFlowPresented) {
            MatchFlowView()
        }
        .sheet(item: $appState.presentedPlayer) { item in
            PlayerProfileSheet(userId: item.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .onChange(of: matchManager.justConfirmedGame) { _, game in
            guard let game else { return }
            router.show(.game(id: game.id), in: .games)
            matchManager.justConfirmedGame = nil
        }
        .onChange(of: roomManager.startedGameId) { _, gameId in
            guard let gameId else { return }
            appState.showToast("球局已开始组队，查看详情", style: .success)
            router.show(.game(id: gameId), in: .games)
            roomManager.startedGameId = nil
        }
        .onChange(of: roomManager.notice) { _, notice in
            guard let notice else { return }
            appState.showToast(notice)
            roomManager.notice = nil
        }
        .onChange(of: locationManager.preferences.travelRadiusKm) { _, radius in
            roomManager.radiusKm = radius
            roomManager.reload()
        }
        .onAppear {
            roomManager.radiusKm = locationManager.preferences.travelRadiusKm
            roomManager.reload()
        }
    }

    @ViewBuilder
    private func rootView(for tab: MainTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .games: GamesView()
        case .messages: MessagesView()
        case .profile: ProfileView()
        }
    }

    private var badges: [MainTab: Int] {
        [
            .games: surveyManager.pendingSurveys.count,
            .messages: messageManager.unreadCount + friendManager.incomingRequests.count
        ]
    }

    private func runPendingCreateAction() {
        guard let action = pendingCreateAction else { return }
        pendingCreateAction = nil
        switch action {
        case .quickMatch:
            router.isMatchSetupPresented = true
        case .createRoom:
            router.open(.createRoom(nil, invitee: nil), in: .games)
        case .joinRoom:
            router.open(.joinRoom(code: nil), in: .games)
        }
    }
}

// MARK: - 悬浮标签栏

struct FloatingTabBar: View {
    @EnvironmentObject private var router: Router
    let badges: [MainTab: Int]
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.games)
            createButton
            tabButton(.messages)
            tabButton(.profile)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(height: 68)
        .sticker(AppTheme.Colors.surface, radius: 26, shadow: CGSize(width: 0, height: 4))
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .background(alignment: .bottom) { scrim }
    }

    /// 标签栏后方的渐隐底色：滚动内容在标签栏上方淡出，不会从标签栏四周露出来
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: AppTheme.Colors.canvas.opacity(0), location: 0),
                .init(color: AppTheme.Colors.canvas.opacity(0.94), location: 0.42),
                .init(color: AppTheme.Colors.canvas, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 124)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let selected = router.selectedTab == tab
        return Button {
            Haptics.selection()
            router.select(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if let count = badges[tab], count > 0 {
                            CountBadge(count: count)
                                .offset(x: 12, y: -8)
                        }
                    }
                Text(tab.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Circle()
                    .fill(selected ? AppTheme.Colors.ink : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(tab.title)
        .accessibilityValue(badges[tab].map { $0 > 0 ? "\($0) 条未处理" : "" } ?? "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var createButton: some View {
        Button {
            Haptics.impact()
            onCreate()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(AppTheme.Colors.onAccent)
                .frame(width: 62, height: 62)
                .background(Circle().fill(AppTheme.Colors.lime))
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                .background(Circle().fill(AppTheme.Colors.shadow).offset(y: 4))
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .offset(y: -18)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("约球")
        .accessibilityHint("快速匹配、发起球局或输入房间码")
    }
}

// MARK: - “+”创建菜单

enum CreateAction {
    case quickMatch, createRoom, joinRoom
}

struct CreateMenuSheet: View {
    let onSelect: (CreateAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("约一场")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            option(icon: "bolt.fill", tint: AppTheme.Colors.lime, title: "快速匹配",
                   subtitle: "按水平、时间和距离自动找搭子", action: .quickMatch)
            option(icon: "sportscourt.fill", tint: AppTheme.Colors.peach, title: "发起球局",
                   subtitle: "我有场地缺人 / 约好友组局，可公开招募", action: .createRoom)
            option(icon: "number", tint: AppTheme.Colors.lavender, title: "输入房间码",
                   subtitle: "好友发来了 6 位房间码", action: .joinRoom)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func option(icon: String, tint: Color, title: String, subtitle: String, action: CreateAction) -> some View {
        Button {
            Haptics.tap()
            onSelect(action)
        } label: {
            HStack(spacing: AppTheme.Spacing.lg) {
                IconTile(systemName: icon, fill: tint, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text(subtitle)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            .padding(AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
