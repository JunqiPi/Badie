import SwiftUI

/// 首页点某一天：这天附近在找人、和我水平对得上的球友，一张张卡片左右滑。
/// 卡片就是对方的约球请求（项目、时间都定好了）。右滑和点爱心一样，直接约：
/// 单打发约球邀请，TA 确认就成局；双打替我开一个公开的双打局并邀请 TA，附近的人可以加入补齐
struct DayCandidatesView: View {
    let day: Date

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

    /// 筛选后的
    private var visible: [MockBackend.DayCandidate] { filtered(by: filter) }

    private func filtered(by filter: DayCardFilter) -> [MockBackend.DayCandidate] {
        cards.filter { filter.matches($0, user: friendManager.user(id: $0.userId)) }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if !visible.isEmpty {
                        Text("右滑约 TA，左滑跳过 · \(visible.count) 人")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)

            filterBar

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let card = visible.first {
                ZStack {
                    if visible.count > 1 {
                        cardView(visible[1]).scaleEffect(0.96).offset(y: 10).allowsHitTesting(false)
                    }
                    cardView(card)
                        .overlay(alignment: drag.width > 0 ? .topLeading : .topTrailing) { swipeStamp }
                        .offset(x: drag.width, y: drag.height * 0.2)
                        .rotationEffect(.degrees(drag.width / 25))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { value in
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
                    roundButton("heart.fill", tint: AppTheme.Colors.lime, label: String(localized: "约 TA")) { like(card) }
                }
                .padding(.bottom, AppTheme.Spacing.lg)
            } else if !cards.isEmpty {
                Spacer()
                EmptyStateView(icon: "line.3.horizontal.decrease.circle", title: String(localized: "没有符合筛选的人"),
                               message: String(localized: "放宽一点条件试试。"),
                               actionTitle: String(localized: "清除筛选")) { setFilter(DayCardFilter()) }
                Spacer()
            } else {
                Spacer()
                EmptyStateView(icon: "person.2", title: String(localized: "这天附近没有能约的球友了"),
                               message: String(localized: "发个约球请求，有人对得上会通知你。"),
                               actionTitle: String(localized: "发个约球请求")) { request() }
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task { await keepFresh() }
        .sheet(item: $profile) { item in
            PlayerProfileSheet(userId: item.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showsFilter) {
            DayCardFilterSheet(filter: $filter, venues: venueCounts, count: { filtered(by: $0).count })
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
            let names = venueCounts.filter { filter.venueIds.contains($0.venue.id) }.map(\.venue.name)
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

    /// 这天卡片里出现的球馆，按人数排
    private var venueCounts: [(venue: MockBackend.DayCandidate.Venue, count: Int)] {
        var counts: [String: (venue: MockBackend.DayCandidate.Venue, count: Int)] = [:]
        for card in cards {
            for venue in card.venues { counts[venue.id] = (counts[venue.id]?.venue ?? venue, (counts[venue.id]?.count ?? 0) + 1) }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.venue.name < $1.venue.name }
    }

    private func setFilter(_ next: DayCardFilter) {
        withAnimation(AppTheme.Motion.standard) { filter = next }
        next.save()
    }

    @ViewBuilder
    private var swipeStamp: some View {
        if abs(drag.width) > 40 {
            Text(drag.width > 0 ? String(localized: "约 TA") : String(localized: "跳过"))
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

    private func next(_ card: MockBackend.DayCandidate, toRight: Bool) {
        seen.insert(card.id)
        withAnimation(AppTheme.Motion.standard) {
            drag = CGSize(width: toRight ? 600 : -600, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            cards.removeAll { $0.id == card.id }
            drag = .zero
        }
    }

    private func skip(_ card: MockBackend.DayCandidate) {
        Haptics.selection()
        next(card, toRight: false)
        Task { await appState.backend.skipCandidate(card.ticketId) }
    }

    /// 右滑和点爱心一样：直接约，不再让人选
    private func like(_ card: MockBackend.DayCandidate) {
        guard let venue = filter.venue(for: card) else { return }
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
                appState.showError(error)
            }
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
