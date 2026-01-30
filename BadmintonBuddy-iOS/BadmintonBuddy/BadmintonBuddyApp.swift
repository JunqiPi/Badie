import SwiftUI
import CoreLocation

@main
struct BadmintonBuddyApp: App {
    @StateObject private var appState = AppState()
    
    // MARK: - Feature Managers (功能管理器)
    @StateObject private var locationManager = LocationManager()
    @StateObject private var friendManager = FriendManager()
    @StateObject private var messageManager = MessageManager()
    @StateObject private var roomManager = RoomManager()
    @StateObject private var surveyManager = SurveyManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(locationManager)
                .environmentObject(friendManager)
                .environmentObject(messageManager)
                .environmentObject(roomManager)
                .environmentObject(surveyManager)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - App State (全局状态管理)
class AppState: ObservableObject {
    @Published var currentScreen: AppScreen = .splash
    @Published var currentUser: User?
    @Published var selectedMode: GameMode?
    @Published var matchedOpponent: User?
    @Published var isMatching = false
    
    // MARK: - 球馆选择状态
    
    /// 已选择的球馆ID集合
    /// - Requirements: 5.2, 5.4
    @Published var selectedCourtIds: Set<String> = []
    
    /// 匹配成功后的球馆
    /// - Requirements: 5.4
    @Published var matchedCourt: BadmintonCourt?
    
    /// 最多可选择的球馆数量
    /// - Requirements: 5.2
    static let maxSelectedCourts = 3
    
    // MARK: - 球馆选择方法
    
    /// 切换球馆选择状态
    /// - Parameter courtId: 球馆ID
    /// - Returns: 操作是否成功（如果已达到最大选择数量且尝试添加新球馆，则返回 false）
    /// - Requirements: 5.1, 5.3
    @discardableResult
    func toggleCourtSelection(_ courtId: String) -> Bool {
        if selectedCourtIds.contains(courtId) {
            // 如果已选择，则取消选择
            selectedCourtIds.remove(courtId)
            return true
        } else if selectedCourtIds.count < Self.maxSelectedCourts {
            // 如果未选择且未达到上限，则添加选择
            selectedCourtIds.insert(courtId)
            return true
        }
        // 已达到最大选择数量，无法添加更多
        return false
    }
    
    /// 清除所有球馆选择
    func clearCourtSelection() {
        selectedCourtIds.removeAll()
    }
    
    // MARK: - 匹配状态计算属性
    
    /// 检查是否可以开始匹配
    /// - 需要选择游戏模式且至少选择一个球馆
    /// - Requirements: 5.5
    var canStartMatching: Bool {
        selectedMode != nil && !selectedCourtIds.isEmpty
    }
    
    /// 用户登录（使用旧版 SkillLevel 枚举，向后兼容）
    @available(*, deprecated, message: "使用 login(nickname:phone:selfReportedLevel:) 替代")
    func login(nickname: String, phone: String, level: SkillLevel) {
        login(nickname: nickname, phone: phone, selfReportedLevel: level.toNineLevel)
    }
    
    /// 用户登录（使用新的9级技能系统）
    /// - Parameters:
    ///   - nickname: 用户昵称
    ///   - phone: 手机号
    ///   - selfReportedLevel: 自报技能等级 (1-7，8-9需要验证)
    func login(nickname: String, phone: String, selfReportedLevel: Int) {
        // 验证等级范围（1-7可自选，8-9需要验证）
        let validLevel = min(max(selfReportedLevel, 1), User.maxSelfSelectableLevel)
        
        currentUser = User(
            id: UUID().uuidString,
            nickname: nickname,
            phone: phone,
            selfReportedLevel: validLevel,
            totalGames: 0,
            wins: 0
        )
        currentScreen = .home
    }
    
    func logout() {
        currentUser = nil
        selectedMode = nil
        matchedOpponent = nil
        currentScreen = .auth
    }
    
    func startMatching() {
        guard selectedMode != nil else { return }
        guard !selectedCourtIds.isEmpty else { return }
        
        isMatching = true
        currentScreen = .matching
        
        // 模拟匹配 2-4 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2...4)) { [weak self] in
            guard self?.isMatching == true else { return }
            self?.matchSuccess()
        }
    }
    
    func cancelMatching() {
        isMatching = false
        currentScreen = .home
    }
    
    private func matchSuccess() {
        isMatching = false
        matchedOpponent = User.mockOpponents.randomElement()
        
        // 从已选择的球馆中随机选择一个作为匹配球馆
        // - Requirements: 6.1, 6.5
        if let selectedCourtId = selectedCourtIds.randomElement() {
            matchedCourt = BadmintonCourt.mockCourts.first { $0.id == selectedCourtId }
        }
        
        currentScreen = .matchSuccess
    }
    
    func confirmMatch() {
        currentScreen = .confirmed
    }
    
    func rematch() {
        matchedOpponent = nil
        currentScreen = .home
    }
}

enum AppScreen {
    case splash, auth, home, matching, matchSuccess, confirmed, profile
}
