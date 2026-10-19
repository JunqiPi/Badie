import SwiftUI

/// 设置或修改密码：用验证码、Apple、Google 登录过的人也可以加一个，之后用邮箱 + 密码登录
struct PasswordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("设置新密码")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("以后可以用邮箱和这个密码登录。至少 8 位，用一句好记的话最方便。")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PasswordField(text: $password, placeholder: String(localized: "新密码"), isNew: true, invalid: errorText != nil) {
                Task { await save() }
            }
            .onChange(of: password) { _, _ in errorText = nil }
            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isWorking { LoadingDots() }
                    Text("保存密码")
                }
            }
            .buttonStyle(.brutal(.primary))
            .disabled(password.isEmpty || isWorking)
        }
        .padding(AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func save() async {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if let problem = await PasswordRules.problem(password) {
            errorText = problem
            return
        }
        do {
            try await appState.updatePassword(password)
            appState.showToast(String(localized: "密码已保存"), style: .success)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? String(localized: "没能保存，请再试一次。")
        }
    }
}
