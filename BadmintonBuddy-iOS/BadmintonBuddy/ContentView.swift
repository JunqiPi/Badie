import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            AppTheme.Colors.bgDark
                .ignoresSafeArea()
            
            switch appState.currentScreen {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.move(edge: .trailing))
            case .home:
                HomeView()
                    .transition(.move(edge: .trailing))
            case .matching:
                MatchingView()
                    .transition(.opacity)
            case .matchSuccess:
                MatchSuccessView()
                    .transition(.scale.combined(with: .opacity))
            case .confirmed:
                ConfirmedView()
                    .transition(.scale)
            case .profile:
                ProfileView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: AppTheme.Animation.normal), value: appState.currentScreen)
    }
}

// MARK: - 确认成功页
struct ConfirmedView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            // 成功图标
            Text("✅")
                .font(.system(size: 80))
                .scaleEffect(1)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: true)
            
            Text("约球成功！")
                .font(AppTheme.Typography.title)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text("已向对方发送约球邀请")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            // 约球卡片
            VStack(alignment: .leading, spacing: 0) {
                // 头部
                HStack {
                    Text("🏸")
                    Text("羽毛球约战")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.primaryGradient)
                
                // 内容
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    infoRow("对手", appState.matchedOpponent?.nickname ?? "")
                    infoRow("地点", "朝阳区体育中心羽毛球馆")
                    infoRow("时间", "今天 19:00")
                    infoRow("模式", appState.selectedMode?.rawValue ?? "单打")
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.Colors.bgCard)
            .cornerRadius(AppTheme.Radius.lg)
            .padding(.horizontal, AppTheme.Spacing.lg)
            
            Spacer()
            
            PrimaryButton("返回首页") {
                appState.selectedMode = nil
                appState.matchedOpponent = nil
                appState.currentScreen = .home
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + "：")
                .foregroundColor(AppTheme.Colors.textSecondary)
            Text(value)
                .foregroundColor(AppTheme.Colors.textPrimary)
        }
        .font(AppTheme.Typography.body)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
