import SwiftUI

// MARK: - 首页卡片（别人刷到你时看到的那张）

/// 卡片颜色：没传背景照片时，卡片上半部分用这个颜色。和服务器、网站用同一套名字
enum CardColor: String, Codable, CaseIterable, Identifiable {
    case lime, lavender, peach, sky, pink, mint, butter, ink

    var id: String { rawValue }

    var fill: Color {
        switch self {
        case .lime: AppTheme.Colors.lime
        case .lavender: AppTheme.Colors.lavender
        case .peach: AppTheme.Colors.peach
        case .sky: AppTheme.Colors.sky
        case .pink: AppTheme.Colors.pink
        case .mint: AppTheme.Colors.mint
        case .butter: AppTheme.Colors.butter
        case .ink: Color(hex: 0x17140F)
        }
    }

    var name: String {
        switch self {
        case .lime: String(localized: "柠檬绿")
        case .lavender: String(localized: "淡紫")
        case .peach: String(localized: "蜜桃")
        case .sky: String(localized: "天蓝")
        case .pink: String(localized: "粉")
        case .mint: String(localized: "薄荷")
        case .butter: String(localized: "奶黄")
        case .ink: String(localized: "墨黑")
        }
    }

    /// 没选过的人：按用户 ID 给一个浅色（不给墨黑）。网站用同样的算法
    static func `default`(for userId: String) -> CardColor {
        let light = allCases.filter { $0 != .ink }
        return light[userId.stableHash % light.count]
    }
}

extension User {
    var cardColor: CardColor { avatar.cardColor ?? .default(for: id) }
}

/// 卡片上半部分：有背景照片就铺满照片；没有就是卡片颜色 + 白色的球场线
struct CardCover: View {
    let color: CardColor
    let photo: UIImage?

    var body: some View {
        ZStack {
            if let photo {
                Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill() }
            } else {
                color.fill
                CourtLines()
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// 羽毛球场的线（从上往下看，网在中间），铺满给的框
struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func x(_ f: CGFloat) -> CGFloat { rect.minX + rect.width * f }
        func y(_ f: CGFloat) -> CGFloat { rect.minY + rect.height * f }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            path.move(to: CGPoint(x: x(x1), y: y(y1)))
            path.addLine(to: CGPoint(x: x(x2), y: y(y2)))
        }
        path.addRect(rect)
        // 网、两边的前发球线
        line(0, 0.5, 1, 0.5)
        line(0, 0.32, 1, 0.32)
        line(0, 0.68, 1, 0.68)
        // 中线
        line(0.5, 0, 0.5, 0.32)
        line(0.5, 0.68, 0.5, 1)
        // 单打边线
        line(0.08, 0, 0.08, 1)
        line(0.92, 0, 0.92, 1)
        return path
    }
}

/// 发现页的大卡片：上面约四分之三是照片（没照片是卡片颜色 + 球场线），左上角一个白色小标签；
/// 下面一块白色信息区：名字和等级、一行信息、空闲时间
struct CoverCard<Footer: View>: View {
    let user: User?
    /// 左上角：“3.2 公里 · 常去 X” / “周六 14:00–17:00 · 单打”
    let pill: String?
    /// 名字下面一行：“双打 · 靠谱”
    let line: String
    var onProfile: (() -> Void)?
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        VStack(spacing: 0) {
            Group {
                if let user {
                    CardCover(color: user.cardColor, photo: AvatarPhotos.cardImage(userId: user.id, avatar: user.avatar))
                } else {
                    AppTheme.Colors.surfaceMuted
                }
            }
            // 字多（小屏、大字体）时照片让出来
            .frame(minHeight: 0, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if let pill, !pill.isEmpty {
                    Text(pill)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.onAccent)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().strokeBorder(AppTheme.Colors.onAccent, lineWidth: 1.5))
                        .padding(AppTheme.Spacing.md)
                }
            }
            Rectangle()
                .fill(AppTheme.Colors.stroke)
                .frame(height: 3)
            info
                .fixedSize(horizontal: false, vertical: true)
                .background(AppTheme.Colors.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 小屏（iPhone SE）也放得下底部的名字和空闲时间
        .frame(minHeight: 240)
        .contentShape(shape)
        .onTapGesture { onProfile?() }
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("看资料")) { onProfile?() }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let user {
                HStack(spacing: AppTheme.Spacing.sm) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title3)
                    LevelBadge(tier: user.displayTier)
                        .fixedSize()
                }
            }
            if !line.isEmpty {
                Text(line)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
            }
            footer()
        }
        .foregroundStyle(AppTheme.Colors.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

/// 卡片下面的圆按钮（✕ ♥ ★），带贴纸投影
struct RoundActionLabel: View {
    let icon: String
    let tint: Color
    var foreground: Color = AppTheme.Colors.onAccent
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.36, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
            .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
    }
}

/// 近 180 天爽约过：卡片底部一个粉色小标签
struct NoShowPill: View {
    let count: Int

    var body: some View {
        TagPill(text: String(localized: "近 180 天爽约 \(count) 次"), icon: "exclamationmark.triangle.fill", fill: AppTheme.Colors.pink)
    }
}

/// 某天的约球请求：时间、单打双打写在左上角，下面一行是约在哪家
struct DayCardView: View {
    struct Details {
        var mode: String
        var startsAt: Date
        var endsAt: Date
        var venues: [String]
        var recentNoShows = 0
    }

    let user: User?
    let details: Details
    var onProfile: (() -> Void)?

    var body: some View {
        CoverCard(user: user, pill: pill, line: line, onProfile: onProfile) {
            if details.recentNoShows > 0 { NoShowPill(count: details.recentNoShows) }
        }
    }

    /// “周六 14:00–17:00 · 单打”
    private var pill: String {
        "\(DateText.weekday(details.startsAt)) \(DateText.time(details.startsAt))–\(DateText.time(details.endsAt)) · \(details.mode)"
    }

    private var line: String {
        [details.venues.first, details.recentNoShows == 0 ? String(localized: "靠谱") : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// 一个人：圆头像 + 下面的名字。发现页顶上那一排（正在看的那张卡加一圈柠檬绿）、球馆页的“最近在这打过”和“常客”
struct PersonBubble: View {
    let user: User
    var isCurrent = false
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xs) {
                AvatarView(user: user, size: size)
                    .padding(4)
                    .background(Circle().fill(isCurrent ? AppTheme.Colors.lime : Color.clear))
                    .overlay(Circle().strokeBorder(isCurrent ? AppTheme.Colors.stroke : Color.clear, lineWidth: 2))
                Text(user.nickname)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1)
                    .frame(width: size + 16)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(user.nickname)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
