import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            ShuttlecockMark(size: 104)
                .rotationEffect(.degrees(bounce ? -10 : 6))
                .offset(y: bounce ? -18 : 0)
                .shadow(color: AppTheme.Colors.shadow.opacity(0.15), radius: 0, x: 0, y: bounce ? 26 : 8)
            VStack(spacing: AppTheme.Spacing.sm) {
                Wordmark(size: 46)
                Text("找到你的羽毛球搭子")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            Spacer()
            Text("按水平 · 按时间 · 按距离")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
                .padding(.bottom, AppTheme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task {
            if appState.skipsSplash {
                appState.finishLaunch()
                return
            }
            withAnimation(AppTheme.Motion.standard) { appeared = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bounce = true }
            }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            appState.finishLaunch()
        }
        .accessibilityElement(children: .combine)
    }
}
