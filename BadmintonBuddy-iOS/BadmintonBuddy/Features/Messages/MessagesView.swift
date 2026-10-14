import SwiftUI

struct MessagesView: View {
    enum Segment: String, CaseIterable {
        case chats = "聊天"
        case friends = "球友"
    }

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var friendManager: FriendManager

    @State private var segment: Segment = .chats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                LargeTitleHeader(title: "消息") {
                    IconButton(systemName: "person.badge.plus", accessibilityLabel: "添加球友") {
                        router.open(.addFriend)
                    }
                }
                SegmentedSticker(options: Segment.allCases, selection: $segment, title: { $0.rawValue }) { option in
                    switch option {
                    case .chats: return messageManager.unreadCount
                    case .friends: return friendManager.incomingRequests.count
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)

                switch segment {
                case .chats: chats
                case .friends: FriendsContent()
                }
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.tabBarClearance)
        }
        .refreshable {
            messageManager.reload()
            friendManager.reload()
        }
    }

    @ViewBuilder
    private var chats: some View {
        if !messageManager.incomingRequests.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionTitle(title: "消息请求", detail: "同球群的人想和你聊 · 忽略对方不会知道")
                VStack(spacing: 0) {
                    ForEach(Array(messageManager.incomingRequests.enumerated()), id: \.element.id) { index, thread in
                        if index > 0 { InsetDivider().padding(.leading, 72) }
                        ThreadRow(thread: thread)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.butter, radius: AppTheme.Radius.lg)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
        }
        if messageManager.conversations.isEmpty {
            EmptyStateView(icon: "bubble.left.and.bubble.right", title: "还没有聊天",
                           message: "匹配成功或添加球友后，就可以在这里约时间、约球馆。",
                           actionTitle: "添加球友") { router.open(.addFriend) }
                .card()
                .padding(.horizontal, AppTheme.Spacing.screen)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(messageManager.conversations.enumerated()), id: \.element.id) { index, thread in
                    if index > 0 { InsetDivider().padding(.leading, 72) }
                    ThreadRow(thread: thread)
                        .contextMenu {
                            if thread.isGroup {
                                Button(role: .destructive) {
                                    messageManager.deleteThread(thread)
                                } label: {
                                    Label("清空并隐藏", systemImage: "trash")
                                }
                            } else if let other = thread.otherParticipantId(currentUserId: messageManager.currentUserId ?? "") {
                                Button(role: .destructive) {
                                    messageManager.deleteThread(thread)
                                } label: {
                                    Label("删除会话", systemImage: "trash")
                                }
                                Button(role: .destructive) {
                                    messageManager.block(other)
                                } label: {
                                    Label("屏蔽", systemImage: "hand.raised.fill")
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            .padding(.horizontal, AppTheme.Spacing.screen)
            Text("长按会话可删除或屏蔽；删除只对你隐藏，不影响对方")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
                .padding(.horizontal, AppTheme.Spacing.screen)
        }
    }
}

private struct ThreadRow: View {
    let thread: MessageThread

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var messageManager: MessageManager

    var body: some View {
        let me = messageManager.currentUserId ?? ""
        let otherId = thread.otherParticipantId(currentUserId: me) ?? ""
        let other = thread.isGroup ? nil : messageManager.user(id: otherId)
        let unread = thread.unreadCount(for: me)
        Button {
            router.open(thread.isGroup ? .groupChat(threadId: thread.id) : .chat(userId: otherId))
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                if thread.isGroup {
                    IconTile(systemName: groupIcon, fill: groupTint, size: 50)
                } else if let other {
                    AvatarView(user: other, size: 50)
                        .opensProfile(other.id)
                } else {
                    AvatarView(text: "?", size: 50)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(thread.isGroup ? (thread.title ?? "群聊") : (other?.nickname ?? "球友"))
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .lineLimit(1)
                        if let other {
                            LevelBadge(level: other.displayLevel, showsName: false, compact: true)
                        }
                        if thread.isPendingRequest && thread.requestFrom == me {
                            TagPill(text: "等对方接受", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
                        }
                        Spacer()
                        Text(DateText.compact(thread.lastActivityAt))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                    HStack {
                        Text(preview)
                            .font(unread > 0 ? AppTheme.Typography.subheadlineBold : AppTheme.Typography.subheadline)
                            .foregroundStyle(unread > 0 ? AppTheme.Colors.ink : AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                        Spacer()
                        if unread > 0 { CountBadge(count: unread) }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开聊天")
    }

    private var groupIcon: String {
        if case .game = thread.context { return "ticket.fill" }
        return "person.3.fill"
    }

    private var groupTint: Color {
        if case .game = thread.context { return AppTheme.Colors.lime }
        return AppTheme.Colors.lavender
    }

    private var preview: String {
        guard let message = thread.lastMessage else { return "" }
        if thread.isGroup, message.kind != .system, message.senderId != messageManager.currentUserId,
           let sender = messageManager.user(id: message.senderId) {
            return "\(sender.nickname)：\(message.content)"
        }
        switch message.kind {
        case .roomInvite: return "[房间邀请] \(message.content)"
        case .gameShare: return "[球局] \(message.content)"
        case .system: return message.content
        case .text:
            let prefix = message.senderId == messageManager.currentUserId ? "我：" : ""
            return prefix + message.content
        }
    }
}

// MARK: - 球友列表（含好友申请）

struct FriendsContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            if !friendManager.incomingRequests.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    SectionTitle(title: "好友申请", detail: "\(friendManager.incomingRequests.count)")
                    ForEach(friendManager.incomingRequests) { request in
                        FriendRequestRow(request: request)
                    }
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionTitle(title: "我的球友", detail: "\(friendManager.friends.count) 人", actionTitle: "添加") {
                    router.open(.addFriend)
                }
                if friendManager.friends.count > 5 {
                    SearchField(text: $query, placeholder: "搜索球友")
                }
                let list = friendManager.searchFriends(query: query)
                if list.isEmpty {
                    EmptyStateView(icon: "person.2", title: query.isEmpty ? "还没有球友" : "没有找到",
                                   message: query.isEmpty ? "一起打过球后互加好友，下次约球更方便。" : "换个关键词试试")
                        .card()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { InsetDivider().padding(.leading, 60) }
                            PlayerRow(user: friend) {
                                appState.showPlayer(friend.id)
                            } trailing: {
                                Button {
                                    router.open(.chat(userId: friend.id))
                                } label: {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(AppTheme.Colors.onAccent)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(AppTheme.Colors.lavender))
                                        .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("给 \(friend.nickname) 发消息")
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
    }
}

/// 独立页面版本（从“我的”进入）
struct FriendsView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "我的球友")
            ScrollView {
                FriendsContent()
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @State private var isWorking = false

    var body: some View {
        if let user = friendManager.user(id: request.fromUserId) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Button {
                    appState.showPlayer(user.id)
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        AvatarView(user: user, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(user.nickname)
                                    .font(AppTheme.Typography.headline)
                                    .foregroundStyle(AppTheme.Colors.ink)
                                LevelBadge(level: user.displayLevel, showsName: false, compact: true)
                            }
                            Text(request.note.isEmpty ? "想加你为球友" : "“\(request.note)”")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button("忽略") { respond(false) }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                    Button("通过") { respond(true) }
                        .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small))
                }
                .disabled(isWorking)
            }
            .card(AppTheme.Colors.surface, padding: AppTheme.Spacing.md)
        }
    }

    private func respond(_ accept: Bool) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await friendManager.respond(request, accept: accept)
                if accept { appState.showToast("已添加为球友", style: .success) }
            } catch {
                appState.showError(error)
            }
        }
    }
}

/// 球友行（头像 + 昵称 + 等级 + 口碑）
struct PlayerRow<Trailing: View>: View {
    let user: User
    var subtitle: String?
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: action) {
                HStack(spacing: AppTheme.Spacing.md) {
                    AvatarView(user: user, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(user.nickname)
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.ink)
                                .lineLimit(1)
                            LevelBadge(level: user.displayLevel, showsName: false, compact: true)
                        }
                        Text(subtitle ?? defaultSubtitle)
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var defaultSubtitle: String {
        "\(user.displayLevelText) · \(user.publicSummary)"
    }
}

// MARK: - 添加球友

struct AddFriendView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var query = ""
    @State private var results: [User] = []
    @State private var coPlayers: [User] = []
    @State private var regulars: [User] = []

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "添加球友")
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SearchField(text: $query, placeholder: "搜索昵称或 4 位 ID")
                        if let me = appState.currentUser {
                            Text("我的 ID：\(me.shortId)")
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                    }
                    if !query.isEmpty {
                        section(title: "搜索结果", users: results, emptyText: "没有找到“\(query)”")
                    }
                    section(title: "一起打过球的人", users: coPlayers, emptyText: "打完球后，这里会出现一起打过的人")
                    section(title: "同馆常客", users: regulars, emptyText: "设置常去球馆后，这里会显示公开了自己是常客的球友")
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            coPlayers = friendManager.recentCoPlayers()
            regulars = friendManager.venueRegulars().map(\.user).filter { !friendManager.isFriend($0.id) }
        }
        .onChange(of: query) { _, value in
            results = friendManager.searchDirectory(query: value)
        }
    }

    private func section(title: String, users: [User], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: title)
            if users.isEmpty {
                Text(emptyText)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { InsetDivider().padding(.leading, 60) }
                        PlayerRow(user: user, subtitle: subtitle(for: user)) {
                            appState.showPlayer(user.id)
                        } trailing: {
                            FriendActionButton(userId: user.id)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
            }
        }
    }

    private func subtitle(for user: User) -> String {
        var parts: [String] = []
        if let distance = friendManager.distance(to: user.id) { parts.append(DistanceFormatter.approximate(km: distance)) }
        parts.append(user.publicSummary)
        return parts.joined(separator: " · ")
    }
}

/// 加好友按钮（根据关系显示不同状态）
struct FriendActionButton: View {
    let userId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @State private var isWorking = false

    var body: some View {
        Group {
            if friendManager.isFriend(userId) {
                TagPill(text: "已是球友", icon: "checkmark", fill: AppTheme.Colors.mint)
            } else if friendManager.hasPendingRequest(to: userId) {
                TagPill(text: "等待通过", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.inkSecondary)
            } else if let incoming = friendManager.incomingRequest(from: userId) {
                Button("通过申请") {
                    Task {
                        try? await friendManager.respond(incoming, accept: true)
                    }
                }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
            } else {
                Button {
                    Task { await send() }
                } label: {
                    Label("加球友", systemImage: "plus")
                }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
                .disabled(isWorking)
            }
        }
    }

    private func send() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await friendManager.sendRequest(to: userId)
            appState.showToast("申请已发送", style: .success)
        } catch {
            appState.showError(error)
        }
    }
}
