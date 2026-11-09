import SwiftUI

/// 选完照片：双指缩放、拖动。头像是圆框；卡片背景是 3:4 的竖框
struct AvatarCropSheet: View {
    struct Item: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    enum Kind {
        case avatar
        case card

        /// 宽 / 高
        var aspect: CGFloat { self == .avatar ? 1 : AvatarPhotos.cardSize.width / AvatarPhotos.cardSize.height }
        var output: CGSize { self == .avatar ? CGSize(width: 320, height: 320) : AvatarPhotos.cardSize }
    }

    let image: UIImage
    var shape: Kind = .avatar
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var frameSize = CGSize(width: 1, height: 1)

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(TextActionStyle())
                Spacer()
                Text(shape == .avatar ? "调整头像" : "调整卡片背景")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                Button("使用") { finish() }
                    .buttonStyle(TextActionStyle())
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.lg)

            GeometryReader { proxy in
                let size = proxy.size
                let scale = baseScale(size) * zoom
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .offset(offset)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay {
                        if shape == .avatar {
                            // 圆圈外面压暗
                            Rectangle()
                                .fill(Color.black.opacity(0.45))
                                .mask { Rectangle().overlay { Circle().blendMode(.destinationOut) }.compositingGroup() }
                                .allowsHitTesting(false)
                            Circle().strokeBorder(.white, lineWidth: 2).allowsHitTesting(false)
                        } else {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    zoom = min(4, max(1, lastZoom * value.magnification))
                                    offset = clamped(offset, size: size)
                                }
                                .onEnded { _ in lastZoom = zoom },
                            DragGesture()
                                .onChanged { value in
                                    offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                                            height: lastOffset.height + value.translation.height), size: size)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .onAppear { frameSize = size }
                    .onChange(of: size) { _, size in frameSize = size }
            }
            .aspectRatio(shape.aspect, contentMode: .fit)
            .padding(.horizontal, AppTheme.Spacing.screen)

            Text("双指缩放，拖动调整位置")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Spacer(minLength: 0)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    /// 照片正好盖满整个框
    private func baseScale(_ size: CGSize) -> CGFloat {
        max(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
    }

    /// 照片始终盖住整个框，拖不出空白
    private func clamped(_ value: CGSize, size: CGSize) -> CGSize {
        let scale = baseScale(size) * zoom
        let maxX = max(0, (image.size.width * scale - size.width) / 2)
        let maxY = max(0, (image.size.height * scale - size.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, value.width)), height: min(maxY, max(-maxY, value.height)))
    }

    private func finish() {
        let scale = baseScale(frameSize) * zoom
        let width = frameSize.width / scale
        let height = frameSize.height / scale
        let center = CGPoint(x: image.size.width / 2 - offset.width / scale, y: image.size.height / 2 - offset.height / scale)
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        if let data = AvatarPhotos.jpegData(from: image, crop: rect, size: shape.output) { onDone(data) }
        dismiss()
    }
}
