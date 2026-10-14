import SwiftUI

// MARK: - 头像

struct AvatarView: View {
    let text: String
    var paletteIndex: Int = 0
    var size: CGFloat = 44
    /// 本人照片（可选）
    var image: UIImage?
    var showsBorder = true

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.Colors.paletteColor(paletteIndex))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(text)
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showsBorder {
                Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: size >= 56 ? 2.5 : 2)
            }
        }
        .accessibilityHidden(true)
    }
}

extension AvatarView {
    init(user: User, size: CGFloat = 44, image: UIImage? = nil) {
        self.init(text: user.avatarText, paletteIndex: user.avatar.paletteIndex, size: size, image: image)
    }

    init(participant: RoomParticipant, size: CGFloat = 44) {
        self.init(text: participant.avatarText, paletteIndex: participant.avatar.paletteIndex, size: size)
    }
}

/// 当前用户头像（自动读取本地照片）
struct MyAvatarView: View {
    @EnvironmentObject private var appState: AppState
    var size: CGFloat = 44
    /// 变更后强制刷新
    var refreshToken: Int = 0

    var body: some View {
        if let user = appState.currentUser {
            AvatarView(user: user, size: size, image: AvatarStore.image(for: user.id))
                .id(refreshToken)
        } else {
            AvatarView(text: "🏸", size: size)
        }
    }
}

/// 重叠头像组
struct AvatarStack: View {
    let users: [User]
    var size: CGFloat = 32
    var maxCount = 4

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(users.prefix(maxCount).enumerated()), id: \.element.id) { index, user in
                AvatarView(user: user, size: size)
                    .zIndex(Double(maxCount - index))
            }
            if users.count > maxCount {
                Text("+\(users.count - maxCount)")
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(width: size, height: size)
                    .background(Circle().fill(AppTheme.Colors.surfaceMuted))
                    .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(users.map(\.nickname).joined(separator: "、"))
    }
}

// MARK: - 等级徽章

struct LevelBadge: View {
    let tier: SkillTier
    var showsName = true
    var compact = false

    init(tier: SkillTier, showsName: Bool = true, compact: Bool = false) {
        self.tier = tier
        self.showsName = showsName
        self.compact = compact
    }

    init(level: Int, showsName: Bool = true, compact: Bool = false) {
        self.init(tier: SkillTier(level: level), showsName: showsName, compact: compact)
    }

    var body: some View {
        Text(showsName ? tier.displayText : tier.text)
            .font(compact ? .system(size: 10, weight: .heavy, design: .rounded) : AppTheme.Typography.caption.weight(.heavy))
            .foregroundStyle(AppTheme.Colors.lime)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 1.5 : 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: 0x17140F)))
            .accessibilityLabel("等级 \(tier.spokenText)，\(tier.name)")
    }
}

/// 小标签（新球友、已认证等）
struct TagPill: View {
    let text: String
    var icon: String?
    var fill: Color = AppTheme.Colors.surface
    var foreground: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(AppTheme.Typography.caption.weight(.bold))
        .foregroundStyle(foreground ?? AppTheme.Colors.onAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
        .fixedSize()
    }
}

struct NewPlayerBadge: View {
    var body: some View {
        TagPill(text: "新球友 · 待校准", icon: "sparkles", fill: AppTheme.Colors.butter)
            .accessibilityLabel("新球友，评价不足 5 次，水平待校准")
    }
}

/// “靠谱”徽章：只看客观履约记录（打满 3 场、没有爽约、临时取消 ≤1 次）
struct ReliableBadge: View {
    var body: some View {
        TagPill(text: "靠谱", icon: "checkmark.shield.fill", fill: AppTheme.Colors.mint)
            .accessibilityLabel("靠谱：打满 3 场，没有爽约")
    }
}

/// 球友给得最多的正面标签（月度快照）；没有达到展示门槛时显示说明
struct PraiseTagsView: View {
    let tags: [SurveyTag]
    var emptyText: String? = "5 位以上球友评价后显示"

    var body: some View {
        if tags.isEmpty {
            if let emptyText {
                Text(emptyText)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        } else {
            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    TagPill(text: tag.rawValue, icon: "hand.thumbsup.fill", fill: AppTheme.Colors.lime)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("球友印象：" + tags.map(\.rawValue).joined(separator: "、"))
        }
    }
}

struct VerifiedBadge: View {
    let status: VerificationStatus

    var body: some View {
        if let text = status.badgeText {
            TagPill(text: text, icon: "checkmark.seal.fill", fill: AppTheme.Colors.lime)
        }
    }
}

// MARK: - 选择胶囊

struct ChoiceChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    var tint: Color = AppTheme.Colors.lime
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(AppTheme.Typography.footnoteBold)
            .foregroundStyle(isSelected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(Capsule().fill(isSelected ? tint : AppTheme.Colors.surface))
            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// 贴纸式分段控件
struct SegmentedSticker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var badge: (Option) -> Int = { _ in 0 }

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    Haptics.selection()
                    withAnimation(AppTheme.Motion.standard) { selection = option }
                } label: {
                    HStack(spacing: 6) {
                        Text(title(option))
                        if badge(option) > 0 {
                            CountBadge(count: badge(option))
                        }
                    }
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(selected ? AppTheme.Colors.onInverse : AppTheme.Colors.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.Colors.inverse)
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .sticker(AppTheme.Colors.surface, radius: 16, shadow: .zero)
    }
}

// MARK: - 评分（星级）

struct RatingPicker: View {
    @Binding var rating: Int
    var maximum = 5

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(1...maximum, id: \.self) { value in
                Button {
                    Haptics.selection()
                    rating = value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(value <= rating ? AppTheme.Colors.star : AppTheme.Colors.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .accessibilityLabel("\(value) 星")
                .accessibilityAddTraits(value == rating ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}
