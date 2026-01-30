import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locationManager: LocationManager
    @State private var onlineCount = 128
    @State private var selectedPlayer: User? = nil
    @State private var showPlayerDetail = false
    
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
                        
                        Text(appState.currentUser?.displayLevelText ?? "⭐ 业余")
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
        RealMapView(
            nearbyPlayers: locationManager.nearbyPlayers,
            onPlayerTapped: { player in
                selectedPlayer = player
                showPlayerDetail = true
            }
        )
        .frame(height: 200)
        .cornerRadius(AppTheme.Radius.lg)
        .sheet(isPresented: $showPlayerDetail) {
            if let player = selectedPlayer {
                PlayerDetailSheet(player: player)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
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
            state.currentUser = User(id: "1", nickname: "球友1", phone: "138****1234", selfReportedLevel: 4, totalGames: 23, wins: 18)
            return state
        }())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}

// MARK: - 玩家详情弹窗
/// 显示玩家的详细信息，包括昵称、技能等级和声誉评分
/// Requirements: 1.6
struct PlayerDetailSheet: View {
    let player: User
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 头部
            HStack {
                Text("球友详情")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            
            // 玩家信息卡片
            VStack(spacing: AppTheme.Spacing.md) {
                // 头像和基本信息
                HStack(spacing: AppTheme.Spacing.lg) {
                    // 头像
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.primaryGradient)
                            .frame(width: 80, height: 80)
                        
                        Text("🏸")
                            .font(.system(size: 36))
                    }
                    
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(player.nickname)
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        // 技能等级
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Text("技能等级")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            
                            Text("Lv.\(player.displayLevel)")
                                .font(AppTheme.Typography.body)
                                .fontWeight(.bold)
                                .foregroundColor(skillLevelColor(for: player.displayLevel))
                        }
                        
                        // 新玩家徽章
                        if player.reputation.isNewPlayer {
                            Text("🆕 新玩家")
                                .font(AppTheme.Typography.small)
                                .foregroundColor(AppTheme.Colors.warning)
                        }
                    }
                    
                    Spacer()
                }
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.Colors.bgCard)
                .cornerRadius(AppTheme.Radius.lg)
                
                // 声誉评分
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("声誉评分")
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    HStack(spacing: AppTheme.Spacing.lg) {
                        // 技能准确度
                        reputationItem(
                            icon: "🎯",
                            label: "技能准确",
                            value: String(format: "%.1f", player.reputation.averageSkillAccuracy)
                        )
                        
                        // 守时率
                        reputationItem(
                            icon: "⏰",
                            label: "守时率",
                            value: String(format: "%.0f%%", player.reputation.punctualityPercentage)
                        )
                        
                        // 人品评分
                        reputationItem(
                            icon: "⭐",
                            label: "人品评分",
                            value: String(format: "%.1f", player.reputation.averageCharacterRating)
                        )
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.Colors.bgCard)
                .cornerRadius(AppTheme.Radius.lg)
                
                // 比赛统计
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("比赛统计")
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    HStack(spacing: AppTheme.Spacing.lg) {
                        statItem(label: "总场次", value: "\(player.totalGames)")
                        statItem(label: "胜场", value: "\(player.wins)")
                        statItem(label: "胜率", value: String(format: "%.0f%%", player.winRate))
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.Colors.bgCard)
                .cornerRadius(AppTheme.Radius.lg)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            
            Spacer()
        }
        .background(AppTheme.Colors.bgDark)
    }
    
    // MARK: - Helper Views
    
    private func reputationItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text(icon)
                .font(.system(size: 24))
            
            Text(value)
                .font(AppTheme.Typography.body)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text(label)
                .font(AppTheme.Typography.small)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text(value)
                .font(AppTheme.Typography.headline)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.Colors.primary)
            
            Text(label)
                .font(AppTheme.Typography.small)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    /// 根据技能等级返回对应颜色
    private func skillLevelColor(for level: Int) -> Color {
        switch level {
        case 1...3:
            return AppTheme.Colors.success // 初级 - 绿色
        case 4...6:
            return AppTheme.Colors.primary // 中级 - 青绿
        case 7...9:
            return AppTheme.Colors.secondary // 高级 - 紫色
        default:
            return AppTheme.Colors.textSecondary
        }
    }
}

#Preview("PlayerDetailSheet") {
    PlayerDetailSheet(
        player: User(
            id: "1",
            nickname: "羽球达人",
            phone: "138****1234",
            selfReportedLevel: 6,
            totalGames: 50,
            wins: 35,
            location: Coordinate(latitude: 39.91, longitude: 116.41)
        )
    )
    .preferredColorScheme(.dark)
}
