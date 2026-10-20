import SwiftUI

// MARK: - 公开球局卡片（“我有场地缺人”）

struct PublicRoomCard: View {
    let room: Room
    var distanceText: String?
    var currentUserId: String?
    var width: CGFloat? = 270

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                TagPill(text: room.mode.title, icon: room.mode.icon, fill: AppTheme.Colors.lavender)
                TagPill(text: room.levelRangeText, fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
                if let event = room.event {
                    TagPill(text: event.title(mode: room.mode), fill: AppTheme.Colors.peach)
                }
                Spacer(minLength: 0)
                seatsBadge
            }
            if let slot = room.slot {
                Text("\(slot.formattedDate)")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Text(slot.formattedTimeRange)
                    .scaledFont(size: 24, relativeTo: .title2)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            if let court = room.court {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .bold))
                    Text(court.name)
                        .lineLimit(1)
                    if let distanceText {
                        Text("· \(distanceText)")
                    }
                }
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                HStack(spacing: -8) {
                    ForEach(room.participants) { participant in
                        if participant.isAnonymous {
                            // 还没加入的公开局看不到是谁
                            Image(systemName: "person.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppTheme.Colors.surfaceMuted))
                                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
                        } else {
                            AvatarView(participant: participant, size: 28)
                        }
                    }
                    ForEach(0..<room.openSeats, id: \.self) { _ in
                        Circle()
                            .strokeBorder(AppTheme.Colors.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .background(Circle().fill(AppTheme.Colors.surface))
                            .frame(width: 28, height: 28)
                    }
                }
                Spacer(minLength: 0)
                if let cost = room.costEstimate, cost.perPerson != nil {
                    Text(cost.perPersonText)
                        .font(AppTheme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.ink)
                }
            }
            if !room.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(room.tags.prefix(2)) { tag in
                        TagPill(text: tag.title, icon: tag.icon, fill: AppTheme.Colors.mint)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var seatsBadge: some View {
        if let me = currentUserId, room.contains(me) {
            TagPill(text: String(localized: "已加入"), icon: "checkmark", fill: AppTheme.Colors.lime)
        } else if let me = currentUserId, room.isWaitlisted(me) {
            TagPill(text: String(localized: "候补中"), fill: AppTheme.Colors.butter)
        } else if room.isFull {
            TagPill(text: String(localized: "满员·可候补"), fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
        } else {
            TagPill(text: String(localized: "缺 \(room.openSeats) 人"), fill: AppTheme.Colors.pink)
        }
    }

    private var accessibilityText: String {
        var parts = [String(localized: "\(room.mode.title)球局"), room.levelRangeText]
        if let event = room.event { parts.append(event.title(mode: room.mode)) }
        if let slot = room.slot { parts.append(slot.formattedFull) }
        if let court = room.court { parts.append(court.name) }
        parts.append(room.isFull ? String(localized: "已满员") : String(localized: "还缺 \(room.openSeats) 人"))
        if let cost = room.costEstimate, cost.perPerson != nil { parts.append(String(localized: "约 \(cost.perPersonText)")) }
        return parts.joined(separator: "，")
    }
}
