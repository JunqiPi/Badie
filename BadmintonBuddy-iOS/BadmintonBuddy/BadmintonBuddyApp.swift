import SwiftUI

@main
struct BadmintonBuddyApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
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
    
    func login(nickname: String, phone: String, level: SkillLevel) {
        currentUser = User(
            id: UUID().uuidString,
            nickname: nickname,
            phone: phone,
            level: level,
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
