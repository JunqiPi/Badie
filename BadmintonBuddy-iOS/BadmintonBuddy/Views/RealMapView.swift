import SwiftUI
import MapKit

// MARK: - RealMapView (真实地图视图)
/// 使用 MapKit 显示真实地图，以用户当前位置为中心
/// 处理位置权限状态和位置不可用情况
/// Requirements: 1.1, 1.2, 1.7
struct RealMapView: View {
    
    // MARK: - Environment
    
    @EnvironmentObject var locationManager: LocationManager
    
    // MARK: - State
    
    /// 地图显示区域
    @State var region: MKCoordinateRegion
    
    /// 地图相机位置（iOS 17+）
    @State private var cameraPosition: MapCameraPosition
    
    // MARK: - Properties
    
    /// 附近的玩家列表
    var nearbyPlayers: [User]
    
    /// 玩家标记点击回调
    var onPlayerTapped: ((User) -> Void)?
    
    // MARK: - Constants
    
    /// 默认地图跨度（约0.1度，覆盖本地区域约10公里）
    private static let defaultSpan = MKCoordinateSpan(
        latitudeDelta: 0.1,
        longitudeDelta: 0.1
    )
    
    /// 默认位置（北京市中心）- 当位置不可用时使用
    private static let defaultCoordinate = CLLocationCoordinate2D(
        latitude: 39.9042,
        longitude: 116.4074
    )
    
    // MARK: - Initialization
    
    /// 初始化地图视图
    /// - Parameters:
    ///   - nearbyPlayers: 附近的玩家列表
    ///   - onPlayerTapped: 玩家标记点击回调
    init(
        nearbyPlayers: [User] = [],
        onPlayerTapped: ((User) -> Void)? = nil
    ) {
        self.nearbyPlayers = nearbyPlayers
        self.onPlayerTapped = onPlayerTapped
        
        // 初始化默认区域
        let initialRegion = MKCoordinateRegion(
            center: Self.defaultCoordinate,
            span: Self.defaultSpan
        )
        _region = State(initialValue: initialRegion)
        _cameraPosition = State(initialValue: .region(initialRegion))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // 根据位置权限状态显示不同内容
            switch locationManager.authorizationStatus {
            case .notDetermined:
                // 未确定权限状态 - 显示请求权限提示
                permissionRequestView
                
            case .denied, .restricted:
                // 权限被拒绝 - 显示设置引导
                permissionDeniedView
                
            case .authorizedWhenInUse, .authorizedAlways:
                // 已授权 - 显示地图
                mapContentView
                
            @unknown default:
                // 未知状态 - 显示地图（降级处理）
                mapContentView
            }
        }
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            updateRegionForLocation(newLocation)
        }
    }
    
    // MARK: - Map Content View
    
    /// 地图内容视图（已授权状态）
    private var mapContentView: some View {
        ZStack {
            // iOS 17+ Map 视图
            Map(position: $cameraPosition) {
                // 用户当前位置标记
                if let location = locationManager.currentLocation {
                    Annotation("我的位置", coordinate: location.coordinate) {
                        userLocationMarker
                    }
                }
                
                // 附近玩家标记
                ForEach(nearbyPlayers) { player in
                    if let coordinate = player.location {
                        Annotation(player.nickname, coordinate: CLLocationCoordinate2D(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )) {
                            playerMarker(for: player)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            
            // 位置不可用指示器
            if !locationManager.isLocationAvailable {
                locationUnavailableOverlay
            }
            
            // 底部位置信息栏
            VStack {
                Spacer()
                locationInfoBar
            }
        }
    }
    
    // MARK: - User Location Marker
    
    /// 用户位置标记
    private var userLocationMarker: some View {
        ZStack {
            // 脉冲效果背景
            Circle()
                .fill(AppTheme.Colors.primary.opacity(0.3))
                .frame(width: 50, height: 50)
            
            // 内圈
            Circle()
                .fill(AppTheme.Colors.primary)
                .frame(width: 20, height: 20)
            
            // 中心点
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .accessibilityLabel("我的当前位置")
    }
    
    // MARK: - Player Marker
    
    /// 玩家标记视图
    /// - Parameter player: 玩家信息
    /// - Returns: 玩家标记视图
    private func playerMarker(for player: User) -> some View {
        Button {
            onPlayerTapped?(player)
        } label: {
            VStack(spacing: 2) {
                // 羽毛球图标
                Text("🏸")
                    .font(.system(size: 24))
                
                // 技能等级徽章
                Text("\(player.displayLevel)")
                    .font(AppTheme.Typography.small)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(skillLevelColor(for: player.displayLevel))
                    .cornerRadius(AppTheme.Radius.sm)
            }
        }
        .accessibilityLabel("\(player.nickname)，技能等级\(player.displayLevel)")
        .accessibilityHint("点击查看详情")
    }
    
    // MARK: - Permission Request View
    
    /// 请求位置权限视图
    private var permissionRequestView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 地图占位背景
            mapPlaceholderBackground
            
            // 权限请求内容
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.Colors.primary)
                
                Text("需要位置权限")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("开启位置权限后，我们可以帮您找到附近的球友")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                
                Button {
                    locationManager.requestAuthorization()
                } label: {
                    Text("开启位置权限")
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppTheme.Colors.primaryGradient)
                        .cornerRadius(AppTheme.Radius.lg)
                }
                .accessibilityLabel("开启位置权限")
                .accessibilityHint("点击请求位置访问权限")
            }
            .padding(AppTheme.Spacing.lg)
        }
    }
    
    // MARK: - Permission Denied View
    
    /// 权限被拒绝视图
    private var permissionDeniedView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 地图占位背景
            mapPlaceholderBackground
            
            // 权限被拒绝内容
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.Colors.warning)
                
                Text("位置权限已关闭")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("需要位置权限才能找到附近的球友\n请在设置中开启位置权限")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                
                Button {
                    openAppSettings()
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "gear")
                        Text("前往设置")
                    }
                    .font(AppTheme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.secondaryGradient)
                    .cornerRadius(AppTheme.Radius.lg)
                }
                .accessibilityLabel("前往设置")
                .accessibilityHint("点击打开系统设置以开启位置权限")
            }
            .padding(AppTheme.Spacing.lg)
        }
    }
    
    // MARK: - Location Unavailable Overlay
    
    /// 位置不可用覆盖层
    private var locationUnavailableOverlay: some View {
        VStack {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.Colors.warning)
                
                Text("位置暂时不可用，显示上次位置")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.bgCard.opacity(0.9))
            .cornerRadius(AppTheme.Radius.md)
            .padding(.top, AppTheme.Spacing.md)
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("位置暂时不可用，正在显示上次已知位置")
    }
    
    // MARK: - Location Info Bar
    
    /// 底部位置信息栏
    private var locationInfoBar: some View {
        HStack {
            Image(systemName: "location.fill")
                .foregroundColor(AppTheme.Colors.primary)
            
            if let location = locationManager.currentLocation {
                Text("当前位置：\(formatCoordinate(location.coordinate))")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            } else {
                Text("正在获取位置...")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // 显示最后更新时间
            if let lastUpdate = locationManager.lastLocationUpdate {
                Text(formatLastUpdate(lastUpdate))
                    .font(AppTheme.Typography.small)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [.clear, AppTheme.Colors.bgDark.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Map Placeholder Background
    
    /// 地图占位背景
    private var mapPlaceholderBackground: some View {
        LinearGradient(
            colors: [Color(hex: "1e3a5f"), Color(hex: "0d2137")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // 网格效果
            GeometryReader { geometry in
                Path { path in
                    let gridSize: CGFloat = 30
                    // 垂直线
                    for x in stride(from: 0, to: geometry.size.width, by: gridSize) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    // 水平线
                    for y in stride(from: 0, to: geometry.size.height, by: gridSize) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(AppTheme.Colors.primary.opacity(0.1), lineWidth: 1)
            }
        )
    }
    
    // MARK: - Helper Methods
    
    /// 处理视图出现
    private func handleOnAppear() {
        // 如果权限未确定，请求授权
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAuthorization()
        }
        
        // 如果已授权，开始更新位置
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
           locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        
        // 如果有当前位置，更新地图区域
        if let location = locationManager.currentLocation {
            updateRegionForLocation(location)
        }
    }
    
    /// 根据位置更新地图区域
    /// - Parameter location: 新位置
    private func updateRegionForLocation(_ location: CLLocation?) {
        guard let location = location else { return }
        
        let newRegion = MKCoordinateRegion(
            center: location.coordinate,
            span: Self.defaultSpan
        )
        
        withAnimation(.easeInOut(duration: AppTheme.Animation.normal)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
    
    /// 打开应用设置
    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    /// 根据技能等级返回对应颜色
    /// - Parameter level: 技能等级 (1-9)
    /// - Returns: 对应颜色
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
    
    /// 格式化坐标显示
    /// - Parameter coordinate: 坐标
    /// - Returns: 格式化字符串
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
    
    /// 格式化最后更新时间
    /// - Parameter date: 更新时间
    /// - Returns: 格式化字符串
    private func formatLastUpdate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview("已授权 - 有位置") {
    RealMapView(
        nearbyPlayers: [
            User(
                id: "1",
                nickname: "球友小明",
                phone: "138****1234",
                selfReportedLevel: 5,
                totalGames: 20,
                wins: 12,
                location: Coordinate(latitude: 39.91, longitude: 116.41)
            ),
            User(
                id: "2",
                nickname: "羽球达人",
                phone: "139****5678",
                selfReportedLevel: 7,
                totalGames: 50,
                wins: 35,
                location: Coordinate(latitude: 39.92, longitude: 116.42)
            )
        ]
    ) { player in
        print("点击了玩家: \(player.nickname)")
    }
    .environmentObject({
        let manager = LocationManager()
        return manager
    }())
    .frame(height: 300)
    .preferredColorScheme(.dark)
}

#Preview("权限未确定") {
    RealMapView()
        .environmentObject({
            let manager = LocationManager()
            return manager
        }())
        .frame(height: 300)
        .preferredColorScheme(.dark)
}
