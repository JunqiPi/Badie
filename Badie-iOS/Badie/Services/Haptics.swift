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
    private static var cache: [String: UIImage] = [:]

    static func image(userId: String, avatar: Avatar) -> UIImage? {
        guard let version = avatar.photoVersion else { return nil }
        let key = "\(userId)#\(version)"
        if let cached = cache[key] { return cached }
        guard let data = source(userId), let image = UIImage(data: data) else { return nil }
        cache[key] = image
        return image
    }

    /// 居中裁成正方形并压缩
    nonisolated static func jpegData(from image: UIImage, side: CGFloat = 320) -> Data? {
        let size = CGSize(width: side, height: side)
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in
            let aspect = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }
}
