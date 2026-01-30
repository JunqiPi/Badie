//
//  CourtDetailSheet.swift
//  BadmintonBuddy
//
//  球馆详情弹窗视图
//  显示球馆的详细信息，包括名称、地址、设施、距离等
//  - Requirements: 4.2
//

import SwiftUI

/// 球馆详情弹窗
/// 显示球馆的详细信息，包括名称、地址、设施、距离等
/// - Requirements: 4.2
struct CourtDetailSheet: View {
    /// 要显示的球馆信息
    let court: BadmintonCourt
    
    /// 当前球馆是否已被选中
    let isSelected: Bool
    
    /// 用户当前位置（用于计算距离）
    let userLocation: Coordinate?
    
    /// 选择/取消选择球馆的回调
    let onToggleSelection: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 头部标题栏
            headerView
            
            // 球馆信息内容区域
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    // 基本信息卡片
                    basicInfoCard
                    
                    // 设施信息卡片
                    amenitiesCard
                    
                    // 营业时间卡片
                    operatingHoursCard
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            
            // 底部选择按钮
            selectionButton
        }
        .background(AppTheme.Colors.bgDark)
    }
    
    // MARK: - 头部视图
    
    /// 头部标题栏，包含标题和关闭按钮
    private var headerView: some View {
        HStack {
            Text("球馆详情")
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
    }
    
    // MARK: - 基本信息卡片
    
    /// 显示球馆名称、图标、地址和距离
    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // 球馆名称和图标
            HStack(spacing: AppTheme.Spacing.md) {
                // 球馆图标
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.primaryGradient)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                // 球馆名称和场地数量
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(court.name)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                    
                    Text(court.formattedCourtCount)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.primary)
                }
                
                Spacer()
            }
            
            // 地址信息
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(AppTheme.Colors.secondary)
                
                Text(court.address)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            
            // 距离信息（仅当有用户位置时显示）
            if let userLocation = userLocation {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "location.fill")
                        .foregroundColor(AppTheme.Colors.primary)
                    
                    Text("距您 \(court.formattedDistance(from: userLocation))")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.bgCard)
        .cornerRadius(AppTheme.Radius.lg)
    }
    
    // MARK: - 设施信息卡片
    
    /// 显示球馆提供的设施服务
    private var amenitiesCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("设施服务")
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            if court.amenities.isEmpty {
                // 无设施信息时的提示
                Text("暂无设施信息")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            } else {
                // 设施网格布局
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: AppTheme.Spacing.md) {
                    ForEach(court.amenities, id: \.self) { amenity in
                        amenityItem(amenity)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.bgCard)
        .cornerRadius(AppTheme.Radius.lg)
    }
    
    /// 单个设施项视图
    /// - Parameter amenity: 设施类型
    /// - Returns: 设施图标和名称的视图
    private func amenityItem(_ amenity: CourtAmenity) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: amenity.icon)
                .font(.system(size: 20))
                .foregroundColor(AppTheme.Colors.primary)
            
            Text(amenity.rawValue)
                .font(AppTheme.Typography.small)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 营业时间卡片
    
    /// 显示球馆的营业时间信息
    private var operatingHoursCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("营业时间")
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            HStack(spacing: AppTheme.Spacing.lg) {
                // 营业时间
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("时间")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Text(court.operatingHours.formattedTimeRange)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
                
                Spacer()
                
                // 营业日
                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                    Text("营业日")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Text(court.operatingHours.formattedDaysOpen)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.bgCard)
        .cornerRadius(AppTheme.Radius.lg)
    }
    
    // MARK: - 选择按钮
    
    /// 底部选择/取消选择按钮
    private var selectionButton: some View {
        Button {
            onToggleSelection()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(isSelected ? "取消选择" : "选择此球馆")
            }
            .font(AppTheme.Typography.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(isSelected ? AppTheme.Colors.secondaryGradient : AppTheme.Colors.primaryGradient)
            .cornerRadius(AppTheme.Radius.lg)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.lg)
        .accessibilityLabel(isSelected ? "取消选择此球馆" : "选择此球馆")
        .accessibilityHint(isSelected ? "点击取消选择\(court.name)" : "点击选择\(court.name)")
    }
}

// MARK: - 预览

#Preview("未选中状态") {
    CourtDetailSheet(
        court: BadmintonCourt.mock,
        isSelected: false,
        userLocation: Coordinate(latitude: 39.9042, longitude: 116.4074),
        onToggleSelection: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("已选中状态") {
    CourtDetailSheet(
        court: BadmintonCourt.mock,
        isSelected: true,
        userLocation: Coordinate(latitude: 39.9042, longitude: 116.4074),
        onToggleSelection: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("无用户位置") {
    CourtDetailSheet(
        court: BadmintonCourt.mock,
        isSelected: false,
        userLocation: nil,
        onToggleSelection: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("无设施球馆") {
    CourtDetailSheet(
        court: BadmintonCourt(
            id: "test-court",
            name: "测试球馆",
            location: Coordinate(latitude: 39.9, longitude: 116.4),
            address: "北京市测试区测试路1号",
            amenities: [],
            operatingHours: .standard,
            courtCount: 4
        ),
        isSelected: false,
        userLocation: Coordinate(latitude: 39.9042, longitude: 116.4074),
        onToggleSelection: {}
    )
    .preferredColorScheme(.dark)
}
