import Foundation
import Combine

// MARK: - SurveyManager (问卷管理器)
/// 管理赛后评价问卷
/// Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.8, 6.9
class SurveyManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 待完成的问卷列表
    @Published var pendingSurveys: [PendingSurvey] = []
    
    /// 已完成的问卷列表
    @Published var completedSurveys: [MatchSurvey] = []
    
    /// 是否正在加载
    @Published var isLoading: Bool = false
    
    /// 错误信息
    @Published var error: SurveyManagerError?
    
    // MARK: - Constants
    
    /// 问卷过期时间（48小时）
    static let surveyExpirationHours: TimeInterval = 48
    
    // MARK: - Initialization
    
    init() {
        // 初始化时加载缓存的问卷数据
        loadCachedData()
    }
    
    // MARK: - Public Methods
    
    /// 提交问卷
    /// - Parameter survey: 问卷数据
    /// Requirements: 6.2 - 问卷包含技能评分(1-9)、准时性(是/否)、人品评分(1-5)
    /// Requirements: 6.8 - 防止重复提交
    /// Requirements: 6.9 - 提交后30秒内更新对方声誉分
    func submitSurvey(_ survey: MatchSurvey) {
        // 检查是否已提交过
        guard !hasSubmittedSurvey(matchId: survey.matchId, evaluatorId: survey.evaluatorId) else {
            error = .alreadySubmitted
            return
        }
        
        // 验证问卷数据
        guard isValidSurvey(survey) else {
            error = .invalidData
            return
        }
        
        // TODO: 实现提交问卷逻辑
        // 1. 发送到服务器
        // 2. 添加到 completedSurveys
        // 3. 从 pendingSurveys 移除对应项
        // 4. 更新对方的声誉分
        
        completedSurveys.append(survey)
        pendingSurveys.removeAll { $0.matchId == survey.matchId }
    }
    
    /// 获取待完成的问卷（过滤已过期的）
    /// - Returns: 未过期的待完成问卷列表
    /// Requirements: 6.3 - 48小时内完成
    /// Requirements: 6.4 - 过期问卷不计入计算
    func getPendingSurveys() -> [PendingSurvey] {
        pendingSurveys.filter { !$0.isExpired }
    }
    
    /// 计算用户的声誉分
    /// - Parameter userId: 用户ID
    /// - Returns: 声誉分数
    /// Requirements: 6.5 - 基于技能准确度、准时率、人品评分计算
    func calculateReputationScore(userId: String) -> ReputationScore {
        // 获取该用户收到的所有评价
        let userSurveys = completedSurveys.filter { $0.evaluatedUserId == userId }
        
        guard !userSurveys.isEmpty else {
            return ReputationScore.empty
        }
        
        // 计算平均技能准确度（与自评的偏差）
        // TODO: 需要获取用户的自评等级来计算偏差
        let averageSkillAccuracy = Double(userSurveys.reduce(0) { $0 + $1.skillRating }) / Double(userSurveys.count)
        
        // 计算准时率
        let punctualCount = userSurveys.filter { $0.wasPunctual }.count
        let punctualityPercentage = Double(punctualCount) / Double(userSurveys.count) * 100
        
        // 计算平均人品评分
        let averageCharacterRating = Double(userSurveys.reduce(0) { $0 + $1.characterRating }) / Double(userSurveys.count)
        
        return ReputationScore(
            averageSkillAccuracy: averageSkillAccuracy,
            punctualityPercentage: punctualityPercentage,
            averageCharacterRating: averageCharacterRating,
            evaluationCount: userSurveys.count
        )
    }
    
    /// 为比赛创建待完成问卷
    /// - Parameters:
    ///   - matchId: 比赛ID
    ///   - participants: 参与者列表
    ///   - currentUserId: 当前用户ID
    /// Requirements: 6.1 - 比赛完成后1分钟内发送问卷通知
    func createPendingSurveys(matchId: String, participants: [User], currentUserId: String) {
        let expiresAt = Date().addingTimeInterval(Self.surveyExpirationHours * 3600)
        
        // 为每个对手创建一个待完成问卷
        for participant in participants where participant.id != currentUserId {
            let pendingSurvey = PendingSurvey(
                id: UUID().uuidString,
                matchId: matchId,
                opponentId: participant.id,
                opponentNickname: participant.nickname,
                matchDate: Date(),
                expiresAt: expiresAt
            )
            pendingSurveys.append(pendingSurvey)
        }
    }
    
    /// 检查是否已提交过问卷
    /// - Parameters:
    ///   - matchId: 比赛ID
    ///   - evaluatorId: 评价者ID
    /// - Returns: 是否已提交
    func hasSubmittedSurvey(matchId: String, evaluatorId: String) -> Bool {
        completedSurveys.contains { $0.matchId == matchId && $0.evaluatorId == evaluatorId }
    }
    
    /// 验证问卷数据是否有效
    /// - Parameter survey: 问卷数据
    /// - Returns: 是否有效
    private func isValidSurvey(_ survey: MatchSurvey) -> Bool {
        // 技能评分 1-9
        guard survey.skillRating >= 1 && survey.skillRating <= 9 else { return false }
        // 人品评分 1-5
        guard survey.characterRating >= 1 && survey.characterRating <= 5 else { return false }
        return true
    }
    
    // MARK: - Private Methods
    
    /// 从本地存储加载缓存数据
    private func loadCachedData() {
        // TODO: 从 UserDefaults 或文件系统加载缓存的问卷数据
    }
    
    /// 保存数据到本地存储
    private func saveCachedData() {
        // TODO: 保存问卷数据到本地存储
    }
    
    /// 清理过期的待完成问卷
    func cleanupExpiredSurveys() {
        pendingSurveys.removeAll { $0.isExpired }
    }
}

// Note: SurveyError is defined in SurveyServiceProtocol.swift
// Using local error enum for manager-specific errors

enum SurveyManagerError: Error, Equatable {
    case alreadySubmitted
    case surveyExpired
    case invalidData
    case surveyNotFound
    case networkError(String)
    
    var localizedDescription: String {
        switch self {
        case .alreadySubmitted:
            return "您已提交过此问卷"
        case .surveyExpired:
            return "问卷已过期，无法提交"
        case .invalidData:
            return "问卷数据无效"
        case .surveyNotFound:
            return "问卷不存在"
        case .networkError(let message):
            return message
        }
    }
}
