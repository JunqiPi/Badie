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
        if ["welcome", "login", "levelQuiz", "levelResult"].contains(screen) {
            environment = AppEnvironment(backend: backend)
            switch screen {
            case "login": environment.appState.onboardingInitialStep = .phone
            case "levelQuiz": environment.appState.onboardingInitialStep = .level
            case "levelResult":
                environment.appState.onboardingInitialStep = .level
                environment.appState.onboardingDemoAnswers = SkillAssessment.demoAnswers
            default: environment.appState.onboardingInitialStep = .welcome
            }
            environment.appState.skipsSplash = true
            return environment
        }

        // 做过定级、存着答案（重炮手、4 级）：“我的”有“分享等级卡片”，卡片上有打法；四个月前测的，可以重测
        let answers = SkillAssessment.levelCardDemoAnswers
        let assessment = SkillAssessment.evaluate(answers).map {
            SkillAssessmentSummary(level: $0.level, needsCalibration: $0.needsCalibration, isReturning: $0.isReturning,
                                   assessedAt: Date().addingTimeInterval(-120 * 86400), rating: $0.tier.rating, answers: answers)
        }
        backend.createAccount(
            phone: "+16265550123",
            nickname: MockBackend.demoNickname,
            gender: .male,
            avatar: Avatar(symbol: "", paletteIndex: 4),
            level: 4,
            preferredMode: .doubles,
            recurringSlots: [RecurringTimeSlot(dayOfWeek: 4, startHour: 19, endHour: 21)],
            location: Coordinate.fallbackCenter,
            assessment: assessment
        )
        seedPlayerPhotos(backend)
        // “我的”最上面是我的卡片（有照片，头像还没传，下面显示“资料 3/4”）；编辑资料里卡片照片和头像都有
        if screen == "profile" || screen == "editProfile" {
            seedMyPhotos(backend, avatar: screen == "editProfile")
        }
        environment = AppEnvironment(backend: backend)
        environment.appState.skipsSplash = true
        environment.locationManager.allowsMapSearch = false
        environment.matchManager.minimumSearchDuration = 0
        // 常去球馆：LABC
        environment.locationManager.refreshCourts()
        if !environment.locationManager.isFavorite(DemoVenue.labc) {
            environment.locationManager.toggleFavorite(DemoVenue.labc)
        }
        let upcoming = seedUpcomingGame(backend)
        environment.matchManager.reloadGames()
        environment.matchManager.prepareDraft(
            user: backend.currentUser,
            nearbyCourts: environment.locationManager.nearbyCourts,
            recurring: backend.recurringSlots(),
            favorites: backend.favoriteCourtIds()
        )

        let router = environment.router
        switch screen {
        case "createMenu":
            router.isCreateMenuPresented = true
        case "matchSetup":
            router.isMatchSetupPresented = true
        case "matchSetupVenues":
            router.matchSetupAnchor = MatchSetupView.venuesAnchor
            router.isMatchSetupPresented = true
        case "courts":
            router.show(.courts, in: .home)
        case "matching":
            environment.matchManager.minimumSearchDuration = 600
            startSearch(environment)
        case "matchFound":
            environment.matchManager.draft.skillTolerance = 2
            startSearch(environment)
        case "ticketWaiting":
            if let ticket = seedDemoTicket(environment, mode: .singles, tolerance: 1, autoAccept: false, state: .waiting) {
                environment.matchManager.openTicket(ticket.id)
            }
        case "offerWaiting":
            if let ticket = seedDemoTicket(environment, mode: .doubles, tolerance: MatchRequest.anySkill, autoAccept: true,
                                           state: .othersConfirming) {
                environment.matchManager.openTicket(ticket.id)
            }
        case "levelGuide":
            router.show(.levelGuide, in: .profile)
        case "levelCard":
            // 等级卡片：重炮手、4 级（上面建账号时已存答案），常去 LABC、周三晚上有空
            environment.appState.opensLevelCardDemo = true
            router.show(.levelGuide, in: .profile)
        case "levelGuideElite":
            // 对照表滚到 6、7 级：俱乐部高手 → 州级
            environment.appState.guideScrollLevel = 6
            router.show(.levelGuide, in: .profile)
        case "verification":
            // 认证申请：BWF 球员页（演示用的链接，不对应真实球员）
            environment.appState.verificationDemo = (
                kind: .bwf, tier: SkillTier(level: 9, modifier: .minus),
                link: "bwfbadminton.com/player/00000/demo-player", name: "Jie Wang",
                note: MockBackend.demoText("2025 Pan Am 青年锦标赛男双八强，2026 年打过两站 Future Series",
                                           "Men's doubles quarterfinal at the 2025 Pan Am Junior Championships; two Future Series events in 2026")
            )
            router.show(.verification, in: .profile)
        case "groups":
            router.show(.groups, in: .games)
        case "groupDetail":
            if let group = backend.myGroups().first {
                router.show(.group(id: group.id), in: .games)
            }
        case "groupChat":
            if let group = backend.myGroups().first {
                let thread = backend.ensureGroupThread(for: group)
                environment.messageManager.reload()
                router.show(.groupChat(threadId: thread.id), in: .messages)
            }
        case "home", "nearbyCards":
            // 发现页（打开 App 就是这页）：附近的人的大卡片（常去的球馆、常有空的时间）；上面一排圆头像是这叠卡里的人。
            // 最前面两位示例球友有照片（见 seedPlayerPhotos），其余是颜色 + 球场线
            router.selectedTab = .home
            environment.appState.discoverDay = nil
        case "dayCards":
            // 发现页选明天：这天附近在找人的球友卡片
            router.selectedTab = .home
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            environment.matchManager.draft.day = tomorrow
            environment.appState.discoverDay = tomorrow
            // 卡片用柠檬色（商店截图里和标题的色块同色）
            for id in backend.db.bots.keys {
                backend.db.users[id]?.avatar.cardColor = .lime
            }
        case "nearbyInvite":
            // 点了卡片上的空闲时间：约 TA 的半屏（项目、日期、几点到几点、球馆），时间已经填好
            router.selectedTab = .home
            DayCandidatesView.demoOpensInvite = true
        case "inviteAnswer":
            // 收到附近的人的邀请：不了 / 换个时间 / 好
            router.selectedTab = .home
            environment.appState.showsInvites = true
        case "playerProfile":
            // 昨天一起打过单打的球友：资料页显示“你们的交集”
            router.selectedTab = .home
            environment.appState.presentedPlayer = PlayerSheetItem(id: "bot-2")
        case "playerNoShow":
            // 商店截图：资料页上能看到近 180 天的爽约次数（有爽约就没有“靠谱”徽章）
            router.selectedTab = .home
            backend.db.users["bot-2"]?.attendance.noShows = 1
            backend.remoteNoShows["bot-2"] = (recent: 1, suspendedUntil: nil)
            environment.appState.presentedPlayer = PlayerSheetItem(id: "bot-2")
        case "homeTicket":
            // 球局页最上面的“约球请求”卡片：找到了，等我确认
            _ = seedDemoTicket(environment, mode: .singles, tolerance: 2, autoAccept: false, state: .offered)
            environment.matchManager.reloadTickets()
            router.selectedTab = .games
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
        case "leaderboard":
            router.show(.leaderboard, in: .home)
        case "venueLeaderboard":
            if let venue = backend.nearestVenues(to: backend.currentUser?.location ?? Coordinate.fallbackCenter, count: 1).first {
                router.show(.venueLeaderboard(venueId: venue.id), in: .home)
            }
        case "challenges":
            router.show(.challenges, in: .games)
        case "gameResult":
            // 刚打完、等对方确认赛果的一场
            if let game = backend.db.games.values.first(where: { $0.status == .completed }) {
                router.show(.game(id: game.id), in: .games)
            }
        case "editProfile":
            router.show(.editProfile, in: .profile)
        case "settings":
            router.show(.settings, in: .profile)
        case "notifications":
            router.show(.notifications, in: .home)
        case "publicGames":
            router.show(.publicGames, in: .home)
        case "venuePicker":
            router.show(.matchVenues(query: nil), in: .home)
        case "venueSearch":
            router.show(.matchVenues(query: "labc"), in: .home)
        case "venueDetail":
            router.show(.venue(id: DemoVenue.eliteRally), in: .home)
        case "addVenue":
            // 演示查重：在 LABC 门口添加“LA Badminton Club”，会提示“是同一个吗？”
            if let labc = backend.venue(id: DemoVenue.labc) {
                router.show(.addVenue(prefill: VenuePrefill(name: "LA Badminton Club", coordinate: labc.location,
                                                            address: labc.postalAddress, checksDuplicates: true)),
                            in: .home)
            }
        default:
            break
        }
        return environment
    }

    /// 商店截图：两位示例球友用真人照片（卡片背景 + 圆头像，图片在 Assets 里），发现页排在最前面，女生在前
    private static let photoPlayers: [(id: String, photo: String)] = [("bot-15", "DemoPlayerF1"), ("bot-9", "DemoPlayerM1")]

    private static func seedPlayerPhotos(_ backend: MockBackend) {
        for player in photoPlayers {
            guard var user = backend.db.users[player.id],
                  let card = UIImage(named: player.photo)?.jpegData(compressionQuality: 0.9),
                  let avatar = UIImage(named: player.photo + "Avatar")?.jpegData(compressionQuality: 0.9) else { continue }
            backend.db.avatarPhotos[player.id] = avatar
            backend.db.avatarPhotos[AvatarPhotos.cardKey(player.id)] = card
            user.avatar.photoVersion = 1
            user.avatar.cardPhotoVersion = 1
            backend.db.users[player.id] = user
            // 也常去 LABC（和我一样）：一定在附近的人里
            let venues = backend.db.favoriteCourtIds[player.id] ?? []
            if !venues.contains(DemoVenue.labc) {
                backend.db.favoriteCourtIds[player.id] = [DemoVenue.labc] + Array(venues.prefix(1))
            }
        }
        backend.demoFeaturedIds = photoPlayers.map { $0.id }
    }

    /// 截图里我的卡片照片和头像（和示例球友用同一组图）
    private static func seedMyPhotos(_ backend: MockBackend, avatar: Bool) {
        guard let me = backend.currentUserId, var user = backend.db.users[me],
              let card = UIImage(named: "DemoPlayerM1")?.jpegData(compressionQuality: 0.9) else { return }
        backend.db.avatarPhotos[AvatarPhotos.cardKey(me)] = card
        user.avatar.cardPhotoVersion = 2
        if avatar, let photo = UIImage(named: "DemoPlayerM1Avatar")?.jpegData(compressionQuality: 0.9) {
            backend.db.avatarPhotos[me] = photo
            user.avatar.photoVersion = 2
        }
        backend.db.users[me] = user
    }

    private static func startSearch(_ environment: AppEnvironment) {
        guard let user = environment.backend.currentUser else { return }
        // 固定为下一个工作日晚上（普通局），截图不受 CI 运行时刻影响
        if let slot = nextWeekdayEvening() { environment.matchManager.draft.apply(slot) }
        environment.matchManager.startSearch(
            user: user,
            location: Coordinate.fallbackCenter,
            courts: environment.locationManager.courts(ids: environment.matchManager.draft.courtIds),
            radiusKm: UserPreferences.defaultTravelRadius
        )
    }

    /// 明天起的第一个周一至周四晚上 19:00–21:00
    private static func nextWeekdayEvening() -> TimeSlot? {
        let calendar = Calendar.current
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            if (2...5).contains(calendar.component(.weekday, from: day)) {
                return TimeSlot.on(day, startHour: 19, endHour: 21)
            }
        }
        return nil
    }

    private enum DemoTicketState { case waiting, offered, othersConfirming }

    /// 直接写入一个约球请求（同步，便于截图）
    private static func seedDemoTicket(_ environment: AppEnvironment, mode: GameMode, tolerance: Int, autoAccept: Bool,
                                       state: DemoTicketState) -> MatchTicket? {
        let backend = environment.backend
        guard let me = backend.currentUser, let slot = nextWeekdayEvening() else { return nil }
        let now = Date()
        var ticket = MatchTicket(
            id: "demo-ticket", userId: me.id, mode: mode, slot: slot,
            courtIds: environment.matchManager.draft.courtIds, skillTolerance: tolerance,
            radiusKm: UserPreferences.defaultTravelRadius, origin: Coordinate.fallbackCenter,
            autoAccept: autoAccept, isLastMinute: false, status: .searching, createdAt: now,
            deadline: MatchTiming.lock(start: slot.startTime, lastMinute: false),
            hasPriority: false, excludedUserIds: []
        )
        if state == .waiting {
            // 演示“还在找”：当下能匹配的人都已排除
            let request = backend.matchRequest(for: ticket, owner: me)
            ticket.excludedUserIds = MatchingService.candidates(for: request, pool: backend.matchmakingPool(for: ticket, now: now))
                .map(\.user.id)
        }
        backend.db.tickets[ticket.id] = ticket
        guard state != .waiting, let offer = backend.runMatchmaking(ticketId: ticket.id, now: now) else {
            return backend.ticket(id: ticket.id)
        }
        if state == .othersConfirming, var current = backend.db.offers[offer.id] {
            // 一位已确认、一位这次来不了（显示“补位中”）、其余还没回复
            let others = current.seats.indices.filter { current.seats[$0].ticketId == nil }
            if let first = others.first {
                current.seats[first].response = .accepted
                current.seats[first].respondedAt = now
            }
            if others.count > 1 { current.seats[others[1]].response = .declined }
            backend.db.offers[offer.id] = current
        }
        return backend.ticket(id: ticket.id)
    }

    /// 今晚的一场双打（用于球局详情截图）
    private static func seedUpcomingGame(_ backend: MockBackend) -> Game {
        let me = backend.currentUserId ?? ""
        let calendar = Calendar.current
        // 晚上 19:30 开打：今天来得及（至少还有 1 小时）就今天，否则明天
        let now = Date()
        let todayEvening = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: now) ?? now
        let start = todayEvening > now.addingTimeInterval(3600)
            ? todayEvening
            : (calendar.date(byAdding: .day, value: 1, to: todayEvening) ?? todayEvening)
        let slot = TimeSlot(date: calendar.startOfDay(for: start), startTime: start, endTime: start.addingTimeInterval(2 * 3600))
        let court = backend.venue(id: DemoVenue.labc) ?? BadmintonCourt.mock
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
        // 球局群聊：成局后所有人在这里沟通
        let thread = backend.ensureGameThread(for: game)
        backend.appendMessage(Message(threadId: thread.id, senderId: "bot-0",
                                      content: MockBackend.demoText("我今晚 7 点就到，先去占场～", "I'll be there at 7 to grab a court"),
                                      sentAt: Date().addingTimeInterval(-40 * 60), deliveredAt: Date().addingTimeInterval(-40 * 60)),
                              participants: thread.participantIds, countsAsUnread: true)
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
            court: backend.venue(id: DemoVenue.eliteRally), slot: slot, levelRange: 3...7, tags: [.casual],
            note: MockBackend.demoText("老地方，打完一起吃饭", "Usual spot, food after"), createdAt: Date(), lastActivityAt: Date(), status: .open
        )
        backend.db.rooms[room.id] = room
        return room
    }
}

/// 演示用的两家洛杉矶球馆（见 Resources/curated-US.json）
enum DemoVenue {
    static let labc = "v-us-ca-labc"
    static let eliteRally = "v-us-ca-elite-rally"
}
#endif
