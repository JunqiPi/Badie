import SwiftUI

// MARK: - 当晚页：排场 | 比赛 | 收款
// 组织者和帮手从球群页的“排场”进来（帮手没有收款）。数据都在服务器上（night_state），每 10 秒重拉；
// 网差时保留上一份，顶上写“x 分钟前更新”。场边单手用：每片场地一个大的“打完了”

enum NightSegment: Hashable {
    case courts, match, pay

    var title: String {
        switch self {
        case .courts: return String(localized: "排场")
        case .match: return String(localized: "比赛")
        case .pay: return String(localized: "收款")
        }
    }
}

/// 点了场上的某个人：从等候的人里换一个上来
private struct SwapTarget: Identifiable {
    let game: NightState.Game
    let out: String

    var id: String { "\(game.id)-\(out)" }
}

struct NightView: View {
    let sessionId: String
    var opensPay = false

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    @State private var state: NightState?
    @State private var loaded = false
    @State private var loadedAt = Date()
    @State private var segment: NightSegment = .courts
    @State private var pay: NightPay?
    @State private var feeText = ""
    @FocusState private var feeFocused: Bool
    @State private var showsPaid = false
    @State private var showsExempt = false
    /// 撤销条显示到什么时候；服务器给的时间换算成本机时间（两边的钟可能不一样）
    @State private var undoDeadline: Date?
    @State private var lastUndo: Date?
    @State private var personAction: NightState.Person?
    @State private var swapTarget: SwapTarget?
    @State private var showsBoard = false
    @State private var showsAdd = false
    @State private var showsSettings = false

    private var backend: MockBackend { appState.backend }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let state {
                content(state)
            } else if loaded {
                EmptyStateView(icon: "sportscourt", title: String(localized: "只有组织者和帮手能看。"))
                Spacer()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task(id: sessionId) {
            if opensPay { segment = .pay }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .onChange(of: segment) { _, value in
            if value == .pay { Task { await loadPay() } }
        }
        .confirmationDialog(personAction?.name ?? "", isPresented: Binding(get: { personAction != nil }, set: { if !$0 { personAction = nil } }),
                            titleVisibility: .visible, presenting: personAction) { person in
            if person.status == "here" {
                Button("放到下一场") { perform { try await backend.remoteNightBump(person.id, next: true) } }
                Button("跳过") { perform { try await backend.remoteNightBump(person.id, next: false) } }
                Button("休息") { mark([person.id], "resting") }
            } else {
                Button("到了") { mark([person.id], "here") }
            }
            Button("走了", role: .destructive) { mark([person.id], "left") }
        }
        .sheet(item: $swapTarget) { target in
            if let state {
                NightSwapSheet(state: state, target: target) { replacement in
                    perform {
                        try await backend.remoteNightSwap(game: target.game.id, out: target.out, in: replacement)
                        undoDeadline = Date().addingTimeInterval(10)
                    }
                } onMark: { status in
                    mark([target.out], status)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsBoard) {
            if let code = state?.boardCode, let url = PayLinks.board(code) {
                BoardQRSheet(url: url)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsAdd) {
            if let state {
                NightAddSheet(state: state) { name in
                    perform {
                        try await backend.remoteNightAdd(sessionId, name: name)
                        appState.showToast(String(localized: "已加上 \(name)"), style: .success)
                    }
                } onArrive: { person in
                    mark([person.id], "here")
                    appState.showToast(String(localized: "\(person.name) 到了"), style: .success)
                }
                .showsToasts()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsSettings) {
            if let state {
                NightSettingsSheet(state: state, me: appState.currentUser?.id) { courts, doubles, balance, helpers in
                    perform {
                        try await backend.remoteNightSettings(sessionId, courts: courts, doubles: doubles, balance: balance)
                        if let helpers, Set(helpers) != Set(state.helpers.map(\.id)) {
                            try await backend.remoteNightHelpers(sessionId, users: helpers)
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("当晚")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                if let state {
                    Text(verbatim: subtitle(state))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 56)
            HStack {
                IconButton(systemName: "chevron.left", accessibilityLabel: String(localized: "返回")) { dismiss() }
                Spacer()
                if let state, state.open {
                    IconButton(systemName: "slider.horizontal.3", accessibilityLabel: String(localized: "排场设置")) { showsSettings = true }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    private func subtitle(_ state: NightState) -> String {
        let range = "\(DateText.time(state.startsAt))–\(DateText.time(state.endsAt))"
        return String(localized: "\(range) · 到了 \(state.hereCount) 人")
    }

    private func segments(_ state: NightState) -> [NightSegment] {
        state.isOrganizer ? [.courts, .match, .pay] : [.courts, .match]
    }

    @ViewBuilder
    private func content(_ state: NightState) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SegmentedSticker(options: segments(state), selection: $segment, title: { $0.title })
            staleLine
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                switch segment {
                case .courts: courtsSection(state)
                case .match: matchSection(state)
                case .pay: paySection(state)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        if segment == .courts {
            undoBar
        }
        bottomBar(state)
    }

    /// 网差时：上一份是几分钟前的（超过 1 分钟变成提示色）
    private var staleLine: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let age = context.date.timeIntervalSince(loadedAt)
            if loaded && age > 25 {
                Text("\(max(1, Int(age / 60))) 分钟前更新")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(age > 60 ? AppTheme.Colors.danger : AppTheme.Colors.inkSecondary)
            }
        }
    }

    // MARK: 排场

    @ViewBuilder
    private func courtsSection(_ state: NightState) -> some View {
        if !state.open {
            notice(String(localized: "不在当晚的时间里。"))
        }
        if state.matchLive {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("比赛在打，排场先停。")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Button("看比赛") { segment = .match }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
            }
            .card(shadow: .zero)
        } else if state.started {
            ForEach(state.courtNumbers, id: \.self) { court in
                courtCard(state, court: court)
            }
            nextSection(state)
            waitingSection(state)
        } else {
            setupSection(state)
            rosterSection(state)
        }
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "clock")
            .font(AppTheme.Typography.subheadlineBold)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
    }

    private func courtCard(_ state: NightState, court: Int) -> some View {
        let game = state.games.first { $0.court == court }
        return HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    CourtTag(court: court)
                    if let game {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("\(max(0, Int(context.date.timeIntervalSince(game.startedAt) / 60))) 分钟")
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                    }
                }
                if let game {
                    let sides = state.sides(game.players)
                    sideLine(state, game: game, ids: sides.a)
                    sideLine(state, game: game, ids: sides.b)
                } else {
                    Text("等人")
                        .font(AppTheme.Typography.title3)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
            }
            Spacer(minLength: 0)
            if let game, state.open {
                Button("打完了") { finish(game) }
                    .buttonStyle(BigActionButtonStyle())
            }
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: game == nil ? .zero : AppTheme.Elevation.card)
    }

    /// 一队的名字：点名字换人
    private func sideLine(_ state: NightState, game: NightState.Game, ids: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                if index > 0 {
                    Text(verbatim: "·")
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
                Button(state.name(id)) { swapTarget = SwapTarget(game: game, out: id) }
                    .buttonStyle(.plain)
                    .disabled(!state.open)
            }
        }
        .font(.system(.title3, design: .rounded, weight: .heavy))
        .foregroundStyle(AppTheme.Colors.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func nextSection(_ state: NightState) -> some View {
        if !state.next.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("接下来")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                ForEach(Array(state.next.enumerated()), id: \.offset) { _, players in
                    let sides = state.sides(players)
                    MatchupLine(a: sides.a.map { state.name($0) }, b: sides.b.map { state.name($0) })
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
        }
    }

    @ViewBuilder
    private func waitingSection(_ state: NightState) -> some View {
        let waiting = state.waiting
        let resting = state.people.filter { $0.status == "resting" }
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("等候 · 今晚打了几场")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            if waiting.isEmpty && resting.isEmpty {
                Text("没人在等")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(waiting) { person in
                    Button { personAction = person } label: {
                        NameChip(name: person.name, count: person.games, note: person.nextUp ? String(localized: "下一场") : nil)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!state.open)
                }
                ForEach(resting) { person in
                    Button { personAction = person } label: {
                        NameChip(name: person.name, note: String(localized: "休息"), fill: AppTheme.Colors.surfaceMuted, dimmed: true)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!state.open)
                }
            }
        }
    }

    // MARK: 开始前：设置和点名

    private func setupSection(_ state: NightState) -> some View {
        VStack(spacing: 0) {
            CourtStepper(courts: Binding(get: { state.courts }, set: { settings(state, courts: $0) }))
                .padding(.leading, AppTheme.Spacing.lg)
                .padding(.trailing, AppTheme.Spacing.xs)
            InsetDivider()
            SegmentedSticker(options: [false, true], selection: Binding(get: { state.doubles }, set: { settings(state, doubles: $0) }),
                             title: { $0 ? String(localized: "双打") : String(localized: "单打") })
                .padding(AppTheme.Spacing.md)
            InsetDivider()
            Toggle(isOn: Binding(get: { state.balance }, set: { settings(state, balance: $0) })) {
                Text("按实力分队")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            .tint(AppTheme.Colors.success)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 56)
        }
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
        .disabled(!state.open)
    }

    private func rosterSection(_ state: NightState) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("名单")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("到了 \(state.hereCount)/\(state.people.count)")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer(minLength: 0)
                if state.open {
                    Button("全到了") { mark(nil, "here") }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                }
            }
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(state.people) { person in
                    rosterChip(person)
                        .disabled(!state.open)
                }
            }
            Text("点一下标到了，按住有更多选项。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
    }

    /// 点一下：到了 ↔ 没到；按住：到了 / 休息 / 走了 / 没到
    private func rosterChip(_ person: NightState.Person) -> some View {
        Menu {
            Button("到了") { mark([person.id], "here") }
            Button("休息") { mark([person.id], "resting") }
            Button("走了") { mark([person.id], "left") }
            Button("没到") { mark([person.id], nil) }
        } label: {
            NameChip(name: person.name, note: statusNote(person), fill: statusFill(person.status),
                     dimmed: person.status == "absent" || person.status == "left")
        } primaryAction: {
            mark([person.id], person.status == "here" ? nil : "here")
        }
        .accessibilityLabel(Text(verbatim: "\(person.name) \(statusNote(person))"))
    }

    private func statusNote(_ person: NightState.Person) -> String {
        switch person.status {
        case "here": return String(localized: "到了")
        case "resting": return String(localized: "休息")
        case "left": return String(localized: "走了")
        default: return person.waitlisted ? String(localized: "候补") : String(localized: "没到")
        }
    }

    private func statusFill(_ status: String) -> Color {
        switch status {
        case "here": return AppTheme.Colors.mint
        case "resting": return AppTheme.Colors.butter
        case "left": return AppTheme.Colors.surfaceMuted
        default: return AppTheme.Colors.surface
        }
    }

    // MARK: 比赛

    @ViewBuilder
    private func matchSection(_ state: NightState) -> some View {
        if let matchId = state.matchId {
            if !state.matchLive && state.open {
                Button("回到排场") {
                    perform {
                        try await backend.remoteNightResume(sessionId)
                        segment = .courts
                    }
                }
                .buttonStyle(.brutalPrimary)
            }
            MatchPanel(matchId: matchId, embedded: true)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("用到场的人打一轮比赛，排场先停。")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Button("用今晚的名单开一场") { router.open(.createMatch(sessionId: sessionId)) }
                    .buttonStyle(.brutalPrimary)
                    .disabled(!state.open)
            }
        }
    }

    // MARK: 收款（只有组织者）

    @ViewBuilder
    private func paySection(_ state: NightState) -> some View {
        if let pay {
            feeRow(pay)
            summaryCard(pay)
            if pay.hasHandles == false && pay.payeeIsMe != false {
                MenuRow(icon: "dollarsign.circle.fill", tint: AppTheme.Colors.butter, title: String(localized: "填收款方式")) {
                    router.open(.paymentHandles)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
            unpaidList(pay)
            collapsible(String(localized: "已付 \(pay.paid.count)"), isOpen: $showsPaid, people: pay.paid) { person in
                paidRow(person)
            }
            if !pay.exempt.isEmpty {
                collapsible(String(localized: "不用付 \(pay.exempt.count)"), isOpen: $showsExempt, people: pay.exempt) { person in
                    exemptRow(person)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.xxl)
        }
    }

    private func feeRow(_ pay: NightPay) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("每人")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            HStack(spacing: 2) {
                Text(verbatim: "$")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                TextField("", text: $feeText)
                    .keyboardType(.decimalPad)
                    .focused($feeFocused)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(width: 130, height: 52)
            .sticker(AppTheme.Colors.surface, radius: 14, shadow: .zero)
            Spacer(minLength: 0)
            Button("保存") { saveFee() }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                .disabled(feeText == (pay.amount.map(FeeText.plain) ?? ""))
        }
    }

    private func summaryCard(_ pay: NightPay) -> some View {
        let paidCount = pay.owing.filter(\.paid).count
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("已付")
                .font(AppTheme.Typography.footnoteBold)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(paidCount)")
                    .scaledFont(size: 40, relativeTo: .title)
                Text(verbatim: "/\(pay.owing.count)")
                    .scaledFont(size: 22, weight: .heavy, relativeTo: .title3)
            }
            if let amount = pay.amount {
                Text("每人 \(FeeText.text(amount))")
                    .font(AppTheme.Typography.subheadlineBold)
            }
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .card(AppTheme.Colors.mint, shadow: .zero)
    }

    private func unpaidList(_ pay: NightPay) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("没付 \(pay.unpaid.count)")
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            if !pay.unpaid.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(pay.unpaid.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { InsetDivider() }
                        unpaidRow(person)
                    }
                }
                .padding(.leading, AppTheme.Spacing.lg)
                .padding(.trailing, AppTheme.Spacing.xs)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
        }
    }

    /// 没付的人：名字（按住可以“不用付”），右边圆圈点成已付
    private func unpaidRow(_ person: NightPay.Person) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Menu {
                Button("不用付") { payAction { try await backend.remoteSetSignupOwes(person.id, owes: false) } }
            } label: {
                payName(person)
            }
            Spacer(minLength: 0)
            Button {
                payAction { try await backend.remoteMarkSignupPaid(person.id, paid: true) }
            } label: {
                Circle()
                    .strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width)
                    .frame(width: 28, height: 28)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "\(person.name) 标为已付"))
        }
        .frame(minHeight: 52)
    }

    private func paidRow(_ person: NightPay.Person) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            payName(person)
            if person.paidSelf == true {
                Text("自己标的")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            Spacer(minLength: 0)
            Button {
                payAction { try await backend.remoteMarkSignupPaid(person.id, paid: false) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.Colors.success)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "\(person.name) 改回没付"))
        }
        .frame(minHeight: 52)
    }

    private func exemptRow(_ person: NightPay.Person) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            payName(person)
            Spacer(minLength: 0)
            Button("加回来") { payAction { try await backend.remoteSetSignupOwes(person.id, owes: true) } }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
        }
        .frame(minHeight: 52)
    }

    private func payName(_ person: NightPay.Person) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: person.name)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .lineLimit(1)
            if person.guest {
                TagPill(text: String(localized: "访客"), fill: AppTheme.Colors.mint)
                if person.email == false {
                    Text("没留邮箱")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
        }
    }

    /// 已付、不用付：收起来，点开再看
    private func collapsible<Row: View>(_ title: String, isOpen: Binding<Bool>, people: [NightPay.Person],
                                        @ViewBuilder row: @escaping (NightPay.Person) -> Row) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(AppTheme.Motion.standard) { isOpen.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(verbatim: title)
                        .font(AppTheme.Typography.bodyBold)
                    Spacer()
                    Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: 52)
                .sticker(AppTheme.Colors.surfaceMuted, radius: 16, shadow: .zero)
            }
            .buttonStyle(.plain)
            if isOpen.wrappedValue && !people.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { InsetDivider() }
                        row(person)
                    }
                }
                .padding(.leading, AppTheme.Spacing.lg)
                .padding(.trailing, AppTheme.Spacing.xs)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
        }
    }

    /// 不能提醒时写原因（按钮灰掉）
    private func remindBlocked(_ pay: NightPay, state: NightState) -> String? {
        if pay.unpaid.isEmpty { return String(localized: "都付了。") }
        if pay.canRemind == true { return nil }
        if let at = pay.remindedAt, Date().timeIntervalSince(at) < 12 * 3600 { return String(localized: "12 小时内提醒过了。") }
        if Date() < state.startsAt { return String(localized: "开场后才能提醒。") }
        return String(localized: "结束 7 天后不能再提醒。")
    }

    // MARK: 底部

    @ViewBuilder
    private var undoBar: some View {
        if let deadline = undoDeadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if context.date < deadline {
                    Button { undo() } label: {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .medium))
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
            }
        }
    }

    @ViewBuilder
    private func bottomBar(_ state: NightState) -> some View {
        switch segment {
        case .courts:
            if state.open && !state.matchLive {
                Group {
                    if state.started {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Button { showsBoard = true } label: {
                                Label("二维码", systemImage: "qrcode")
                            }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large))
                            .disabled(state.boardCode == nil)
                            Button { showsAdd = true } label: {
                                Label("加人", systemImage: "plus")
                            }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large))
                        }
                    } else {
                        Button("开始") { perform { try await backend.remoteNightStart(sessionId) } }
                            .buttonStyle(.brutalPrimary)
                    }
                }
                .modifier(NightBottomBar())
            }
        case .match:
            EmptyView()
        case .pay:
            if let pay {
                let blocked = remindBlocked(pay, state: state)
                VStack(spacing: AppTheme.Spacing.xs) {
                    if let blocked {
                        Text(verbatim: blocked)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                    Button { remind() } label: {
                        Label("提醒没付的", systemImage: "bell.fill")
                    }
                    .buttonStyle(.brutalPrimary)
                    .disabled(blocked != nil)
                }
                .modifier(NightBottomBar())
            }
        }
    }

    // MARK: 数据和操作

    private func load() async {
        do {
            let next = try await backend.remoteNightState(sessionId)
            if let until = next?.undoUntil, until != lastUndo {
                lastUndo = until
                undoDeadline = Date().addingTimeInterval(min(10, max(3, until.timeIntervalSinceNow)))
            }
            state = next
            loadedAt = Date()
        } catch {
            // 网差：保留上一份
        }
        loaded = true
        if segment == .pay { await loadPay() }
    }

    private func loadPay() async {
        guard state?.isOrganizer == true else { return }
        guard let next = try? await backend.remoteNightPay(sessionId) else { return }
        pay = next
        if !feeFocused { feeText = next.amount.map(FeeText.plain) ?? "" }
    }

    /// 做一个操作，出错就提示（场地已经换过了等），之后都重拉一次
    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                appState.showClubError(error)
            }
            await load()
        }
    }

    private func payAction(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                appState.showClubError(error)
            }
            await loadPay()
        }
    }

    private func mark(_ signups: [String]?, _ status: String?) {
        perform { try await backend.remoteNightMark(sessionId, signups: signups, status: status) }
    }

    private func settings(_ state: NightState, courts: Int? = nil, doubles: Bool? = nil, balance: Bool? = nil) {
        perform {
            try await backend.remoteNightSettings(sessionId, courts: courts ?? state.courts, doubles: doubles ?? state.doubles,
                                                  balance: balance ?? state.balance)
        }
    }

    private func finish(_ game: NightState.Game) {
        Haptics.impact()
        perform {
            try await backend.remoteNightFinish(game: game.id)
            undoDeadline = Date().addingTimeInterval(10)
        }
    }

    private func undo() {
        perform {
            try await backend.remoteNightUndo(sessionId)
            undoDeadline = nil
        }
    }

    private func saveFee() {
        let text = feeText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let amount = Double(text)
        if !text.isEmpty && amount == nil { return }
        feeFocused = false
        payAction { try await backend.remoteSetSessionFee(sessionId, amount: amount) }
    }

    private func remind() {
        Task {
            do {
                let count = try await backend.remoteRemindUnpaid(sessionId)
                appState.showToast(String(localized: "已提醒 \(count) 人"), style: .success)
            } catch {
                appState.showClubError(error)
            }
            await loadPay()
        }
    }
}

/// 页面底部的按钮条
private struct NightBottomBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
            .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { InsetDivider() }
    }
}

/// “A · B 对 C · D”
struct MatchupLine: View {
    let a: [String]
    let b: [String]

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(verbatim: a.joined(separator: " · "))
            Text("对")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Text(verbatim: b.joined(separator: " · "))
        }
        .font(.system(.body, design: .rounded, weight: .heavy))
        .foregroundStyle(AppTheme.Colors.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - 换人

private struct NightSwapSheet: View {
    let state: NightState
    let target: SwapTarget
    let onSwap: (String) -> Void
    let onMark: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("换下 \(state.name(target.out))")
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                }
                .padding(.top, AppTheme.Spacing.xl)
                if state.waiting.isEmpty {
                    Text("没人在等")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                ForEach(state.waiting) { person in
                    Button {
                        onSwap(person.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(verbatim: person.name)
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Spacer()
                            Text("今晚 \(person.games) 场")
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(minHeight: 56)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
                HStack(spacing: AppTheme.Spacing.md) {
                    Button("打完这场休息") {
                        onMark("resting")
                        dismiss()
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                    Button("打完这场走") {
                        onMark("left")
                        dismiss()
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

// MARK: - 加人：候补和没到的人排前面，再输名字

private struct NightAddSheet: View {
    let state: NightState
    let onAdd: (String) -> Void
    let onArrive: (NightState.Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 还没到场的人：候补、没到在前，再是休息、走了的
    private var candidates: [NightState.Person] {
        let order = ["absent": 0, "resting": 1, "left": 2]
        return state.people.filter { $0.status != "here" }.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.waitlisted ? -1 : 0) + (order[lhs.element.status] ?? 0) * 2
            let right = (rhs.element.waitlisted ? -1 : 0) + (order[rhs.element.status] ?? 0) * 2
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map { $0.element }
    }

    private var sameName: Bool {
        let typed = trimmed.lowercased()
        guard !typed.isEmpty else { return false }
        return state.people.contains { person in
            let existing = person.name.lowercased()
            return existing == typed || existing.hasPrefix(typed + " ")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("加人")
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                }
                .padding(.top, AppTheme.Spacing.xl)
                ForEach(candidates) { person in
                    Button {
                        onArrive(person)
                    } label: {
                        HStack {
                            Text(verbatim: person.name)
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Spacer()
                            Text(verbatim: note(person))
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(AppTheme.Colors.ink)
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(minHeight: 56)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        BrutalTextField(label: String(localized: "名单上没有的人"), placeholder: String(localized: "名字"), text: $name,
                                        characterLimit: 24)
                        Button("加") {
                            onAdd(trimmed)
                            name = ""
                        }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: false))
                        .disabled(trimmed.isEmpty || trimmed.count > 24)
                        .padding(.top, 22)
                    }
                    if sameName {
                        Text("名单上已经有叫 \(trimmed) 的人。")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func note(_ person: NightState.Person) -> String {
        if person.waitlisted { return String(localized: "候补") }
        switch person.status {
        case "resting": return String(localized: "休息")
        case "left": return String(localized: "走了")
        default: return String(localized: "没到")
        }
    }
}

// MARK: - 设置：场地数、单双打、按实力分队、帮手

private struct NightSettingsSheet: View {
    let state: NightState
    let me: String?
    /// 场地数、双打、按实力分队、帮手（不是组织者时为 nil）
    let onSave: (Int, Bool, Bool, [String]?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var courts: Int
    @State private var doubles: Bool
    @State private var balance: Bool
    @State private var helpers: Set<String>

    init(state: NightState, me: String?, onSave: @escaping (Int, Bool, Bool, [String]?) -> Void) {
        self.state = state
        self.me = me
        self.onSave = onSave
        _courts = State(initialValue: state.courts)
        _doubles = State(initialValue: state.doubles)
        _balance = State(initialValue: state.balance)
        _helpers = State(initialValue: Set(state.helpers.map(\.id)))
    }

    /// 帮手从到场的注册用户里选
    private var candidates: [NightState.Person] {
        state.people.filter { $0.status == "here" && $0.userId != nil && $0.userId != me }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    HStack {
                        Text("排场设置")
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                    }
                    .padding(.top, AppTheme.Spacing.xl)
                    VStack(spacing: 0) {
                        CourtStepper(courts: $courts)
                            .padding(.leading, AppTheme.Spacing.lg)
                            .padding(.trailing, AppTheme.Spacing.xs)
                        InsetDivider()
                        SegmentedSticker(options: [false, true], selection: $doubles,
                                         title: { $0 ? String(localized: "双打") : String(localized: "单打") })
                            .padding(AppTheme.Spacing.md)
                        InsetDivider()
                        Toggle(isOn: $balance) {
                            Text("按实力分队")
                                .font(AppTheme.Typography.bodyBold)
                                .foregroundStyle(AppTheme.Colors.ink)
                        }
                        .tint(AppTheme.Colors.success)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(minHeight: 56)
                    }
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    if state.isOrganizer {
                        helpersSection
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            Button("保存") {
                onSave(courts, doubles, balance, state.isOrganizer ? Array(helpers) : nil)
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private var helpersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("帮手")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                RulesButton(title: String(localized: "帮手"),
                            points: [String(localized: "能排场、加人、输比分。"),
                                     String(localized: "不能收款，也不能结束或删除。"),
                                     String(localized: "最多 3 个，只在今晚有效。")])
            }
            if candidates.isEmpty {
                Text("到场的注册用户才能当帮手。")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(candidates) { person in
                    if let userId = person.userId {
                        ChoiceChip(title: person.name, icon: helpers.contains(userId) ? "checkmark" : nil,
                                   isSelected: helpers.contains(userId)) {
                            if helpers.contains(userId) {
                                helpers.remove(userId)
                            } else if helpers.count < 3 {
                                helpers.insert(userId)
                            }
                        }
                    }
                }
            }
        }
    }
}
