import SwiftUI

// MARK: - 比赛 · 新建
// “+”菜单的“比赛 · 循环赛、淘汰赛”，或者当晚页的“用今晚的名单开一场”（到场的人预先填好，用报名 id）。
// 一屏往下填：名字、球馆、场地数、参赛的人、单打还是双打、赛制、打几轮、每局几分；底部是预计几轮几分钟和“开始”

/// 参赛的一个人：球友、当晚的报名，或者输的名字（访客）
struct MatchEntry: Identifiable, Equatable {
    let id: String
    let name: String
    var userId: String?
    var signupId: String?
    var guest = false

    /// create_match 的 p_players 里的一项
    var payload: [String: Any] {
        if let signupId { return ["signup_id": signupId] }
        if let userId { return ["user_id": userId] }
        return ["name": name]
    }
}

struct MatchCreateView: View {
    var sessionId: String?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var name = ""
    @State private var venueId: String?
    @State private var showsVenuePicker = false
    @State private var courts = 2
    @State private var entries: [MatchEntry] = []
    @State private var play: MatchPlay = .rotating
    @State private var chosenFormat: MatchFormat = .roundRobin
    @State private var pools = 2
    @State private var advance = 1
    @State private var thirdPlace = false
    @State private var points = 21
    @State private var bestOf = 1
    @State private var winByTwo = true
    /// 打几轮（没选过 = 默认）
    @State private var chosenRounds: Int?
    @State private var preview: MatchPreview?
    @State private var showsPicker = false
    @State private var showsNameEntry = false
    @State private var typedName = ""
    @State private var saving = false
    @State private var didSetup = false

    /// 默认的名字：“11月18日 比赛”
    private var defaultName: String {
        String(localized: "\(Date().formatted(.dateTime.month().day())) 比赛")
    }

    private var venueName: String? { venueId.flatMap { locationManager.court(id: $0)?.name } }

    /// 轮换搭档只有循环
    private var format: MatchFormat { play == .rotating ? .roundRobin : chosenFormat }

    /// 人数不对时的提示（服务器还会再查一次）
    private var countProblem: String? {
        MatchSetup.countProblem(format: format, play: play, players: entries.count, pools: pools, advance: advance)
    }

    /// 打几轮：没选过用默认，超出能选的收回来
    private var rounds: Int? {
        guard format.byRounds, let preview else { return nil }
        return min(chosenRounds ?? preview.defaultRounds, preview.maxRounds)
    }

    private var previewKey: String {
        "\(format.rawValue)-\(play.rawValue)-\(entries.count)-\(courts)-\(points)-\(bestOf)-\(pools)-\(advance)-\(chosenRounds ?? 0)-\(thirdPlace)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "比赛"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    basics
                    playersSection
                    formatSection
                    pointsSection
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            bottomBar
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear(perform: setup)
        .task(id: previewKey) {
            guard countProblem == nil else {
                preview = nil
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            preview = try? await appState.backend.remoteMatchPreview(
                format: format, play: play, players: entries.count, courts: courts, points: points, bestOf: bestOf,
                pools: format == .groups ? pools : nil, advance: format == .groups ? advance : nil,
                rounds: format.byRounds ? chosenRounds : nil, thirdPlace: format.hasKnockout && thirdPlace)
        }
        .sheet(isPresented: $showsVenuePicker) {
            CourtPickerSheet(selectedId: $venueId, slot: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsPicker) {
            MatchPlayerPicker(candidates: candidates, selectedIds: Set(entries.compactMap(\.userId))) { user in
                toggle(user)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("输入名字", isPresented: $showsNameEntry) {
            TextField("名字", text: $typedName)
            Button("加") { addTyped() }
            Button("取消", role: .cancel) { typedName = "" }
        }
    }

    // MARK: 名字、球馆、场地

    private var basics: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text("名字")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(width: 56, alignment: .leading)
                TextField(defaultName, text: $name)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 52)
            InsetDivider()
            Button {
                showsVenuePicker = true
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("球馆")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .frame(width: 56, alignment: .leading)
                    Text(verbatim: venueName ?? String(localized: "选填"))
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(venueName == nil ? AppTheme.Colors.inkTertiary : AppTheme.Colors.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            InsetDivider()
            CourtStepper(courts: $courts)
                .padding(.leading, AppTheme.Spacing.lg)
                .padding(.trailing, AppTheme.Spacing.xs)
        }
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
    }

    // MARK: 参赛的人

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("参赛的人")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("\(entries.count) 人")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer(minLength: 0)
            }
            if !entries.isEmpty {
                FlowLayout(spacing: AppTheme.Spacing.sm) {
                    ForEach(entries) { entry in
                        Button {
                            entries.removeAll { $0.id == entry.id }
                        } label: {
                            entryChip(entry)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(String(localized: "移除\(entry.name)"))
                    }
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    showsPicker = true
                } label: {
                    Label("选球友", systemImage: "person.badge.plus")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                Button {
                    showsNameEntry = true
                } label: {
                    Label("输入名字", systemImage: "character.cursor.ibeam")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
            }
        }
    }

    private func entryChip(_ entry: MatchEntry) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: String(entry.name.prefix(1)).uppercased())
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.onAccent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(chipColor(entry)))
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.hairline))
            Text(verbatim: entry.name)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.ink)
                .lineLimit(1)
            if entry.guest {
                TagPill(text: String(localized: "访客"), fill: AppTheme.Colors.mint)
            }
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(Capsule().fill(AppTheme.Colors.surface))
        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.hairline))
    }

    /// 访客灰色，其余按名字取一个贴纸色
    private func chipColor(_ entry: MatchEntry) -> Color {
        if entry.guest { return AppTheme.Colors.surfaceMuted }
        let seed = entry.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return AppTheme.Colors.paletteColor(seed)
    }

    // MARK: 赛制

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("赛制")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(MatchPlay.allCases) { option in
                    choiceButton(option.title, selected: option == play) {
                        play = option
                        chosenRounds = nil
                    }
                }
            }
            if play != .rotating {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.sm), GridItem(.flexible(), spacing: AppTheme.Spacing.sm)],
                          spacing: AppTheme.Spacing.sm) {
                    ForEach(MatchFormat.allCases) { option in
                        choiceButton(option.title, selected: option == format) {
                            chosenFormat = option
                            chosenRounds = nil
                        }
                    }
                }
            }
            options
        }
    }

    /// 赛制下面的设置：分几组、每组前几名、打几轮、三四名
    @ViewBuilder
    private var options: some View {
        if format.hasKnockout || rounds != nil {
            VStack(spacing: 0) {
                if format == .groups {
                    stepperRow(String(localized: "几组"), value: pools, range: 2...8) { pools = $0 }
                    InsetDivider()
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text("每组前几名出线")
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Spacer(minLength: 0)
                        ChoiceChip(title: "1", isSelected: advance == 1) { advance = 1 }
                        ChoiceChip(title: "2", isSelected: advance == 2) { advance = 2 }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(minHeight: 56)
                }
                if let rounds, let preview {
                    stepperRow(String(localized: "打几轮"), value: rounds, range: 1...max(1, preview.maxRounds)) { chosenRounds = $0 }
                    if format == .roundRobin && play != .rotating && preview.fullRounds > 0 {
                        Text("循环打满一遍是 \(preview.fullRounds) 轮。")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .padding(.bottom, AppTheme.Spacing.md)
                    }
                }
                if format.hasKnockout {
                    if format == .groups { InsetDivider() }
                    toggleRow(String(localized: "打三四名"), isOn: $thirdPlace)
                }
            }
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
        }
    }

    private func stepperRow(_ title: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: { onChange(min(max($0, range.lowerBound), range.upperBound)) }), in: range) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(verbatim: title)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer(minLength: 0)
                Text(verbatim: "\(value)")
                    .font(AppTheme.Typography.bodyBold)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.ink)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: 56)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(verbatim: title)
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(AppTheme.Colors.ink)
        }
        .tint(AppTheme.Colors.success)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: 56)
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            Haptics.selection()
            action()
        } label: {
            Text(verbatim: title)
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(selected ? AppTheme.Colors.onInverse : AppTheme.Colors.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(shape.fill(selected ? AppTheme.Colors.inverse : AppTheme.Colors.surface))
                .overlay(shape.strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: 每局几分

    private var pointsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("每局")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: AppTheme.Spacing.sm) {
                SegmentedSticker(options: [21, 15, 11], selection: $points, title: { "\($0)" })
                    .frame(maxWidth: 180)
                SegmentedSticker(options: [1, 3], selection: $bestOf,
                                 title: { $0 == 1 ? String(localized: "一局") : String(localized: "三局两胜") })
            }
            Toggle(isOn: $winByTwo) {
                Text("领先 2 分")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            .tint(AppTheme.Colors.success)
            .frame(minHeight: 44)
        }
    }

    // MARK: 底部：预计、开始

    private var bottomBar: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let preview {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Label(String(localized: "预计 \(preview.rounds) 轮，约 \(Int(preview.minutes)) 分钟"), systemImage: "clock")
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Spacer(minLength: 0)
                }
            }
            if let problem = countProblem, !entries.isEmpty {
                Text(verbatim: problem)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("开始") { create() }
                .buttonStyle(.brutalPrimary)
                .disabled(saving || countProblem != nil)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    // MARK: 数据

    /// 能选的人：自己、球友、球群里的人
    private var candidates: [User] {
        var seen = Set<String>()
        var list: [User] = []
        if let me = appState.currentUser {
            seen.insert(me.id)
            list.append(me)
        }
        for user in friendManager.friends {
            if seen.insert(user.id).inserted { list.append(user) }
        }
        for group in groupManager.myGroups {
            for id in group.memberIds {
                if let user = groupManager.user(id), seen.insert(id).inserted { list.append(user) }
            }
        }
        return list
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let sessionId {
            // 从当晚开：到场的人预先填好（用报名 id），场地数也一样
            Task {
                guard let night = try? await appState.backend.remoteNightState(sessionId) else { return }
                courts = night.courts
                entries = night.people.filter { $0.status == "here" }.map { person in
                    MatchEntry(id: person.id, name: person.name, userId: person.userId, signupId: person.id, guest: person.guest)
                }
            }
        } else if let me = appState.currentUser {
            entries = [MatchEntry(id: me.id, name: me.nickname, userId: me.id)]
        }
    }

    private func toggle(_ user: User) {
        if let index = entries.firstIndex(where: { $0.userId == user.id }) {
            entries.remove(at: index)
        } else if entries.count < 64 {
            entries.append(MatchEntry(id: user.id, name: user.nickname, userId: user.id))
        }
    }

    private func addTyped() {
        let clean = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        typedName = ""
        guard !clean.isEmpty, entries.count < 64 else { return }
        entries.append(MatchEntry(id: UUID().uuidString, name: String(clean.prefix(24)), guest: true))
    }

    private func create() {
        saving = true
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { saving = false }
            do {
                let id = try await appState.backend.remoteCreateMatch(
                    name: title.isEmpty ? defaultName : title, venueId: venueId, courts: courts, format: format, play: play,
                    points: points, bestOf: bestOf, winByTwo: winByTwo, players: entries.map(\.payload),
                    rounds: rounds, pools: format == .groups ? pools : nil,
                    advance: format == .groups ? advance : nil, thirdPlace: format.hasKnockout && thirdPlace, sessionId: sessionId)
                Haptics.success()
                router.pop()
                // 从当晚开的：回到当晚页的“比赛”
                if sessionId == nil { router.open(.match(id: id)) }
            } catch RemoteError.server(let code) where code == "invalid_player_count" {
                appState.showToast(countProblem ?? String(localized: "要 2–64 人。"), style: .error)
            } catch {
                appState.showClubError(error)
            }
        }
    }
}

// MARK: - 选球友

private struct MatchPlayerPicker: View {
    let candidates: [User]
    let selectedIds: Set<String>
    let onToggle: (User) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选球友")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)
            ScrollView {
                VStack(spacing: 0) {
                    if candidates.isEmpty {
                        Text("还没有球友。可以输入名字。")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .padding(.top, AppTheme.Spacing.xl)
                    }
                    ForEach(candidates) { user in
                        Button {
                            Haptics.selection()
                            onToggle(user)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                AvatarView(user: user, size: 40)
                                Text(verbatim: user.nickname)
                                    .font(AppTheme.Typography.bodyBold)
                                    .foregroundStyle(AppTheme.Colors.ink)
                                Spacer(minLength: 0)
                                Image(systemName: selectedIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(selectedIds.contains(user.id) ? AppTheme.Colors.success : AppTheme.Colors.inkTertiary)
                            }
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedIds.contains(user.id) ? [.isSelected, .isButton] : .isButton)
                        InsetDivider()
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
