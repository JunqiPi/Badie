package com.badie.app.features.messages

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.CountBadge
import com.badie.app.design.Dot
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.LevelBadge
import com.badie.app.design.NoticeBanner
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.features.social.ConfirmDialog
import com.badie.app.features.social.FriendActionButton
import com.badie.app.features.social.FriendsContent
import com.badie.app.features.social.ReportSheet
import com.badie.app.l10n.tr
import com.badie.app.models.ContactInfoDetector
import com.badie.app.models.DateText
import com.badie.app.models.Message
import com.badie.app.models.MessageKind
import com.badie.app.models.MessageThread
import com.badie.app.models.MessageValidation
import com.badie.app.models.ThreadContext
import com.badie.app.models.User
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import com.badie.app.backend.BackendError
import kotlinx.coroutines.launch

// 消息页（聊天 / 球友）、私信、群聊、通知中心。
// 对应 iPhone 的 Features/Messages/MessagesView.swift、ChatView.swift、GroupChatView.swift，
// 和 Features/Social/PlayerProfileSheet.swift 末尾的 NotificationsView

private enum class Segment { Chats, Friends }

@Composable
fun MessagesScreen() {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    var segment by rememberSaveable { mutableStateOf(Segment.Chats) }
    RefreshEverything(Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.tabBarClearance),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            LargeTitleHeader(tr("消息")) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    if (segment == Segment.Chats) {
                        RulesButton(
                            tr("聊天"),
                            listOf(tr("长按会话可以删除或屏蔽。"), tr("删除只对你隐藏，不影响对方。"), tr("同球群的人可以给你发消息请求。"), tr("忽略消息请求，对方不会知道。")),
                        )
                    }
                    IconButton(Sym.personBadgePlus, tr("添加球友")) { env.router.open(Route.AddFriend) }
                }
            }
            SegmentedSticker(
                Segment.entries, segment, { segment = it }, Modifier.padding(horizontal = AppTheme.Spacing.screen),
                badge = { if (it == Segment.Chats) messageManager.unreadCount else env.friendManager.incomingRequestCount },
            ) { if (it == Segment.Chats) tr("聊天") else tr("球友") }
            when (segment) {
                Segment.Chats -> Chats()
                Segment.Friends -> FriendsContent()
            }
        }
    }
}

@Composable
private fun ColumnScope.Chats() {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    val colors = AppTheme.colors
    val requests = messageManager.incomingRequests
    if (requests.isNotEmpty()) {
        Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            SectionTitle(tr("消息请求"), detail = "${requests.size}")
            Column(Modifier.fillMaxWidth().sticker(colors.butter, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg)) {
                requests.forEachIndexed { index, thread ->
                    if (index > 0) InsetDivider(Modifier.padding(start = 72.dp))
                    ThreadRow(thread)
                }
            }
        }
    }
    val conversations = messageManager.conversations
    if (conversations.isEmpty()) {
        EmptyStateView(
            Sym.bubbleLeftAndBubbleRight, tr("还没有聊天"),
            Modifier.padding(horizontal = AppTheme.Spacing.screen).card(),
            actionTitle = tr("添加球友"),
        ) { env.router.open(Route.AddFriend) }
    } else {
        Column(
            Modifier.padding(horizontal = AppTheme.Spacing.screen).fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg)
                .padding(horizontal = AppTheme.Spacing.lg),
        ) {
            conversations.forEachIndexed { index, thread ->
                if (index > 0) InsetDivider(Modifier.padding(start = 72.dp))
                ThreadRow(thread, contextMenu = true)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ThreadRow(thread: MessageThread, contextMenu: Boolean = false) {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val me = messageManager.currentUserId ?: ""
    val otherId = thread.otherParticipantId(me) ?: ""
    val other = if (thread.isGroup) null else messageManager.user(otherId)
    val unread = thread.unreadCount(me)
    var menu by remember { mutableStateOf(false) }
    val hint = tr("打开聊天")
    Box {
        Row(
            Modifier.fillMaxWidth()
                .combinedClickable(
                    remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClickLabel = hint,
                    onLongClick = if (contextMenu) ({
                        haptics.impact()
                        menu = true
                    }) else null,
                ) { env.router.open(if (thread.isGroup) Route.GroupChat(thread.id) else Route.Chat(otherId)) }
                .padding(vertical = AppTheme.Spacing.md)
                .semantics(mergeDescendants = true) {},
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            when {
                thread.isGroup -> {
                    val isGame = thread.context is ThreadContext.Game
                    IconTile(if (isGame) Sym.ticketFill else Sym.person3Fill, fill = if (isGame) colors.lime else colors.lavender, size = 50.dp)
                }
                other != null -> AvatarView(other, Modifier.pressable { env.appState.showPlayer(other.id) }, size = 50.dp)
                else -> AvatarView("?", size = 50.dp)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        Text(
                            if (thread.isGroup) thread.title ?: tr("群聊") else other?.nickname ?: tr("球友"),
                            style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        if (other != null) LevelBadge(other.displayTier, showsName = false, compact = true)
                        if (thread.isPendingRequest && thread.requestFrom == me) {
                            TagPill(tr("等对方接受"), Modifier.weight(1f, fill = false), fill = colors.surfaceMuted, foreground = colors.inkSecondary)
                        }
                    }
                    Text(DateText.compact(thread.lastActivityAt), style = AppTheme.Typography.caption, color = colors.inkTertiary, maxLines = 1)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        preview(thread), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                        style = if (unread > 0) AppTheme.Typography.subheadlineBold else AppTheme.Typography.subheadline,
                        color = if (unread > 0) colors.ink else colors.inkSecondary,
                    )
                    if (unread > 0) CountBadge(unread)
                }
            }
        }
        DropdownMenu(menu, { menu = false }, containerColor = colors.surface) {
            if (thread.isGroup) {
                MenuItem(Sym.trash, tr("清空并隐藏"), destructive = true) {
                    menu = false
                    messageManager.deleteThread(thread)
                }
            } else if (otherId.isNotEmpty()) {
                MenuItem(Sym.trash, tr("删除会话"), destructive = true) {
                    menu = false
                    messageManager.deleteThread(thread)
                }
                MenuItem(Sym.handRaisedFill, tr("屏蔽"), destructive = true) {
                    menu = false
                    messageManager.block(otherId)
                }
            }
        }
    }
}

@Composable
private fun MenuItem(icon: SymbolId, title: String, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) AppTheme.colors.danger else AppTheme.colors.ink
    DropdownMenuItem(
        text = { Text(title, style = AppTheme.Typography.body, color = color) },
        leadingIcon = { Symbol(icon, size = 16, tint = color) },
        onClick = onClick,
    )
}

@Composable
private fun preview(thread: MessageThread): String {
    val messageManager = LocalEnv.current.messageManager
    // 没聊过的私信只有新球友
    val message = thread.lastMessage ?: return if (thread.isGroup) "" else tr("已是球友")
    if (thread.isGroup && message.kind != MessageKind.System && message.senderId != messageManager.currentUserId) {
        messageManager.user(message.senderId)?.let { return tr("%@：%@", it.nickname, message.content) }
    }
    return when (message.kind) {
        is MessageKind.RoomInvite -> tr("[房间邀请] %@", message.content)
        is MessageKind.GameShare -> tr("[球局] %@", message.content)
        MessageKind.System -> message.content
        MessageKind.Text -> (if (message.senderId == messageManager.currentUserId) tr("我：") else "") + message.content
    }
}

// MARK: - 私信

@Composable
fun ChatScreen(userId: String) {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    val friendManager = env.friendManager
    val colors = AppTheme.colors
    var showReport by remember { mutableStateOf(false) }
    var showBlockConfirm by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val other = messageManager.user(userId)
    val messages = messageManager.messagesWith(userId)
    val me = messageManager.currentUserId
    val listState = rememberLazyListState()
    val blockedToast = tr("已屏蔽，对方不会收到通知")
    val unblockedToast = tr("已解除屏蔽")

    DisposableEffect(userId) {
        messageManager.open(userId)
        onDispose { messageManager.close(userId) }
    }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size) }

    Column(Modifier.fillMaxSize()) {
        Box {
            ScreenHeader(other?.nickname ?: tr("聊天"), onBack = { env.router.pop() }) {
                if (other != null) {
                    val label = tr("%@的资料", other.nickname)
                    Box(Modifier.size(44.dp).pressable { env.appState.showPlayer(other.id) }.semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
                        AvatarView(other, size = 36.dp)
                    }
                }
                Box {
                    IconButton(Sym.ellipsis, tr("更多")) { menu = true }
                    DropdownMenu(menu, { menu = false }, containerColor = colors.surface) {
                        MenuItem(Sym.personCropCircle, tr("查看资料")) {
                            menu = false
                            env.appState.showPlayer(userId)
                        }
                        if (friendManager.isFriend(userId)) {
                            MenuItem(Sym.sportscourt, tr("约 TA 打球")) {
                                menu = false
                                env.router.open(Route.CreateRoom(invitee = userId))
                            }
                        }
                        HorizontalDivider(color = colors.divider)
                        if (messageManager.isBlocked(userId)) {
                            MenuItem(Sym.handRaisedSlash, tr("解除屏蔽")) {
                                menu = false
                                messageManager.unblock(userId)
                                env.appState.showToast(unblockedToast)
                            }
                        } else {
                            MenuItem(Sym.handRaisedFill, tr("屏蔽"), destructive = true) {
                                menu = false
                                showBlockConfirm = true
                            }
                        }
                        MenuItem(Sym.exclamationmarkBubbleFill, tr("举报"), destructive = true) {
                            menu = false
                            showReport = true
                        }
                    }
                }
            }
            if (other != null) {
                Text(
                    "${other.displayLevelText} · ${other.publicSummary}", style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1,
                    modifier = Modifier.align(Alignment.BottomCenter).offset(y = (-2).dp),
                )
            }
        }
        val receiptId = messages.lastOrNull { it.senderId == me && it.kind != MessageKind.System }?.id
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth(),
            state = listState,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.md),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            if (messages.isEmpty()) {
                item { EmptyStateView(Sym.handWaveFill, tr("还没有消息"), tint = colors.butter) }
            }
            itemsIndexed(messages, key = { _, message -> message.id }) { index, message ->
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    if (index == 0 || message.sentAt - messages[index - 1].sentAt > 10 * 60_000) {
                        val day = DateText.compact(message.sentAt)
                        val time = DateText.time(message.sentAt)
                        Text(
                            if (day == time) time else "$day $time", style = AppTheme.Typography.caption, color = colors.inkTertiary,
                            modifier = Modifier.padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.sm),
                        )
                    }
                    MessageBubble(message, isMine = message.senderId == me, showsReceipt = message.id == receiptId) { code ->
                        env.router.open(Route.JoinRoom(code))
                    }
                }
            }
            item { Spacer(Modifier.size(1.dp)) }
        }
        ChatInputBar(userId, messages)
    }
    if (showReport) {
        SheetScaffold(onDismiss = { showReport = false }, fullHeight = true) {
            ReportSheet(userId, other?.nickname ?: tr("TA")) { showReport = false }
        }
    }
    if (showBlockConfirm) {
        ConfirmDialog(
            tr("屏蔽 %@？", other?.nickname ?: tr("TA")),
            tr("屏蔽后对方无法给你发消息、加你好友或加入你的房间，也不会出现在匹配结果里。对方不会收到通知。"),
            tr("屏蔽"), onDismiss = { showBlockConfirm = false },
        ) {
            messageManager.block(userId)
            env.appState.showToast(blockedToast)
        }
    }
}

/** 私信和消息请求的规则（“?”里） */
@Composable
private fun messageRules(): List<String> = listOf(
    tr("球友之间可以直接私信。"),
    tr("陌生人不能直接发消息，是为了少一点骚扰和骗局。"),
    tr("同一个球群的人可以先发一条消息请求：纯文字，不能留链接或联系方式。"),
    tr("对方接受后才能互相发消息；忽略的话对方不会知道。"),
    tr("打满 %lld 场后才能发消息请求，之前可以先在球群群聊里打招呼。", User.GAMES_BEFORE_MESSAGE_REQUESTS),
)

@Composable
private fun ChatInputBar(userId: String, messages: List<Message>) {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val other = messageManager.user(userId)
    val thread = messageManager.threadWith(userId)
    val permission = messageManager.permission(userId)
    val isIncomingRequest = thread != null && thread.isPendingRequest && thread.requestFrom == userId
    // 非好友提到了站外联系方式 / 转账方式：提醒防骗
    val showsContactWarning = !env.friendManager.isFriend(userId) &&
        messages.any { it.senderId == userId && ContactInfoDetector.mentionsOffPlatformContact(it.content) }
    Column(
        Modifier.fillMaxWidth().background(colors.canvas),
    ) {
        InsetDivider()
        Column(
            Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            if (showsContactWarning) {
                NoticeBanner(Sym.exclamationmarkShieldFill, tr("打球前不用转账、代付或给验证码，遇到这类要求请举报"), tint = colors.pink)
            }
            if (isIncomingRequest) {
                Column(
                    Modifier.fillMaxWidth().sticker(colors.butter, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                        Symbol(Sym.envelopeBadgeFill, size = 16, tint = colors.onAccent)
                        Text(
                            tr("%@ 想和你聊天", other?.nickname ?: tr("TA")), style = AppTheme.Typography.headline, color = colors.onAccent,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        RulesButton(tr("消息请求"), messageRules())
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        BrutalButton(tr("忽略"), {
                            messageManager.declineRequest(userId)
                            env.router.pop()
                        }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small)
                        BrutalButton(tr("接受"), {
                            messageManager.acceptRequest(userId)
                            haptics.success()
                        }, Modifier.weight(1f), size = ButtonSize.Small)
                    }
                }
            }
            when (permission) {
                MessagePermission.Blocked -> NoticeBanner(Sym.handRaisedFill, tr("已屏蔽"), tint = colors.surfaceMuted, actionTitle = tr("解除")) {
                    messageManager.unblock(userId)
                }
                MessagePermission.PendingRequest -> NoticeBanner(Sym.paperplaneFill, tr("等对方接受"), tint = colors.sky)
                is MessagePermission.GameChat -> NoticeBanner(
                    Sym.person3Fill, tr("球局群聊，赛后 48 小时关闭"), tint = colors.lime, actionTitle = tr("去群聊"),
                ) { env.router.open(Route.GroupChat(messageManager.gameChatId(permission.gameId))) }
                MessagePermission.FriendsOnly -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                        NoticeBanner(Sym.personCropCircleBadgePlus, tr("加为球友后才能私信"), Modifier.weight(1f), tint = colors.surfaceMuted)
                        RulesButton(tr("私信"), messageRules())
                    }
                    FriendActionButton(userId)
                }
                MessagePermission.NewAccount -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                    NoticeBanner(
                        Sym.hourglass, tr("打满 %lld 场后才能发消息请求", User.GAMES_BEFORE_MESSAGE_REQUESTS), Modifier.weight(1f), tint = colors.surfaceMuted,
                    )
                    RulesButton(tr("私信"), messageRules())
                }
                MessagePermission.Allowed, is MessagePermission.Request -> Composer(userId, permission, messages.size)
            }
        }
    }
}

@Composable
private fun Composer(userId: String, permission: MessagePermission, messageCount: Int) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var draft by rememberSaveable(userId) { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    val quickReplies = listOf(tr("几点开始？"), tr("去哪个球馆？"), tr("我带球"), tr("我到了"), tr("AA 就行"))

    fun send(text: String) {
        if (Message.validate(text) != MessageValidation.Valid) return
        isSending = true
        scope.launch {
            try {
                env.messageManager.send(text, userId)
                if (text == draft) draft = ""
            } catch (error: RemoteError) {
                env.appState.showError(error)
            } catch (error: BackendError) {
                env.appState.showError(error)
            }
            isSending = false
        }
    }

    if (permission is MessagePermission.Request) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Symbol(Sym.person3Fill, size = 11, tint = colors.inkSecondary)
            Text(
                tr("同在「%@」", permission.groupName), style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1,
                modifier = Modifier.weight(1f, fill = false),
            )
            RulesButton(tr("消息请求"), messageRules())
        }
    }
    if (messageCount < 6 && permission == MessagePermission.Allowed) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            quickReplies.forEach { reply -> ChoiceChip(reply, isSelected = false) { send(reply) } }
        }
    }
    MessageField(draft, { draft = it }, canSend = Message.validate(draft) == MessageValidation.Valid && !isSending, tooLong = draft.length > MessageManager.MAX_MESSAGE_LENGTH) {
        send(draft)
    }
    if (draft.length > MessageManager.MAX_MESSAGE_LENGTH - 100) {
        Text(
            "${draft.length}/${MessageManager.MAX_MESSAGE_LENGTH}",
            style = AppTheme.Typography.caption.copy(fontFeatureSettings = "tnum"), modifier = Modifier.fillMaxWidth(),
            color = if (draft.length > MessageManager.MAX_MESSAGE_LENGTH) colors.danger else colors.inkTertiary,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
        )
    }
}

/** 输入框（1–5 行）+ 发送按钮 */
@Composable
private fun MessageField(draft: String, onChange: (String) -> Unit, canSend: Boolean, tooLong: Boolean = false, onSend: () -> Unit) {
    val colors = AppTheme.colors
    val sendLabel = tr("发送")
    val placeholder = tr("发消息…")
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        BasicTextField(
            draft, onChange, minLines = 1, maxLines = 5,
            modifier = Modifier.weight(1f).defaultMinSize(minHeight = 48.dp)
                .sticker(colors.surface, radius = 20.dp, shadow = AppTheme.Elevation.none, stroke = if (tooLong) colors.danger else colors.stroke)
                .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md)
                .semantics { contentDescription = placeholder },
            textStyle = AppTheme.Typography.body.copy(color = colors.ink),
            cursorBrush = SolidColor(colors.ink),
            decorationBox = { field ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (draft.isEmpty()) Text(placeholder, style = AppTheme.Typography.body, color = colors.inkTertiary)
                    field()
                }
            },
        )
        Box(
            Modifier.size(48.dp).pressable(scale = 0.9f, enabled = canSend, onClick = onSend)
                .sticker(if (canSend) colors.lime else colors.surfaceMuted, radius = 24.dp, shadow = AppTheme.Elevation.none)
                .semantics { contentDescription = sendLabel },
            contentAlignment = Alignment.Center,
        ) { Symbol(Sym.arrowUp, size = 18, tint = colors.onAccent) }
    }
}

// MARK: - 消息气泡

@Composable
fun MessageBubble(message: Message, isMine: Boolean, showsReceipt: Boolean = false, onJoinRoom: (String) -> Unit = {}) {
    val colors = AppTheme.colors
    when (val kind = message.kind) {
        MessageKind.System -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Text(
                message.content, style = AppTheme.Typography.caption, color = colors.inkSecondary,
                modifier = Modifier.clip(CircleShape).background(colors.surfaceMuted).padding(horizontal = AppTheme.Spacing.md, vertical = 6.dp),
            )
        }
        is MessageKind.RoomInvite -> BubbleContainer(isMine, showsReceipt, message) {
            Column(
                Modifier.width(220.dp).sticker(colors.lavender, radius = 18.dp, shadow = AppTheme.Elevation.low).padding(AppTheme.Spacing.md),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(Sym.ticketFill, size = 11, tint = colors.onAccent)
                    Text(tr("房间邀请"), style = AppTheme.Typography.overline, color = colors.onAccent)
                }
                Text(message.content, style = AppTheme.Typography.subheadlineBold, color = colors.onAccent)
                Text(kind.code, style = androidx.compose.ui.text.TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Black, fontSize = 22.sp), color = colors.onAccent)
                if (!isMine) BrutalButton(tr("加入房间"), { onJoinRoom(kind.code) }, kind = ButtonKind.Inverse, size = ButtonSize.Small)
            }
        }
        MessageKind.Text, is MessageKind.GameShare -> BubbleContainer(isMine, showsReceipt, message) {
            Text(
                message.content, style = AppTheme.Typography.body, color = if (isMine) colors.onAccent else colors.ink,
                modifier = Modifier.sticker(if (isMine) colors.lime else colors.surface, radius = 18.dp, shadow = AppTheme.Elevation.none)
                    .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md),
            )
        }
    }
}

@Composable
private fun BubbleContainer(isMine: Boolean, showsReceipt: Boolean, message: Message, content: @Composable () -> Unit) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        horizontalAlignment = if (isMine) Alignment.End else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Box(Modifier.padding(start = if (isMine) 48.dp else 0.dp, end = if (isMine) 0.dp else 48.dp)) { content() }
        if (showsReceipt && isMine) {
            val receipt = when {
                message.readAt != null -> tr("已读 %@", DateText.time(message.readAt))
                message.isDelivered -> tr("已送达")
                else -> tr("发送中")
            }
            Text(receipt, style = AppTheme.Typography.caption, color = if (message.isRead) colors.success else colors.inkTertiary)
        }
    }
}

// MARK: - 群聊

/** 群聊：球局群（确认后开放、赛后 48 小时关闭）和球群群聊 */
@Composable
fun GroupChatScreen(threadId: String) {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    val colors = AppTheme.colors
    val thread = messageManager.thread(threadId)
    val messages = messageManager.messages(threadId)
    val me = messageManager.currentUserId
    val listState = rememberLazyListState()

    DisposableEffect(threadId) {
        messageManager.openThread(threadId)
        onDispose { messageManager.closeThread(threadId) }
    }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1) }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(thread?.title ?: tr("群聊"), onBack = { env.router.pop() }) {
            when (val context = thread?.context) {
                is ThreadContext.Game -> IconButton(Sym.ticketFill, tr("查看球局")) { env.router.open(Route.Game(context.gameId)) }
                is ThreadContext.Group -> IconButton(Sym.person3Fill, tr("查看球群")) { env.router.open(Route.Group(context.groupId)) }
                null -> Unit
            }
        }
        MembersStrip(thread)
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth(),
            state = listState,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.md),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            itemsIndexed(messages, key = { _, message -> message.id }) { index, message ->
                GroupMessageRow(message, messages.getOrNull(index - 1), me)
            }
        }
        GroupInputBar(threadId, thread)
    }
}

@Composable
private fun MembersStrip(thread: MessageThread?) {
    val env = LocalEnv.current
    val members = thread?.participantIds.orEmpty().mapNotNull(env.messageManager::user)
    val label = tr("群成员 %lld 人", members.size)
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.xs)
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        members.take(12).forEachIndexed { index, member ->
            AvatarView(member, Modifier.offset(x = (-6 * index).dp).pressable { env.appState.showPlayer(member.id) }, size = 30.dp)
        }
        Text(
            tr("%lld 人", members.size), style = AppTheme.Typography.caption, color = AppTheme.colors.inkSecondary,
            modifier = Modifier.offset(x = (-6 * (members.take(12).size - 1).coerceAtLeast(0)).dp).padding(start = AppTheme.Spacing.md),
        )
    }
}

@Composable
private fun GroupMessageRow(message: Message, previous: Message?, me: String?) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val isMine = message.senderId == me
    if (message.kind == MessageKind.System || isMine) {
        MessageBubble(message, isMine)
        return
    }
    val sender = env.messageManager.user(message.senderId)
    val showsSender = previous?.senderId != message.senderId
    val mentionsContact = ContactInfoDetector.mentionsOffPlatformContact(message.content)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            if (showsSender && sender != null) {
                AvatarView(sender, Modifier.pressable { env.appState.showPlayer(sender.id) }, size = 32.dp)
            } else {
                Spacer(Modifier.width(32.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (showsSender) Text(sender?.nickname ?: tr("球友"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
                MessageBubble(message, isMine = false)
            }
        }
        if (mentionsContact) {
            Row(Modifier.padding(start = 40.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Symbol(Sym.exclamationmarkShieldFill, size = 11, tint = colors.danger)
                Text(tr("提到了站外联系方式，转账、代付要谨慎"), style = AppTheme.Typography.caption, color = colors.danger)
            }
        }
    }
}

@Composable
private fun GroupInputBar(threadId: String, thread: MessageThread?) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var draft by rememberSaveable(threadId) { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().background(colors.canvas)) {
        InsetDivider()
        Column(Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.sm)) {
            if (env.messageManager.canPost(threadId)) {
                MessageField(draft, { draft = it }, canSend = Message.validate(draft) == MessageValidation.Valid && !isSending) {
                    val text = draft
                    isSending = true
                    scope.launch {
                        try {
                            env.messageManager.sendGroup(text, threadId)
                            draft = ""
                        } catch (error: RemoteError) {
                            env.appState.showError(error)
                        } catch (error: BackendError) {
                            env.appState.showError(error)
                        }
                        isSending = false
                    }
                }
            } else {
                val closed = when (thread?.context) {
                    is ThreadContext.Game -> tr("群聊已关闭，想再约先加为球友")
                    is ThreadContext.Group -> tr("加入球群后才能在群里发言")
                    null -> tr("群聊已结束")
                }
                NoticeBanner(Sym.lockFill, closed, tint = colors.surfaceMuted)
            }
        }
    }
}

// MARK: - 通知中心

@Composable
fun NotificationsScreen() {
    val env = LocalEnv.current
    val inboxManager = env.inboxManager
    val colors = AppTheme.colors
    val unreadLabel = tr("未读")
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("通知"), onBack = { env.router.pop() }) {
            if (inboxManager.unreadCount > 0) TextAction(tr("全部已读"), { inboxManager.markRead() }, color = colors.ink)
        }
        RefreshEverything(Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                if (inboxManager.items.isEmpty()) EmptyStateView(Sym.bellSlash, tr("暂无通知"))
                inboxManager.items.forEach { item ->
                    Row(
                        Modifier.fillMaxWidth().pressable(scale = 0.98f) { env.openInboxItem(item) }
                            .sticker(
                                if (item.isRead) colors.surfaceMuted else colors.surface, radius = AppTheme.Radius.md,
                                shadow = if (item.isRead) AppTheme.Elevation.none else androidx.compose.ui.unit.DpOffset(0.dp, 3.dp),
                            )
                            .padding(AppTheme.Spacing.md)
                            .semantics(mergeDescendants = true) {},
                        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                        verticalAlignment = Alignment.Top,
                    ) {
                        IconTile(item.kind.icon, fill = item.kind.tint(colors), size = 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(item.title, style = AppTheme.Typography.headline, color = colors.ink)
                            Text(item.body, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                            Text(DateText.compact(item.createdAt), style = AppTheme.Typography.caption, color = colors.inkTertiary)
                        }
                        if (!item.isRead) {
                            Dot(colors.dangerFill, 9.dp, Modifier.padding(top = 6.dp).semantics { contentDescription = unreadLabel })
                        }
                    }
                }
            }
        }
    }
}
