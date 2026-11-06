import SwiftUI

/// 选完照片：双指缩放、拖动，圆圈里的部分就是头像
struct AvatarCropSheet: View {
    struct Item: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    let image: UIImage
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(TextActionStyle())
                Spacer()
                Text("调整头像")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                Button("使用") { finish() }
                    .buttonStyle(TextActionStyle())
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.lg)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let scale = baseScale(side) * zoom
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .offset(offset)
                    .frame(width: side, height: side)
                    .clipped()
                    .overlay {
                        // 圆圈外面压暗
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .mask { Rectangle().overlay { Circle().blendMode(.destinationOut) }.compositingGroup() }
                            .allowsHitTesting(false)
                        Circle().strokeBorder(.white, lineWidth: 2).allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    zoom = min(4, max(1, lastZoom * value.magnification))
                                    offset = clamped(offset, side: side)
                                }
                                .onEnded { _ in lastZoom = zoom },
                            DragGesture()
                                .onChanged { value in
                                    offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                                            height: lastOffset.height + value.translation.height), side: side)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .onAppear { cropSide = side }
                    .onChange(of: side) { _, side in cropSide = side }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppTheme.Spacing.screen)

            Text("双指缩放，拖动调整位置")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Spacer(minLength: 0)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    @State private var cropSide: CGFloat = 1

    /// 短边正好铺满方框
    private func baseScale(_ side: CGFloat) -> CGFloat {
        side / max(1, min(image.size.width, image.size.height))
    }

    /// 照片始终盖住整个方框，拖不出空白
    private func clamped(_ value: CGSize, side: CGFloat) -> CGSize {
        let scale = baseScale(side) * zoom
        let maxX = max(0, (image.size.width * scale - side) / 2)
        let maxY = max(0, (image.size.height * scale - side) / 2)
        return CGSize(width: min(maxX, max(-maxX, value.width)), height: min(maxY, max(-maxY, value.height)))
    }

    private func finish() {
        let scale = baseScale(cropSide) * zoom
        let length = cropSide / scale
        let center = CGPoint(x: image.size.width / 2 - offset.width / scale, y: image.size.height / 2 - offset.height / scale)
        let rect = CGRect(x: center.x - length / 2, y: center.y - length / 2, width: length, height: length)
        if let data = AvatarPhotos.jpegData(from: image, crop: rect) { onDone(data) }
        dismiss()
    }
}
