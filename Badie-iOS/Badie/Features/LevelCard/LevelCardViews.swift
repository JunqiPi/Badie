import SwiftUI
import UniformTypeIdentifiers

// MARK: - 等级卡片：测级结果做成图片分享
//
// 两个尺寸：帖子 1080×1350（正面 + 背面两张卡斜放在海报上）、限时动态 1080×1920（角色窗 + 称号 + 六格数据）。
// 网站画同样的卡片（web/src/app/）。人物插画在 Assets.xcassets 的 Play-<打法>，以后换正式插画只换图片文件。
// 卡片在本机画，不经过服务器；昵称只印在图片上。

/// 卡片上的等级来源
enum LevelCardLabel: Hashable {
    /// 问卷自评
    case selfRated
    /// 打过球、球友评价已经校准过等级
    case calibrated
    /// 7–9 级审核通过
    case verified

    init(user: User) {
        if user.verifiedRating != nil {
            self = .verified
        } else if !user.reputation.isNewPlayer {
            self = .calibrated
        } else {
            self = .selfRated
        }
    }

    var title: String {
        switch self {
        case .selfRated: return String(localized: "自评")
        case .calibrated: return String(localized: "已校准")
        case .verified: return String(localized: "已认证")
        }
    }
}

enum LevelCardFormat: String, CaseIterable, Identifiable {
    /// 帖子 1080×1350
    case post
    /// 限时动态 1080×1920
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .post: return String(localized: "帖子")
        case .story: return String(localized: "限时动态")
        }
    }

    /// 画布大小（点）；导出时 ×3
    var size: CGSize {
        switch self {
        case .post: return CGSize(width: 360, height: 450)
        case .story: return CGSize(width: 360, height: 640)
        }
    }
}

/// 卡片上印的内容：只放已知的，不知道的那一行不显示
struct LevelCardData: Hashable, Identifiable {
    var id: LevelCardData { self }
    var tier: SkillTier
    var label: LevelCardLabel
    /// “阿杰#3400”
    var name: String?
    /// 常去球馆所在的城市
    var region: String?
    var play: PlayProfile?
    var gap: AssessmentGap?
    var mode: GameMode?
    var venue: String?
    var times: String?
    /// 印网址（发小红书时关掉，改印“App Store 搜 Badie 羽毛球”）
    var showsURL = true

    /// 这一档的网页（带 ?ref=card，网站据此显示“你的朋友是 4+。你呢？”）
    var link: URL { Self.url(for: tier) }

    /// 18 个自评档：/levels/4-plus/、/levels/4/、/levels/4-minus/；7 级起每级一个说明页 /levels/7/
    static func slug(for tier: SkillTier) -> String {
        guard tier.level <= SkillLevel.maxSelfSelectable else { return "\(tier.level)" }
        switch tier.modifier {
        case .minus: return "\(tier.level)-minus"
        case .base: return "\(tier.level)"
        case .plus: return "\(tier.level)-plus"
        }
    }

    /// 网页的语言前缀（和网站 i18n.ts 的 pathPrefixes 一样）：英文没有前缀，简体中文 /zh/，繁体 /zh-hant/，其他是语言代码
    static func languagePrefix(_ language: String = AppLanguage.current) -> String {
        switch language {
        case "en": return ""
        case "zh-Hans": return "zh/"
        case "zh-Hant": return "zh-hant/"
        default: return AppLanguage.supported.contains(language) ? "\(language)/" : ""
        }
    }

    static func url(for tier: SkillTier, language: String = AppLanguage.current) -> URL {
        URL(string: "https://badie.rsvp/\(languagePrefix(language))levels/\(slug(for: tier))/?ref=card")
            ?? URL(string: "https://badie.rsvp/levels/")!
    }

    /// 网址里的档位：“4-plus” → 4+；“7” → 7
    static func tier(fromSlug slug: String) -> SkillTier? {
        let parts = slug.split(separator: "-")
        guard let first = parts.first, let level = Int(first), SkillLevel.range.contains(level) else { return nil }
        switch parts.count == 2 ? String(parts[1]) : "" {
        case "minus": return SkillTier(level: level, modifier: .minus)
        case "plus": return SkillTier(level: level, modifier: .plus)
        case "": return parts.count == 1 ? SkillTier(level: level) : nil
        default: return nil
        }
    }

    /// 刚测完：等级就是问卷结果
    @MainActor
    static func make(result: SkillAssessmentResult, appState: AppState) -> LevelCardData {
        var data = LevelCardData(tier: result.tier, label: .selfRated, play: result.play, gap: result.nextGap)
        if let user = appState.currentUser { data.fill(from: user, appState: appState) }
        return data
    }

    /// “我的”里：显示的等级、球友评价校准过就写“已校准”，打法从存着的答案算
    @MainActor
    static func make(user: User, appState: AppState) -> LevelCardData {
        let answers = user.assessment?.answers
        var data = LevelCardData(tier: user.displayTier, label: LevelCardLabel(user: user),
                                 play: answers.flatMap(SkillAssessment.playProfile))
        // 差的那一项只在还没到那一级时显示
        if let gap = answers.flatMap(SkillAssessment.evaluate)?.nextGap, Double(gap.level) > data.tier.rating {
            data.gap = gap
        }
        data.fill(from: user, appState: appState)
        return data
    }

    @MainActor
    private mutating func fill(from user: User, appState: AppState) {
        name = user.nickname + user.tagText
        mode = user.preferredMode
        let venue = appState.backend.favoriteCourtIds().compactMap { appState.venueService.venue(id: $0) }.first
        self.venue = venue?.name
        region = venue.map { $0.postalAddress.city }.flatMap { $0.isEmpty ? nil : $0 }
        times = UsualTimeText.summary(appState.backend.usualTimes(of: user.id))
    }
}

// MARK: - 颜色

/// 每种打法一套颜色：海报底色、上面的字、装饰线
struct LevelCardPalette {
    let background: Color
    let onBackground: Color
    let circuit: Color
    /// 限时动态角色窗的渐变
    let windowTop: Color
    let windowBottom: Color
    /// 徽章上的字、竖排 BADIE
    let accent: Color
    /// 正面卡人物区的底色和重复大字的颜色
    let artBackground: Color
    let artGhost: Color
    /// 人物区里的字和图标
    let artInk: Color

    static let ink = Color(hex: 0x17140F)
    static let cream = Color(hex: 0xF2EFE7)
    static let lime = Color(hex: 0xD4F33F)
    static let violet = Color(hex: 0x6B4CFF)
    static let gold = Color(hex: 0xD9B44A)

    init(style: PlayStyle?) {
        let base: UInt32
        switch style {
        case .cannon, nil: base = 0xD4F33F
        case .net: base = 0x8B7CF6
        case .wall: base = 0x4F8CFF
        case .quick: base = 0xFF9A3C
        case .engine: base = 0x2EC4B6
        case .captain: base = 0xFF5A5F
        case .allround: base = 0x17140F
        case .rookie: base = 0x6EC1FF
        }
        if style == .allround {
            background = Self.ink
            onBackground = Self.gold
            circuit = Self.gold
            windowTop = Self.mix(0x17140F, 0xD9B44A, 0.3)
            windowBottom = Self.mix(0x17140F, 0x0B0D24, 0.5)
            accent = Self.gold
            artBackground = Color(hex: 0x2A2620)
            artGhost = Self.gold.opacity(0.12)
            artInk = Self.gold
        } else {
            // 紫、蓝、红底上用白字（和网站一致）
            let darkBackground = style.map { [PlayStyle.net, .wall, .captain].contains($0) } ?? false
            background = Color(hex: base)
            onBackground = darkBackground ? .white : Self.ink
            circuit = darkBackground ? Self.lime : Self.violet
            windowTop = Self.mix(base, 0xFFFFFF, 0.35)
            windowBottom = Self.mix(base, 0x0B0D24, 0.55)
            accent = Self.lime
            artBackground = Self.cream
            artGhost = Self.ink.opacity(0.09)
            artInk = Self.ink
        }
    }

    /// a 和 b 按 t 混合（t = 0 是 a）
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) / 255 }
        func blend(_ shift: UInt32) -> Double { channel(a, shift) * (1 - t) + channel(b, shift) * t }
        return Color(.sRGB, red: blend(16), green: blend(8), blue: blend(0))
    }
}

// MARK: - 形状

/// 按比例给顶点的多边形（0…1）
struct UnitPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        path.move(to: map(first))
        for point in points.dropFirst() { path.addLine(to: map(point)) }
        path.closeSubpath()
        return path
    }

    static func make(_ values: [(CGFloat, CGFloat)]) -> UnitPolygon {
        UnitPolygon(points: values.map { CGPoint(x: $0.0, y: $0.1) })
    }

    static let hexagon = make([(0.5, 0), (1, 0.25), (1, 0.75), (0.5, 1), (0, 0.75), (0, 0.25)])
    static let topBand = make([(0, 0), (1, 0), (1, 1), (0.78, 1), (0.72, 0.6), (0.28, 0.6), (0.22, 1), (0, 1)])
    static let bottomBand = make([(0, 0), (0.22, 0), (0.28, 0.4), (0.72, 0.4), (0.78, 0), (1, 0), (1, 1), (0, 1)])
    static let tab = make([(0.08, 0), (0.92, 0), (1, 1), (0, 1)])
    static let hudPanel = make([(0, 0.08), (0.14, 0.08), (0.18, 0), (0.82, 0), (0.86, 0.08), (1, 0.08),
                                (1, 0.92), (0.86, 0.92), (0.82, 1), (0.18, 1), (0.14, 0.92), (0, 0.92)])
    static let window = make([(0.06, 0), (0.48, 0), (0.52, 0.03), (1, 0.03), (1, 1), (0, 1), (0, 0.05)])
    static let titlePanel = make([(0, 0), (1, 0), (1, 0.82), (0.94, 1), (0, 1)])
    static let tile = make([(0.04, 0), (0.96, 0), (1, 0.12), (1, 0.88), (0.96, 1), (0.04, 1), (0, 0.88), (0, 0.12)])
}

/// 雷达图的多边形：values 是 0…1，从正上方顺时针
struct RadarPolygon: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for (index, value) in values.enumerated() {
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(values.count)
            let point = CGPoint(x: center.x + CGFloat(cos(angle) * value) * radius,
                                y: center.y + CGFloat(sin(angle) * value) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// 斜线底纹（限时动态的背景）
private struct SlashPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 54
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height * 0.58, y: rect.minY))
            x += step
        }
        return path
    }
}

// MARK: - 打法雷达图（结果页）

struct PlayRadar: View {
    let profile: PlayProfile
    var foreground: Color = AppTheme.Colors.onAccent

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = max(side / 2 - 26, 10)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                ForEach([1.0 / 3, 2.0 / 3, 1.0], id: \.self) { ring in
                    RadarPolygon(values: Array(repeating: ring, count: PlayAxis.allCases.count))
                        .stroke(foreground.opacity(0.2), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }
                RadarPolygon(values: PlayAxis.allCases.map { min(max(profile.value($0), 0), 6) / 6 })
                    .fill(foreground.opacity(0.7))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                ForEach(Array(PlayAxis.allCases.enumerated()), id: \.offset) { index, axis in
                    let angle = -Double.pi / 2 + Double(index) * Double.pi / 3
                    VStack(spacing: 0) {
                        Text(axis.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Text(verbatim: "\(profile.displayValue(axis))")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(foreground)
                    .fixedSize()
                    .position(x: center.x + CGFloat(cos(angle)) * (radius + 16),
                              y: center.y + CGFloat(sin(angle)) * (radius + 14))
                }
            }
        }
        .frame(height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlayAxis.allCases.map { "\($0.title) \(profile.displayValue($0))" }.joined(separator: ", "))
    }
}

// MARK: - 卡片

struct LevelCardView: View {
    let data: LevelCardData
    let format: LevelCardFormat

    var body: some View {
        Group {
            switch format {
            case .post: LevelCardPoster(data: data)
            case .story: LevelCardStory(data: data)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}

/// 卡片上的字体：固定字号（图片尺寸固定，不跟随动态字体）
private func cardFont(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

/// 大数字：窄一点
private func numberFont(_ size: CGFloat) -> Font {
    .system(size: size, weight: .black).width(.condensed)
}

/// 卡片底部的落款：网址或“App Store 搜 Badie 羽毛球”
private func footerText(_ data: LevelCardData) -> String {
    data.showsURL ? "BADIE.RSVP/LEVELS" : String(localized: "App Store 搜 Badie 羽毛球")
}

/// 人物插画（没有打法时不画人，只印等级）
private struct CardArt: View {
    let play: PlayProfile?

    var body: some View {
        if let play {
            Image(play.style.artName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        }
    }
}

/// 六边形等级徽章
private struct HexBadge: View {
    let code: String
    let fill: Color
    let text: Color
    var size: CGFloat = 13

    var body: some View {
        Text(verbatim: code)
            .font(cardFont(size))
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UnitPolygon.hexagon.fill(fill))
    }
}

/// 小球拍图标
private struct RacketMark: View {
    var color: Color = .white

    var body: some View {
        HStack(spacing: -1) {
            Capsule().fill(color).frame(width: 22, height: 2)
            Ellipse().stroke(color, lineWidth: 1.4).frame(width: 12, height: 9)
        }
    }
}

/// 海报上的装饰线（线 + 端点）
private struct Circuit: View {
    let height: CGFloat
    let color: Color
    var flipped = false

    var body: some View {
        VStack(spacing: 0) {
            if flipped { Circle().fill(color).frame(width: 6, height: 6) }
            Rectangle().fill(color).frame(width: 2, height: height)
            if !flipped { Circle().fill(color).frame(width: 6, height: 6) }
        }
    }
}

// MARK: 帖子：正面 + 背面

struct LevelCardPoster: View {
    let data: LevelCardData

    private var palette: LevelCardPalette { LevelCardPalette(style: data.play?.style) }

    var body: some View {
        ZStack {
            palette.background
            UnitPolygon.topBand.fill(LevelCardPalette.ink)
                .frame(width: 360, height: 41)
                .position(x: 180, y: 20.5)
            UnitPolygon.bottomBand.fill(LevelCardPalette.ink)
                .frame(width: 360, height: 41)
                .position(x: 180, y: 429.5)
            Circuit(height: 80, color: palette.circuit).position(x: 30, y: 43)
            Circuit(height: 100, color: palette.circuit).position(x: 330, y: 53)
            Circuit(height: 73, color: palette.circuit, flipped: true).position(x: 41, y: 450 - 39.5)
            Circuit(height: 87, color: palette.circuit, flipped: true).position(x: 319, y: 450 - 46.5)
            VStack(alignment: .leading, spacing: -24) {
                Text(verbatim: "BAD")
                Text(verbatim: "IE")
            }
            .font(cardFont(100))
            .tracking(-4)
            .foregroundStyle(palette.onBackground.opacity(0.07))
            .fixedSize()
            .position(x: 230, y: 230)
            header
                .position(x: 180, y: 66)
            front
                .frame(width: 157, height: 233)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 9)
                .rotationEffect(.degrees(-4))
                .position(x: 99, y: 220)
            back
                .frame(width: 157, height: 227)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 9)
                .rotationEffect(.degrees(3))
                .position(x: 266, y: 262)
            Text(verbatim: String(localized: "#我的羽球卡"))
                .font(cardFont(12))
                .foregroundStyle(palette.onBackground)
                .position(x: 180, y: 392)
        }
        .frame(width: 360, height: 450)
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text(verbatim: String(localized: "测测你几级 · 2 分钟"))
                .font(cardFont(8.5))
                .tracking(1)
            Text(verbatim: footerText(data))
                .font(cardFont(data.showsURL ? 18 : 14))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(palette.onBackground)
        .frame(width: 320)
    }

    // MARK: 正面

    private var front: some View {
        ZStack(alignment: .top) {
            LevelCardPalette.ink
            frontArt
                .frame(width: 157, height: 139)
                .clipped()
                .frame(maxHeight: .infinity, alignment: .top)
            frontBottom
                .frame(width: 157, height: 94)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var frontArt: some View {
        ZStack(alignment: .topLeading) {
            palette.artBackground
            VStack(alignment: .leading, spacing: -8) {
                ForEach(0..<4, id: \.self) { _ in
                    Text(verbatim: data.play?.style.ghostWord ?? "BADIE")
                        .font(cardFont(39))
                        .tracking(-1.5)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(palette.artGhost)
            .offset(x: -4, y: -6)
            if let play = data.play {
                CardArt(play: play)
                    .frame(width: 118, height: 136)
                    .position(x: 84, y: 74)
                Text(verbatim: play.style.onomatopoeia)
                    .font(cardFont(13))
                    .foregroundStyle(palette.artInk)
                    .rotationEffect(.degrees(-10))
                    .fixedSize()
                    .position(x: 128, y: 112)
            } else {
                Text(verbatim: data.tier.code)
                    .font(numberFont(72))
                    .foregroundStyle(palette.artInk)
                    .fixedSize()
                    .position(x: 84, y: 76)
            }
            // 红色 HUD 短线
            Rectangle().fill(Color(hex: 0xE5484D)).frame(width: 23, height: 1.5).position(x: 18, y: 100)
            Rectangle().fill(Color(hex: 0xE5484D)).frame(width: 16, height: 1.5).position(x: 141, y: 80)
            HexBadge(code: data.tier.code, fill: LevelCardPalette.ink, text: palette.accent)
                .frame(width: 23, height: 25)
                .position(x: 18.5, y: 19.5)
            VStack(spacing: 4) {
                modeIcon(String(localized: "单"), on: data.mode != .doubles)
                modeIcon(String(localized: "双"), on: data.mode != .singles)
            }
            .position(x: 144, y: 23)
        }
    }

    /// 单打 / 双打：常打的那个涂黑；都行就都涂黑
    private func modeIcon(_ text: String, on: Bool) -> some View {
        Text(verbatim: text)
            .font(cardFont(6.5))
            .foregroundStyle(on ? palette.artBackground : palette.artInk)
            .frame(width: 13, height: 13)
            .background(Circle().fill(on ? palette.artInk : Color.clear))
            .overlay(Circle().stroke(palette.artInk, lineWidth: 1.3))
    }

    private var frontBottom: some View {
        ZStack(alignment: .top) {
            Text(verbatim: "BADIE")
                .font(cardFont(6.5))
                .tracking(1.3)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(UnitPolygon.tab.fill(LevelCardPalette.ink))
                .offset(y: -6)
            VStack(spacing: 1) {
                Text(verbatim: data.name ?? data.tier.text)
                    .font(cardFont(13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: regionLine)
                    .font(cardFont(5.5, .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x9A948A))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8)
            .padding(.top, 9)
            HStack(alignment: .bottom, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: data.play == nil ? String(localized: "等级") : String(localized: "打法"))
                        .font(cardFont(5.5))
                        .tracking(0.8)
                        .foregroundStyle(Color(hex: 0x9A948A))
                    Text(verbatim: data.play?.style.title ?? data.tier.name)
                        .font(cardFont(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let play = data.play {
                        Text(verbatim: play.style.line)
                            .font(cardFont(5.5, .bold))
                            .foregroundStyle(Color(hex: 0xD6D1C8))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let shot = data.play?.bestShot {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: String(localized: "最强一拍"))
                            .font(cardFont(5.5))
                            .tracking(0.8)
                            .foregroundStyle(Color(hex: 0x9A948A))
                        Text(verbatim: shot.name)
                            .font(cardFont(9.5))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        RacketMark()
                    }
                    .frame(maxWidth: 62, alignment: .trailing)
                }
            }
            .padding(8)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// “LOS ANGELES · 4+ 中级 · 自评”
    private var regionLine: String {
        [data.region?.uppercased(), "\(data.tier.code) \(data.tier.name)", data.label.title]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: 背面

    private var backRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let mode = data.mode { rows.append((String(localized: "位置"), mode.title)) }
        if let venue = data.venue { rows.append((String(localized: "常去球馆"), venue)) }
        if let times = data.times { rows.append((String(localized: "空闲时间"), times)) }
        if let play = data.play { rows.append((String(localized: "最佳搭档"), play.style.partnerText)) }
        // 什么都不知道时，印这一档的标准
        if rows.isEmpty, let criterion = SkillLevel.tierCriteria(for: data.tier).first {
            rows.append(("\(data.tier.code) \(data.tier.name)", criterion))
        }
        return rows
    }

    private var back: some View {
        ZStack(alignment: .topLeading) {
            LevelCardPalette.ink
            HStack(spacing: 6) {
                HexBadge(code: data.tier.code, fill: palette.accent, text: LevelCardPalette.ink, size: 6)
                    .frame(width: 14, height: 16)
                    .frame(width: 23, height: 23)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(hex: 0x2A2620)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: data.name ?? data.tier.name)
                        .font(cardFont(9.5))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 3) {
                        if let region = data.region {
                            Text(verbatim: region.uppercased())
                                .font(cardFont(5.5, .bold))
                                .tracking(0.6)
                                .foregroundStyle(Color(hex: 0x9A948A))
                                .lineLimit(1)
                        }
                        Text(verbatim: "LV.\(data.tier.code)")
                            .font(cardFont(5.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(LevelCardPalette.violet)
                    }
                }
            }
            .padding(8)
            UnitPolygon.hudPanel.fill(LevelCardPalette.cream)
                .frame(width: 157, height: 132)
                .offset(y: 44)
            VStack(spacing: 3.5) {
                ForEach(Array(backRows.enumerated()), id: \.offset) { _, row in
                    VStack(spacing: 1) {
                        Text(verbatim: row.0)
                            .font(cardFont(5))
                            .tracking(0.6)
                            .foregroundStyle(Color(hex: 0xE5484D))
                            .lineLimit(1)
                        Text(verbatim: row.1)
                            .font(cardFont(7.5))
                            .foregroundStyle(LevelCardPalette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: 0xE2DDD2))
                }
            }
            .frame(width: 117, height: 108, alignment: .center)
            .offset(x: 20, y: 56)
            Text(verbatim: "BADIE")
                .font(cardFont(7))
                .tracking(2)
                .foregroundStyle(palette.accent)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .position(x: 10, y: 110)
            if let play = data.play {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(PlayAxis.allCases) { axis in
                        VStack(spacing: 0) {
                            Text(verbatim: axis.title)
                                .font(cardFont(5))
                                .foregroundStyle(Color(hex: 0x9A948A))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(verbatim: "\(play.displayValue(axis))")
                                .font(numberFont(17))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: 157, height: 40)
                .offset(y: 182)
            }
        }
    }
}

// MARK: 限时动态：角色窗 + 称号 + 六格

struct LevelCardStory: View {
    let data: LevelCardData

    private var palette: LevelCardPalette { LevelCardPalette(style: data.play?.style) }

    private struct Tile: Identifiable {
        let id: Int
        let label: String
        let value: String
        var detail: String?
        let icon: String
    }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2B2F6B), Color(hex: 0x0B0D24), Color(hex: 0x05060F)],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 520)
            SlashPattern()
                .stroke(Color(red: 120 / 255, green: 140 / 255, blue: 1).opacity(0.08), lineWidth: 1.5)
            Text(verbatim: "badie")
                .font(cardFont(20))
                .foregroundStyle(LevelCardPalette.lime)
                .position(x: 180, y: 30)
            window
                .frame(width: 232, height: 267)
                .position(x: 180, y: 188.5)
            titlePanel
                .frame(width: 254, height: 85)
                .position(x: 180, y: 341.5)
            tiles
                .frame(width: 282)
                .position(x: 180, y: 393 + tilesHeight / 2)
            VStack(spacing: 3) {
                Text(verbatim: String(localized: "#我的羽球卡"))
                    .font(cardFont(11.5))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)
                Text(verbatim: String(localized: "测测你几级 · 不用注册"))
                    .font(cardFont(10))
                    .foregroundStyle(Color(hex: 0xC9CDF5))
                Text(verbatim: footerText(data))
                    .font(cardFont(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 320)
            .position(x: 180, y: 600)
        }
        .frame(width: 360, height: 640)
    }

    private var window: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [palette.windowTop, palette.windowBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                LinearGradient(colors: [palette.windowTop, palette.windowBottom], startPoint: .top, endPoint: .bottom)
                    .opacity(0.85)
                if let play = data.play {
                    CardArt(play: play)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    Text(verbatim: play.style.onomatopoeia)
                        .font(cardFont(26))
                        .foregroundStyle(play.style == .allround ? LevelCardPalette.gold : LevelCardPalette.lime)
                        .shadow(color: Color(hex: 0x0B0D24), radius: 0, x: 1.5, y: 1.5)
                        .rotationEffect(.degrees(-10))
                        .fixedSize()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                } else {
                    Text(verbatim: data.tier.code)
                        .font(numberFont(110))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize()
                }
            }
            .clipped()
            .padding(EdgeInsets(top: 18, leading: 14, bottom: 14, trailing: 14))
            Text(verbatim: "BADIE · \(Calendar.current.component(.year, from: Date()))")
                .font(cardFont(6.5))
                .tracking(1.8)
                .foregroundStyle(Color(hex: 0xC9CDF5))
                .fixedSize()
                .rotationEffect(.degrees(90))
                .position(x: 7, y: 90)
        }
        .clipShape(UnitPolygon.window)
        .shadow(color: palette.windowTop.opacity(0.6), radius: 22)
    }

    private var titlePanel: some View {
        VStack(spacing: 3) {
            Text(verbatim: data.play?.style.title ?? "\(data.tier.text) \(data.tier.name)")
                .font(cardFont(27))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let play = data.play {
                Text(verbatim: play.style.line)
                    .font(cardFont(9, .bold))
                    .foregroundStyle(Color(hex: 0xDFE2FF))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [palette.windowTop.opacity(0.85), palette.windowBottom.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(UnitPolygon.titlePanel)
        )
    }

    /// 六格：等级、最强一拍、最高的两项、离下一级还差（没有时换成第三高的一项）、最佳搭档
    private var tileList: [Tile] {
        var list: [Tile] = [Tile(id: 0, label: String(localized: "等级 · \(data.label.title)"), value: data.tier.code,
                                 detail: data.tier.name, icon: "hexagon.fill")]
        guard let play = data.play else {
            if let gap = data.gap {
                list.append(Tile(id: 4, label: String(localized: "离 \(gap.level) 级还差"), value: gap.dimension.name,
                                 icon: "arrow.up.right"))
            }
            return list
        }
        if let shot = play.bestShot {
            list.append(Tile(id: 1, label: String(localized: "最强一拍"), value: shot.name, icon: "figure.badminton"))
        }
        let ranked = play.rankedAxes
        let axisCount = data.gap == nil ? 3 : 2
        for (index, axis) in ranked.prefix(axisCount).enumerated() {
            list.append(Tile(id: 2 + index, label: axis.title, value: "\(play.displayValue(axis)) / \(SkillLevel.maxSelfSelectable)",
                             icon: "bolt.fill"))
        }
        if let gap = data.gap {
            list.append(Tile(id: 5, label: String(localized: "离 \(gap.level) 级还差"), value: gap.dimension.name,
                             icon: "arrow.up.right"))
        }
        list.append(Tile(id: 6, label: String(localized: "最佳搭档"), value: play.style.partnerText, icon: "person.2.fill"))
        return list
    }

    private var tilesHeight: CGFloat {
        let rows = CGFloat((tileList.count + 1) / 2)
        return rows * 48 + max(rows - 1, 0) * 7
    }

    /// 两列（ImageRenderer 里不用 Lazy 容器）
    private var tiles: some View {
        let list = tileList
        let rows = stride(from: 0, to: list.count, by: 2).map { Array(list[$0..<min($0 + 2, list.count)]) }
        return VStack(spacing: 7) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 7) {
                    ForEach(rows[row]) { tile in
                        tileView(tile)
                            .frame(maxWidth: .infinity)
                    }
                    if rows[row].count == 1 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 48)
                    }
                }
            }
        }
    }

    private func tileView(_ tile: Tile) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: tile.icon)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: -4, y: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: tile.label)
                    .font(cardFont(7))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0xC9CDF5))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: tile.value)
                        .font(cardFont(17))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let detail = tile.detail {
                        Text(verbatim: detail)
                            .font(cardFont(10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .frame(height: 48)
        .clipShape(UnitPolygon.tile)
        .overlay(UnitPolygon.tile.stroke(Color(red: 200 / 255, green: 205 / 255, blue: 1).opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 出图和分享

/// 分享出去的 PNG
struct LevelCardImage: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in card.png }
            .suggestedFileName("Badie.png")
    }
}

@MainActor
enum LevelCardRenderer {
    /// 画成图片：帖子 1080×1350，限时动态 1080×1920
    static func render(_ data: LevelCardData, format: LevelCardFormat) -> UIImage? {
        let renderer = ImageRenderer(content: LevelCardView(data: data, format: format))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(format.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 分享等级卡片：选尺寸、预览、系统分享（图片 + 链接）
struct LevelCardSheet: View {
    @State var data: LevelCardData
    @State private var format: LevelCardFormat = .post
    @State private var image: UIImage?
    @State private var png: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("等级卡片")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(LevelCardFormat.allCases) { option in
                            ChoiceChip(title: option.title, isSelected: format == option) { format = option }
                        }
                        Spacer(minLength: 0)
                    }
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .accessibilityLabel(Text(verbatim: accessibilitySummary))
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: format == .post ? 420 : 520)
                    Toggle(isOn: $data.showsURL) {
                        Text("印上网址")
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                    }
                    .tint(AppTheme.Colors.success)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            if let image, let png {
                ShareLink(item: LevelCardImage(png: png),
                          message: Text(verbatim: String(localized: "测测你几级：\(data.link.absoluteString)")),
                          preview: SharePreview(String(localized: "我的羽球卡"), image: Image(uiImage: image))) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.brutalPrimary)
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task(id: renderKey) {
            let output = await LevelCardRenderer.render(data, format: format)
            image = output
            png = output?.pngData()
        }
    }

    private var renderKey: String { "\(format.rawValue)-\(data.showsURL)" }

    private var accessibilitySummary: String {
        [data.name, data.tier.displayText, data.label.title, data.play?.style.title, data.play?.style.line]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
