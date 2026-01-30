import SwiftUI

struct MatchingView: View {
    @EnvironmentObject var appState: AppState
    @State private var dotCount = 0
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            
            // 搜索动画
            ZStack {
                // 脉冲环
                SearchingRing(delay: 0)
                SearchingRing(delay: 0.5)
                SearchingRing(delay: 1.0)
                
                // 玩家卡片
                PlayerCard(
                    name: appState.currentUser?.nickname ?? "我",
                    level: appState.currentUser?.level ?? .intermediate
                )
            }
            .frame(height: 220)
            
            // 匹配文字
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("正在寻找对手\(String(repeating: ".", count: dotCount))")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("\(appState.selectedMode?.rawValue ?? "单打")模式")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.primary)
            }
            
            Spacer()
            
            // 取消按钮
            Button {
                appState.cancelMatching()
            } label: {
                Text("取消匹配")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.accent)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                            .stroke(AppTheme.Colors.accent, lineWidth: 2)
                    )
            }
            
            Spacer()
                .frame(height: AppTheme.Spacing.xxl)
        }
        .onAppear {
            startDotAnimation()
        }
    }
    
    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}

#Preview {
    MatchingView()
        .environmentObject({
            let state = AppState()
            state.currentUser = User(id: "1", nickname: "球友1", phone: "", level: .intermediate, totalGames: 0, wins: 0)
            state.selectedMode = .singles
            return state
        }())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
