import SwiftUI

// MARK: - 点头像看资料
//
// 任何出现别人头像的地方都可以点开对方的个人页（自己的头像不响应）。
// 资料页用就近的 sheet 弹出，所以在全屏匹配流程、其他弹窗里也能用。

private struct ProfileLinkModifier: ViewModifier {
    let userId: String?
    var allowsInvite = true

    @EnvironmentObject private var appState: AppState
    @State private var presented: PlayerSheetItem?

    func body(content: Content) -> some View {
        if let userId, !userId.isEmpty, userId != appState.currentUser?.id {
            Button {
                Haptics.tap()
                presented = PlayerSheetItem(id: userId)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看个人资料")
            .sheet(item: $presented) { item in
                PlayerProfileSheet(userId: item.id, allowsInvite: allowsInvite)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        } else {
            content
        }
    }
}

extension View {
    /// 点击打开这位球友的个人资料（自己或未知用户时不响应）
    func opensProfile(_ userId: String?, allowsInvite: Bool = true) -> some View {
        modifier(ProfileLinkModifier(userId: userId, allowsInvite: allowsInvite))
    }
}
