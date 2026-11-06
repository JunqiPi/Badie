import SwiftUI

/// 帮助与反馈：在 App 里直接写给我们，管理员在后台回复（回复会作为通知发回来）；也可以发邮件
struct HelpSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FeedbackKind = .bug
    @State private var text = ""
    @State private var isSending = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    Text("帮助与反馈")
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Spacer()
                    IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                }
                .padding(.top, AppTheme.Spacing.xl)

                if appState.isRemote {
                    Text("我们会读每一条，回复会出现在你的通知里。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: AppTheme.Spacing.sm) {
                        ForEach(FeedbackKind.allCases) { option in
                            ChoiceChip(title: option.title, isSelected: kind == option) { kind = option }
                        }
                    }
                    BrutalTextField(label: kind.title, placeholder: kind.placeholder, text: $text,
                                    characterLimit: FeedbackKind.maxLength, axis: .vertical)
                    Text("会一起发送：\(FeedbackKind.contextLine)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("发送") { send() }
                        .buttonStyle(BrutalButtonStyle(kind: .primary))
                        .disabled(isSending || trimmed.count < 5)
                }

                Text("也可以发邮件")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.top, AppTheme.Spacing.sm)
                ContactCard()
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await appState.submitFeedback(kind, text: trimmed)
                appState.showToast(String(localized: "收到了，谢谢你。"), style: .success)
                dismiss()
            } catch {
                appState.showError(error)
            }
        }
    }
}

enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug, idea, court, other

    static let maxLength = 2000

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return String(localized: "遇到问题")
        case .idea: return String(localized: "建议")
        case .court: return String(localized: "球馆信息")
        case .other: return String(localized: "其他")
        }
    }

    var placeholder: String {
        switch self {
        case .bug: return String(localized: "在哪个页面、做了什么、看到了什么")
        case .idea: return String(localized: "想要什么功能，用在什么场合")
        case .court: return String(localized: "球馆名字和哪里不对，或者我们漏掉的球馆")
        case .other: return String(localized: "想说什么都可以")
        }
    }

    /// 版本、系统、机型、语言：排查问题用，提交前显示给用户看
    static var context: [String: String] {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
        return ["app": version, "platform": "ios", "os": "iOS \(UIDevice.current.systemVersion)",
                "device": deviceModel, "locale": AppLanguage.current]
    }

    static var contextLine: String {
        let c = context
        return ["Badie \(c["app"] ?? "")", c["os"], c["device"], c["locale"]].compactMap { $0 }.joined(separator: " · ")
    }

    /// 机型代号，比如 iPhone17,1
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
