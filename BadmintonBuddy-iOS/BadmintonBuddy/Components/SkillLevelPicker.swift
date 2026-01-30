import SwiftUI

// MARK: - 技能等级选择器
/// 可复用的9级技能等级选择组件
/// - 显示所有9个等级，带图标和描述
/// - 1-7级可自选，8-9级需要赛事认证（显示为禁用状态）
/// - Requirements: 2.1, 2.2
struct SkillLevelPicker: View {
    /// 当前选中的等级
    @Binding var selectedLevel: Int
    
    /// 最大可自选等级（默认7，8-9级需要验证）
    var maxSelectableLevel: Int = 7
    
    /// 所有技能等级范围
    private let allLevels = Array(1...9)
    
    /// 网格列配置 - 3列布局
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // 标题
            Text("羽毛球水平")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            // 提示信息
            Text("选择1-\(maxSelectableLevel)级，\(maxSelectableLevel + 1)-9级需要赛事认证")
                .font(AppTheme.Typography.small)
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
            
            // 等级选择网格
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                ForEach(allLevels, id: \.self) { level in
                    skillLevelButton(for: level)
                }
            }
        }
    }
    
    // MARK: - 单个等级按钮
    @ViewBuilder
    private func skillLevelButton(for level: Int) -> some View {
        let isSelected = selectedLevel == level
        let isDisabled = level > maxSelectableLevel
        
        Button {
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.3)) {
                selectedLevel = level
            }
        } label: {
            VStack(spacing: 4) {
                Text(User.skillLevelIcon(for: level))
                    .font(.system(size: 20))
                    .opacity(isDisabled ? 0.5 : 1.0)
                
                Text(User.skillLevelName(for: level))
                    .font(AppTheme.Typography.small)
                    .foregroundColor(isDisabled ? AppTheme.Colors.textSecondary.opacity(0.5) : AppTheme.Colors.textPrimary)
                
                Text("Lv.\(level)")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .opacity(isDisabled ? 0.5 : 1.0)
                
                if isDisabled {
                    Text("需要赛事认证")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.Colors.warning.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(buttonBackground(isSelected: isSelected, isDisabled: isDisabled))
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(
                        buttonBorderColor(isSelected: isSelected, isDisabled: isDisabled),
                        lineWidth: 2
                    )
            )
        }
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(for: level, isDisabled: isDisabled))
    }
    
    private func buttonBackground(isSelected: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return AppTheme.Colors.bgCard.opacity(0.5)
        } else if isSelected {
            return AppTheme.Colors.primary.opacity(0.15)
        } else {
            return AppTheme.Colors.bgCard
        }
    }
    
    private func buttonBorderColor(isSelected: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return AppTheme.Colors.bgLight.opacity(0.3)
        } else if isSelected {
            return AppTheme.Colors.primary
        } else {
            return AppTheme.Colors.bgLight
        }
    }
    
    private func accessibilityLabel(for level: Int, isDisabled: Bool) -> String {
        let levelName = User.skillLevelName(for: level)
        if isDisabled {
            return "等级\(level) \(levelName)，需要赛事认证"
        } else {
            return "等级\(level) \(levelName)"
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedLevel = 4
        var body: some View {
            SkillLevelPicker(selectedLevel: $selectedLevel)
                .padding()
                .background(AppTheme.Colors.bgDark)
        }
    }
    return PreviewWrapper().preferredColorScheme(.dark)
}
