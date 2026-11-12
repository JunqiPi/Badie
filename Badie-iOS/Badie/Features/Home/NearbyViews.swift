import PhotosUI
import SwiftUI

// MARK: - 附近的人：卡片

/// 附近的人：和按天的卡片同一个样子，只是不写时间，写 TA 常去的球馆、常有空的时间
struct NearbyCardView: View {
    let user: User?
    let card: MockBackend.NearbyPlayer
    /// 第一行显示的球馆（选了球馆筛选时是选的那家）
    var venue: MockBackend.DayCandidate.Venue?
    var onProfile: (() -> Void)?
    /// 点了 TA 的某段空闲时间：约 TA 这一段最近的一次
    var onInvite: ((RecurringTimeSlot) -> Void)?

    var body: some View {
        let photo = user.flatMap { AvatarPhotos.cardImage(userId: $0.id, avatar: $0.avatar) }
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let user {
                    CardCover(color: user.cardColor, photo: photo) {
                        AvatarView(user: user, size: 140)
                            .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
                    }
                } else {
                    AppTheme.Colors.surfaceMuted
                }
            }
            .overlay(alignment: .topLeading) {
                NearbyChip().padding(AppTheme.Spacing.md)
            }
            .overlay(alignment: .bottomLeading) {
                if let user, photo != nil {
                    AvatarView(user: user, size: 64)
                        .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 2, y: 3))
                        .padding(.leading, AppTheme.Spacing.lg)
                        .offset(y: 32)
                }
            }
            .zIndex(1)
            info
                .padding(.top, photo != nil ? 36 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let user {
                HStack(spacing: AppTheme.Spacing.sm) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    LevelBadge(tier: user.displayTier)
                    if card.recentNoShows == 0 { ReliableBadge() }
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if let name = (venue ?? card.venues.first)?.name {
                    Label(String(localized: "常去 \(name)"), systemImage: "mappin.and.ellipse").lineLimit(1)
                }
                if let mode = card.preferredMode {
                    Label(mode.title, systemImage: "figure.badminton")
                }
                if card.recentNoShows > 0 {
                    Label(String(localized: "近 180 天爽约 \(card.recentNoShows) 次"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }
            .font(AppTheme.Typography.bodyBold)
            .foregroundStyle(AppTheme.Colors.ink)
            if !card.usualTimes.isEmpty {
                UsualTimeChips(slots: card.usualTimes, onTap: onInvite)
            }
            HStack(spacing: AppTheme.Spacing.md) {
                if let onProfile {
                    Button("看资料", action: onProfile)
                        .buttonStyle(TextActionStyle())
                }
                Spacer(minLength: 0)
                FriendQuickButton(userId: card.userId, isFriend: card.isFriend, request: card.friendRequest)
            }
        }
        .padding(AppTheme.Spacing.lg)
    }
}

/// “常有空”：TA 的空闲时间，一段一个小标签（最多 4 个，多了“+N”）。点一个就约这一段
struct UsualTimeChips: View {
    let slots: [RecurringTimeSlot]
    var onTap: ((RecurringTimeSlot) -> Void)?

    var body: some View {
        let sorted = UsualTimeText.sortedByNext(slots)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("常有空")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            FlowLayout(spacing: 6) {
                ForEach(sorted.prefix(4)) { slot in
                    Button {
                        onTap?(slot)
                    } label: {
                        Text(UsualTimeText.chip(slot))
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.onAccent)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Capsule().fill(AppTheme.Colors.lime))
                            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(onTap == nil)
                    .accessibilityLabel(Text("约 \(UsualTimeText.chip(slot))"))
                }
                if sorted.count > 4 {
                    TagPill(text: "+\(sorted.count - 4)", fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.inkSecondary)
                }
            }
        }
    }
}

/// 加球友 / 已申请 / 同意 / 发消息（加球友不占每天约人的名额）
struct FriendQuickButton: View {
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

    var body: some View {
        Group {
            if isFriend || becameFriends || friendManager.isFriend(userId) {
                Button {
                    router.open(.chat(userId: userId), in: .messages)
                } label: {
                    Label("发消息", systemImage: "bubble.left.fill")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
            } else if requested || request == .sent || friendManager.hasPendingRequest(to: userId) {
                Button("已申请") {}
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                    .disabled(true)
            } else if request == .received || friendManager.incomingRequest(from: userId) != nil {
                Button("同意") { add() }
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
            } else {
                Button {
                    add()
                } label: {
                    Label("加球友", systemImage: "person.badge.plus")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
            }
        }
        .disabled(isWorking)
    }

    /// 对方也申请过我：同意（服务器上再申请一次就是同意）；否则发申请
    private func add() {
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

/// 卡片左上角的小标签
struct NearbyChip: View {
    var body: some View {
        TagPill(text: String(localized: "常在附近"), fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
    }
}

/// 这天的卡片刷完了，接着是附近的人（虚线框）
struct NearbyDivider: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("这天的刷完了")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            Text("接着看附近的人")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).fill(AppTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            .strokeBorder(AppTheme.Colors.stroke, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        .accessibilityElement(children: .combine)
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

// MARK: - 约 TA：哪天、什么时候、哪家

/// 半屏“约<昵称>”：右滑、点卡片上的空闲时间、收到邀请后“换个时间”都用这一页
struct InviteComposeSheet: View {
    enum Purpose: Equatable {
        case new
        case counter(roomId: String)
    }

    enum DayChoice: Hashable {
        case weekend
        case nextWeekdays
        case day(Date)
    }

    enum TimeChoice: Hashable {
        /// TA 的某段空闲时间（slot id）
        case usual(String)
        case part(Daypart)
        case any
        case custom
    }

    let userId: String
    var purpose: Purpose = .new
    /// TA 的空闲时间（排在“什么时候”最前面）
    var partnerTimes: [RecurringTimeSlot] = []
    /// TA 常去的球馆（卡片上的），近的在前
    var theirVenues: [MockBackend.DayCandidate.Venue] = []
    /// 点卡片上的空闲时间进来：时间已经填好
    var prefill: RecurringTimeSlot?
    /// 换个时间：现在的球馆
    var currentVenue: BadmintonCourt?
    /// 发出去了（新邀请带结果；换个时间是 nil）
    var onSent: (MockBackend.InviteResult?, PlayWindow) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var day: DayChoice = .weekend
    @State private var time: TimeChoice = .any
    @State private var customStart = 19 * 60
    @State private var customEnd = 21 * 60
    @State private var venueIds: [String] = []
    @State private var suggestedVenueName: String?
    @State private var showsDatePicker = false
    @State private var pickedDate = Date()
    @State private var showsVenuePicker = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var didLoad = false

    private var partner: User? { friendManager.user(id: userId) }
    private var times: [RecurringTimeSlot] { UsualTimeText.sortedByNext(partnerTimes) }

    private var nextDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// 现在选的时间窗口
    private var window: PlayWindow? {
        switch day {
        case .weekend:
            return PlayWindow.weekend(daypart: part)
        case .nextWeekdays:
            return PlayWindow.nextWeekdays(daypart: part)
        case .day(let date):
            switch time {
            case .usual(let id):
                guard let slot = times.first(where: { $0.id == id }) else { return PlayWindow.on(date, daypart: nil) }
                return PlayWindow.nextOccurrence(of: slot)
            case .part(let daypart):
                return PlayWindow.on(date, daypart: daypart)
            case .any:
                return PlayWindow.on(date, daypart: nil)
            case .custom:
                return PlayWindow.on(date, startMinutes: customStart, endMinutes: customEnd)
            }
        }
    }

    private var part: Daypart? {
        if case .part(let daypart) = time { return daypart }
        return nil
    }

    private var isSpecificDay: Bool {
        if case .day = day { return true }
        return false
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
                    .padding(.top, AppTheme.Spacing.xl)
                field(String(localized: "哪天")) { dayChips }
                field(String(localized: "什么时候")) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        timeChips
                        if time == .custom { customSteppers }
                        captionLine
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
        .onChange(of: customStart) { _, start in
            if customEnd < start + 120 { customEnd = min(24 * 60, start + 120) }
        }
        .onChange(of: customEnd) { _, end in
            if customStart > end - 120 { customStart = max(6 * 60, end - 120) }
        }
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

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            content()
        }
    }

    // MARK: 哪天

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ChoiceChip(title: String(localized: "这周末"), isSelected: day == .weekend) { selectDay(.weekend) }
                ChoiceChip(title: String(localized: "下周工作日"), isSelected: day == .nextWeekdays) { selectDay(.nextWeekdays) }
                ForEach(nextDays, id: \.self) { date in
                    ChoiceChip(title: WindowText.dayName(date), isSelected: day == .day(date)) { selectDay(.day(date)) }
                }
                // 用日历选了 7 天以后的某天
                if case .day(let date) = day, !nextDays.contains(date) {
                    ChoiceChip(title: WindowText.dayName(date), isSelected: true) {}
                }
                ChoiceChip(title: "…", isSelected: false) {
                    if case .day(let date) = day { pickedDate = date }
                    showsDatePicker = true
                }
                .accessibilityLabel(Text("选日期"))
            }
            .padding(.vertical, 4)
        }
    }

    private func selectDay(_ choice: DayChoice) {
        day = choice
        switch choice {
        case .weekend, .nextWeekdays:
            // 跨好几天的只能选时段
            if time == .custom { time = .any }
            if case .usual = time { time = .any }
        case .day(let date):
            // 选了 TA 的某段空闲时间又换了一天：改成那一段所在的时段
            if case .usual(let id) = time, let slot = times.first(where: { $0.id == id }) {
                let sameDay = PlayWindow.nextOccurrence(of: slot).map { Calendar.current.isDate($0.start, inSameDayAs: date) } ?? false
                if !sameDay {
                    time = Daypart.best(start: slot.startMinutes, end: slot.endMinutes).map { TimeChoice.part($0) } ?? .any
                }
            }
        }
        errorText = nil
    }

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
                selectDay(.day(calendar.startOfDay(for: pickedDate)))
                showsDatePicker = false
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
        }
        .padding(AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    // MARK: 什么时候

    private var timeChips: some View {
        FlowLayout(spacing: AppTheme.Spacing.sm) {
            ForEach(times.prefix(4)) { slot in
                ChoiceChip(title: UsualTimeText.chip(slot), isSelected: time == .usual(slot.id), tint: AppTheme.Colors.peach) {
                    selectUsual(slot)
                }
            }
            ForEach(Daypart.allCases) { daypart in
                ChoiceChip(title: daypart.title, isSelected: time == .part(daypart)) { selectTime(.part(daypart)) }
            }
            ChoiceChip(title: String(localized: "都行"), isSelected: time == .any) { selectTime(.any) }
            if isSpecificDay {
                ChoiceChip(title: String(localized: "自己定"), isSelected: time == .custom) { selectTime(.custom) }
            }
        }
    }

    private func selectTime(_ choice: TimeChoice) {
        time = choice
        errorText = nil
    }

    /// TA 的空闲时间：日子跟着变成那一段最近的一次
    private func selectUsual(_ slot: RecurringTimeSlot) {
        guard let next = PlayWindow.nextOccurrence(of: slot) else { return }
        day = .day(Calendar.current.startOfDay(for: next.start))
        time = .usual(slot.id)
        errorText = nil
    }

    private var customSteppers: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Stepper(value: $customStart, in: (6 * 60)...(22 * 60), step: 30) {
                clockRow(String(localized: "开始"), customStart)
            }
            Stepper(value: $customEnd, in: (8 * 60)...(24 * 60), step: 30) {
                clockRow(String(localized: "结束"), customEnd)
            }
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func clockRow(_ title: String, _ minutes: Int) -> some View {
        HStack {
            Text(title)
                .font(AppTheme.Typography.bodyBold)
            Spacer()
            Text(RecurringTimeSlot.clock(minutes))
                .font(AppTheme.Typography.headline)
                .monospacedDigit()
        }
        .foregroundStyle(AppTheme.Colors.ink)
    }

    @ViewBuilder
    private var captionLine: some View {
        if let window, window.isPossible() {
            Text(isSpecificDay ? WindowText.caption(window) : "\(WindowText.headline(window)) · \(WindowText.caption(window))")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .monospacedDigit()
        } else {
            Text("这个时间来不及了")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.danger)
        }
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

    /// 点了空闲时间就用那一段；否则用两人空闲时间的交集（服务器给），没有交集就“这周末 · 都行”。
    /// 球馆：建议的那家，否则两人都常去的、我常去的、TA 常去的
    private func loadDefaults() async {
        if let currentVenue { venueIds = [currentVenue.id] }
        if let prefill {
            selectUsual(times.first(where: { $0.id == prefill.id }) ?? prefill)
        }
        let suggestion = await appState.backend.suggestInvite(with: userId, venueId: currentVenue?.id)
        if prefill == nil, let window = suggestion?.window { apply(window) }
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

    /// 服务器建议的时间（同一天的）换成上面的选项
    private func apply(_ window: PlayWindow) {
        guard window.isSingleDay else { return }
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: window.start)
        day = .day(date)
        if let slot = times.first(where: { slot in
            guard let next = PlayWindow.nextOccurrence(of: slot) else { return false }
            return calendar.isDate(next.start, inSameDayAs: date) && next.start <= window.start && next.end >= window.end
        }) {
            time = .usual(slot.id)
        } else if let daypart = window.displayDaypart, PlayWindow.on(date, daypart: daypart)?.end == window.end {
            time = .part(daypart)
        } else {
            customStart = max(6 * 60, Int(window.start.timeIntervalSince(date) / 60) / 30 * 30)
            customEnd = min(24 * 60, max(customStart + 120, Int(window.end.timeIntervalSince(date) / 60) / 30 * 30))
            time = .custom
        }
    }

    // MARK: 发出

    private func send() {
        guard let window, window.isPossible(), let venueId else { return }
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                switch purpose {
                case .new:
                    let result = try await appState.backend.invitePlayer(userId, venueId: venueId, window: window)
                    Haptics.success()
                    onSent(result, window)
                case .counter(let roomId):
                    try await appState.backend.counterInvite(roomId, venueId: venueId == currentVenue?.id ? nil : venueId, window: window)
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
    /// 半屏的标题：第一次是“<TA>约你打球”，换过时间的是“<TA>想换个时间”
    static func title(_ room: Room, me: String?, name: (String) -> String) -> String {
        guard let invite = room.invite else { return "" }
        let other = name(invite.other(than: me))
        if invite.rounds == 0 && invite.toId == me { return String(localized: "\(other)约你打球") }
        return String(localized: "\(other)想换个时间")
    }

    /// 约人时的错误：说发生了什么
    static func error(_ error: Error) -> String {
        guard case RemoteError.server(let code)? = error as? RemoteError else { return error.localizedDescription }
        switch code {
        case "invite_limit": return String(localized: "今天的 10 个用完了，明天再来")
        case "already_invited": return String(localized: "你们之间已经有一个邀请了")
        case "not_visible": return String(localized: "先在设置里打开“在同馆常客里显示我”")
        case "invalid_window", "invalid_slot": return String(localized: "这个时间来不及了")
        case "not_your_turn": return String(localized: "在等对方回复")
        case "invite_expired": return String(localized: "这个邀请已经过期了")
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
            Text([detail, room.court?.name].compactMap { $0 }.joined(separator: " · "))
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
                               currentVenue: room.court) { _, _ in
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
                                   currentVenue: room.court) { _, _ in
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
                appState.showToast(String(localized: "已撤回"))
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
