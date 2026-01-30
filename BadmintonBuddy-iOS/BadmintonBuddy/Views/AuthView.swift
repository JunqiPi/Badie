import SwiftUI

struct AuthView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoginMode = true
    
    // 登录表单
    @State private var loginPhone = ""
    @State private var loginPassword = ""
    
    // 注册表单
    @State private var regNickname = ""
    @State private var regPhone = ""
    @State private var regPassword = ""
    @State private var selectedLevel: SkillLevel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Tab 切换
                HStack(spacing: 0) {
                    tabButton("登录", isSelected: isLoginMode) {
                        withAnimation { isLoginMode = true }
                    }
                    tabButton("注册", isSelected: !isLoginMode) {
                        withAnimation { isLoginMode = false }
                    }
                }
                .background(AppTheme.Colors.bgCard)
                .cornerRadius(AppTheme.Radius.md)
                .padding(.top, AppTheme.Spacing.xxl)
                
                // 表单内容
                if isLoginMode {
                    loginForm
                } else {
                    registerForm
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
    }
    
    // MARK: - Tab 按钮
    private func tabButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.body)
                .foregroundColor(isSelected ? .white : AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? AppTheme.Colors.primary : Color.clear)
                .cornerRadius(AppTheme.Radius.sm)
        }
        .padding(4)
    }
    
    // MARK: - 登录表单
    private var loginForm: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            AppTextField(
                label: "手机号",
                placeholder: "请输入手机号",
                text: $loginPhone,
                keyboardType: .phonePad
            )
            
            AppTextField(
                label: "密码",
                placeholder: "请输入密码",
                text: $loginPassword,
                isSecure: true
            )
            
            PrimaryButton("登录") {
                // 模拟登录
                appState.login(
                    nickname: "球友\(loginPhone.suffix(4))",
                    phone: loginPhone,
                    level: .intermediate
                )
            }
            .padding(.top, AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 注册表单
    private var registerForm: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            AppTextField(
                label: "昵称",
                placeholder: "请输入昵称",
                text: $regNickname
            )
            
            AppTextField(
                label: "手机号",
                placeholder: "请输入手机号",
                text: $regPhone,
                keyboardType: .phonePad
            )
            
            AppTextField(
                label: "密码",
                placeholder: "请输入密码",
                text: $regPassword,
                isSecure: true
            )
            
            // 水平选择
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("羽毛球水平")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.md) {
                    ForEach(SkillLevel.allCases) { level in
                        levelButton(level)
                    }
                }
            }
            
            PrimaryButton("注册", isDisabled: selectedLevel == nil) {
                guard let level = selectedLevel else { return }
                appState.login(
                    nickname: regNickname,
                    phone: regPhone,
                    level: level
                )
            }
            .padding(.top, AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 水平选择按钮
    private func levelButton(_ level: SkillLevel) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedLevel = level
            }
        } label: {
            Text(level.displayText)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(AppTheme.Colors.bgCard)
                .cornerRadius(AppTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .stroke(
                            selectedLevel == level ? AppTheme.Colors.primary : AppTheme.Colors.bgLight,
                            lineWidth: 2
                        )
                )
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
