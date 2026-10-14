import SwiftUI

// MARK: - 待评价列表

struct SurveyListView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var surveyManager: SurveyManager

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "待评价")
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    NoticeBanner(icon: "lock.shield.fill",
                                 text: "评价匿名，只展示汇总结果；双方都提交后（或 48 小时后）才会计入，避免“互相客气”和报复性差评。",
                                 tint: AppTheme.Colors.sky)
                    if surveyManager.pendingSurveys.isEmpty {
                        EmptyStateView(icon: "checkmark.seal.fill", title: "都评价完啦", message: "谢谢你让社区更靠谱。", tint: AppTheme.Colors.mint)
                    }
                    ForEach(surveyManager.pendingSurveys) { survey in
                        Button {
                            router.open(.survey(pendingId: survey.id))
                        } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                AvatarView(text: survey.opponentAvatarText, paletteIndex: survey.opponentAvatar.paletteIndex, size: 46)
                                    .opensProfile(survey.opponentId, allowsInvite: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("评价 \(survey.opponentNickname)")
                                        .font(AppTheme.Typography.headline)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                    Text("\(DateText.relativeDay(survey.matchDate)) · \(survey.courtName)")
                                        .font(AppTheme.Typography.footnote)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                TagPill(text: DateText.remaining(until: survey.expiresAt), icon: "hourglass", fill: AppTheme.Colors.pink)
                            }
                            .padding(AppTheme.Spacing.md)
                            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear { surveyManager.refresh() }
    }
}

// MARK: - 评价表单

struct SurveyFormView: View {
    let pendingId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var surveyManager: SurveyManager

    @State private var attendance: AttendanceAnswer = .onTime
    @State private var calibration: LevelCalibration? = .accurate
    @State private var skillRating = SkillTier(level: 4)
    @State private var characterRating = 5
    @State private var tags: Set<SurveyTag> = []
    @State private var issues: Set<SurveyIssue> = []
    @State private var wantsRematch = false
    @State private var isSubmitting = false
    @State private var didSetup = false
    /// 提交前保存一份，避免提交后列表刷新导致页面消失
    @State private var snapshot: PendingSurvey?

    private var survey: PendingSurvey? { surveyManager.survey(id: pendingId) ?? snapshot }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "赛后评价")
            if let survey {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                        opponentCard(survey)
                        attendanceQuestion
                        levelQuestion(survey)
                        characterQuestion
                        tagsQuestion
                        issuesQuestion
                        rematchQuestion
                        Text("评价匿名，只展示汇总；双方都提交后（或 48 小时后）才会计入。")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
                Button {
                    Task { await submit(survey) }
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if isSubmitting { LoadingDots() }
                        Text("提交评价")
                    }
                }
                .buttonStyle(.brutalPrimary)
                .disabled(isSubmitting || survey.isExpired())
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            } else {
                Spacer()
                EmptyStateView(icon: "hourglass.bottomhalf.filled", title: "这份评价已提交或已过期",
                               message: "评价需要在球局结束后 48 小时内完成。")
                Spacer()
            }
        }
        .onAppear(perform: setup)
    }

    // MARK: Sections

    private func opponentCard(_ survey: PendingSurvey) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            AvatarView(text: survey.opponentAvatarText, paletteIndex: survey.opponentAvatar.paletteIndex, size: 60)
                .opensProfile(survey.opponentId, allowsInvite: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(survey.opponentNickname)
                    .font(AppTheme.Typography.title3)
                LevelBadge(tier: survey.opponentTier)
                Text("\(DateText.relativeDay(survey.matchDate)) · \(survey.courtName)")
                    .font(AppTheme.Typography.footnote)
                    .opacity(0.75)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Image(systemName: "hourglass")
                    .font(.system(size: 16, weight: .bold))
                Text(DateText.remaining(until: survey.expiresAt))
                    .font(AppTheme.Typography.caption)
            }
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .card(AppTheme.Colors.lavender)
    }

    private var attendanceQuestion: some View {
        question("TA 准时到场了吗？", hint: "到场情况会计入对方的履约记录") {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(AttendanceAnswer.allCases) { answer in
                    optionCard(
                        title: answer.rawValue,
                        icon: icon(for: answer),
                        isSelected: attendance == answer,
                        tint: answer == .noShow ? AppTheme.Colors.pink : AppTheme.Colors.lime
                    ) {
                        attendance = answer
                    }
                }
            }
        }
    }

    private func levelQuestion(_ survey: PendingSurvey) -> some View {
        question("TA 的实际水平和标注的 \(survey.opponentTier.text) 比？", hint: "高低各一档（1/3 级）；差得多就精确调，越如实越好") {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(LevelCalibration.allCases) { option in
                    optionCard(
                        title: option.rawValue,
                        subtitle: option.rating(from: survey.opponentTier).text,
                        icon: icon(for: option),
                        isSelected: calibration == option,
                        tint: AppTheme.Colors.lime
                    ) {
                        calibration = option
                        skillRating = option.rating(from: survey.opponentTier)
                    }
                }
            }
            HStack {
                Text("精确到档")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                TierStepper(tier: Binding(
                    get: { skillRating },
                    set: { value in
                        skillRating = value
                        calibration = LevelCalibration.allCases.first { $0.rating(from: survey.opponentTier) == value }
                    }
                ))
                .frame(width: 180)
            }
        }
    }

    private var characterQuestion: some View {
        question("球品如何？", hint: "\(characterHint) · 只用于匹配排序，不会显示分数") {
            RatingPicker(rating: $characterRating)
        }
    }

    private var tagsQuestion: some View {
        question("TA 的优点（可选）", hint: "5 位以上球友评价后，大家给得最多的会显示在 TA 的主页") {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(SurveyTag.allCases) { tag in
                    ChoiceChip(title: tag.rawValue, isSelected: tags.contains(tag), tint: AppTheme.Colors.mint) {
                        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                    }
                }
            }
        }
    }

    private var issuesQuestion: some View {
        question("有什么需要 TA 注意的？（可选）", hint: "不公开、不扣分；多位球友都提到时，我们会私下提醒 TA，不说是谁") {
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(SurveyIssue.allCases) { issue in
                    ChoiceChip(title: issue.rawValue, isSelected: issues.contains(issue), tint: AppTheme.Colors.peach) {
                        if issues.contains(issue) { issues.remove(issue) } else { issues.insert(issue) }
                    }
                }
            }
        }
    }

    private var rematchQuestion: some View {
        Toggle(isOn: $wantsRematch) {
            VStack(alignment: .leading, spacing: 2) {
                Text("下次还想和 TA 打")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text("只有你们都选了才会告诉双方；只有一方选，谁也不会知道")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
        }
        .tint(AppTheme.Colors.success)
    }

    private var characterHint: String {
        switch characterRating {
        case 1: return "很差：言语冒犯或危险动作"
        case 2: return "较差：不太尊重人"
        case 3: return "一般"
        case 4: return "不错：友善配合"
        default: return "非常好：下次还想约"
        }
    }

    // MARK: Building blocks

    private func question<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(hint)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            content()
        }
    }

    private func optionCard(
        title: String,
        subtitle: String? = nil,
        icon: String,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            withAnimation(AppTheme.Motion.standard) { action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(AppTheme.Typography.subheadlineBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .sticker(isSelected ? tint : AppTheme.Colors.surface, radius: AppTheme.Radius.md,
                     shadow: isSelected ? AppTheme.Elevation.low : .zero)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func icon(for answer: AttendanceAnswer) -> String {
        switch answer {
        case .onTime: return "checkmark.circle.fill"
        case .late: return "tortoise.fill"
        case .noShow: return "person.fill.xmark"
        }
    }

    private func icon(for option: LevelCalibration) -> String {
        switch option {
        case .lower: return "arrow.down.circle.fill"
        case .accurate: return "equal.circle.fill"
        case .higher: return "arrow.up.circle.fill"
        }
    }

    // MARK: Actions

    private func setup() {
        guard !didSetup, let survey = surveyManager.survey(id: pendingId) else { return }
        didSetup = true
        snapshot = survey
        skillRating = survey.opponentTier
    }

    private func submit(_ survey: PendingSurvey) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await surveyManager.submit(
                survey,
                skillRating: skillRating,
                attendance: attendance,
                characterRating: characterRating,
                tags: SurveyTag.allCases.filter { tags.contains($0) },
                issues: SurveyIssue.allCases.filter { issues.contains($0) },
                wantsRematch: wantsRematch
            )
            appState.showToast("评价已提交，谢谢！", style: .success)
            router.pop()
            if let next = surveyManager.pending(forGame: survey.matchId).first {
                router.open(.survey(pendingId: next.id))
            }
        } catch {
            appState.showError(error)
        }
    }
}
