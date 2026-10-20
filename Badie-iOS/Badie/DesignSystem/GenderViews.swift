import SwiftUI

/// 定级用的性别：男 / 女，附说明（男女等级分开算，只用来定级和匹配，不代表性别认同）
struct GenderPicker: View {
    @Binding var selection: Gender

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("定级用的性别")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            SegmentedSticker(options: Gender.choices, selection: $selection, title: { $0.label })
            Text("羽毛球男女的等级分开算，这里只用来给你定级和公平匹配，不代表你的性别认同，随时可以在设置里改。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// “谁能来 / 和谁打”：不限，或只限某个性别（nil = 不限）。标题由各页面按自己的样式写
struct AudiencePicker: View {
    /// 能选的限定：约球男女都能选；开局、建群只能限定自己的性别
    let options: [Gender]
    @Binding var selection: Gender?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ChoiceChip(title: String(localized: "不限"), isSelected: selection == nil) { selection = nil }
                ForEach(options) { gender in
                    ChoiceChip(title: gender.onlyLabel, isSelected: selection == gender) { selection = gender }
                }
            }
            Text(selection == nil ? String(localized: "男女一起打时，女子等级按低约 1.5 级来算，这样比赛势均力敌。")
                                  : String(localized: "只有符合条件的人能看到和加入。"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 以前注册、还没选性别的人：打开 App 先补上（男女的等级分开算）
struct GenderPromptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var gender: Gender = .unspecified
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Spacer()
            Text("还有一件事")
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Text("按男子还是女子等级？")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
            GenderPicker(selection: $gender)
            Spacer()
            Button {
                Task {
                    guard var user = appState.currentUser else { return }
                    isSaving = true
                    user.gender = gender
                    _ = await appState.updateProfile(user)
                    isSaving = false
                }
            } label: {
                Text("继续")
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large))
            .disabled(gender == .unspecified || isSaving)
        }
        .padding(AppTheme.Spacing.xl)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

extension User {
    /// 公开局、球群按参加的人算等级：只限女生按女子等级，男女都能来时女子等级按低 1.5 级换算
    func level(for audience: Gender?) -> Int {
        let offset = gender == .female && audience != .female ? Gender.womenOffset : 0
        return min(9, max(1, Int((displayTier.rating - offset).rounded())))
    }
}
