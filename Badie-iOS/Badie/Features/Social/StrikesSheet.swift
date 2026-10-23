import SwiftUI

/// 爽约记录：现在能不能约球、每一次的情况；48 小时内可以申诉
struct StrikesSheet: View {
    @EnvironmentObject private var appState: AppState

    @State private var appealing: Int?
    @State private var text = ""
    @State private var isSending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                if let strikes = appState.strikes {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(strikes.suspendedUntil?.suspensionText ?? String(localized: "近 180 天爽约 \(strikes.recent) 次"))
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                        Text("180 天内第二次：7 天不能约球。第三次：以后不能约球。180 天内没再爽约就重新计数。")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(strikes.strikes) { strike in
                        row(strike)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { appState.markStrikesSeen() }
    }

    private func row(_ strike: MyStrikes.Strike) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text([strike.startsAt.formatted(.dateTime.month().day().weekday()), strike.venue].compactMap { $0 }.joined(separator: " · "))
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer(minLength: 0)
                if let status = statusText(strike.status) {
                    Text(status)
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            if appealing == strike.id {
                Text("发生了什么？")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                TextField(String(localized: "比如：去了，只是忘了签到。"), text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(AppTheme.Spacing.md)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                HStack {
                    Button("提交申诉") { send(strike.id) }
                        .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small))
                        .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                    Button("取消") { appealing = nil }
                        .buttonStyle(TextActionStyle())
                }
            } else if strike.canAppeal {
                Button("申诉") {
                    text = ""
                    appealing = strike.id
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
            }
        }
        .padding(AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private func statusText(_ status: MyStrikes.Status) -> String? {
        switch status {
        case .active: return nil
        case .appealed: return String(localized: "申诉审核中")
        case .upheld: return String(localized: "申诉未通过")
        case .overturned: return String(localized: "申诉后已撤销")
        }
    }

    private func send(_ id: Int) {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await appState.appealStrike(id, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                appealing = nil
                appState.showToast(String(localized: "申诉已提交，我们会在 24 小时内回复。"), style: .success)
            } catch {
                appState.showError(error)
            }
        }
    }
}
