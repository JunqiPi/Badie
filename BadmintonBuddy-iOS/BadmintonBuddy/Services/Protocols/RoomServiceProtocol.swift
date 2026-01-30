//
//  RoomServiceProtocol.swift
//  BadmintonBuddy
//
//  定义房间服务协议，用于自定义游戏房间功能
//

import Foundation

// MARK: - Forward Declarations (Placeholder Types)

/// 房间参与者模型
/// - Note: 完整实现将在 Task 4.5 中创建
struct RoomParticipant: Identifiable, Codable, Equatable {
    let id: String
    let oderId: String
    let nickname: String
    let skillLevel: Int
    let joinedAt: Date
}

/// 房间模型
/// - Note: 完整实现将在 Task 4.1 中创建
struct Room: Identifiable, Codable {
    let id: String
    let code: String // 6位字母数字房间码
    let ownerId: String
    let mode: GameMode
    var participants: [RoomParticipant]
    let createdAt: Date
    var lastActivityAt: Date
    
    /// 所需玩家数量
    var requiredPlayerCount: Int {
        mode == .singles ? 2 : 4
    }
    
    /// 房间是否已满员可以开始
    var isReady: Bool {
        participants.count == requiredPlayerCount
    }
    
    /// 房间是否已过期（30分钟无活动）
    var isExpired: Bool {
        Date().timeIntervalSince(lastActivityAt) > Room.expirationDuration
    }
    
    /// 房间过期时间：30分钟
    static let expirationDuration: TimeInterval = 30 * 60
    
    /// 房间码长度
    static let codeLength = 6
    
    /// 房间码有效字符集（排除易混淆字符 0, O, I, L, 1）
    static let codeCharacters = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    
    /// 生成随机房间码
    static func generateCode() -> String {
        String((0..<codeLength).map { _ in codeCharacters.randomElement()! })
    }
}

// MARK: - Room Service Protocol

/// 房间服务协议
/// 提供房间创建、加入、邀请和管理功能
/// - Requirements: 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10
protocol RoomServiceProtocol {
    
    /// 创建新房间
    /// - Parameter mode: 游戏模式（单打/双打）
    /// - Returns: 创建的房间对象
    /// - Throws: 网络错误时抛出错误
    /// - Note: 自动生成6位唯一房间码
    func createRoom(mode: GameMode) async throws -> Room
    
    /// 通过房间码加入房间
    /// - Parameter code: 6位房间码
    /// - Returns: 加入的房间对象
    /// - Throws: 房间不存在、已满或已过期时抛出错误
    func joinRoom(code: String) async throws -> Room
    
    /// 邀请好友加入房间
    /// - Parameters:
    ///   - roomId: 房间ID
    ///   - userId: 被邀请用户ID
    /// - Throws: 非房主操作、房间已满或网络错误时抛出错误
    /// - Note: 只有房主可以邀请好友
    func inviteToRoom(roomId: String, userId: String) async throws
    
    /// 离开房间
    /// - Parameter roomId: 房间ID
    /// - Throws: 网络错误时抛出错误
    /// - Note: 如果房主离开，房间将被关闭
    func leaveRoom(roomId: String) async throws
    
    /// 开始比赛
    /// - Parameter roomId: 房间ID
    /// - Throws: 非房主操作、人数不足或网络错误时抛出错误
    /// - Note: 只有房主可以开始比赛，且房间必须满员
    func startMatch(roomId: String) async throws
}

// MARK: - Room Errors

/// 房间服务错误类型
enum RoomError: Error, LocalizedError {
    case roomNotFound
    case roomFull
    case roomExpired
    case notRoomOwner
    case alreadyInRoom
    case notEnoughPlayers(required: Int, current: Int)
    case invalidCode
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .roomNotFound:
            return "房间不存在"
        case .roomFull:
            return "房间已满"
        case .roomExpired:
            return "房间已过期"
        case .notRoomOwner:
            return "只有房主可以执行此操作"
        case .alreadyInRoom:
            return "您已在房间中"
        case .notEnoughPlayers(let required, let current):
            return "人数不足，需要\(required)人，当前\(current)人"
        case .invalidCode:
            return "房间码无效，请检查后重试"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
