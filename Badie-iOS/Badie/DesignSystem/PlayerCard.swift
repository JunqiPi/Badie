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

/// 卡片上半部分：有背景照片就铺满照片；没有就是纯色 + 中间的大头像
struct CardCover<Face: View>: View {
    let color: CardColor
    let photo: UIImage?
    @ViewBuilder let face: () -> Face

    var body: some View {
        ZStack {
            if let photo {
                Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill() }
            } else {
                color.fill
                face()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// 发现页的大卡片，左上角一个白色小标签。
/// 有照片：照片铺满，底部压暗写名字、等级、一行信息；没照片：上面约六成是纯色 + 大头像，下面一块白色信息区
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
        let photo = user.flatMap { AvatarPhotos.cardImage(userId: $0.id, avatar: $0.avatar) }
        Group {
            if let photo, let user {
                ZStack(alignment: .bottomLeading) {
                    CardCover(color: user.cardColor, photo: photo) { EmptyView() }
                    info(onPhoto: true)
                        .padding(.top, AppTheme.Spacing.xxxl)
                        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                }
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        colorCover
                            .frame(minHeight: 0, maxHeight: .infinity)
                        Rectangle()
                            .fill(AppTheme.Colors.stroke)
                            .frame(height: 3)
                        // 信息区至少占四成；字多（小屏、大字体）时上面的颜色让出来
                        info(onPhoto: false)
                            .frame(minHeight: proxy.size.height * 0.38, alignment: .top)
                            .background(AppTheme.Colors.surface)
                    }
                }
            }
        }
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

    /// 没照片时的上半部分：卡片颜色 + 居中的大头像（放不下就换小一号，上下让开左上角的标签）
    @ViewBuilder
    private var colorCover: some View {
        if let user {
            CardCover(color: user.cardColor, photo: nil) {
                ViewThatFits(in: .vertical) {
                    face(user, size: 120)
                    face(user, size: 72)
                }
                .padding(.vertical, 40)
            }
        } else {
            AppTheme.Colors.surfaceMuted
        }
    }

    private func face(_ user: User, size: CGFloat) -> some View {
        AvatarView(user: user, size: size)
            .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
    }

    private func info(onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if let user {
                HStack(spacing: AppTheme.Spacing.sm) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title2)
                    LevelBadge(tier: user.displayTier)
                        .fixedSize()
                }
            }
            if !line.isEmpty {
                Text(line)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(onPhoto ? Color.white : AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
            }
            footer()
        }
        .foregroundStyle(onPhoto ? Color.white : AppTheme.Colors.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.lg)
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
