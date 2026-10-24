import SwiftUI

// MARK: - 通知：图标、颜色，点开去哪

extension InboxItem.Kind {
    var icon: String {
        switch self {
        case .friendRequest, .friendAccepted: return "person.badge.plus"
        case .roomInvite, .roomJoined, .waitlistPromoted: return "ticket.fill"
        case .kicked, .roomClosed: return "door.left.hand.open"
        case .surveyDue, .reviewReceived: return "star.fill"
        case .gameConfirmed, .gameReminder: return "sportscourt.fill"
        case .matchOffer: return "bolt.fill"
        case .matchUpdate: return "arrow.triangle.2.circlepath"
        case .messageRequest: return "envelope.badge.fill"
        case .groupUpdate: return "person.3.fill"
        case .rematch: return "arrow.uturn.left.circle.fill"
        case .gameCancelled: return "xmark.circle.fill"
        case .system: return "megaphone.fill"
        case .challenge: return "flag.2.crossed.fill"
        case .resultUpdate: return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .friendRequest, .friendAccepted: return AppTheme.Colors.lavender
        case .roomInvite, .roomJoined, .waitlistPromoted: return AppTheme.Colors.peach
        case .kicked, .roomClosed, .gameCancelled: return AppTheme.Colors.surfaceMuted
        case .surveyDue, .reviewReceived: return AppTheme.Colors.pink
        case .gameConfirmed, .gameReminder, .matchOffer: return AppTheme.Colors.lime
        case .matchUpdate, .messageRequest: return AppTheme.Colors.butter
        case .groupUpdate: return AppTheme.Colors.lavender
        case .rematch: return AppTheme.Colors.mint
        case .system: return AppTheme.Colors.sky
        case .challenge: return AppTheme.Colors.peach
        case .resultUpdate: return AppTheme.Colors.mint
        }
    }
}

extension InboxItem.Kind {
    /// 和约球有关、要你处理或知道的：首页最上面列出来
    var isActionable: Bool {
        switch self {
        case .gameCancelled, .kicked, .roomClosed, .challenge, .roomInvite, .roomJoined, .waitlistPromoted,
             .matchOffer, .gameConfirmed, .friendRequest, .messageRequest:
            return true
        default:
            return false
        }
    }

    /// 球局没了：打开 App 时直接弹窗告诉，点“知道了”才算看过
    var isUrgent: Bool {
        self == .gameCancelled || self == .kicked || self == .roomClosed
    }
}

/// 点开一条通知：标为已读，再打开对应的页面（通知中心、首页动态和重要通知弹窗共用）
@MainActor
struct InboxNavigator {
    let router: Router
    let inboxManager: InboxManager
    let roomManager: RoomManager
    let surveyManager: SurveyManager
    let appState: AppState
    let matchManager: MatchManager

    func open(_ item: InboxItem) {
        inboxManager.markRead(item)
        switch item.kind {
        case .friendRequest, .friendAccepted:
            if let id = item.relatedId { appState.showPlayer(id) }
        case .roomInvite, .roomJoined, .waitlistPromoted:
            // 模拟后端给的是房间码，正式后端给的是房间 ID
            if let key = item.relatedId {
                if let room = roomManager.myRooms.first(where: { $0.code == key || $0.id == key }) {
                    router.open(.room(id: room.id))
                } else if appState.isRemote {
                    router.open(.room(id: key))
                } else {
                    router.open(.joinRoom(code: key))
                }
            }
        case .surveyDue:
            if let id = item.relatedId, surveyManager.survey(id: id) != nil {
                router.open(.survey(pendingId: id))
            } else {
                router.open(.surveys)
            }
        case .gameConfirmed, .gameCancelled, .gameReminder:
            if let id = item.relatedId { router.open(.game(id: id)) }
        case .reviewReceived:
            router.select(.profile)
        case .matchOffer, .matchUpdate:
            if let id = item.relatedId { matchManager.openTicket(id) }
        case .messageRequest:
            if let id = item.relatedId { router.open(.chat(userId: id), in: .messages) }
        case .groupUpdate:
            if let id = item.relatedId { router.open(.group(id: id)) }
        case .rematch:
            if let id = item.relatedId { appState.showPlayer(id) }
        case .challenge:
            // 接受后 relatedId 是球局 ID，否则是挑战 ID
            if let id = item.relatedId, appState.backend.db.games[id] != nil {
                router.open(.game(id: id))
            } else {
                router.open(.challenges)
            }
        case .resultUpdate:
            if let id = item.relatedId { router.open(.game(id: id)) }
        case .kicked, .roomClosed, .system:
            break
        }
    }
}

/// 球局没了（取消、被移出、关闭）：打开 App 时直接弹出，点“知道了”才算看过
struct UrgentNoticeSheet: View {
    let items: [InboxItem]
    let onOpen: (InboxItem) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(items.count == 1 ? items[0].title : String(localized: "\(items.count) 场球局有变化"))
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(items) { item in
                        Button { onOpen(item) } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                IconTile(systemName: item.kind.icon, fill: item.kind.tint, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    if items.count > 1 {
                                        Text(item.title)
                                            .font(AppTheme.Typography.headline)
                                            .foregroundStyle(AppTheme.Colors.ink)
                                    }
                                    Text(item.body)
                                        .font(AppTheme.Typography.subheadline)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                            }
                            .padding(AppTheme.Spacing.lg)
                            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            }
            Button("知道了", action: onDone)
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
