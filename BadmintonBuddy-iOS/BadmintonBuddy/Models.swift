import Foundation

// MARK: - 用户模型
struct User: Identifiable, Equatable {
    let id: String
    var nickname: String
    var phone: String
    var level: SkillLevel
    var totalGames: Int
    var wins: Int
    var joinDate: Date = Date()
    
    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames) * 100
    }
    
    static let mockOpponents: [User] = [
        User(id: "1", nickname: "小明", phone: "138****1234", level: .advanced, totalGames: 45, wins: 32),
        User(id: "2", nickname: "阿杰", phone: "139****5678", level: .intermediate, totalGames: 28, wins: 18),
        User(id: "3", nickname: "小红", phone: "137****9012", level: .pro, totalGames: 120, wins: 98),
        User(id: "4", nickname: "大伟", phone: "136****3456", level: .beginner, totalGames: 12, wins: 5),
        User(id: "5", nickname: "小李", phone: "135****7890", level: .intermediate, totalGames: 35, wins: 22)
    ]
}

// MARK: - 技能等级
enum SkillLevel: String, CaseIterable, Identifiable {
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
}

// MARK: - 游戏模式
enum GameMode: String, CaseIterable, Identifiable {
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
}

// MARK: - 匹配结果
struct MatchResult {
    let opponent: User
    let venue: String
    let distance: Double
    let suggestedTime: Date
    
    static let mock = MatchResult(
        opponent: User.mockOpponents[0],
        venue: "朝阳区体育中心羽毛球馆",
        distance: 1.2,
        suggestedTime: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
    )
}
