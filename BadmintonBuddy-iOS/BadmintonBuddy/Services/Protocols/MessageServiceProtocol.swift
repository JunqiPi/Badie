//
//  MessageServiceProtocol.swift
//  BadmintonBuddy
//
//  定义消息服务协议，用于私信功能
//

import Foundation

// MARK: - Forward Declarations (Placeholder Types)

/// 消息模型
/// - Note: 完整实现将在 Task 5.1 中创建
struct Message: Identifiable, Codable, Equatable {
    let id: String
    let threadId: String
    let senderId: String
    let content: String
    let sentAt: Date
    var deliveredAt: Date?
    var readAt: Date?
    
    /// 消息是否已送达
    var isDelivered: Bool { deliveredAt != nil }
    
    /// 消息是否已读
    var isRead: Bool { readAt != nil }
    
    /// 消息内容最大字符数
    static let maxContentLength = 1000
}

// MARK: - Message Service Protocol

/// 消息服务协议
/// 提供私信发送、加载和状态管理功能
/// - Requirements: 5.1, 5.2, 5.3, 5.7, 5.8
protocol MessageServiceProtocol {
    
    /// 发送消息给指定用户
    /// - Parameters:
    ///   - message: 要发送的消息
    ///   - userId: 接收者用户ID
    /// - Throws: 网络错误、用户被屏蔽或消息过长时抛出错误
    /// - Note: 消息内容不能超过1000字符
    func sendMessage(_ message: Message, to userId: String) async throws
    
    /// 加载指定会话的消息
    /// - Parameters:
    ///   - threadId: 会话ID
    ///   - limit: 加载消息数量限制，默认50条
    /// - Returns: 按时间排序的消息列表
    /// - Throws: 网络错误或会话不存在时抛出错误
    /// - Note: 应在2秒内返回最近50条消息
    func loadMessages(threadId: String, limit: Int) async throws -> [Message]
    
    /// 标记会话为已读
    /// - Parameter threadId: 会话ID
    /// - Throws: 网络错误时抛出错误
    func markAsRead(threadId: String) async throws
}

// MARK: - Message Errors

/// 消息服务错误类型
enum MessageError: Error, LocalizedError {
    case contentTooLong(maxLength: Int)
    case contentEmpty
    case userBlocked
    case threadNotFound
    case networkError(underlying: Error)
    case deliveryFailed
    
    var errorDescription: String? {
        switch self {
        case .contentTooLong(let maxLength):
            return "消息不能超过\(maxLength)字"
        case .contentEmpty:
            return "消息内容不能为空"
        case .userBlocked:
            return "无法发送消息给该用户"
        case .threadNotFound:
            return "会话不存在"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .deliveryFailed:
            return "消息发送失败，请重试"
        }
    }
}
