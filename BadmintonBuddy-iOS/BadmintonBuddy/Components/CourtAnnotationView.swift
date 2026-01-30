//
//  CourtAnnotationView.swift
//  BadmintonBuddy
//
//  地图上的球馆标注视图，用于显示羽毛球馆位置和选中状态
//  - Requirements: 4.1, 4.3, 9.1, 9.2
//

import SwiftUI

// MARK: - CourtAnnotationView (球馆地图标注视图)
/// 在地图上显示球馆标注，包含球馆图标、名称和选中状态
/// 用于 RealMapView 中显示附近球馆的位置标记
/// - Requirements: 4.1, 4.3, 9.1, 9.2
struct CourtAnnotationView: View {
    
    // MARK: - Properties
    
    /// 球馆信息
    let court: BadmintonCourt
    
    /// 是否被选中
    let isSelected: Bool
    
    /// 点击回调
    let onTap: () -> Void
    
    // MARK: - Constants
    
    /// 图标容器大小
    private let iconContainerSize: CGFloat = 44
    
    /// 图标大小
    private let iconSize: CGFloat = 20
    
    /// 选中状态边框宽度
    private let selectedBorderWidth: CGFloat = 3
    
    /// 名称标签最大宽度
    private let maxNameWidth: CGFloat = 80
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // 球馆图标，带选中状态
                iconView
                
                // 球馆名称标签
                nameLabel
            }
        }
        .buttonStyle(.plain)
        // 无障碍支持
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    // MARK: - Icon View
    
    /// 球馆图标视图
    private var iconView: some View {
        ZStack {
            // 图标背景圆
            Circle()
                .fill(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.bgCard)
                .frame(width: iconContainerSize, height: iconContainerSize)
            
            // 球馆图标
            Image(systemName: "sportscourt.fill")
                .font(.system(size: iconSize))
                .foregroundColor(isSelected ? .white : AppTheme.Colors.primary)
        }
        // 选中状态边框高亮
        .overlay(
            Circle()
                .stroke(
                    isSelected ? AppTheme.Colors.primary : .clear,
                    lineWidth: selectedBorderWidth
                )
        )
        // 选中状态缩放效果
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
    
    // MARK: - Name Label
    
    /// 球馆名称标签
    private var nameLabel: some View {
        Text(court.name)
            .font(AppTheme.Typography.small)
            .foregroundColor(AppTheme.Colors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: maxNameWidth)
    }
    
    // MARK: - Accessibility
    
    /// 无障碍标签文本
    private var accessibilityLabelText: String {
        "\(court.name)，\(isSelected ? "已选择" : "未选择")"
    }
    
    /// 无障碍提示文本
    private var accessibilityHintText: String {
        "点击\(isSelected ? "取消选择" : "选择")此球馆"
    }
}

// MARK: - Preview

#Preview("未选中") {
    CourtAnnotationView(
        court: BadmintonCourt.mock,
        isSelected: false,
        onTap: {}
    )
    .preferredColorScheme(.dark)
    .padding()
    .background(AppTheme.Colors.bgDark)
}

#Preview("已选中") {
    CourtAnnotationView(
        court: BadmintonCourt.mock,
        isSelected: true,
        onTap: {}
    )
    .preferredColorScheme(.dark)
    .padding()
    .background(AppTheme.Colors.bgDark)
}

#Preview("多个球馆") {
    VStack(spacing: 40) {
        HStack(spacing: 30) {
            // 未选中状态
            CourtAnnotationView(
                court: BadmintonCourt.mockCourts[0],
                isSelected: false,
                onTap: {}
            )
            
            // 选中状态
            CourtAnnotationView(
                court: BadmintonCourt.mockCourts[1],
                isSelected: true,
                onTap: {}
            )
            
            // 未选中状态
            CourtAnnotationView(
                court: BadmintonCourt.mockCourts[2],
                isSelected: false,
                onTap: {}
            )
        }
        
        Text("左/右：未选中 / 中：选中")
            .font(AppTheme.Typography.caption)
            .foregroundColor(AppTheme.Colors.textSecondary)
    }
    .padding(40)
    .background(AppTheme.Colors.bgDark)
    .preferredColorScheme(.dark)
}

#Preview("所有模拟球馆") {
    VStack(spacing: 20) {
        ForEach(Array(BadmintonCourt.mockCourts.enumerated()), id: \.element.id) { index, court in
            HStack(spacing: 16) {
                CourtAnnotationView(
                    court: court,
                    isSelected: index == 0,  // 第一个选中
                    onTap: {}
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(court.name)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text("\(court.courtCount)片场地")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
        }
    }
    .padding(20)
    .background(AppTheme.Colors.bgDark)
    .preferredColorScheme(.dark)
}
