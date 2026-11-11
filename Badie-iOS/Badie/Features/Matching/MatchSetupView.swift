import SwiftUI

/// 快速匹配设置：项目 · 日期 · 时间 · 球馆（最多 3 个）· 实力差
/// 页面上只放字段名和选项；规则收进各字段旁的“?”
struct MatchSetupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var recurring: [RecurringTimeSlot] = []
    @State private var showVenuePicker = false
    static let venuesAnchor = "venues"

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<TimeSlotConstants.maximumDaysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var userTier: SkillTier { appState.currentUser?.displayTier ?? SkillTier(level: 4) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("快速匹配")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) {
                    router.isMatchSetupPresented = false
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                        if matchManager.draft.replacingTicketId != nil {
                            editingTag
                                .padding(.horizontal, AppTheme.Spacing.screen)
                        }
                        eventSection
                            .padding(.horizontal, AppTheme.Spacing.screen)
                        dateSection
                        timeSection
                            .padding(.horizontal, AppTheme.Spacing.screen)
                        courtsSection
                            .padding(.horizontal, AppTheme.Spacing.screen)
                            .id(Self.venuesAnchor)
                        skillSection
                            .padding(.horizontal, AppTheme.Spacing.screen)
                        confirmSection
                            .padding(.horizontal, AppTheme.Spacing.screen)
                    }
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .onAppear {
                    // 演示/截图：直接滚到“球馆”部分
                    if router.matchSetupAnchor == Self.venuesAnchor {
                        router.matchSetupAnchor = nil
                        DispatchQueue.main.async { proxy.scrollTo(Self.venuesAnchor, anchor: .top) }
                    }
                }
            }
            footer
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            recurring = appState.backend.recurringSlots()
            matchManager.prepareDraft(user: appState.currentUser, nearbyCourts: locationManager.nearbyCourts,
                                      recurring: recurring, favorites: locationManager.favoriteCourts.map(\.id),
                                      isValidCourt: { locationManager.court(id: $0) != nil })
        }
        .sheet(isPresented: $showVenuePicker) {
            VenuePickerView(mode: .multiple(max: MatchDraft.maxCourts), selection: $matchManager.draft.courtIds,
                            slot: matchManager.draft.slot)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 正在修改一个请求（保存时换掉原来的）

    private var editingTag: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            TagPill(text: String(localized: "修改中"), icon: "pencil", fill: AppTheme.Colors.butter)
            Spacer(minLength: 0)
            Button("不改了") {
                matchManager.draft.replacingTicketId = nil
            }
            .buttonStyle(TextActionStyle())
        }
    }

    // MARK: 项目：单打 / 双打 / 混双；不是混双时还能只限同性别（男单、女双……）

    private enum EventChoice: Hashable { case singles, doubles, mixed }

    private var gender: Gender { appState.currentUser?.gender ?? .unspecified }

    /// 混双要知道自己的性别（男女都要有）
    private var eventChoices: [EventChoice] {
        PlayEvent.choices(mode: .doubles, gender: gender).contains(.mixed) ? [.singles, .doubles, .mixed] : [.singles, .doubles]
    }

    private var eventChoice: Binding<EventChoice> {
        Binding(
            get: {
                if matchManager.draft.event == .mixed { return .mixed }
                return matchManager.draft.mode == .singles ? .singles : .doubles
            },
            set: { choice in
                switch choice {
                case .singles, .doubles:
                    matchManager.draft.mode = choice == .singles ? .singles : .doubles
                    if matchManager.draft.event == .mixed { matchManager.draft.event = nil }
                case .mixed:
                    matchManager.draft.mode = .doubles
                    matchManager.draft.event = .mixed
                }
            }
        )
    }

    /// 不限，或只限自己的性别（混双时不显示）
    private var audienceChoices: [PlayEvent?] {
        PlayEvent.choices(mode: matchManager.draft.mode, gender: gender).filter { $0 != .mixed }
    }

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                label(String(localized: "项目"))
                Spacer()
                RulesButton(title: String(localized: "项目"),
                            points: PlayEvent.choices(mode: .doubles, gender: gender).map { PlayEvent.caption($0) })
            }
            SegmentedSticker(options: eventChoices, selection: eventChoice, title: { choice in
                switch choice {
                case .singles: return GameMode.singles.title
                case .doubles: return GameMode.doubles.title
                case .mixed: return PlayEvent.mixed.title(mode: .doubles)
                }
            })
            if matchManager.draft.event != .mixed && audienceChoices.count > 1 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(audienceChoices, id: \.self) { event in
                        ChoiceChip(title: event?.title(mode: matchManager.draft.mode) ?? String(localized: "不限"),
                                   isSelected: matchManager.draft.event == event) {
                            matchManager.draft.event = event
                        }
                    }
                }
            }
        }
    }

    // MARK: Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            label(String(localized: "日期"))
                .padding(.horizontal, AppTheme.Spacing.screen)
            DateStrip(
                days: days,
                selection: $matchManager.draft.day,
                counts: { matchManager.availableCount(on: $0, radiusKm: locationManager.preferences.travelRadiusKm) }
            )
        }
    }

    // MARK: Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: 0) {
                label(String(localized: "时间"))
                Spacer()
                RulesButton(title: String(localized: "时间"), points: [
                    String(localized: "匹配时，你和对方的时间至少要重叠 30 分钟。"),
                    String(localized: "离开赛不到 30 分钟就不能发起了。")
                ])
            }
            HStack(spacing: AppTheme.Spacing.md) {
                TimeStepper(title: String(localized: "开始"), minutes: $matchManager.draft.startMinutes, range: (6 * 60)...(23 * 60))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                TimeStepper(title: String(localized: "结束"), minutes: $matchManager.draft.endMinutes, range: (7 * 60)...(24 * 60))
            }
            if let message = matchManager.draft.validation.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ChoiceChip(title: String(localized: "任何时间"), isSelected: matchManager.draft.isAnyTime, tint: AppTheme.Colors.lime) {
                        matchManager.draft.setAnyTime()
                    }
                    ForEach(Self.presets, id: \.0) { preset in
                        ChoiceChip(title: preset.0, isSelected: matchManager.draft.startMinutes == preset.1 && matchManager.draft.endMinutes == preset.2,
                                   tint: AppTheme.Colors.peach) {
                            matchManager.draft.startMinutes = preset.1
                            matchManager.draft.endMinutes = preset.2
                        }
                    }
                    ForEach(recurring.activeSlots) { slot in
                        ChoiceChip(title: String(localized: "常用 · \(slot.displayText)"), icon: "star.fill", isSelected: false, tint: AppTheme.Colors.butter) {
                            if let next = slot.nextOccurrence() { matchManager.draft.apply(next) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private static let presets: [(String, Int, Int)] = [
        (String(localized: "早上"), 7 * 60, 9 * 60), (String(localized: "中午"), 12 * 60, 14 * 60),
        (String(localized: "下午"), 14 * 60, 17 * 60),
        (String(localized: "晚上"), 19 * 60, 21 * 60), (String(localized: "夜里"), 21 * 60, 23 * 60)
    ]

    // MARK: Courts（每行只有名字和距离）

    private var courtsSection: some View {
        let selected = locationManager.courts(ids: matchManager.draft.courtIds)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                label(String(localized: "球馆"))
                RulesButton(title: String(localized: "球馆"), points: [
                    String(localized: "只和也能去这些球馆（或 150 米内同一处）的球友匹配。"),
                    String(localized: "最多选 \(MatchDraft.maxCourts) 个。"),
                    String(localized: "按钮上的费用按所选球馆里最便宜的一家估算，到场后按实际费用 AA。"),
                    String(localized: "平台不收服务费。")
                ])
                Spacer()
                Text("\(selected.count)/\(MatchDraft.maxCourts)")
                    .font(AppTheme.Typography.footnoteBold)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(selected.enumerated()), id: \.element.id) { index, court in
                    if index > 0 { InsetDivider() }
                    courtRow(court)
                }
                if !selected.isEmpty { InsetDivider() }
                Button {
                    showVenuePicker = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        IconTile(systemName: selected.isEmpty ? "magnifyingglass" : "plus", fill: AppTheme.Colors.lime, size: 36)
                        Text("选择球馆")
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                    .padding(.vertical, AppTheme.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
        }
    }

    private func courtRow(_ court: BadmintonCourt) -> some View {
        let isClosed = matchManager.draft.slot.map { !court.isOpen(for: $0) } ?? false
        return HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(court.name)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(2)
                if isClosed {
                    Label("所选时段不营业", systemImage: "moon.zzz.fill")
                        .font(AppTheme.Typography.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(court.formattedDistance(from: locationManager.coordinate))
                .font(AppTheme.Typography.footnoteBold)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize()
            Button {
                Haptics.selection()
                _ = matchManager.draft.toggleCourt(court.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("移除\(court.name)")
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    // MARK: Skill tolerance

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                label(String(localized: "实力差"))
                Spacer()
                RulesButton(title: String(localized: "实力差"), points: skillPoints)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                ChoiceChip(title: String(localized: "±1 级"), isSelected: matchManager.draft.skillTolerance == 1) { matchManager.draft.skillTolerance = 1 }
                ChoiceChip(title: String(localized: "±2 级"), isSelected: matchManager.draft.skillTolerance == 2) { matchManager.draft.skillTolerance = 2 }
                ChoiceChip(title: String(localized: "不限"), isSelected: matchManager.draft.skillTolerance >= MatchRequest.anySkill) {
                    matchManager.draft.skillTolerance = MatchRequest.anySkill
                }
            }
        }
    }

    /// 每档会匹配到的等级范围（一级 = 3 个小档）
    private var skillPoints: [String] {
        let one = SkillTier.rangeText(userTier.offset(by: -3), userTier.offset(by: 3))
        let two = SkillTier.rangeText(userTier.offset(by: -6), userTier.offset(by: 6))
        return [
            String(localized: "你的等级是 \(userTier.text)。"),
            String(localized: "±1 级：匹配 \(one) 的球友。"),
            String(localized: "±2 级：匹配 \(two) 的球友。"),
            String(localized: "不限：匹配所有水平的球友。"),
            String(localized: "水平越接近，排得越靠前。")
        ]
    }

    // MARK: Confirmation

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                Text("找到就直接接受")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                RulesButton(title: String(localized: "找到就直接接受"), points: confirmPoints)
                Spacer(minLength: AppTheme.Spacing.sm)
                Toggle(String(localized: "找到就直接接受"), isOn: $matchManager.draft.autoAccept)
                    .labelsHidden()
                    .tint(AppTheme.Colors.success)
            }
            if isLastMinute && canRequest {
                HStack(spacing: 0) {
                    TagPill(text: String(localized: "临时局"), icon: "bolt.fill", fill: AppTheme.Colors.butter)
                    RulesButton(title: String(localized: "临时局"), points: [
                        String(localized: "离开赛不远时发起的是临时局，只匹配此刻也在找人的球友。"),
                        String(localized: "找到后要在 5–10 分钟内确认，建议打开“找到就直接接受”。")
                    ])
                }
            }
            if let error = timingError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canRequest: Bool {
        guard let slot = matchManager.draft.slot else { return false }
        return MatchTiming.canRequest(start: slot.startTime)
    }

    private var isLastMinute: Bool {
        guard let slot = matchManager.draft.slot else { return false }
        return MatchTiming.isLastMinute(start: slot.startTime)
    }

    /// 只在来不及的时候出一句
    private var timingError: String? {
        guard let slot = matchManager.draft.slot, slot.endTime > Date(), !canRequest else { return nil }
        return String(localized: "离开赛不到 30 分钟，来不及凑人了，换个时间试试")
    }

    private var confirmPoints: [String] {
        var points = [
            String(localized: "打开后，条件合适就替你接受，其他人确认后就约成，不用再点一次。"),
            String(localized: "所有人都确认才成局，谁没确认不会告诉其他人。")
        ]
        if let slot = matchManager.draft.slot, !isLastMinute {
            let lock = MatchTiming.lock(start: slot.startTime, lastMinute: false)
            points.append(String(localized: "最晚 \(DateText.relativeDay(lock)) \(DateText.time(lock))（开赛前 2 小时）前确认完，否则自动取消，不计入记录。"))
        }
        return points
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Button {
                start()
            } label: {
                VStack(spacing: 2) {
                    if matchManager.draft.replacingTicketId != nil {
                        Label("保存修改", systemImage: "checkmark")
                    } else {
                        Label("开始匹配", systemImage: "bolt.fill")
                    }
                    if let estimate = estimatedCostText {
                        Text(estimate)
                            .font(AppTheme.Typography.caption.weight(.bold))
                            .monospacedDigit()
                            .opacity(0.75)
                    }
                }
            }
            .buttonStyle(.brutalPrimary)
            .disabled(!matchManager.draft.canSearch || !canRequest)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    /// 所选球馆中最便宜的预计 AA：“约 $12/人”；都不知道价格时“费用待定”
    private var estimatedCostText: String? {
        guard let slot = matchManager.draft.slot, slot.isValidDuration else { return nil }
        let courts = locationManager.courts(ids: matchManager.draft.courtIds)
        guard !courts.isEmpty else { return nil }
        let estimates = courts.map { CostSplit.estimate(court: $0, slot: slot.trimmedForGame(), mode: matchManager.draft.mode) }
        guard let cheapest = estimates.filter({ $0.perPerson != nil }).min(by: { $0.perPerson! < $1.perPerson! }) else {
            return String(localized: "费用待定")
        }
        return String(localized: "约 \(cheapest.perPersonText)")
    }

    private func start() {
        guard let user = appState.currentUser else { return }
        router.isMatchSetupPresented = false
        let coordinate = locationManager.coordinate
        let courts = locationManager.courts(ids: matchManager.draft.courtIds)
        let radius = locationManager.preferences.travelRadiusKm
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            matchManager.startSearch(user: user, location: coordinate, courts: courts, radiusKm: radius)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 时间步进器（30 分钟一档）

struct TimeStepper: View {
    let title: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            HStack(spacing: 0) {
                stepButton("minus", delta: -30)
                // 点时间直接从列表里选，加减按钮微调
                Menu {
                    ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 30)), id: \.self) { option in
                        Button {
                            Haptics.selection()
                            minutes = option
                        } label: {
                            if option == minutes { Label(Self.text(option), systemImage: "checkmark") } else { Text(Self.text(option)) }
                        }
                    }
                } label: {
                    Text(Self.text(minutes))
                        .scaledFont(size: 22, relativeTo: .title3)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .minimumScaleFactor(0.7)
                        .contentShape(Rectangle())
                }
                stepButton("plus", delta: 30)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)时间")
        .accessibilityValue(String(localized: "\(minutes / 60) 点 \(String(format: "%02d", minutes % 60)) 分"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(30)
            case .decrement: adjust(-30)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ icon: String, delta: Int) -> some View {
        Button {
            adjust(delta)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(AppTheme.Colors.ink)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .disabled(!range.contains(minutes + delta))
    }

    private static func text(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func adjust(_ delta: Int) {
        let next = minutes + delta
        guard range.contains(next) else { return }
        Haptics.selection()
        minutes = next
    }
}
