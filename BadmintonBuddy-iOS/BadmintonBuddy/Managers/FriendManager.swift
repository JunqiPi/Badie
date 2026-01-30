import Foundation
import Combine

// MARK: - Friend Request Model (好友请求模型)

/// 好友请求状态
enum FriendRequestStatus: String, Codable {
    case pending    // 待处理
    case accepted   // 已接受
    case declined   // 已拒绝
}

/// 好友请求模型
/// - Note: 用于管理好友请求的发送和接收
struct FriendRequest: Identifiable, Codable {
    let id: String
    let fromUserId: String
    let fromNickname: String
    let toUserId: String
    let sentAt: Date
    var status: FriendRequestStatus
}

/// 好友关系模型
/// - Note: 表示两个用户之间的双向好友关系
struct Friendship: Identifiable, Codable {
    let id: String
    let userId1: String
    let userId2: String
    let createdAt: Date
}

// MARK: - FriendManager (好友管理器)
/// 管理好友关系和好友请求
/// Requirements: 3.1, 3.2
class FriendManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 好友列表
    @Published var friends: [User] = []
    
    /// 待处理的好友请求
    @Published var pendingRequests: [FriendRequest] = []
    
    /// 已发送的好友请求
    @Published var sentRequests: [FriendRequest] = []
    
    /// 是否正在加载
    @Published var isLoading: Bool = false
    
    /// 错误信息
    @Published var error: FriendError?
    
    // MARK: - Initialization
    
    init() {
        // 初始化时可以从本地存储加载缓存的好友列表
    }
    
    // MARK: - Public Methods
    
    /// 发送好友请求
    /// - Parameter toUser: 目标用户
    /// Requirements: 3.1 - 好友请求应在3秒内送达
    func sendFriendRequest(to toUser: User) {
        // TODO: 实现发送好友请求逻辑
        // 1. 创建 FriendRequest 对象
        // 2. 发送到服务器
        // 3. 添加到 sentRequests
    }
    
    /// 接受好友请求
    /// - Parameter request: 好友请求
    /// Requirements: 3.2 - 接受后双方立即添加到好友列表
    func acceptRequest(_ request: FriendRequest) {
        // TODO: 实现接受好友请求逻辑
        // 1. 更新请求状态为 accepted
        // 2. 将对方添加到 friends 列表
        // 3. 从 pendingRequests 移除
    }
    
    /// 拒绝好友请求
    /// - Parameter request: 好友请求
    func declineRequest(_ request: FriendRequest) {
        // TODO: 实现拒绝好友请求逻辑
        // 1. 更新请求状态为 declined
        // 2. 从 pendingRequests 移除
    }
    
    /// 移除好友
    /// - Parameter friend: 要移除的好友
    func removeFriend(_ friend: User) {
        // TODO: 实现移除好友逻辑
        // 1. 从 friends 列表移除
        // 2. 同步到服务器
    }
    
    /// 加载好友列表
    func loadFriends() {
        // TODO: 从服务器或本地存储加载好友列表
        isLoading = true
        // 模拟异步加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isLoading = false
        }
    }
    
    /// 加载待处理的好友请求
    func loadPendingRequests() {
        // TODO: 从服务器加载待处理的好友请求
    }
    
    /// 搜索好友
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的好友列表
    func searchFriends(query: String) -> [User] {
        guard !query.isEmpty else { return friends }
        return friends.filter { $0.nickname.localizedCaseInsensitiveContains(query) }
    }
    
    /// 检查是否已是好友
    /// - Parameter userId: 用户ID
    /// - Returns: 是否已是好友
    func isFriend(userId: String) -> Bool {
        friends.contains { $0.id == userId }
    }
    
    /// 检查是否有待处理的请求
    /// - Parameter userId: 用户ID
    /// - Returns: 是否有待处理的请求
    func hasPendingRequest(from userId: String) -> Bool {
        pendingRequests.contains { $0.fromUserId == userId }
    }
}

// MARK: - Friend Errors

enum FriendError: Error, Equatable {
    case requestFailed
    case alreadyFriends
    case requestAlreadySent
    case userNotFound
    case networkError(String)
    
    var localizedDescription: String {
        switch self {
        case .requestFailed:
            return "发送好友请求失败，请重试"
        case .alreadyFriends:
            return "你们已经是好友了"
        case .requestAlreadySent:
            return "已发送过好友请求"
        case .userNotFound:
            return "用户不存在"
        case .networkError(let message):
            return message
        }
    }
}
