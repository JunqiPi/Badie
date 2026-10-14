import SwiftUI

// MARK: - 高水平认证申请（7+ 起）

struct VerificationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var kind: VerificationStatus = .tournament
    @State private var tier = VerificationStatus.tournament.minTier
    @State private var link = ""
    @State private var nameOnRecord = ""
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var didSetup = false

    private var request: VerificationRequest? { appState.backend.myVerificationRequest() }

    private var linkProblem: String? {
        link.isEmpty ? nil : VerificationEvidence.problem(with: link, for: kind)
    }

    private var canSubmit: Bool {
        !isSubmitting && !link.isEmpty && linkProblem == nil
            && nameOnRecord.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "高水平认证")
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    intro
                    if let request, request.status == .pending {
                        pendingCard(request)
                    } else {
                        if let request, request.status == .rejected {
                            NoticeBanner(icon: "exclamationmark.circle.fill",
                                         text: "上次申请没有通过：\(request.reviewNote ?? "证据无法核实")。可以补充材料后重新申请。",
                                         tint: AppTheme.Colors.peach)
                        }
                        kindPicker
                        tierPicker
                        evidenceFields
                        privacyNote
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            if request?.status != .pending {
                Button {
                    submit()
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if isSubmitting { LoadingDots() }
                        Text("提交审核")
                    }
                }
                .buttonStyle(.brutalPrimary)
                .disabled(!canSubmit)
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear(perform: setup)
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if let user = appState.currentUser {
                HStack(spacing: AppTheme.Spacing.sm) {
                    LevelBadge(tier: user.displayTier)
                    VerifiedBadge(status: user.verificationStatus)
                    Spacer(minLength: 0)
                }
            }
            Text("问卷和球友评价最多到 7−。7 起只看能公开查到的证据：赛事成绩、全国排名或运动员等级证书、BWF 世界排名。")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("认证后以认证档位为准；球友评价最多往下调 1 档（比如伤病、状态下滑）。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(AppTheme.Colors.surface, shadow: .zero)
    }

    private func pendingCard(_ request: VerificationRequest) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                TagPill(text: "审核中", icon: "hourglass", fill: AppTheme.Colors.butter)
                Spacer()
                Text("提交于 \(DateText.shortDay(request.submittedAt))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            InfoRow(icon: "checkmark.seal.fill", tint: AppTheme.Colors.lime, title: "申请 \(request.claimedTier.text)",
                    subtitle: request.kind.title)
            InfoRow(icon: "link", title: "证据", subtitle: request.evidenceURL)
            InfoRow(icon: "person.text.rectangle", tint: AppTheme.Colors.peach, title: "证据上的姓名",
                    subtitle: request.nameOnRecord)
            Text("一般 \(VerificationRequest.reviewDays) 个工作日内审核完，结果会发到通知里。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Button(role: .destructive) {
                appState.backend.cancelVerificationRequest()
                appState.showToast("已撤回申请")
            } label: {
                Text("撤回申请")
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
        }
        .card(AppTheme.Colors.surface, shadow: .zero)
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: "证据类型")
            ForEach([VerificationStatus.tournament, .national, .bwf]) { option in
                Button {
                    Haptics.selection()
                    kind = option
                    tier = min(max(tier, option.minTier), option.maxTier)
                } label: {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        Image(systemName: kind == option ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.ink)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(option.title)
                                    .font(AppTheme.Typography.headline)
                                Spacer()
                                Text("\(option.minTier.code)–\(option.maxTier.code)")
                                    .font(AppTheme.Typography.footnoteBold)
                                    .monospacedDigit()
                            }
                            Text(SkillLevel.evidenceSummary(for: option))
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sticker(kind == option ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface,
                             radius: AppTheme.Radius.md, shadow: .zero)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == option ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    private var tierPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: "申请的档位")
            HStack {
                Text("按证据能证明的最高一档填，审核时可能下调")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                TierStepper(tier: $tier, range: kind.minTier...kind.maxTier)
                    .frame(width: 170)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SkillLevel.tierCriteria(for: tier), id: \.self) { line in
                    Label(line, systemImage: "checkmark")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sticker(AppTheme.Colors.surfaceMuted, radius: AppTheme.Radius.md, shadow: .zero)
        }
    }

    private var evidenceFields: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            BrutalTextField(label: kind == .national ? "证据链接或证书编号" : "证据链接",
                            placeholder: VerificationEvidence.placeholder(for: kind), text: $link,
                            keyboard: .URL, contentType: .URL, errorText: linkProblem)
            BrutalTextField(label: "成绩 / 证书上的姓名", placeholder: "和证件一致，例如 Wei Zhang", text: $nameOnRecord,
                            contentType: .name, characterLimit: 40)
            BrutalTextField(label: "补充说明（选填）", placeholder: "例：2025 洛杉矶公开赛 A 组男双亚军", text: $note,
                            characterLimit: 200, axis: .vertical)
        }
    }

    private var privacyNote: some View {
        Label("链接和姓名只给审核人员看，不会公开；审核时会核对证件。冒用他人成绩会被封号。",
              systemImage: "lock.fill")
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        // 已认证过：默认从下一类证据开始
        if let user = appState.currentUser, user.verificationStatus != .unverified {
            let next = VerificationStatus.allCases.first { $0.maxTier > user.tierCap && $0 != .unverified } ?? .bwf
            kind = next
            tier = next.minTier
        }
        #if DEBUG
        if let demo = appState.verificationDemo {
            kind = demo.kind
            tier = demo.tier
            link = demo.link
            nameOnRecord = demo.name
            note = demo.note
        }
        #endif
    }

    private func submit() {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try appState.backend.submitVerification(kind: kind, tier: tier, evidenceURL: link,
                                                    nameOnRecord: nameOnRecord, note: note)
            Haptics.success()
            appState.showToast("已提交，审核结果会发到通知里", style: .success)
        } catch {
            Haptics.error()
            appState.showError(error)
        }
    }
}
