import SwiftUI

// MARK: - 球局票据卡（首页“下一场”、详情页头部）

struct GameTicketCard: View {
    let game: Game
    let players: [User]
    var currentUserId: String?
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: compact ? AppTheme.Spacing.sm : AppTheme.Spacing.md) {
            HStack {
                Text("\(game.mode.title) · \(game.statusText)")
                    .font(AppTheme.Typography.overline)
                    .tracking(0.8)
                Spacer()
                statusChip(now: now)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(DateText.time(game.slot.startTime))
                    .scaledFont(size: compact ? 34 : 44)
                Text("–\(DateText.time(game.slot.endTime))")
                    .scaledFont(size: compact ? 18 : 22, relativeTo: .title3)
            }
            .monospacedDigit()
            Text(game.slot.formattedDate)
                .font(AppTheme.Typography.bodyBold)
            DashedDivider()
                .padding(.vertical, compact ? 2 : AppTheme.Spacing.xs)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.court.name)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(1)
                Text(game.court.address)
                    .font(AppTheme.Typography.footnote)
                    .opacity(0.75)
                    .lineLimit(1)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                AvatarStack(users: players, size: compact ? 30 : 36)
                Text(playersText)
                    .font(AppTheme.Typography.footnoteBold)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !compact, game.cost.perPerson != nil {
                    Text(game.cost.perPersonText)
                        .font(AppTheme.Typography.headline)
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .padding(compact ? AppTheme.Spacing.lg : AppTheme.Spacing.xl)
        .background {
            let shape = TicketShape(notchPosition: compact ? 0.52 : 0.55)
            ZStack {
                shape
                    .fill(AppTheme.Colors.shadow)
                    .offset(x: 3, y: 4)
                shape
                    .fill(tint)
                shape
                    .strokeBorder(AppTheme.Colors.stroke, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.mode.title)球局，\(game.slot.formattedFull)，\(game.court.name)，\(playersText)")
    }

    private var tint: Color {
        switch game.status {
        case .confirmed: return AppTheme.Colors.peach
        case .completed: return AppTheme.Colors.mint
        case .cancelled: return AppTheme.Colors.surfaceMuted
        }
    }

    private var playersText: String {
        let others = players.filter { $0.id != currentUserId }.map(\.nickname)
        guard !others.isEmpty else { return "等待球友加入" }
        if others.count == 1 { return "你和 \(others[0])" }
        return "你和 \(others.prefix(2).joined(separator: "、"))\(others.count > 2 ? " 等 \(others.count) 人" : "")"
    }

    @ViewBuilder
    private func statusChip(now: Date) -> some View {
        switch game.status {
        case .confirmed:
            if game.isInProgress(now: now) {
                chip("进行中", fill: AppTheme.Colors.lime)
            } else if game.slot.endTime <= now {
                chip("待完成", fill: AppTheme.Colors.butter)
            } else {
                chip(DateText.countdown(to: game.slot.startTime, now: now), fill: Color(hex: 0x17140F), foreground: AppTheme.Colors.lime)
            }
        case .completed:
            chip(game.result?.didWin == true ? "赢了 🎉" : "已完成", fill: AppTheme.Colors.surface)
        case .cancelled:
            chip(game.cancelledLate ? "临时取消" : "已取消", fill: AppTheme.Colors.surface)
        }
    }

    private func chip(_ text: String, fill: Color, foreground: Color = AppTheme.Colors.onAccent) -> some View {
        Text(text)
            .font(AppTheme.Typography.caption.weight(.heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color(hex: 0x17140F), lineWidth: 1.5))
    }
}

// MARK: - 列表行卡片

struct GameRowCard: View {
    let game: Game
    let players: [User]
    var currentUserId: String?
    var pendingSurveyCount = 0

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(spacing: 0) {
                Text(DateText.weekday(game.slot.startTime))
                    .font(AppTheme.Typography.caption)
                Text("\(Calendar.current.component(.day, from: game.slot.startTime))")
                    .scaledFont(size: 24, relativeTo: .title2)
                    .monospacedDigit()
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            .frame(width: 56, height: 62)
            .sticker(tint, radius: 14, shadow: .zero)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(game.mode.title) · \(game.slot.formattedTimeRange)")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                    if game.status == .cancelled {
                        TagPill(text: game.cancelledLate ? "临时取消" : "已取消", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
                    }
                }
                Text(game.court.name)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    AvatarStack(users: players.filter { $0.id != currentUserId }, size: 24)
                    if pendingSurveyCount > 0 {
                        TagPill(text: "待评价 \(pendingSurveyCount)", icon: "star.fill", fill: AppTheme.Colors.pink)
                    } else if let result = game.result, game.status == .completed {
                        Text(result.didWin == true ? "胜 \(result.score)" : (result.didWin == false ? "负 \(result.score)" : result.score))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch game.status {
        case .confirmed: return AppTheme.Colors.peach
        case .completed: return AppTheme.Colors.mint
        case .cancelled: return AppTheme.Colors.surfaceMuted
        }
    }
}
