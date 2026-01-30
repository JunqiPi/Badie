import SwiftUI
import MapKit

struct MatchSuccessView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locationManager: LocationManager
    
    // 动画状态
    @State private var leftCardOffset: CGFloat = -300
    @State private var rightCardOffset: CGFloat = 300
    @State private var leftCardRotation: Double = -15
    @State private var rightCardRotation: Double = 15
    @State private var showVS = false
    @State private var vsScale: CGFloat = 0
    @State private var cardGlow = false
    @State private var showResult = false
    @State private var particlesVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // 卡片碰撞区域
            ZStack {
                // 左侧卡片 (我)
                collisionCard(
                    name: appState.currentUser?.nickname ?? "我",
                    skillLevel: appState.currentUser?.displayLevel ?? 4,
                    borderColor: AppTheme.Colors.primary
                )
                .offset(x: leftCardOffset)
                .rotationEffect(.degrees(leftCardRotation))
                .shadow(color: cardGlow ? AppTheme.Colors.primary.opacity(0.6) : .clear, radius: 20)
                
                // VS 爆炸效果
                if showVS {
                    ZStack {
                        // 粒子效果
                        ForEach(0..<6, id: \.self) { index in
                            particleView(index: index)
                        }
                        
                        // VS 文字
                        Text("VS")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(AppTheme.Colors.warning)
                            .shadow(color: AppTheme.Colors.warning, radius: 10)
                            .scaleEffect(vsScale)
                    }
                }
                
                // 右侧卡片 (对手)
                collisionCard(
                    name: appState.matchedOpponent?.nickname ?? "对手",
                    skillLevel: appState.matchedOpponent?.displayLevel ?? 6,
                    borderColor: AppTheme.Colors.secondary
                )
                .offset(x: rightCardOffset)
                .rotationEffect(.degrees(rightCardRotation))
                .shadow(color: cardGlow ? AppTheme.Colors.secondary.opacity(0.6) : .clear, radius: 20)
            }
            .frame(height: 280)
            
            // 匹配结果信息
            if showResult {
                resultView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer()
        }
        .onAppear {
            startCollisionAnimation()
        }
    }
    
    // MARK: - 碰撞卡片
    private func collisionCard(name: String, skillLevel: Int, borderColor: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AvatarView(size: 56)
            
            Text(name)
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text(User.skillLevelDisplayText(for: skillLevel))
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 140)
        .background(AppTheme.Colors.bgCard)
        .cornerRadius(AppTheme.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .stroke(borderColor, lineWidth: 3)
        )
    }
    
    // MARK: - 粒子效果
    private func particleView(index: Int) -> some View {
        let angles: [Double] = [0, 60, 120, 180, 240, 300]
        let angle = angles[index] * .pi / 180
        let distance: CGFloat = particlesVisible ? 80 : 0
        
        return Circle()
            .fill(AppTheme.Colors.warning)
            .frame(width: 10, height: 10)
            .offset(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            .opacity(particlesVisible ? 0 : 1)
            .animation(
                .easeOut(duration: 0.8).delay(Double(index) * 0.05),
                value: particlesVisible
            )
    }
    
    // MARK: - 结果视图
    private var resultView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 标题
            HStack {
                Text("🎉")
                Text("匹配成功！")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.Colors.primary, AppTheme.Colors.warning],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // 详情卡片
            VStack(spacing: AppTheme.Spacing.md) {
                // 球馆信息（使用 matchedCourt）
                if let court = appState.matchedCourt {
                    detailRow(icon: "🏸", text: court.name)
                    detailRow(icon: "📍", text: court.address)
                    detailRow(icon: "📏", text: "距离你 \(court.formattedDistance(from: userCoordinate))")
                }
                detailRow(icon: "⏰", text: "建议时间：今天 19:00")
            }
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.bgCard)
            .cornerRadius(AppTheme.Radius.lg)
            .padding(.horizontal, AppTheme.Spacing.lg)
            
            // 操作按钮
            VStack(spacing: AppTheme.Spacing.md) {
                PrimaryButton("确认约球") {
                    appState.confirmMatch()
                }
                
                // 导航按钮（打开地图应用）
                if let court = appState.matchedCourt {
                    Button {
                        openMapsNavigation(to: court)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "map.fill")
                            Text("导航到球馆")
                        }
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppTheme.Colors.bgCard)
                        .cornerRadius(AppTheme.Radius.lg)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                                .stroke(AppTheme.Colors.primary, lineWidth: 1)
                        )
                    }
                    .accessibilityLabel("导航到\(court.name)")
                }
                
                SecondaryButton(title: "重新匹配") {
                    appState.rematch()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
    }
    
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(icon)
                .font(.system(size: 20))
            Text(text)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
            Spacer()
        }
    }
    
    // MARK: - 用户坐标
    /// 获取用户当前坐标，用于计算到球馆的距离
    /// - Requirements: 7.3
    private var userCoordinate: Coordinate {
        if let location = locationManager.currentLocation {
            return Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
        // 默认北京坐标（天安门）
        return Coordinate(latitude: 39.9042, longitude: 116.4074)
    }
    
    // MARK: - 导航到球馆
    /// 打开地图应用导航到指定球馆
    /// - Parameter court: 目标球馆
    /// - Requirements: 7.4
    private func openMapsNavigation(to court: BadmintonCourt) {
        let coordinate = CLLocationCoordinate2D(
            latitude: court.location.latitude,
            longitude: court.location.longitude
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = court.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    // MARK: - 碰撞动画
    private func startCollisionAnimation() {
        // 阶段1: 卡片飞入 (0-0.7s)
        withAnimation(.easeOut(duration: AppTheme.Animation.collision)) {
            leftCardOffset = -70
            rightCardOffset = 70
            leftCardRotation = -5
            rightCardRotation = 5
        }
        
        // 阶段2: 碰撞效果 (0.7s)
        DispatchQueue.main.asyncAfter(deadline: .now() + AppTheme.Animation.collision) {
            // 震动反馈
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                cardGlow = true
                showVS = true
                vsScale = 1
            }
            
            // 粒子爆炸
            withAnimation {
                particlesVisible = true
            }
        }
        
        // 阶段3: 显示结果 (1.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showResult = true
            }
        }
    }
}

#Preview {
    MatchSuccessView()
        .environmentObject({
            let state = AppState()
            state.currentUser = User(id: "1", nickname: "球友1", phone: "", selfReportedLevel: 4, totalGames: 0, wins: 0)
            state.matchedOpponent = User.mockOpponents[0]
            state.matchedCourt = BadmintonCourt.mock
            return state
        }())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
