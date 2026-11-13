import SwiftUI

/// 按天看人的筛选：项目、球馆、等级、时间、对方性别、只看没爽约过的。记在本机，下次打开还在
struct DayCardFilter: Codable, Equatable {
    enum Event: String, Codable, CaseIterable {
        case any, singles, doubles, mixed

        var title: String {
            switch self {
            case .any: String(localized: "全部")
            case .singles: String(localized: "单打")
            case .doubles: String(localized: "双打")
            case .mixed: String(localized: "混双")
            }
        }
    }

    enum TimeOfDay: String, Codable, CaseIterable {
        case morning, afternoon, evening

        var title: String {
            switch self {
            case .morning: String(localized: "上午")
            case .afternoon: String(localized: "下午")
            case .evening: String(localized: "晚上")
            }
        }

        /// 一段空闲时间有没有落在这个时段里（上午 0–12 点、下午 12–18 点、晚上 18 点以后，和按开始时间分的一致）
        func overlaps(_ slot: RecurringTimeSlot) -> Bool {
            let range: (Int, Int)
            switch self {
            case .morning: range = (0, 12 * 60)
            case .afternoon: range = (12 * 60, 18 * 60)
            case .evening: range = (18 * 60, 24 * 60)
            }
            return min(slot.endMinutes, range.1) - max(slot.startMinutes, range.0) > 0
        }

        /// 按开始时间：12 点前上午，18 点前下午，之后晚上
        init(_ date: Date) {
            let hour = Calendar.current.component(.hour, from: date)
            self = hour < 12 ? .morning : hour < 18 ? .afternoon : .evening
        }
    }

    var event: Event = .any
    /// 空 = 全部球馆
    var venueIds: Set<String> = []
    /// 选过的球馆的名字（这天没人约那家时，也能在筛选页和小标签里看到）
    var venueNames: [String: String] = [:]
    var minLevel = 1
    var maxLevel = 9
    /// 空 = 不限
    var times: Set<TimeOfDay> = []
    /// nil = 不限
    var gender: Gender?
    var reliableOnly = false

    static let levels = 1...9

    init() {}

    /// 以后加了新条件，老的存档也能读（缺的用默认值）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let empty = DayCardFilter()
        event = (try? c.decodeIfPresent(Event.self, forKey: .event)) ?? empty.event
        venueIds = (try? c.decodeIfPresent(Set<String>.self, forKey: .venueIds)) ?? empty.venueIds
        venueNames = (try? c.decodeIfPresent([String: String].self, forKey: .venueNames)) ?? empty.venueNames
        minLevel = (try? c.decodeIfPresent(Int.self, forKey: .minLevel)) ?? empty.minLevel
        maxLevel = (try? c.decodeIfPresent(Int.self, forKey: .maxLevel)) ?? empty.maxLevel
        times = (try? c.decodeIfPresent(Set<TimeOfDay>.self, forKey: .times)) ?? empty.times
        gender = try? c.decodeIfPresent(Gender.self, forKey: .gender)
        reliableOnly = (try? c.decodeIfPresent(Bool.self, forKey: .reliableOnly)) ?? empty.reliableOnly
    }

    /// 选了几个条件（按钮上显示）
    var activeCount: Int {
        [event != .any, !venueIds.isEmpty, minLevel > 1 || maxLevel < 9, !times.isEmpty, gender != nil, reliableOnly].filter { $0 }.count
    }

    func matches(_ card: MockBackend.DayCandidate, user: User?) -> Bool {
        switch event {
        case .any: break
        case .singles: if card.mode != .singles { return false }
        case .doubles: if card.mode != .doubles || card.mixed { return false }
        case .mixed: if !card.mixed { return false }
        }
        if !venueIds.isEmpty, !card.venues.contains(where: { venueIds.contains($0.id) }) { return false }
        if let user {
            let level = user.displayLevel
            if level < minLevel || level > maxLevel { return false }
            if let gender, user.gender != gender { return false }
        }
        if !times.isEmpty, !times.contains(TimeOfDay(card.startsAt)) { return false }
        if reliableOnly, card.recentNoShows > 0 { return false }
        return true
    }

    /// 附近的人：时间按 TA 的空闲时间（有一段落在选的时段里就算，没填的都算）；
    /// 项目按 TA 常打的（没填的都算），混双算双打；球馆按 TA 常去的
    func matches(_ card: MockBackend.NearbyPlayer, user: User?) -> Bool {
        if !times.isEmpty, !card.usualTimes.isEmpty,
           !card.usualTimes.contains(where: { slot in times.contains { $0.overlaps(slot) } }) { return false }
        if let mode = card.preferredMode {
            switch event {
            case .any: break
            case .singles: if mode != .singles { return false }
            case .doubles, .mixed: if mode != .doubles { return false }
            }
        }
        if !venueIds.isEmpty, !card.venues.contains(where: { venueIds.contains($0.id) }) { return false }
        if let user {
            let level = user.displayLevel
            if level < minLevel || level > maxLevel { return false }
            if let gender, user.gender != gender { return false }
        }
        if reliableOnly, card.recentNoShows > 0 { return false }
        return true
    }

    /// 约在哪家：选了球馆就用选的那家，否则离我最近的
    func venue(for card: MockBackend.DayCandidate) -> MockBackend.DayCandidate.Venue? {
        let sorted = card.venues.sorted { ($0.km ?? .infinity) < ($1.km ?? .infinity) }
        return sorted.first { venueIds.contains($0.id) } ?? sorted.first
    }

    // MARK: 本机记住

    private static let key = "BadieDayCardFilter"

    static func load() -> DayCardFilter {
        guard let data = UserDefaults.standard.data(forKey: key),
              let filter = try? JSONDecoder().decode(DayCardFilter.self, from: data) else { return DayCardFilter() }
        return filter
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// 筛选页
struct DayCardFilterSheet: View {
    @Binding var filter: DayCardFilter
    /// 这天卡片里出现的球馆和人数
    let venues: [(venue: MockBackend.DayCandidate.Venue, count: Int)]
    /// 按现在的条件能看到几个人
    let count: (DayCardFilter) -> Int
    /// 现在看的是哪天（nil：任何时间）；换了一天在点按钮时告诉外面
    var day: Date?
    var onDay: (Date?) -> Void = { _ in }

    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DayCardFilter()
    @State private var draftDay: Date?

    private var dayChanged: Bool { draftDay != day }

    /// 今天起 7 天
    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("筛选")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                Button("重置") {
                    draft = DayCardFilter()
                    draftDay = nil
                }
                .buttonStyle(TextActionStyle())
                .disabled(draft == DayCardFilter() && draftDay == nil)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    section(String(localized: "日期")) { dayChips }
                    section(String(localized: "项目")) {
                        SegmentedSticker(options: DayCardFilter.Event.allCases, selection: $draft.event, title: { $0.title })
                    }
                    if !allVenues.isEmpty {
                        section(String(localized: "球馆")) {
                            VStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(allVenues, id: \.venue.id) { item in
                                    venueRow(item.venue, count: item.count)
                                }
                            }
                        }
                    }
                    section(String(localized: "等级")) {
                        HStack(spacing: AppTheme.Spacing.md) {
                            levelStepper(String(localized: "从"), value: $draft.minLevel, range: 1...draft.maxLevel)
                            levelStepper(String(localized: "到"), value: $draft.maxLevel, range: draft.minLevel...9)
                        }
                    }
                    section(String(localized: "时间")) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(DayCardFilter.TimeOfDay.allCases, id: \.self) { time in
                                ChoiceChip(title: time.title, isSelected: draft.times.contains(time)) {
                                    if draft.times.contains(time) { draft.times.remove(time) } else { draft.times.insert(time) }
                                }
                            }
                        }
                    }
                    section(String(localized: "对方性别")) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ChoiceChip(title: String(localized: "不限"), isSelected: draft.gender == nil) { draft.gender = nil }
                            ChoiceChip(title: String(localized: "男"), isSelected: draft.gender == .male) { draft.gender = .male }
                            ChoiceChip(title: String(localized: "女"), isSelected: draft.gender == .female) { draft.gender = .female }
                        }
                    }
                    Toggle(isOn: $draft.reliableOnly) {
                        Text("只看没爽约过的")
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                    }
                    .tint(AppTheme.Colors.lime)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }

            // 换了一天，人数要换过去才知道
            Button(dayChanged ? String(localized: "好") : String(localized: "看 \(count(draft)) 个人")) {
                filter = draft
                filter.save()
                if dayChanged { onDay(draftDay) }
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            draft = filter
            draftDay = day
        }
    }

    /// 任何时间（附近的人）、今天、明天……后面是这天有几个人有空
    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ChoiceChip(title: String(localized: "任何时间"), isSelected: draftDay == nil) { draftDay = nil }
                ForEach(days, id: \.self) { date in
                    let count = matchManager.availableCount(on: date, radiusKm: locationManager.preferences.travelRadiusKm)
                    ChoiceChip(title: count > 0 ? "\(WindowText.dayName(date)) · \(count)" : WindowText.dayName(date),
                               isSelected: draftDay.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false) {
                        draftDay = date
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, -AppTheme.Spacing.screen)
    }

    /// 这天卡片里的球馆，加上以前选过、这天没人约的（人数 0，可以去掉）
    private var allVenues: [(venue: MockBackend.DayCandidate.Venue, count: Int)] {
        let present = Set(venues.map(\.venue.id))
        let saved = filter.venueIds.subtracting(present).sorted().map {
            (venue: MockBackend.DayCandidate.Venue(id: $0, name: filter.venueNames[$0] ?? $0), count: 0)
        }
        return venues + saved
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func venueRow(_ venue: MockBackend.DayCandidate.Venue, count: Int) -> some View {
        let selected = draft.venueIds.contains(venue.id)
        return Button {
            Haptics.selection()
            if selected {
                draft.venueIds.remove(venue.id)
                draft.venueNames[venue.id] = nil
            } else {
                draft.venueIds.insert(venue.id)
                draft.venueNames[venue.id] = venue.name
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                Text(venue.name)
                    .font(AppTheme.Typography.subheadlineBold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: AppTheme.Spacing.sm)
                Text("\(count)")
                    .font(AppTheme.Typography.footnoteBold)
                    .monospacedDigit()
            }
            .foregroundStyle(selected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: 48)
            .sticker(selected ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func levelStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus").frame(width: 36, height: 40).contentShape(Rectangle())
            }
            .disabled(value.wrappedValue <= range.lowerBound)
            .accessibilityLabel(Text("降低"))
            Text("Lv.\(value.wrappedValue)")
                .font(AppTheme.Typography.headline)
                .monospacedDigit()
            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus").frame(width: 36, height: 40).contentShape(Rectangle())
            }
            .disabled(value.wrappedValue >= range.upperBound)
            .accessibilityLabel(Text("提高"))
        }
        .font(.system(size: 15, weight: .heavy))
        .foregroundStyle(AppTheme.Colors.ink)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }
}
