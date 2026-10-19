import SwiftUI

/// 密码输入框：右边的眼睛显示 / 隐藏。textContentType 用 .password / .newPassword，
/// iPhone 钥匙串才会自动填入（面容 ID 解锁），注册时还会建议一个强密码
struct PasswordField: View {
    @Binding var text: String
    var placeholder = String(localized: "密码")
    /// 注册、重设、修改时是新密码
    var isNew = false
    var invalid = false
    var onSubmit: () -> Void = {}

    @State private var shown = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Group {
                if shown {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(isNew ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit(onSubmit)
            .focused($focused)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .accessibilityLabel(placeholder)

            Button {
                shown.toggle()
                focused = true
            } label: {
                Image(systemName: shown ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shown ? String(localized: "隐藏密码") : String(localized: "显示密码"))
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.xs)
        .frame(minHeight: 52)
        .sticker(AppTheme.Colors.surface, radius: 14, shadow: focused ? AppTheme.Elevation.low : .zero,
                 stroke: invalid ? AppTheme.Colors.danger : AppTheme.Colors.stroke)
    }
}
