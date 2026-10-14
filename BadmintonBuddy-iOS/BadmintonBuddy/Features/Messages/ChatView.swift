import SwiftUI

struct ChatView: View {
    let userId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var roomManager: RoomManager

    @State private var draft = ""
    @State private var isSending = false
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @FocusState private var inputFocused: Bool

    private var other: User? { messageManager.user(id: userId) }
    private var messages: [Message] { messageManager.messages(with: userId) }
    private var isBlocked: Bool { messageManager.isBlocked(userId) }
    private var me: String? { messageManager.currentUserId }
    private var permission: MessagePermission {
        _ = messageManager.threads
        return messageManager.permission(with: userId)
    }
    private var thread: MessageThread? {
        _ = messageManager.threads
        return messageManager.thread(with: userId)
    }
    /// 对方发来的消息请求，等我处理
    private var isIncomingRequest: Bool {
        guard let thread else { return false }
        return thread.isPendingRequest && thread.requestFrom == userId
    }
    /// 非好友提到了站外联系方式 / 转账方式：提醒防骗
    private var showsContactWarning: Bool {
        !friendManager.isFriend(userId)
            && messages.contains { $0.senderId == userId && ContactInfoDetector.mentionsOffPlatformContact($0.content) }
    }

    private let quickReplies = ["几点开始？", "去哪个球馆？", "我带球", "我到了", "AA 就行"]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        if messages.isEmpty {
                            EmptyStateView(icon: "hand.wave.fill", title: "打个招呼吧",
                                           message: "约时间、约球馆、约 AA，都可以在这里说。", tint: AppTheme.Colors.butter)
                        }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if showsTimestamp(at: index) {
                                Text(DateText.compact(message.sentAt) == DateText.time(message.sentAt)
                                     ? DateText.time(message.sentAt)
                                     : "\(DateText.compact(message.sentAt)) \(DateText.time(message.sentAt))")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                                    .padding(.top, AppTheme.Spacing.sm)
                            }
                            MessageBubble(
                                message: message,
                                isMine: message.senderId == me,
                                showsReceipt: message.id == lastMineId,
                                onJoinRoom: { code in router.open(.joinRoom(code: code)) }
                            )
                            .id(message.id)
                        }
                        if messageManager.isTyping(userId) {
                            HStack {
                                LoadingDots()
                                    .padding(.horizontal, AppTheme.Spacing.lg)
                                    .padding(.vertical, AppTheme.Spacing.md)
                                    .sticker(AppTheme.Colors.surface, radius: 18, shadow: .zero)
                                    .accessibilityLabel("对方正在输入")
                                Spacer()
                            }
                            .id("typing")
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy, animated: true) }
                .onChange(of: messageManager.isTyping(userId)) { _, _ in scrollToBottom(proxy, animated: true) }
            }
            inputBar
        }
        .onAppear { messageManager.open(with: userId) }
        .onDisappear { messageManager.close(with: userId) }
        .sheet(isPresented: $showReport) {
            ReportSheet(userId: userId, nickname: other?.nickname ?? "TA")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("屏蔽 \(other?.nickname ?? "TA")？", isPresented: $showBlockConfirm) {
            Button("取消", role: .cancel) {}
            Button("屏蔽", role: .destructive) {
                messageManager.block(userId)
                appState.showToast("已屏蔽，对方不会收到通知")
            }
        } message: {
            Text("屏蔽后对方无法给你发消息、加你好友或加入你的房间，也不会出现在匹配结果里。对方不会收到通知。")
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: other?.nickname ?? "聊天") {
            if let other {
                AvatarView(user: other, size: 36)
                    .frame(width: 44, height: 44)
                    .opensProfile(other.id)
                    .accessibilityLabel("\(other.nickname)的资料")
            }
            Menu {
                Button {
                    appState.showPlayer(userId)
                } label: {
                    Label("查看资料", systemImage: "person.crop.circle")
                }
                if friendManager.isFriend(userId) {
                    Button {
                        router.open(.createRoom(nil, invitee: userId))
                    } label: {
                        Label("约 TA 打球", systemImage: "sportscourt")
                    }
                }
                Divider()
                if isBlocked {
                    Button {
                        messageManager.unblock(userId)
                        appState.showToast("已解除屏蔽")
                    } label: {
                        Label("解除屏蔽", systemImage: "hand.raised.slash")
                    }
                } else {
                    Button(role: .destructive) {
                        showBlockConfirm = true
                    } label: {
                        Label("屏蔽", systemImage: "hand.raised.fill")
                    }
                }
                Button(role: .destructive) {
                    showReport = true
                } label: {
                    Label("举报", systemImage: "exclamationmark.bubble.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(width: 44, height: 44)
                    .sticker(AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
            }
            .accessibilityLabel("更多")
        }
        .overlay(alignment: .bottom) {
            if let other {
                Text("\(other.displayLevelText) · \(other.publicSummary)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .offset(y: -2)
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if showsContactWarning {
                NoticeBanner(icon: "exclamationmark.shield.fill",
                             text: "对方提到了站外联系方式或转账。见面打球前不需要转账、代付或提供验证码，遇到这类要求请举报。",
                             tint: AppTheme.Colors.pink)
            }
            if isIncomingRequest {
                requestCard
            }
            switch permission {
            case .blocked:
                NoticeBanner(icon: "hand.raised.fill", text: "你已屏蔽对方，解除后才能继续聊天", tint: AppTheme.Colors.surfaceMuted,
                             actionTitle: "解除") {
                    messageManager.unblock(userId)
                }
            case .pendingRequest:
                NoticeBanner(icon: "paperplane.fill", text: "已发出消息请求，对方接受后才能继续聊", tint: AppTheme.Colors.sky)
            case .gameChat(let gameId):
                NoticeBanner(icon: "person.3.fill", text: "你们在同一场球局里，在球局群聊里沟通就行（赛后 48 小时关闭）",
                             tint: AppTheme.Colors.lime, actionTitle: "去群聊") {
                    if let threadId = messageManager.gameChatId(for: gameId) {
                        router.open(.groupChat(threadId: threadId))
                    }
                }
            case .friendsOnly:
                VStack(spacing: AppTheme.Spacing.sm) {
                    NoticeBanner(icon: "person.crop.circle.badge.plus",
                                 text: "加为球友后才能私信。陌生人不能直接发消息，是为了少一点骚扰和骗局。",
                                 tint: AppTheme.Colors.surfaceMuted)
                    FriendActionButton(userId: userId)
                }
            case .newAccount:
                NoticeBanner(icon: "hourglass",
                             text: "打满 \(User.gamesBeforeMessageRequests) 场后才能给球群里的人发消息请求；可以先在球群群聊里打招呼",
                             tint: AppTheme.Colors.surfaceMuted)
            case .allowed, .request:
                composer
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    /// 对方发来的消息请求：接受 / 忽略（忽略对方不会知道）
    private var requestCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("\(other?.nickname ?? "TA") 想和你聊天", systemImage: "envelope.badge.fill")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            Text("你们在同一个球群。接受后才能互相发消息；忽略的话对方不会知道。")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppTheme.Spacing.sm) {
                Button("忽略") {
                    messageManager.declineRequest(from: userId)
                    router.pop()
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                Button("接受") {
                    messageManager.acceptRequest(from: userId)
                    Haptics.success()
                }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small))
            }
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.butter, radius: AppTheme.Radius.md, shadow: .zero)
    }

    @ViewBuilder
    private var composer: some View {
        if case .request(let groupName) = permission {
            Text("你们同在「\(groupName)」。可以先发一条消息请求：纯文字，不能留链接或联系方式，对方接受后再聊。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: AppTheme.Spacing.sm) {
            if messages.count < 6, permission == .allowed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(quickReplies, id: \.self) { reply in
                            ChoiceChip(title: reply, isSelected: false) {
                                Task { await send(reply) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                TextField("发消息…", text: $draft, axis: .vertical)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .sticker(AppTheme.Colors.surface, radius: 20, shadow: .zero,
                             stroke: draft.count > MessageManager.maxMessageLength ? AppTheme.Colors.danger : AppTheme.Colors.stroke)
                Button {
                    Task { await send(draft) }
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
            if draft.count > MessageManager.maxMessageLength - 100 {
                Text("\(draft.count)/\(MessageManager.maxMessageLength)")
                    .font(AppTheme.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(draft.count > MessageManager.maxMessageLength ? AppTheme.Colors.danger : AppTheme.Colors.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var canSend: Bool {
        Message.validate(draft) == .valid && !isSending
    }

    private var lastMineId: String? {
        messages.last { $0.senderId == me && $0.kind != .system }?.id
    }

    private func showsTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return messages[index].sentAt.timeIntervalSince(messages[index - 1].sentAt) > 10 * 60
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let target: String? = messageManager.isTyping(userId) ? "typing" : messages.last?.id
        guard let target else { return }
        if animated {
            withAnimation(AppTheme.Motion.gentle) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func send(_ text: String) async {
        guard Message.validate(text) == .valid else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await messageManager.send(text, to: userId)
            if text == draft { draft = "" }
        } catch {
            appState.showError(error)
        }
    }
}

// MARK: - 消息气泡

struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    var showsReceipt = false
    var onJoinRoom: (String) -> Void = { _ in }

    var body: some View {
        switch message.kind {
        case .system:
            Text(message.content)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.Colors.surfaceMuted))
                .frame(maxWidth: .infinity)
        case .roomInvite(let code):
            bubbleContainer {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Label("房间邀请", systemImage: "ticket.fill")
                        .font(AppTheme.Typography.overline)
                    Text(message.content)
                        .font(AppTheme.Typography.subheadlineBold)
                    Text(code)
                        .font(.system(.title2, design: .monospaced, weight: .black))
                    if !isMine {
                        Button("加入房间") { onJoinRoom(code) }
                            .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .small, fullWidth: true))
                    }
                }
                .foregroundStyle(AppTheme.Colors.onAccent)
                .padding(AppTheme.Spacing.md)
                .frame(width: 220, alignment: .leading)
                .sticker(AppTheme.Colors.lavender, radius: 18, shadow: AppTheme.Elevation.low)
            }
        case .text, .gameShare:
            bubbleContainer {
                Text(message.content)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(isMine ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .sticker(isMine ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: 18, shadow: .zero)
                    .textSelection(.enabled)
            }
        }
    }

    private func bubbleContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            HStack {
                if isMine { Spacer(minLength: 48) }
                content()
                if !isMine { Spacer(minLength: 48) }
            }
            if showsReceipt && isMine {
                Text(receiptText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(message.isRead ? AppTheme.Colors.success : AppTheme.Colors.inkTertiary)
                    .accessibilityLabel(receiptText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var receiptText: String {
        if let readAt = message.readAt { return "已读 \(DateText.time(readAt))" }
        if message.isDelivered { return "已送达" }
        return "发送中"
    }
}

// MARK: - 举报

struct ReportSheet: View {
    let userId: String
    let nickname: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var messageManager: MessageManager
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason?
    @State private var detail = ""
    @State private var alsoBlock = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    Text("举报 \(nickname)")
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Spacer()
                    IconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
                }
                .padding(.top, AppTheme.Spacing.xl)
                Text("举报信息仅平台可见，我们会在 24 小时内处理。")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(ReportReason.allCases) { option in
                        Button {
                            Haptics.selection()
                            reason = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                    .font(AppTheme.Typography.bodyBold)
                                    .foregroundStyle(AppTheme.Colors.ink)
                                Spacer()
                                Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(reason == option ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                            }
                            .padding(AppTheme.Spacing.md)
                            .sticker(reason == option ? AppTheme.Colors.pink : AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(reason == option ? [.isSelected, .isButton] : .isButton)
                    }
                }
                BrutalTextField(label: "补充说明（可选）", placeholder: "发生了什么？", text: $detail, characterLimit: 200, axis: .vertical)
                Toggle(isOn: $alsoBlock) {
                    Text("同时屏蔽对方")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                }
                .tint(AppTheme.Colors.success)
                Button("提交举报") {
                    guard let reason else { return }
                    Task {
                        await messageManager.report(userId, reason: reason, detail: detail, alsoBlock: alsoBlock)
                        appState.showToast("举报已提交，感谢你让社区更安全", style: .success)
                        dismiss()
                    }
                }
                .buttonStyle(BrutalButtonStyle(kind: .destructive))
                .disabled(reason == nil)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}
