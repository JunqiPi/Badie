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
