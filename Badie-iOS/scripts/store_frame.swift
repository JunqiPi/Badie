// App Store 截图：上方一行大字（*包住的词* 用柠檬色马克笔标出，和 App 里一样），下方是缩小的截图，底部出血。
// 输出和原图一样大的 JPEG（不带透明通道），文件名带顺序号。
// 用法: swift store_frame.swift <captions.json> <语言> <原图目录> <输出目录>
import AppKit

let args = CommandLine.arguments
guard args.count == 5 else {
    print("用法: swift store_frame.swift <captions.json> <语言> <原图目录> <输出目录>")
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
guard let captions = config.captions[language] else {
    print("没有 \(language) 的文字")
    exit(1)
}
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let canvas = color(0xF5F0E6)
let ink = color(0x17140F)
let lime = color(0xD4F33F)

/// “Players at *your level*” → 标出的部分加柠檬色底
func caption(_ text: String, size: CGFloat) -> NSAttributedString {
    var font = NSFont.systemFont(ofSize: size, weight: .black)
    if let rounded = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: rounded, size: size) ?? font }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.08
    let result = NSMutableAttributedString()
    for (index, part) in text.components(separatedBy: "*").enumerated() where !part.isEmpty {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        if index % 2 == 1 { attributes[.backgroundColor] = lime }
        result.append(NSAttributedString(string: part, attributes: attributes))
    }
    return result
}

for (index, screen) in config.order.enumerated() {
    let input = inputDir.appendingPathComponent("store-\(screen).png")
    guard let text = captions[screen],
          let source = CGImageSourceCreateWithURL(input as CFURL, nil),
          let shot = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("跳过 \(language)/\(screen)：没有截图或文字")
        continue
    }
    let width = CGFloat(shot.width), height = CGFloat(shot.height)
    guard let context = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    context.setFillColor(canvas.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // 文字：放在上方 21% 里，放不下就缩小字号
    let captionTop = height * 0.045, captionBottom = height * 0.205
    let textWidth = width * 0.86
    var size = width * 0.082
    var attributed = caption(text, size: size)
    var bounds = attributed.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    while bounds.height > captionBottom - captionTop, size > width * 0.04 {
        size *= 0.94
        attributed = caption(text, size: size)
        bounds = attributed.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let textY = height - captionTop - (captionBottom - captionTop + bounds.height) / 2
    attributed.draw(with: CGRect(x: (width - textWidth) / 2, y: textY, width: textWidth, height: bounds.height),
                    options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()

    // 截图：缩小、圆角、黑边和偏移的实色阴影（App 里卡片的样式），底部超出画布
    let scale: CGFloat = 0.80
    let frame = CGRect(x: (width - width * scale) / 2, y: height - height * 0.225 - height * scale,
                       width: width * scale, height: height * scale)
    let radius = frame.width * 0.12
    let stroke = width * 0.007
    context.setFillColor(ink.cgColor)
    context.addPath(CGPath(roundedRect: frame.offsetBy(dx: width * 0.012, dy: -width * 0.016), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
    context.saveGState()
    context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(shot, in: frame)
    context.restoreGState()
    context.setStrokeColor(ink.cgColor)
    context.setLineWidth(stroke)
    context.addPath(CGPath(roundedRect: frame.insetBy(dx: stroke / 2, dy: stroke / 2), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.strokePath()

    guard let image = context.makeImage() else { continue }
    let output = outputDir.appendingPathComponent("\(index + 1)-\(screen).jpg")
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.jpeg" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    CGImageDestinationFinalize(destination)
    print("framed \(language)/\(index + 1)-\(screen)")
}
