import SwiftUI

// MARK: - 请求状态（卡片上只放状态词）

struct TicketStatus {
    let title: String
    let icon: String
    let tint: Color
    /// 需要我操作（等我确认 / 已暂停）
    let needsAction: Bool

    init(ticket: MatchTicket, offer: MatchOffer?, now: Date = Date()) {
        switch ticket.status {
        case .searching:
            title = ticket.isLastMinute
                ? String(localized: "临时局 · 正在找")
                : String(localized: "在找搭子") + " · " + String(localized: "\(DateText.deadline(ticket.deadline, now: now))前确认")
            icon = "hourglass"
            tint = AppTheme.Colors.sky
            needsAction = false
        case .offered:
            if let offer, let seat = offer.seat(of: ticket.userId), seat.response == .pending {
                title = String(localized: "待你确认") + " · " + MatchTiming.remainingText(until: seat.respondBy, now: now)
                icon = "bolt.fill"
                tint = AppTheme.Colors.lime
                needsAction = true
            } else if let offer, offer.vacantCount > 0 {
                title = String(localized: "补位中")
                icon = "arrow.triangle.2.circlepath"
                tint = AppTheme.Colors.butter
                needsAction = false
            } else {
                let total = offer?.seats.count ?? 2
                title = String(localized: "已确认 \(offer?.acceptedCount ?? 1)/\(total)")
                icon = "checkmark.circle.fill"
                tint = AppTheme.Colors.mint
                needsAction = false
            }
        case .matched:
            title = String(localized: "约成了")
            icon = "sportscourt.fill"
            tint = AppTheme.Colors.lime
            needsAction = false
        case .paused:
            title = String(localized: "已暂停")
            icon = "pause.circle.fill"
            tint = AppTheme.Colors.peach
            needsAction = true
        case .expired:
            title = String(localized: "没约到")
            icon = "clock.badge.xmark"
            tint = AppTheme.Colors.surfaceMuted
            needsAction = false
        case .cancelled:
            title = String(localized: "已取消")
            icon = "xmark.circle.fill"
            tint = AppTheme.Colors.surfaceMuted
            needsAction = false
        }
    }
}

// MARK: - 首页 / 球局页上的请求卡片

struct TicketStatusCard: View {
    let ticket: MatchTicket
    let offer: MatchOffer?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let status = TicketStatus(ticket: ticket, offer: offer, now: context.date)
            // 亮绿底上用固定的深色字（深色模式下 ink 是浅色）
            let ink = status.needsAction ? AppTheme.Colors.onAccent : AppTheme.Colors.ink
            let secondary = status.needsAction ? AppTheme.Colors.onAccent.opacity(0.75) : AppTheme.Colors.inkSecondary
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: status.icon, fill: status.tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("约球请求 · \(ticket.event.title(mode: ticket.mode))")
                        .font(AppTheme.Typography.overline)
                        .tracking(0.6)
                        .foregroundStyle(secondary)
                    Text(ticket.slot.formattedFull)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(ink)
                    Text(status.title)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(status.needsAction ? ink : secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(ink)
            }
            .padding(AppTheme.Spacing.lg)
            .sticker(status.needsAction ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            .accessibilityElement(children: .combine)
            .accessibilityHint("查看这个约球请求")
        }
    }
}

// MARK: - 请求摘要：项目·时间 / 球馆 / 距离·实力差

struct TicketSummaryCard: View {
    let ticket: MatchTicket
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(icon: ticket.mode.icon, tint: AppTheme.Colors.lavender,
                    title: "\(ticket.event.title(mode: ticket.mode)) · \(ticket.slot.formattedFull)")
            InsetDivider()
            InfoRow(icon: "mappin.and.ellipse", tint: AppTheme.Colors.sky, title: venueTitle)
            InsetDivider()
            InfoRow(icon: "arrow.left.and.right", tint: AppTheme.Colors.peach, title: rangeTitle)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private var venueTitle: String {
        let names = locationManager.courts(ids: ticket.courtIds).map(\.name)
        guard let first = names.first else { return String(localized: "\(ticket.courtIds.count) 个球馆") }
        return names.count > 1 ? String(localized: "\(first) 等 \(names.count) 家") : first
    }

    private var rangeTitle: String {
        let radius = DistanceFormatter.radius(km: ticket.radiusKm)
        return ticket.skillTolerance >= MatchRequest.anySkill
            ? String(localized: "\(radius) · 实力不限")
            : String(localized: "\(radius) · 实力差 ±\(ticket.skillTolerance) 级")
    }
}

// MARK: - 请求已挂起，正在找

struct TicketWaitingView: View {
    let ticket: MatchTicket

    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var router: Router
    @State private var confirmsCancel = false

    var body: some View {
        let summary = matchManager.poolSummary(for: ticket)
        VStack(spacing: 0) {
            HStack {
                TagPill(text: ticket.isLastMinute ? String(localized: "临时局 · 正在找") : String(localized: "在找搭子"),
                        icon: "circle.fill", fill: AppTheme.Colors.lime)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭（请求会继续）")) { matchManager.closeFlow() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    Text("找到就通知你")
                        .font(AppTheme.Typography.display)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    TicketSummaryCard(ticket: ticket)

                    HStack(spacing: AppTheme.Spacing.sm) {
                        StatTile(value: "\(summary.available)", label: ticket.isLastMinute ? String(localized: "此刻在找") : String(localized: "那天有空"))
                        StatTile(value: "\(summary.compatible)", label: String(localized: "都合适"))
                    }

                    deadlineTag

                    if !matchManager.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("想快一点")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                                .accessibilityAddTraits(.isHeader)
                            FlowLayout(spacing: AppTheme.Spacing.sm) {
                                ForEach(matchManager.suggestions) { suggestion in
                                    ChoiceChip(title: suggestion.title, icon: suggestion.icon, isSelected: false) {
                                        matchManager.apply(suggestion)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .refreshesEverything()

            VStack(spacing: AppTheme.Spacing.xs) {
                HStack(spacing: AppTheme.Spacing.xl) {
                    Button("修改") { edit() }
                        .buttonStyle(TextActionStyle())
                        .underline()
                        .accessibilityLabel("修改请求")
                    Button("取消") { confirmsCancel = true }
                        .buttonStyle(TextActionStyle())
                        .underline()
                        .accessibilityLabel("取消请求")
                }
                Button("好") { matchManager.closeFlow() }
                    .buttonStyle(.brutal(.inverse))
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        }
        .confirmationDialog("取消这个约球请求？", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("取消请求", role: .destructive) { matchManager.cancelTicket(ticket.id) }
            Button("继续找", role: .cancel) {}
        } message: {
            Text("还没约成，取消不影响任何记录。")
        }
    }

    /// 关掉流程，打开填好原条件的设置页；保存时换掉这个请求
    private func edit() {
        matchManager.prepareEdit(ticket)
        matchManager.closeFlow()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            router.isMatchSetupPresented = true
        }
    }

    /// “周三 17:00前确认” + “?”（确认期限、到点没约成怎么办）
    private var deadlineTag: some View {
        HStack(spacing: 0) {
            TagPill(text: String(localized: "\(DateText.deadline(ticket.deadline))前确认"), icon: "timer",
                    fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
            RulesButton(title: String(localized: "约成规则"), points: deadlinePoints)
        }
    }

    private var deadlinePoints: [String] {
        if ticket.isLastMinute {
            return [
                String(localized: "临时局只找附近此刻也在找人的球友。"),
                String(localized: "找到人后需要在 5–10 分钟内确认，最晚开赛前 20 分钟约成。"),
                String(localized: "到点没约成会自动结束，不计入任何记录。"),
                String(localized: "找到合适的人会马上通知你，不用一直开着 App。")
            ]
        }
        return [
            String(localized: "最晚\(DateText.deadline(ticket.deadline))（开赛前 2 小时）前所有人都要确认，都确认了才算约成。"),
            String(localized: "到点没约成会自动结束，不计入任何记录。"),
            String(localized: "只和也能去这些球馆（或 150 米内同一处）的球友匹配。"),
            String(localized: "找到合适的人会马上通知你，不用一直开着 App。")
        ]
    }
}

// MARK: - 暂停 / 结束 / 取消

struct TicketEndedView: View {
    let ticket: MatchTicket

    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            HStack {
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { matchManager.closeFlow() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)

            Spacer(minLength: 0)
            VStack(spacing: AppTheme.Spacing.xs) {
                EmptyStateView(icon: icon, title: title, tint: tint)
                if !points.isEmpty {
                    RulesButton(title: title, points: points)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            Spacer(minLength: 0)

            VStack(spacing: AppTheme.Spacing.sm) {
                switch ticket.status {
                case .paused:
                    Button("继续找") {
                        Haptics.tap()
                        matchManager.resumeTicket(ticket.id)
                    }
                    .buttonStyle(.brutalPrimary)
                    Button("取消") { matchManager.cancelTicket(ticket.id) }
                        .buttonStyle(TextActionStyle())
                        .accessibilityLabel("取消请求")
                case .expired:
                    if canGoLastMinute {
                        Button {
                            matchManager.retryAsLastMinute(ticket)
                        } label: {
                            ArrowButtonLabel(title: String(localized: "转临时局"))
                        }
                        .buttonStyle(.brutalPrimary)
                    }
                    Button("发起球局") {
                        matchManager.closeFlow()
                        router.open(.createRoom(ticket.mode, invitee: nil), in: .games)
                    }
                    .buttonStyle(canGoLastMinute ? BrutalButtonStyle(kind: .secondary, size: .large) : BrutalButtonStyle(kind: .primary, size: .large))
                default:
                    Button("关闭") { matchManager.closeFlow() }
                        .buttonStyle(.brutalSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
    }

    private var canGoLastMinute: Bool {
        !ticket.isLastMinute && MatchTiming.canRequest(start: ticket.slot.startTime)
    }

    private var icon: String {
        switch ticket.status {
        case .paused: return "pause.circle.fill"
        case .expired: return "clock.badge.xmark"
        default: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        ticket.status == .paused ? AppTheme.Colors.peach : AppTheme.Colors.surfaceMuted
    }

    private var title: String {
        switch ticket.status {
        case .paused: return String(localized: "你错过了一个匹配")
        case .expired: return String(localized: "这次没约到人")
        default: return String(localized: "请求已取消")
        }
    }

    /// 原来写在页面上的说明，收进“?”
    private var points: [String] {
        switch ticket.status {
        case .paused:
            return [
                String(localized: "为了不让别人白等，错过确认的请求会先暂停。"),
                String(localized: "还想打的话点“继续找”，不影响任何记录。")
            ]
        case .expired:
            var list = [
                String(localized: "\(ticket.slot.formattedFull) 到了确认截止时间还没凑齐，请求已结束。"),
                String(localized: "不计入任何记录。")
            ]
            if canGoLastMinute {
                list.append(String(localized: "转临时局：只找此刻也在找人的球友，找到后会替你接受，等对方确认。"))
            }
            list.append(String(localized: "发起球局：发起公开球局，让球友来找你。"))
            return list
        default:
            return []
        }
    }
}
