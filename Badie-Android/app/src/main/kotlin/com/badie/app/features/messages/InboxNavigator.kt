package com.badie.app.features.messages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.badie.app.design.AppTheme
import com.badie.app.design.BadieColors
import com.badie.app.design.BrutalButton
import com.badie.app.design.IconTile
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.pressable
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.InboxItem
import com.badie.app.remote.RemoteError
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import kotlinx.coroutines.launch

// 通知：图标、颜色，点开去哪；球局没了的重要通知弹窗；轮询。
// 对应 iPhone 的 Features/Social/InboxNavigator.swift，和 App/MainTabView.swift 里 showUrgent 那部分

val InboxItem.Kind.icon: SymbolId
    get() = when (this) {
        InboxItem.Kind.FriendRequest, InboxItem.Kind.FriendAccepted -> Sym.personBadgePlus
        InboxItem.Kind.RoomInvite, InboxItem.Kind.RoomJoined, InboxItem.Kind.WaitlistPromoted -> Sym.ticketFill
        InboxItem.Kind.Kicked, InboxItem.Kind.RoomClosed -> Sym.doorLeftHandOpen
        InboxItem.Kind.SurveyDue, InboxItem.Kind.ReviewReceived -> Sym.starFill
        InboxItem.Kind.GameConfirmed, InboxItem.Kind.GameReminder -> Sym.sportscourtFill
        InboxItem.Kind.MatchOffer -> Sym.boltFill
        InboxItem.Kind.MatchUpdate -> Sym.arrowTriangle2Circlepath
        InboxItem.Kind.MessageRequest -> Sym.envelopeBadgeFill
        InboxItem.Kind.GroupUpdate -> Sym.person3Fill
        InboxItem.Kind.Rematch -> Sym.arrowUturnLeftCircleFill
        InboxItem.Kind.GameCancelled -> Sym.xmarkCircleFill
        InboxItem.Kind.System -> Sym.megaphoneFill
        InboxItem.Kind.Challenge -> Sym.flag2CrossedFill
        InboxItem.Kind.ResultUpdate -> Sym.checkmarkSealFill
        InboxItem.Kind.InviteCounter -> Sym.clockArrowCirclepath
        InboxItem.Kind.InviteDeclined -> Sym.handRaisedFill
        InboxItem.Kind.GameTimeSet -> Sym.clockBadgeCheckmark
    }

fun InboxItem.Kind.tint(colors: BadieColors): Color = when (this) {
    InboxItem.Kind.FriendRequest, InboxItem.Kind.FriendAccepted -> colors.lavender
    InboxItem.Kind.RoomInvite, InboxItem.Kind.RoomJoined, InboxItem.Kind.WaitlistPromoted -> colors.peach
    InboxItem.Kind.Kicked, InboxItem.Kind.RoomClosed, InboxItem.Kind.GameCancelled -> colors.surfaceMuted
    InboxItem.Kind.SurveyDue, InboxItem.Kind.ReviewReceived -> colors.pink
    InboxItem.Kind.GameConfirmed, InboxItem.Kind.GameReminder, InboxItem.Kind.MatchOffer -> colors.lime
    InboxItem.Kind.MatchUpdate, InboxItem.Kind.MessageRequest -> colors.butter
    InboxItem.Kind.GroupUpdate -> colors.lavender
    InboxItem.Kind.Rematch -> colors.mint
    InboxItem.Kind.System -> colors.sky
    InboxItem.Kind.Challenge -> colors.peach
    InboxItem.Kind.ResultUpdate -> colors.mint
    InboxItem.Kind.InviteCounter -> colors.peach
    InboxItem.Kind.InviteDeclined -> colors.surfaceMuted
    InboxItem.Kind.GameTimeSet -> colors.lime
}

/** 球局没了：打开 App 时直接弹窗告诉，点“知道了”才算看过 */
val InboxItem.Kind.isUrgent: Boolean
    get() = this == InboxItem.Kind.GameCancelled || this == InboxItem.Kind.Kicked || this == InboxItem.Kind.RoomClosed

/** 点开一条通知：标为已读，再打开对应的页面（通知中心和重要通知弹窗共用） */
fun AppEnvironment.openInboxItem(item: InboxItem) {
    inboxManager.markRead(item)
    val id = item.relatedId
    when (item.kind) {
        InboxItem.Kind.FriendRequest, InboxItem.Kind.FriendAccepted, InboxItem.Kind.Rematch -> id?.let(appState::showPlayer)
        // 正式后端给的是房间 ID
        InboxItem.Kind.RoomInvite, InboxItem.Kind.RoomJoined, InboxItem.Kind.WaitlistPromoted -> id?.let { router.open(Route.Room(it)) }
        // 正式后端的链接里是球局 ID，不是待评价的 ID：去评价列表
        InboxItem.Kind.SurveyDue -> router.open(Route.Surveys)
        InboxItem.Kind.GameConfirmed, InboxItem.Kind.GameCancelled, InboxItem.Kind.GameReminder, InboxItem.Kind.ResultUpdate, InboxItem.Kind.GameTimeSet ->
            id?.let { router.open(Route.Game(it)) }
        InboxItem.Kind.ReviewReceived -> router.select(MainTab.Profile)
        // 找到搭子、匹配进展：打开那个请求的匹配流程
        InboxItem.Kind.MatchOffer, InboxItem.Kind.MatchUpdate ->
            if (id != null) matchManager.openTicket(id) else matchManager.isFlowPresented = true
        InboxItem.Kind.MessageRequest -> id?.let { router.open(Route.Chat(it), MainTab.Messages) }
        InboxItem.Kind.GroupUpdate -> id?.let { router.open(Route.Group(it)) }
        // 接受后 relatedId 是球局 ID，否则是挑战 ID
        InboxItem.Kind.Challenge ->
            if (id != null && friendManager.cache.games.any { it.id == id }) router.open(Route.Game(id)) else router.open(Route.Challenges)
        // 对方想换个时间：打开邀请（不了 / 换个时间 / 好）
        InboxItem.Kind.InviteCounter -> id?.let { router.open(Route.Room(it)) }
        // 这次来不了：回到发现页，再约别人
        InboxItem.Kind.InviteDeclined -> router.showRoot(MainTab.Home)
        InboxItem.Kind.Kicked, InboxItem.Kind.RoomClosed, InboxItem.Kind.System -> Unit
    }
}

/**
 * 主界面上和球友、消息有关的后台工作，放在 shell/MainTabView.kt 里：
 * - 回到前台：马上重拉，并开始每 15 秒轮询（球友、会话、通知、球群）；退到后台停
 * - 回到前台：读我的爽约记录（有新的就弹说明，见 AppState.showsStrikes）
 * - 球局没了（取消、被移出、关闭）的通知没读：弹窗，点“知道了”才算看过
 */
@Composable
fun SocialOverlays() {
    val env = LocalEnv.current
    var urgentItems by remember { mutableStateOf<List<InboxItem>>(emptyList()) }
    // 这次打开 App 已经弹过的（划掉不算看过，下次回到前台再弹）
    var urgentShown by remember { mutableStateOf<Set<String>>(emptySet()) }
    val scope = rememberCoroutineScope()

    fun showUrgent() {
        val pending = env.inboxManager.items.filter { !it.isRead && it.kind.isUrgent && it.id !in urgentShown }
        if (pending.isEmpty() || urgentItems.isNotEmpty()) return
        urgentShown = urgentShown + pending.map { it.id }
        urgentItems = pending
    }

    LifecycleResumeEffect(env) {
        urgentShown = emptySet()
        showUrgent()
        env.messageManager.refreshNow()
        env.friendManager.startPolling()
        env.messageManager.startPolling()
        env.inboxManager.startPolling()
        env.groupManager.startPolling()
        val strikes = scope.launch {
            try {
                env.friendManager.refreshStrikes()
            } catch (_: RemoteError) {
            }
        }
        onPauseOrDispose {
            strikes.cancel()
            env.friendManager.stopPolling()
            env.messageManager.stopPolling()
            env.inboxManager.stopPolling()
            env.groupManager.stopPolling()
        }
    }
    LaunchedEffect(env.inboxManager.items) { showUrgent() }

    if (urgentItems.isNotEmpty()) {
        SheetScaffold(onDismiss = { urgentItems = emptyList() }) {
            UrgentNoticeSheet(
                urgentItems,
                onOpen = { item ->
                    urgentItems = emptyList()
                    env.openInboxItem(item)
                },
                onDone = {
                    urgentItems.forEach(env.inboxManager::markRead)
                    urgentItems = emptyList()
                },
            )
        }
    }
}

/** 球局没了（取消、被移出、关闭）：打开 App 时直接弹出，点“知道了”才算看过 */
@Composable
fun UrgentNoticeSheet(items: List<InboxItem>, onOpen: (InboxItem) -> Unit, onDone: () -> Unit) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(
            if (items.size == 1) items[0].title else tr("%lld 场球局有变化", items.size),
            style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl),
        )
        Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            items.forEach { item ->
                Row(
                    Modifier.fillMaxWidth().pressable(scale = 0.98f) { onOpen(item) }.sticker(colors.surface, radius = AppTheme.Radius.lg)
                        .padding(AppTheme.Spacing.lg).semantics(mergeDescendants = true) {},
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconTile(item.kind.icon, fill = item.kind.tint(colors), size = 40.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        if (items.size > 1) Text(item.title, style = AppTheme.Typography.headline, color = colors.ink)
                        Text(item.body, style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
                    }
                    Symbol(Sym.chevronRight, size = 14, tint = colors.inkTertiary)
                }
            }
        }
        BrutalButton(tr("知道了"), onDone)
    }
}
