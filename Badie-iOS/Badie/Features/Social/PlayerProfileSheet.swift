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
    @State private var showChallenge = false

    private var user: User? { friendManager.user(id: userId) }

    var body: some View {
        ScrollView {
            if let user {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    header(user)
                    statsRow(user)
                    winRateLine(user)
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
                EmptyStateView(icon: "person.fill.questionmark", title: String(localized: "找不到这位球友"))
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showReport) {
            ReportSheet(userId: userId, nickname: user?.nickname ?? String(localized: "TA"))
        }
        .sheet(isPresented: $showChallenge) {
            ChallengeComposer(targetId: userId)
                .presentationDragIndicator(.visible)
        }
    }

    private func header(_ user: User) -> some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            AvatarView(user: user, size: 76)
                .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
            VStack(alignment: .leading, spacing: 6) {
                NicknameText(user: user)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                FlowLayout(spacing: 6) {
                    LevelBadge(tier: user.displayTier)
                    if user.isReliable { ReliableBadge() }
                    if user.isNewPlayer { NewPlayerBadge() }
                    VerifiedBadge(status: user.verificationStatus)
                    // 男女等级分开算：标出这个等级是男子还是女子的
                    if let ladder = user.gender.ladderLabel {
                        TagPill(text: ladder, fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
                    }
                    let noShows = friendManager.noShows(of: user.id)
                    if noShows.recent > 0 {
                        TagPill(text: String(localized: "近 180 天爽约 \(noShows.recent) 次"), fill: AppTheme.Colors.pink)
                    }
                    if let until = noShows.suspendedUntil {
                        TagPill(text: until.suspensionText, fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.ink)
                    }
                }
                if let distance = friendManager.distance(to: user.id) {
                    Text("离你 \(DistanceFormatter.approximate(km: distance))")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statsRow(_ user: User) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            StatTile(value: user.gamesBand, label: String(localized: "打过"))
            StatTile(value: user.preferredMode?.title ?? String(localized: "都可以"), label: String(localized: "偏好"))
        }
    }

    /// 场次够了才公开胜率，否则不显示
    @ViewBuilder
    private func winRateLine(_ user: User) -> some View {
        let rate = appState.backend.winRate(for: user.id, month: Rankings.month(containing: Date()))
        if rate.isPublic {
            Label("本月胜率 \(rate.percentage)%（\(rate.games) 场 · \(rate.opponents) 位对手）", systemImage: "chart.bar.fill")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
    }

    /// 能挑战就显示按钮；对方不接受挑战时整块隐藏；其他情况灰掉并说明原因
    @ViewBuilder
    private func challengeButton(_ user: User) -> some View {
        let availability = appState.backend.challengeAvailability(for: user.id)
        if user.id != appState.currentUser?.id, availability != .notAccepting {
            VStack(spacing: AppTheme.Spacing.xs) {
                Button {
                    showChallenge = true
                } label: {
                    Label("发起单打挑战", systemImage: "flag.2.crossed.fill")
                }
                .buttonStyle(BrutalButtonStyle(kind: .accent(AppTheme.Colors.peach), size: .medium))
                .disabled(availability != .available)
                if let reason = availability.reason {
                    Text(reason)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// 别人只看到正面印象和“靠谱”徽章；评分数字只在内部用于匹配排序
    private func reputationCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("球友印象")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            PraiseTagsView(tags: user.reputation.publicTags, emptyText: String(localized: "评价的球友还不到 5 位，暂不显示印象"))
            Text(user.isNewPlayer
                 ? String(localized: "评价不足 5 次，等级为问卷定级 \(SkillTier(rating: user.selfRating).text)，仅供参考")
                 : String(localized: "等级由问卷与球友评价综合得出"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
        .card()
    }

    /// 私信按钮：按关系决定能不能聊、在哪聊（陌生人不能直接私信）
    @ViewBuilder
    private func messageButton(_ user: User) -> some View {
        switch messageManager.permission(with: user.id) {
        case .allowed, .pendingRequest:
            Button {
                dismiss()
                router.open(.chat(userId: user.id), in: .messages)
            } label: {
                Label("私信", systemImage: "bubble.left.fill")
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
        case .request:
            Button {
                dismiss()
                router.open(.chat(userId: user.id), in: .messages)
            } label: {
                Label("发消息请求", systemImage: "envelope.fill")
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
        case .gameChat(let gameId):
            Button {
                if let threadId = messageManager.gameChatId(for: gameId) {
                    dismiss()
                    router.open(.groupChat(threadId: threadId), in: .messages)
                }
            } label: {
                Label("球局群聊", systemImage: "person.3.fill")
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
        case .friendsOnly, .newAccount, .blocked:
            EmptyView()
        }
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
                    Text(together.isEmpty ? String(localized: "还没一起打过") : String(localized: "一起打过 \(together.count) 场"))
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
                Text(mutual.isEmpty ? String(localized: "没有共同球友") : String(localized: "共同球友 \(mutual.count) 位"))
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
                    messageButton(user)
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
                challengeButton(user)
            }
            HStack(spacing: AppTheme.Spacing.lg) {
                if friendManager.isFriend(user.id) {
                    Button("删除球友") {
                        Task {
                            try? await friendManager.remove(user.id)
                            appState.showToast(String(localized: "已删除"))
                        }
                    }
                    .buttonStyle(TextActionStyle())
                }
                if !isBlocked {
                    Button("屏蔽") {
                        messageManager.block(user.id)
                        friendManager.reload()
                        appState.showToast(String(localized: "已屏蔽，对方不会收到通知"))
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
                    appState.showToast(String(localized: "已添加为球友"), style: .success)
                }
            }
            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .medium))
        } else {
            Button {
                Task {
                    do {
                        try await friendManager.sendRequest(to: userId)
                        appState.showToast(String(localized: "申请已发送"), style: .success)
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

    private var navigator: InboxNavigator {
        InboxNavigator(router: router, inboxManager: inboxManager, roomManager: roomManager, surveyManager: surveyManager,
                       appState: appState, matchManager: matchManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "通知")) {
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
                        EmptyStateView(icon: "bell.slash", title: String(localized: "暂无通知"), message: String(localized: "好友申请、房间邀请、球局提醒都会出现在这里。"))
                    }
                    ForEach(inboxManager.items) { item in
                        Button {
                            navigator.open(item)
                        } label: {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                IconTile(systemName: item.kind.icon, fill: item.kind.tint, size: 40)
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
}
