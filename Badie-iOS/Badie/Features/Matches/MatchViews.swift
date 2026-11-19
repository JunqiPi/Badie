import SwiftUI

// MARK: - 比赛页
// 进行中：正在打的场地（输比分）、下一场、积分榜、全部对阵；结束后：冠军 + 最终排名 + 分享成图片。
// 当晚页的“比赛”分段用同一个 MatchPanel（embedded）。数据在服务器上（match_state），每 10 秒重拉

struct MatchPage: View {
    let matchId: String

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "比赛"))
            ScrollView {
                MatchPanel(matchId: matchId)
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

struct MatchPanel: View {
    let matchId: String
    /// 放在当晚页里：不显示分享按钮，删掉后不返回
    var embedded = false

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager

    @State private var state: MatchState?
    @State private var loaded = false
    @State private var scoring: MatchState.Game?
    @State private var showsBoard = false
    @State private var showsCourts = false
    @State private var showsHelpers = false
    @State private var showsQualify = false
    @State private var showsWithdraw = false
    @State private var showsAddPlayer = false
    @State private var newPlayerName = ""
    @State private var confirmsEnd = false
    @State private var confirmsDelete = false
    @State private var showsAllGames = false
    @State private var undoDeadline: Date?
    @State private var lastUndo: Date?
    @State private var shareImage: UIImage?
    @State private var sharePng: Data?

    private var backend: MockBackend { appState.backend }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            if let state {
                header(state)
                if state.isLive {
                    liveContent(state)
                } else {
                    finalContent(state)
                }
            } else if loaded {
                EmptyStateView(icon: "trophy", title: String(localized: "没有找到这场比赛"))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.Spacing.xxl)
            }
        }
        .task(id: matchId) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .sheet(item: $scoring) { game in
            if let state {
                MatchScoreSheet(match: state, game: game) { await load() }
                    .presentationDetents([.large])
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
        .sheet(isPresented: $showsCourts) {
            if let state {
                MatchCourtsSheet(initial: state.courts) { courts in
                    perform { try await backend.remoteMatchCourts(matchId, courts: courts) }
                }
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsHelpers) {
            if let state {
                MatchHelpersSheet(candidates: helperCandidates(state), initial: Set((state.helpers ?? []).map(\.id))) { users in
                    perform { try await backend.remoteMatchHelpers(matchId, users: users) }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsQualify) {
            if let state {
                MatchQualifySheet(match: state) { keys in
                    perform { try await backend.remoteMatchQualify(matchId, keys: keys) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("谁退赛了？", isPresented: $showsWithdraw, titleVisibility: .visible) {
            if let state {
                ForEach(state.players.filter { !$0.withdrawn }) { player in
                    Button(player.name) {
                        perform { try await backend.remoteMatchWithdraw(player: player.id, game: nil) }
                    }
                }
            }
        } message: {
            Text("没打的场次取消，已经打完的照算。")
        }
        .alert("加人", isPresented: $showsAddPlayer) {
            TextField("名字", text: $newPlayerName)
            Button("加") {
                let name = newPlayerName
                newPlayerName = ""
                perform { try await backend.remoteMatchAddPlayer(matchId, name: name) }
            }
            Button("取消", role: .cancel) { newPlayerName = "" }
        } message: {
            Text("从下一轮开始排。")
        }
        .confirmationDialog("结束比赛？", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("结束比赛", role: .destructive) {
                perform { try await backend.remoteMatchEnd(matchId) }
            }
        } message: {
            Text("没打的写“没打”，按已经打的排名。")
        }
        .confirmationDialog("删掉这场比赛？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { delete() }
        } message: {
            Text("参赛的人会收到通知，不能恢复。")
        }
    }

    // MARK: 顶部

    private func header(_ state: MatchState) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: state.name)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle(state))
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            Spacer(minLength: 0)
            IconButton(systemName: "qrcode", accessibilityLabel: String(localized: "二维码和链接")) { showsBoard = true }
            if state.canManage && (state.isLive || state.isOrganizer) {
                Menu {
                    menuItems(state)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.ink)
                        .frame(width: 44, height: 44)
                        .sticker(AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
                }
                .accessibilityLabel("管理比赛")
            }
        }
    }

    private func subtitle(_ state: MatchState) -> String {
        let format = MatchFormat.title(state.format, play: state.play)
        // 循环、瑞士轮写第几轮；有淘汰赛的不写
        if state.isLive, state.matchFormat.byRounds, let round = state.round, round <= state.rounds {
            return String(localized: "\(format) · 第 \(round)/\(state.rounds) 轮")
        }
        return format
    }

    @ViewBuilder
    private func menuItems(_ state: MatchState) -> some View {
        if state.isLive {
            Button { showsCourts = true } label: { Label("场地数", systemImage: "sportscourt") }
            if state.isOrganizer {
                Button { showsHelpers = true } label: { Label("帮手", systemImage: "person.2") }
            }
            if state.play == MatchPlay.rotating.rawValue {
                Button { showsAddPlayer = true } label: { Label("加人", systemImage: "person.badge.plus") }
            }
            Button { showsWithdraw = true } label: { Label("退赛", systemImage: "figure.walk") }
            if state.isOrganizer {
                Button { confirmsEnd = true } label: { Label("结束比赛", systemImage: "flag.checkered") }
            }
        }
        if state.isOrganizer {
            Button(role: .destructive) { confirmsDelete = true } label: { Label("删除", systemImage: "trash") }
        }
    }

    // MARK: 进行中

    @ViewBuilder
    private func liveContent(_ state: MatchState) -> some View {
        if state.tieAtCut == true && state.isOrganizer {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("出线的名额卡在并列上。")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                Button("选谁出线") { showsQualify = true }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
            }
            .card(AppTheme.Colors.butter, shadow: .zero)
        }
        if state.canManage, let deadline = undoDeadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if context.date < deadline {
                    Button { undo() } label: {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .medium))
                }
            }
        }
        playingSection(state)
        nextSection(state)
        // 单淘汰没有积分榜
        if state.matchFormat != .knockout { standingsSection(state) }
        allGamesSection(state)
    }

    @ViewBuilder
    private func playingSection(_ state: MatchState) -> some View {
        let playing = state.realGames.filter { $0.status == "playing" }.sorted { ($0.court ?? 0) < ($1.court ?? 0) }
        if !playing.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                sectionTitle(String(localized: "正在打"))
                ForEach(playing) { game in
                    HStack(spacing: AppTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let court = game.court {
                                CourtTag(court: court)
                            }
                            Text(verbatim: state.sideName(game.a))
                            Text(verbatim: state.sideName(game.b))
                        }
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        if state.canScore(game) {
                            Button("输比分") { scoring = game }
                                .buttonStyle(BigActionButtonStyle())
                        }
                    }
                    .padding(.leading, AppTheme.Spacing.lg)
                    .padding(.trailing, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                }
            }
        }
    }

    @ViewBuilder
    private func nextSection(_ state: MatchState) -> some View {
        let queued = Array(state.realGames.filter { $0.status == "queued" }.prefix(max(2, state.courts)))
        if !queued.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                sectionTitle(String(localized: "下一场"))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(queued) { game in
                        MatchupLine(a: game.a.map { state.name($0) }, b: game.b.map { state.name($0) })
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
        }
    }

    private func standingsSection(_ state: MatchState) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                sectionTitle(String(localized: "积分榜"))
                RulesButton(title: String(localized: "排名规则"), points: MatchRules.points)
            }
            if let pools = state.pools, pools > 1 {
                ForEach(1...pools, id: \.self) { pool in
                    StandingsTable(rows: state.standings.filter { $0.pool == pool }, title: String(localized: "第 \(pool) 组"))
                }
            } else {
                StandingsTable(rows: state.standings)
            }
        }
    }

    private func allGamesSection(_ state: MatchState) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(AppTheme.Motion.standard) { showsAllGames.toggle() }
            } label: {
                HStack {
                    Text("全部对阵")
                        .font(AppTheme.Typography.bodyBold)
                    Spacer()
                    Image(systemName: showsAllGames ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: 52)
                .sticker(AppTheme.Colors.surfaceMuted, radius: 16, shadow: .zero)
            }
            .buttonStyle(.plain)
            if showsAllGames {
                let rounds = Array(Set(state.realGames.map(\.round))).sorted()
                ForEach(rounds, id: \.self) { round in
                    let games = state.realGames.filter { $0.round == round }
                    Text(verbatim: roundTitle(round, games: games))
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .padding(.top, AppTheme.Spacing.xs)
                    ForEach(games) { game in
                        gameRow(state, game: game)
                    }
                }
            }
        }
    }

    private func roundTitle(_ round: Int, games: [MatchState.Game]) -> String {
        // 决赛和三四名同一轮：写“决赛”
        if let game = games.first(where: { $0.stage == "ko" }) { return MatchRules.stageTitle(game) }
        if let game = games.first { return MatchRules.stageTitle(game) }
        return String(localized: "第 \(round) 轮")
    }

    private func gameRow(_ state: MatchState, game: MatchState.Game) -> some View {
        let opens = state.canScore(game) || (game.status == "done" && state.isMine(game))
        return Button {
            scoring = game
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: state.sideName(game.a))
                    Text(verbatim: state.sideName(game.b))
                }
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.ink)
                .lineLimit(1)
                Spacer(minLength: 0)
                if game.flagged == true && state.canManage {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.danger)
                        .accessibilityLabel("有人说比分不对")
                }
                Text(verbatim: MatchRules.result(game))
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        }
        .buttonStyle(.plain)
        .disabled(!opens)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.ink)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: 结束：最终排名

    @ViewBuilder
    private func finalContent(_ state: MatchState) -> some View {
        let rows = state.ranking ?? state.standings
        let champion = rows.first { $0.rank == 1 }
        sectionTitle(String(localized: "最终排名"))
        if let champion {
            HStack(spacing: AppTheme.Spacing.lg) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                VStack(alignment: .leading, spacing: 2) {
                    Text("冠军")
                        .font(AppTheme.Typography.subheadlineBold)
                    Text(verbatim: champion.name)
                        .scaledFont(size: 36, relativeTo: .title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("\(champion.wins) 胜 \(champion.losses) 负 · 净胜 \(MatchRules.diffText(champion.diff))")
                        .font(AppTheme.Typography.subheadlineBold)
                }
                .foregroundStyle(AppTheme.Colors.onAccent)
            }
            .card(AppTheme.Colors.butter)
        }
        let others = rows.filter { $0.key != champion?.key }
        if !others.isEmpty {
            StandingsTable(rows: others, isFinal: true)
        }
        if !embedded, let image = shareImage, let png = sharePng {
            ShareLink(item: LevelCardImage(png: png), preview: SharePreview(state.name, image: Image(uiImage: image))) {
                Label("分享成图片", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.brutalPrimary)
        }
    }

    // MARK: 数据和操作

    /// 能当帮手的人：参赛的注册用户、球友（不含自己）
    private func helperCandidates(_ state: MatchState) -> [NightHelper] {
        let me = appState.currentUser?.id
        var seen = Set<String>()
        var list: [NightHelper] = []
        for player in state.players {
            if let userId = player.userId, userId != me, seen.insert(userId).inserted {
                list.append(NightHelper(id: userId, nickname: player.name))
            }
        }
        for friend in friendManager.friends where friend.id != me {
            if seen.insert(friend.id).inserted {
                list.append(NightHelper(id: friend.id, nickname: friend.nickname))
            }
        }
        return list
    }

    private func load() async {
        do {
            let next = try await backend.remoteMatchState(matchId)
            if let until = next?.undoUntil, until != lastUndo {
                lastUndo = until
                undoDeadline = Date().addingTimeInterval(min(10, max(3, until.timeIntervalSinceNow)))
            }
            let finished = next?.isLive == false && state?.isLive != false
            state = next
            if finished, let next, !embedded { renderShare(next) }
        } catch {
            // 网差：保留上一份
        }
        loaded = true
    }

    /// 最终排名画成图片（和等级卡同一套样式，4:5）
    private func renderShare(_ state: MatchState) {
        let card = MatchShareCard(name: state.name, subtitle: MatchFormat.title(state.format, play: state.play), date: state.endedAt ?? state.createdAt,
                                  rows: state.ranking ?? state.standings)
        let image = MatchShareRenderer.render(card)
        shareImage = image
        sharePng = image?.pngData()
    }

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

    private func undo() {
        perform {
            try await backend.remoteMatchUndo(matchId)
            undoDeadline = nil
        }
    }

    private func delete() {
        Task {
            do {
                try await backend.remoteMatchDelete(matchId)
                appState.showToast(String(localized: "已删除"))
                if !embedded { router.pop() }
            } catch {
                appState.showClubError(error)
            }
        }
    }
}

// MARK: - 积分榜、排名规则

enum MatchRules {
    static var points: [String] {
        [String(localized: "先看胜场；打的场数不一样时看胜率。"),
         String(localized: "再看净胜分、总得分。"),
         String(localized: "还一样就看两人（两队）之间的胜负。"),
         String(localized: "三人以上还分不开，写并列。")]
    }

    /// +5、−2、0
    static func diffText(_ diff: Int) -> String {
        diff > 0 ? "+\(diff)" : diff < 0 ? "−\(-diff)" : "0"
    }

    /// 比分：“21–18 19–21”
    static func scoreText(_ scores: [Int]) -> String {
        stride(from: 0, to: scores.count - 1, by: 2).map { "\(scores[$0])–\(scores[$0 + 1])" }.joined(separator: " ")
    }

    /// 这一场叫什么：第几轮、四分之一决赛、半决赛、决赛、三四名决赛、16 强
    static func stageTitle(_ game: MatchState.Game) -> String {
        if game.stage == "third" { return String(localized: "三四名决赛") }
        if game.stage == "ko" {
            switch game.koSize ?? 0 {
            case 2: return String(localized: "决赛")
            case 4: return String(localized: "半决赛")
            case 8: return String(localized: "四分之一决赛")
            default: return String(localized: "\(game.koSize ?? 0) 强")
            }
        }
        return String(localized: "第 \(game.round) 轮")
    }

    /// 全部对阵里右边那一格
    static func result(_ game: MatchState.Game) -> String {
        switch game.status {
        case "done":
            if game.walkover == true { return String(localized: "已退赛") }
            if game.retired != nil {
                return [scoreText(game.scores ?? []), String(localized: "中途退赛")].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return scoreText(game.scores ?? [])
        case "playing": return game.court.map { String(localized: "场地 \($0)") } ?? ""
        case "cancelled": return String(localized: "取消")
        case "skipped": return String(localized: "没打")
        default: return ""
        }
    }
}

/// 积分榜（进行中）和最终排名的表：名次、名字、胜-负、净胜分
struct StandingsTable: View {
    let rows: [MatchState.Standing]
    var title: String?
    var isFinal = false

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                Text(verbatim: title)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppTheme.Spacing.sm)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(verbatim: isFinal ? String(localized: "名次") : "")
                    .frame(width: 36, alignment: .leading)
                Text("名字")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("胜-负")
                    .frame(width: 56)
                Text("净胜分")
                    .frame(width: 56, alignment: .trailing)
            }
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
            .frame(minHeight: 28)
            ForEach(rows) { row in
                HStack(spacing: AppTheme.Spacing.sm) {
                    rank(row)
                        .frame(width: 36, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(verbatim: row.name)
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(row.withdrawn == true ? AppTheme.Colors.inkTertiary : AppTheme.Colors.ink)
                            .lineLimit(1)
                        if row.tied == true {
                            Text("并列")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        if row.withdrawn == true {
                            Text("已退赛")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "\(row.wins)-\(row.losses)")
                        .font(AppTheme.Typography.bodyBold)
                        .monospacedDigit()
                        .frame(width: 56)
                    Text(verbatim: MatchRules.diffText(row.diff))
                        .font(AppTheme.Typography.subheadlineBold)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .foregroundStyle(AppTheme.Colors.ink)
                .frame(minHeight: isFinal ? 44 : 32)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
    }

    @ViewBuilder
    private func rank(_ row: MatchState.Standing) -> some View {
        if isFinal {
            Text(verbatim: "\(row.rank)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(row.rank <= 3 ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(row.rank <= 3 ? AppTheme.Colors.lavender : AppTheme.Colors.surface))
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.hairline))
        } else {
            Text(verbatim: "\(row.rank)")
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
    }
}

// MARK: - 输比分（半屏）
// 两边大数字，加减，点数字直接输；三局两胜一局一局填。
// 球员只能在打的时候输自己那场，先存的算；别人再打开看到“Amy 填的：21–18”，只能点“不对”。
// 组织者、帮手随时能改（写“Kevin 改的”）；不合规的比分存不了，写明哪里不对；中途退赛单独记

struct MatchScoreSheet: View {
    let match: MatchState
    let game: MatchState.Game
    let onDone: () async -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 每局两个数：[a1, b1, a2, b2, a3, b3]
    @State private var scores: [Int]
    @State private var setIndex = 0
    @State private var saving = false
    @State private var confirmsRetire = false
    @State private var typingIndex = 0
    @State private var typedText = ""
    @State private var showsTyping = false
    @State private var confirmsWithdraw = false

    init(match: MatchState, game: MatchState.Game, onDone: @escaping () async -> Void) {
        self.match = match
        self.game = game
        self.onDone = onDone
        let count = match.bestOf == 3 ? 6 : 2
        var initial = game.scores ?? []
        while initial.count < count { initial.append(0) }
        _scores = State(initialValue: Array(initial.prefix(count)))
    }

    private var editable: Bool { match.canScore(game) }

    private var title: String {
        let stage = MatchRules.stageTitle(game)
        if let court = game.court { return String(localized: "场地 \(court) · \(stage)") }
        return stage
    }

    /// 要存的比分：去掉后面没填的局
    private var entered: [Int] { MatchScoring.played(scores) }
    private var check: MatchScoring.Check { MatchScoring.check(entered, match.scoring) }
    private var retireProblem: String? { MatchScoring.retireProblem(entered, match.scoring) }

    private var rulesText: String {
        let sets = match.bestOf == 3 ? String(localized: "三局两胜") : String(localized: "一局")
        return String(localized: "\(match.points) 分 · \(sets)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: rulesText)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.top, AppTheme.Spacing.xl)
            if editable {
                editor
            } else {
                readOnly
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .showsToasts()
        .alert("输入比分", isPresented: $showsTyping) {
            TextField("", text: $typedText)
                .keyboardType(.numberPad)
            Button("好") {
                if let value = Int(typedText), (0...99).contains(value), scores.indices.contains(typingIndex) {
                    scores[typingIndex] = value
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("谁中途退赛了？", isPresented: $confirmsRetire, titleVisibility: .visible) {
            ForEach([1, 2], id: \.self) { side in
                Button(String(localized: "\(match.sideName(side == 1 ? game.a : game.b)) 中途退赛")) { retire(side: side) }
            }
        } message: {
            Text("按退赛时的比分填，没打完的那局也填上。对方赢。")
        }
        .confirmationDialog("谁退赛了？", isPresented: $confirmsWithdraw, titleVisibility: .visible) {
            ForEach(game.a + game.b, id: \.self) { playerId in
                Button(match.name(playerId)) { withdraw(playerId) }
            }
        } message: {
            Text("这一场算对方赢。")
        }
    }

    /// 谁填的、谁改的
    @ViewBuilder
    private var byLine: some View {
        if let by = game.editedBy {
            Text("\(by) 改的")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        } else if let by = game.scoredBy, game.status == "done" {
            Text("\(by) 填的")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            byLine
            if match.bestOf == 3 {
                SegmentedSticker(options: [0, 1, 2], selection: $setIndex, title: { String(localized: "第 \($0 + 1) 局") })
            }
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                sideColumn(side: 0)
                sideColumn(side: 1)
            }
            if match.bestOf == 3 && !entered.isEmpty {
                Text(verbatim: MatchRules.scoreText(entered))
                    .font(AppTheme.Typography.headline)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(maxWidth: .infinity)
            }
            if case .problem(let text) = check {
                Text(verbatim: text)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            // 不合规的比分存不了
            Button("保存") { save() }
                .buttonStyle(.brutalPrimary)
                .disabled(saving || !isValid)
            if match.canManage {
                HStack(spacing: AppTheme.Spacing.lg) {
                    Button("有人中途退赛") {
                        if let problem = retireProblem {
                            appState.showToast(problem, style: .error)
                        } else {
                            confirmsRetire = true
                        }
                    }
                    if game.status != "done" {
                        Button("退赛") { confirmsWithdraw = true }
                    }
                }
                .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sideColumn(side: Int) -> some View {
        let index = setIndex * 2 + side
        let names = match.sideName(side == 0 ? game.a : game.b)
        return VStack(spacing: AppTheme.Spacing.sm) {
            Text(verbatim: names)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 44)
            Button {
                typingIndex = index
                typedText = "\(scores[index])"
                showsTyping = true
            } label: {
                Text(verbatim: "\(scores[index])")
                    .scaledFont(size: 64, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(maxWidth: .infinity, minHeight: 112)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(String(localized: "\(names) 的比分，点一下直接输"))
            .accessibilityValue(Text(verbatim: "\(scores[index])"))
            HStack(spacing: AppTheme.Spacing.sm) {
                stepButton(icon: "minus", label: String(localized: "减一分"), fill: AppTheme.Colors.surfaceMuted) {
                    scores[index] = max(0, scores[index] - 1)
                }
                stepButton(icon: "plus", label: String(localized: "加一分"), fill: AppTheme.Colors.surface) {
                    scores[index] = min(99, scores[index] + 1)
                }
            }
        }
    }

    private func stepButton(icon: String, label: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(AppTheme.Colors.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .sticker(fill, radius: 16, shadow: .zero)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// 球员看别人填的比分：只能点“不对”
    private var readOnly: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(verbatim: match.sideName(game.a))
                Spacer(minLength: 0)
                Text(verbatim: match.sideName(game.b))
            }
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.ink)
            if game.status == "done" {
                Text(verbatim: MatchRules.result(game))
                    .scaledFont(size: 44, relativeTo: .largeTitle)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(maxWidth: .infinity)
                if let text = enteredBy {
                    Text(verbatim: text)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                if match.isMine(game) {
                    if game.flagged == true {
                        Text("已经告诉组织者了。")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    } else {
                        Button("不对") { flag() }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large))
                    }
                }
            } else {
                Text(verbatim: MatchRules.result(game))
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
        }
    }

    /// “Amy 填的：21–18”或“Kevin 改的”
    private var enteredBy: String? {
        if let by = game.editedBy { return String(localized: "\(by) 改的") }
        guard let by = game.scoredBy else { return nil }
        let score = MatchRules.scoreText(game.scores ?? [])
        return String(localized: "\(by) 填的：\(score)")
    }

    private var isValid: Bool {
        if case .winner = check { return true }
        return false
    }

    private func save() {
        send { try await appState.backend.remoteMatchScore(game: game.id, scores: entered, version: game.version ?? 0) }
    }

    private func retire(side: Int) {
        send { try await appState.backend.remoteMatchRetire(game: game.id, side: side, scores: entered, version: game.version ?? 0) }
    }

    private func send(_ call: @escaping () async throws -> Void) {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await call()
                Haptics.success()
                await onDone()
                dismiss()
            } catch RemoteError.server(let code) where code == "score_taken" || code == "score_changed" {
                // 有人先存了：提示一句，关掉重看
                appState.showError(RemoteError.server(code))
                await onDone()
                dismiss()
            } catch {
                // 没存上：数字留在原处，可以再点一次
                appState.showClubError(error)
            }
        }
    }

    private func flag() {
        Task {
            do {
                try await appState.backend.remoteMatchFlag(game: game.id)
                appState.showToast(String(localized: "已经告诉组织者了。"))
                await onDone()
                dismiss()
            } catch {
                appState.showClubError(error)
            }
        }
    }

    private func withdraw(_ playerId: String) {
        Task {
            do {
                try await appState.backend.remoteMatchWithdraw(player: playerId, game: game.id)
                await onDone()
                dismiss()
            } catch {
                appState.showClubError(error)
            }
        }
    }
}

// MARK: - 组织者菜单里的几个半屏

private struct MatchCourtsSheet: View {
    let initial: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var courts = 2

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("场地数")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            CourtStepper(courts: $courts)
                .padding(.leading, AppTheme.Spacing.lg)
                .padding(.trailing, AppTheme.Spacing.xs)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            Button("保存") {
                onSave(courts)
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { courts = initial }
    }
}

/// 帮手（记分员）：最多 3 个，从参赛的人和球友里选
private struct MatchHelpersSheet: View {
    let candidates: [NightHelper]
    let initial: Set<String>
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("帮手")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                RulesButton(title: String(localized: "帮手"),
                            points: [String(localized: "能输比分、改场地数、加人。"),
                                     String(localized: "不能结束或删除比赛。"),
                                     String(localized: "最多 3 个。")])
                Spacer()
            }
            .padding(.top, AppTheme.Spacing.xl)
            ScrollView {
                FlowLayout(spacing: AppTheme.Spacing.sm) {
                    ForEach(candidates) { person in
                        ChoiceChip(title: person.nickname, icon: selected.contains(person.id) ? "checkmark" : nil,
                                   isSelected: selected.contains(person.id)) {
                            if selected.contains(person.id) {
                                selected.remove(person.id)
                            } else if selected.count < 3 {
                                selected.insert(person.id)
                            }
                        }
                    }
                }
                if candidates.isEmpty {
                    Text("还没有球友。")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            Button("保存") {
                onSave(Array(selected))
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { selected = initial }
    }
}

/// 分组出线卡在并列上：组织者点选谁出线
private struct MatchQualifySheet: View {
    let match: MatchState
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []

    /// 出线的名额：每组前几名；3 组时再加一个最好的第 2 名
    private var needed: Int {
        (match.pools ?? 2) * (match.advance ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("选谁出线")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            Text("选 \(needed) 个，按名次排种子。")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(match.standings.filter { $0.withdrawn != true }) { row in
                        Button {
                            if let index = selected.firstIndex(of: row.key) {
                                selected.remove(at: index)
                            } else if selected.count < needed {
                                selected.append(row.key)
                            }
                        } label: {
                            HStack {
                                Text(verbatim: "\(row.rank)")
                                    .frame(width: 28, alignment: .leading)
                                Text(verbatim: row.name)
                                if let pool = row.pool {
                                    Text("第 \(pool) 组")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(row.key) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                            }
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .frame(minHeight: 52)
                            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button("保存") {
                onSave(seeded)
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
            .disabled(selected.count != needed)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    /// 种子顺序：先按组里的名次，再按组
    private var seeded: [String] {
        let rows = match.standings.filter { selected.contains($0.key) }
        return rows.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? (lhs.pool ?? 0) < (rhs.pool ?? 0) : lhs.rank < rhs.rank
        }.map(\.key)
    }
}

// MARK: - 分享成图片：和等级卡同一套样式（米白底、墨色字、柠檬绿），4:5

struct MatchShareCard: View {
    let name: String
    let subtitle: String
    let date: Date
    let rows: [MatchState.Standing]

    /// 画布大小（点），导出 ×3 = 1080×1350
    static let size = CGSize(width: 360, height: 450)

    private let ink = Color(hex: 0x17140F)
    private let cream = Color(hex: 0xF2EFE7)
    private let lime = Color(hex: 0xD4F33F)
    private let gray = Color(hex: 0x6F695E)

    var body: some View {
        let champion = rows.first
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "BADIE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(2)
                Spacer()
                Text(verbatim: "\(subtitle) · \(date.formatted(.dateTime.month().day()))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(gray)
                    .lineLimit(1)
            }
            Text(verbatim: name)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 14)
            if let champion {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(lime))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("冠军")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(lime)
                        Text(verbatim: champion.name)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(cream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: "\(champion.wins)-\(champion.losses)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(cream)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ink))
                .padding(.top, 14)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.dropFirst().prefix(7))) { row in
                    HStack(spacing: 10) {
                        Text(verbatim: "\(row.rank)")
                            .frame(width: 24, alignment: .leading)
                            .foregroundStyle(gray)
                        Text(verbatim: row.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: "\(row.wins)-\(row.losses)")
                            .frame(width: 44)
                        Text(verbatim: MatchRules.diffText(row.diff))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(ink.opacity(0.1)).frame(height: 1)
                    }
                }
            }
            .padding(.top, 10)
            Spacer(minLength: 0)
            Text(verbatim: "badie.rsvp")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(gray)
        }
        .foregroundStyle(ink)
        .padding(22)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(cream)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
enum MatchShareRenderer {
    static func render(_ card: MatchShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(MatchShareCard.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - 我的 → 比赛

struct MyMatchesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var matches: [MyMatch] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "比赛"))
            if loaded && matches.isEmpty {
                EmptyStateView(icon: "trophy", title: String(localized: "还没有比赛"), tint: AppTheme.Colors.butter,
                               actionTitle: String(localized: "建一场")) {
                    router.open(.createMatch(sessionId: nil))
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(matches) { match in
                            Button {
                                router.open(.match(id: match.id))
                            } label: {
                                row(match)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .refreshable { await load() }
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task { await load() }
    }

    private func row(_ match: MyMatch) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            IconTile(systemName: "trophy.fill", fill: AppTheme.Colors.butter, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: match.name)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1)
                Text("\(MatchFormat.title(match.format, play: match.play)) · \(match.players) 人 · \(match.createdAt.formatted(.dateTime.month().day()))")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            TagPill(text: status(match), fill: match.status == "live" ? AppTheme.Colors.lime : AppTheme.Colors.surfaceMuted,
                    foreground: AppTheme.Colors.onAccent)
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func status(_ match: MyMatch) -> String {
        if match.status == "live" { return String(localized: "进行中") }
        if let rank = match.rank { return String(localized: "第 \(rank) 名") }
        return String(localized: "已结束")
    }

    private func load() async {
        if let list = try? await appState.backend.remoteMyMatches() { matches = list }
        loaded = true
    }
}
