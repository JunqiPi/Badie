import SwiftUI

/// 用户协议、隐私政策：网站上的页面，在系统浏览器里打开
struct LegalLinks: View {
    static let terms = URL(string: "https://badie.rsvp/terms/")!
    static let privacy = URL(string: "https://badie.rsvp/privacy/")!

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Link(destination: Self.terms) { Text("用户协议").underline() }
            Link(destination: Self.privacy) { Text("隐私政策").underline() }
        }
        .font(AppTheme.Typography.footnoteBold)
        .foregroundStyle(AppTheme.Colors.inkSecondary)
    }
}
