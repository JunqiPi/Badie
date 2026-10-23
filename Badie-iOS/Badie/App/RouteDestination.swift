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
        case .venue(let id):
            VenueDetailPage(venueId: id)
        case .matchVenues(let query):
            MatchVenuesPage(initialQuery: query ?? "")
        case .addVenue(let prefill):
            AddVenuePage(prefill: prefill)
        case .groupChat(let threadId):
            GroupChatView(threadId: threadId)
        case .group(let id):
            GroupDetailView(groupId: id)
        case .groups:
            GroupsView()
        case .createGroup(let venueId):
            CreateGroupView(initialVenueId: venueId)
        case .levelGuide:
            LevelGuidePage()
        case .verification:
            VerificationView()
        case .leaderboard:
            WeeklyLeaderboardView()
        case .venueLeaderboard(let venueId):
            WeeklyLeaderboardView(venueId: venueId)
        case .challenges:
            ChallengesView()
        }
    }
}

// MARK: - 球馆相关页面（导航栈版本）

struct VenueDetailPage: View {
    let venueId: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "球馆"))
            if let venue = appState.backend.venue(id: venueId) {
                CourtDetailSheet(court: venue, isSheet: false)
            } else {
                EmptyStateView(icon: "mappin.slash", title: String(localized: "没有找到这个球馆"))
                Spacer()
            }
        }
    }
}

struct LevelGuidePage: View {
    @EnvironmentObject private var appState: AppState

    private var guideScrollLevel: Int? {
        #if DEBUG
        return appState.guideScrollLevel
        #else
        return nil
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "等级"))
            SkillLevelGuideView(highlight: appState.currentUser?.displayTier, showsCloseButton: false,
                                scrollLevel: guideScrollLevel)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

struct MatchVenuesPage: View {
    var initialQuery = ""
    @EnvironmentObject private var matchManager: MatchManager

    var body: some View {
        VenuePickerView(mode: .multiple(max: MatchDraft.maxCourts), selection: $matchManager.draft.courtIds,
                        slot: matchManager.draft.slot, initialQuery: initialQuery)
    }
}

struct AddVenuePage: View {
    var prefill: VenuePrefill?
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var router: Router

    var body: some View {
        AddVenueView(initialName: prefill?.name ?? "",
                     initialCoordinate: prefill?.coordinate ?? locationManager.coordinate,
                     initialAddress: prefill?.address,
                     checksDuplicatesOnAppear: prefill?.checksDuplicates ?? false) { venue in
            router.pop()
            router.open(.venue(id: venue.id))
        }
    }
}
