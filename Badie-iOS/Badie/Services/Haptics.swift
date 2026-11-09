import UIKit

/// 触感反馈（统一入口，方便在测试/降级时关闭）
@MainActor
enum Haptics {
    static var isEnabled = true

    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func impact() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// 头像照片：上传前裁成 320×320 JPEG；显示时按“用户 + 版本”缓存解码结果
@MainActor
enum AvatarPhotos {
    /// 由后端提供照片数据
    static var source: @MainActor (String) -> Data? = { _ in nil }
    /// 内存紧张时系统会自动清掉
    private static let cache = NSCache<NSString, UIImage>()

    static func image(userId: String, avatar: Avatar) -> UIImage? {
        guard let version = avatar.photoVersion else { return nil }
        let key = "\(userId)#\(version)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = source(userId), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 卡片背景照片（和头像分开存，键前面加 card:）
    static func cardImage(userId: String, avatar: Avatar) -> UIImage? {
        guard let version = avatar.cardPhotoVersion else { return nil }
        let key = "card:\(userId)#\(version)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = source(cardKey(userId)), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    nonisolated static func cardKey(_ userId: String) -> String { "card:\(userId)" }

    /// 卡片背景：竖图 600×800
    static let cardSize = CGSize(width: 600, height: 800)

    /// 相册里选的照片：直接解码成长边不超过 1600 像素的图再裁（4800 万像素的原图全尺寸解码要上百 MB），放在后台做
    nonisolated static func image(fromPhoto data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1600,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
    }

    /// 按裁剪框（照片坐标）出 JPEG：默认 320×320 的头像。服务器每张最多 256 KB，太大就再压一压
    nonisolated static func jpegData(from image: UIImage, crop: CGRect, size: CGSize = CGSize(width: 320, height: 320)) -> Data? {
        guard crop.width > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let k = size.width / crop.width
        let output = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // JPEG 没有透明：透明的 PNG 先铺白底，不然是黑的
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: -crop.minX * k, y: -crop.minY * k, width: image.size.width * k, height: image.size.height * k))
        }
        for quality in [0.8, 0.65, 0.5, 0.35] {
            if let data = output.jpegData(compressionQuality: quality), data.count <= 250_000 { return data }
        }
        return nil
    }

    /// 居中裁成正方形并压缩。按 1 倍出图：默认按屏幕倍率会变成 960×960，超过服务器 256 KB 的上限
    nonisolated static func jpegData(from image: UIImage, side: CGFloat = 320) -> Data? {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let aspect = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }
}
