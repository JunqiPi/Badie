import SwiftUI

/// 快速匹配设置：模式 · 日期 · 时间段 · 球馆（最多 3 个）· 水平差
struct MatchSetupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var recurring: [RecurringTimeSlot] = []

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<TimeSlotConstants.maximumDaysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var userLevel: Int { appState.currentUser?.displayLevel ?? 4 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("快速匹配")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") {
                    router.isMatchSetupPresented = false
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    modeSection
                        .padding(.horizontal, AppTheme.Spacing.screen)
                    dateSection
                    timeSection
                        .padding(.horizontal, AppTheme.Spacing.screen)
                    courtsSection
                        .padding(.horizontal, AppTheme.Spacing.screen)
                    skillSection
                        .padding(.horizontal, AppTheme.Spacing.screen)
                }
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            footer
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            recurring = appState.backend.recurringSlots()
            matchManager.prepareDraft(user: appState.currentUser, nearbyCourts: locationManager.nearbyCourts,
                                      recurring: recurring, favorites: locationManager.favoriteCourtIds)
        }
    }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            label("模式")
            HStack(spacing: AppTheme.Spacing.md) {
                ForEach(GameMode.allCases) { mode in
                    let selected = matchManager.draft.mode == mode
                    Button {
                        Haptics.selection()
                        withAnimation(AppTheme.Motion.standard) { matchManager.draft.mode = mode }
                    } label: {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 22, weight: .bold))
                            Text(mode.title)
                                .font(AppTheme.Typography.title3)
                            Text(mode.versusText)
                                .font(AppTheme.Typography.footnoteBold)
                                .opacity(0.7)
                        }
                        .foregroundStyle(selected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.lg)
                        .sticker(selected ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.lg,
                                 shadow: selected ? AppTheme.Elevation.card : .zero)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    // MARK: Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            label("日期（未来 14 天）")
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
            label("时间段（1–8 小时）")
            HStack(spacing: AppTheme.Spacing.md) {
                TimeStepper(title: "开始", minutes: $matchManager.draft.startMinutes, range: (6 * 60)...(23 * 60))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                TimeStepper(title: "结束", minutes: $matchManager.draft.endMinutes, range: (7 * 60)...(24 * 60))
            }
            if let message = matchManager.draft.validation.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            } else if let slot = matchManager.draft.slot {
                Text("共 \(slot.formattedDuration)，匹配时至少需要与对方重叠 30 分钟")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(presets, id: \.0) { preset in
                        ChoiceChip(title: preset.0, isSelected: matchManager.draft.startMinutes == preset.1 && matchManager.draft.endMinutes == preset.2,
                                   tint: AppTheme.Colors.peach) {
                            matchManager.draft.startMinutes = preset.1
                            matchManager.draft.endMinutes = preset.2
                        }
                    }
                    ForEach(recurring.activeSlots) { slot in
                        ChoiceChip(title: "常用 · \(slot.displayText)", icon: "star.fill", isSelected: false, tint: AppTheme.Colors.butter) {
                            if let next = slot.nextOccurrence() { matchManager.draft.apply(next) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var presets: [(String, Int, Int)] {
        [("早场 7–9", 7 * 60, 9 * 60), ("午间 12–14", 12 * 60, 14 * 60), ("下午 14–17", 14 * 60, 17 * 60),
         ("晚上 19–21", 19 * 60, 21 * 60), ("夜场 21–23", 21 * 60, 23 * 60)]
    }

    // MARK: Courts

    private var courtsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                label("球馆（最多 \(MatchDraft.maxCourts) 个）")
                Spacer()
                Text("\(matchManager.draft.courtIds.count)/\(MatchDraft.maxCourts)")
                    .font(AppTheme.Typography.footnoteBold)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            if locationManager.nearbyCourts.isEmpty {
                NoticeBanner(icon: "mappin.slash", text: "出行范围内没有球馆，试试在“我的-出行范围”调大半径")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(locationManager.nearbyCourts.prefix(8).enumerated()), id: \.element.id) { index, court in
                        if index > 0 { InsetDivider() }
                        CourtSelectRow(
                            court: court,
                            distance: court.formattedDistance(from: locationManager.coordinate),
                            isSelected: matchManager.draft.courtIds.contains(court.id),
                            isOpen: matchManager.draft.slot.map { court.operatingHours.covers($0) } ?? true
                        ) {
                            if !matchManager.draft.toggleCourt(court.id) {
                                appState.showToast("最多选择 \(MatchDraft.maxCourts) 个球馆")
                            } else {
                                Haptics.selection()
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
        }
    }

    // MARK: Skill tolerance

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            label("可接受的水平差")
            HStack(spacing: AppTheme.Spacing.sm) {
                ChoiceChip(title: "±1 级", isSelected: matchManager.draft.skillTolerance == 1) { matchManager.draft.skillTolerance = 1 }
                ChoiceChip(title: "±2 级", isSelected: matchManager.draft.skillTolerance == 2) { matchManager.draft.skillTolerance = 2 }
                ChoiceChip(title: "不限", isSelected: matchManager.draft.skillTolerance >= MatchRequest.anySkill) {
                    matchManager.draft.skillTolerance = MatchRequest.anySkill
                }
            }
            Text(toleranceExplanation)
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
    }

    private var toleranceExplanation: String {
        let tolerance = matchManager.draft.skillTolerance
        guard tolerance < MatchRequest.anySkill else { return "你的等级 Lv.\(userLevel)，将匹配所有水平的球友" }
        let low = max(1, userLevel - tolerance)
        let high = min(9, userLevel + tolerance)
        return "你的等级 Lv.\(userLevel)，将匹配 Lv.\(low)–\(high) 的球友，水平越接近排得越前"
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let estimate = estimatedCost {
                Text("预计 AA 约 ¥\(estimate)/人 · 平台不收服务费")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            Button {
                start()
            } label: {
                Label("开始匹配", systemImage: "bolt.fill")
            }
            .buttonStyle(.brutalPrimary)
            .disabled(!matchManager.draft.canSearch)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    private var estimatedCost: Int? {
        guard let slot = matchManager.draft.slot, slot.isValidDuration else { return nil }
        let courts = locationManager.courts.filter { matchManager.draft.courtIds.contains($0.id) }
        guard let cheapest = courts.min(by: { $0.pricePerHour < $1.pricePerHour }) else { return nil }
        return CostSplit.estimate(court: cheapest, slot: slot.trimmedForGame(), mode: matchManager.draft.mode).perPerson
    }

    private func start() {
        guard let user = appState.currentUser else { return }
        router.isMatchSetupPresented = false
        let coordinate = locationManager.coordinate
        let courts = locationManager.courts
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
                Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    .scaledFont(size: 22, relativeTo: .title3)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.7)
                stepButton("plus", delta: 30)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)时间")
        .accessibilityValue(String(format: "%d 点 %02d 分", minutes / 60, minutes % 60))
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

    private func adjust(_ delta: Int) {
        let next = minutes + delta
        guard range.contains(next) else { return }
        Haptics.selection()
        minutes = next
    }
}

// MARK: - 球馆选择行

struct CourtSelectRow: View {
    let court: BadmintonCourt
    let distance: String
    let isSelected: Bool
    var isOpen = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(court.name)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(distance)
                        Text("·")
                        Text("¥\(court.pricePerHour)/时\(court.isEstimatedInfo ? "（估）" : "")")
                        if !isOpen {
                            Text("· 该时段未营业")
                                .foregroundStyle(AppTheme.Colors.danger)
                        }
                    }
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
