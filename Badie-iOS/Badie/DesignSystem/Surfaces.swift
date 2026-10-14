import SwiftUI

// MARK: - 贴纸式表面：填充 + 墨色描边 + 硬投影

struct StickerBackground: ViewModifier {
    var fill: Color
    var radius: CGFloat
    var shadow: CGSize
    var strokeColor: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    if shadow != .zero {
                        shape
                            .fill(AppTheme.Colors.shadow)
                            .offset(x: shadow.width, y: shadow.height)
                    }
                    shape.fill(fill)
                    shape.strokeBorder(strokeColor, lineWidth: AppTheme.Stroke.width)
                }
            }
    }
}

extension View {
    /// 贴纸卡片背景（默认白色表面 + 描边 + 右下硬投影）
    func sticker(
        _ fill: Color = AppTheme.Colors.surface,
        radius: CGFloat = AppTheme.Radius.lg,
        shadow: CGSize = AppTheme.Elevation.card,
        stroke: Color = AppTheme.Colors.stroke
    ) -> some View {
        modifier(StickerBackground(fill: fill, radius: radius, shadow: shadow, strokeColor: stroke))
    }

    /// 带内边距的卡片
    func card(
        _ fill: Color = AppTheme.Colors.surface,
        padding: CGFloat = AppTheme.Spacing.lg,
        radius: CGFloat = AppTheme.Radius.lg,
        shadow: CGSize = AppTheme.Elevation.card
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sticker(fill, radius: radius, shadow: shadow)
    }
}

// MARK: - 图标贴片（马卡龙底色 + 描边 + SF Symbol）

struct IconTile: View {
    let systemName: String
    var fill: Color = AppTheme.Colors.lime
    var size: CGFloat = 40
    var iconColor: Color = AppTheme.Colors.onAccent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(iconColor)
            .frame(width: size, height: size)
            .sticker(fill, radius: size * 0.3, shadow: .zero)
            .accessibilityHidden(true)
    }
}

/// 中性图标按钮（导航栏返回、设置等），最小点击区域 44pt
struct IconButton: View {
    let systemName: String
    let accessibilityLabel: String
    /// 传入强调色时图标使用 onAccent，否则为中性表面 + 墨色图标
    var accent: Color?
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent == nil ? AppTheme.Colors.ink : AppTheme.Colors.onAccent)
                .frame(width: 44, height: 44)
                .sticker(accent ?? AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        CountBadge(count: badge)
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(badge > 0 ? "\(badge) 条未读" : "")
    }
}

/// 红色数字角标
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(AppTheme.Colors.dangerFill))
            .overlay(Capsule().strokeBorder(AppTheme.Colors.canvas, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// 按下时轻微缩放的通用按钮样式（用于卡片、图标按钮等）
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(AppTheme.Motion.press, value: configuration.isPressed)
    }
}

// MARK: - 屏幕标题栏（自定义导航栏）

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var showsBack: Bool = true
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .lineLimit(1)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack {
                if showsBack {
                    IconButton(systemName: "chevron.left", accessibilityLabel: "返回") {
                        if let onBack { onBack() } else { dismiss() }
                    }
                }
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.md)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, showsBack: Bool = true, onBack: (() -> Void)? = nil) {
        self.title = title
        self.showsBack = showsBack
        self.onBack = onBack
        self.trailing = { EmptyView() }
    }
}

/// 大标题（Tab 根页面）
struct LargeTitleHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Text(title)
                    .font(AppTheme.Typography.display)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.sm)
    }
}

// MARK: - 分区标题

struct SectionTitle: View {
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .frame(minHeight: 44)
            }
        }
    }
}

// MARK: - 统计格

struct StatTile: View {
    let value: String
    let label: String
    /// 传入强调色时文字使用 onAccent
    var accent: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .scaledFont(size: 24, relativeTo: .title2)
                .foregroundStyle(accent == nil ? AppTheme.Colors.ink : AppTheme.Colors.onAccent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(accent == nil ? AppTheme.Colors.inkSecondary : AppTheme.Colors.onAccent.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(accent ?? AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

// MARK: - 信息行（图标贴片 + 标题 + 说明）

struct InfoRow<Trailing: View>: View {
    let icon: String
    var tint: Color = AppTheme.Colors.sky
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            IconTile(systemName: icon, fill: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

extension InfoRow where Trailing == EmptyView {
    init(icon: String, tint: Color = AppTheme.Colors.sky, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// 列表菜单行（我的页面等）
struct MenuRow: View {
    let icon: String
    var tint: Color = AppTheme.Colors.lavender
    let title: String
    var value: String?
    var badge: Int = 0
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: icon, fill: tint, size: 34)
                Text(title)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(isDestructive ? AppTheme.Colors.danger : AppTheme.Colors.ink)
                Spacer()
                if badge > 0 {
                    CountBadge(count: badge)
                }
                if let value {
                    Text(value)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 卡片内分割线
struct InsetDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.Colors.divider)
            .frame(height: AppTheme.Stroke.hairline)
    }
}
