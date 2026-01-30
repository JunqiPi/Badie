import Foundation

// MARK: - 坐标模型
/// 地理坐标，用于位置计算
/// - Requirements: 1.3
struct Coordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    /// 使用 Haversine 公式计算到另一坐标的距离（英里）
    /// - Parameter other: 目标坐标
    /// - Returns: 距离（英里）
    func distance(to other: Coordinate) -> Double {
        let earthRadiusMiles = 3958.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        
        let a = sin(deltaLat/2) * sin(deltaLat/2) +
                cos(lat1) * cos(lat2) * sin(deltaLon/2) * sin(deltaLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return earthRadiusMiles * c
    }
}

// MARK: - 验证状态
/// 用户技能等级验证状态
/// - Requirements: 2.3, 2.4
enum VerificationStatus: String, Codable {
    case unverified          // 未验证
    case regionalChampion    // 地区冠军 - 8级所需
    case nationalChampion    // 全国冠军 - 9级所需
}

// MARK: - 用户模型
/// 增强版用户模型，支持9级技能系统和声誉评分
/// - Requirements: 2.1, 2.6, 2.7
struct User: Identifiable, Codable, Equatable {
    let id: String
    var nickname: String
    var phone: String
    var selfReportedLevel: Int      // 自报技能等级 (1-9)
    var calculatedLevel: Double     // 加权平均计算等级
    var totalGames: Int
    var wins: Int
    var joinDate: Date
    var location: Coordinate?
    var lastLocationUpdate: Date?
    var verificationStatus: VerificationStatus
    var reputation: ReputationScore
    
    /// 显示等级：70% 同行评价 + 30% 自报（需要至少5次评价）
    /// - Requirements: 2.6, 2.7
    var displayLevel: Int {
        // 评价数少于5次时，仅显示自报等级
        guard reputation.evaluationCount >= 5 else { return selfReportedLevel }
        return Int(round(calculatedLevel))
    }
    
    /// 胜率百分比
    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames) * 100
    }
    
    /// 自报等级有效范围
    static let selfReportedLevelRange = 1...9
    
    /// 自选等级最大值（8-9级需要验证）
    static let maxSelfSelectableLevel = 7
    
    /// 显示等级计算所需的最小评价数
    static let minimumEvaluationsForWeightedLevel = 5
    
    /// 自报等级权重
    static let selfReportedWeight: Double = 0.3
    
    /// 同行评价权重
    static let peerEvaluationWeight: Double = 0.7
    
    // MARK: - 便捷初始化器
    
    /// 创建新用户（注册时使用）
    /// - Parameters:
    ///   - id: 用户ID
    ///   - nickname: 昵称
    ///   - phone: 手机号
    ///   - selfReportedLevel: 自报技能等级 (1-7，8-9需要验证)
    init(
        id: String,
        nickname: String,
        phone: String,
        selfReportedLevel: Int,
        totalGames: Int = 0,
        wins: Int = 0,
        joinDate: Date = Date(),
        location: Coordinate? = nil,
        lastLocationUpdate: Date? = nil,
        verificationStatus: VerificationStatus = .unverified,
        reputation: ReputationScore = .empty
    ) {
        self.id = id
        self.nickname = nickname
        self.phone = phone
        // 确保自报等级在有效范围内
        self.selfReportedLevel = min(max(selfReportedLevel, 1), 9)
        // 初始计算等级等于自报等级
        self.calculatedLevel = Double(self.selfReportedLevel)
        self.totalGames = totalGames
        self.wins = wins
        self.joinDate = joinDate
        self.location = location
        self.lastLocationUpdate = lastLocationUpdate
        self.verificationStatus = verificationStatus
        self.reputation = reputation
    }
    
    /// 完整初始化器（从服务器加载时使用）
    init(
        id: String,
        nickname: String,
        phone: String,
        selfReportedLevel: Int,
        calculatedLevel: Double,
        totalGames: Int,
        wins: Int,
        joinDate: Date,
        location: Coordinate?,
        lastLocationUpdate: Date?,
        verificationStatus: VerificationStatus,
        reputation: ReputationScore
    ) {
        self.id = id
        self.nickname = nickname
        self.phone = phone
        self.selfReportedLevel = selfReportedLevel
        self.calculatedLevel = calculatedLevel
        self.totalGames = totalGames
        self.wins = wins
        self.joinDate = joinDate
        self.location = location
        self.lastLocationUpdate = lastLocationUpdate
        self.verificationStatus = verificationStatus
        self.reputation = reputation
    }
    
    /// 更新计算等级（收到新评价后调用）
    /// - Parameter peerAverageLevel: 同行评价的平均等级
    mutating func updateCalculatedLevel(peerAverageLevel: Double) {
        // 公式: 30% 自报 + 70% 同行评价
        calculatedLevel = User.selfReportedWeight * Double(selfReportedLevel) +
                         User.peerEvaluationWeight * peerAverageLevel
    }
    
    // MARK: - Mock Data
    
    static let mockOpponents: [User] = [
        User(
            id: "1",
            nickname: "小明",
            phone: "138****1234",
            selfReportedLevel: 6,
            totalGames: 45,
            wins: 32,
            reputation: ReputationScore(
                averageSkillAccuracy: 0.9,
                punctualityPercentage: 95,
                averageCharacterRating: 4.5,
                evaluationCount: 12
            )
        ),
        User(
            id: "2",
            nickname: "阿杰",
            phone: "139****5678",
            selfReportedLevel: 4,
            totalGames: 28,
            wins: 18,
            reputation: ReputationScore(
                averageSkillAccuracy: 0.85,
                punctualityPercentage: 88,
                averageCharacterRating: 4.2,
                evaluationCount: 8
            )
        ),
        User(
            id: "3",
            nickname: "小红",
            phone: "137****9012",
            selfReportedLevel: 7,
            totalGames: 120,
            wins: 98,
            verificationStatus: .regionalChampion,
            reputation: ReputationScore(
                averageSkillAccuracy: 0.95,
                punctualityPercentage: 100,
                averageCharacterRating: 4.8,
                evaluationCount: 35
            )
        ),
        User(
            id: "4",
            nickname: "大伟",
            phone: "136****3456",
            selfReportedLevel: 2,
            totalGames: 12,
            wins: 5,
            reputation: ReputationScore(
                averageSkillAccuracy: 0.8,
                punctualityPercentage: 75,
                averageCharacterRating: 3.5,
                evaluationCount: 3  // 新玩家
            )
        ),
        User(
            id: "5",
            nickname: "小李",
            phone: "135****7890",
            selfReportedLevel: 5,
            totalGames: 35,
            wins: 22,
            reputation: ReputationScore(
                averageSkillAccuracy: 0.88,
                punctualityPercentage: 92,
                averageCharacterRating: 4.0,
                evaluationCount: 10
            )
        )
    ]
}

// MARK: - 旧版技能等级（保留向后兼容）
/// 旧版技能等级枚举，用于向后兼容
/// - Note: 新代码应使用 User.selfReportedLevel (1-9)
@available(*, deprecated, message: "使用 User.selfReportedLevel (1-9) 替代")
enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case beginner = "入门"
    case intermediate = "业余"
    case advanced = "进阶"
    case pro = "专业"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .beginner: return "🌱"
        case .intermediate: return "⭐"
        case .advanced: return "🔥"
        case .pro: return "👑"
        }
    }
    
    var displayText: String {
        "\(icon) \(rawValue)"
    }
    
    /// 转换为新的9级系统
    var toNineLevel: Int {
        switch self {
        case .beginner: return 2
        case .intermediate: return 4
        case .advanced: return 6
        case .pro: return 7
        }
    }
    
    /// 从9级系统转换
    static func fromNineLevel(_ level: Int) -> SkillLevel {
        switch level {
        case 1...2: return .beginner
        case 3...4: return .intermediate
        case 5...6: return .advanced
        default: return .pro
        }
    }
}

// MARK: - 游戏模式
enum GameMode: String, CaseIterable, Identifiable, Codable {
    case singles = "单打"
    case doubles = "双打"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .singles: return "🎯"
        case .doubles: return "🤝"
        }
    }
    
    var description: String {
        switch self {
        case .singles: return "1 vs 1 对决"
        case .doubles: return "2 vs 2 组队"
        }
    }
    
    /// 所需玩家数量
    var requiredPlayers: Int {
        switch self {
        case .singles: return 2
        case .doubles: return 4
        }
    }
}

// MARK: - 匹配结果
/// 匹配结果模型，包含对手信息和匹配的球馆
/// - Requirements: 7.1, 7.2, 7.3, 7.4
struct MatchResult: Codable {
    /// 匹配的对手
    let opponent: User
    
    /// 匹配的球馆（替换原有的 venue 字符串）
    /// - Requirements: 7.2
    let court: BadmintonCourt
    
    /// 到球馆的距离（公里）
    /// - Note: 现在是到球馆的距离，而不是到对手的距离
    /// - Requirements: 7.3
    let distance: Double
    
    /// 建议的比赛时间
    let suggestedTime: Date
    
    // MARK: - 计算属性
    
    /// 格式化的距离显示
    /// - Requirements: 7.3
    var formattedDistance: String {
        if distance < 1 {
            return String(format: "%.0f 米", distance * 1000)
        } else {
            return String(format: "%.1f 公里", distance)
        }
    }
    
    /// 格式化的建议时间显示
    var formattedSuggestedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: suggestedTime)
    }
    
    // MARK: - Mock 数据
    
    static let mock = MatchResult(
        opponent: User.mockOpponents[0],
        court: BadmintonCourt.mock,
        distance: 1.2,
        suggestedTime: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
    )
}


// MARK: - 技能等级显示辅助
/// 9级技能系统的显示辅助扩展
extension User {
    /// 获取技能等级的图标
    static func skillLevelIcon(for level: Int) -> String {
        switch level {
        case 1...2: return "🌱"
        case 3...4: return "⭐"
        case 5...6: return "🔥"
        case 7: return "💎"
        case 8: return "🏆"
        case 9: return "👑"
        default: return "⭐"
        }
    }
    
    /// 获取技能等级的名称
    static func skillLevelName(for level: Int) -> String {
        switch level {
        case 1: return "入门"
        case 2: return "初学"
        case 3: return "业余"
        case 4: return "进阶"
        case 5: return "中级"
        case 6: return "高级"
        case 7: return "专业"
        case 8: return "地区冠军"
        case 9: return "全国冠军"
        default: return "业余"
        }
    }
    
    /// 获取技能等级的完整显示文本（图标 + 名称）
    static func skillLevelDisplayText(for level: Int) -> String {
        "\(skillLevelIcon(for: level)) \(skillLevelName(for: level))"
    }
    
    /// 当前用户的显示等级文本
    var displayLevelText: String {
        User.skillLevelDisplayText(for: displayLevel)
    }
    
    /// 当前用户的自报等级文本
    var selfReportedLevelText: String {
        User.skillLevelDisplayText(for: selfReportedLevel)
    }
}
