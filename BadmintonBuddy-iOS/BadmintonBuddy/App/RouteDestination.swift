import SwiftUI

/// 导航目的地映射
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .game(let id):
            GameDetailView(gameId: id)
        case .room(let id):
            RoomLobbyView(roomId: id)
        case .createRoom(let mode, let invitee):
            CreateRoomView(initialMode: mode, inviteeId: invitee)
        case .joinRoom(let code):
            JoinRoomView(initialCode: code ?? "")
        case .publicGames:
            PublicGamesView()
        case .chat(let userId):
            ChatView(userId: userId)
        case .friends:
            FriendsView()
        case .addFriend:
            AddFriendView()
        case .surveys:
            SurveyListView()
        case .survey(let pendingId):
            SurveyFormView(pendingId: pendingId)
        case .editProfile:
            EditProfileView()
        case .settings:
            SettingsView()
        case .recurringSlots:
            RecurringSlotsView()
        case .blockedUsers:
            BlockedUsersView()
        case .notifications:
            NotificationsView()
        case .courts:
            CourtsView()
        case .gameHistory:
            GameHistoryView()
        }
    }
}
