import SwiftUI

/// 第一个标签“发现”：一张大卡片，左滑跳过、右滑约。
/// 上面一排选“附近的人”或某一天（这天发了约球请求的人），有待办时再一排小标签（邀请、挑战、好友申请……）。
/// 原来首页的球局、快速约球、附近球局、排行在“球局”标签里
struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var inboxManager: InboxManager

    @State private var filter = DayCardFilter.load()
    @State private var showsFilter = false
    /// 下拉刷新时加一，卡片跟着重新拉
    @State private var reloadToken = 0
    @State private var pendingChallenges = 0
    /// 附近的人里的邀请（我发的、收到的，还没结束的），和点了“好”之后要打开的球局
    @State private var invites: [Room] = []
    @State private var acceptedGameId: String?

    private var invitesForMe: [Room] {
        invites.filter { $0.invite?.awaitingId == appState.currentUser?.id && $0.status.isOpen }
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// 选的那天（已经过去的天当作“附近的人”）
    private var selectedDay: Date? {
        guard let day = appState.discoverDay, day >= Calendar.current.startOfDay(for: Date()) else { return nil }
        return Calendar.current.startOfDay(for: day)
    }

    /// 换一天就换一叠卡
    private var deckKey: String {
        selectedDay.map { "day-\($0.timeIntervalSince1970)" } ?? "nearby"
    }

    /// 没开定位：卡片那里自己会提示开定位，不再重复横幅
    private var showsLocationBanner: Bool {
        locationManager.isDenied && !(appState.isRemote && locationManager.currentLocation == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 只有上面这部分能下拉刷新：卡片要左右滑，不放进滚动视图
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    header
                        .padding(.horizontal, AppTheme.Spacing.screen)
                    dayChips
                    updates
                    if showsLocationBanner {
                        NoticeBanner(icon: "location.slash.fill", text: LocationError.permissionDenied.message,
                                     actionTitle: String(localized: "去设置")) { openSettings() }
                            .padding(.horizontal, AppTheme.Spacing.screen)
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.md)
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .fixedSize(horizontal: false, vertical: true)
            .refreshesEverything {
                reloadToken += 1
                reloadChallenges()
                await loadInvites()
            }

            DayCandidatesView(day: selectedDay, filter: $filter, showsFilter: $showsFilter, reloadToken: reloadToken)
                .id(deckKey)
                .frame(maxHeight: .infinity)
                // ✕ / ♥ 停在标签栏上面（中间的“+”比标签栏高出一截）
                .padding(.bottom, AppTheme.Spacing.tabBarClearance - AppTheme.Spacing.md)
        }
        .sheet(isPresented: $appState.showsInvites, onDismiss: {
            // 点了好：半屏收起后打开球局
            if let id = acceptedGameId {
                acceptedGameId = nil
                router.open(.game(id: id), in: .games)
            }
            Task { await loadInvites() }
        }) {
            InviteAnswerSheet(invites: invitesForMe) { room, gameId in
                answered(room, gameId: gameId)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .task {
            await loadInvites()
        }
        .onAppear {
            prepareDraft()
            reloadChallenges()
        }
        .onChange(of: appState.showsInvites) { _, showing in
            if showing { Task { await loadInvites(closesIfEmpty: true) } }
        }
        .onChange(of: matchManager.games) { _, _ in
            reloadChallenges()
        }
        .onChange(of: matchManager.rankingsRevision) { _, _ in
            reloadChallenges()
        }
        .onChange(of: inboxManager.unreadCount) { _, _ in
            reloadChallenges()
            Task { await loadInvites() }
        }
        .onChange(of: locationManager.nearbyCourts) { _, _ in
            prepareDraft()
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("发现")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                RulesButton(title: String(localized: "怎么约"), points: [
                    String(localized: "右滑约 TA，左滑跳过"),
                    String(localized: "单打：发约球邀请，TA 确认就成局"),
                    String(localized: "双打：替你开一个公开双打局并邀请 TA，附近的人可以加入补齐"),
                    String(localized: "附近的人：定了级、常去附近球馆、打开了“在同馆常客里显示我”的人"),
                    String(localized: "约附近的人：选个大概的时间和球馆，TA 说好就成局，具体几点在群聊里定"),
                    String(localized: "每天最多约 10 个，加球友不算"),
                    String(localized: "跳过或拒绝的人 30 天内不会再出现")
                ])
            }
            .padding(.horizontal, 100)
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    router.select(.profile)
                } label: {
                    MyAvatarView(size: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("我的资料")
                Spacer()
                IconButton(systemName: "bell.fill", accessibilityLabel: String(localized: "通知"), badge: inboxManager.unreadCount) {
                    router.open(.notifications)
                }
                IconButton(systemName: "line.3.horizontal.decrease", accessibilityLabel: String(localized: "筛选"),
                           badge: filter.activeCount) {
                    showsFilter = true
                }
            }
        }
    }

    // MARK: 附近的人 / 哪天

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                chip(title: String(localized: "附近的人"), count: nil, isSelected: selectedDay == nil,
                     accessibility: String(localized: "附近的人")) {
                    select(nil)
                }
                ForEach(days, id: \.self) { day in
                    let count = matchManager.availableCount(on: day, radiusKm: locationManager.preferences.travelRadiusKm)
                    chip(title: dayTitle(day), count: count,
                         isSelected: selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false,
                         accessibility: DateText.relativeDay(day) + String(localized: "，\(count) 人有空")) {
                        select(day)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "今天") }
        if calendar.isDateInTomorrow(day) { return String(localized: "明天") }
        return DateText.weekday(day)
    }

    private func chip(title: String, count: Int?, isSelected: Bool, accessibility: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppTheme.Typography.footnoteBold)
                    .lineLimit(1)
                if let count, count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.onInverse : AppTheme.Colors.ink)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: 36)
            .background(Capsule().fill(isSelected ? AppTheme.Colors.inverse : AppTheme.Colors.surface))
            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// 选某天：快速约球的日期也跟着变（和原来首页的日期条一样）
    private func select(_ day: Date?) {
        withAnimation(AppTheme.Motion.standard) { appState.discoverDay = day }
        guard let day else { return }
        matchManager.draft.day = day
        if !matchManager.draft.validation.isValid, Calendar.current.isDateInToday(day) {
            matchManager.draft.apply(TimeSlot.suggestedDefault())
        }
    }

    // MARK: 待办

    private var navigator: InboxNavigator {
        InboxNavigator(router: router, inboxManager: inboxManager, roomManager: roomManager, surveyManager: surveyManager,
                       appState: appState, matchManager: matchManager)
    }

    /// 没看过的约球消息（取消、邀请、约成……）按种类归在一起，最早出现的种类排前面
    private var actionableUpdates: [(kind: InboxItem.Kind, items: [InboxItem])] {
        // 附近的人里的邀请有自己的“邀请 N”，这里不重复
        let inviteRooms = Set(invites.map(\.id))
        let unread = inboxManager.items.filter {
            !$0.isRead && $0.kind.isActionable && $0.kind != .challenge && !inviteRooms.contains($0.relatedId ?? "")
        }
        var order: [InboxItem.Kind] = []
        var grouped: [InboxItem.Kind: [InboxItem]] = [:]
        for item in unread {
            if grouped[item.kind] == nil { order.append(item.kind) }
            grouped[item.kind, default: []].append(item)
        }
        return order.map { (kind: $0, items: grouped[$0] ?? []) }
    }

    /// 待办：一排带数字的小标签（邀请 2、挑战 1……）。只有一条就直接打开，多条去通知中心
    @ViewBuilder
    private var updates: some View {
        let groups = actionableUpdates
        let forMe = invitesForMe
        if pendingChallenges > 0 || !groups.isEmpty || !forMe.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if !forMe.isEmpty {
                        CountPill(icon: "envelope.fill", title: String(localized: "邀请"), count: forMe.count) {
                            appState.showsInvites = true
                        }
                    }
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
                // 小标签一行放不下时横着滑
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.vertical, 2)
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
        case .gameTimeSet: return String(localized: "定了时间")
        default: return String(localized: "通知")
        }
    }

    private func loadInvites(closesIfEmpty: Bool = false) async {
        guard appState.currentUser != nil, let rooms = try? await appState.backend.nearbyInvites() else { return }
        invites = rooms
        if closesIfEmpty && invitesForMe.isEmpty { appState.showsInvites = false }
    }

    private func answered(_ room: Room, gameId: String?) {
        // 这个邀请的通知也算看过了
        for item in inboxManager.items where item.relatedId == room.id && !item.isRead {
            inboxManager.markRead(item)
        }
        if let gameId { acceptedGameId = gameId }
    }

    // MARK: Helpers

    /// 别人发给我、还没回应、没过期的挑战
    private func reloadChallenges() {
        guard let me = appState.currentUser?.id else {
            pendingChallenges = 0
            return
        }
        pendingChallenges = appState.backend.challenges()
            .filter { $0.targetId == me && $0.status == .pending && !$0.isExpired() }
            .count
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
