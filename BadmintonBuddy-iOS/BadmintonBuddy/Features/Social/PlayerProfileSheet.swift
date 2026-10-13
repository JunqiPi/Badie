import SwiftUI

/// 球友资料卡：等级、口碑、履约，以及加好友/私信/约球/屏蔽
struct PlayerProfileSheet: View {
    let userId: String
    var allowsInvite = true

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var messageManager: MessageManager
    @Environment(\.dismiss) private var dismiss

    @State private var showReport = false

    private var user: User? { friendManager.user(id: userId) }

    var body: some View {
        ScrollView {
            if let user {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    header(user)
                    statsRow(user)
                    reputationCard(user)
                    connectionCard(user)
                    if !user.bio.isEmpty {
                        Text("“\(user.bio)”")
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .card()
                    }
                    actions(user)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xl)
            } else {
                EmptyStateView(icon: "person.fill.questionmark", title: "找不到这位球友")
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showReport) {
            ReportSheet(userId: userId, nickname: user?.nickname ?? "TA")
        }
    }

    private func header(_ user: User) -> some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            AvatarView(user: user, size: 76)
                .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
            VStack(alignment: .leading, spacing: 6) {
                Text(user.nickname)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                FlowLayout(spacing: 6) {
                    LevelBadge(level: user.displayLevel)
                    if user.isReliable { ReliableBadge() }
                    if user.isNewPlayer { NewPlayerBadge() }
                    VerifiedBadge(status: user.verificationStatus)
                    if user.gender != .unspecified {
                        TagPill(text: user.gender.label, fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
                    }
                }
                if let distance = friendManager.distance(to: user.id) {
                    Text("距你 \(DistanceFormatter.string(km: distance)) · ID \(user.shortId)")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statsRow(_ user: User) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            StatTile(value: "\(user.totalGames)", label: "场次")
            StatTile(value: "\(Int(user.winRate.rounded()))%", label: "胜率")
        }
    }

    /// 别人只看到正面印象和“靠谱”徽章；评分数字只在内部用于匹配排序
    private func reputationCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("球友印象")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                if user.isReliable { ReliableBadge() }
            }
            PraiseTagsView(tags: user.reputation.publicTags, emptyText: "评价的球友还不到 5 位，暂不显示印象")
            Text(user.isNewPlayer
                 ? "评价不足 5 次，等级为自评 Lv.\(user.selfReportedLevel)，仅供参考"
                 : "等级由自评与球友评价综合得出")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
        .card()
    }

    /// 你们的交集：一起打过几场、共同球友（帮助判断“这个人靠不靠谱、是不是圈子里的人”）
    private func connectionCard(_ user: User) -> some View {
        let together = friendManager.gamesTogether(with: user.id)
        let mutual = friendManager.mutualFriends(with: user.id)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("你们的交集")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "sportscourt.fill", fill: AppTheme.Colors.lime, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(together.isEmpty ? "还没一起打过" : "一起打过 \(together.count) 场")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if let last = together.first {
                        Text("最近一次：\(DateText.relativeDay(last.slot.startTime)) · \(last.court.name)")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "person.2.fill", fill: AppTheme.Colors.lavender, size: 36)
                Text(mutual.isEmpty ? "没有共同球友" : "共同球友 \(mutual.count) 位")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer(minLength: 0)
                HStack(spacing: -8) {
                    ForEach(mutual.prefix(4)) { friend in
                        AvatarView(user: friend, size: 30)
                            .opensProfile(friend.id)
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func actions(_ user: User) -> some View {
        let isBlocked = messageManager.isBlocked(user.id)
        VStack(spacing: AppTheme.Spacing.sm) {
            if isBlocked {
                Button("解除屏蔽") {
                    messageManager.unblock(user.id)
                    friendManager.reload()
                }
                .buttonStyle(.brutalSecondary)
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        dismiss()
                        router.open(.chat(userId: user.id), in: .messages)
                    } label: {
                        Label("私信", systemImage: "bubble.left.fill")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                    if friendManager.isFriend(user.id) {
                        if allowsInvite {
                            Button {
                                dismiss()
                                router.open(.createRoom(nil, invitee: user.id), in: .games)
                            } label: {
                                Label("约 TA 打球", systemImage: "sportscourt.fill")
                            }
                            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .medium))
                        }
                    } else {
                        FriendActionButtonLarge(userId: user.id)
                    }
                }
            }
            HStack(spacing: AppTheme.Spacing.lg) {
                if friendManager.isFriend(user.id) {
                    Button("删除球友") {
                        Task {
                            try? await friendManager.remove(user.id)
                            appState.showToast("已删除")
                        }
                    }
                    .buttonStyle(TextActionStyle())
                }
                if !isBlocked {
                    Button("屏蔽") {
                        messageManager.block(user.id)
                        friendManager.reload()
                        appState.showToast("已屏蔽，对方不会收到通知")
                        dismiss()
                    }
                    .buttonStyle(TextActionStyle())
                }
                Button("举报") { showReport = true }
                    .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
            }
        }
    }
}

/// 资料卡里的大号加好友按钮
private struct FriendActionButtonLarge: View {
    let userId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager

    var body: some View {
        if friendManager.hasPendingRequest(to: userId) {
            Button("已申请，等待通过") {}
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                .disabled(true)
        } else if let incoming = friendManager.incomingRequest(from: userId) {
            Button("通过好友申请") {
                Task {
                    try? await friendManager.respond(incoming, accept: true)
                    appState.showToast("已添加为球友", style: .success)
                }
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .medium))
        } else {
            Button {
                Task {
                    do {
                        try await friendManager.sendRequest(to: userId)
                        appState.showToast("申请已发送", style: .success)
                    } catch {
                        appState.showError(error)
                    }
                }
            } label: {
                Label("加球友", systemImage: "person.badge.plus")
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .medium))
        }
    }
}

// MARK: - 通知中心

struct NotificationsView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var inboxManager: InboxManager
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var surveyManager: SurveyManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var matchManager: MatchManager

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "通知") {
                if inboxManager.unreadCount > 0 {
                    Button("全部已读") { inboxManager.markRead() }
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .frame(minHeight: 44)
                }
            }
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    if inboxManager.items.isEmpty {
                        EmptyStateView(icon: "bell.slash", title: "暂无通知", message: "好友申请、房间邀请、球局提醒都会出现在这里。")
                    }
                    ForEach(inboxManager.items) { item in
                        Button {
                            open(item)
                        } label: {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                IconTile(systemName: icon(for: item.kind), fill: tint(for: item.kind), size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(AppTheme.Typography.headline)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                        .multilineTextAlignment(.leading)
                                    Text(item.body)
                                        .font(AppTheme.Typography.footnote)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(DateText.compact(item.createdAt))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                                }
                                Spacer(minLength: 0)
                                if !item.isRead {
                                    Circle()
                                        .fill(AppTheme.Colors.dangerFill)
                                        .frame(width: 9, height: 9)
                                        .padding(.top, 6)
                                        .accessibilityLabel("未读")
                                }
                            }
                            .padding(AppTheme.Spacing.md)
                            .sticker(item.isRead ? AppTheme.Colors.surfaceMuted : AppTheme.Colors.surface,
                                     radius: AppTheme.Radius.md,
                                     shadow: item.isRead ? .zero : CGSize(width: 0, height: 3))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }

    private func open(_ item: InboxItem) {
        inboxManager.markRead(item)
        switch item.kind {
        case .friendRequest, .friendAccepted:
            if let id = item.relatedId { appState.showPlayer(id) }
        case .roomInvite, .roomJoined, .waitlistPromoted:
            if let code = item.relatedId {
                if let room = roomManager.myRooms.first(where: { $0.code == code }) {
                    router.open(.room(id: room.id))
                } else {
                    router.open(.joinRoom(code: code))
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
        case .kicked, .roomClosed, .system:
            break
        }
    }

    private func icon(for kind: InboxItem.Kind) -> String {
        switch kind {
        case .friendRequest, .friendAccepted: return "person.badge.plus"
        case .roomInvite, .roomJoined, .waitlistPromoted: return "ticket.fill"
        case .kicked, .roomClosed: return "door.left.hand.open"
        case .surveyDue, .reviewReceived: return "star.fill"
        case .gameConfirmed, .gameReminder: return "sportscourt.fill"
        case .matchOffer: return "bolt.fill"
        case .matchUpdate: return "arrow.triangle.2.circlepath"
        case .gameCancelled: return "xmark.circle.fill"
        case .system: return "megaphone.fill"
        }
    }

    private func tint(for kind: InboxItem.Kind) -> Color {
        switch kind {
        case .friendRequest, .friendAccepted: return AppTheme.Colors.lavender
        case .roomInvite, .roomJoined, .waitlistPromoted: return AppTheme.Colors.peach
        case .kicked, .roomClosed, .gameCancelled: return AppTheme.Colors.surfaceMuted
        case .surveyDue, .reviewReceived: return AppTheme.Colors.pink
        case .gameConfirmed, .gameReminder, .matchOffer: return AppTheme.Colors.lime
        case .matchUpdate: return AppTheme.Colors.butter
        case .system: return AppTheme.Colors.sky
        }
    }
}
