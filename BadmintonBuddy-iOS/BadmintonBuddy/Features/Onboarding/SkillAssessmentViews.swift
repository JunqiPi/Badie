import SwiftUI

// MARK: - 定级问卷：一次一题，答完自动出等级

struct SkillAssessmentView: View {
    @Binding var answers: [String: Int]
    @State private var index = 0
    @State private var showGuide = false

    private var questions: [AssessmentQuestion] { SkillAssessment.questions }
    private var result: SkillAssessmentResult? { SkillAssessment.evaluate(answers) }
    private var isShowingResult: Bool { index >= questions.count && result != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if isShowingResult, let result {
                AssessmentResultCard(result: result)
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        showGuide = true
                    } label: {
                        Label("看 1–9 级对照表", systemImage: "list.number")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                    Button {
                        withAnimation(AppTheme.Motion.standard) {
                            answers = [:]
                            index = 0
                        }
                    } label: {
                        Label("重新回答", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                }
            } else {
                questionCard(questions[min(index, questions.count - 1)])
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(AppTheme.Motion.standard, value: index)
        .onAppear {
            // 已经答完（返回上一步再回来）直接显示结果
            if result != nil { index = questions.count }
        }
        .sheet(isPresented: $showGuide) {
            SkillLevelGuideView(highlight: result?.tier)
                .presentationDragIndicator(.visible)
        }
    }

    private func questionCard(_ question: AssessmentQuestion) -> some View {
        let position = (questions.firstIndex(of: question) ?? 0) + 1
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("第 \(position) / \(questions.count) 题")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                if position > 1 {
                    Button("上一题") {
                        Haptics.tap()
                        index = max(0, index - 1)
                    }
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(minHeight: 32)
                }
            }
            ProgressBar(progress: Double(position - 1) / Double(questions.count))
            VStack(alignment: .leading, spacing: 4) {
                Text(question.title)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(question.hint)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(question.options) { option in
                    optionRow(option, question: question)
                }
            }
        }
    }

    private func optionRow(_ option: AssessmentOption, question: AssessmentQuestion) -> some View {
        let selected = answers[question.id] == option.id
        let letters = ["A", "B", "C", "D", "E"]
        return Button {
            Haptics.selection()
            answers[question.id] = option.id
            // 选完自动进入下一题
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                index = min(questions.count, (questions.firstIndex(of: question) ?? index) + 1)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(letters[min(option.id, letters.count - 1)])
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(selected ? AppTheme.Colors.lime : AppTheme.Colors.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(selected ? Color(hex: 0x17140F) : AppTheme.Colors.surfaceMuted))
                Text(option.text)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 半透明底色不能叠实心投影（投影会透出来变成深色），选中态不加投影
            .sticker(selected ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface,
                     radius: AppTheme.Radius.md, shadow: .zero)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - 定级结果

struct AssessmentResultCard: View {
    let result: SkillAssessmentResult

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("根据你的回答，你的等级是")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(result.tier.text)
                    .scaledFont(size: 44, relativeTo: .largeTitle)
                Text(SkillLevel.name(for: result.level))
                    .font(AppTheme.Typography.title2)
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            Text("\(result.tier.modifier == .base ? "本级" : result.tier.modifier.symbol)：\(result.tier.modifier.meaning)")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.8))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SkillLevel.anchors(for: result.level), id: \.self) { anchor in
                    Label(anchor, systemImage: "checkmark")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.onAccent)
                }
            }
            if let flight = SkillLevel.usFlight(for: result.level) {
                Text("大致相当于美国业余赛 \(flight)")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
            }
            if let gate = result.limitingGate, result.level < SkillLevel.maxSelfSelectable {
                notice("arrow.up.circle.fill", "想到 Lv.\(result.level + 1)：\(gate)")
            }
            if result.needsCalibration {
                notice("scope", "你的比赛经历比技术题的结果高，先按经历定级；打几场后会按球友评价更快校准。")
            }
            if result.isReturning {
                notice("arrow.uturn.backward.circle.fill", "回归球友：按现在的状态定级，球友评价会帮你更快回到原来的水平。")
            }
            if result.suggestsVerification {
                notice("checkmark.seal.fill", "参加过 A 组或 Open 组？问卷最高到 7−，注册后可以凭赛果在资料页申请 7+ 以上的认证。")
            }
            Text("打满 5 场并获得评价后，等级会按球友评价自动校准。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.7))
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.lime, radius: AppTheme.Radius.lg)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }

    private func notice(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppTheme.Typography.footnoteBold)
            .foregroundStyle(AppTheme.Colors.onAccent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.55)))
    }
}

// MARK: - 1–9 级对照表（27 档）

struct SkillLevelGuideView: View {
    var highlight: SkillTier?
    var showsCloseButton = true
    /// 打开时滚到哪一级（默认是当前所在的级）
    var scrollLevel: Int?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("等级对照表")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if showsCloseButton {
                    IconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("1–9 级，每级再分 −、本级、+ 三档，共 27 档。对照“能稳定做到”的那一级，而不是偶尔打出来的球。")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        modifierLegend
                        ForEach(Array(SkillLevel.range), id: \.self) { level in
                            levelCard(level)
                                .id(level)
                        }
                        Text("1–7 级参考打球吧“业余 1–9 级”、中羽在线 0–9 级、USTA NTRP 的写法；7+ 起按可查证的赛果、全国排名、运动员技术等级和 BWF 世界排名划分。中国羽协的等级是“九级最低”，方向和这里相反；美国赛事组别各赛事不同，仅作大致对应。")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .onAppear {
                    if let scrollLevel {
                        proxy.scrollTo(scrollLevel, anchor: .top)
                    } else if let highlight {
                        proxy.scrollTo(highlight.level, anchor: .center)
                    }
                }
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    /// −/本级/+ 的通用含义
    private var modifierLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([SkillTier.Modifier.minus, .base, .plus], id: \.self) { modifier in
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text(modifier == .base ? "本级" : modifier.symbol)
                        .font(AppTheme.Typography.footnoteBold)
                        .frame(width: 36, alignment: .leading)
                    Text(modifier.meaning)
                        .font(AppTheme.Typography.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AppTheme.Colors.ink)
            }
            Text("7 级起差距大，每一档单独定义（见下方）。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.surfaceMuted, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func levelCard(_ level: Int) -> some View {
        let isCurrent = level == highlight?.level
        let tiers = [SkillTier.Modifier.minus, .base, .plus].map { SkillTier(level: level, modifier: $0) }
        let detailed = level >= SkillLevel.maxSelfSelectable
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("\(level)")
                    .scaledFont(size: 20, relativeTo: .title3)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.Colors.paletteColor(level)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                VStack(alignment: .leading, spacing: 0) {
                    Text(SkillLevel.name(for: level))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text([SkillLevel.usFlight(for: level).map { "≈ \($0)" }, SkillLevel.typicalExperience(for: level)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    TagPill(text: "你在这里", fill: AppTheme.Colors.lime)
                } else if level > SkillLevel.maxSelfSelectable {
                    TagPill(text: "需认证", icon: "lock.fill", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
                }
            }
            if !detailed {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SkillLevel.anchors(for: level), id: \.self) { anchor in
                        Label(anchor, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.ink)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(tiers) { tier in
                        tierChip(tier)
                    }
                }
            } else {
                if level == SkillLevel.maxSelfSelectable {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(SkillLevel.anchors(for: level), id: \.self) { anchor in
                            Label(anchor, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.ink)
                        }
                    }
                }
                VStack(spacing: 6) {
                    ForEach(tiers) { tier in
                        tierRow(tier)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(isCurrent ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface, radius: AppTheme.Radius.md,
                 shadow: .zero)
        .accessibilityElement(children: .combine)
    }

    /// 1–6 级：三个小胶囊，标出你在哪一档
    private func tierChip(_ tier: SkillTier) -> some View {
        let selected = tier == highlight
        return Text(tier.code)
            .font(AppTheme.Typography.footnoteBold)
            .monospacedDigit()
            .foregroundStyle(selected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? AppTheme.Colors.lime : AppTheme.Colors.surfaceMuted))
            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: selected ? 1.5 : 0))
            .accessibilityLabel(tier.spokenText + (selected ? "，你在这里" : ""))
    }

    /// 7–9 级：每一档单独的标准
    private func tierRow(_ tier: SkillTier) -> some View {
        let selected = tier == highlight
        let locked = tier > VerificationStatus.unverifiedMaxTier
        return HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Text(tier.code)
                .font(AppTheme.Typography.subheadlineBold)
                .monospacedDigit()
                .foregroundStyle(selected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                .frame(width: 40, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AppTheme.Colors.lime : AppTheme.Colors.surfaceMuted))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SkillLevel.tierCriteria(for: tier), id: \.self) { line in
                    Text(line)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .accessibilityLabel("需认证")
            }
        }
    }
}

/// 小圆点列表
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 重新测评（每 90 天一次）

struct ReassessSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("重新测评")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)
            ScrollView {
                SkillAssessmentView(answers: $answers)
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
            if let result = SkillAssessment.evaluate(answers) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    Button("使用 \(result.tier.displayText)") {
                        do {
                            try appState.backend.updateAssessment(result)
                            Haptics.success()
                            appState.showToast("问卷等级已更新为 \(result.tier.text)", style: .success)
                            dismiss()
                        } catch {
                            appState.showError(error)
                        }
                    }
                    .buttonStyle(.brutalPrimary)
                    Text("90 天内只能重测一次；已有球友评价的话，显示等级仍以球友评价为主")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
