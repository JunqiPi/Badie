import SwiftUI

/// 定级用的性别：男 / 女，附说明（男女等级分开算，只用来定级和匹配，不代表性别认同）
struct GenderPicker: View {
    @Binding var selection: Gender

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                Text("定级用的性别")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                RulesButton(title: String(localized: "定级用的性别"), points: [
                    String(localized: "羽毛球男女的等级分开算，这里只用来给你定级和公平匹配，不代表你的性别认同，随时可以在设置里改。"),
                ])
            }
            SegmentedSticker(options: Gender.choices, selection: $selection, title: { $0.label })
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
                RulesButton(title: String(localized: "谁能来"), points: [
                    String(localized: "男女一起打时，女子等级按低约 1.5 级来算，这样比赛势均力敌。"),
                    String(localized: "只有符合条件的人能看到和加入。"),
                ])
            }
        }
    }
}

/// 项目（约球、开局）：不限、男单 / 女单 / 男双 / 女双、混双；换成单打时混双自动改回不限。标题由各页面按自己的样式写
struct EventPicker: View {
    let mode: GameMode
    let gender: Gender
    /// 直接约的那个人的性别
    var partner: Gender?
    @Binding var selection: PlayEvent?

    private var choices: [PlayEvent?] { PlayEvent.choices(mode: mode, gender: gender, partner: partner) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(choices, id: \.self) { event in
                    ChoiceChip(title: event?.title(mode: mode) ?? String(localized: "不限"), isSelected: selection == event) {
                        selection = event
                    }
                }
                RulesButton(title: String(localized: "项目"), points: choices.map { PlayEvent.caption($0) })
            }
        }
        .onChange(of: mode) { _, _ in
            if !choices.contains(selection) { selection = nil }
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

    /// 按项目算：混双男生和男生比、女生和女生比，用自己的等级；其余同上
    func level(in event: PlayEvent?) -> Int {
        event == .mixed ? min(9, max(1, Int(displayTier.rating.rounded()))) : level(for: event?.gender)
    }
}
