package com.badie.app.features.home

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.backend.DayCandidate
import com.badie.app.backend.FriendRequestState
import com.badie.app.backend.NearbyPlayer
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.CoverCard
import com.badie.app.design.LevelBadge
import com.badie.app.design.NicknameText
import com.badie.app.design.NoShowPill
import com.badie.app.design.ReliableBadge
import com.badie.app.design.RoundActionLabel
import com.badie.app.design.Sym
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.Room
import com.badie.app.models.User
import com.badie.app.models.UsualTimeText
import com.badie.app.models.WindowText
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import kotlinx.coroutines.launch

// 对应 iPhone 的 Features/Home/NearbyViews.swift（邀请局的页面 InviteRoomView、定时间 SetGameTimeSheet 归房间和球局那两块）

// MARK: - 卡片

/** 附近的人：和按天的卡片同一个样子，只是不写时间，左上角写 TA 常去的球馆，底部是常有空的时间 */
@Composable
fun NearbyCardView(
    user: User?,
    card: NearbyPlayer,
    modifier: Modifier = Modifier,
    /** 左上角显示的球馆（选了球馆筛选时是选的那家） */
    venue: DayCandidate.Place? = null,
    onProfile: (() -> Unit)? = null,
    /** 点了 TA 的某段空闲时间：约 TA 这一段最近的一次 */
    onInvite: ((RecurringTimeSlot) -> Unit)? = null,
) {
    // “3.2 公里 · 常去 X”（不知道距离就只写球馆）
    val place = venue ?: card.venues.firstOrNull()
    val pill = place?.let { listOfNotNull(it.km?.let { km -> DistanceFormatter.string(km) }, tr("常去 %@", it.name)).joinToString(" · ") }
    // “双打 · 靠谱”
    val line = listOfNotNull(card.preferredMode?.title, if (card.recentNoShows == 0) tr("靠谱") else null).joinToString(" · ")
    CoverCard(user, pill, line, modifier, onProfile) {
        if (card.recentNoShows > 0) NoShowPill(card.recentNoShows)
        if (card.usualTimes.isNotEmpty()) UsualTimeChips(card.usualTimes, onInvite)
    }
}

/** 某天的约球请求：时间、单打双打写在左上角，下面一行是约在哪家 */
@Composable
fun DayCardView(user: User?, mode: String, startsAt: Long, endsAt: Long, venues: List<String>, recentNoShows: Int, modifier: Modifier = Modifier, onProfile: (() -> Unit)? = null) {
    // “周六 14:00–17:00 · 单打”
    val pill = "${DateText.weekday(startsAt)} ${DateText.time(startsAt)}–${DateText.time(endsAt)} · $mode"
    val line = listOfNotNull(venues.firstOrNull(), if (recentNoShows == 0) tr("靠谱") else null).joinToString(" · ")
    CoverCard(user, pill, line, modifier, onProfile) {
        if (recentNoShows > 0) NoShowPill(recentNoShows)
    }
}

/** TA 的空闲时间：最近的两段做成小胶囊，多了“+N”。点一个就约这一段 */
@Composable
fun UsualTimeChips(slots: List<RecurringTimeSlot>, onTap: ((RecurringTimeSlot) -> Unit)?) {
    val colors = AppTheme.colors
    val sorted = UsualTimeText.sortedByNext(slots)
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        for (slot in sorted.take(2)) {
            val text = UsualTimeText.chip(slot)
            val label = tr("约 %@", text)
            Text(
                text, style = AppTheme.Typography.footnoteBold, color = colors.onAccent, maxLines = 1,
                modifier = Modifier
                    .pressable(enabled = onTap != null) { onTap?.invoke(slot) }
                    .semantics { contentDescription = label }
                    .defaultMinSize(minHeight = 32.dp)
                    .sticker(colors.lime, radius = 16.dp, shadow = AppTheme.Elevation.none, stroke = colors.onAccent, strokeWidth = 1.5.dp)
                    .padding(horizontal = 10.dp, vertical = 7.dp),
            )
        }
        if (sorted.size > 2) TagPill("+${sorted.size - 2}", fill = colors.lime)
    }
}

// MARK: - ★ 加球友

/**
 * ★ 加球友：不占每天约人的名额，也不翻到下一张。已是球友就发消息，TA 申请过我就同意，已申请就说一声。
 * 关系看 FriendManager，缓存里还没有时用服务器给的（[isFriend]、[request]）
 */
@Composable
fun FriendStarButton(userId: String, isFriend: Boolean = false, request: FriendRequestState? = null) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    var requested by remember(userId) { mutableStateOf(false) }
    var becameFriends by remember(userId) { mutableStateOf(false) }
    var isWorking by remember(userId) { mutableStateOf(false) }
    val status = when {
        isFriend || becameFriends || friendManager.isFriend(userId) -> 0
        requested || request == FriendRequestState.Sent || friendManager.hasPendingRequest(userId) -> 1
        request == FriendRequestState.Received || friendManager.incomingRequest(userId) != null -> 2
        else -> 3
    }
    val label = when (status) {
        0 -> tr("发消息")
        1 -> tr("已申请")
        2 -> tr("通过好友申请")
        else -> tr("加球友")
    }
    RoundActionLabel(
        if (status == 0) Sym.bubbleLeftFill else Sym.starFill, AppTheme.colors.butter,
        Modifier
            .alpha(if (status == 1) 0.45f else 1f)
            .pressable(enabled = !isWorking) {
                when (status) {
                    0 -> env.router.open(Route.Chat(userId), MainTab.Messages)
                    1 -> env.appState.showToast(L10n.tr("已申请，等待通过"))
                    else -> {
                        // TA 也申请过我：服务器上再申请一次就是同意
                        isWorking = true
                        scope.launch {
                            try {
                                val incoming = friendManager.incomingRequest(userId)
                                if (incoming != null) {
                                    friendManager.respond(incoming, accept = true)
                                    becameFriends = true
                                    env.appState.showToast(L10n.tr("已添加为球友"), Toast.Style.Success)
                                } else {
                                    friendManager.sendRequest(userId)
                                    if (friendManager.isFriend(userId) || request == FriendRequestState.Received) {
                                        becameFriends = true
                                        env.appState.showToast(L10n.tr("已添加为球友"), Toast.Style.Success)
                                    } else {
                                        requested = true
                                        env.appState.showToast(L10n.tr("申请已发送"), Toast.Style.Success)
                                    }
                                }
                                haptics.success()
                            } catch (error: RemoteError) {
                                env.appState.showError(error)
                            } finally {
                                isWorking = false
                            }
                        }
                    }
                }
            }
            .semantics { contentDescription = label },
    )
}

// MARK: - 第一次约人前：让附近的人也能看到你 / 加一张照片

enum class InvitePromptKind {
    /** 没打开“在同馆常客里显示我” */
    Visibility,
    /** 没有卡片背景照片 */
    Photo,
}

@Composable
fun InvitePromptSheet(kind: InvitePromptKind, onConfirm: () -> Unit, onCancel: () -> Unit, onPhoto: (android.net.Uri) -> Unit = {}) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) onPhoto(uri) }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(
            if (kind == InvitePromptKind.Visibility) tr("先让附近的人也能看到你") else tr("加一张照片？"),
            style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl).semantics { heading() },
        )
        val me = env.appState.currentUser
        if (kind == InvitePromptKind.Photo && me != null) {
            Row(
                Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                AvatarView(me, size = 48.dp)
                Text(tr("别人刷到你时看到的就是这张卡"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
            }
        }
        Spacer(Modifier.padding(top = AppTheme.Spacing.sm))
        if (kind == InvitePromptKind.Photo) {
            BrutalButton(tr("选照片"), { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
            BrutalButton(tr("先不加"), onConfirm, kind = ButtonKind.Secondary)
        } else {
            BrutalButton(tr("打开"), onConfirm)
            BrutalButton(tr("不了"), onCancel, kind = ButtonKind.Secondary)
        }
    }
}

// MARK: - 邀请的说法

object InviteText {
    /** 标题说现在这个时间是谁提的：第一次是“<TA>约你打球”或“你约了<TA>”，换过时间的是“<TA>想换个时间”或“你想换个时间” */
    fun title(room: Room, me: String?, name: (String) -> String): String {
        val invite = room.invite ?: return ""
        val other = name(invite.other(me))
        // 换时间是轮流的：偶数次是发邀请的人提的时间，奇数次是收到的人提的
        val mine = (if (invite.rounds % 2 == 0) invite.fromId else invite.toId) == me
        if (invite.rounds == 0) return if (mine) L10n.tr("你约了%@", other) else L10n.tr("%@约你打球", other)
        return if (mine) L10n.tr("你想换个时间") else L10n.tr("%@想换个时间", other)
    }

    /** 约人时的错误：说发生了什么 */
    fun error(error: Throwable): String {
        val code = (error as? RemoteError.Server)?.code ?: return error.message ?: L10n.tr("出了点问题，请重试。")
        return when (code) {
            "invite_limit" -> L10n.tr("今天的 10 个用完了，明天再来")
            "already_invited" -> L10n.tr("你们之间已经有一个邀请了")
            "not_visible" -> L10n.tr("先在设置里打开“在同馆常客里显示我”")
            "invalid_window", "invalid_slot" -> L10n.tr("这个时间来不及了")
            "overlapping" -> L10n.tr("这个时间你已经有球局或待确认的约球了。")
            "not_your_turn" -> L10n.tr("在等对方回复")
            "invite_expired" -> L10n.tr("这个邀请已经过期了")
            "too_late" -> L10n.tr("来不及了，换个时间吧")
            "time_already_set" -> L10n.tr("时间已经定好了")
            else -> error.message
        }
    }
}

/** 对方是谁：头像、昵称、等级 */
@Composable
fun InvitePersonRow(user: User?) {
    val colors = AppTheme.colors
    Row(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        if (user != null) {
            AvatarView(user, size = 52.dp)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NicknameText(user, style = AppTheme.Typography.headline)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    LevelBadge(user.displayTier)
                    if (user.isReliable) ReliableBadge()
                }
            }
        }
    }
}

/** 约的时间和球馆：“周六 11/15 · 下午” / “14:00–18:00 之间打 2 小时 · 球馆” */
@Composable
fun InviteSlotCard(room: Room) {
    val colors = AppTheme.colors
    val window = room.window
    val slot = room.slot
    val headline = when {
        window != null -> WindowText.headlineWithDate(window)
        slot != null -> "${DateText.weekday(slot.startTime)} ${DateText.shortDay(slot.startTime)}"
        else -> ""
    }
    val detail = window?.let { WindowText.caption(it) } ?: slot?.formattedTimeRange()
    Column(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(headline, style = AppTheme.Typography.headline, color = colors.ink)
        Text(listOfNotNull(room.mode.title, detail, room.court?.name).joinToString(" · "), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
    }
}

// MARK: - 收到的邀请：一次一个，不了 / 换个时间 / 好

/** 轮到我回的邀请（从通知打开的半屏里一个一个回）。回完一个调 [onAnswered]，说好的带球局 ID */
@Composable
fun InviteAnswerSheet(invites: List<Room>, onAnswered: (Room, String?) -> Unit, onCounter: (Room) -> Unit, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    var answered by remember { mutableStateOf(setOf<String>()) }
    var isWorking by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    val me = env.appState.currentUser?.id
    val room = invites.firstOrNull { it.id !in answered }
    val invite = room?.invite
    fun answer(target: Room, accept: Boolean) {
        isWorking = true
        errorText = null
        scope.launch {
            try {
                val gameId = manager.nearbyApi.respondInvite(target.id, accept)
                if (accept) haptics.success() else haptics.selection()
                answered = answered + target.id
                onAnswered(target, gameId)
                // 说好了去球局；回完了也关掉
                if (accept || invites.none { it.id !in answered }) onDismiss()
            } catch (error: RemoteError) {
                errorText = InviteText.error(error)
            } finally {
                isWorking = false
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        if (room != null && invite != null) {
            Text(
                InviteText.title(room, me) { manager.user(it)?.nickname ?: "" }, style = AppTheme.Typography.title2, color = colors.ink,
                modifier = Modifier.padding(top = AppTheme.Spacing.xl).semantics { heading() },
            )
            InvitePersonRow(manager.user(invite.other(me)))
            InviteSlotCard(room)
            errorText?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = colors.danger) }
            Row(Modifier.padding(top = AppTheme.Spacing.sm), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalButton(tr("不了"), { answer(room, false) }, Modifier.weight(1f), kind = ButtonKind.Secondary, enabled = !isWorking)
                BrutalButton(tr("换个时间"), { onCounter(room) }, Modifier.weight(1f), kind = ButtonKind.Secondary, enabled = !isWorking)
                BrutalButton(tr("好"), { answer(room, true) }, Modifier.weight(1f), enabled = !isWorking)
            }
        }
    }
}

