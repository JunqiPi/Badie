#if DEBUG
import SwiftUI

/// 仅 DEBUG：通过启动参数 `-BBDemoScreen <name>` 直接进入指定页面，
/// 用于 CI 截图与设计走查（数据存放在临时目录，不影响真实数据）。
@MainActor
enum DemoLauncher {
    static func makeEnvironment(screen: String) -> AppEnvironment {
        let backend = MockBackend(store: .demo)
        backend.resetAll()
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false

        let environment: AppEnvironment
        if screen == "welcome" || screen == "login" {
            environment = AppEnvironment(backend: backend)
            environment.appState.onboardingInitialStep = screen == "login" ? .phone : .welcome
            environment.appState.skipsSplash = true
            return environment
        }

        backend.createAccount(
            phone: "13800001234",
            nickname: "阿杰",
            avatar: Avatar(symbol: "", paletteIndex: 4),
            level: 4,
            preferredMode: .doubles,
            recurringSlots: [RecurringTimeSlot(dayOfWeek: 4, startHour: 19, endHour: 21)],
            location: Coordinate.fallbackCenter
        )
        environment = AppEnvironment(backend: backend)
        environment.appState.skipsSplash = true
        environment.locationManager.usesOnlyCuratedCourts = true
        environment.matchManager.minimumSearchDuration = 0
        let upcoming = seedUpcomingGame(backend)
        environment.matchManager.reloadGames()
        environment.matchManager.prepareDraft(
            user: backend.currentUser,
            nearbyCourts: BadmintonCourt.curatedBeijing,
            recurring: backend.recurringSlots(),
            favorites: []
        )

        let router = environment.router
        switch screen {
        case "matchSetup":
            router.isMatchSetupPresented = true
        case "courts":
            router.show(.courts, in: .home)
        case "matching":
            environment.matchManager.minimumSearchDuration = 600
            startSearch(environment)
        case "matchFound":
            environment.matchManager.draft.skillTolerance = 2
            startSearch(environment)
        case "ticket":
            router.show(.game(id: upcoming.id), in: .games)
        case "games":
            router.selectedTab = .games
        case "messages":
            router.selectedTab = .messages
        case "chat":
            router.show(.chat(userId: "bot-0"), in: .messages)
        case "friends":
            router.show(.friends, in: .profile)
        case "room":
            if let room = seedRoom(backend) {
                environment.roomManager.reload()
                router.show(.room(id: room.id), in: .games)
            }
        case "joinRoom":
            router.show(.joinRoom(code: nil), in: .games)
        case "survey":
            if let pending = backend.pendingSurveys().first {
                router.show(.survey(pendingId: pending.id), in: .games)
            }
        case "profile":
            router.selectedTab = .profile
        case "editProfile":
            router.show(.editProfile, in: .profile)
        case "settings":
            router.show(.settings, in: .profile)
        case "notifications":
            router.show(.notifications, in: .home)
        case "publicGames":
            router.show(.publicGames, in: .home)
        default:
            break
        }
        return environment
    }

    private static func startSearch(_ environment: AppEnvironment) {
        guard let user = environment.backend.currentUser else { return }
        environment.matchManager.startSearch(
            user: user,
            location: Coordinate.fallbackCenter,
            courts: BadmintonCourt.curatedBeijing,
            radiusKm: UserPreferences.defaultTravelRadius
        )
    }

    /// 今晚的一场双打（用于球局详情截图）
    private static func seedUpcomingGame(_ backend: MockBackend) -> Game {
        let me = backend.currentUserId ?? ""
        let calendar = Calendar.current
        let start = Date().addingTimeInterval(2 * 3600 + 15 * 60).roundedUp(toMinutes: 30)
        let slot = TimeSlot(date: calendar.startOfDay(for: start), startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let court = BadmintonCourt.curatedBeijing[0]
        let players = [me, "bot-0", "bot-4", "bot-8"]
        let game = Game(
            id: "demo-upcoming", mode: .doubles, court: court, slot: slot,
            playerIds: players, teams: [[me, "bot-4"], ["bot-0", "bot-8"]], hostId: me,
            origin: .quickMatch, status: .confirmed, createdAt: Date(),
            checkIns: [:], paidPlayerIds: [me, "bot-0"],
            cost: CostSplit.estimate(court: court, slot: slot, mode: .doubles),
            result: nil, cancelledBy: nil, cancelledLate: false, reminderEnabled: true
        )
        backend.db.games[game.id] = game
        return game
    }

    /// 私密房间：我 + 2 位好友，还差 1 人
    private static func seedRoom(_ backend: MockBackend) -> Room? {
        guard let me = backend.currentUser else { return nil }
        let slot = TimeSlot.on(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(), startHour: 19, endHour: 21)
        let room = Room(
            id: "demo-room", code: "BX7K2M", ownerId: me.id, mode: .doubles, visibility: .privateRoom,
            participants: [RoomParticipant(user: me)] + ["bot-0", "bot-1"].compactMap { backend.user(id: $0) }.map { RoomParticipant(user: $0) },
            invitedUserIds: ["bot-3"], waitlist: [],
            court: BadmintonCourt.curatedBeijing[1], slot: slot, levelRange: 3...7, tags: [.casual],
            note: "老地方，打完一起吃饭", createdAt: Date(), lastActivityAt: Date(), status: .open
        )
        backend.db.rooms[room.id] = room
        return room
    }
}
#endif
