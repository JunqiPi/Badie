import SwiftUI

/// 发起球局：私密房间（凭房间码/邀请）或公开招募（附近球友可见，支持候补）
struct CreateRoomView: View {
    var initialMode: GameMode?
    var inviteeId: String?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var friendManager: FriendManager

    @State private var mode: GameMode = .doubles
    @State private var visibility: RoomVisibility = .privateRoom
    @State private var hasSchedule = true
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var startMinutes = 19 * 60
    @State private var endMinutes = 21 * 60
    @State private var courtId: String?
    @State private var lowerLevel = 1
    @State private var upperLevel = 9
    @State private var tags: Set<RoomTag> = []
    @State private var note = ""
    @State private var showCourtPicker = false
    @State private var isWorking = false
    @State private var didSetup = false

    private var slot: TimeSlot? {
        guard hasSchedule || visibility == .publicListing else { return nil }
        return TimeSlot.on(day, startHour: startMinutes / 60, startMinute: startMinutes % 60,
                           endHour: endMinutes / 60, endMinute: endMinutes % 60)
    }

    private var court: BadmintonCourt? { courtId.flatMap { locationManager.court(id: $0) } }

    private var validationMessage: String? {
        if visibility == .publicListing || hasSchedule {
            if let message = slot?.validate().errorMessage { return message }
        }
        if visibility == .publicListing && court == nil { return "公开球局需要选择球馆" }
        return nil
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<TimeSlotConstants.maximumDaysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "发起球局")
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    group("模式") {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(GameMode.allCases) { option in
                                ChoiceChip(title: "\(option.title) \(option.versusText)", icon: option.icon, isSelected: mode == option) {
                                    mode = option
                                }
                            }
                        }
                    }
                    group("招募方式") {
                        SegmentedSticker(options: [RoomVisibility.privateRoom, .publicListing], selection: $visibility) {
                            $0 == .privateRoom ? "仅邀请（私密）" : "公开到附近"
                        }
                        Text(visibility == .privateRoom
                             ? "生成 6 位房间码，分享给好友加入；30 分钟无活动自动关闭。"
                             : "附近符合水平的球友都能看到并报名，满员后可候补，有人退出自动递补。")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    scheduleGroup
                    courtGroup
                    if visibility == .publicListing {
                        levelGroup
                        tagsGroup
                    }
                    group("备注（可选）") {
                        BrutalTextField(label: "给球友的话", placeholder: "例：已订 2 小时，打完 AA；自带球", text: $note,
                                        characterLimit: 80, axis: .vertical)
                    }
                    if let cost = costPreview {
                        InfoRow(icon: Money.icon(for: cost.currencyCode), tint: AppTheme.Colors.butter,
                                title: cost.perPerson == nil ? "费用待定" : "预计 AA \(cost.perPersonText)", subtitle: cost.breakdownText)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            footer
        }
        .sheet(isPresented: $showCourtPicker) {
            CourtPickerSheet(selectedId: $courtId, slot: slot)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: setup)
    }

    // MARK: Groups

    private var scheduleGroup: some View {
        group("时间") {
            if visibility == .privateRoom {
                Toggle(isOn: $hasSchedule.animation(AppTheme.Motion.standard)) {
                    Text("现在就定时间")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                }
                .tint(AppTheme.Colors.success)
            }
            if hasSchedule || visibility == .publicListing {
                DateStrip(days: days, selection: $day)
                    .padding(.horizontal, -AppTheme.Spacing.screen)
                HStack(spacing: AppTheme.Spacing.md) {
                    TimeStepper(title: "开始", minutes: $startMinutes, range: (6 * 60)...(23 * 60))
                    TimeStepper(title: "结束", minutes: $endMinutes, range: (7 * 60)...(24 * 60))
                }
                if let message = slot?.validate().errorMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            } else {
                Text("建好房间后，房主可以在房间里再设置时间和球馆。")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
        }
    }

    private var courtGroup: some View {
        group(visibility == .publicListing ? "球馆" : "球馆（可选）") {
            Button {
                showCourtPicker = true
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    IconTile(systemName: "sportscourt.fill", fill: AppTheme.Colors.sky, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(court?.name ?? "选择球馆")
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        if let court {
                            Text(court.address)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(court.formattedDistance(from: locationManager.coordinate)) · \(court.pricingText)")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.inkTertiary)
                        } else {
                            Text("搜索球馆名、简称或地址")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
                .padding(AppTheme.Spacing.md)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
    }

    private var levelGroup: some View {
        group("接受的水平") {
            HStack(spacing: AppTheme.Spacing.md) {
                LevelStepper(title: "最低", level: $lowerLevel, range: 1...upperLevel)
                LevelStepper(title: "最高", level: $upperLevel, range: lowerLevel...9)
            }
            let myLevel = appState.currentUser?.displayLevel ?? 4
            HStack(spacing: AppTheme.Spacing.sm) {
                ChoiceChip(title: "不限", isSelected: lowerLevel == 1 && upperLevel == 9) {
                    lowerLevel = 1; upperLevel = 9
                }
                ChoiceChip(title: "我的水平 ±1", isSelected: lowerLevel == max(1, myLevel - 1) && upperLevel == min(9, myLevel + 1)) {
                    lowerLevel = max(1, myLevel - 1); upperLevel = min(9, myLevel + 1)
                }
                ChoiceChip(title: "新手 1–3", isSelected: lowerLevel == 1 && upperLevel == 3) {
                    lowerLevel = 1; upperLevel = 3
                }
            }
        }
    }

    private var tagsGroup: some View {
        group("球局氛围") {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(RoomTag.allCases) { tag in
                    ChoiceChip(title: tag.rawValue, icon: tag.icon, isSelected: tags.contains(tag), tint: AppTheme.Colors.mint) {
                        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            if let message = validationMessage {
                Text(message)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            Button {
                Task { await create() }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isWorking { LoadingDots() }
                    Text(visibility == .publicListing ? "发布球局" : "创建房间")
                }
            }
            .buttonStyle(.brutalPrimary)
            .disabled(validationMessage != nil || isWorking)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    private var costPreview: CostSplit? {
        guard let court, let slot, slot.isValidDuration else { return nil }
        return CostSplit.estimate(court: court, slot: slot, mode: mode)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: Actions

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let initialMode { mode = initialMode }
        let suggested = TimeSlot.suggestedDefault()
        let calendar = Calendar.current
        day = calendar.startOfDay(for: suggested.startTime)
        startMinutes = calendar.component(.hour, from: suggested.startTime) * 60 + calendar.component(.minute, from: suggested.startTime)
        endMinutes = min(24 * 60, startMinutes + 120)
        courtId = locationManager.favoriteCourtIds.first { locationManager.court(id: $0) != nil } ?? locationManager.nearbyCourts.first?.id
        if let level = appState.currentUser?.displayLevel {
            lowerLevel = max(1, level - 2)
            upperLevel = min(9, level + 2)
        }
    }

    private func create() async {
        isWorking = true
        defer { isWorking = false }
        let draft = RoomDraft(
            mode: mode,
            visibility: visibility,
            court: court,
            slot: slot,
            levelRange: lowerLevel...upperLevel,
            tags: RoomTag.allCases.filter { tags.contains($0) },
            note: note
        )
        do {
            let room = try await roomManager.create(draft)
            if let inviteeId, friendManager.isFriend(inviteeId) {
                try? await roomManager.invite([inviteeId], to: room)
            }
            Haptics.success()
            router.pop()
            router.open(.room(id: room.id))
        } catch {
            appState.showError(error)
        }
    }
}

// MARK: - 细分档位步进器（1− … 9+）

struct TierStepper: View {
    @Binding var tier: SkillTier
    var range: ClosedRange<SkillTier> = SkillTier(index: 0)...SkillTier(index: SkillTier.count - 1)

    private func step(_ delta: Int) {
        let next = tier.offset(by: delta)
        guard next != tier, range.contains(next) else { return }
        tier = next
        Haptics.selection()
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { step(-1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(width: 40, height: 44)
            }
            .disabled(tier == range.lowerBound)
            VStack(spacing: 0) {
                Text(SkillLevel.name(for: tier.level))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Text(tier.text)
                    .font(AppTheme.Typography.headline)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            Button { step(1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(width: 40, height: 44)
            }
            .disabled(tier == range.upperBound)
        }
        .foregroundStyle(AppTheme.Colors.ink)
        .padding(.vertical, 4)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("水平")
        .accessibilityValue(tier.spokenText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }
}

// MARK: - 等级步进器

struct LevelStepper: View {
    let title: String
    @Binding var level: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if range.contains(level - 1) { level -= 1; Haptics.selection() }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(width: 40, height: 44)
            }
            .disabled(!range.contains(level - 1))
            VStack(spacing: 0) {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Text("Lv.\(level)")
                    .font(AppTheme.Typography.headline)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            Button {
                if range.contains(level + 1) { level += 1; Haptics.selection() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(width: 40, height: 44)
            }
            .disabled(!range.contains(level + 1))
        }
        .foregroundStyle(AppTheme.Colors.ink)
        .padding(.vertical, 4)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)等级")
        .accessibilityValue("\(level) 级")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if range.contains(level + 1) { level += 1 }
            case .decrement: if range.contains(level - 1) { level -= 1 }
            @unknown default: break
            }
        }
    }
}
