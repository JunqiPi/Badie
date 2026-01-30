import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locationManager: LocationManager
    @State private var onlineCount = 128
    
    // MARK: - 球馆选择状态（替换原有的玩家选择）
    /// 当前选中的球馆（用于显示详情弹窗）
    /// - Requirements: 10.1
    @State private var selectedCourt: BadmintonCourt? = nil
    
    /// 是否显示球馆详情弹窗
    /// - Requirements: 10.1
    @State private var showCourtDetail = false
    
    /// 是否显示出行半径设置弹窗
    /// - Requirements: 10.4
    @State private var showRadiusSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部用户信息
            headerView
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // 地图区域（显示球馆标记）
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
    
    // MARK: - 地图区域（球馆选择）
    /// 显示地图和球馆标记，支持球馆选择和出行半径设置
    /// - Requirements: 10.1, 10.4
    private var mapView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ZStack(alignment: .topTrailing) {
                // 真实地图视图，显示附近球馆
                RealMapView(
                    nearbyCourts: locationManager.nearbyCourts,
                    selectedCourtIds: appState.selectedCourtIds,
                    onCourtTapped: { court in
                        selectedCourt = court
                        showCourtDetail = true
                    }
                )
                .frame(height: 200)
                .cornerRadius(AppTheme.Radius.lg)
                
                // 出行半径设置按钮
                /// - Requirements: 10.4
                Button {
                    showRadiusSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(AppTheme.Colors.bgCard.opacity(0.9))
                        .clipShape(Circle())
                }
                .padding(AppTheme.Spacing.sm)
                .accessibilityLabel("搜索范围设置")
                .accessibilityHint("点击调整搜索球馆的范围")
            }
            
            // 已选球馆摘要
            /// - Requirements: 10.2
            selectedCourtsSummary
        }
        .sheet(isPresented: $showCourtDetail) {
            if let court = selectedCourt {
                CourtDetailSheet(
                    court: court,
                    isSelected: appState.selectedCourtIds.contains(court.id),
                    userLocation: locationManager.currentLocation.map {
                        Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                    },
                    onToggleSelection: {
                        appState.toggleCourtSelection(court.id)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showRadiusSettings) {
            radiusSettingsSheet
        }
    }
    
    // MARK: - 已选球馆摘要
    /// 显示已选择的球馆数量和名称标签
    /// - Requirements: 5.6, 10.2
    @ViewBuilder
    private var selectedCourtsSummary: some View {
        if !appState.selectedCourtIds.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("已选择 \(appState.selectedCourtIds.count)/\(AppState.maxSelectedCourts) 个球馆")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    // 清除所有选择按钮
                    Button("清除") {
                        appState.clearCourtSelection()
                    }
                    .font(AppTheme.Typography.small)
                    .foregroundColor(AppTheme.Colors.warning)
                    .accessibilityLabel("清除所有选择")
                    .accessibilityHint("点击取消选择所有球馆")
                }
                
                // 已选球馆名称标签
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(selectedCourts, id: \.id) { court in
                            courtChip(court)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 球馆标签组件
    /// 显示单个已选球馆的标签，点击可取消选择
    /// - Parameter court: 球馆信息
    /// - Returns: 球馆标签视图
    private func courtChip(_ court: BadmintonCourt) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 12))
            
            Text(court.name)
                .font(AppTheme.Typography.small)
                .lineLimit(1)
            
            // 移除按钮
            Button {
                appState.toggleCourtSelection(court.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .accessibilityLabel("取消选择\(court.name)")
        }
        .foregroundColor(AppTheme.Colors.textPrimary)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(AppTheme.Colors.bgCard)
        .cornerRadius(AppTheme.Radius.md)
    }
    
    // MARK: - 出行半径设置弹窗
    /// 显示出行半径调整滑块
    /// - Requirements: 10.4
    private var radiusSettingsSheet: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("搜索范围设置")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.md) {
                Text("\(Int(locationManager.userPreferences.travelRadiusKm)) 公里")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(AppTheme.Colors.primary)
                
                Slider(
                    value: Binding(
                        get: { locationManager.userPreferences.travelRadiusKm },
                        set: { locationManager.updateTravelRadius($0) }
                    ),
                    in: UserPreferences.minimumTravelRadius...UserPreferences.maximumTravelRadius,
                    step: 1
                )
                .tint(AppTheme.Colors.primary)
                
                // 范围提示
                HStack {
                    Text("\(Int(UserPreferences.minimumTravelRadius)) 公里")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text("\(Int(UserPreferences.maximumTravelRadius)) 公里")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.lg)
            
            Button("完成") {
                showRadiusSettings = false
            }
            .font(AppTheme.Typography.body)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.primaryGradient)
            .cornerRadius(AppTheme.Radius.lg)
        }
        .padding(AppTheme.Spacing.lg)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
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
    /// 显示匹配按钮和状态提示
    /// - Requirements: 5.5, 10.3
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
                    appState.canStartMatching
                        ? AnyShapeStyle(AppTheme.Colors.secondaryGradient)
                        : AnyShapeStyle(AppTheme.Colors.bgLight)
                )
                .cornerRadius(AppTheme.Radius.lg)
                .shadow(
                    color: appState.canStartMatching ? AppTheme.Colors.secondary.opacity(0.4) : .clear,
                    radius: 10,
                    y: 4
                )
            }
            .disabled(!appState.canStartMatching)
            
            // 匹配状态提示
            Text(matchButtonPrompt)
                .font(AppTheme.Typography.caption)
                .foregroundColor(matchButtonPromptColor)
        }
    }
    
    // MARK: - 匹配按钮提示文本
    /// 根据当前选择状态返回提示文本
    /// - Requirements: 5.5, 10.3
    private var matchButtonPrompt: String {
        if appState.selectedMode == nil {
            return "请先选择对战模式"
        } else if appState.selectedCourtIds.isEmpty {
            return "请先选择球馆"
        } else {
            return "已选择\(appState.selectedMode!.rawValue)模式，\(appState.selectedCourtIds.count)个球馆"
        }
    }
    
    // MARK: - 匹配按钮提示颜色
    /// 根据是否可以开始匹配返回提示颜色
    private var matchButtonPromptColor: Color {
        appState.canStartMatching ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary
    }
    
    // MARK: - 已选球馆列表
    /// 从 locationManager 的球馆列表中筛选出已选择的球馆
    private var selectedCourts: [BadmintonCourt] {
        locationManager.nearbyCourts.filter { appState.selectedCourtIds.contains($0.id) }
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

#Preview("已选球馆") {
    HomeView()
        .environmentObject({
            let state = AppState()
            state.currentUser = User(id: "1", nickname: "球友1", phone: "138****1234", selfReportedLevel: 4, totalGames: 23, wins: 18)
            state.selectedCourtIds = ["court-001", "court-002"]
            state.selectedMode = .singles
            return state
        }())
        .environmentObject({
            let manager = LocationManager()
            manager.nearbyCourts = BadmintonCourt.mockCourts
            return manager
        }())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
