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
    @State private var selectedLevel: Int? = nil  // 使用新的9级系统 (1-7可选)
    
    /// 可自选的技能等级范围 (1-7，8-9需要验证)
    private let selectableLevels = Array(1...User.maxSelfSelectableLevel)
    
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
                // 模拟登录 - 使用新的9级系统，默认等级4（业余）
                appState.login(
                    nickname: "球友\(loginPhone.suffix(4))",
                    phone: loginPhone,
                    selfReportedLevel: 4
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
            
            // 水平选择 - 使用新的9级系统
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("羽毛球水平")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                Text("选择1-7级，8-9级需要赛事认证")
                    .font(AppTheme.Typography.small)
                    .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
                
                // 使用 LazyVGrid 显示等级选择
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: AppTheme.Spacing.sm) {
                    ForEach(selectableLevels, id: \.self) { level in
                        levelButton(level)
                    }
                }
            }
            
            PrimaryButton("注册", isDisabled: selectedLevel == nil) {
                guard let level = selectedLevel else { return }
                appState.login(
                    nickname: regNickname,
                    phone: regPhone,
                    selfReportedLevel: level
                )
            }
            .padding(.top, AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 水平选择按钮 (新的9级系统)
    private func levelButton(_ level: Int) -> some View {
        let isSelected = selectedLevel == level
        
        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedLevel = level
            }
        } label: {
            VStack(spacing: 4) {
                Text(User.skillLevelIcon(for: level))
                    .font(.system(size: 20))
                Text(User.skillLevelName(for: level))
                    .font(AppTheme.Typography.small)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                Text("Lv.\(level)")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppTheme.Colors.primary.opacity(0.15) : AppTheme.Colors.bgCard)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(
                        isSelected ? AppTheme.Colors.primary : AppTheme.Colors.bgLight,
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
