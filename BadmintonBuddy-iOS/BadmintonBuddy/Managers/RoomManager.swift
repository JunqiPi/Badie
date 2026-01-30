import Foundation
import Combine

// MARK: - RoomManager (房间管理器)
/// 管理自定义游戏房间
/// Requirements: 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10
class RoomManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前所在的房间
    @Published var currentRoom: Room?
    
    /// 当前房间码
    @Published var roomCode: String?
    
    /// 是否正在加载
    @Published var isLoading: Bool = false
    
    /// 错误信息（使用 RoomServiceProtocol 中定义的 RoomError）
    @Published var error: RoomManagerError?
    
    // MARK: - Private Properties
    
    /// 房间过期检查定时器
    private var expirationTimer: Timer?
    
    /// 房间过期时间（30分钟）
    static let roomExpirationSeconds: TimeInterval = 1800
    
    // MARK: - Initialization
    
    init() {
        // 初始化时可以恢复之前的房间状态
    }
    
    deinit {
        expirationTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// 创建房间
    /// - Parameter mode: 游戏模式（单打/双打）
    /// Requirements: 3.3 - 允许创建指定模式的房间
    /// Requirements: 3.4 - 生成唯一的6位房间码
    func createRoom(mode: GameMode) {
        isLoading = true
        
        // 生成房间码
        let code = Room.generateCode()
        
        // TODO: 实际实现需要与服务器交互确保房间码唯一
        let room = Room(
            id: UUID().uuidString,
            code: code,
            ownerId: "", // TODO: 从 AppState 获取当前用户ID
            mode: mode,
            participants: [],
            createdAt: Date(),
            lastActivityAt: Date()
        )
        
        currentRoom = room
        roomCode = code
        isLoading = false
        
        // 启动过期检查定时器
        startExpirationTimer()
    }
    
    /// 加入房间
    /// - Parameter code: 房间码
    /// Requirements: 3.4 - 通过房间码加入
    func joinRoom(code: String) {
        isLoading = true
        
        // TODO: 实现加入房间逻辑
        // 1. 验证房间码格式
        // 2. 向服务器请求加入
        // 3. 更新 currentRoom
        
        // 验证房间码格式
        guard code.count == 6 else {
            error = .invalidCode
            isLoading = false
            return
        }
        
        // TODO: 从服务器获取房间信息
        isLoading = false
    }
    
    /// 离开房间
    func leaveRoom() {
        // TODO: 实现离开房间逻辑
        // 1. 通知服务器
        // 2. 清理本地状态
        
        stopExpirationTimer()
        currentRoom = nil
        roomCode = nil
    }
    
    /// 踢出玩家（仅房主可用）
    /// - Parameter participant: 要踢出的参与者
    /// Requirements: 3.9 - 房主可以踢出玩家
    /// Requirements: 3.10 - 被踢出的玩家立即移除并收到通知
    func kickPlayer(_ participant: RoomParticipant) {
        guard var room = currentRoom else {
            error = .notInRoom
            return
        }
        
        // TODO: 验证当前用户是否为房主
        
        // 从参与者列表移除
        room.participants.removeAll { $0.id == participant.id }
        currentRoom = room
        
        // 更新最后活动时间
        updateLastActivity()
        
        // TODO: 通知被踢出的玩家
    }
    
    /// 邀请好友加入房间
    /// - Parameter friend: 要邀请的好友
    /// Requirements: 3.5 - 房主可以邀请好友
    func inviteFriend(_ friend: User) {
        guard currentRoom != nil else {
            error = .notInRoom
            return
        }
        
        // TODO: 实现邀请好友逻辑
        // 1. 发送邀请通知给好友
        // 2. 等待好友接受
        
        updateLastActivity()
    }
    
    /// 开始比赛
    /// Requirements: 3.6 - 人数满足时启用开始按钮
    /// Requirements: 3.7 - 开始后所有参与者进入确认页面
    func startMatch() {
        guard let room = currentRoom else {
            error = .notInRoom
            return
        }
        
        // 检查人数是否满足
        guard room.isReady else {
            error = .notEnoughPlayers
            return
        }
        
        // TODO: 实现开始比赛逻辑
        // 1. 通知所有参与者
        // 2. 转换到比赛确认页面
        
        stopExpirationTimer()
    }
    
    /// 更新最后活动时间
    private func updateLastActivity() {
        currentRoom?.lastActivityAt = Date()
    }
    
    // MARK: - Expiration Timer
    
    /// 启动过期检查定时器
    /// Requirements: 3.8 - 30分钟无活动自动关闭房间
    private func startExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkExpiration()
        }
    }
    
    /// 停止过期检查定时器
    private func stopExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil
    }
    
    /// 检查房间是否过期
    private func checkExpiration() {
        guard let room = currentRoom else { return }
        
        if room.isExpired {
            // 房间已过期，自动关闭
            error = .roomExpired
            leaveRoom()
            // TODO: 通知所有参与者
        }
    }
}

// Note: RoomError is defined in RoomServiceProtocol.swift
// Using local error enum for manager-specific errors

enum RoomManagerError: Error, Equatable {
    case invalidCode
    case roomNotFound
    case roomFull
    case roomExpired
    case notInRoom
    case notRoomOwner
    case notEnoughPlayers
    case alreadyInRoom
    case networkError(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidCode:
            return "房间码无效，请检查后重试"
        case .roomNotFound:
            return "房间不存在"
        case .roomFull:
            return "房间已满"
        case .roomExpired:
            return "房间已过期"
        case .notInRoom:
            return "您不在房间中"
        case .notRoomOwner:
            return "只有房主可以执行此操作"
        case .notEnoughPlayers:
            return "人数不足，无法开始比赛"
        case .alreadyInRoom:
            return "您已在房间中"
        case .networkError(let message):
            return message
        }
    }
}
