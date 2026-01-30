import Foundation
import Combine

// MARK: - Message Thread Model (消息会话模型)

/// 消息会话模型
/// - Note: 用于管理两个用户之间的私信会话
struct MessageThread: Identifiable, Codable {
    let id: String
    let participantIds: [String]
    var lastMessage: Message?
    var lastActivityAt: Date
    var unreadCount: Int
    
    /// 获取会话中另一个参与者的ID
    /// - Parameter currentUserId: 当前用户ID
    /// - Returns: 另一个参与者的ID，如果不存在则返回nil
    func otherParticipantId(currentUserId: String) -> String? {
        participantIds.first { $0 != currentUserId }
    }
}

// MARK: - Blocked User Model (屏蔽用户模型)

/// 屏蔽用户模型
/// - Note: 记录用户屏蔽关系
struct BlockedUser: Identifiable, Codable {
    let id: String
    let blockedUserId: String
    let blockedAt: Date
}

// MARK: - MessageManager (消息管理器)
/// 管理私信会话和消息
/// Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.7, 5.8, 5.9
class MessageManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 消息会话列表
    @Published var threads: [MessageThread] = []
    
    /// 未读消息总数
    @Published var unreadCount: Int = 0
    
    /// 已屏蔽的用户列表
    @Published var blockedUsers: [BlockedUser] = []
    
    /// 是否正在加载
    @Published var isLoading: Bool = false
    
    /// 错误信息（使用 MessageServiceProtocol 中定义的 MessageError）
    @Published var error: MessageError?
    
    // MARK: - Constants
    
    /// 消息最大字符数（与 Message.maxContentLength 保持一致）
    static let maxMessageLength: Int = Message.maxContentLength
    
    /// 默认加载消息数量
    static let defaultMessageLimit: Int = 50
    
    // MARK: - Initialization
    
    init() {
        // 初始化时从本地存储加载缓存的消息
        loadCachedData()
    }
    
    // MARK: - Public Methods
    
    /// 发送消息
    /// - Parameters:
    ///   - content: 消息内容
    ///   - toUserId: 接收者ID
    /// Requirements: 5.2 - 消息应在3秒内送达
    /// Requirements: 5.7 - 消息最多1000字符
    func sendMessage(_ content: String, to toUserId: String) {
        // 验证消息长度
        guard content.count > 0 && content.count <= Self.maxMessageLength else {
            error = .messageTooLong
            return
        }
        
        // 检查是否被屏蔽
        guard !isBlocked(userId: toUserId) else {
            error = .userBlocked
            return
        }
        
        // TODO: 实现发送消息逻辑
        // 1. 创建 Message 对象
        // 2. 添加到对应的 thread
        // 3. 发送到服务器
        // 4. 更新 deliveredAt 时间戳
    }
    
    /// 加载消息
    /// - Parameters:
    ///   - threadId: 会话ID
    ///   - limit: 加载数量限制
    /// Requirements: 5.1 - 应在2秒内加载最近50条消息
    func loadMessages(threadId: String, limit: Int = defaultMessageLimit) {
        // TODO: 实现加载消息逻辑
        // 1. 从本地存储加载
        // 2. 从服务器同步最新消息
    }
    
    /// 标记消息为已读
    /// - Parameter threadId: 会话ID
    /// Requirements: 5.3 - 显示已读回执
    func markAsRead(threadId: String) {
        // TODO: 实现标记已读逻辑
        // 1. 更新本地消息的 readAt 时间戳
        // 2. 同步到服务器
        // 3. 更新 unreadCount
    }
    
    /// 删除会话
    /// - Parameter thread: 要删除的会话
    /// Requirements: 5.9 - 软删除，只从当前用户视图移除
    func deleteThread(_ thread: MessageThread) {
        // TODO: 实现删除会话逻辑
        // 1. 从 threads 列表移除
        // 2. 标记为已删除（软删除）
        // 3. 对方仍可见
    }
    
    /// 屏蔽用户
    /// - Parameter userId: 要屏蔽的用户ID
    /// Requirements: 5.5 - 屏蔽后阻止消息发送
    /// Requirements: 5.6 - 不通知被屏蔽用户
    func blockUser(_ userId: String) {
        // TODO: 实现屏蔽用户逻辑
        let blockedUser = BlockedUser(
            id: UUID().uuidString,
            blockedUserId: userId,
            blockedAt: Date()
        )
        blockedUsers.append(blockedUser)
    }
    
    /// 取消屏蔽用户
    /// - Parameter userId: 要取消屏蔽的用户ID
    func unblockUser(_ userId: String) {
        blockedUsers.removeAll { $0.blockedUserId == userId }
    }
    
    /// 检查用户是否被屏蔽
    /// - Parameter userId: 用户ID
    /// - Returns: 是否被屏蔽
    func isBlocked(userId: String) -> Bool {
        blockedUsers.contains { $0.blockedUserId == userId }
    }
    
    /// 获取与指定用户的会话
    /// - Parameter userId: 用户ID
    /// - Returns: 会话（如果存在）
    func getThread(with userId: String) -> MessageThread? {
        threads.first { $0.participantIds.contains(userId) }
    }
    
    /// 更新未读消息数
    func updateUnreadCount() {
        unreadCount = threads.reduce(0) { $0 + $1.unreadCount }
    }
    
    // MARK: - Private Methods
    
    /// 从本地存储加载缓存数据
    /// Requirements: 5.8 - 本地持久化消息
    private func loadCachedData() {
        // TODO: 从 UserDefaults 或文件系统加载缓存的消息
    }
    
    /// 保存数据到本地存储
    private func saveCachedData() {
        // TODO: 保存消息到本地存储
    }
    
    /// 网络恢复时同步数据
    /// Requirements: 5.8 - 网络恢复时同步
    func syncOnReconnect() {
        // TODO: 实现网络恢复时的数据同步
    }
}

// Note: MessageError is defined in MessageServiceProtocol.swift
