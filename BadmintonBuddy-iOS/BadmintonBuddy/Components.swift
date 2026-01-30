import SwiftUI

// MARK: - 主按钮
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var isDisabled: Bool = false
    
    init(_ title: String, icon: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let icon = icon {
                    Text(icon)
                        .font(.system(size: 20))
                }
                Text(title)
                    .font(AppTheme.Typography.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                isDisabled
                    ? AnyShapeStyle(AppTheme.Colors.bgLight)
                    : AnyShapeStyle(AppTheme.Colors.primaryGradient)
            )
            .cornerRadius(AppTheme.Radius.full)
            .shadow(color: isDisabled ? .clear : AppTheme.Colors.primary.opacity(0.4), radius: 10, y: 4)
        }
        .disabled(isDisabled)
        .scaleEffect(isDisabled ? 1 : 1)
        .animation(.easeInOut(duration: AppTheme.Animation.fast), value: isDisabled)
    }
}

// MARK: - 次要按钮
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var borderColor: Color = AppTheme.Colors.textSecondary
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                        .stroke(borderColor, lineWidth: 2)
                )
        }
    }
}

// MARK: - 输入框
struct AppTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .font(AppTheme.Typography.body)
            .foregroundColor(AppTheme.Colors.textPrimary)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.bgCard)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(AppTheme.Colors.bgLight, lineWidth: 2)
            )
        }
    }
}

// MARK: - 头像组件
struct AvatarView: View {
    var size: CGFloat = 48
    var emoji: String = "👤"
    
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.avatarGradient)
                .frame(width: size, height: size)
            
            Text(emoji)
                .font(.system(size: size * 0.5))
        }
    }
}

// MARK: - 卡片容器
struct CardView<Content: View>: View {
    let content: Content
    var padding: CGFloat = AppTheme.Spacing.md
    
    init(padding: CGFloat = AppTheme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(AppTheme.Colors.bgCard)
            .cornerRadius(AppTheme.Radius.lg)
    }
}

// MARK: - 脉冲动画圆点
struct PulseDot: View {
    @State private var isAnimating = false
    var color: Color = AppTheme.Colors.success
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.2 : 1)
            .opacity(isAnimating ? 0.5 : 1)
            .animation(
                .easeInOut(duration: 1)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - 搜索脉冲环
struct SearchingRing: View {
    @State private var isAnimating = false
    var delay: Double = 0
    
    var body: some View {
        Circle()
            .stroke(AppTheme.Colors.primary, lineWidth: 3)
            .frame(width: 180, height: 180)
            .scaleEffect(isAnimating ? 1.5 : 0.5)
            .opacity(isAnimating ? 0 : 1)
            .animation(
                .easeOut(duration: 2)
                .repeatForever(autoreverses: false)
                .delay(delay),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - 玩家卡片 (用于匹配动画)
struct PlayerCard: View {
    let name: String
    let level: SkillLevel
    var borderColor: Color = AppTheme.Colors.primary
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            AvatarView(size: 48)
            
            Text(name)
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text(level.displayText)
                .font(AppTheme.Typography.small)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.bgCard)
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .stroke(borderColor, lineWidth: 3)
        )
    }
}

// MARK: - 模式选择卡片
struct ModeCard: View {
    let mode: GameMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.md) {
                Text(mode.icon)
                    .font(.system(size: 40))
                
                Text(mode.rawValue)
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(mode.description)
                    .font(AppTheme.Typography.small)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                // VS 图示
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(mode == .singles ? "👤" : "👥")
                    Text("VS")
                        .font(AppTheme.Typography.small)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.accent)
                    Text(mode == .singles ? "👤" : "👥")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.lg)
            .background(
                isSelected
                    ? LinearGradient(
                        colors: [AppTheme.Colors.primary.opacity(0.1), AppTheme.Colors.secondary.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(colors: [AppTheme.Colors.bgCard], startPoint: .top, endPoint: .bottom)
            )
            .cornerRadius(AppTheme.Radius.xl)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                    .stroke(isSelected ? AppTheme.Colors.primary : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? AppTheme.Colors.primary.opacity(0.2) : .clear, radius: 15)
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}
