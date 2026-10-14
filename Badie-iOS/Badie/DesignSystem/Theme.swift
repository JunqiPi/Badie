import SwiftUI
import UIKit

// MARK: - 设计系统 "Court Pop"
// 米白球场底 · 墨色描边 · 硬投影 · 荧光柠檬主色 · 马卡龙贴纸辅色
// 设计依据见 docs/DESIGN.md。所有颜色均为浅色/深色自适应；
// 文字对比度：ink/canvas ≈ 16:1，inkSecondary/canvas ≈ 6.5:1（WCAG AA ≥ 4.5:1）。
// 规则：柠檬绿只作“填充色”，上面的文字永远用 onAccent（墨色），从不把柠檬绿当文字色用在浅色底上。

enum AppTheme {

    // MARK: - 颜色
    enum Colors {
        // 画布与表面
        static let canvas = Color.dynamic(light: 0xF5F0E6, dark: 0x16131D)
        static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x221E2B)
        static let surfaceMuted = Color.dynamic(light: 0xEDE6D8, dark: 0x2C2737)
        static let divider = Color.dynamic(light: 0xE6DFD0, dark: 0x332D40)

        // 文字（墨色体系）
        static let ink = Color.dynamic(light: 0x17140F, dark: 0xF4EFE6)
        static let inkSecondary = Color.dynamic(light: 0x5B554B, dark: 0xB9B2A6)
        /// 仅用于禁用态、装饰性或大号文字（对比度约 3:1）
        static let inkTertiary = Color.dynamic(light: 0x8C8579, dark: 0x857D90)

        // 描边与硬投影
        static let stroke = Color.dynamic(light: 0x17140F, dark: 0x756A90)
        static let shadow = Color.dynamic(light: 0x17140F, dark: 0x07060A)

        /// 强调色（柠檬/马卡龙）上的文字与图标颜色，深浅模式一致
        static let onAccent = Color(hex: 0x17140F)
        /// 反色按钮（浅色模式为墨色，深色模式为米白）
        static let inverse = Color.dynamic(light: 0x17140F, dark: 0xF4EFE6)
        static let onInverse = Color.dynamic(light: 0xF5F0E6, dark: 0x17140F)

        // 主色与贴纸辅色
        static let lime = Color(hex: 0xD4F33F)
        static let lavender = Color.dynamic(light: 0xC8BEFF, dark: 0xB3A6FF)
        static let peach = Color.dynamic(light: 0xFFC98F, dark: 0xF5B97A)
        static let pink = Color.dynamic(light: 0xFFB3CF, dark: 0xF79CC0)
        static let sky = Color.dynamic(light: 0xA8D8FF, dark: 0x8EC8F5)
        static let butter = Color.dynamic(light: 0xFFE36E, dark: 0xF2D45C)
        static let mint = Color.dynamic(light: 0x9FE8C3, dark: 0x86D9B0)

        // 语义色（文字可用）
        static let danger = Color.dynamic(light: 0xC92A2F, dark: 0xFF6B6E)
        static let dangerFill = Color(hex: 0xD22F35)
        static let success = Color.dynamic(light: 0x1F7A47, dark: 0x5BD38F)
        static let star = Color(hex: 0xFFB800)

        /// 头像/贴纸调色板（按用户 ID 稳定取色）
        static let palette: [Color] = [lavender, sky, peach, mint, butter, pink]

        static func paletteColor(_ index: Int) -> Color {
            palette[((index % palette.count) + palette.count) % palette.count]
        }
    }

    // MARK: - 字体（全部基于系统文本样式，支持动态字体）
    enum Typography {
        static let display = Font.system(.largeTitle, design: .rounded, weight: .black)
        static let title = Font.system(.title, design: .rounded, weight: .heavy)
        static let title2 = Font.system(.title2, design: .rounded, weight: .heavy)
        static let title3 = Font.system(.title3, design: .rounded, weight: .bold)
        static let headline = Font.system(.headline, design: .rounded, weight: .bold)
        static let body = Font.system(.body, design: .rounded, weight: .medium)
        static let bodyBold = Font.system(.body, design: .rounded, weight: .bold)
        static let callout = Font.system(.callout, design: .rounded, weight: .medium)
        static let subheadline = Font.system(.subheadline, design: .rounded, weight: .medium)
        static let subheadlineBold = Font.system(.subheadline, design: .rounded, weight: .bold)
        static let footnote = Font.system(.footnote, design: .rounded, weight: .medium)
        static let footnoteBold = Font.system(.footnote, design: .rounded, weight: .bold)
        static let caption = Font.system(.caption, design: .rounded, weight: .semibold)
        static let overline = Font.system(.caption2, design: .rounded, weight: .heavy)
    }

    // MARK: - 间距（4pt 栅格）
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        /// 页面左右边距
        static let screen: CGFloat = 20
        /// 为悬浮标签栏预留的底部空间
        static let tabBarClearance: CGFloat = 110
    }

    // MARK: - 圆角
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 26
    }

    // MARK: - 描边与硬投影
    enum Stroke {
        static let width: CGFloat = 2
        static let hairline: CGFloat = 1.5
    }

    enum Elevation {
        /// 卡片/贴纸：右下硬投影
        static let card = CGSize(width: 3, height: 4)
        /// 小元素
        static let low = CGSize(width: 2, height: 2)
        /// 按钮：垂直投影，按下时“压平”
        static let buttonDepth: CGFloat = 4
    }

    // MARK: - 动效
    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.78)
        static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.6)
        static let gentle = Animation.easeInOut(duration: 0.3)
        static let collision: Double = 0.7
    }
}

// MARK: - Color helpers

extension Color {
    /// 由 0xRRGGBB 创建颜色
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// 浅色/深色自适应颜色
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 可缩放的固定字号（大数字等，跟随动态字体缩放）

struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// 使用随动态字体缩放的固定字号
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .black,
        design: Font.Design = .rounded,
        relativeTo textStyle: Font.TextStyle = .largeTitle
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}
