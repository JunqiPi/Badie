import SwiftUI

// MARK: - 主按钮样式：描边 + 垂直硬投影，按下时“压平”（触感反馈的视觉版本）

struct BrutalButtonStyle: ButtonStyle {
    enum Kind {
        /// 柠檬绿，页面最重要的行动
        case primary
        /// 墨色（深色模式为米白），次重要的强行动
        case inverse
        /// 白色表面，次要行动
        case secondary
        /// 危险操作
        case destructive
        /// 自定义马卡龙色
        case accent(Color)
    }

    enum Size {
        case large, medium, small

        var minHeight: CGFloat {
            switch self {
            case .large: return 56
            case .medium: return 46
            case .small: return 36
            }
        }

        var font: Font {
            switch self {
            case .large: return AppTheme.Typography.headline
            case .medium: return AppTheme.Typography.subheadlineBold
            case .small: return AppTheme.Typography.footnoteBold
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .large: return AppTheme.Spacing.xl
            case .medium: return AppTheme.Spacing.lg
            case .small: return AppTheme.Spacing.md
            }
        }

        var radius: CGFloat {
            switch self {
            case .large: return 18
            case .medium: return 14
            case .small: return 12
            }
        }

        var depth: CGFloat {
            switch self {
            case .large: return AppTheme.Elevation.buttonDepth
            case .medium: return 3
            case .small: return 2
            }
        }
    }

    var kind: Kind = .primary
    var size: Size = .large
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        BrutalButtonBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }
}

private struct BrutalButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: BrutalButtonStyle.Kind
    let size: BrutalButtonStyle.Size
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        let depth = isEnabled ? size.depth : 0

        configuration.label
            .font(size.font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
            .contentShape(shape)
            .offset(y: pressed ? depth : 0)
            .background(shape.fill(AppTheme.Colors.shadow).offset(y: depth))
            .animation(AppTheme.Motion.press, value: pressed)
    }

    private var fill: Color {
        guard isEnabled else { return AppTheme.Colors.surfaceMuted }
        switch kind {
        case .primary: return AppTheme.Colors.lime
        case .inverse: return AppTheme.Colors.inverse
        case .secondary: return AppTheme.Colors.surface
        case .destructive: return AppTheme.Colors.dangerFill
        case .accent(let color): return color
        }
    }

    private var foreground: Color {
        guard isEnabled else { return AppTheme.Colors.inkTertiary }
        switch kind {
        case .primary, .accent: return AppTheme.Colors.onAccent
        case .inverse: return AppTheme.Colors.onInverse
        case .secondary: return AppTheme.Colors.ink
        case .destructive: return .white
        }
    }
}

extension ButtonStyle where Self == BrutalButtonStyle {
    static var brutalPrimary: BrutalButtonStyle { BrutalButtonStyle(kind: .primary) }
    static var brutalInverse: BrutalButtonStyle { BrutalButtonStyle(kind: .inverse) }
    static var brutalSecondary: BrutalButtonStyle { BrutalButtonStyle(kind: .secondary) }

    static func brutal(
        _ kind: BrutalButtonStyle.Kind = .primary,
        size: BrutalButtonStyle.Size = .large,
        fullWidth: Bool = true
    ) -> BrutalButtonStyle {
        BrutalButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

// MARK: - 文字按钮（低强调）

struct TextActionStyle: ButtonStyle {
    var color: Color = AppTheme.Colors.inkSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.subheadlineBold)
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - 行动按钮内容：文字 + 右侧圆角箭头块（参考 "Save and Continue" 样式）

struct ArrowButtonLabel: View {
    let title: String
    var arrowFill: Color = AppTheme.Colors.lime

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: AppTheme.Spacing.sm)
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(AppTheme.Colors.onAccent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(arrowFill))
        }
    }
}
