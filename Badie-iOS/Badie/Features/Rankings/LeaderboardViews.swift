import SwiftUI

// MARK: - 我在周榜上的位置（周榜页、首页共用）

struct WeeklyStanding {
    let points: Int
    let games: Int
    let wins: Int
    /// 在榜上的名次；达到门槛但在前 50 名外时为 nil
    let rank: Int?
    let isQualified: Bool
    /// 不能上榜的原因（关闭了上榜、注册未满 7 天）
    let absenceReason: String?
    /// 还要再打几场才达到上榜门槛
    let gamesNeeded: Int
    let isCurrentWeek: Bool

    @MainActor
    init(backend: MockBackend, userId: String, week: DateInterval, countryCode: String? = nil, entries: [Rankings.Entry]) {
        let score = backend.weeklyScore(for: userId, week: week, countryCode: countryCode)
        points = score.points
        games = score.games
        wins = score.wins
        rank = entries.first { $0.userId == userId }?.rank
        isQualified = score.games >= Rankings.weeklyMinimumGames && score.opponents >= Rankings.weeklyMinimumOpponents
        absenceReason = backend.boardAbsenceReason()
        isCurrentWeek = week.contains(Date())
        gamesNeeded = max(1, Rankings.weeklyMinimumGames - score.games, Rankings.weeklyMinimumOpponents - score.opponents)
    }

    /// 首页、置顶卡片上的一句话
    var summary: String {
        if let absenceReason { return absenceReason }
        if let rank { return String(localized: "第 \(rank) 名 · \(points) 分") }
        if isQualified { return String(localized: "\(points) 分 · 暂未进前 \(Rankings.boardSize) 名") }
        if !isCurrentWeek { return String(localized: "上周没有上榜") }
        return String(localized: "本周再打 \(gamesNeeded) 场确认过的比赛上榜（至少 \(Rankings.weeklyMinimumOpponents) 位不同对手）")
    }
}

// MARK: - 全球周榜

struct WeeklyLeaderboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var matchManager: MatchManager

    private enum Scope: Hashable { case global, country }
    private enum WeekChoice: Hashable { case this, last }

    @State private var scope: Scope = .global
    @State private var weekChoice: WeekChoice = .this
    /// 男子榜 / 女子榜；没选过就看自己的
    @State private var boardChoice: Gender?
    @State private var onlyMyBracket = false
    @State private var entries: [Rankings.Entry] = []
    @State private var standing: WeeklyStanding?
    @State private var showsRules = false
    @State private var reportTarget: String?

    private var backend: MockBackend { appState.backend }
    private var me: User? { appState.currentUser }
    private var country: CountryInfo { CountryInfo.info(for: backend.currentCountryCode) }

    private var week: DateInterval {
        let current = Rankings.week(containing: Date())
        return weekChoice == .this ? current : Rankings.week(containing: current.start.addingTimeInterval(-1))
    }

    private var boardGender: Gender { boardChoice ?? backend.myBoard }
    private var onMyBoard: Bool { boardGender == backend.myBoard }

    /// 我的水平段；看另一个榜时不按我的段筛
    private var myBracket: LevelBracket? {
        guard onMyBoard else { return nil }
        return me.map { LevelBracket(rating: $0.displayTier.rating) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "本周排行")) {
                IconButton(systemName: "questionmark", accessibilityLabel: String(localized: "积分怎么算")) {
                    showsRules = true
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    filters
                    if let standing { myStandingCard(standing) }
                    board
                    Button("积分怎么算") { showsRules = true }
                        .buttonStyle(TextActionStyle())
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear(perform: reload)
        .onChange(of: scope) { _, _ in reload() }
        .onChange(of: weekChoice) { _, _ in reload() }
        .onChange(of: boardChoice) { _, _ in reload() }
        .onChange(of: onlyMyBracket) { _, _ in reload() }
        .onChange(of: matchManager.games) { _, _ in reload() }
        .onChange(of: matchManager.rankingsRevision) { _, _ in reload() }
        .sheet(isPresented: $showsRules) {
            WeeklyRulesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("举报这位球友？", isPresented: Binding(
            get: { reportTarget != nil },
            set: { if !$0 { reportTarget = nil } }
        ), titleVisibility: .visible, presenting: reportTarget) { userId in
            Button("刷榜 / 虚假比赛", role: .destructive) { report(userId, reason: .other) }
            Button("广告 / 引流", role: .destructive) { report(userId, reason: .scam) }
        } message: { _ in
            Text("举报后对方会立即从你的榜单上隐藏，我们会人工核实。")
        }
    }

    // MARK: 筛选

    private var filters: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SegmentedSticker(options: [Scope.global, .country], selection: $scope) { option in
                option == .global ? String(localized: "全球") : "\(country.flag) \(country.nameZh)"
            }
            SegmentedSticker(options: [WeekChoice.this, .last], selection: $weekChoice) { option in
                option == .this ? String(localized: "本周") : String(localized: "上周")
            }
            BoardPicker(selection: $boardChoice, mine: backend.myBoard)
            if let myBracket {
                Toggle(isOn: $onlyMyBracket) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("只看我的水平段")
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Text(myBracket.title)
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                .tint(AppTheme.Colors.lime)
                .padding(.vertical, AppTheme.Spacing.xs)
            }
            Text("每周一 0 点（UTC）重新开始")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    // MARK: 我的位置

    private func myStandingCard(_ standing: WeeklyStanding) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            MyAvatarView(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("我的位置")
                    .font(AppTheme.Typography.overline)
                    .tracking(0.8)
                Text(standing.summary)
                    .font(AppTheme.Typography.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(standing.games) 场 · 胜 \(standing.wins)")
                    .font(AppTheme.Typography.footnote)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .card(AppTheme.Colors.lime)
        .accessibilityElement(children: .combine)
    }

    // MARK: 榜单

    @ViewBuilder
    private var board: some View {
        if entries.isEmpty {
            EmptyStateView(icon: "trophy", title: String(localized: "还没有人上榜"),
                           message: String(localized: "打满 \(Rankings.weeklyMinimumGames) 场双方确认过的比赛就能上榜"),
                           tint: AppTheme.Colors.butter)
                .card()
        } else {
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(entries) { entry in
                    if let user = backend.user(id: entry.userId) {
                        let isMe = entry.userId == me?.id
                        LeaderboardRow(entry: entry, user: user, isMe: isMe, showsLevel: true,
                                       points: entry.score)
                            .contextMenu {
                                if !isMe {
                                    Button(role: .destructive) {
                                        reportTarget = entry.userId
                                    } label: {
                                        Label("举报（刷榜、广告等）", systemImage: "exclamationmark.bubble")
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: 数据

    private func reload() {
        var list = backend.weeklyLeaderboard(week: week, countryCode: scope == .country ? backend.currentCountryCode : nil,
                                             gender: boardGender)
        if onlyMyBracket, let myBracket {
            list = Self.reranked(list.filter { entry in
                backend.user(id: entry.userId).map { LevelBracket(rating: $0.displayTier.rating) == myBracket } ?? false
            })
        }
        entries = list
        // 看另一个榜时不显示“我的位置”（我不在那个榜上）
        standing = onMyBoard ? me.map { WeeklyStanding(backend: backend, userId: $0.id, week: week,
                                                       countryCode: scope == .country ? backend.currentCountryCode : nil, entries: list) } : nil
    }

    /// 筛选后重新编号（同分同胜场同名次）
    private static func reranked(_ list: [Rankings.Entry]) -> [Rankings.Entry] {
        var result: [Rankings.Entry] = []
        for (index, entry) in list.enumerated() {
            let tied = index > 0 && list[index - 1].score == entry.score && list[index - 1].wins == entry.wins
            result.append(Rankings.Entry(userId: entry.userId, rank: tied ? result[index - 1].rank : index + 1,
                                         score: entry.score, games: entry.games, wins: entry.wins))
        }
        return result
    }

    private func report(_ userId: String, reason: ReportReason) {
        backend.reportFromLeaderboard(userId, reason: reason)
        reportTarget = nil
        reload()
        appState.showToast(String(localized: "已隐藏，我们会尽快核实"), style: .success)
    }
}

// MARK: - 积分规则

private struct WeeklyRulesSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("积分怎么算")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.top, AppTheme.Spacing.xl)
                VStack(alignment: .leading, spacing: 0) {
                    InfoRow(icon: "plus.circle.fill", tint: AppTheme.Colors.lime,
                            title: String(localized: "每场确认过的比赛：输 10 分、赢 15 分"),
                            subtitle: String(localized: "输了也有分，多打就多得"))
                    InsetDivider()
                    InfoRow(icon: "chart.bar.fill", tint: AppTheme.Colors.sky,
                            title: String(localized: "看对手强弱"),
                            subtitle: String(localized: "对手比你强最多 ×1.5，比你弱最少 ×0.5"))
                    InsetDivider()
                    InfoRow(icon: "person.2.fill", tint: AppTheme.Colors.peach,
                            title: String(localized: "同一对手第 2 场减半、第 3 场起不计分"),
                            subtitle: String(localized: "多和不同的人打"))
                    InsetDivider()
                    InfoRow(icon: "number", tint: AppTheme.Colors.butter,
                            title: String(localized: "每周最多计 \(Rankings.weeklyGameCap) 场"),
                            subtitle: String(localized: "至少 \(Rankings.weeklyMinimumGames) 场、\(Rankings.weeklyMinimumOpponents) 位不同对手才上榜"))
                    InsetDivider()
                    InfoRow(icon: "checkmark.seal.fill", tint: AppTheme.Colors.mint,
                            title: String(localized: "双方确认的比赛才算"),
                            subtitle: String(localized: "有分歧或没确认的不计分"))
                    InsetDivider()
                    InfoRow(icon: "calendar", tint: AppTheme.Colors.lavender,
                            title: String(localized: "注册满 \(Rankings.minimumAccountAgeDays) 天才上榜"),
                            subtitle: String(localized: "可在设置里关闭上榜"))
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

// MARK: - 场馆月榜

struct VenueLeaderboardView: View {
    let venueId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var matchManager: MatchManager

    private enum MonthChoice: Hashable { case this, last }
    private static let visibleCount = 10

    @State private var monthChoice: MonthChoice = .this
    @State private var boardChoice: Gender?
    @State private var sections: [BracketBoard] = []

    private struct BracketBoard: Identifiable {
        let bracket: LevelBracket
        let entries: [Rankings.Entry]
        var id: Int { bracket.rawValue }
    }

    private var backend: MockBackend { appState.backend }
    private var me: String? { appState.currentUser?.id }

    private var month: DateInterval {
        let current = Rankings.month(containing: Date())
        return monthChoice == .this ? current : Rankings.month(containing: current.start.addingTimeInterval(-1))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "本馆排行"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(backend.venue(id: venueId)?.name ?? String(localized: "球馆"))
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("按本月在这家球馆打的确认过的场数排名（同一对手最多计 \(Rankings.venueSameOpponentCap) 场、每天最多 \(Rankings.venueDailyCap) 场）；每个水平段单独排")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SegmentedSticker(options: [MonthChoice.this, .last], selection: $monthChoice) { option in
                        option == .this ? String(localized: "本月") : String(localized: "上月")
                    }
                    BoardPicker(selection: $boardChoice, mine: backend.myBoard)
                    if sections.isEmpty {
                        EmptyStateView(icon: "trophy", title: String(localized: "这个月还没有人上榜"),
                                       tint: AppTheme.Colors.butter)
                            .card()
                    } else {
                        ForEach(sections) { section in
                            bracketSection(section.bracket, entries: section.entries)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear(perform: reload)
        .onChange(of: monthChoice) { _, _ in reload() }
        .onChange(of: boardChoice) { _, _ in reload() }
        .onChange(of: matchManager.games) { _, _ in reload() }
        .onChange(of: matchManager.rankingsRevision) { _, _ in reload() }
    }

    private func bracketSection(_ bracket: LevelBracket, entries: [Rankings.Entry]) -> some View {
        var visible = Array(entries.prefix(Self.visibleCount))
        if let mine = entries.first(where: { $0.userId == me }), !visible.contains(mine) {
            visible.append(mine)
        }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: bracket.title, detail: String(localized: "\(entries.count) 人"))
            ForEach(visible) { entry in
                if let user = backend.user(id: entry.userId) {
                    LeaderboardRow(entry: entry, user: user, isMe: entry.userId == me, showsLevel: false,
                                   badge: entry.rank == 1 ? String(localized: "本月馆主") : nil)
                }
            }
        }
    }

    private func reload() {
        sections = backend.venueLeaderboard(venueId: venueId, month: month, gender: boardChoice).map {
            BracketBoard(bracket: $0.bracket, entries: $0.entries)
        }
    }
}

// MARK: - 男子榜 / 女子榜

/// 男女等级分开算，榜也分开；默认看自己的
private struct BoardPicker: View {
    @Binding var selection: Gender?
    let mine: Gender

    var body: some View {
        SegmentedSticker(options: Gender.choices, selection: Binding(
            get: { selection ?? mine },
            set: { selection = $0 }
        )) { $0.boardLabel }
    }
}

// MARK: - 榜单行

private struct LeaderboardRow: View {
    let entry: Rankings.Entry
    let user: User
    let isMe: Bool
    let showsLevel: Bool
    /// 周榜积分；场馆榜不显示
    var points: Int?
    var badge: String?

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.showPlayer(user.id)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                rankMark
                AvatarView(user: user, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(user.nickname)
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .lineLimit(1)
                        if isMe {
                            TagPill(text: String(localized: "我"), fill: AppTheme.Colors.lime)
                        }
                        if let badge {
                            TagPill(text: badge, icon: "crown.fill", fill: AppTheme.Colors.butter)
                        }
                    }
                    Text(detailText)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let points {
                    Text("\(points) 分")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sticker(isMe ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface,
                     radius: AppTheme.Radius.md, shadow: .zero)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(isMe)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var detailText: String {
        let record = String(localized: "\(entry.games) 场 · 胜 \(entry.wins)")
        return showsLevel ? "\(user.displayLevelText) · \(record)" : record
    }

    private var accessibilityText: String {
        let base = String(localized: "第 \(entry.rank) 名，\(user.nickname)，\(detailText)")
        guard let points else { return base }
        return String(localized: "\(base)，\(points) 分")
    }

    private var medalFill: Color? {
        switch entry.rank {
        case 1: return AppTheme.Colors.butter
        case 2: return AppTheme.Colors.sky
        case 3: return AppTheme.Colors.peach
        default: return nil
        }
    }

    private var rankMark: some View {
        Text("\(entry.rank)")
            .font(AppTheme.Typography.bodyBold)
            .monospacedDigit()
            .foregroundStyle(medalFill == nil ? AppTheme.Colors.inkSecondary : AppTheme.Colors.onAccent)
            .frame(width: 32, height: 32)
            .background {
                if let medalFill {
                    Circle().fill(medalFill)
                    Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5)
                }
            }
            .minimumScaleFactor(0.6)
    }
}
