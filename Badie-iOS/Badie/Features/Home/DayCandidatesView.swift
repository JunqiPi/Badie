import PhotosUI
import SwiftUI

/// 首页点某一天：这天附近在找人、和我水平对得上的球友，一张张卡片左右滑。
/// 卡片就是对方的约球请求（项目、时间都定好了）。右滑和点爱心一样，直接约：
/// 单打发约球邀请，TA 确认就成局；双打替我开一个公开的双打局并邀请 TA，附近的人可以加入补齐。
/// 这天的刷完了，接着是附近的人（不分日期）：右滑是约 TA，选个大概的时间和球馆发一个邀请。
/// 首页“附近的人”打开的是只有附近的人的这一叠（lobbyOnly）
struct DayCandidatesView: View {
    /// 演示截图：打开后直接弹出约第一张卡的半屏
    static var demoOpensInvite = false

    let day: Date
    /// 只看附近的人（首页“附近的人”）
    var lobbyOnly = false

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss

    /// 这天所有能约的人（筛选前）
    @State private var cards: [MockBackend.DayCandidate] = []
    /// 已经滑过的，自动刷新时不再加回来
    @State private var seen: Set<String> = []
    @State private var isLoading = true
    @State private var drag: CGSize = .zero
    @State private var filter = DayCardFilter.load()
    @State private var showsFilter = false
    /// 全屏页上面要自己弹资料页（首页那层弹不出来）
    @State private var profile: PlayerSheetItem?
    /// 卡片正在飞走：这段时间不再接受右滑、左滑和按钮（防止连点约两次）
    @State private var leaving = false
    /// 常在附近的人（筛选前）、已经滑过的、这天卡片里出现过的人（不重复出现）
    @State private var nearby: [MockBackend.NearbyPlayer] = []
    @State private var nearbySeen: Set<String> = []
    @State private var dayUsers: Set<String> = []
    /// 滑过几张常在附近的卡：第一张上面显示“这天的刷完了”
    @State private var nearbySwiped = 0
    /// 第一次约人前的提醒（打开可见 / 加照片），以及是为哪张卡、点的哪段空闲时间
    @State private var prompt: InvitePromptSheet.Kind?
    @State private var promptCard: MockBackend.NearbyPlayer?
    @State private var promptSlot: RecurringTimeSlot?
    @State private var cardCropItem: AvatarCropSheet.Item?
    /// 正在约的人（半屏“约<昵称>”）
    @State private var composeTarget: ComposeTarget?

    private struct ComposeTarget: Identifiable {
        let player: MockBackend.NearbyPlayer
        /// 点了卡片上的哪段空闲时间
        let slot: RecurringTimeSlot?

        var id: String { player.id }
    }

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
        nearby.filter { !dayUsers.contains($0.userId) && filter.matches($0, user: friendManager.user(id: $0.userId)) }
    }

    /// 一叠卡：先是这天的，再是常在附近的
    private enum DeckCard: Identifiable {
        case day(MockBackend.DayCandidate)
        case nearby(MockBackend.NearbyPlayer)

        var id: String {
            switch self {
            case .day(let card): return "day-\(card.id)"
            case .nearby(let player): return "nearby-\(player.id)"
            }
        }

        var isNearby: Bool {
            if case .nearby = self { return true }
            return false
        }
    }

    private var deck: [DeckCard] {
        (lobbyOnly ? [] : visible.map { DeckCard.day($0) }) + visibleNearby.map { DeckCard.nearby($0) }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lobbyOnly ? String(localized: "附近的人") : day.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if lobbyOnly {
                        if !visibleNearby.isEmpty {
                            Text("\(visibleNearby.count) 人")
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .monospacedDigit()
                        }
                    } else if !visible.isEmpty {
                        Text("\(visible.count) 人")
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .monospacedDigit()
                    } else if !visibleNearby.isEmpty {
                        Text("常在附近 · \(visibleNearby.count) 人")
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .monospacedDigit()
                    }
                }
                RulesButton(title: String(localized: "怎么约"), points: [
                    String(localized: "右滑约 TA，左滑跳过"),
                    String(localized: "单打：发约球邀请，TA 确认就成局"),
                    String(localized: "双打：替你开一个公开双打局并邀请 TA，附近的人可以加入补齐"),
                    String(localized: "附近的人：定了级、常去附近球馆、打开了“在同馆常客里显示我”的人"),
                    String(localized: "约附近的人：选个大概的时间和球馆，TA 说好就成局，具体几点在群聊里定"),
                    String(localized: "每天最多约 10 个，加球友不算"),
                    String(localized: "跳过或拒绝的人 30 天内不会再出现")
                ])
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)

            filterBar

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
                if card.isNearby && nearbySwiped == 0 && !lobbyOnly {
                    NearbyDivider()
                        .padding(.horizontal, AppTheme.Spacing.screen)
                }
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
                    roundButton("heart.fill", tint: AppTheme.Colors.lime, label: likeTitle(card)) { like(card) }
                }
                .disabled(leaving)
                .padding(.bottom, AppTheme.Spacing.lg)
            } else if (!lobbyOnly && !cards.isEmpty) || !nearby.isEmpty {
                Spacer()
                EmptyStateView(icon: "line.3.horizontal.decrease.circle", title: String(localized: "没有符合筛选的人"),
                               actionTitle: String(localized: "清除筛选")) { setFilter(DayCardFilter()) }
                Spacer()
            } else if lobbyOnly {
                Spacer()
                EmptyStateView(icon: "person.2", title: String(localized: "附近暂时没有人"))
                Spacer()
            } else {
                Spacer()
                EmptyStateView(icon: "person.2", title: String(localized: "这天附近没有能约的球友了"),
                               actionTitle: String(localized: "约球")) { request() }
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .showsToasts()
        // 在资料页里点了私信、约球等：先关掉这一页，新页面才看得见
        .onChange(of: router.navigations) { _, _ in dismiss() }
        .onChange(of: locationManager.currentLocation == nil) { _, missing in
            if !missing { Task { await load(showsErrors: true) } }
        }
        .task { await keepFresh() }
        .sheet(item: $profile) { item in
            PlayerProfileSheet(userId: item.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
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
    }

    // MARK: Filter

    /// 筛选按钮 + 选了的条件（点 ✕ 去掉）
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    showsFilter = true
                } label: {
                    Label(filter.activeCount > 0 ? String(localized: "筛选 · \(filter.activeCount)") : String(localized: "筛选"),
                          systemImage: "line.3.horizontal.decrease")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.onInverse)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(AppTheme.Colors.inverse))
                }
                .buttonStyle(PressableStyle())
                ForEach(activeChips, id: \.title) { chip in
                    Button {
                        var next = filter
                        chip.clear(&next)
                        setFilter(next)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.title)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
                        }
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.onAccent)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(AppTheme.Colors.lime))
                        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text("去掉 \(chip.title)"))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }

    private struct Chip {
        let title: String
        let clear: (inout DayCardFilter) -> Void
    }

    private var activeChips: [Chip] {
        var chips: [Chip] = []
        if filter.event != .any { chips.append(Chip(title: filter.event.title) { $0.event = .any }) }
        if !filter.venueIds.isEmpty {
            let names = filter.venueIds.sorted().map { id in
                venueCounts.first { $0.venue.id == id }?.venue.name ?? filter.venueNames[id] ?? id
            }
            let title = names.count == 1 ? names[0] : String(localized: "\(filter.venueIds.count) 家球馆")
            chips.append(Chip(title: title) { $0.venueIds = [] })
        }
        if filter.minLevel > 1 || filter.maxLevel < 9 {
            chips.append(Chip(title: "Lv.\(filter.minLevel)–\(filter.maxLevel)") { $0.minLevel = 1; $0.maxLevel = 9 })
        }
        if !filter.times.isEmpty {
            let title = DayCardFilter.TimeOfDay.allCases.filter { filter.times.contains($0) }.map(\.title).joined(separator: "、")
            chips.append(Chip(title: title) { $0.times = [] })
        }
        if let gender = filter.gender {
            chips.append(Chip(title: gender == .male ? String(localized: "男") : String(localized: "女")) { $0.gender = nil })
        }
        if filter.reliableOnly { chips.append(Chip(title: String(localized: "没爽约过")) { $0.reliableOnly = false }) }
        return chips
    }

    /// 这天卡片和常在附近的人里出现的球馆，按人数排
    private var venueCounts: [(venue: MockBackend.DayCandidate.Venue, count: Int)] {
        var counts: [String: (venue: MockBackend.DayCandidate.Venue, count: Int)] = [:]
        for card in cards {
            for venue in card.venues { counts[venue.id] = (counts[venue.id]?.venue ?? venue, (counts[venue.id]?.count ?? 0) + 1) }
        }
        for player in nearby where !dayUsers.contains(player.userId) {
            for venue in player.venues { counts[venue.id] = (counts[venue.id]?.venue ?? venue, (counts[venue.id]?.count ?? 0) + 1) }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.venue.name < $1.venue.name }
    }

    private func setFilter(_ next: DayCardFilter) {
        withAnimation(AppTheme.Motion.standard) { filter = next }
        next.save()
    }

    private func likeTitle(_ card: DeckCard) -> String {
        String(localized: "约 TA")
    }

    @ViewBuilder
    private func swipeStamp(_ card: DeckCard) -> some View {
        if abs(drag.width) > 40 {
            Text(drag.width > 0 ? likeTitle(card) : String(localized: "跳过"))
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
                           onProfile: { profile = PlayerSheetItem(id: player.userId) },
                           onInvite: { slot in invite(player, slot: slot) })
        }
    }

    private func cardView(_ card: MockBackend.DayCandidate) -> some View {
        DayCardView(user: friendManager.user(id: card.userId),
                    details: .init(mode: card.mixed ? String(localized: "混双") : card.mode.title, startsAt: card.startsAt, endsAt: card.endsAt,
                                   venues: orderedVenues(card).map(\.name), recentNoShows: card.recentNoShows),
                    onProfile: { profile = PlayerSheetItem(id: card.userId) })
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

    /// 没人可约：回到首页打开约球设置，日期就是这天
    private func request() {
        matchManager.draft.day = day
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            router.isMatchSetupPresented = true
        }
    }

    /// 打开期间每 30 秒拉一次：新出现的人接在后面，不打乱正在看的那张；已经走了的人拿掉
    private func keepFresh() async {
        await load(showsErrors: true)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await load(showsErrors: false)
        }
    }

    private func load(showsErrors: Bool) async {
        defer { isLoading = false }
        do {
            var fresh: [MockBackend.DayCandidate] = []
            if !lobbyOnly {
                fresh = try await appState.backend.dayCandidates(on: day, center: locationManager.coordinate,
                                                                 radiusKm: locationManager.preferences.travelRadiusKm)
            }
            let freshIds = Set(fresh.map(\.id))
            let current = visible.first?.id
            var merged = cards.filter { freshIds.contains($0.id) || $0.id == current }
            let known = Set(merged.map(\.id))
            merged += fresh.filter { !known.contains($0.id) && !seen.contains($0.id) }
            cards = merged
            dayUsers.formUnion(fresh.map(\.userId))
        } catch {
            if showsErrors { appState.showError(error) }
        }
        // 常在附近变得慢：只在打开和开定位时拉；拉不到不影响这天的卡片
        if showsErrors { await loadNearby() }
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
        fly(toRight: toRight) {
            nearby.removeAll { $0.id == player.id }
            nearbySwiped += 1
        }
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
