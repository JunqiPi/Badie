import PhotosUI
import SwiftUI

/// 发现页中间的一叠卡片，左右滑（日期、筛选按钮、规则在 DiscoverView 的头部）。
/// - 选了某天（day 不为 nil）：这天附近在找人、和我水平对得上的球友。卡片就是对方的约球请求（项目、时间都定好了）。
///   右滑和点爱心一样，直接约：单打发约球邀请，TA 确认就成局；双打替我开一个公开的双打局并邀请 TA，附近的人可以加入补齐。
/// - “附近的人”（day 为 nil）：常在附近打的人，不分日期。右滑是约 TA，选个大概的时间和球馆发一个邀请。
struct DayCandidatesView: View {
    /// 演示截图：打开后直接弹出约第一张卡的半屏
    static var demoOpensInvite = false

    /// nil：附近的人；某天：这天的卡片
    let day: Date?
    /// 筛选条件（头部的筛选按钮要显示选了几项，所以放在外面）
    @Binding var filter: DayCardFilter
    @Binding var showsFilter: Bool
    /// 下拉刷新时加一：重新拉卡片
    var reloadToken = 0

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager

    /// 这天所有能约的人（筛选前）
    @State private var cards: [MockBackend.DayCandidate] = []
    /// 已经滑过的，自动刷新时不再加回来
    @State private var seen: Set<String> = []
    @State private var isLoading = true
    @State private var drag: CGSize = .zero
    /// 卡片正在飞走：这段时间不再接受右滑、左滑和按钮（防止连点约两次）
    @State private var leaving = false
    /// 常在附近的人（筛选前）、已经滑过的
    @State private var nearby: [MockBackend.NearbyPlayer] = []
    @State private var nearbySeen: Set<String> = []
    /// 第一次约人前的提醒（打开可见 / 加照片），以及是为哪张卡、点的哪段空闲时间
    @State private var prompt: InvitePromptSheet.Kind?
    @State private var promptCard: MockBackend.NearbyPlayer?
    @State private var promptSlot: RecurringTimeSlot?
    @State private var cardCropItem: AvatarCropSheet.Item?
    /// 正在约的人（半屏“约<昵称>”）
    @State private var composeTarget: ComposeTarget?
    /// 刷完了点“扩大范围”：改附近范围
    @State private var showsRadius = false

    private struct ComposeTarget: Identifiable {
        let player: MockBackend.NearbyPlayer
        /// 点了卡片上的哪段空闲时间
        let slot: RecurringTimeSlot?

        var id: String { player.id }
    }

    private var lobbyOnly: Bool { day == nil }

    /// 没开定位：不能按默认城市找人（会约到别的城市）
    private var needsLocation: Bool {
        appState.isRemote && locationManager.currentLocation == nil
    }

    /// 筛选后的
    private var visible: [MockBackend.DayCandidate] { filtered(by: filter) }

    private func filtered(by filter: DayCardFilter) -> [MockBackend.DayCandidate] {
        cards.filter { filter.matches($0, user: friendManager.user(id: $0.userId)) }
    }

    private var visibleNearby: [MockBackend.NearbyPlayer] { filteredNearby(by: filter) }

    private func filteredNearby(by filter: DayCardFilter) -> [MockBackend.NearbyPlayer] {
        nearby.filter { filter.matches($0, user: friendManager.user(id: $0.userId)) }
    }

    /// 一张卡：这天的约球请求，或常在附近的人
    private enum DeckCard: Identifiable {
        case day(MockBackend.DayCandidate)
        case nearby(MockBackend.NearbyPlayer)

        var id: String {
            switch self {
            case .day(let card): return "day-\(card.id)"
            case .nearby(let player): return "nearby-\(player.id)"
            }
        }
    }

    private var deck: [DeckCard] {
        lobbyOnly ? visibleNearby.map { DeckCard.nearby($0) } : visible.map { DeckCard.day($0) }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            if needsLocation {
                Spacer()
                EmptyStateView(icon: "location", title: String(localized: "开启定位"),
                               actionTitle: String(localized: "开启定位")) { enableLocation() }
                Spacer()
            } else if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let card = deck.first {
                ZStack {
                    if deck.count > 1 {
                        cardView(deck[1]).scaleEffect(0.96).offset(y: 10).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    cardView(card)
                        .overlay(alignment: drag.width > 0 ? .topLeading : .topTrailing) { swipeStamp(card) }
                        .offset(x: drag.width, y: drag.height * 0.2)
                        .rotationEffect(.degrees(drag.width / 25))
                        .gesture(
                            DragGesture()
                                .onChanged { if !leaving { drag = $0.translation } }
                                .onEnded { value in
                                    guard !leaving else { return }
                                    if value.translation.width > 110 { like(card) }
                                    else if value.translation.width < -110 { skip(card) }
                                    else { withAnimation(AppTheme.Motion.standard) { drag = .zero } }
                                }
                        )
                        .id(card.id)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.screen)
                HStack(spacing: AppTheme.Spacing.xxl) {
                    roundButton("xmark", tint: AppTheme.Colors.surface, label: String(localized: "跳过")) { skip(card) }
                    roundButton("heart.fill", tint: AppTheme.Colors.lime, label: likeTitle) { like(card) }
                }
                .disabled(leaving)
            } else if (lobbyOnly ? !nearby.isEmpty : !cards.isEmpty) {
                Spacer()
                EmptyStateView(icon: "line.3.horizontal.decrease.circle", title: String(localized: "没有符合筛选的人"),
                               actionTitle: String(localized: "清除筛选")) { setFilter(DayCardFilter()) }
                Spacer()
            } else {
                Spacer()
                outOfCards
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: locationManager.currentLocation == nil) { _, missing in
            if !missing { Task { await load(showsErrors: true) } }
        }
        .onChange(of: locationManager.preferences.travelRadiusKm) { _, _ in
            Task { await load(showsErrors: true) }
        }
        .onChange(of: reloadToken) { _, _ in
            Task { await load(showsErrors: true) }
        }
        .task { await keepFresh() }
        .sheet(isPresented: $showsFilter) {
            DayCardFilterSheet(filter: $filter, venues: venueCounts, count: { filtered(by: $0).count + filteredNearby(by: $0).count })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $prompt) { kind in
            InvitePromptSheet(kind: kind, onConfirm: { confirmPrompt(kind) }, onCancel: { cancelPrompt() },
                              onPhoto: { item in pickedPhoto(item) })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(item: $cardCropItem) { item in
            AvatarCropSheet(image: item.image, shape: .card) { jpeg in Task { await uploadCardThenInvite(jpeg) } }
        }
        .sheet(item: $composeTarget) { target in
            InviteComposeSheet(userId: target.player.userId, partnerTimes: target.player.usualTimes,
                               theirVenues: target.player.venues, prefill: target.slot) { result, window in
                sent(target.player, result: result, window: window)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsRadius) {
            TravelRadiusSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    /// 刷完了 / 这天没人：一句话 + 发个约球请求 / 扩大范围
    private var outOfCards: some View {
        let title: String
        if lobbyOnly {
            title = nearbySeen.isEmpty ? String(localized: "附近暂时没有人") : String(localized: "附近的人都看完了")
        } else {
            title = seen.isEmpty ? String(localized: "这天还没人约") : String(localized: "这天的刷完了")
        }
        let requestButton = Button(String(localized: "发个约球请求")) { request() }
            .buttonStyle(.brutal(.primary, size: .small, fullWidth: false))
        let widenButton = Button(String(localized: "扩大范围")) { showsRadius = true }
            .buttonStyle(.brutal(.secondary, size: .small, fullWidth: false))
        return VStack(spacing: AppTheme.Spacing.lg) {
            EmptyStateView(icon: "person.2", title: title)
            // 字长的语言放不下一行就上下排
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    requestButton
                    widenButton
                }
                VStack(spacing: AppTheme.Spacing.sm) {
                    requestButton
                    widenButton
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
    }

    // MARK: Filter

    /// 卡片里出现的球馆，按人数排
    private var venueCounts: [(venue: MockBackend.DayCandidate.Venue, count: Int)] {
        var counts: [String: (venue: MockBackend.DayCandidate.Venue, count: Int)] = [:]
        let venues: [[MockBackend.DayCandidate.Venue]] = lobbyOnly ? nearby.map(\.venues) : cards.map(\.venues)
        for list in venues {
            for venue in list { counts[venue.id] = (counts[venue.id]?.venue ?? venue, (counts[venue.id]?.count ?? 0) + 1) }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.venue.name < $1.venue.name }
    }

    private func setFilter(_ next: DayCardFilter) {
        withAnimation(AppTheme.Motion.standard) { filter = next }
        next.save()
    }

    private var likeTitle: String {
        String(localized: "约 TA")
    }

    @ViewBuilder
    private func swipeStamp(_ card: DeckCard) -> some View {
        if abs(drag.width) > 40 {
            Text(drag.width > 0 ? likeTitle : String(localized: "跳过"))
                .font(AppTheme.Typography.title3)
                .foregroundStyle(drag.width > 0 ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xs)
                .sticker(drag.width > 0 ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.sm, shadow: .zero)
                .rotationEffect(.degrees(drag.width > 0 ? -8 : 8))
                .padding(AppTheme.Spacing.lg)
                .allowsHitTesting(false)
        }
    }

    // MARK: Card

    @ViewBuilder
    private func cardView(_ card: DeckCard) -> some View {
        switch card {
        case .day(let candidate): cardView(candidate)
        case .nearby(let player):
            NearbyCardView(user: friendManager.user(id: player.userId), card: player,
                           venue: player.venues.first { filter.venueIds.contains($0.id) },
                           onProfile: { appState.showPlayer(player.userId) },
                           onInvite: { slot in invite(player, slot: slot) })
        }
    }

    private func cardView(_ card: MockBackend.DayCandidate) -> some View {
        DayCardView(user: friendManager.user(id: card.userId),
                    details: .init(mode: card.mixed ? String(localized: "混双") : card.mode.title, startsAt: card.startsAt, endsAt: card.endsAt,
                                   venues: orderedVenues(card).map(\.name), recentNoShows: card.recentNoShows),
                    onProfile: { appState.showPlayer(card.userId) })
    }

    /// 约在哪家的那家排第一
    private func orderedVenues(_ card: MockBackend.DayCandidate) -> [MockBackend.DayCandidate.Venue] {
        guard let first = filter.venue(for: card) else { return card.venues }
        return [first] + card.venues.filter { $0.id != first.id }
    }

    private func roundButton(_ icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(AppTheme.Colors.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(tint))
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: Actions

    /// 没人可约：打开约球设置，日期就是选的这天
    private func request() {
        if let day {
            matchManager.draft.day = day
            if !matchManager.draft.validation.isValid, Calendar.current.isDateInToday(day) {
                matchManager.draft.apply(TimeSlot.suggestedDefault())
            }
        }
        router.isMatchSetupPresented = true
    }

    /// 某天的卡片每 30 秒拉一次（在别的标签页时不拉）：新出现的人接在后面，不打乱正在看的那张；已经走了的人拿掉。
    /// 附近的人变得慢，只在打开、下拉、开定位、改范围时拉
    private func keepFresh() async {
        await load(showsErrors: true)
        guard !lobbyOnly else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            if router.selectedTab == .home { await load(showsErrors: false) }
        }
    }

    private func load(showsErrors: Bool) async {
        defer { isLoading = false }
        guard let day else {
            await loadNearby()
            return
        }
        do {
            let fresh = try await appState.backend.dayCandidates(on: day, center: locationManager.coordinate,
                                                                 radiusKm: locationManager.preferences.travelRadiusKm)
            let freshIds = Set(fresh.map(\.id))
            let current = visible.first?.id
            var merged = cards.filter { freshIds.contains($0.id) || $0.id == current }
            let known = Set(merged.map(\.id))
            merged += fresh.filter { !known.contains($0.id) && !seen.contains($0.id) }
            cards = merged
        } catch {
            if showsErrors { appState.showError(error) }
        }
    }

    private func loadNearby() async {
        guard let fresh = try? await appState.backend.nearbyPlayers(center: locationManager.coordinate,
                                                                    radiusKm: locationManager.preferences.travelRadiusKm) else { return }
        let freshIds = Set(fresh.map(\.id))
        let current = visibleNearby.first?.id
        var merged = nearby.filter { freshIds.contains($0.id) || $0.id == current }
        let known = Set(merged.map(\.id))
        merged += fresh.filter { !known.contains($0.id) && !nearbySeen.contains($0.id) }
        nearby = merged
        if Self.demoOpensInvite, composeTarget == nil, let first = visibleNearby.first {
            Self.demoOpensInvite = false
            composeTarget = ComposeTarget(player: first, slot: UsualTimeText.sortedByNext(first.usualTimes).first)
        }
    }

    /// 卡片飞走，动画放完再从叠里拿掉
    private func fly(toRight: Bool, remove: @escaping () -> Void) {
        leaving = true
        withAnimation(AppTheme.Motion.standard) {
            drag = CGSize(width: toRight ? 600 : -600, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            remove()
            drag = .zero
            leaving = false
        }
    }

    private func next(_ card: MockBackend.DayCandidate, toRight: Bool) {
        seen.insert(card.id)
        fly(toRight: toRight) { cards.removeAll { $0.id == card.id } }
    }

    private func next(_ player: MockBackend.NearbyPlayer, toRight: Bool) {
        nearbySeen.insert(player.id)
        fly(toRight: toRight) { nearby.removeAll { $0.id == player.id } }
    }

    /// 没约成（网络、撞时间等）：卡片放回最前面，还能再滑；TA 已经约不了的就不放回
    private func putBack(_ card: MockBackend.DayCandidate, after error: Error) {
        if case RemoteError.server("not_available")? = error as? RemoteError { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            seen.remove(card.id)
            cards.removeAll { $0.id == card.id }
            cards.insert(card, at: 0)
        }
    }

    private func enableLocation() {
        if locationManager.isDenied, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        } else {
            locationManager.requestAuthorization()
        }
    }

    private func skip(_ card: DeckCard) {
        switch card {
        case .day(let candidate): skip(candidate)
        case .nearby(let player): skip(player)
        }
    }

    private func like(_ card: DeckCard) {
        switch card {
        case .day(let candidate): like(candidate)
        case .nearby(let player): invite(player, slot: nil)
        }
    }

    private func skip(_ card: MockBackend.DayCandidate) {
        guard !leaving else { return }
        Haptics.selection()
        next(card, toRight: false)
        Task { await appState.backend.skipCandidate(card.ticketId) }
    }

    /// 右滑和点爱心一样：直接约，不再让人选
    private func like(_ card: MockBackend.DayCandidate) {
        guard !leaving, let venue = filter.venue(for: card) else { return }
        Haptics.tap()
        next(card, toRight: true)
        let start = Self.inviteStart(for: card)
        Task {
            do {
                if card.mode == .singles && !card.mixed {
                    try await appState.backend.inviteCandidate(card.ticketId, venueId: venue.id, startsAt: start)
                    Haptics.success()
                    appState.showToast(String(localized: "已约 TA \(start.formatted(date: .omitted, time: .shortened)) 在 \(venue.name) 打单打，对方确认就成局"),
                                       style: .success)
                } else {
                    try await appState.backend.inviteDoublesCandidate(card.ticketId, venueId: venue.id, startsAt: start)
                    Haptics.success()
                    appState.showToast(String(localized: "已开一个双打局并邀请 TA，附近的人可以加入"), style: .success)
                }
            } catch {
                appState.showToast(Self.inviteError(error), style: .error)
                putBack(card, after: error)
            }
        }
    }

    // MARK: 常在附近

    private func skip(_ player: MockBackend.NearbyPlayer) {
        guard !leaving else { return }
        Haptics.selection()
        next(player, toRight: false)
        Task { await appState.backend.skipNearby(player.userId) }
    }

    /// 选照片的提醒每台设备只出一次
    private static let photoAskedKey = "BadieNearbyPhotoAsked"

    /// 右滑、点卡片上的空闲时间：约 TA。没打开“在同馆常客里显示我”先问；没卡片照片提醒一次
    private func invite(_ player: MockBackend.NearbyPlayer, slot: RecurringTimeSlot?) {
        guard !leaving, let me = appState.currentUser else { return }
        if !me.privacy.showsAsRegular {
            ask(.visibility, for: player, slot: slot)
        } else if me.avatar.cardPhotoVersion == nil && !UserDefaults.standard.bool(forKey: Self.photoAskedKey) {
            UserDefaults.standard.set(true, forKey: Self.photoAskedKey)
            ask(.photo, for: player, slot: slot)
        } else {
            openCompose(player, slot: slot)
        }
    }

    private func ask(_ kind: InvitePromptSheet.Kind, for player: MockBackend.NearbyPlayer, slot: RecurringTimeSlot?) {
        withAnimation(AppTheme.Motion.standard) { drag = .zero }
        promptCard = player
        promptSlot = slot
        prompt = kind
    }

    /// 卡片回到中间，弹出“约<昵称>”；发出去了卡片才飞走
    private func openCompose(_ player: MockBackend.NearbyPlayer, slot: RecurringTimeSlot?, after delay: UInt64 = 0) {
        withAnimation(AppTheme.Motion.standard) { drag = .zero }
        Task { @MainActor in
            // 等上一个半屏收起来，下一个才弹得出来
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            composeTarget = ComposeTarget(player: player, slot: slot)
        }
    }

    private func confirmPrompt(_ kind: InvitePromptSheet.Kind) {
        prompt = nil
        guard let player = promptCard else { return }
        let slot = promptSlot
        promptCard = nil
        promptSlot = nil
        switch kind {
        case .photo:
            openCompose(player, slot: slot, after: 450_000_000)
        case .visibility:
            Task {
                do {
                    try await appState.backend.enableShowsAsRegular()
                    openCompose(player, slot: slot, after: 450_000_000)
                } catch {
                    appState.showError(error)
                }
            }
        }
    }

    private func cancelPrompt() {
        prompt = nil
        promptCard = nil
        promptSlot = nil
    }

    /// 选了照片：先关提醒，再裁剪；裁好上传后接着约
    private func pickedPhoto(_ item: PhotosPickerItem) {
        prompt = nil
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = await AvatarPhotos.image(fromPhoto: data) else {
                appState.showToast(String(localized: "无法读取这张照片"), style: .error)
                return
            }
            // 等提醒的半屏收起来，裁剪页才弹得出来
            try? await Task.sleep(nanoseconds: 450_000_000)
            cardCropItem = AvatarCropSheet.Item(image: image)
        }
    }

    private func uploadCardThenInvite(_ jpeg: Data) async {
        do {
            try await appState.backend.uploadCardPhoto(jpeg)
        } catch {
            appState.showError(error)
        }
        if let player = promptCard {
            let slot = promptSlot
            promptCard = nil
            promptSlot = nil
            openCompose(player, slot: slot, after: 450_000_000)
        }
    }

    /// 邀请发出去了：卡片飞走，说一声还能约几个
    private func sent(_ player: MockBackend.NearbyPlayer, result: MockBackend.InviteResult?, window: PlayWindow) {
        next(player, toRight: true)
        let name = friendManager.user(id: player.userId)?.nickname ?? ""
        var text = String(localized: "已邀请\(name) · \(WindowText.headline(window))")
        if let result { text += "\n" + String(localized: "今天还能约 \(result.remaining) 个") }
        appState.showToast(text, style: .success)
    }

    /// 卡片页上没有让人选时间，有些通用的错误说法会让人看不懂，换成这里的说法
    static func inviteError(_ error: Error) -> String {
        guard case RemoteError.server(let code)? = error as? RemoteError else { return error.localizedDescription }
        switch code {
        case "overlapping": return String(localized: "这个时间你已经有球局或待确认的约球了。")
        case "too_soon", "invalid_slot": return String(localized: "TA 的时间快到了，来不及约了。")
        case "too_many_requests": return String(localized: "今天约得太多了，明天再来。")
        case "too_many_invites": return String(localized: "这天已经在等 3 个人回复了，有人回复再约。")
        case "too_many_rooms": return String(localized: "你已经开了 3 个局，先关掉一个再约双打。")
        case "invalid_event": return String(localized: "约混双要先在资料里填性别。")
        default: return error.localizedDescription
        }
    }

    /// 从 TA 的开始时间约 2 小时；今天的话至少半小时后、按半小时对齐
    static func inviteStart(for card: MockBackend.DayCandidate, now: Date = Date()) -> Date {
        let earliest = now.addingTimeInterval(30 * 60)
        guard card.startsAt < earliest else { return card.startsAt }
        let seconds = ceil(earliest.timeIntervalSince1970 / 1800) * 1800
        return Date(timeIntervalSince1970: seconds)
    }
}
