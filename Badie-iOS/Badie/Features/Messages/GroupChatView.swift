import SwiftUI

/// 群聊：球局群（确认后开放、赛后 48 小时关闭）和球群群聊
struct GroupChatView: View {
    let threadId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var messageManager: MessageManager

    @State private var draft = ""
    @State private var isSending = false

    private var thread: MessageThread? { messageManager.thread(id: threadId) }
    private var messages: [Message] { messageManager.messages(threadId: threadId) }
    private var me: String? { messageManager.currentUserId }
    private var canPost: Bool { messageManager.canPost(in: threadId) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: thread?.title ?? String(localized: "群聊")) {
                if let destination {
                    IconButton(systemName: destination.icon, accessibilityLabel: destination.label) {
                        router.open(destination.route)
                    }
                }
            }
            membersStrip
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            row(message, previous: index > 0 ? messages[index - 1] : nil)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(AppTheme.Motion.gentle) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { messageManager.openThread(threadId) }
        .onDisappear { messageManager.closeThread(threadId) }
    }

    // MARK: Header

    private var destination: (icon: String, label: String, route: Route)? {
        switch thread?.context {
        case .game(let gameId): return ("ticket.fill", String(localized: "查看球局"), .game(id: gameId))
        case .group(let groupId): return ("person.3.fill", String(localized: "查看球群"), .group(id: groupId))
        case nil: return nil
        }
    }

    private var membersStrip: some View {
        let members = (thread?.participantIds ?? []).compactMap { messageManager.user($0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -6) {
                ForEach(members.prefix(12)) { member in
                    AvatarView(user: member, size: 30)
                        .opensProfile(member.id)
                }
                Text("\(members.count) 人")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .padding(.leading, AppTheme.Spacing.md)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .accessibilityLabel("群成员 \(members.count) 人")
    }

    // MARK: Messages

    @ViewBuilder
    private func row(_ message: Message, previous: Message?) -> some View {
        let isMine = message.senderId == me
        if message.kind == .system || isMine {
            MessageBubble(message: message, isMine: isMine)
        } else {
            let sender = messageManager.user(message.senderId)
            let showsSender = previous?.senderId != message.senderId
            let mentionsContact = ContactInfoDetector.mentionsOffPlatformContact(message.content)
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                if showsSender, let sender {
                    AvatarView(user: sender, size: 32)
                        .opensProfile(sender.id)
                } else {
                    Color.clear.frame(width: 32, height: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if showsSender {
                        Text(sender?.nickname ?? String(localized: "球友"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                    MessageBubble(message: message, isMine: false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if mentionsContact {
                    Label("提到了站外联系方式，转账、代付要谨慎", systemImage: "exclamationmark.shield.fill")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.danger)
                        .offset(x: 40, y: 16)
                }
            }
            .padding(.bottom, mentionsContact ? 16 : 0)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if canPost {
                HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                    TextField("发消息…", text: $draft, axis: .vertical)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1...5)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .sticker(AppTheme.Colors.surface, radius: 20, shadow: .zero)
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(AppTheme.Colors.onAccent)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(canSend ? AppTheme.Colors.lime : AppTheme.Colors.surfaceMuted))
                            .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .disabled(!canSend)
                    .accessibilityLabel("发送")
                }
            } else {
                NoticeBanner(icon: "lock.fill",
                             text: closedText,
                             tint: AppTheme.Colors.surfaceMuted)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    private var closedText: String {
        switch thread?.context {
        case .game: return String(localized: "球局群聊在赛后 48 小时关闭了。想再约的话，加个球友吧。")
        case .group: return String(localized: "加入球群后才能在群里发言")
        case nil: return String(localized: "这个群聊已经结束了")
        }
    }

    private var canSend: Bool { Message.validate(draft) == .valid && !isSending }

    private func send() async {
        let text = draft
        guard Message.validate(text) == .valid else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await messageManager.sendGroup(text, threadId: threadId)
            draft = ""
        } catch {
            appState.showError(error)
        }
    }
}
