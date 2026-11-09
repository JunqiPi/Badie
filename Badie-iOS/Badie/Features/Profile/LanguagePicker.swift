import SwiftUI

/// 设置 → App 语言：在 App 里直接选，马上生效
struct LanguagePicker: View {
    @EnvironmentObject private var host: AppHost
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("App 语言")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.horizontal, AppTheme.Spacing.screen)
            ScrollView {
                VStack(spacing: 0) {
                    option(nil, title: String(localized: "跟随系统"), detail: AppLanguage.name(AppLanguage.system))
                    ForEach(AppLanguage.supported, id: \.self) { code in
                        Divider()
                        option(code, title: AppLanguage.name(code))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func option(_ code: String?, title: String, detail: String? = nil) -> some View {
        let selected = AppLanguage.chosen == code
        return Button {
            Haptics.selection()
            dismiss()
            // 等弹窗收起再换：界面会按新语言从头建一遍
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                host.setLanguage(code)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(title)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    // 每种语言用自己的写法和读音
                    .environment(\.locale, Locale(identifier: code ?? AppLanguage.current))
                if let detail {
                    Text(detail)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(AppTheme.Colors.ink)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(Text(verbatim: title))
    }
}
