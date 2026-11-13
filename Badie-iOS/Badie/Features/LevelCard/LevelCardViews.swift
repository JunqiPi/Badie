import SwiftUI
import UniformTypeIdentifiers

// MARK: - 等级卡片：测级结果做成图片分享
//
// 一张 4:5 的卡，导出 1080×1350。图片就是卡片本身，有正面和背面：
// 正面是人物、头像、名字、打法和最强一拍；背面是知道的几行资料、离下一级还差什么、六项数字。
// App 里一次看一面，点一下翻面；分享的是当前这一面。所有打法用同一套颜色。
// 网站画同样的卡片（web/src/app/）。人物插画在 Assets.xcassets 的 Play-<打法>，以后换正式插画只换图片文件。
// 卡片在本机画，不经过服务器；昵称和头像只印在图片上。

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

/// 卡片的两面
enum LevelCardFace: Hashable {
    case front, back
}

/// 背面的一行
struct LevelCardRow: Hashable {
    let label: String
    let value: String
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
    /// 头像照片（JPEG）；没传过照片时为 nil
    var avatar: Data?
    /// 印网址（发小红书时关掉，改印“App Store 搜 Badie 羽毛球”）
    var showsURL = true
    /// 印头像（有照片时才有用）
    var showsAvatar = true

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
        // 头像：和 AvatarView 用同一份照片（传过照片才有）
        avatar = user.avatar.photoVersion == nil ? nil : AvatarPhotos.source(user.id)
    }
}

// MARK: 卡片上的字

extension LevelCardData {
    /// “4+ 中级”
    var tierLine: String { "\(tier.code) \(tier.name)" }

    /// 名字下面的小字：“LOS ANGELES · 4+ 中级 · 自评”，只印知道的。
    /// 正面没有名字时大字已经是等级，传 includesTier: false 不再印一遍
    func subline(includesTier: Bool = true) -> String {
        [region?.uppercased(), includesTier ? tierLine : nil, label.title]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// 背面的几行：只放知道的，最多 4 行
    var backRows: [LevelCardRow] {
        var rows: [LevelCardRow] = []
        if let mode { rows.append(LevelCardRow(label: String(localized: "偏好"), value: mode.title)) }
        if let venue { rows.append(LevelCardRow(label: String(localized: "常去球馆"), value: venue)) }
        if let times { rows.append(LevelCardRow(label: String(localized: "空闲时间"), value: times)) }
        if let play { rows.append(LevelCardRow(label: String(localized: "最佳搭档"), value: play.style.partnerText)) }
        // 什么都不知道时，印这一档的标准
        if rows.isEmpty, let criterion = SkillLevel.tierCriteria(for: tier).first {
            rows.append(LevelCardRow(label: tierLine, value: criterion))
        }
        return Array(rows.prefix(4))
    }

    /// 底边的落款：网址或“App Store 搜 Badie 羽毛球”
    var footer: String {
        showsURL ? "BADIE.RSVP/LEVELS" : String(localized: "App Store 搜 Badie 羽毛球")
    }

    /// 要印的头像（没有照片或关掉了就是 nil）
    var avatarImage: UIImage? {
        guard showsAvatar, let avatar else { return nil }
        return UIImage(data: avatar)
    }
}

// MARK: - 颜色和形状

/// 卡片的颜色：所有打法用同一套
private enum LevelCardPalette {
    static let ink = Color(hex: 0x17140F)
    static let cream = Color(hex: 0xF2EFE7)
    static let lime = Color(hex: 0xD4F33F)
    /// 次要的字
    static let gray = Color(hex: 0x9A948A)
    /// 打法的那句话
    static let line = Color(hex: 0xD6D1C8)
    /// 背面每一行的底色和行名
    static let rowFill = Color(hex: 0xE2DDD2)
    static let rowLabel = Color(hex: 0x6F695E)
    /// 分隔线、卡片边
    static let hairline = Color.white.opacity(0.12)
}

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
    static let tab = make([(0.08, 0), (0.92, 0), (1, 1), (0, 1)])
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
//
// 画布固定 360×450 点（设计稿 540×675 的 2/3），导出时 ×3。每样东西按坐标放，文字按基线放。

struct LevelCardView: View {
    let data: LevelCardData
    let face: LevelCardFace

    /// 画布大小（点）
    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        Group {
            switch face {
            case .front: LevelCardFront(data: data)
            case .back: LevelCardBack(data: data)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
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

private extension View {
    /// 画布上的一层：左上角放在 (x, y)
    func placed(x: CGFloat, y: CGFloat) -> some View {
        Color.clear.overlay(alignment: .topLeading) {
            self.alignmentGuide(.leading) { _ in -x }
                .alignmentGuide(.top) { _ in -y }
        }
    }

    /// 画布上的一层：左边在 x，第一行字的基线在 y
    func placed(x: CGFloat, baseline y: CGFloat) -> some View {
        Color.clear.overlay(alignment: .topLeading) {
            self.alignmentGuide(.leading) { _ in -x }
                .alignmentGuide(.top) { dimensions in dimensions[.firstTextBaseline] - y }
        }
    }
}

/// 一行字：放不下就缩小（最小一半）。x 是这行字的左边、中间或右边（看 anchor），baseline 是基线
private struct CardLine: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .black
    let color: Color
    var tracking: CGFloat = 0
    var anchor: HorizontalAlignment = .leading
    let x: CGFloat
    let baseline: CGFloat
    let width: CGFloat

    var body: some View {
        Text(verbatim: text)
            .font(cardFont(size, weight))
            .tracking(tracking)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // 字距会多出最后一个字后面的空，居中时左边补上同样的宽度
            .padding(.leading, anchor == .center ? tracking : 0)
            .frame(width: width, alignment: Alignment(horizontal: anchor, vertical: .center))
            .placed(x: left, baseline: baseline)
    }

    private var left: CGFloat {
        if anchor == .center { return x - width / 2 }
        if anchor == .trailing { return x - width }
        return x
    }
}

/// 六边形等级徽章：左上角在 (x, y)
private struct CardBadge: View {
    let code: String
    let fill: Color
    let text: Color
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            UnitPolygon.hexagon.fill(fill)
                .frame(width: width, height: height)
                .placed(x: x, y: y)
            CardLine(text: code, size: fontSize, color: text, anchor: .center,
                     x: x + width / 2, baseline: y + height / 2 + fontSize * 0.34, width: width * 0.82)
        }
    }
}

/// 头像：照片外面一圈柠檬绿，再一圈卡片底色。圆心在 (x, y)，radius 是照片的半径
private struct CardAvatar: View {
    let image: UIImage
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat

    var body: some View {
        let outer = radius + 4.67
        ZStack {
            Circle().fill(LevelCardPalette.ink)
            Circle().fill(LevelCardPalette.lime)
                .frame(width: (radius + 2) * 2, height: (radius + 2) * 2)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: radius * 2, height: radius * 2)
                .clipShape(Circle())
        }
        .frame(width: outer * 2, height: outer * 2)
        .placed(x: x - outer, y: y - outer)
    }
}

/// 卡片边：一圈细线
private struct CardEdge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.14), lineWidth: 1)
            .frame(width: 353.33, height: 443.33)
    }
}

// MARK: 正面

private struct LevelCardFront: View {
    let data: LevelCardData

    /// 人物区的下边
    private var top: CGFloat { 261.33 }

    var body: some View {
        let avatar = data.avatarImage
        ZStack {
            LevelCardPalette.ink
            art
                .frame(width: 344, height: top - 8)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 9.33, topTrailingRadius: 9.33))
                .placed(x: 8, y: 8)
            CardBadge(code: data.tier.code, fill: LevelCardPalette.ink, text: LevelCardPalette.lime,
                      x: 20, y: 20, width: 50.67, height: 57.33, fontSize: 21.33)
            modeMark(.singles).placed(x: 310, y: 19.33)
            modeMark(.doubles).placed(x: 310, y: 56.67)
            tab
            if let avatar {
                CardAvatar(image: avatar, x: 50.67, y: top + 1.33, radius: 29.33)
            }
            identity(hasAvatar: avatar != nil)
            bottom
            CardEdge()
        }
    }

    /// 人物区：浅色底、重复的大字、人物（没有打法时不画人，只印等级）
    private var art: some View {
        ZStack {
            LevelCardPalette.cream
            ForEach(0..<4, id: \.self) { index in
                Text(verbatim: data.play?.style.ghostWord ?? "BADIE")
                    .font(cardFont(85.33))
                    .foregroundStyle(LevelCardPalette.ink.opacity(0.08))
                    .lineLimit(1)
                    .fixedSize()
                    .placed(x: -12, baseline: 56 + CGFloat(index) * 69.33)
            }
            if let play = data.play {
                Image(play.style.artName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 256.67, alignment: .bottom)
                    .placed(x: 62, y: 6)
            } else {
                Text(verbatim: data.tier.code)
                    .font(numberFont(120))
                    .foregroundStyle(LevelCardPalette.ink)
                    .fixedSize()
            }
        }
    }

    /// 单打 / 双打：偏好的那个涂黑；没填偏好就都不涂
    private func modeMark(_ mode: GameMode) -> some View {
        let on = data.mode == mode
        return ZStack {
            Circle().fill(on ? LevelCardPalette.ink : LevelCardPalette.cream)
            Circle().strokeBorder(LevelCardPalette.ink, lineWidth: 2.67)
            HStack(spacing: 1.33) {
                ForEach(0..<(mode == .singles ? 1 : 2), id: \.self) { _ in
                    Circle()
                        .fill(on ? LevelCardPalette.cream : LevelCardPalette.ink)
                        .frame(width: 6.67, height: 6.67)
                }
            }
        }
        .frame(width: 30.67, height: 30.67)
    }

    /// 人物区和信息区交界上的 BADIE 标
    private var tab: some View {
        ZStack {
            UnitPolygon.tab.fill(LevelCardPalette.ink)
                .frame(width: 104, height: 20)
                .placed(x: 128, y: top - 12)
            CardLine(text: "BADIE", size: 13.33, color: LevelCardPalette.lime, tracking: 3.33, anchor: .center,
                     x: 180, baseline: top + 3.33, width: 100)
        }
    }

    /// 名字（没有名字时印等级）和下面的小字。有头像时名字窄一点，不压到头像
    private func identity(hasAvatar: Bool) -> some View {
        ZStack {
            CardLine(text: data.name ?? data.tierLine, size: 26.67, color: .white, anchor: .center,
                     x: 180, baseline: top + 44, width: hasAvatar ? 204 : 320)
            CardLine(text: data.subline(includesTier: data.name != nil), size: 11.33, weight: .heavy,
                     color: LevelCardPalette.gray, tracking: 0.67, anchor: .center,
                     x: 180, baseline: top + 65.33, width: 320)
            Rectangle().fill(LevelCardPalette.hairline)
                .frame(width: 320, height: 1)
                .placed(x: 20, y: top + 81.33)
        }
    }

    /// 左下打法、右下最强一拍、底边落款
    private var bottom: some View {
        ZStack {
            CardLine(text: data.play == nil ? String(localized: "等级") : String(localized: "打法"),
                     size: 10, weight: .heavy, color: LevelCardPalette.gray, x: 20, baseline: 360, width: 180)
            CardLine(text: data.play?.style.title ?? data.tier.name, size: 29.33, color: .white,
                     x: 20, baseline: 393.33, width: 193.33)
            if let play = data.play {
                Text(verbatim: play.style.line)
                    .font(cardFont(10, .bold))
                    .foregroundStyle(LevelCardPalette.line)
                    .lineLimit(2)
                    .lineSpacing(1.3)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                    .frame(width: 193.33, alignment: .leading)
                    .placed(x: 20, baseline: 410.67)
            }
            if let shot = data.play?.bestShot {
                CardLine(text: String(localized: "最强一拍"), size: 10, weight: .heavy, color: LevelCardPalette.gray,
                         anchor: .trailing, x: 340, baseline: 360, width: 120)
                CardLine(text: shot.name, size: 18.67, color: LevelCardPalette.lime, anchor: .trailing,
                         x: 340, baseline: 390.67, width: 120)
            }
            CardLine(text: data.footer, size: 8.67, weight: .heavy, color: LevelCardPalette.gray, tracking: 2,
                     anchor: .center, x: 180, baseline: 436, width: 306.67)
        }
    }
}

// MARK: 背面

private struct LevelCardBack: View {
    let data: LevelCardData

    /// 浅色面板的上边
    private var panelTop: CGFloat { 85.33 }

    var body: some View {
        let rows = data.backRows
        // 行少的时候每行高一点
        let rowHeight: CGFloat = rows.count > 3 ? 40 : 49.33
        let rowGap: CGFloat = rows.count > 3 ? 5.33 : 6.67
        let panelHeight = CGFloat(rows.count) * rowHeight + CGFloat(max(rows.count - 1, 0)) * rowGap + 29.33
        let nextY = panelTop + panelHeight + 28
        ZStack {
            LevelCardPalette.ink
            header(avatar: data.avatarImage)
            RoundedRectangle(cornerRadius: 9.33).fill(LevelCardPalette.cream)
                .frame(width: 328, height: panelHeight)
                .placed(x: 16, y: panelTop)
            VStack(spacing: rowGap) {
                ForEach(rows, id: \.self) { row in
                    rowView(row, height: rowHeight)
                }
            }
            .placed(x: 29.33, y: panelTop + 14.67)
            if let gap = data.gap {
                CardLine(text: String(localized: "离 \(gap.level) 级还差"), size: 10, weight: .heavy,
                         color: LevelCardPalette.gray, x: 20, baseline: nextY, width: 133.33)
                CardLine(text: gap.dimension.name, size: 14.67, color: LevelCardPalette.lime, anchor: .trailing,
                         x: 340, baseline: nextY + 1.33, width: 193.33)
            }
            if let play = data.play {
                stats(play, y: data.gap == nil ? nextY : nextY + 17.33)
            }
            CardLine(text: "\(String(localized: "测测你几级 · 2 分钟")) · \(data.footer)", size: 8.67, weight: .heavy,
                     color: LevelCardPalette.gray, tracking: 2, anchor: .center, x: 180, baseline: 434, width: 306.67)
            CardEdge()
        }
    }

    /// 抬头：徽章、名字（没有就印打法）、小字，右上角头像。有头像时字窄一点
    private func header(avatar: UIImage?) -> some View {
        let width: CGFloat = avatar == nil ? 266.67 : 213.33
        return ZStack {
            CardBadge(code: data.tier.code, fill: LevelCardPalette.lime, text: LevelCardPalette.ink,
                      x: 20, y: 20, width: 40, height: 45.33, fontSize: 16)
            CardLine(text: data.name ?? data.play?.style.title ?? data.tier.name, size: 20, color: .white,
                     x: 70.67, baseline: 41.33, width: width)
            CardLine(text: data.subline(), size: 10, weight: .heavy, color: LevelCardPalette.gray, tracking: 0.67,
                     x: 70.67, baseline: 60, width: width)
            if let avatar {
                CardAvatar(image: avatar, x: 318.67, y: 42.67, radius: 20)
            }
        }
    }

    /// 面板里的一行：左边行名，右边内容
    private func rowView(_ row: LevelCardRow, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: row.label)
                .font(cardFont(10, .heavy))
                .tracking(0.67)
                .foregroundStyle(LevelCardPalette.rowLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 86.67, alignment: .leading)
            Text(verbatim: row.value)
                .font(cardFont(14))
                .foregroundStyle(LevelCardPalette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(width: 301.33, height: height)
        .background(RoundedRectangle(cornerRadius: 5.33).fill(LevelCardPalette.rowFill))
    }

    /// 分隔线和六项数字；y 是分隔线的位置
    private func stats(_ play: PlayProfile, y: CGFloat) -> some View {
        let column: CGFloat = 320 / CGFloat(PlayAxis.allCases.count)
        return ZStack {
            Rectangle().fill(LevelCardPalette.hairline)
                .frame(width: 320, height: 1)
                .placed(x: 20, y: y)
            ForEach(Array(PlayAxis.allCases.enumerated()), id: \.offset) { index, axis in
                let left = 20 + column * CGFloat(index)
                CardLine(text: axis.title, size: 9.33, weight: .heavy, color: LevelCardPalette.gray, anchor: .center,
                         x: left + column / 2, baseline: y + 30.67, width: column - 4)
                Text(verbatim: "\(play.displayValue(axis))")
                    .font(numberFont(37.33))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: column)
                    .placed(x: left, baseline: y + 78.67)
            }
        }
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
    /// 把一面画成图片：1080×1350
    static func render(_ data: LevelCardData, face: LevelCardFace) -> UIImage? {
        let renderer = ImageRenderer(content: LevelCardView(data: data, face: face))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(LevelCardView.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 翻面：绕竖轴转半圈，转到侧面时换成另一面。angle 是 0（正面）到 180（背面）
private struct CardFlip: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity((angle >= 90) == isBack ? 1 : 0)
            .rotation3DEffect(.degrees(isBack ? angle - 180 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

/// 分享等级卡片：预览（点一下翻面）、系统分享当前这一面（图片 + 链接）
struct LevelCardSheet: View {
    @State var data: LevelCardData
    @State private var face: LevelCardFace = .front
    @State private var images: [LevelCardFace: UIImage] = [:]
    @State private var pngs: [LevelCardFace: Data] = [:]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    VStack(spacing: 0) {
                        card
                        Button {
                            flip()
                        } label: {
                            Label("翻面", systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(TextActionStyle())
                    }
                    Toggle(isOn: $data.showsURL) {
                        Text("印上网址")
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                    }
                    .tint(AppTheme.Colors.success)
                    if data.avatar != nil {
                        Toggle(isOn: $data.showsAvatar) {
                            Text("印上头像")
                                .font(AppTheme.Typography.subheadlineBold)
                                .foregroundStyle(AppTheme.Colors.ink)
                        }
                        .tint(AppTheme.Colors.success)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            if let image = images[face], let png = pngs[face] {
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
            // 两面都画好，翻面时不用等
            var rendered: [LevelCardFace: UIImage] = [:]
            for side in [LevelCardFace.front, .back] {
                rendered[side] = await LevelCardRenderer.render(data, face: side)
            }
            images = rendered
            pngs = rendered.compactMapValues { $0.pngData() }
        }
    }

    /// 卡片：两面叠在一起，只显示当前这一面
    private var card: some View {
        ZStack {
            if let front = images[.front], let back = images[.back] {
                faceImage(front).modifier(CardFlip(angle: angle, isBack: false))
                faceImage(back).modifier(CardFlip(angle: angle, isBack: true))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .contentShape(Rectangle())
        .onTapGesture { flip() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
        .accessibilityAddTraits(.isImage)
    }

    private func faceImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    private var angle: Double { face == .back ? 180 : 0 }

    /// 翻到另一面；开了“减弱动态效果”就不转，直接换
    private func flip() {
        Haptics.selection()
        let next: LevelCardFace = face == .front ? .back : .front
        if reduceMotion {
            face = next
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { face = next }
        }
    }

    private var renderKey: String { "\(data.showsURL)-\(data.showsAvatar)" }

    /// 读屏念当前这一面上的字
    private var accessibilitySummary: String {
        var parts = [data.name, data.tier.displayText, data.label.title].compactMap { $0 }
        switch face {
        case .front: parts += [data.play?.style.title, data.play?.style.line].compactMap { $0 }
        case .back: parts += data.backRows.map { "\($0.label) \($0.value)" }
        }
        return parts.joined(separator: ", ")
    }
}
