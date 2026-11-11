import SwiftUI

/// 规则说明放这里：页面上只有一个小“?”，点开是半屏的要点。
/// 页面本身只放名词、数字、状态词；“为什么”“怎么算”都收进来（谁想看谁点）
struct RulesButton: View {
    let title: String
    /// 每条一句话
    let points: [String]

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .sheet(isPresented: $showing) {
            RulesSheet(title: title, points: points)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// “?”点开的半屏：标题 + 一条条要点
struct RulesSheet: View {
    let title: String
    let points: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Text(title)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.top, AppTheme.Spacing.xl)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    ForEach(points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                            Circle()
                                .fill(AppTheme.Colors.ink)
                                .frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            Text(point)
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.Colors.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

/// 待办小标签：图标 + 一个词 + 红色数字（首页的“挑战 1”“好友申请 1”）
struct CountPill: View {
    let icon: String
    let title: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(AppTheme.Typography.footnoteBold)
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppTheme.Colors.dangerFill))
                }
            }
            .foregroundStyle(AppTheme.Colors.ink)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: 36)
            .background(Capsule().fill(AppTheme.Colors.surface))
            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(verbatim: "\(title) \(count)"))
    }
}
