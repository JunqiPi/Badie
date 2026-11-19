import SwiftUI

// MARK: - 付给组织者（付钱的人的半屏）
// Venmo / Cash App / PayPal 打开对应的链接，金额和备注预先填好；Zelle 没有链接，只能复制。
// 钱不经过 Badie：付完自己点“我付了”，组织者那边直接算已付（写“自己标的”）

struct PaySheet: View {
    let sessionId: String
    let groupName: String
    let startsAt: Date
    let endsAt: Date
    let pay: GroupTonight.Pay
    /// 打开时是不是已付
    let paid: Bool
    let onPaidChange: (Bool) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var isPaid: Bool?
    @State private var saving = false

    private var paidNow: Bool { isPaid ?? paid }

    /// 付款备注：Badie · 周三 7 PM · 球群名
    private var note: String {
        "Badie · \(startsAt.formatted(.dateTime.weekday(.abbreviated).hour())) · \(groupName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("付给 \(pay.to)")
                                .font(AppTheme.Typography.title2)
                                .foregroundStyle(AppTheme.Colors.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text(verbatim: subtitle)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        if let amount = pay.amount {
                            Text(verbatim: FeeText.text(amount))
                                .scaledFont(size: 40, relativeTo: .title)
                                .foregroundStyle(AppTheme.Colors.ink)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.xl)

                    let handles = pay.handles ?? PaymentHandles()
                    if let venmo = handles.venmo, !venmo.isEmpty {
                        appRow("Venmo", handle: "@" + venmo, url: PayLinks.venmo(venmo, amount: pay.amount, note: note))
                    }
                    if let cashapp = handles.cashapp, !cashapp.isEmpty {
                        appRow("Cash App", handle: "$" + cashapp, url: PayLinks.cashApp(cashapp, amount: pay.amount))
                    }
                    if let paypal = handles.paypal, !paypal.isEmpty {
                        appRow("PayPal", handle: paypal, url: PayLinks.payPal(paypal, amount: pay.amount))
                    }
                    if let zelle = handles.zelle, !zelle.isEmpty {
                        zelleRow(zelle)
                    }
                    if handles.isEmpty {
                        Text("\(pay.to) 还没填收款方式，当面付就行。")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    } else {
                        Text("备注：\(note)")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            VStack(spacing: AppTheme.Spacing.xs) {
                if paidNow {
                    Label("已付", systemImage: "checkmark.circle.fill")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.success)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    // 只能改回自己标的（组织者标的不动）
                    if pay.paidSelf == true || isPaid == true {
                        Button("改回没付") { mark(false) }
                            .buttonStyle(TextActionStyle())
                            .disabled(saving)
                    }
                } else {
                    Button("我付了") { mark(true) }
                        .buttonStyle(.brutalPrimary)
                        .disabled(saving)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .showsToasts()
    }

    private var subtitle: String {
        let slot = TimeSlot(date: startsAt, startTime: startsAt, endTime: endsAt)
        return groupName.isEmpty ? slot.formattedFull : "\(slot.formattedFull) · \(groupName)"
    }

    private func appRow(_ name: String, handle: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(verbatim: name)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer(minLength: 0)
                Text(verbatim: handle)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 56)
            .sticker(AppTheme.Colors.surface, radius: 16)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func zelleRow(_ zelle: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Zelle")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text(verbatim: zelle)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = zelle
                appState.showToast(String(localized: "已复制"), style: .success)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(BrutalButtonStyle(kind: .accent(AppTheme.Colors.surfaceMuted), size: .small, fullWidth: false))
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.sm)
        .frame(minHeight: 56)
        .sticker(AppTheme.Colors.surface, radius: 16, shadow: .zero)
    }

    private func mark(_ paid: Bool) {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await appState.backend.remoteIPaid(sessionId, paid: paid)
                isPaid = paid
                onPaidChange(paid)
                if paid {
                    Haptics.success()
                    dismiss()
                }
            } catch {
                appState.showClubError(error)
            }
        }
    }
}

// MARK: - 我的 → 收款方式

struct PaymentHandlesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var handles = PaymentHandles()
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "收款方式"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    Text("只给同一场的人看。都可以不填。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    BrutalTextField(label: String(localized: "Venmo 用户名"), placeholder: "@name", text: field(\.venmo))
                    BrutalTextField(label: String(localized: "Cash App 的 $cashtag"), placeholder: "$cashtag", text: field(\.cashapp))
                    BrutalTextField(label: String(localized: "PayPal.me 用户名"), placeholder: "paypal.me/name", text: field(\.paypal))
                    BrutalTextField(label: String(localized: "Zelle 邮箱或手机号"), placeholder: "", text: field(\.zelle),
                                    keyboard: .emailAddress)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            Button("保存") { save() }
                .buttonStyle(.brutalPrimary)
                .disabled(saving)
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
                .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { InsetDivider() }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task {
            if let mine = try? await appState.backend.remoteMyPaymentHandles() { handles = mine }
        }
    }

    private func field(_ key: WritableKeyPath<PaymentHandles, String?>) -> Binding<String> {
        Binding(get: { handles[keyPath: key] ?? "" }, set: { handles[keyPath: key] = $0 })
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await appState.backend.remoteSetPaymentHandles(handles)
                appState.showToast(String(localized: "已保存"), style: .success)
                router.pop()
            } catch {
                appState.showClubError(error)
            }
        }
    }
}
