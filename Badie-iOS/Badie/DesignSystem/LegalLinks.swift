import SwiftUI
import UIKit

/// 用户协议、隐私政策、联系我们：网站上的页面，在系统浏览器里打开
struct LegalLinks: View {
    static let terms = URL(string: "https://badie.rsvp/terms/")!
    static let privacy = URL(string: "https://badie.rsvp/privacy/")!
    static let contact = URL(string: "https://badie.rsvp/contact/")!
    static let supportEmail = "support@badie.rsvp"

    var body: some View {
        // 字大或语言长的时候一行放不下，改成竖排
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.lg) { links }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) { links }
        }
        .font(AppTheme.Typography.footnoteBold)
        .foregroundStyle(AppTheme.Colors.inkSecondary)
    }

    @ViewBuilder private var links: some View {
        Link(destination: Self.terms) { Text("用户协议").underline() }
        Link(destination: Self.privacy) { Text("隐私政策").underline() }
        Link(destination: Self.contact) { Text("联系我们").underline() }
    }
}

/// 设置里的“联系我们”：用邮件 App 写信（末尾带上版本号，方便排查）；手机没设置邮件时改成复制地址
struct ContactCard: View {
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("问题、bug、建议，或者我们漏掉的球馆，都可以发邮件告诉我们。一般几天内回复。")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: LegalLinks.supportEmail)
                .font(AppTheme.Typography.bodyBold)
                .foregroundStyle(AppTheme.Colors.ink)
                .textSelection(.enabled)
            HStack(spacing: AppTheme.Spacing.md) {
                Button("写邮件") { write() }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                Button(copied ? String(localized: "已复制") : String(localized: "复制邮箱地址")) { copy() }
                    .buttonStyle(TextActionStyle())
            }
        }
        .card(AppTheme.Colors.surface, shadow: .zero)
    }

    private func write() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = LegalLinks.supportEmail
        mail.queryItems = [
            URLQueryItem(name: "subject", value: "Badie"),
            URLQueryItem(name: "body", value: "\n\n—\nBadie \(version) · iOS \(UIDevice.current.systemVersion)"),
        ]
        guard let url = mail.url else { return copy() }
        openURL(url) { accepted in if !accepted { copy() } }
    }

    private func copy() {
        UIPasteboard.general.string = LegalLinks.supportEmail
        copied = true
    }
}
