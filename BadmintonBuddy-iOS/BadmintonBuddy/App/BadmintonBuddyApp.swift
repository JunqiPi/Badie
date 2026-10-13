import SwiftUI

@main
@MainActor
struct BadmintonBuddyApp: App {
    @StateObject private var appState: AppState
    @StateObject private var router: Router
    @StateObject private var locationManager: LocationManager
    @StateObject private var matchManager: MatchManager
    @StateObject private var friendManager: FriendManager
    @StateObject private var messageManager: MessageManager
    @StateObject private var roomManager: RoomManager
    @StateObject private var surveyManager: SurveyManager
    @StateObject private var inboxManager: InboxManager

    init() {
        let environment = AppEnvironment.makeForLaunch()
        _appState = StateObject(wrappedValue: environment.appState)
        _router = StateObject(wrappedValue: environment.router)
        _locationManager = StateObject(wrappedValue: environment.locationManager)
        _matchManager = StateObject(wrappedValue: environment.matchManager)
        _friendManager = StateObject(wrappedValue: environment.friendManager)
        _messageManager = StateObject(wrappedValue: environment.messageManager)
        _roomManager = StateObject(wrappedValue: environment.roomManager)
        _surveyManager = StateObject(wrappedValue: environment.surveyManager)
        _inboxManager = StateObject(wrappedValue: environment.inboxManager)
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(router)
                .environmentObject(locationManager)
                .environmentObject(matchManager)
                .environmentObject(friendManager)
                .environmentObject(messageManager)
                .environmentObject(roomManager)
                .environmentObject(surveyManager)
                .environmentObject(inboxManager)
        }
    }
}
