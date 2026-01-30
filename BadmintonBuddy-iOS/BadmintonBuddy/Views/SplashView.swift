import SwiftUI

struct SplashView: View {
    @EnvironmentObject var appState: AppState
    @State private var shuttlecockOffset: CGFloat = 0
    @State private var showButton = false
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xxl) {
            Spacer()
            
            // Logo 区域
            VStack(spacing: AppTheme.Spacing.lg) {
                // 羽毛球动画
                Text("🏸")
                    .font(.system(size: 80))
                    .offset(y: shuttlecockOffset)
                    .animation(
                        .easeInOut(duration: 1)
                        .repeatForever(autoreverses: true),
                        value: shuttlecockOffset
                    )
                    .onAppear {
                        shuttlecockOffset = -20
                    }
                
                // 标题
                Text("羽毛球搭子")
                    .font(AppTheme.Typography.largeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.Colors.primary, AppTheme.Colors.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("找到你的最佳球友")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // 开始按钮
            if showButton {
                PrimaryButton("开始匹配") {
                    appState.currentScreen = .auth
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer()
                .frame(height: AppTheme.Spacing.xxl)
        }
        .onAppear {
            // 延迟显示按钮
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showButton = true
                }
            }
        }
    }
}

#Preview {
    SplashView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
