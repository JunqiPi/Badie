import SwiftUI
import CoreImage.CIFilterBuiltins

/// 昵称 + 编号（昵称#0042）：昵称可以重名，编号用来区分
struct NicknameText: View {
    let user: User

    var body: some View {
        HStack(spacing: 0) {
            Text(user.nickname)
                .lineLimit(1)
            Text(user.tagText)
                .opacity(0.5)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// 我的加球友链接：当面扫二维码，或者发给对方；重置后旧链接失效
struct FriendLinkSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager

    @State private var confirmsReset = false
    @State private var isResetting = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            if let user = appState.currentUser, let link = user.friendLink {
                VStack(spacing: AppTheme.Spacing.sm) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text("拿到这个链接的人都能加你")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                .padding(.top, AppTheme.Spacing.xl)

                QRCodeView(text: link.absoluteString)
                    .frame(width: 240, height: 240)
                    .padding(AppTheme.Spacing.lg)
                    .sticker(.white, radius: AppTheme.Radius.lg)
                    .accessibilityLabel("加球友二维码")

                VStack(spacing: AppTheme.Spacing.sm) {
                    ShareLink(item: link) {
                        Label("发给好友", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                    Button("重置链接") { confirmsReset = true }
                        .buttonStyle(TextActionStyle())
                        .disabled(isResetting)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .confirmationDialog("重置加球友链接？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("重置链接", role: .destructive) { reset() }
        } message: {
            Text("旧链接和二维码会失效")
        }
    }

    private func reset() {
        isResetting = true
        Task {
            defer { isResetting = false }
            do {
                try await friendManager.resetFriendLink()
                appState.showToast(String(localized: "新链接已生成"), style: .success)
            } catch {
                appState.showToast((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, style: .error)
            }
        }
    }
}

/// 黑白二维码（放大时不模糊）；链接变了才重新生成
private struct QRCodeView: View {
    let text: String
    @State private var image: UIImage?

    private static let context = CIContext()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: text) { image = Self.image(for: text) }
    }

    private static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
