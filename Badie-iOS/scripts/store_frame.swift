// App Store 截图（海报式）：第 1 张是一句定位加一部完整的手机，中间每张放大一页的关键部分，最后一张只有字和 logo。
// 底色只用品牌的三种：柠檬色、墨色、米色；标出的词（*包住的部分*）单独一行、带色块。
// 位置是按 6.9 英寸（1320 × 2868）的截图调的；6.3 英寸那组由成品等比缩小得到（两种屏幕长宽比相同）。
// 输出和原图一样大的 JPEG（不带透明通道），文件名带顺序号。
// 用法: swift store_frame.swift <captions.json> <语言> <原图目录> <输出目录> <Logo.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 6 else {
    print("用法: swift store_frame.swift <captions.json> <语言> <原图目录> <输出目录> <Logo.png>")
    exit(2)
}
struct Captions: Decodable {
    let order: [String]
    let captions: [String: [String: String]]
}
let config = try JSONDecoder().decode(Captions.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let language = args[2]
let inputDir = URL(fileURLWithPath: args[3])
let outputDir = URL(fileURLWithPath: args[4])
let logoURL = URL(fileURLWithPath: args[5])
guard let captions = config.captions[language] else {
    print("没有 \(language) 的文字")
    exit(1)
}
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let cream = color(0xF5F0E6)
let ink = color(0x17140F)
let lime = color(0xD4F33F)
let lavender = color(0xC8BEFF)

/// 底色、字色、标出部分的底色和字色、面板的投影色
struct Theme {
    let background: NSColor, text: NSColor, box: NSColor, onBox: NSColor, shadow: NSColor
    static let creamTheme = Theme(background: color(0xF5F0E6), text: color(0x17140F), box: color(0xD4F33F), onBox: color(0x17140F), shadow: color(0x17140F))
    static let inkTheme = Theme(background: color(0x17140F), text: color(0xF5F0E6), box: color(0xD4F33F), onBox: color(0x17140F), shadow: color(0xD4F33F))
    static let limeTheme = Theme(background: color(0xD4F33F), text: color(0x17140F), box: color(0x17140F), onBox: color(0xD4F33F), shadow: color(0x17140F))
}

enum Art {
    /// 整部手机，底部出血
    case phone
    /// 界面从 top 往下的部分放进圆角面板（墨色底用）
    case panel(top: CGFloat, scale: CGFloat)
    /// 界面从 top 往下的部分直接铺在底色上（米色底用：App 的底色本来就是米色）
    case flat(top: CGFloat, scale: CGFloat)
    /// “按天看人”的球友卡片：稍微倾斜，后面露出下一张
    case playerCard
    /// 只有 logo
    case logo
}

struct Slide {
    let theme: Theme
    let art: Art
}

/// 每一张：底色和画面。top 是截图里的像素位置（按 1320 宽）
let slides: [String: Slide] = [
    "home": Slide(theme: .limeTheme, art: .phone),
    "matchSetup": Slide(theme: .inkTheme, art: .panel(top: 386, scale: 0.944)),
    "matchFound": Slide(theme: .creamTheme, art: .flat(top: 661, scale: 0.96)),
    "dayCards": Slide(theme: .inkTheme, art: .playerCard),
    "levelResult": Slide(theme: .creamTheme, art: .flat(top: 643, scale: 1.0)),
    "playerNoShow": Slide(theme: .inkTheme, art: .panel(top: 1399, scale: 0.96)),
    "room": Slide(theme: .creamTheme, art: .flat(top: 361, scale: 0.96)),
    "groupDetail": Slide(theme: .inkTheme, art: .panel(top: 361, scale: 0.944)),
    "free": Slide(theme: .limeTheme, art: .logo),
]

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func font(_ size: CGFloat) -> NSFont {
    var font = NSFont.systemFont(ofSize: size, weight: .black)
    if let rounded = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: rounded, size: size) ?? font }
    return font
}

func text(_ string: String, size: CGFloat, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font(size), .foregroundColor: color])
}

/// “明天*谁有空*” → [("明天", false), ("谁有空", true)]：没标出的一行，标出的一行，按原来的先后
func lines(of caption: String) -> [(text: String, boxed: Bool)] {
    let parts = caption.replacingOccurrences(of: "\n", with: " ").components(separatedBy: "*")
    guard parts.count >= 3 else { return [(caption.trimmingCharacters(in: .whitespaces), false)] }
    let before = parts[0].trimmingCharacters(in: .whitespaces)
    let highlighted = parts[1].trimmingCharacters(in: .whitespaces)
    let after = parts[2...].joined().trimmingCharacters(in: .whitespaces)
    var result: [(text: String, boxed: Bool)] = []
    if !before.isEmpty { result.append((before, false)) }
    result.append((highlighted, true))
    if !after.isEmpty { result.append((after, false)) }
    return result
}

// 画布左上角为原点的坐标换成 CoreGraphics 的（左下角为原点）
var canvasHeight: CGFloat = 0
func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasHeight - top - height, width: width, height: height)
}

/// 画标题，返回标题底边的位置（从上往下量）
func drawTitle(_ caption: String, theme: Theme, top: CGFloat, cap: CGFloat, width: CGFloat) -> CGFloat {
    let rows = lines(of: caption)
    let maxWidth = width * 0.86
    // 每行都要放得下，几行用同一个字号
    var size = cap
    for row in rows {
        let padding: CGFloat = row.boxed ? cap * 0.28 : 0
        let natural = text(row.text, size: cap, color: ink).size().width + padding
        if natural > maxWidth { size = min(size, cap * maxWidth / natural) }
    }
    let rowHeight = size * 1.24
    let gap = size * 0.1
    var y = top
    for row in rows {
        let attributed = text(row.text, size: size, color: row.boxed ? theme.onBox : theme.text)
        let measured = attributed.size()
        let padding: CGFloat = row.boxed ? size * 0.14 : 0
        let x = (width - measured.width) / 2
        let box = rect(x - padding, y, measured.width + padding * 2, rowHeight)
        if row.boxed {
            theme.box.setFill()
            box.fill()
        }
        attributed.draw(at: CGPoint(x: x, y: box.minY + (rowHeight - measured.height) / 2))
        y += rowHeight + gap
    }
    return y - gap
}

/// 把 logo 的柠檬色底去掉，只留墨色的羽毛球图形
func logoMark() -> CGImage? {
    guard let logo = loadImage(logoURL) else { return nil }
    let width = logo.width, height = logo.height
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = context.data else { return nil }
    context.draw(logo, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    for index in 0..<(width * height) {
        // 底色的绿色分量约 250，图形约 27：越暗越不透明
        let green = CGFloat(pixels[index * 4 + 1])
        let alpha = max(0, min(1, (235 - green) / 200))
        pixels[index * 4] = UInt8(CGFloat(0x17) * alpha)
        pixels[index * 4 + 1] = UInt8(CGFloat(0x14) * alpha)
        pixels[index * 4 + 2] = UInt8(CGFloat(0x0F) * alpha)
        pixels[index * 4 + 3] = UInt8(255 * alpha)
    }
    return context.makeImage()
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// 在圆角范围里画一张图
func drawClipped(_ image: CGImage, in frame: CGRect, radius: CGFloat, context: CGContext) {
    context.saveGState()
    context.addPath(roundedPath(frame, radius))
    context.clip()
    context.draw(image, in: frame)
    context.restoreGState()
}

for (index, key) in config.order.enumerated() {
    guard let caption = captions[key], let slide = slides[key] else {
        print("跳过 \(language)/\(key)：没有文字或版式")
        continue
    }
    // 最后一张没有截图，画布大小跟第一张一样
    let shot = loadImage(inputDir.appendingPathComponent("store-\(key).png"))
    guard let reference = shot ?? loadImage(inputDir.appendingPathComponent("store-\(config.order[0]).png")) else {
        print("跳过 \(language)/\(key)：没有截图")
        continue
    }
    if case .logo = slide.art {} else if shot == nil {
        print("跳过 \(language)/\(key)：没有截图")
        continue
    }
    let width = CGFloat(reference.width), height = CGFloat(reference.height)
    canvasHeight = height
    let unit = width / 1320  // 下面的数字都是按 1320 宽写的
    guard let context = CGContext(data: nil, width: reference.width, height: reference.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    context.interpolationQuality = .high
    let theme = slide.theme
    context.setFillColor(theme.background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    switch slide.art {
    case .phone:
        guard let shot else { break }
        let bottom = drawTitle(caption, theme: theme, top: 200 * unit, cap: 292 * unit, width: width)
        let screenWidth = 1040 * unit, bezel = 22 * unit, radius = 130 * unit
        let top = bottom + 70 * unit
        let screen = rect((width - screenWidth) / 2, top + bezel, screenWidth, screenWidth * height / width)
        // 机身：比屏幕大一圈，右下多出一点当投影
        context.setFillColor(ink.cgColor)
        context.addPath(roundedPath(screen.insetBy(dx: -bezel, dy: -bezel).offsetBy(dx: 16 * unit, dy: -22 * unit), radius + bezel))
        context.addPath(roundedPath(screen.insetBy(dx: -bezel, dy: -bezel), radius + bezel))
        context.fillPath()
        drawClipped(shot, in: screen, radius: radius, context: context)

    case .panel(let cropTop, let scale), .flat(let cropTop, let scale):
        guard let shot else { break }
        let bottom = drawTitle(caption, theme: theme, top: 210 * unit, cap: 205 * unit, width: width)
        let cropY = cropTop * unit
        guard let piece = shot.cropping(to: CGRect(x: 0, y: cropY, width: width, height: height - cropY)) else { break }
        let pieceWidth = width * scale, pieceHeight = (height - cropY) * scale
        // 高的从标题下面开始、底部出血；矮的放在剩下空间的中间
        let top = pieceHeight > height - bottom - 260 * unit ? bottom + 90 * unit : (bottom + height) / 2 + 10 * unit - pieceHeight / 2
        let frame = rect((width - pieceWidth) / 2, top, pieceWidth, pieceHeight)
        if case .panel = slide.art {
            let radius = 76 * unit
            context.setFillColor(theme.shadow.cgColor)
            context.addPath(roundedPath(frame.offsetBy(dx: 18 * unit, dy: -24 * unit), radius))
            context.fillPath()
            drawClipped(piece, in: frame, radius: radius, context: context)
        } else {
            context.draw(piece, in: frame)
        }

    case .playerCard:
        guard let shot else { break }
        let bottom = drawTitle(caption, theme: theme, top: 210 * unit, cap: 205 * unit, width: width)
        // 卡片和爱心按钮在截图里的位置（6.9 英寸上量的）
        let cardRect = CGRect(x: 60 * unit, y: 556 * unit, width: 1198 * unit, height: 1907 * unit)
        let heartRect = CGRect(x: 698 * unit, y: 2504 * unit, width: 212 * unit, height: 212 * unit)
        guard let card = shot.cropping(to: cardRect), let heart = shot.cropping(to: heartRect) else { break }
        let radius = 66 * unit
        func place(center: CGPoint, angle: CGFloat, scale: CGFloat, draw: (CGRect) -> Void) {
            let size = CGSize(width: cardRect.width * scale, height: cardRect.height * scale)
            context.saveGState()
            context.translateBy(x: center.x, y: height - center.y)
            context.rotate(by: angle * .pi / 180)
            draw(CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            context.restoreGState()
        }
        // 后面露出的下一张：淡紫色
        place(center: CGPoint(x: 770 * unit, y: bottom + 1010 * unit), angle: 7, scale: 0.88) { frame in
            context.setFillColor(lavender.cgColor)
            context.addPath(roundedPath(frame, radius * 0.88))
            context.fillPath()
        }
        place(center: CGPoint(x: 620 * unit, y: bottom + 1040 * unit), angle: -4, scale: 0.92) { frame in
            drawClipped(card, in: frame, radius: radius * 0.92, context: context)
        }
        let heartSize = 300 * unit
        let heartFrame = rect(1080 * unit - heartSize / 2, bottom + 1860 * unit - heartSize / 2, heartSize, heartSize)
        context.saveGState()
        context.addEllipse(in: heartFrame)
        context.clip()
        context.draw(heart, in: heartFrame)
        context.restoreGState()

    case .logo:
        _ = drawTitle(caption, theme: theme, top: 860 * unit, cap: 324 * unit, width: width)
        if let mark = logoMark() {
            let size = 420 * unit
            context.draw(mark, in: rect((width - size) / 2, 1960 * unit - size / 2, size, size))
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else { continue }
    let output = outputDir.appendingPathComponent("\(index + 1)-\(key).jpg")
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.jpeg" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    CGImageDestinationFinalize(destination)
    print("framed \(language)/\(index + 1)-\(key)")
}
