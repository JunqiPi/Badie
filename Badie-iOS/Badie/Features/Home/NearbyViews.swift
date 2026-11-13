import PhotosUI
import SwiftUI

// MARK: - 附近的人：卡片

/// 附近的人：和按天的卡片同一个样子，只是不写时间，左上角写 TA 常去的球馆，底部是常有空的时间
struct NearbyCardView: View {
    let user: User?
    let card: MockBackend.NearbyPlayer
    /// 左上角显示的球馆（选了球馆筛选时是选的那家）
    var venue: MockBackend.DayCandidate.Venue?
    var onProfile: (() -> Void)?
    /// 点了 TA 的某段空闲时间：约 TA 这一段最近的一次
    var onInvite: ((RecurringTimeSlot) -> Void)?

    var body: some View {
        CoverCard(user: user, pill: pill, line: line, onProfile: onProfile) {
            if card.recentNoShows > 0 { NoShowPill(count: card.recentNoShows) }
            if !card.usualTimes.isEmpty { UsualTimeChips(slots: card.usualTimes, onTap: onInvite) }
        }
    }

    /// “3.2 公里 · 常去 X”（不知道距离就只写球馆）
    private var pill: String? {
        guard let place = venue ?? card.venues.first else { return nil }
        return [place.km.map { DistanceFormatter.string(km: $0) }, String(localized: "常去 \(place.name)")]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// “双打 · 靠谱”
    private var line: String {
        [card.preferredMode?.title, card.recentNoShows == 0 ? String(localized: "靠谱") : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// TA 的空闲时间：最近的两段做成小胶囊，多了“+N”。点一个就约这一段
struct UsualTimeChips: View {
    let slots: [RecurringTimeSlot]
    var onTap: ((RecurringTimeSlot) -> Void)?

    var body: some View {
        let sorted = UsualTimeText.sortedByNext(slots)
        HStack(spacing: 6) {
            ForEach(sorted.prefix(2)) { slot in
                Button {
                    onTap?(slot)
                } label: {
                    Text(UsualTimeText.chip(slot))
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.onAccent)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(AppTheme.Colors.lime))
                        .overlay(Capsule().strokeBorder(AppTheme.Colors.onAccent, lineWidth: 1.5))
                }
                .buttonStyle(PressableStyle())
                .disabled(onTap == nil)
                .accessibilityLabel(Text("约 \(UsualTimeText.chip(slot))"))
            }
            if sorted.count > 2 {
                TagPill(text: "+\(sorted.count - 2)", fill: AppTheme.Colors.lime)
            }
        }
    }
}

/// ★ 加球友：不占每天约人的名额，也不翻到下一张。已是球友就发消息，TA 申请过我就同意，已申请就说一声
struct FriendStarButton: View {
    let userId: String
    /// 服务器给的关系（缓存里还没有时用）
    var isFriend = false
    var request: MockBackend.FriendRequestState?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @State private var requested = false
    @State private var becameFriends = false
    @State private var isWorking = false

    private enum Status { case friend, sent, received, none }

    private var status: Status {
        if isFriend || becameFriends || friendManager.isFriend(userId) { return .friend }
        if requested || request == .sent || friendManager.hasPendingRequest(to: userId) { return .sent }
        if request == .received || friendManager.incomingRequest(from: userId) != nil { return .received }
        return .none
    }

    var body: some View {
        let current = status
        Button {
            tap(current)
        } label: {
            RoundActionLabel(icon: current == .friend ? "bubble.left.fill" : "star.fill", tint: AppTheme.Colors.butter)
                .opacity(current == .sent ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(isWorking)
        .accessibilityLabel(label(current))
    }

    private func label(_ status: Status) -> String {
        switch status {
        case .friend: return String(localized: "发消息")
        case .sent: return String(localized: "已申请")
        case .received: return String(localized: "通过好友申请")
        case .none: return String(localized: "加球友")
        }
    }

    private func tap(_ status: Status) {
        switch status {
        case .friend: router.open(.chat(userId: userId), in: .messages)
        case .sent: appState.showToast(String(localized: "已申请，等待通过"))
        case .received, .none: add()
        }
    }

    /// TA 也申请过我：同意（服务器上再申请一次就是同意）；否则发申请
    private func add() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if let incoming = friendManager.incomingRequest(from: userId) {
                    try await friendManager.respond(incoming, accept: true)
                    becameFriends = true
                    appState.showToast(String(localized: "已添加为球友"), style: .success)
                } else {
                    try await friendManager.sendRequest(to: userId)
                    if friendManager.isFriend(userId) || request == .received {
                        becameFriends = true
                        appState.showToast(String(localized: "已添加为球友"), style: .success)
                    } else {
                        requested = true
                        appState.showToast(String(localized: "申请已发送"), style: .success)
                    }
                }
                Haptics.success()
            } catch {
                appState.showError(error)
            }
        }
    }
}

// MARK: - 第一次约人前：让附近的人也能看到你 / 加一张照片

struct InvitePromptSheet: View {
    enum Kind: String, Identifiable {
        /// 没打开“在同馆常客里显示我”
        case visibility
        /// 没有卡片背景照片
        case photo

        var id: String { rawValue }
    }

    let kind: Kind
    var onConfirm: () -> Void
    var onCancel: () -> Void
    /// 选了照片（只有 .photo）
    var onPhoto: (PhotosPickerItem) -> Void = { _ in }

    @EnvironmentObject private var appState: AppState
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(kind == .visibility ? String(localized: "先让附近的人也能看到你") : String(localized: "加一张照片？"))
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            if kind == .photo, let user = appState.currentUser {
                HStack(spacing: AppTheme.Spacing.md) {
                    AvatarView(user: user, size: 48)
                    Text("别人刷到你时看到的就是这张卡")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.Spacing.md)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
            }
            Spacer(minLength: 0)
            if kind == .photo {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("选照片").frame(maxWidth: .infinity)
                }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                Button("先不加", action: onConfirm)
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
            } else {
                Button("打开", action: onConfirm)
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                Button("不了", action: onCancel)
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onChange(of: photoItem) { _, item in
            if let item { onPhoto(item) }
        }
    }
}

// MARK: - 约 TA：项目、日期、时间、球馆

/// 半屏“约<昵称>”：右滑、点卡片上的空闲时间、收到邀请后“换个时间”都用这一页。
/// 发出去的是定好的时间：哪天、几点到几点（半小时一档，1–4 小时）
struct InviteComposeSheet: View {
    enum Purpose: Equatable {
        case new
        case counter(roomId: String)
    }

    let userId: String
    var purpose: Purpose = .new
    /// TA 的空闲时间：选的那天 TA 有空，时间上面写一句“<TA> 周五晚上有空”
    var partnerTimes: [RecurringTimeSlot] = []
    /// TA 常去的球馆（卡片上的），近的在前
    var theirVenues: [MockBackend.DayCandidate.Venue] = []
    /// 点卡片上的空闲时间进来：按那一段填好
    var prefill: RecurringTimeSlot?
    /// 换个时间：现在的球馆
    var currentVenue: BadmintonCourt?
    /// 默认的项目：TA 常打的；换个时间是现在的项目
    var initialMode: GameMode?
    /// 发出去了（新邀请带结果；换个时间是 nil）
    var onSent: (MockBackend.InviteResult?, PlayWindow) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: GameMode = .singles
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var startMinutes = 19 * 60
    @State private var endMinutes = 21 * 60
    @State private var venueIds: [String] = []
    @State private var suggestedVenueName: String?
    @State private var showsDatePicker = false
    @State private var pickedDate = Date()
    @State private var showsVenuePicker = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var didLoad = false

    /// 一场 1–4 小时（和服务器一致）
    private static let shortest = 60
    private static let longest = 240

    private var partner: User? { friendManager.user(id: userId) }

    /// 日期条：今天起 14 天；用日历选了更远的那天也放进来
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var list = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        if !list.contains(day) { list.append(day) }
        return list
    }

    /// 定好的时间：整个窗口就是一场
    private var window: PlayWindow? {
        guard var window = PlayWindow.on(day, startMinutes: startMinutes, endMinutes: endMinutes) else { return nil }
        window.durationMinutes = endMinutes - startMinutes
        return window
    }

    /// 选的那天 TA 有空的那段：“周五晚上”（和选的时间重叠的优先）
    private var partnerFree: String? {
        let weekday = Calendar.current.component(.weekday, from: day)
        let sameDay = partnerTimes.filter { $0.dayOfWeek == weekday }.sorted { $0.startMinutes < $1.startMinutes }
        let slot = sameDay.first { $0.startMinutes < endMinutes && $0.endMinutes > startMinutes } ?? sameDay.first
        return slot.map(UsualTimeText.chip)
    }

    private var venueId: String? { venueIds.first }

    private var venueName: String? {
        guard let venueId else { return nil }
        if let court = locationManager.court(id: venueId) ?? appState.backend.venue(id: venueId) { return court.name }
        if let venue = theirVenues.first(where: { $0.id == venueId }) { return venue.name }
        if currentVenue?.id == venueId { return currentVenue?.name }
        return suggestedVenueName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Text(purpose == .new ? String(localized: "约\(partner?.nickname ?? "")") : String(localized: "换个时间"))
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(2)
                    .padding(.top, AppTheme.Spacing.xl)
                field(String(localized: "项目")) {
                    SegmentedSticker(options: GameMode.allCases, selection: $mode, title: { $0.title })
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        fieldTitle(String(localized: "日期"))
                        Spacer()
                        IconButton(systemName: "calendar", accessibilityLabel: String(localized: "选日期")) {
                            pickedDate = day
                            showsDatePicker = true
                        }
                    }
                    DateStrip(days: days, selection: $day)
                        .padding(.horizontal, -AppTheme.Spacing.screen)
                }
                field(String(localized: "时间")) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        if let partnerFree, let name = partner?.nickname {
                            Text("\(name) \(partnerFree)有空")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: AppTheme.Spacing.md) {
                            TimeStepper(title: String(localized: "开始"), minutes: startBinding, range: (6 * 60)...(23 * 60))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(AppTheme.Colors.inkTertiary)
                                .accessibilityHidden(true)
                            TimeStepper(title: String(localized: "结束"), minutes: endBinding, range: (7 * 60)...(24 * 60))
                        }
                        if !(window?.isPossible() ?? false) {
                            Text("这个时间来不及了")
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.danger)
                        }
                    }
                }
                field(String(localized: "球馆")) { venueButton }
                if let errorText {
                    Text(errorText)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(purpose == .new ? String(localized: "发出邀请") : String(localized: "发出")) { send() }
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                    .disabled(isWorking || venueId == nil || !(window?.isPossible() ?? false))
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task {
            guard !didLoad else { return }
            didLoad = true
            await loadDefaults()
        }
        .onChange(of: day) { _, _ in errorText = nil }
        .onChange(of: mode) { _, _ in errorText = nil }
        .sheet(isPresented: $showsDatePicker) {
            datePickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsVenuePicker) {
            VenuePickerView(mode: .single, selection: $venueIds)
                .presentationDragIndicator(.visible)
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.Typography.footnoteBold)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            fieldTitle(title)
            content()
        }
    }

    // MARK: 日期、时间

    private var datePickerSheet: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let last = calendar.date(byAdding: .day, value: TimeSlotConstants.maximumDaysAhead, to: today) ?? today
        return VStack(spacing: AppTheme.Spacing.md) {
            DatePicker("", selection: $pickedDate, in: today...last, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(AppTheme.Colors.ink)
            Button("好") {
                day = calendar.startOfDay(for: pickedDate)
                showsDatePicker = false
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
        }
        .padding(AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    /// 改开始：时长不变，结束跟着挪（最晚 24:00）
    private var startBinding: Binding<Int> {
        Binding(get: { startMinutes }, set: { start in
            let length = endMinutes - startMinutes
            startMinutes = start
            endMinutes = min(24 * 60, start + length)
            errorText = nil
        })
    }

    /// 改结束：一场保持 1–4 小时，不够或太长就挪开始
    private var endBinding: Binding<Int> {
        Binding(get: { endMinutes }, set: { end in
            endMinutes = end
            startMinutes = min(max(startMinutes, end - Self.longest), end - Self.shortest)
            errorText = nil
        })
    }

    // MARK: 球馆

    private var venueButton: some View {
        Button {
            showsVenuePicker = true
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(venueName ?? String(localized: "选球馆"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    if let venueId, isShared(venueId) {
                        Text("你们都常去")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            .padding(AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func isShared(_ venueId: String) -> Bool {
        locationManager.favoriteCourtIds.contains(venueId) && theirVenues.contains { $0.id == venueId }
    }

    // MARK: 默认值

    /// 项目：TA 常打的。时间：点了空闲时间就用那一段；否则用两人空闲时间的交集（服务器给）；都没有就 19:00–21:00（今天来不及就明天）。
    /// 球馆：建议的那家，否则两人都常去的、我常去的、TA 常去的
    private func loadDefaults() async {
        if let initialMode { mode = initialMode }
        if let currentVenue { venueIds = [currentVenue.id] }
        if let prefill, let next = PlayWindow.nextOccurrence(of: prefill) {
            apply(next)
        } else if !(window?.isPossible() ?? false), let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day) {
            day = tomorrow
        }
        let before = (day, startMinutes, endMinutes)
        let suggestion = await appState.backend.suggestInvite(with: userId, venueId: currentVenue?.id)
        // 等建议的时候已经自己改了时间，就不再覆盖
        if prefill == nil, let window = suggestion?.window, (day, startMinutes, endMinutes) == before { apply(window) }
        if venueIds.isEmpty {
            if let id = suggestion?.venueId {
                venueIds = [id]
                suggestedVenueName = suggestion?.venueName
            } else if let id = theirVenues.first(where: { locationManager.favoriteCourtIds.contains($0.id) })?.id
                        ?? locationManager.favoriteCourtIds.first(where: { locationManager.court(id: $0) != nil })
                        ?? theirVenues.first?.id {
                venueIds = [id]
            }
        }
    }

    /// 一段时间（TA 的空闲时间、两人的交集）填成：那天，从开头打 2 小时
    private func apply(_ window: PlayWindow) {
        let calendar = Calendar.current
        let start = (PlayWindow.clockMinutes(window.start, calendar: calendar) + 29) / 30 * 30
        guard (6 * 60)...(23 * 60) ~= start else { return }
        day = calendar.startOfDay(for: window.start)
        startMinutes = start
        endMinutes = min(24 * 60, start + 120)
    }

    // MARK: 发出

    private func send() {
        guard !isWorking, let window, window.isPossible(), let venueId else { return }
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                switch purpose {
                case .new:
                    let result = try await appState.backend.invitePlayer(userId, venueId: venueId, window: window, mode: mode)
                    Haptics.success()
                    onSent(result, window)
                case .counter(let roomId):
                    try await appState.backend.counterInvite(roomId, venueId: venueId == currentVenue?.id ? nil : venueId,
                                                             window: window, mode: mode)
                    Haptics.success()
                    onSent(nil, window)
                }
                dismiss()
            } catch {
                errorText = InviteText.error(error)
            }
        }
    }
}

// MARK: - 收到的邀请

enum InviteText {
    /// 标题说现在这个时间是谁提的：第一次是“<TA>约你打球”或“你约了<TA>”，换过时间的是“<TA>想换个时间”或“你想换个时间”
    static func title(_ room: Room, me: String?, name: (String) -> String) -> String {
        guard let invite = room.invite else { return "" }
        let other = name(invite.other(than: me))
        // 换时间是轮流的：偶数次是发邀请的人提的时间，奇数次是收到的人提的
        let mine = (invite.rounds % 2 == 0 ? invite.fromId : invite.toId) == me
        if invite.rounds == 0 {
            return mine ? String(localized: "你约了\(other)") : String(localized: "\(other)约你打球")
        }
        return mine ? String(localized: "你想换个时间") : String(localized: "\(other)想换个时间")
    }

    /// 约人时的错误：说发生了什么
    static func error(_ error: Error) -> String {
        guard case RemoteError.server(let code)? = error as? RemoteError else { return error.localizedDescription }
        switch code {
        case "invite_limit": return String(localized: "今天的 10 个用完了，明天再来")
        case "already_invited": return String(localized: "你们之间已经有一个邀请了")
        case "not_visible": return String(localized: "先在设置里打开“在同馆常客里显示我”")
        case "invalid_window", "invalid_slot": return String(localized: "这个时间来不及了")
        case "overlapping": return String(localized: "这个时间你已经有球局或待确认的约球了。")
        case "not_your_turn": return String(localized: "在等对方回复")
        case "invite_expired": return String(localized: "这个邀请已经过期了")
        case "too_late": return String(localized: "来不及了，换个时间吧")
        case "time_already_set": return String(localized: "时间已经定好了")
        default: return error.localizedDescription
        }
    }
}

/// 对方是谁：头像、昵称、等级
struct InvitePersonRow: View {
    let user: User?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if let user {
                AvatarView(user: user, size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        LevelBadge(tier: user.displayTier)
                        if user.isReliable { ReliableBadge() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }
}

/// 约的时间和球馆：“周六 11/15 · 下午” / “14:00–18:00 之间打 2 小时 · 球馆”
struct InviteSlotCard: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            Text([room.mode.title, detail, room.court?.name].compactMap { $0 }.joined(separator: " · "))
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if let window = room.window { return WindowText.headlineWithDate(window) }
        guard let slot = room.slot else { return "" }
        return "\(DateText.weekday(slot.startTime)) \(DateText.shortDay(slot.startTime))"
    }

    private var detail: String? {
        if let window = room.window { return WindowText.caption(window) }
        return room.slot?.formattedTimeRange
    }
}

/// 首页“邀请 N”点开：一次一个，不了 / 换个时间 / 好
struct InviteAnswerSheet: View {
    let invites: [Room]
    /// 回完一个：说好的带球局 ID
    let onAnswered: (Room, _ gameId: String?) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @Environment(\.dismiss) private var dismiss
    @State private var answered: Set<String> = []
    @State private var counterRoom: Room?
    @State private var isWorking = false
    @State private var errorText: String?

    private var me: String? { appState.currentUser?.id }
    private var current: Room? { invites.first { !answered.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if let room = current, let invite = room.invite {
                let other = invite.other(than: me)
                Text(InviteText.title(room, me: me) { friendManager.user(id: $0)?.nickname ?? "" })
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.top, AppTheme.Spacing.xl)
                InvitePersonRow(user: friendManager.user(id: other))
                InviteSlotCard(room: room)
                if let errorText {
                    Text(errorText)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.danger)
                }
                Spacer(minLength: 0)
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button("不了") { answer(room, accept: false) }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                    Button("换个时间") { counterRoom = room }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                    Button("好") { answer(room, accept: true) }
                        .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(item: $counterRoom, onDismiss: {
            if current == nil { dismiss() }
        }) { room in
            let other = room.invite?.other(than: me) ?? ""
            InviteComposeSheet(userId: other, purpose: .counter(roomId: room.id),
                               partnerTimes: appState.backend.usualTimes(of: other),
                               currentVenue: room.court, initialMode: room.mode) { _, _ in
                answered.insert(room.id)
                onAnswered(room, nil)
                appState.showToast(String(localized: "已发给 TA"), style: .success)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func answer(_ room: Room, accept: Bool) {
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                let gameId = try await appState.backend.respondInvite(room.id, accept: accept)
                if accept { Haptics.success() } else { Haptics.selection() }
                answered.insert(room.id)
                onAnswered(room, gameId)
                // 说好了去球局；回完了也关掉
                if accept || current == nil { dismiss() }
            } catch {
                errorText = InviteText.error(error)
            }
        }
    }
}

// MARK: - 邀请局的页面（通知、我的房间点进来）

/// 房间链接：附近的人里的邀请打开邀请页，其他的打开房间
struct RoomRouteView: View {
    let roomId: String

    @EnvironmentObject private var roomManager: RoomManager

    var body: some View {
        if roomManager.room(id: roomId)?.invite != nil {
            InviteRoomView(roomId: roomId)
        } else {
            RoomLobbyView(roomId: roomId)
        }
    }
}

struct InviteRoomView: View {
    let roomId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var friendManager: FriendManager
    @State private var showsCounter = false
    @State private var isWorking = false
    @State private var errorText: String?

    private var room: Room? { roomManager.room(id: roomId) }
    private var me: String? { appState.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "邀请")) { EmptyView() }
            if let room, let invite = room.invite {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        Text(InviteText.title(room, me: me) { friendManager.user(id: $0)?.nickname ?? "" })
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                        InvitePersonRow(user: friendManager.user(id: invite.other(than: me)))
                        InviteSlotCard(room: room)
                        statusPill(room, invite: invite)
                        if let errorText {
                            Text(errorText)
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.danger)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
                footer(room, invite: invite)
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.lg)
            } else {
                Spacer()
                EmptyStateView(icon: "envelope.open", title: String(localized: "邀请已经结束了"))
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showsCounter) {
            if let room, let invite = room.invite {
                let other = invite.other(than: me)
                InviteComposeSheet(userId: other, purpose: .counter(roomId: room.id),
                                   partnerTimes: appState.backend.usualTimes(of: other),
                                   currentVenue: room.court, initialMode: room.mode) { _, _ in
                    appState.showToast(String(localized: "已发给 TA"), style: .success)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func statusPill(_ room: Room, invite: LobbyInvite) -> some View {
        switch room.status {
        case .open:
            if invite.awaitingId != me {
                TagPill(text: String(localized: "等 TA 回复"), icon: "hourglass", fill: AppTheme.Colors.butter)
            }
        case .started:
            TagPill(text: String(localized: "约成了"), icon: "checkmark", fill: AppTheme.Colors.lime)
        case .closed(let reason):
            TagPill(text: closedText(reason), fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
        }
    }

    private func closedText(_ reason: RoomCloseReason) -> String {
        switch reason {
        case .declined: return String(localized: "这次来不了")
        case .ownerClosed: return String(localized: "已撤回")
        case .expired, .startTimePassed: return String(localized: "已过期")
        }
    }

    @ViewBuilder
    private func footer(_ room: Room, invite: LobbyInvite) -> some View {
        switch room.status {
        case .open where invite.awaitingId == me:
            HStack(spacing: AppTheme.Spacing.sm) {
                Button("不了") { answer(room, accept: false) }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                Button("换个时间") { showsCounter = true }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                Button("好") { answer(room, accept: true) }
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .disabled(isWorking)
        case .open where room.ownerId == me:
            Button("撤回") { withdraw(room) }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                .disabled(isWorking)
        case .open where invite.toId == me:
            // 换了时间在等对方回：受邀的人也能直接说不了
            Button("不了") { withdraw(room) }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                .disabled(isWorking)
        case .started(let gameId):
            Button("看球局") { router.open(.game(id: gameId), in: .games) }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
        default:
            EmptyView()
        }
    }

    private func answer(_ room: Room, accept: Bool) {
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                let gameId = try await appState.backend.respondInvite(room.id, accept: accept)
                roomManager.reload()
                if accept { Haptics.success() } else { Haptics.selection() }
                if let gameId { router.open(.game(id: gameId), in: .games) }
            } catch {
                errorText = InviteText.error(error)
            }
        }
    }

    private func withdraw(_ room: Room) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await appState.backend.withdrawInvite(room.id)
                roomManager.reload()
                if room.ownerId == me { appState.showToast(String(localized: "已撤回")) } else { Haptics.selection() }
            } catch {
                errorText = InviteText.error(error)
            }
        }
    }
}

/// “我的房间”里的邀请：和谁、大概什么时候、轮到谁
struct InviteRoomCard: View {
    let room: Room
    var currentUserId: String?

    @EnvironmentObject private var friendManager: FriendManager

    var body: some View {
        let other = room.invite?.other(than: currentUserId) ?? ""
        let user = friendManager.user(id: other)
        HStack(spacing: AppTheme.Spacing.md) {
            if let user { AvatarView(user: user, size: 44) }
            VStack(alignment: .leading, spacing: 2) {
                Text(user?.nickname ?? "")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1)
                Text(timeText)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if room.invite?.awaitingId == currentUserId {
                TagPill(text: String(localized: "待回复"), fill: AppTheme.Colors.pink)
            } else {
                TagPill(text: String(localized: "等 TA 回复"), fill: AppTheme.Colors.butter)
            }
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let when = room.window.map { WindowText.headline($0) } ?? room.slot?.formattedFull ?? ""
        return [when, room.court?.name].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 定时间

/// 约成了但还没定具体几点：在窗口里挑一个开始时间（打 2 小时）
struct SetGameTimeSheet: View {
    let game: Game

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date?
    @State private var isWorking = false
    @State private var errorText: String?

    private var starts: [Date] { game.window?.possibleStarts() ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("定时间")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            if starts.isEmpty {
                Text("这个时间来不及了")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            } else {
                Picker("", selection: Binding(get: { selection ?? starts[0] }, set: { selection = $0 })) {
                    ForEach(starts, id: \.self) { start in
                        Text(Self.label(start, duration: game.window?.duration ?? 7200)).tag(start)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            Spacer(minLength: 0)
            Button("定下来") { save() }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                .disabled(isWorking || starts.isEmpty)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    /// “周六 14:00–16:00”
    static func label(_ start: Date, duration: TimeInterval) -> String {
        "\(WindowText.dayName(start)) \(DateText.time(start))–\(DateText.time(start.addingTimeInterval(duration)))"
    }

    private func save() {
        guard let start = selection ?? starts.first else { return }
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.backend.setGameTime(game.id, startsAt: start)
                matchManager.reloadGames()
                Haptics.success()
                appState.showToast(String(localized: "定好了：\(Self.label(start, duration: game.window?.duration ?? 7200))"), style: .success)
                dismiss()
            } catch {
                errorText = InviteText.error(error)
            }
        }
    }
}
