//
//  MatchingServiceProtocol.swift
//  BadmintonBuddy
//
//  定义匹配服务协议，用于基于球馆选择、技能等级和时间段进行玩家匹配
//  - Requirements: 6.1, 6.2, 6.3, 6.5
//

import Foundation

// MARK: - TimeSlot
// TimeSlot 模型已移至 Models/TimeSlotModels.swift
// - Requirements: 4.2, 4.3

// MARK: - 匹配候选人模型

/// 匹配候选人模型
/// 表示一个潜在的匹配对手，包含用户信息、距离、技能差异和重叠时间段
/// - Requirements: 4.4, 4.5, 6.2, 6.3
struct MatchCandidate: Identifiable, Equatable {
    /// 唯一标识符
    let id: String
    
    /// 候选用户的完整信息
    /// 包含昵称、技能等级、声誉评分等所有用户属性
    let user: User
    
    /// 与球馆的距离（公里）
    /// 注意：现在是到球馆的距离，而不是到用户的距离
    /// - Requirements: 6.3
    let distance: Double
    
    /// 技能等级差异
    /// 正值表示候选人等级更高，负值表示更低
    /// 匹配算法使用绝对值进行排序
    let skillDifference: Int
    
    /// 重叠的可用时间段
    /// 当前用户和候选人时间段的交集，至少30分钟
    /// - Requirements: 4.3
    let overlappingTimeSlot: TimeSlot
    
    // MARK: - 球馆匹配属性
    
    /// 匹配的球馆（双方都选择的球馆）
    /// - Requirements: 6.3
    let matchedCourt: BadmintonCourt
    
    /// 共同选择的球馆数量
    /// - Requirements: 6.2
    let commonCourtCount: Int
    
    // MARK: - 计算属性
    
    /// 匹配分数（越低越好）
    /// 计算公式: |技能差异| × 10 - 共同球馆数 × 5
    /// 优先考虑技能匹配（权重10），其次是球馆重叠（权重5）
    /// - Requirements: 6.2
    /// - Note: 分数越低表示匹配质量越高
    var matchScore: Double {
        let skillWeight = 10.0
        let courtWeight = 5.0
        return Double(abs(skillDifference)) * skillWeight - Double(commonCourtCount) * courtWeight
    }
    
    /// 候选人的昵称（便捷访问）
    var nickname: String {
        user.nickname
    }
    
    /// 候选人的显示技能等级（便捷访问）
    var skillLevel: Int {
        user.displayLevel
    }
    
    /// 候选人的声誉评分（便捷访问）
    var reputation: ReputationScore {
        user.reputation
    }
    
    /// 是否为新玩家（评价数少于5次）
    var isNewPlayer: Bool {
        user.reputation.isNewPlayer
    }
    
    /// 格式化的距离显示（到球馆的距离）
    var formattedDistance: String {
        if distance < 1 {
            return String(format: "%.0f 米", distance * 1000)
        } else {
            return String(format: "%.1f 公里", distance)
        }
    }
    
    /// 格式化的技能差异显示
    var formattedSkillDifference: String {
        if skillDifference == 0 {
            return "同等级"
        } else if skillDifference > 0 {
            return "+\(skillDifference) 级"
        } else {
            return "\(skillDifference) 级"
        }
    }
    
    // MARK: - 初始化器
    
    /// 创建匹配候选人（基于球馆匹配）
    /// - Parameters:
    ///   - id: 唯一标识符（默认使用用户ID）
    ///   - user: 候选用户
    ///   - distance: 到球馆的距离（公里）
    ///   - skillDifference: 技能差异
    ///   - overlappingTimeSlot: 重叠时间段
    ///   - matchedCourt: 匹配的球馆
    ///   - commonCourtCount: 共同选择的球馆数量
    /// - Requirements: 6.2, 6.3
    init(
        id: String? = nil,
        user: User,
        distance: Double,
        skillDifference: Int,
        overlappingTimeSlot: TimeSlot,
        matchedCourt: BadmintonCourt,
        commonCourtCount: Int
    ) {
        self.id = id ?? user.id
        self.user = user
        self.distance = distance
        self.skillDifference = skillDifference
        self.overlappingTimeSlot = overlappingTimeSlot
        self.matchedCourt = matchedCourt
        self.commonCourtCount = commonCourtCount
    }
    
    // MARK: - Equatable
    
    static func == (lhs: MatchCandidate, rhs: MatchCandidate) -> Bool {
        lhs.id == rhs.id &&
        lhs.user == rhs.user &&
        lhs.distance == rhs.distance &&
        lhs.skillDifference == rhs.skillDifference &&
        lhs.overlappingTimeSlot == rhs.overlappingTimeSlot &&
        lhs.matchedCourt == rhs.matchedCourt &&
        lhs.commonCourtCount == rhs.commonCourtCount
    }
}

// MARK: - 匹配候选人排序扩展

extension Array where Element == MatchCandidate {
    /// 按匹配分数排序（升序，分数越低越好）
    /// - Requirements: 4.4, 4.5
    /// - Returns: 排序后的候选人列表
    func sortedByMatchScore() -> [MatchCandidate] {
        sorted { $0.matchScore < $1.matchScore }
    }
    
    /// 获取最佳匹配候选人
    /// - Returns: 匹配分数最低的候选人，如果列表为空则返回nil
    var bestMatch: MatchCandidate? {
        min(by: { $0.matchScore < $1.matchScore })
    }
    
    /// 按技能差异分组
    /// - Returns: 按技能差异绝对值分组的字典
    func groupedBySkillDifference() -> [Int: [MatchCandidate]] {
        Dictionary(grouping: self) { abs($0.skillDifference) }
    }
}

// MARK: - Matching Service Protocol

/// 基于球馆的匹配服务协议
/// 提供基于球馆选择、技能等级和时间段的玩家匹配功能
/// - Requirements: 6.1, 6.2, 6.3, 6.4, 6.5
protocol MatchingServiceProtocol {
    
    /// 基于球馆的匹配查找
    /// - Parameters:
    ///   - mode: 游戏模式（单打/双打）
    ///   - skillLevel: 当前用户技能等级 (1-9)
    ///   - selectedCourtIds: 用户选择的球馆ID集合
    ///   - timeSlot: 期望的时间段
    ///   - currentUserId: 当前用户ID（排除自己）
    /// - Returns: 按匹配分数排序的候选人列表
    /// - Throws: 网络错误或无可用匹配时抛出错误
    /// - Note: 只匹配至少有一个共同球馆选择的用户
    /// - Requirements: 6.1, 6.5
    func findMatches(
        mode: GameMode,
        skillLevel: Int,
        selectedCourtIds: Set<String>,
        timeSlot: TimeSlot,
        currentUserId: String
    ) async throws -> [MatchCandidate]
}

// MARK: - Matching Errors

/// 匹配服务错误类型
enum MatchingError: Error, LocalizedError {
    case noMatchesFound
    case locationUnavailable
    case networkError(underlying: Error)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .noMatchesFound:
            return "未找到匹配的玩家"
        case .locationUnavailable:
            return "位置服务不可用"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .timeout:
            return "匹配超时，请重试"
        }
    }
}
