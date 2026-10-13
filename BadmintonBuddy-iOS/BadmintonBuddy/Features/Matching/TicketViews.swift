import SwiftUI

// MARK: - 请求状态文案

struct TicketStatus {
    let title: String
    let icon: String
    let tint: Color
    /// 需要我操作（等我确认 / 已暂停）
    let needsAction: Bool

    init(ticket: MatchTicket, offer: MatchOffer?, now: Date = Date()) {
        switch ticket.status {
        case .searching:
            title = ticket.isLastMinute ? "临时局 · 正在找附近的人" : "正在找 · 最晚 \(DateText.time(ticket.deadline)) 前约成"
            icon = "hourglass"
            tint = AppTheme.Colors.sky
            needsAction = false
        case .offered:
            if let offer, let seat = offer.seat(of: ticket.userId), seat.response == .pending {
                title = "找到搭子了，等你确认 · \(MatchTiming.remainingText(until: seat.respondBy, now: now))"
                icon = "bolt.fill"
                tint = AppTheme.Colors.lime
                needsAction = true
            } else if let offer, offer.vacantCount > 0 {
                title = "有人来不了，正在找人补位"
                icon = "arrow.triangle.2.circlepath"
                tint = AppTheme.Colors.butter
                needsAction = false
            } else {
                let total = offer?.seats.count ?? 2
                title = "已确认，等其他人（\(offer?.acceptedCount ?? 1)/\(total)）"
                icon = "checkmark.circle.fill"
                tint = AppTheme.Colors.mint
                needsAction = false
            }
        case .matched:
            title = "约成了"
            icon = "sportscourt.fill"
            tint = AppTheme.Colors.lime
            needsAction = false
        case .paused:
            title = "错过了确认，已暂停 · 点开继续找"
            icon = "pause.circle.fill"
            tint = AppTheme.Colors.peach
            needsAction = true
        case .expired:
            title = "这次没约到人，已结束"
            icon = "clock.badge.xmark"
            tint = AppTheme.Colors.surfaceMuted
            needsAction = false
        case .cancelled:
            title = "已取消"
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
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: status.icon, fill: status.tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("约球请求 · \(ticket.mode.title)")
                        .font(AppTheme.Typography.overline)
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    Text(ticket.slot.formattedFull)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text(status.title)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(status.needsAction ? AppTheme.Colors.ink : AppTheme.Colors.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            .padding(AppTheme.Spacing.lg)
            .sticker(status.needsAction ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            .accessibilityElement(children: .combine)
            .accessibilityHint("查看这个约球请求")
        }
    }
}

// MARK: - 请求摘要（模式、时间、球馆、条件）

struct TicketSummaryCard: View {
    let ticket: MatchTicket
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(icon: ticket.mode.icon, tint: AppTheme.Colors.lavender,
                    title: "\(ticket.mode.title) · \(ticket.slot.formattedFull)",
                    subtitle: ticket.skillTolerance >= MatchRequest.anySkill ? "不限水平" : "水平相差 ±\(ticket.skillTolerance) 级以内")
            InsetDivider()
            InfoRow(icon: "mappin.and.ellipse", tint: AppTheme.Colors.sky,
                    title: venueTitle,
                    subtitle: "只和也能去这些球馆（或 150 米内同一处）的球友匹配")
            InsetDivider()
            InfoRow(icon: "location.circle.fill", tint: AppTheme.Colors.peach,
                    title: "\(DistanceFormatter.radius(km: ticket.radiusKm)) 内的球友",
                    subtitle: ticket.isLastMinute ? "临时局只找附近此刻也在找人的球友" : nil)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private var venueTitle: String {
        let names = locationManager.courts(ids: ticket.courtIds).map(\.name)
        guard let first = names.first else { return "\(ticket.courtIds.count) 个球馆" }
        return names.count > 1 ? "\(first) 等 \(names.count) 个球馆" : first
    }
}

// MARK: - 请求已挂起，正在找

struct TicketWaitingView: View {
    let ticket: MatchTicket

    @EnvironmentObject private var matchManager: MatchManager
    @State private var confirmsCancel = false

    var body: some View {
        let summary = matchManager.poolSummary(for: ticket)
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭（请求会继续）") { matchManager.closeFlow() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        TagPill(text: ticket.isLastMinute ? "临时局 · 正在找" : "后台匹配中",
                                icon: "dot.radiowaves.left.and.right", fill: AppTheme.Colors.lime)
                        (Text("已经在帮你\n") + Text(markedText: "找搭子") + Text("了"))
                            .font(AppTheme.Typography.display)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("找到合适的人会马上通知你，不用一直开着 App。所有人都确认后才算约成。")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TicketSummaryCard(ticket: ticket)

                    HStack(spacing: AppTheme.Spacing.sm) {
                        StatTile(value: "\(summary.available)", label: ticket.isLastMinute ? "附近正在找人" : "附近那天有空")
                        StatTile(value: "\(summary.compatible)", label: "条件都合适")
                    }

                    timingNote

                    if !matchManager.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("想快一点？这些调整现在就能找到人")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                            ForEach(matchManager.suggestions) { suggestion in
                                Button {
                                    Haptics.tap()
                                    matchManager.apply(suggestion)
                                } label: {
                                    HStack(spacing: AppTheme.Spacing.md) {
                                        IconTile(systemName: suggestion.icon, fill: AppTheme.Colors.lime, size: 40)
                                        Text(suggestion.title)
                                            .font(AppTheme.Typography.bodyBold)
                                            .foregroundStyle(AppTheme.Colors.ink)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundStyle(AppTheme.Colors.ink)
                                    }
                                    .padding(AppTheme.Spacing.md)
                                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: AppTheme.Elevation.low)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }

            VStack(spacing: AppTheme.Spacing.xs) {
                Button("好的，有消息通知我") { matchManager.closeFlow() }
                    .buttonStyle(.brutalPrimary)
                Button("取消请求") { confirmsCancel = true }
                    .buttonStyle(TextActionStyle())
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

    private var timingNote: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.Colors.ink)
            Text(ticket.isLastMinute
                 ? "临时局：找到人后需要在 5–10 分钟内确认，最晚开赛前 20 分钟约成。到点没约成会自动结束，不计入任何记录。"
                 : "最晚 \(DateText.time(ticket.deadline))（开赛前 2 小时）前所有人都要确认。到点没约成会自动结束，不计入任何记录。")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.Colors.surfaceMuted))
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
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") { matchManager.closeFlow() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)

            Spacer(minLength: 0)
            EmptyStateView(icon: icon, title: title, message: message, tint: tint)
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
                    Button("取消请求") { matchManager.cancelTicket(ticket.id) }
                        .buttonStyle(TextActionStyle())
                case .expired:
                    if canGoLastMinute {
                        Button {
                            matchManager.retryAsLastMinute(ticket)
                        } label: {
                            ArrowButtonLabel(title: "转为临时局继续找")
                        }
                        .buttonStyle(.brutalPrimary)
                        Text("只找 \(DistanceFormatter.radius(km: MatchTiming.lastMinuteRadiusKm)) 内此刻也在找人的球友，找到后会替你接受，等对方确认")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                            .multilineTextAlignment(.center)
                    }
                    Button("发起公开球局，让球友来找你") {
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
        case .paused: return "你错过了一个匹配"
        case .expired: return "这次没约到人"
        default: return "请求已取消"
        }
    }

    private var message: String {
        switch ticket.status {
        case .paused:
            return "为了不让别人白等，这个请求先暂停了。还想打的话点“继续找”，不影响任何记录。"
        case .expired:
            return "\(ticket.slot.formattedFull) 到了确认截止时间还没凑齐，请求已结束，不计入任何记录。"
        default:
            return "随时可以重新发起。"
        }
    }
}
