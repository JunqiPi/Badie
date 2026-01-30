import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var onlineCount = 128
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部用户信息
            headerView
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // 地图区域
                    mapView
                    
                    // 模式选择
                    modeSelectionView
                    
                    // 匹配按钮
                    matchButtonView
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            startOnlineCountTimer()
        }
    }
    
    // MARK: - 顶部栏
    private var headerView: some View {
        HStack {
            // 用户信息
            Button {
                appState.currentScreen = .profile
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    AvatarView(size: 48)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.currentUser?.nickname ?? "球友")
                            .font(AppTheme.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        Text(appState.currentUser?.level.displayText ?? "⭐ 业余")
                            .font(AppTheme.Typography.small)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            // 在线人数
            HStack(spacing: AppTheme.Spacing.sm) {
                PulseDot()
                Text("\(onlineCount) 人在线")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.bgCard)
    }
    
    // MARK: - 地图区域
    private var mapView: some View {
        ZStack {
            // 地图背景
            LinearGradient(
                colors: [Color(hex: "1e3a5f"), Color(hex: "0d2137")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 其他玩家位置
            ForEach(0..<5, id: \.self) { index in
                otherPlayerMarker(index: index)
            }
            
            // 我的位置
            VStack {
                ZStack {
                    // 脉冲效果
                    Circle()
                        .fill(AppTheme.Colors.primary.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .scaleEffect(1.5)
                        .opacity(0.5)
                    
                    Text("📍")
                        .font(.system(size: 32))
                }
            }
            
            // 底部位置信息
            VStack {
                Spacer()
                HStack {
                    Text("📍 当前位置：朝阳区体育中心")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    Spacer()
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(height: 200)
        .cornerRadius(AppTheme.Radius.lg)
    }
    
    private func otherPlayerMarker(index: Int) -> some View {
        let positions: [(CGFloat, CGFloat)] = [
            (-80, -60), (100, -40), (-60, 40), (80, 20), (20, 60)
        ]
        let pos = positions[index % positions.count]
        
        return Text("🏸")
            .font(.system(size: 20))
            .offset(x: pos.0, y: pos.1)
            .animation(
                .easeInOut(duration: 3)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.5),
                value: true
            )
    }
    
    // MARK: - 模式选择
    private var modeSelectionView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("选择对战模式")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            HStack(spacing: AppTheme.Spacing.md) {
                ForEach(GameMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        isSelected: appState.selectedMode == mode
                    ) {
                        appState.selectedMode = mode
                    }
                }
            }
        }
    }
    
    // MARK: - 匹配按钮
    private var matchButtonView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Button {
                appState.startMatching()
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("⚡")
                        .font(.system(size: 24))
                    Text("开始匹配")
                        .font(AppTheme.Typography.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.lg)
                .background(
                    appState.selectedMode == nil
                        ? AnyShapeStyle(AppTheme.Colors.bgLight)
                        : AnyShapeStyle(AppTheme.Colors.secondaryGradient)
                )
                .cornerRadius(AppTheme.Radius.lg)
                .shadow(
                    color: appState.selectedMode == nil ? .clear : AppTheme.Colors.secondary.opacity(0.4),
                    radius: 10,
                    y: 4
                )
            }
            .disabled(appState.selectedMode == nil)
            
            Text(appState.selectedMode == nil ? "请先选择对战模式" : "已选择\(appState.selectedMode!.rawValue)模式")
                .font(AppTheme.Typography.caption)
                .foregroundColor(
                    appState.selectedMode == nil
                        ? AppTheme.Colors.textSecondary
                        : AppTheme.Colors.primary
                )
        }
    }
    
    // MARK: - 在线人数定时器
    private func startOnlineCountTimer() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            onlineCount = 120 + Int.random(in: -10...10)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject({
            let state = AppState()
            state.currentUser = User(id: "1", nickname: "球友1", phone: "138****1234", level: .intermediate, totalGames: 23, wins: 18)
            return state
        }())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
