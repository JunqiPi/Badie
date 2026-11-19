import SwiftUI
import SafariServices

extension AppState {
    /// 当晚页和比赛页的报错：not_allowed 在别处是约球的意思，这里说清楚是谁能做
    func showClubError(_ error: Error) {
        if let remote = error as? RemoteError, remote == .server("not_allowed") {
            showToast(String(localized: "只有组织者和帮手能做这一步。"), style: .error)
        } else {
            showError(error)
        }
    }
}

// MARK: - 球群页场次行上的当天按钮
// 组织者、帮手：“排场”（柠檬绿，进当晚页）；结束后还有人没付：“收款 · n 人没付”。
// 球员：开场后“报名 / 已报名”换成“看排场”，要付钱的人换成“付给 Kevin · $12”（一行只有一个按钮）

/// 球员的按钮：付钱或看排场（换掉报名按钮）
struct TonightPlayerButton: View {
    let item: GroupTonight
    let groupId: String

    @EnvironmentObject private var groupManager: GroupManager

    @State private var showsPay = false
    @State private var board: BoardLink?
    /// 刚在付款半屏里点了“我付了”（等下次拉到新数据之前先这样显示）
    @State private var paidHere: Bool?

    /// 组织者、帮手有“排场”，不用换掉报名按钮
    static func replacesSignup(_ item: GroupTonight) -> Bool {
        item.pay != nil || (item.board != nil && item.canRun != true)
    }

    var body: some View {
        if let pay = item.pay {
            Button(payTitle(pay)) { showsPay = true }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                .sheet(isPresented: $showsPay) {
                    PaySheet(sessionId: item.id, groupName: groupManager.group(id: groupId)?.name ?? "",
                             startsAt: item.startsAt, endsAt: item.endsAt, pay: pay, paid: paidHere ?? pay.paid) { paid in
                        paidHere = paid
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                }
        } else if let code = item.board, let url = PayLinks.board(code) {
            Button("看排场") { board = BoardLink(url: url) }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                .sheet(item: $board) { link in
                    SafariView(url: link.url)
                        .ignoresSafeArea()
                }
        }
    }

    private func payTitle(_ pay: GroupTonight.Pay) -> String {
        if paidHere ?? pay.paid { return String(localized: "已付") }
        if let amount = pay.amount { return String(localized: "付给 \(pay.to) · \(FeeText.text(amount))") }
        return String(localized: "付给 \(pay.to)")
    }
}

/// 组织者、帮手的按钮：排场；当晚过了还有人没付：收款
struct TonightRunButton: View {
    let item: GroupTonight

    @EnvironmentObject private var router: Router

    var body: some View {
        if item.canRun == true {
            Button {
                router.open(.night(sessionId: item.id, pay: false))
            } label: {
                Label("排场", systemImage: "sportscourt.fill")
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .medium))
        } else if let unpaid = item.unpaid, unpaid > 0 {
            Button(String(localized: "收款 · \(unpaid) 人没付")) {
                router.open(.night(sessionId: item.id, pay: true))
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
        }
    }
}

/// 已经结束、不在“接下来的场次”里的当天场次（还能付钱、收款）
struct TonightPastRow: View {
    let item: GroupTonight
    let groupId: String

    private var hasAction: Bool {
        item.canRun == true || (item.unpaid ?? 0) > 0 || TonightPlayerButton.replacesSignup(item)
    }

    var body: some View {
        if hasAction {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Text(verbatim: TimeSlot(date: item.startsAt, startTime: item.startsAt, endTime: item.endsAt).formattedFull)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Spacer(minLength: 0)
                    if TonightPlayerButton.replacesSignup(item) {
                        TonightPlayerButton(item: item, groupId: groupId)
                    }
                }
                TonightRunButton(item: item)
            }
            .padding(AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md)
        }
    }
}

// MARK: - 球局页最上面的“今晚”卡

struct TonightCard: View {
    let items: [TonightItem]

    @EnvironmentObject private var router: Router
    @State private var board: BoardLink?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(items) { item in
                card(item)
            }
        }
        .sheet(item: $board) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    private func card(_ item: TonightItem) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            IconTile(systemName: item.kind == "match" ? "trophy.fill" : "sportscourt.fill",
                     fill: item.status == "court" || item.status == "next" ? AppTheme.Colors.mint : AppTheme.Colors.sky, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("今晚 · \(item.name)")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                Text(verbatim: statusText(item))
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let code = item.boardCode, let url = PayLinks.board(code) {
                Button("看全部") { board = BoardLink(url: url) }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        .contentShape(Rectangle())
        .onTapGesture {
            if let id = item.matchId {
                router.open(.match(id: id))
            } else if let id = item.groupId {
                router.open(.group(id: id))
            }
        }
    }

    private func statusText(_ item: TonightItem) -> String {
        switch item.status {
        case "court": return String(localized: "你在场地 \(item.court ?? 0)")
        case "next": return String(localized: "下一场是你")
        case "resting": return String(localized: "休息中 · 今晚打了 \(item.games ?? 0) 场")
        default: return String(localized: "等候中 · 今晚打了 \(item.games ?? 0) 场")
        }
    }
}

// MARK: - 看板：App 里用内置浏览器打开同一个网页

struct BoardLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// 看板的二维码和链接（立在场边给大家扫）
struct BoardQRSheet: View {
    let url: URL

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            HStack {
                Text("看板")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.top, AppTheme.Spacing.xl)
            QRCodeView(text: url.absoluteString)
                .frame(width: 240, height: 240)
                .padding(AppTheme.Spacing.lg)
                .sticker(.white, radius: AppTheme.Radius.lg)
                .accessibilityLabel("看板二维码")
            Text(verbatim: url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(AppTheme.Colors.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                UIPasteboard.general.string = url.absoluteString
                appState.showToast(String(localized: "已复制链接"), style: .success)
            } label: {
                Label("复制链接", systemImage: "doc.on.doc")
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .showsToasts()
    }
}

// MARK: - 场边用的大按钮、场地号

/// 场地卡上的柠檬绿大按钮（打完了、输比分）：单手按得到
struct BigActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.onAccent)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .frame(width: 96, height: 76)
            .background(shape.fill(AppTheme.Colors.lime))
            .overlay(shape.strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
            .offset(y: configuration.isPressed ? AppTheme.Elevation.buttonDepth : 0)
            .background(shape.fill(AppTheme.Colors.shadow).offset(y: AppTheme.Elevation.buttonDepth))
            .animation(AppTheme.Motion.press, value: configuration.isPressed)
    }
}

/// “场地 2”小牌子
struct CourtTag: View {
    let court: Int

    var body: some View {
        Text("场地 \(court)")
            .font(AppTheme.Typography.footnoteBold)
            .foregroundStyle(AppTheme.Colors.onAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.Colors.sky))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.hairline))
    }
}

/// 场地数：减、几片、加（1–12）
struct CourtStepper: View {
    @Binding var courts: Int

    var body: some View {
        HStack(spacing: 0) {
            Text("场地")
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(AppTheme.Colors.ink)
            Spacer(minLength: 0)
            Button {
                courts = max(1, courts - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 17, weight: .heavy))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(courts <= 1)
            .accessibilityLabel("减少场地")
            Text("\(courts) 片")
                .font(AppTheme.Typography.title3)
                .monospacedDigit()
                .frame(minWidth: 56)
            Button {
                courts = min(12, courts + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .heavy))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(courts >= 12)
            .accessibilityLabel("增加场地")
        }
        .foregroundStyle(AppTheme.Colors.ink)
        .frame(minHeight: 52)
    }
}

/// 一个人的名字胶囊：右边是今晚打了几场（或一个小标记）
struct NameChip: View {
    let name: String
    var count: Int?
    var note: String?
    var fill: Color = AppTheme.Colors.surface
    var dimmed = false

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: name)
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(dimmed ? AppTheme.Colors.inkSecondary : AppTheme.Colors.ink)
                .lineLimit(1)
            if let note {
                Text(verbatim: note)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            if let count {
                Text(verbatim: "\(count)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppTheme.Colors.surfaceMuted))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, count == nil ? 12 : 5)
        .frame(height: 40)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.hairline))
        .contentShape(Capsule())
    }
}
