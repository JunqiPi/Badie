import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    private var user: User? { appState.currentUser }
    
    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            HStack {
                Button {
                    appState.currentScreen = .home
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.primary)
                }
                
                Spacer()
                
                Text("个人资料")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    // 编辑功能
                } label: {
                    Text("编辑")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.primary)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.bgCard)
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // 头像区域
                    VStack(spacing: AppTheme.Spacing.md) {
                        AvatarView(size: 100)
                        
                        Text(user?.nickname ?? "球友")
                            .font(AppTheme.Typography.title)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                    }
                    .padding(.top, AppTheme.Spacing.xl)
                    
                    // 统计数据
                    HStack(spacing: 0) {
                        statItem(value: "\(user?.totalGames ?? 0)", label: "总场次")
                        statItem(value: "\(user?.wins ?? 0)", label: "胜场")
                        statItem(value: String(format: "%.0f%%", user?.winRate ?? 0), label: "胜率")
                    }
                    .padding(.vertical, AppTheme.Spacing.lg)
                    .background(AppTheme.Colors.bgCard)
                    .cornerRadius(AppTheme.Radius.lg)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    
                    // 详细信息
                    VStack(spacing: 0) {
                        infoRow(label: "水平等级", value: user?.level.displayText ?? "⭐ 业余")
                        Divider().background(AppTheme.Colors.bgLight)
                        infoRow(label: "常用球馆", value: "朝阳区体育中心")
                        Divider().background(AppTheme.Colors.bgLight)
                        infoRow(label: "加入时间", value: formatDate(user?.joinDate ?? Date()))
                    }
                    .background(AppTheme.Colors.bgCard)
                    .cornerRadius(AppTheme.Radius.lg)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    
                    // 退出登录
                    Button {
                        appState.logout()
                    } label: {
                        Text("退出登录")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                    .stroke(AppTheme.Colors.accent, lineWidth: 2)
                            )
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.lg)
                }
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.Colors.primary)
            Text(label)
                .font(AppTheme.Typography.small)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.Colors.textPrimary)
        }
        .padding(AppTheme.Spacing.md)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#Preview {
    ProfileView()
        .environmentObject({
            let state = AppState()
            state.currentUser = User(id: "1", nickname: "球友1", phone: "138****1234", level: .intermediate, totalGames: 23, wins: 18)
            return state
        }())
        .preferredColorScheme(.dark)
        .background(AppTheme.Colors.bgDark)
}
