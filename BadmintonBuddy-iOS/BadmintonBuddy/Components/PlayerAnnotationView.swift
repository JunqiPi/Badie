import SwiftUI

// MARK: - PlayerAnnotationView (玩家地图标注视图)
/// 在地图上显示玩家标注，包含头像、技能等级徽章和选中状态
/// 用于 RealMapView 中显示附近玩家的位置标记
/// Requirements: 1.5
struct PlayerAnnotationView: View {
    
    // MARK: - Properties
    
    /// 玩家信息
    let player: User
    
    /// 是否被选中
    let isSelected: Bool
    
    // MARK: - Constants
    
    /// 头像大小
    private let avatarSize: CGFloat = 40
    
    /// 徽章大小
    private let badgeSize: CGFloat = 20
    
    /// 选中状态边框宽度
    private let selectedBorderWidth: CGFloat = 3
    
    /// 未选中状态边框宽度
    private let normalBorderWidth: CGFloat = 2
    
    // MARK: - Initialization
    
    /// 初始化玩家标注视图
    /// - Parameters:
    ///   - player: 玩家信息
    ///   - isSelected: 是否被选中，默认为 false
    init(player: User, isSelected: Bool = false) {
        self.player = player
        self.isSelected = isSelected
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 玩家头像
            avatarView
            
            // 技能等级徽章
            skillBadge
        }
        // 选中状态动画
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        // 无障碍支持
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("点击查看玩家详情")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    // MARK: - Avatar View
    
    /// 玩家头像视图
    private var avatarView: some View {
        ZStack {
            // 选中状态外发光效果
            if isSelected {
                Circle()
                    .fill(AppTheme.Colors.primary.opacity(0.3))
                    .frame(width: avatarSize + 16, height: avatarSize + 16)
                    .blur(radius: 4)
            }
            
            // 头像背景圆
            Circle()
                .fill(AppTheme.Colors.avatarGradient)
                .frame(width: avatarSize, height: avatarSize)
            
            // 头像内容（使用首字母或默认表情）
            Text(avatarContent)
                .font(.system(size: avatarSize * 0.45))
            
            // 边框（选中状态高亮）
            Circle()
                .stroke(
                    isSelected ? AppTheme.Colors.primary : AppTheme.Colors.bgLight,
                    lineWidth: isSelected ? selectedBorderWidth : normalBorderWidth
                )
                .frame(width: avatarSize, height: avatarSize)
        }
    }
    
    // MARK: - Skill Badge
    
    /// 技能等级徽章
    private var skillBadge: some View {
        ZStack {
            // 徽章背景
            Circle()
                .fill(skillLevelColor)
                .frame(width: badgeSize, height: badgeSize)
            
            // 等级数字
            Text("\(player.displayLevel)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        // 徽章边框
        .overlay(
            Circle()
                .stroke(AppTheme.Colors.bgDark, lineWidth: 1.5)
        )
        // 位置偏移到右下角
        .offset(x: 4, y: 4)
    }
    
    // MARK: - Computed Properties
    
    /// 头像显示内容（首字母或默认表情）
    private var avatarContent: String {
        // 获取昵称首字符
        if let firstChar = player.nickname.first {
            return String(firstChar)
        }
        // 默认使用羽毛球表情
        return "🏸"
    }
    
    /// 根据技能等级返回对应颜色
    private var skillLevelColor: Color {
        switch player.displayLevel {
        case 1...2:
            return AppTheme.Colors.success      // 入门级 - 绿色
        case 3...4:
            return Color(hex: "3498DB")         // 业余级 - 蓝色
        case 5...6:
            return AppTheme.Colors.primary      // 中高级 - 青绿
        case 7:
            return AppTheme.Colors.secondary    // 专业级 - 紫色
        case 8...9:
            return AppTheme.Colors.accent       // 冠军级 - 粉色
        default:
            return AppTheme.Colors.textSecondary
        }
    }
    
    /// 无障碍标签文本
    private var accessibilityLabelText: String {
        var label = "\(player.nickname)，技能等级\(player.displayLevel)级"
        
        // 添加新玩家标识
        if player.reputation.isNewPlayer {
            label += "，新玩家"
        }
        
        // 添加选中状态
        if isSelected {
            label += "，已选中"
        }
        
        return label
    }
}

// MARK: - Preview

#Preview("默认状态") {
    VStack(spacing: 40) {
        // 不同等级的玩家
        HStack(spacing: 30) {
            PlayerAnnotationView(
                player: User(
                    id: "1",
                    nickname: "小明",
                    phone: "138****1234",
                    selfReportedLevel: 2
                ),
                isSelected: false
            )
            
            PlayerAnnotationView(
                player: User(
                    id: "2",
                    nickname: "阿杰",
                    phone: "139****5678",
                    selfReportedLevel: 5
                ),
                isSelected: false
            )
            
            PlayerAnnotationView(
                player: User(
                    id: "3",
                    nickname: "大伟",
                    phone: "137****9012",
                    selfReportedLevel: 7
                ),
                isSelected: false
            )
        }
        
        Text("不同等级玩家")
            .font(AppTheme.Typography.caption)
            .foregroundColor(AppTheme.Colors.textSecondary)
    }
    .padding(40)
    .background(AppTheme.Colors.bgDark)
    .preferredColorScheme(.dark)
}

#Preview("选中状态") {
    VStack(spacing: 40) {
        HStack(spacing: 30) {
            // 未选中
            PlayerAnnotationView(
                player: User(
                    id: "1",
                    nickname: "球友",
                    phone: "138****1234",
                    selfReportedLevel: 4
                ),
                isSelected: false
            )
            
            // 选中
            PlayerAnnotationView(
                player: User(
                    id: "2",
                    nickname: "球友",
                    phone: "139****5678",
                    selfReportedLevel: 4
                ),
                isSelected: true
            )
        }
        
        Text("左：未选中 / 右：选中")
            .font(AppTheme.Typography.caption)
            .foregroundColor(AppTheme.Colors.textSecondary)
    }
    .padding(40)
    .background(AppTheme.Colors.bgDark)
    .preferredColorScheme(.dark)
}

#Preview("所有等级") {
    VStack(spacing: 20) {
        // 第一行：1-5级
        HStack(spacing: 20) {
            ForEach(1...5, id: \.self) { level in
                VStack(spacing: 8) {
                    PlayerAnnotationView(
                        player: User(
                            id: "\(level)",
                            nickname: "L\(level)",
                            phone: "138****\(level)234",
                            selfReportedLevel: level
                        ),
                        isSelected: false
                    )
                    
                    Text("\(level)级")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        
        // 第二行：6-9级
        HStack(spacing: 20) {
            ForEach(6...9, id: \.self) { level in
                VStack(spacing: 8) {
                    PlayerAnnotationView(
                        player: User(
                            id: "\(level)",
                            nickname: "L\(level)",
                            phone: "138****\(level)234",
                            selfReportedLevel: level
                        ),
                        isSelected: false
                    )
                    
                    Text("\(level)级")
                        .font(AppTheme.Typography.small)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
    }
    .padding(40)
    .background(AppTheme.Colors.bgDark)
    .preferredColorScheme(.dark)
}
