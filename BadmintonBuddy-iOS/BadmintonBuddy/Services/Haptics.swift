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

/// 本人头像照片的本地存储（不上传）
enum AvatarStore {
    private static func url(for userId: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("avatar-\(userId).jpg")
    }

    static func image(for userId: String?) -> UIImage? {
        guard let userId, let url = url(for: userId), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, for userId: String) {
        guard let url = url(for: userId) else { return }
        let size = CGSize(width: 320, height: 320)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            let aspect = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        if let data = scaled.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func delete(for userId: String?) {
        guard let userId, let url = url(for: userId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
