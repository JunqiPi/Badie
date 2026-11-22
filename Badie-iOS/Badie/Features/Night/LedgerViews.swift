import SwiftUI

// MARK: - 你还没付（球群页最上面、球局页）
// 写了金额、还没付的场次，按球群和收钱的人合起来：一张卡一个大按钮，一次付清（每一场都记“我付了”）。
// 没写金额的场次照旧在场次行上“付给 Kevin”

struct DuesCard: View {
    let dues: [MyDue]
    /// 球群页上不用再写球群名
    var showsGroup = true
    let onPaid: () -> Void

    @State private var paying: Pile?

    struct Pile: Identifiable {
        let dues: [MyDue]

        var id: String { "\(first.groupId):\(first.toId)" }
        var first: MyDue { dues[0] }
        var total: Double { dues.reduce(0) { $0 + $1.amount } }
        var dates: String {
            dues.map { $0.startsAt.formatted(.dateTime.month(.abbreviated).day()) }.joined(separator: ", ")
        }
    }

    private var piles: [Pile] {
        let grouped = Dictionary(grouping: dues) { "\($0.groupId):\($0.toId)" }
        return grouped.values
            .map { Pile(dues: $0.sorted { $0.startsAt < $1.startsAt }) }
            .sorted { $0.first.startsAt < $1.first.startsAt }
    }

    var body: some View {
        if !dues.isEmpty {
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(piles) { pile in
                    card(pile)
                }
            }
            .sheet(item: $paying) { pile in
                PaySheet(sessionId: pile.first.sessionId, groupName: pile.first.group,
                         startsAt: pile.first.startsAt, endsAt: pile.first.endsAt,
                         pay: GroupTonight.Pay(to: pile.first.to, amount: pile.total, handles: pile.first.handles, paid: false, paidSelf: nil),
                         paid: false, otherSessionIds: pile.dues.dropFirst().map(\.sessionId), dates: pile.dates) { paid in
                    if paid { onPaid() }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
    }

    private func card(_ pile: Pile) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("你还没付")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.onAccent)
                    Text(verbatim: showsGroup ? "\(pile.first.group) · \(pile.dates)" : pile.dates)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(verbatim: FeeText.text(pile.total))
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .monospacedDigit()
            }
            Button {
                paying = pile
            } label: {
                Label(String(localized: "付给 \(pile.first.to) · \(FeeText.text(pile.total))"), systemImage: "dollarsign.circle.fill")
            }
            .buttonStyle(.brutalPrimary)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.butter, radius: AppTheme.Radius.lg)
    }
}

// MARK: - 收款记录（只有组织者）
// 谁还欠着（按人合起来，一次标成已付）、开过的每一场收齐了没有（点进去和当晚页的“收款”一样）、导出成表格

struct GroupLedgerView: View {
    let groupId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var ledger: GroupLedger?
    @State private var earlier: [GroupLedger.Session] = []
    @State private var reachedEnd = false
    @State private var failed = false
    @State private var busy: String?
    /// 导出的表格（打开页面时在后台生成）
    @State private var exportFile: URL?

    private var sessions: [GroupLedger.Session] { (ledger?.sessions ?? []) + earlier }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "收款")) {
                if let exportFile {
                    ShareLink(item: exportFile) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .frame(width: 44, height: 44)
                            .sticker(AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
                    }
                    .accessibilityLabel("导出")
                }
            }
            if let ledger {
                if sessions.isEmpty {
                    EmptyStateView(icon: "dollarsign.circle", title: String(localized: "还没有开过的场次。"),
                                   message: String(localized: "每一场开始后会出现在这里。"))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                            owedSection(ledger.owed ?? [])
                            sessionsSection
                        }
                        .padding(.horizontal, AppTheme.Spacing.screen)
                        .padding(.bottom, AppTheme.Spacing.xxl)
                    }
                    .refreshable { await load() }
                }
            } else if failed {
                EmptyStateView(icon: "lock", title: String(localized: "只有组织者能看。"))
                Spacer()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task(id: groupId) { await load() }
    }

    // MARK: 谁还欠着

    private func owedSection(_ owed: [GroupLedger.Owed]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text("还欠着")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                if !owed.isEmpty {
                    Text(verbatim: FeeText.text(owed.reduce(0) { $0 + $1.amount }))
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            if owed.isEmpty {
                Label("都付了。", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(owed.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { InsetDivider() }
                        owedRow(person)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            }
        }
    }

    private func owedRow(_ person: GroupLedger.Owed) -> some View {
        let count = String(localized: "\(person.sessions) 场")
        return HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: person.name)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    if person.guest {
                        TagPill(text: String(localized: "访客"), fill: AppTheme.Colors.mint)
                    }
                }
                Text(verbatim: "\(count) · \(FeeText.text(person.amount))")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Button("标成已付") { markPaid(person) }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                .disabled(busy != nil)
        }
        .frame(minHeight: 64)
    }

    // MARK: 开过的场次

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("开过的场次")
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(sessions) { session in
                Button {
                    router.open(.sessionPayments(sessionId: session.id))
                } label: {
                    sessionRow(session)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
            if !reachedEnd && sessions.count >= GroupLedger.pageSize {
                Button("看更早的场次") { loadEarlier() }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                    .disabled(busy != nil)
            }
        }
    }

    private func sessionRow(_ session: GroupLedger.Session) -> some View {
        let all = session.owes > 0 && session.paid >= session.owes
        return HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: TimeSlot(date: session.startsAt, startTime: session.startsAt, endTime: session.endsAt).formattedFull)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text(verbatim: [FeeText.price(session.amount) ?? String(localized: "没写金额"), session.venue].joined(separator: " · "))
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if session.owes > 0 {
                TagPill(text: String(localized: "已付 \(session.paid)/\(session.owes)"), icon: all ? "checkmark" : nil,
                        fill: all ? AppTheme.Colors.mint : AppTheme.Colors.butter)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md)
    }

    // MARK: 数据

    private func load() async {
        do {
            ledger = try await appState.backend.remoteGroupLedger(groupId)
            earlier = []
            reachedEnd = false
            failed = false
        } catch {
            if ledger == nil { failed = true }
        }
        if exportFile == nil, let rows = try? await appState.backend.remoteGroupLedgerRows(groupId), !rows.isEmpty {
            exportFile = LedgerExport.write(rows)
        }
    }

    private func loadEarlier() {
        guard let last = sessions.last else { return }
        busy = "more"
        Task {
            defer { busy = nil }
            do {
                let page = try await appState.backend.remoteGroupLedger(groupId, before: last.startsAt)
                earlier += page.sessions
                if page.sessions.count < GroupLedger.pageSize { reachedEnd = true }
            } catch {
                appState.showError(error)
            }
        }
    }

    private func markPaid(_ person: GroupLedger.Owed) {
        busy = person.id
        Task {
            defer { busy = nil }
            do {
                try await appState.backend.remoteMarkSignupsPaid(person.signups, paid: true)
                Haptics.success()
                appState.showToast(String(localized: "已标成已付"), style: .success)
                await load()
            } catch {
                appState.showClubError(error)
            }
        }
    }
}

// MARK: - 导出成表格（CSV）

enum LedgerExport {
    /// 写到临时目录，返回文件地址；日期和时间按球馆当地（2026-11-18、19:00），表格里好排序
    static func write(_ rows: [LedgerRow]) -> URL? {
        let head = [String(localized: "日期"), String(localized: "时间"), String(localized: "球馆"), String(localized: "球友"),
                    String(localized: "访客"), String(localized: "金额"), String(localized: "已付"), String(localized: "自己标的")]
        let lines = rows.map { row -> [String] in
            let paid = row.paidAt.map { local($0, row.tz).date } ?? (row.owes ? "" : String(localized: "不用付"))
            let at = local(row.startsAt, row.tz)
            return [at.date, at.time, row.venue, row.name, row.guest ? String(localized: "访客") : "",
                    row.amount.map(FeeText.plain) ?? "", paid, row.paidSelf ? String(localized: "自己标的") : ""]
        }
        // 带 BOM，Excel 打开中文不乱码
        let csv = "\u{FEFF}" + ([head] + lines).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("badie-payments-\(local(Date(), nil).date).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func cell(_ text: String) -> String {
        text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
    }

    static func local(_ date: Date, _ tz: String?) -> (date: String, time: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH:mm"
        return (day, formatter.string(from: date))
    }
}
