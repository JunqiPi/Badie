import SwiftUI

/// 第一个标签“发现”：一张大卡片，左滑跳过、右滑约。
/// 最上面一行左边是附近范围（点开选 5 / 10 / 20 / 50 公里），右边是球馆、通知、筛选（选哪天也在筛选里）；
/// 下面一排圆头像是这叠卡里的人（DayCandidatesView）。谁约了我、谁想加我这类待办在通知里。
/// 原来首页的球局、快速约球、附近球局、排行在“球局”标签里
struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var inboxManager: InboxManager

    @State private var filter = DayCardFilter.load()
    @State private var showsFilter = false
    /// 下拉刷新时加一，卡片跟着重新拉
    @State private var reloadToken = 0
    /// 附近的人里的邀请（我发的、收到的，还没结束的），和点了“好”之后要打开的球局
    @State private var invites: [Room] = []
    @State private var acceptedGameId: String?

    /// 轮到我回的邀请（从通知或演示打开的半屏里一个一个回）
    private var answering: [Room] {
        invites.filter { $0.invite?.awaitingId == appState.currentUser?.id && $0.status.isOpen }
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
                    if showsLocationBanner {
                        NoticeBanner(icon: "location.slash.fill", text: LocationError.permissionDenied.message,
                                     actionTitle: String(localized: "去设置")) { openSettings() }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.sm)
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .fixedSize(horizontal: false, vertical: true)
            .refreshesEverything {
                reloadToken += 1
                await loadInvites()
            }

            DayCandidatesView(day: selectedDay, filter: $filter, showsFilter: $showsFilter, reloadToken: reloadToken)
                .id(deckKey)
                .frame(maxHeight: .infinity)
                // ✕ ♥ ★ 停在标签栏上面（中间的“+”比标签栏高出一截）
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
        }
        .onChange(of: appState.showsInvites) { _, showing in
            if showing { Task { await loadInvites(closesIfEmpty: true) } }
        }
        .onChange(of: locationManager.nearbyCourts) { _, _ in
            prepareDraft()
        }
    }

    // MARK: Header

    /// 左边“附近 / 10 公里内 ▾”（点开选范围），右边球馆、通知、筛选
    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Menu {
                Picker(String(localized: "附近范围"), selection: radiusBinding) {
                    ForEach(radiusChoices, id: \.self) { km in
                        Text(DistanceFormatter.radius(km: km)).tag(km)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay.map { String(localized: "附近 · \(dayTitle($0))") } ?? String(localized: "附近"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(locationManager.radiusText)
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "附近范围"))
            .accessibilityValue(locationManager.radiusText)
            IconButton(systemName: "building.2", accessibilityLabel: String(localized: "附近球馆")) {
                router.open(.courts)
            }
            IconButton(systemName: "bell.fill", accessibilityLabel: String(localized: "通知"), badge: inboxManager.unreadCount) {
                router.open(.notifications)
            }
            IconButton(systemName: "line.3.horizontal.decrease", accessibilityLabel: String(localized: "筛选"),
                       badge: filter.activeCount + (selectedDay == nil ? 0 : 1)) {
                showsFilter = true
            }
        }
    }

    /// 5 / 10 / 20 / 50 公里（用英里的地区：3 / 5 / 10 / 30 英里），存的都是公里
    private var radiusChoices: [Double] {
        let unit = locationManager.distanceUnit
        let values: [Double] = unit == .miles ? [3, 5, 10, 30] : [5, 10, 20, 50]
        return values.map { min(UserPreferences.maximumTravelRadius, unit.km(from: $0)) }
    }

    /// 现在的范围不在几个选项里（以前用滑块选的）时，菜单里不打勾
    private var radiusBinding: Binding<Double> {
        Binding(get: { locationManager.preferences.travelRadiusKm }, set: { km in
            Haptics.selection()
            _ = locationManager.updateTravelRadius(km)
        })
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "今天") }
        if calendar.isDateInTomorrow(day) { return String(localized: "明天") }
        return DateText.weekday(day)
    }

    // MARK: 邀请

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
