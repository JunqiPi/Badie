import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            AppLogo()
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(bounce ? -6 : 4))
                .offset(y: bounce ? -14 : 0)
            Wordmark(size: 46)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
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
