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

    /// 底纹颜色：深色底用浅色
    var pattern: Color { self == .ink ? Color.white.opacity(0.12) : Color(hex: 0x17140F).opacity(0.1) }

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

/// 卡片上半部分：有背景照片就铺满照片；没有就是颜色 + Badie 底纹 + 中间的大头像
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
                LogoPattern(tint: color.pattern)
                face()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// 斜着排的 Badie 标志底纹
struct LogoPattern: View {
    let tint: Color
    var tile: CGFloat = 44

    var body: some View {
        Canvas { context, size in
            var mark = context.resolve(Image("LogoMark"))
            mark.shading = .color(tint)
            let step = tile * 1.35
            var row = 0
            var y: CGFloat = -tile / 2
            while y < size.height {
                var x: CGFloat = (row.isMultiple(of: 2) ? 0 : step / 2) - tile / 2
                while x < size.width {
                    context.draw(mark, in: CGRect(x: x, y: y, width: tile, height: tile * 514 / 456))
                    x += step
                }
                y += step
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 一张铺满的卡片：上面是背景照片或颜色，下面是等级、时间、球馆
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
        let photo = user.flatMap { AvatarPhotos.cardImage(userId: $0.id, avatar: $0.avatar) }
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let user {
                    CardCover(color: user.cardColor, photo: photo) {
                        AvatarView(user: user, size: 140)
                            .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
                    }
                } else {
                    AppTheme.Colors.surfaceMuted
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let user, photo != nil {
                    // 有背景照片：头像小一点，压在照片左下角
                    AvatarView(user: user, size: 64)
                        .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 2, y: 3))
                        .padding(.leading, AppTheme.Spacing.lg)
                        .offset(y: 32)
                }
            }
            .zIndex(1)
            info
                .padding(.top, photo != nil ? 36 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let user {
                HStack(spacing: AppTheme.Spacing.sm) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    LevelBadge(tier: user.displayTier)
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Label(details.mode, systemImage: "figure.badminton")
                Label("\(details.startsAt.formatted(date: .omitted, time: .shortened))–\(details.endsAt.formatted(date: .omitted, time: .shortened))",
                      systemImage: "clock")
                ForEach(details.venues, id: \.self) { venue in
                    Label(venue, systemImage: "mappin.and.ellipse").lineLimit(1)
                }
                if details.recentNoShows > 0 {
                    Label(String(localized: "近 180 天爽约 \(details.recentNoShows) 次"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }
            .font(AppTheme.Typography.bodyBold)
            .foregroundStyle(AppTheme.Colors.ink)
            if let onProfile {
                Button("看资料", action: onProfile)
                    .buttonStyle(TextActionStyle())
            }
        }
        .padding(AppTheme.Spacing.lg)
    }
}
