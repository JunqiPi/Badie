import SwiftUI

/// 第一个标签“发现”：一张大卡片，左滑跳过、右滑约。
/// 最上面一行是“附近 · 什么时候”和城市（点开选哪天），下面一排圆头像是等我处理的人（谁约了我、谁想加我……）。
/// 原来首页的球局、快速约球、附近球局、排行在“球局”标签里
struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var inboxManager: InboxManager
    @EnvironmentObject private var friendManager: FriendManager

    @State private var filter = DayCardFilter.load()
    @State private var showsFilter = false
    @State private var showsWhen = false
    /// 下拉刷新时加一，卡片跟着重新拉
    @State private var reloadToken = 0
    /// 别人发给我、还没回应、没过期的挑战
    @State private var challenges: [Challenge] = []
    /// 附近的人里的邀请（我发的、收到的，还没结束的），和点了“好”之后要打开的球局
    @State private var invites: [Room] = []
    @State private var acceptedGameId: String?
    /// 点了某个人的“约你”：半屏只回这一个
    @State private var answeringId: String?

    private var invitesForMe: [Room] {
        invites.filter { $0.invite?.awaitingId == appState.currentUser?.id && $0.status.isOpen }
    }

    /// 从圆头像点进来只回那一个；从通知进来的回全部
    private var answering: [Room] {
        guard let answeringId else { return invitesForMe }
        return invitesForMe.filter { $0.id == answeringId }
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// 选的那天（已经过去的天当作“任何时间”）
    private var selectedDay: Date? {
        guard let day = appState.discoverDay, day >= Calendar.current.startOfDay(for: Date()) else { return nil }
        return Calendar.current.startOfDay(for: day)
    }

    /// 换一天就换一叠卡（旧的那叠还没拉完的结果也跟着丢掉）
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
                    storyRow
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
                // ✕ ♥ ★ 停在标签栏上面（中间的“+”比标签栏高出一截）
                .padding(.bottom, AppTheme.Spacing.tabBarClearance - AppTheme.Spacing.md)
        }
        .sheet(isPresented: $showsWhen) {
            whenSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $appState.showsInvites, onDismiss: {
            answeringId = nil
            // 点了好：半屏收起后打开球局
            if let id = acceptedGameId {
                acceptedGameId = nil
                router.open(.game(id: id), in: .games)
            }
            Task { await loadInvites() }
        }) {
            InviteAnswerSheet(invites: answering) { room, gameId in
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

    /// 左边“附近 · 任何时间 / 城市 ▾”（点开选哪天），右边通知和筛选
    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                showsWhen = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "附近 · \(whenTitle)"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.Colors.lime)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 3))
                            .accessibilityHidden(true)
                        Text(place)
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityElement(children: .combine)
            IconButton(systemName: "bell.fill", accessibilityLabel: String(localized: "通知"), badge: inboxManager.unreadCount) {
                router.open(.notifications)
            }
            IconButton(systemName: "line.3.horizontal.decrease", accessibilityLabel: String(localized: "筛选"),
                       badge: filter.activeCount) {
                showsFilter = true
            }
        }
    }

    private var whenTitle: String {
        selectedDay.map { dayTitle($0) } ?? String(localized: "任何时间")
    }

    /// 最近那家球馆所在的城市；没开定位、还没有球馆就写“附近”
    private var place: String {
        guard !locationManager.isDenied, !(appState.isRemote && locationManager.currentLocation == nil),
              let city = locationManager.nearbyCourts.first?.postalAddress.city, !city.isEmpty else {
            return String(localized: "附近")
        }
        return city
    }

    // MARK: 什么时候

    /// 任何时间（附近的人）、今天、明天……后面写这天有几个人有空
    private var whenSheet: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("什么时候")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, AppTheme.Spacing.xl)
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    whenRow(String(localized: "任何时间"), detail: nil, isSelected: selectedDay == nil) { pick(nil) }
                    ForEach(days, id: \.self) { day in
                        let count = matchManager.availableCount(on: day, radiusKm: locationManager.preferences.travelRadiusKm)
                        whenRow(dayTitle(day), detail: count > 0 ? String(localized: "\(count) 人有空") : nil, dimmed: count == 0,
                                isSelected: selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false) {
                            pick(day)
                        }
                    }
                }
                .padding(.bottom, AppTheme.Spacing.lg)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func whenRow(_ title: String, detail: String?, dimmed: Bool = false, isSelected: Bool,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(AppTheme.Typography.footnoteBold)
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.onAccent : dimmed ? AppTheme.Colors.inkTertiary : AppTheme.Colors.ink)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 52)
            .sticker(isSelected ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.md,
                     shadow: isSelected ? AppTheme.Elevation.low : .zero)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "今天") }
        if calendar.isDateInTomorrow(day) { return String(localized: "明天") }
        return DateText.weekday(day)
    }

    /// 选好就收起；快速约球的日期也跟着变（和原来首页的日期条一样）
    private func pick(_ day: Date?) {
        showsWhen = false
        withAnimation(AppTheme.Motion.standard) { appState.discoverDay = day }
        guard let day else { return }
        matchManager.draft.day = day
        if !matchManager.draft.validation.isValid, Calendar.current.isDateInToday(day) {
            matchManager.draft.apply(TimeSlot.suggestedDefault())
        }
    }

    // MARK: 圆头像

    /// 一个等我处理的人：谁约了我、谁想加我、谁挑战我、找到的搭子等我确认
    private struct Story: Identifiable {
        enum Kind { case invite, friend, challenge, offer }

        let kind: Kind
        let userId: String
        /// 邀请的房间
        var roomId: String?
        /// 好友申请、待确认的通知
        var item: InboxItem?

        var id: String { "\(kind)-\(userId)" }

        var ring: Color {
            switch kind {
            case .invite: return AppTheme.Colors.lime
            case .friend: return AppTheme.Colors.lavender
            case .challenge: return AppTheme.Colors.peach
            case .offer: return AppTheme.Colors.sky
            }
        }
    }

    private var navigator: InboxNavigator {
        InboxNavigator(router: router, inboxManager: inboxManager, roomManager: roomManager, surveyManager: surveyManager,
                       appState: appState, matchManager: matchManager)
    }

    /// 没有人的通知（球局取消、有人加入……）不放这里，看铃铛
    private var stories: [Story] {
        let me = appState.currentUser?.id
        var list = invitesForMe.compactMap { room in
            room.invite.map { Story(kind: .invite, userId: $0.other(than: me), roomId: room.id) }
        }
        list += challenges.map { Story(kind: .challenge, userId: $0.challengerId) }
        for item in inboxManager.items where !item.isRead {
            if item.kind == .friendRequest, let id = item.relatedId, !friendManager.isFriend(id) {
                list.append(Story(kind: .friend, userId: id, item: item))
            } else if item.kind == .matchOffer, let id = offerPartner(item) {
                list.append(Story(kind: .offer, userId: id, item: item))
            }
        }
        // 同一个人同一件事只放一个
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// 第一个是“+ 约球”，后面每个人一个圆头像，多了横着滑
    private var storyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                storyButton(String(localized: "约球"), ring: AppTheme.Colors.lime) {
                    router.isMatchSetupPresented = true
                } face: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(AppTheme.Colors.onAccent)
                }
                ForEach(stories) { story in
                    storyButton(storyTitle(story), ring: story.ring) {
                        open(story)
                    } face: {
                        if let user = friendManager.user(id: story.userId) {
                            AvatarView(user: user, size: 52)
                        } else {
                            AvatarView(text: "?", size: 52)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.xxs)
        }
    }

    private func storyButton<Face: View>(_ title: String, ring: Color, action: @escaping () -> Void,
                                         @ViewBuilder face: () -> Face) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xs) {
                face()
                    .frame(width: 52, height: 52)
                    .padding(4)
                    .background(Circle().fill(ring))
                    .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 72)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private func storyTitle(_ story: Story) -> String {
        let name = friendManager.user(id: story.userId)?.nickname ?? String(localized: "TA")
        switch story.kind {
        case .invite: return String(localized: "\(name) 约你")
        case .friend: return String(localized: "\(name) 加你")
        case .challenge: return String(localized: "\(name) 挑战")
        case .offer: return String(localized: "待确认")
        }
    }

    /// 和原来的小标签点开的一样：邀请 → 回邀请的半屏；挑战 → 挑战列表；好友申请 → TA 的资料；待确认 → 约球请求
    private func open(_ story: Story) {
        switch story.kind {
        case .invite: if let id = story.roomId { openInvite(id) }
        case .challenge: router.open(.challenges)
        case .friend, .offer: if let item = story.item { navigator.open(item) }
        }
    }

    /// 先刷新：已经回过或过期了就说一声，圆头像也跟着没了
    private func openInvite(_ roomId: String) {
        Task {
            await loadInvites()
            guard invitesForMe.contains(where: { $0.id == roomId }) else {
                appState.showToast(String(localized: "邀请已经结束了"))
                return
            }
            answeringId = roomId
            appState.showsInvites = true
        }
    }

    /// 找到的搭子：通知里是约球请求的 ID，取这组里的另一个人（已经不在等确认了就不放）
    private func offerPartner(_ item: InboxItem) -> String? {
        guard let ticket = matchManager.tickets.first(where: { $0.id == item.relatedId }),
              let offer = matchManager.offer(for: ticket) else { return nil }
        return offer.seats.first { $0.userId != appState.currentUser?.id }?.userId
    }

    private func loadInvites(closesIfEmpty: Bool = false) async {
        guard appState.currentUser != nil, let rooms = try? await appState.backend.nearbyInvites() else { return }
        invites = rooms
        if closesIfEmpty && answering.isEmpty { appState.showsInvites = false }
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
            challenges = []
            return
        }
        challenges = appState.backend.challenges()
            .filter { $0.targetId == me && $0.status == .pending && !$0.isExpired() }
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
