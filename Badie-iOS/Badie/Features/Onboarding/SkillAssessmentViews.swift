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
        let letters = ["A", "B", "C", "D", "E", "F", "G"]
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
                Text(result.tier.name)
                    .font(AppTheme.Typography.title2)
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            Text("\(result.tier.code)：\(SkillLevel.tierCriteria(for: result.tier).first ?? result.tier.modifier.meaning)")
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.onAccent)
                .fixedSize(horizontal: false, vertical: true)
            if let flight = SkillLevel.usFlight(for: result.level) {
                Text("大致相当于美国业余赛 \(flight)")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
            }
            if !result.dimensions.isEmpty {
                dimensionProfile
            }
            if let gate = result.limitingGate {
                notice("arrow.up.circle.fill", gate)
            } else if result.tier < SkillAssessment.maxTier, let next = SkillLevel.tierCriteria(for: result.tier.offset(by: 1)).first {
                notice("arrow.up.circle.fill", String(localized: "想到 \(result.tier.offset(by: 1).code)：\(next)"))
            }
            if result.needsCalibration {
                notice("scope", String(localized: "你的比赛经历比技术题的结果高，先按经历定级；打几场后会按球友评价更快校准。"))
            }
            if result.isReturning {
                notice("arrow.uturn.backward.circle.fill", String(localized: "回归球友：按现在的状态定级，球友评价会帮你更快回到原来的水平。"))
            }
            if result.tier == SkillAssessment.maxTier {
                notice("person.2.fill", String(localized: "\(SkillAssessment.maxTier.code) 是问卷能给的最高档；球友评价最多推到 \(VerificationStatus.unverifiedMaxTier.code)，7 起凭证据认证。"))
            }
            if result.suggestsVerification {
                notice("checkmark.seal.fill", String(localized: "打过 A 组或 Open 组？7 起凭赛果、全国排名或运动员等级证书认证，注册后在资料页申请。"))
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

    /// 技术分项：每项几级，最强的标出来（技术特点）
    private var dimensionProfile: some View {
        let strengths = Set(result.strengths.map(\.id))
        let lowest = result.dimensions.map(\.level).min()
        return VStack(alignment: .leading, spacing: 6) {
            Text("技术分项")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
            FlowLayout(spacing: 6) {
                ForEach(result.dimensions) { dimension in
                    let isStrength = strengths.contains(dimension.id)
                    let isWeak = !strengths.isEmpty && dimension.level == lowest
                    HStack(spacing: 4) {
                        if isStrength {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text("\(dimension.name) \(dimension.level)")
                    }
                    .font(AppTheme.Typography.caption.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(isWeak ? AppTheme.Colors.peach : Color.white.opacity(isStrength ? 0.9 : 0.55)))
                    .accessibilityLabel(isStrength ? String(localized: "\(dimension.name) \(dimension.level) 级，技术特点")
                        : isWeak ? String(localized: "\(dimension.name) \(dimension.level) 级，短板")
                        : String(localized: "\(dimension.name) \(dimension.level) 级"))
                }
            }
        }
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
    /// 展开了“分项标准”的等级
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("等级对照表")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if showsCloseButton {
                    IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("1–9 级，每级再分 −、本级、+ 三档，共 27 档。3–6 级一级比一级多一个维度：技术会不会 → 主动球好不好 → 被动球能不能摆脱、战术 → 在俱乐部里的位置。每级可以展开看分项标准（步法、发力、前后场、攻防）。对照“能稳定做到”的，而不是偶尔打出来的球；7 起是州级、全国、国际水平，只看能查到的赛果、排名和证书。")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        modifierLegend
                        ForEach(Array(SkillLevel.range), id: \.self) { level in
                            levelCard(level)
                                .id(level)
                        }
                        Text("分项标准参考中羽在线论坛流传的 1–9 级分项描述；1–6 级还参考了打球吧“业余 1–9 级”和 USTA NTRP；7 起按 tournamentsoftware 公开成绩、USAB 全国排名、《运动员技术等级标准》（2025 版）和 BWF 世界排名划分。中国羽协的业余等级是“九级最低”，方向和这里相反；美国各赛事的组别强度不同，所以按“最高组 / 次高组”的相对位置认定。")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .onAppear {
                    // 默认展开当前所在的级（或演示时指定的级）
                    if let level = scrollLevel ?? highlight?.level { expanded.insert(level) }
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
                    Text(modifier == .base ? String(localized: "本级") : modifier.symbol)
                        .font(AppTheme.Typography.footnoteBold)
                        .frame(width: 36, alignment: .leading)
                    Text(modifier.meaning)
                        .font(AppTheme.Typography.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AppTheme.Colors.ink)
            }
            Text("7 级起差距大，每一档单独命名，按证据定档。")
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
                    TagPill(text: String(localized: "你在这里"), fill: AppTheme.Colors.lime)
                } else if level > SkillLevel.maxSelfSelectable {
                    TagPill(text: String(localized: "需认证"), icon: "lock.fill", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
                }
            }
            if level <= SkillLevel.maxSelfSelectable {
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
            dimensionNotes(level)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(isCurrent ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface, radius: AppTheme.Radius.md,
                 shadow: .zero)
        .accessibilityElement(children: .contain)
    }

    /// 可展开的分项标准：步法、发力、前后场、攻防在这一级是什么样子
    @ViewBuilder
    private func dimensionNotes(_ level: Int) -> some View {
        let notes = SkillLevel.dimensionNotes(for: level)
        if !notes.isEmpty {
            let isOpen = expanded.contains(level)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(AppTheme.Motion.standard) {
                        if isOpen { expanded.remove(level) } else { expanded.insert(level) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .bold))
                        Text(isOpen ? String(localized: "收起分项标准") : String(localized: "分项标准（\(notes.count) 项）"))
                            .font(AppTheme.Typography.footnoteBold)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lv.\(level) 分项标准")
                .accessibilityValue(isOpen ? String(localized: "已展开") : String(localized: "已收起"))
                if isOpen {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes.indices, id: \.self) { index in
                            let note = notes[index]
                            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                                Text(note.name)
                                    .font(AppTheme.Typography.footnoteBold)
                                    .foregroundStyle(AppTheme.Colors.ink)
                                    .frame(width: 72, alignment: .leading)
                                Text(note.text)
                                    .font(AppTheme.Typography.footnote)
                                    .foregroundStyle(AppTheme.Colors.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.Colors.surfaceMuted))
                }
            }
        }
    }

    /// 每一档的标准（7 起需认证的档位带锁）
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
                if tier.level >= SkillLevel.maxSelfSelectable && tier.name != SkillLevel.name(for: tier.level) {
                    Text(tier.name)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                }
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
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
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
                        Task {
                            do {
                                try await appState.backend.saveAssessment(result, answers: answers)
                                Haptics.success()
                                appState.showToast(String(localized: "问卷等级已更新为 \(result.tier.text)"), style: .success)
                                dismiss()
                            } catch {
                                appState.showError(error)
                            }
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
