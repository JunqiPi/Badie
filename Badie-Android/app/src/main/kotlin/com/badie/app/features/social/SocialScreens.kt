package com.badie.app.features.social

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.InfoRow
import com.badie.app.design.InsetDivider
import com.badie.app.design.LevelBadge
import com.badie.app.design.NicknameText
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.FriendRequest
import com.badie.app.models.User
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 球友列表、添加球友、加球友链接、屏蔽名单。
// 对应 iPhone 的 Features/Messages/MessagesView.swift（FriendsContent、FriendsView、FriendRequestRow、AddFriendView、FriendActionButton）、
// Features/Social/FriendLinkSheet.swift、Features/Profile/SettingsView.swift 的 BlockedUsersView

/** 独立页面版本（从“我的”进入） */
@Composable
fun FriendsScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("我的球友"), onBack = { router.pop() })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = AppTheme.Spacing.xxl)) {
            FriendsContent()
        }
    }
}

/** 球友列表（含好友申请）：消息页的“球友”和“我的球友”页共用 */
@Composable
fun FriendsContent() {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val colors = AppTheme.colors
    var query by remember { mutableStateOf("") }
    Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
        val requests = friendManager.incomingRequests
        if (requests.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                SectionTitle(tr("好友申请"), detail = "${requests.size}")
                requests.forEach { FriendRequestRow(it) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            SectionTitle(tr("我的球友"), detail = tr("%lld 人", friendManager.friends.size), actionTitle = tr("添加")) {
                env.router.open(Route.AddFriend)
            }
            if (friendManager.friends.size > 5) SearchField(query, { query = it }, tr("搜索球友"))
            val list = friendManager.searchFriends(query)
            if (list.isEmpty()) {
                EmptyStateView(Sym.person2, if (query.isEmpty()) tr("还没有球友") else tr("没有找到"), Modifier.card())
            } else {
                Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg)) {
                    list.forEachIndexed { index, friend ->
                        if (index > 0) InsetDivider(Modifier.padding(start = 60.dp))
                        PlayerRow(friend, onClick = { env.appState.showPlayer(friend.id) }) {
                            val label = tr("给 %@ 发消息", friend.nickname)
                            Box(
                                Modifier.size(44.dp).pressable { env.router.open(Route.Chat(friend.id)) }.semantics { contentDescription = label },
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    Modifier.size(36.dp).sticker(colors.lavender, radius = 18.dp, shadow = AppTheme.Elevation.none, strokeWidth = 1.5.dp),
                                    contentAlignment = Alignment.Center,
                                ) { Symbol(Sym.bubbleLeftFill, size = 15, tint = colors.onAccent) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun FriendRequestRow(request: FriendRequest) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var isWorking by remember { mutableStateOf(false) }
    val user = friendManager.user(request.fromUserId) ?: return
    val accepted = tr("已添加为球友")

    fun respond(accept: Boolean) {
        scope.launch {
            isWorking = true
            try {
                friendManager.respond(request, accept)
                if (accept) env.appState.showToast(accepted, Toast.Style.Success)
            } catch (error: RemoteError) {
                env.appState.showError(error)
            }
            isWorking = false
        }
    }

    Column(Modifier.card(padding = AppTheme.Spacing.md), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(
            Modifier.fillMaxWidth().pressable(scale = 1f) { env.appState.showPlayer(user.id) },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            AvatarView(user, size = 46.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(user.nickname, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1)
                    LevelBadge(user.displayTier, showsName = false, compact = true)
                }
                Text(
                    if (request.note.isEmpty()) tr("想加你为球友") else "“${request.note}”",
                    style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 2,
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            BrutalButton(tr("忽略"), { respond(false) }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small, enabled = !isWorking)
            BrutalButton(tr("通过"), { respond(true) }, Modifier.weight(1f), size = ButtonSize.Small, enabled = !isWorking)
        }
    }
}

// MARK: - 添加球友

@Composable
fun AddFriendScreen() {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<User>>(emptyList()) }
    var searchError by remember { mutableStateOf<String?>(null) }
    var showsFriendLink by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        try {
            friendManager.refreshGames()
            friendManager.refreshRegulars()
        } catch (_: RemoteError) {
        }
    }
    LaunchedEffect(query) {
        val text = query.trim()
        searchError = null
        if (text.length < 2) {
            results = emptyList()
            return@LaunchedEffect
        }
        // 停止输入 0.3 秒后再搜（服务器限速）
        delay(300)
        try {
            results = friendManager.findPlayers(text)
        } catch (error: RemoteError) {
            searchError = error.message
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("添加球友"), onBack = { env.router.pop() })
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            SearchField(query, { query = it }, tr("昵称或 昵称#1234"))
            if (env.appState.currentUser?.friendLink != null) {
                InfoRow(
                    Sym.qrcode, tr("我的加球友链接"),
                    Modifier.pressable(scale = 0.98f) {
                        haptics.tap()
                        showsFriendLink = true
                    }.sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg),
                    tint = colors.lime,
                ) { Symbol(Sym.chevronRight, size = 14, tint = colors.inkTertiary) }
            }
            val error = searchError
            if (error != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(Sym.exclamationmarkCircleFill, size = 13, tint = colors.danger)
                    Text(error, style = AppTheme.Typography.footnoteBold, color = colors.danger)
                }
            } else if (query.isNotEmpty()) {
                PlayerSection(tr("搜索结果"), results, tr("没有找到“%@”", query))
            }
            PlayerSection(tr("一起打过球的人"), friendManager.recentCoPlayers(), tr("还没有"))
            PlayerSection(
                tr("同馆常客"), friendManager.regulars, tr("还没有"),
                rules = listOf(tr("设了常去球馆，这里会显示公开了自己是常客的球友。")),
            )
        }
    }
    if (showsFriendLink) {
        SheetScaffold(onDismiss = { showsFriendLink = false }, fullHeight = true) { FriendLinkSheet() }
    }
}

@Composable
private fun PlayerSection(title: String, users: List<User>, emptyText: String, rules: List<String>? = null) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(title, style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
            if (rules != null) RulesButton(title, rules)
        }
        if (users.isEmpty()) {
            Text(emptyText, style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
        } else {
            Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg)) {
                users.forEachIndexed { index, user ->
                    if (index > 0) InsetDivider(Modifier.padding(start = 60.dp))
                    PlayerRow(user, subtitle = subtitle(user), onClick = { env.appState.showPlayer(user.id) }) { FriendActionButton(user.id) }
                }
            }
        }
    }
}

@Composable
private fun subtitle(user: User): String {
    val friendManager = LocalEnv.current.friendManager
    val parts = mutableListOf(user.tagText)
    friendManager.distance(user.id)?.let { parts += DistanceFormatter.approximate(it) }
    parts += user.publicSummary
    return parts.joinToString(" · ")
}

/** 加好友按钮（根据关系显示不同状态） */
@Composable
fun FriendActionButton(userId: String) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var isWorking by remember { mutableStateOf(false) }
    val sent = tr("申请已发送")
    val incoming = friendManager.incomingRequest(userId)
    when {
        friendManager.isFriend(userId) -> TagPill(tr("已是球友"), icon = Sym.checkmark, fill = colors.mint)
        friendManager.hasPendingRequest(userId) -> TagPill(tr("等待通过"), fill = colors.surfaceMuted, foreground = colors.inkSecondary)
        incoming != null -> BrutalButton(tr("通过申请"), {
            scope.launch {
                try {
                    friendManager.respond(incoming, true)
                } catch (_: RemoteError) {
                }
            }
        }, size = ButtonSize.Small, fullWidth = false)
        else -> BrutalButton({
            scope.launch {
                isWorking = true
                try {
                    friendManager.sendRequest(userId)
                    env.appState.showToast(sent, Toast.Style.Success)
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
                isWorking = false
            }
        }, size = ButtonSize.Small, fullWidth = false, enabled = !isWorking) {
            Symbol(Sym.plus, size = 12)
            Spacer(Modifier.size(4.dp))
            Text(tr("加球友"))
        }
    }
}

// MARK: - 加球友链接

/**
 * 我的加球友链接：发给对方，或者重置（旧链接失效）。
 * iPhone 这里还有一个二维码，安卓要加二维码的依赖，先只显示链接（可以复制）
 */
@Composable
fun FriendLinkSheet() {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val android = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmsReset by remember { mutableStateOf(false) }
    var isResetting by remember { mutableStateOf(false) }
    val user = env.appState.currentUser
    val link = user?.friendLink
    val created = tr("新链接已生成")
    val copied = tr("已复制")
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
    ) {
        if (user != null && link != null) {
            Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                NicknameText(user, Modifier.weight(1f, fill = false), style = AppTheme.Typography.title2)
                RulesButton(
                    tr("加球友链接"),
                    listOf(tr("拿到这个链接的人都能加你。"), tr("当面扫码，或者发给对方。"), tr("重置后，旧链接和二维码会失效。")),
                )
            }
            Column(
                Modifier.fillMaxWidth().sticker(androidx.compose.ui.graphics.Color.White, radius = AppTheme.Radius.lg)
                    .pressable(scale = 0.98f) {
                        copyText(android, link)
                        env.appState.showToast(copied, Toast.Style.Success)
                    }
                    .padding(AppTheme.Spacing.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                Symbol(Sym.link, size = 28, tint = colors.onAccent)
                Text(link, style = AppTheme.Typography.subheadlineBold, color = colors.onAccent, textAlign = TextAlign.Center)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Symbol(Sym.docOnDoc, size = 12, tint = colors.onAccent.copy(alpha = 0.6f))
                    Text(tr("复制"), style = AppTheme.Typography.caption, color = colors.onAccent.copy(alpha = 0.6f))
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalButton({ shareText(android, link) }) {
                    Symbol(Sym.paperplaneFill, size = 16)
                    Spacer(Modifier.size(AppTheme.Spacing.sm))
                    Text(tr("发给好友"))
                }
                TextAction(tr("重置链接"), { confirmsReset = true }, enabled = !isResetting)
            }
        }
    }
    if (confirmsReset) {
        ConfirmDialog(tr("重置加球友链接？"), tr("旧链接和二维码会失效"), tr("重置链接"), onDismiss = { confirmsReset = false }) {
            isResetting = true
            scope.launch {
                try {
                    env.friendManager.resetFriendLink()
                    env.appState.showToast(created, Toast.Style.Success)
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
                isResetting = false
            }
        }
    }
}

// MARK: - 屏蔽名单

@Composable
fun BlockedUsersScreen() {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    val colors = AppTheme.colors
    val unblocked = tr("已解除屏蔽")
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("屏蔽名单"), onBack = { env.router.pop() })
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            val blocked = messageManager.blockedUsers
            if (blocked.isEmpty()) EmptyStateView(Sym.handRaised, tr("没有屏蔽任何人"), tint = colors.mint)
            blocked.forEach { item ->
                Row(
                    Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    messageManager.user(item.blockedUserId)?.let { user ->
                        AvatarView(user, Modifier.pressable { env.appState.showPlayer(user.id) }, size = 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(user.nickname, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1)
                            Text(tr("屏蔽于 %@", DateText.compact(item.blockedAt)), style = AppTheme.Typography.caption, color = colors.inkSecondary)
                        }
                    } ?: Spacer(Modifier.weight(1f))
                    BrutalButton(tr("解除"), {
                        messageManager.unblock(item.blockedUserId)
                        env.appState.showToast(unblocked)
                    }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
                }
            }
        }
    }
}
