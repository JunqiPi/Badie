import SwiftUI

/// 下拉刷新：不管在哪一页，都把该刷新的全部刷新一遍（我的请求和球局、好友和消息、球群、开放的局、通知、日期上的人数、附近球馆）
struct RefreshEverything: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var matchManager: MatchManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var inboxManager: InboxManager
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var locationManager: LocationManager
    /// 这一页自己还要多刷的东西
    var extra: (() async -> Void)?

    func body(content: Content) -> some View {
        content.refreshable {
            await appState.backend.refreshEverything()
            locationManager.refreshCourts()
            matchManager.reloadTickets()
            matchManager.reloadGames()
            friendManager.reload()
            await friendManager.refreshRegulars()
            await messageManager.refresh()
            roomManager.reload()
            surveyManager.refresh()
            inboxManager.reload()
            groupManager.reload()
            await extra?()
        }
    }
}

extension View {
    /// 页面里的列表下拉时刷新全部
    func refreshesEverything(_ extra: (() async -> Void)? = nil) -> some View {
        modifier(RefreshEverything(extra: extra))
    }
}
