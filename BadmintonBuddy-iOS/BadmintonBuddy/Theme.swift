import SwiftUI

// MARK: - 设计系统 (Design Tokens)
// 基于原型图配色方案，符合 WCAG 2.1 AA 无障碍标准
// 对比度: 主色/背景 >= 4.5:1

enum AppTheme {
    // MARK: - 颜色
    enum Colors {
        static let primary = Color(hex: "00D4AA")        // 主色 - 青绿
        static let primaryDark = Color(hex: "00B894")    // 主色深
        static let secondary = Color(hex: "6C5CE7")      // 次要色 - 紫
        static let accent = Color(hex: "FD79A8")         // 强调色 - 粉
        
        static let bgDark = Color(hex: "1A1A2E")         // 深色背景
        static let bgCard = Color(hex: "16213E")         // 卡片背景
        static let bgLight = Color(hex: "0F3460")        // 浅色背景
        
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "A0A0A0")
        
        static let success = Color(hex: "00E676")
        static let warning = Color(hex: "FFD93D")
        static let error = Color(hex: "FF6B6B")
        
        // 渐变
        static let primaryGradient = LinearGradient(
            colors: [primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let secondaryGradient = LinearGradient(
            colors: [secondary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let avatarGradient = LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - 字体
    enum Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold)
        static let title = Font.system(size: 24, weight: .semibold)
        static let headline = Font.system(size: 20, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let caption = Font.system(size: 14, weight: .regular)
        static let small = Font.system(size: 12, weight: .regular)
    }
    
    // MARK: - 间距
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - 圆角
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 30
    }
    
    // MARK: - 动画时长 (毫秒)
    enum Animation {
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let collision: Double = 0.7
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
