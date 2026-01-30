//
//  SurveyServiceProtocol.swift
//  BadmintonBuddy
//
//  定义问卷服务协议，用于赛后评价和声誉系统
//

import Foundation

// MARK: - Forward Declarations (Placeholder Types)

/// 比赛问卷模型
/// - Note: 完整实现将在 Task 2.5 中创建
struct MatchSurvey: Identifiable, Codable {
    let id: String
    let matchId: String
    let evaluatorId: String
    let evaluatedUserId: String
    let skillRating: Int // 1-9
    let wasPunctual: Bool
    let characterRating: Int // 1-5
    let submittedAt: Date
    
    /// 技能评分有效范围
    static let skillRatingRange = 1...9
    
    /// 人品评分有效范围
    static let characterRatingRange = 1...5
}

/// 待完成问卷模型
/// - Note: 完整实现将在 Task 2.5 中创建
struct PendingSurvey: Identifiable, Codable {
    let id: String
    let matchId: String
    let opponentId: String
    let opponentNickname: String
    let matchDate: Date
    let expiresAt: Date
    
    /// 问卷是否已过期（48小时后过期）
    var isExpired: Bool { Date() > expiresAt }
    
    /// 问卷有效期：48小时
    static let validityDuration: TimeInterval = 48 * 60 * 60
}

/// 声誉分数模型
/// - Note: 完整实现将在 Task 2.5 中创建
struct ReputationScore: Codable, Equatable {
    var averageSkillAccuracy: Double // 技能评分准确度
    var punctualityPercentage: Double // 准时率百分比
    var averageCharacterRating: Double // 平均人品评分 (1-5)
    var evaluationCount: Int // 评价数量
    
    /// 是否为新玩家（评价数少于5次）
    var isNewPlayer: Bool { evaluationCount < 5 }
    
    /// 空的声誉分数（新用户默认值）
    static let empty = ReputationScore(
        averageSkillAccuracy: 0,
        punctualityPercentage: 100,
        averageCharacterRating: 3,
        evaluationCount: 0
    )
    
    /// 成为非新玩家所需的最小评价数
    static let minimumEvaluationsForDisplay = 5
}

// MARK: - Survey Service Protocol

/// 问卷服务协议
/// 提供赛后问卷提交、获取和声誉计算功能
/// - Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.8, 6.9
protocol SurveyServiceProtocol {
    
    /// 提交比赛问卷
    /// - Parameter survey: 要提交的问卷
    /// - Throws: 问卷过期、重复提交或网络错误时抛出错误
    /// - Note: 每场比赛每个评价者只能提交一次问卷
    func submitSurvey(_ survey: MatchSurvey) async throws
    
    /// 获取待完成的问卷列表
    /// - Returns: 未过期的待完成问卷列表
    /// - Throws: 网络错误时抛出错误
    /// - Note: 自动过滤已过期的问卷
    func getPendingSurveys() async throws -> [PendingSurvey]
    
    /// 计算用户的声誉分数
    /// - Parameter userId: 用户ID
    /// - Returns: 计算后的声誉分数
    /// - Note: 声誉分数基于技能准确度、准时率和人品评分计算
    func calculateReputationScore(userId: String) -> ReputationScore
}

// MARK: - Survey Errors

/// 问卷服务错误类型
enum SurveyError: Error, LocalizedError {
    case surveyExpired
    case duplicateSubmission
    case invalidRating(field: String, validRange: ClosedRange<Int>)
    case matchNotFound
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .surveyExpired:
            return "问卷已过期，无法提交"
        case .duplicateSubmission:
            return "您已提交过此问卷"
        case .invalidRating(let field, let range):
            return "\(field)评分必须在\(range.lowerBound)-\(range.upperBound)之间"
        case .matchNotFound:
            return "比赛记录不存在"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
