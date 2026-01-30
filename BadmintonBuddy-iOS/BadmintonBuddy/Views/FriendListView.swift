//
//  FriendListView.swift
//  BadmintonBuddy
//
//  好友列表视图 - 显示用户的好友列表，支持搜索和选择模式
//  Requirements: 3.5 - 房主可以从好友列表邀请好友到房间
//

import SwiftUI

// MARK: - FriendListView (好友列表视图)

/// 好友列表视图
/// - 显示用户的所有好友，包含头像、昵称、技能等级
/// - 支持按昵称搜索/过滤好友
/// - 支持选择模式，用于房间邀请功能
struct FriendListView: View {
    
    // MARK: - Environment
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var friendManager: FriendManager
    
    // MARK: - Properties
    
    /// 是否为选择模式（用于房间邀请）
    var isSelectionMode: Bool = false
    
    /// 已选中的好友ID集合（选择模式下使用）
    @Binding var selectedFriendIds: Set<String>
    
    /// 好友选择回调（非选择模式下使用）
    var onFriendSelected: ((User) -> Void)?
    
    /// 最大可选择数量（0表示无限制）
    var maxSelectionCount: Int = 0
    
    // MARK: - State
    
    /// 搜索关键词
    @State private var searchText: String = ""
    
    /// 是否显示搜索栏
    @State private var isSearching: Bool = false
    
    // MARK: - Computed Properties
    
    /// 过滤后的好友列表
    private var filteredFriends: [User] {
        friendManager.searchFriends(query: searchText)
    }
    
    /// 是否可以继续选择（未达到最大选择数量）
    private var canSelectMore: Bool {
        maxSelectionCount == 0 || selectedFriendIds.count < maxSelectionCount
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            navigationBar
            
            // 搜索栏
            searchBar
            
            // 好友列表
            friendList
        }
        .background(AppTheme.Colors.bgDark)
        .onAppear {
            friendManager.loadFriends()
        }
    }
    
    // MARK: - Navigation Bar
    
    /// 导航栏视图
    private var navigationBar: some View {
        HStack {
            // 返回按钮
            Button {
                appState.currentScreen = .home
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.primary)
            }
            .accessibilityLabel("返回")
            .accessibilityHint("返回上一页")
            
            Spacer()
            
            // 标题
            Text(isSelectionMode ? "选择好友" : "好友列表")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Spacer()
            
            // 搜索按钮
            Button {
                withAnimation(.easeInOut(duration: AppTheme.Animation.fast)) {
                    isSearching.toggle()
                    if !isSearching {
                        searchText = ""
                    }
                }
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.primary)
            }
            .accessibilityLabel(isSearching ? "关闭搜索" : "搜索好友")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.bgCard)
    }
    
    // MARK: - Search Bar
    
    /// 搜索栏视图
    @ViewBuilder
    private var searchBar: some View {
        if isSearching {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                TextField("搜索好友昵称", text: $searchText)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.bgLight)
            .cornerRadius(AppTheme.Radius.md)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    // MARK: - Friend List
    
    /// 好友列表视图
    private var friendList: some View {
        Group {
            if friendManager.isLoading {
                // 加载状态
                loadingView
            } else if filteredFriends.isEmpty {
                // 空状态
                emptyStateView
            } else {
                // 好友列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFriends) { friend in
                            FriendRowView(
                                friend: friend,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedFriendIds.contains(friend.id),
                                canSelect: canSelectMore || selectedFriendIds.contains(friend.id)
                            ) {
                                handleFriendTap(friend)
                            }
                            
                            // 分隔线
                            if friend.id != filteredFriends.last?.id {
                                Divider()
                                    .background(AppTheme.Colors.bgLight)
                                    .padding(.leading, 80) // 对齐头像右侧
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    /// 加载状态视图
    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.primary))
                .scaleEffect(1.2)
            
            Text("加载中...")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: searchText.isEmpty ? "person.2.slash" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
            
            Text(searchText.isEmpty ? "暂无好友" : "未找到匹配的好友")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text(searchText.isEmpty ? "快去添加一些球友吧！" : "试试其他关键词")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xl)
    }
    
    // MARK: - Actions
    
    /// 处理好友点击事件
    /// - Parameter friend: 被点击的好友
    private func handleFriendTap(_ friend: User) {
        if isSelectionMode {
            // 选择模式：切换选中状态
            if selectedFriendIds.contains(friend.id) {
                selectedFriendIds.remove(friend.id)
            } else if canSelectMore {
                selectedFriendIds.insert(friend.id)
            }
        } else {
            // 非选择模式：触发回调
            onFriendSelected?(friend)
        }
    }
}

// MARK: - FriendRowView (好友行视图)

/// 好友列表行视图
/// - 显示单个好友的信息：头像、昵称、技能等级
/// - 支持选择状态显示
private struct FriendRowView: View {
    
    // MARK: - Properties
    
    /// 好友数据
    let friend: User
    
    /// 是否为选择模式
    let isSelectionMode: Bool
    
    /// 是否已选中
    let isSelected: Bool
    
    /// 是否可以选择（未达到最大选择数量）
    let canSelect: Bool
    
    /// 点击回调
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // 头像
                avatarView
                
                // 用户信息
                userInfoView
                
                Spacer()
                
                // 选择指示器或箭头
                trailingView
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(isSelected ? AppTheme.Colors.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isSelectionMode && !canSelect ? 0.5 : 1.0)
        .disabled(isSelectionMode && !canSelect)
        .accessibilityLabel("\(friend.nickname)，\(User.skillLevelName(for: friend.displayLevel))级别")
        .accessibilityHint(isSelectionMode ? (isSelected ? "已选中，点击取消选择" : "点击选择") : "点击查看详情")
    }
    
    // MARK: - Avatar View
    
    /// 头像视图
    private var avatarView: some View {
        ZStack {
            AvatarView(size: 50)
            
            // 新玩家徽章
            if friend.reputation.isNewPlayer {
                Text("新")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppTheme.Colors.accent)
                    .cornerRadius(4)
                    .offset(x: 18, y: -18)
            }
        }
    }
    
    // MARK: - User Info View
    
    /// 用户信息视图
    private var userInfoView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            // 昵称
            Text(friend.nickname)
                .font(AppTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .lineLimit(1)
            
            // 技能等级
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(User.skillLevelDisplayText(for: friend.displayLevel))
                    .font(AppTheme.Typography.small)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                // 验证徽章
                if friend.verificationStatus != .unverified {
                    verificationBadge
                }
            }
        }
    }
    
    // MARK: - Verification Badge
    
    /// 验证徽章视图
    private var verificationBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
            
            Text(friend.verificationStatus == .nationalChampion ? "国冠" : "区冠")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(AppTheme.Colors.warning)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(AppTheme.Colors.warning.opacity(0.2))
        .cornerRadius(4)
    }
    
    // MARK: - Trailing View
    
    /// 尾部视图（选择指示器或箭头）
    @ViewBuilder
    private var trailingView: some View {
        if isSelectionMode {
            // 选择模式：显示复选框
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundColor(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
                .animation(.easeInOut(duration: AppTheme.Animation.fast), value: isSelected)
        } else {
            // 非选择模式：显示箭头
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Convenience Initializers

extension FriendListView {
    
    /// 非选择模式初始化器
    /// - Parameters:
    ///   - onFriendSelected: 好友选择回调
    init(onFriendSelected: @escaping (User) -> Void) {
        self.isSelectionMode = false
        self._selectedFriendIds = .constant([])
        self.onFriendSelected = onFriendSelected
        self.maxSelectionCount = 0
    }
    
    /// 选择模式初始化器
    /// - Parameters:
    ///   - selectedFriendIds: 已选中的好友ID集合绑定
    ///   - maxSelectionCount: 最大可选择数量（0表示无限制）
    init(selectedFriendIds: Binding<Set<String>>, maxSelectionCount: Int = 0) {
        self.isSelectionMode = true
        self._selectedFriendIds = selectedFriendIds
        self.onFriendSelected = nil
        self.maxSelectionCount = maxSelectionCount
    }
}

// MARK: - Preview

#Preview("好友列表 - 普通模式") {
    FriendListView { friend in
        print("Selected: \(friend.nickname)")
    }
    .environmentObject(AppState())
    .environmentObject({
        let manager = FriendManager()
        manager.friends = User.mockOpponents
        return manager
    }())
    .preferredColorScheme(.dark)
}

#Preview("好友列表 - 选择模式") {
    struct PreviewWrapper: View {
        @State private var selectedIds: Set<String> = ["1"]
        
        var body: some View {
            FriendListView(selectedFriendIds: $selectedIds, maxSelectionCount: 3)
                .environmentObject(AppState())
                .environmentObject({
                    let manager = FriendManager()
                    manager.friends = User.mockOpponents
                    return manager
                }())
        }
    }
    
    return PreviewWrapper()
        .preferredColorScheme(.dark)
}

#Preview("好友列表 - 空状态") {
    FriendListView { _ in }
        .environmentObject(AppState())
        .environmentObject(FriendManager())
        .preferredColorScheme(.dark)
}
