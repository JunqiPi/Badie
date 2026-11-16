package com.badie.app.features.rooms

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.layout.layout
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.badie.app.backend.RoomDraft
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.BrutalTextField
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.FitText
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InfoRow
import com.badie.app.design.InsetDivider
import com.badie.app.design.LevelBadge
import com.badie.app.design.LoadingDots
import com.badie.app.design.MenuRow
import com.badie.app.design.NoticeBanner
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.features.games.BadieSwitch
import com.badie.app.features.games.ConfirmAlert
import com.badie.app.features.games.Flow
import com.badie.app.features.games.FormGroup
import com.badie.app.features.games.RoomNotice
import com.badie.app.features.games.SystemActions
import com.badie.app.features.games.distanceText
import com.badie.app.features.games.opensProfile
import com.badie.app.features.games.rememberNow
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.CostSplit
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.PlayEvent
import com.badie.app.models.Room
import com.badie.app.models.RoomParticipant
import com.badie.app.models.RoomStatus
import com.badie.app.models.RoomTag
import com.badie.app.models.RoomVisibility
import com.badie.app.models.TimeSlot
import com.badie.app.models.Venue
import com.badie.app.models.title
import com.badie.app.models.zoned
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 房间：房间页、发起、输入房间码、附近球局。对应 iPhone 的 Features/Rooms/*.swift
// 入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面）

// MARK: - 房间页

@Composable
fun RoomScreen(id: String) {
    val env = LocalEnv.current
    val manager = env.roomManager
    val room = manager.room(id)
    val context = LocalContext.current
    // 打开时拉一次，之后每 15 秒刷新（谁加入了、开局了没有）
    LaunchedEffect(id) {
        while (true) {
            try {
                manager.load(id)
            } catch (_: RemoteError) {
            }
            delay(15_000)
        }
    }
    RoomNotice()
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(if (room?.visibility == RoomVisibility.PublicListing) tr("公开球局") else tr("私密房间"), onBack = { env.router.pop() }) {
            if (room != null && room.code.isNotEmpty()) {
                IconButton(Sym.squareAndArrowUp, tr("分享房间")) { SystemActions.share(context, room.inviteText()) }
            }
        }
        if (room != null) {
            RoomLobby(room)
        } else {
            Spacer(Modifier.weight(1f))
            EmptyStateView(Sym.doorLeftHandClosed, tr("房间不存在或已关闭"))
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun ColumnScope.RoomLobby(room: Room) {
    val env = LocalEnv.current
    val me = env.appState.currentUser?.id ?: ""
    val scope = rememberCoroutineScope()
    var showsInvite by remember { mutableStateOf(false) }
    var showsEdit by remember { mutableStateOf(false) }
    var kickTarget by remember { mutableStateOf<RoomParticipant?>(null) }
    var showsLeave by remember { mutableStateOf(false) }
    val isOwner = room.ownerId == me
    RefreshEverything(Modifier.weight(1f)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            StatusBanner(room)
            if (room.code.isNotEmpty()) CodeCard(room)
            DetailsCard(room, isOwner) { showsEdit = true }
            SeatsSection(room, me, isOwner, onInvite = { showsInvite = true }, onKick = { kickTarget = it })
            if (room.waitlist.isNotEmpty()) WaitlistSection(room, me)
            if (room.contains(me) && room.invitedUserIds.isNotEmpty()) InvitedSection(room)
        }
    }
    if (room.status.isOpen) Footer(room, me, isOwner) { showsLeave = true }
    if (showsInvite) {
        BadieSheet(onDismiss = { showsInvite = false }) { dismiss ->
            FriendPickerSheet(
                tr("邀请好友"), room.openSeats, (room.participants.map { it.userId } + room.invitedUserIds).toSet(),
                onConfirm = { ids ->
                    dismiss()
                    if (ids.isNotEmpty()) {
                        scope.launch {
                            try {
                                env.roomManager.invite(ids, room)
                                env.appState.showToast(L10n.tr("邀请已发送"), Toast.Style.Success)
                            } catch (error: RemoteError) {
                                env.appState.showError(error)
                            }
                        }
                    }
                },
                onDismiss = dismiss,
            )
        }
    }
    if (showsEdit) {
        BadieSheet(onDismiss = { showsEdit = false }) { dismiss -> RoomDetailsEditor(room, dismiss) }
    }
    kickTarget?.let { target ->
        ConfirmAlert(tr("移出 %@？", target.nickname), tr("对方会收到通知，候补中的球友会自动递补。"), tr("移出"), onDismiss = { kickTarget = null }) {
            scope.launch {
                try {
                    env.roomManager.kick(target, room)
                    env.appState.showToast(L10n.tr("已移出 %@", target.nickname))
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
            }
        }
    }
    if (showsLeave) {
        ConfirmAlert(
            if (isOwner) tr("解散房间？所有人都会收到通知") else tr("退出房间？"), null,
            if (isOwner) tr("解散") else tr("退出"), onDismiss = { showsLeave = false },
        ) {
            scope.launch {
                try {
                    env.roomManager.leave(room)
                    env.appState.showToast(if (isOwner) L10n.tr("房间已解散") else L10n.tr("已退出"))
                    env.router.pop()
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
            }
        }
    }
}

@Composable
private fun StatusBanner(room: Room) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    when (val status = room.status) {
        RoomStatus.Open -> if (room.slot == null) {
            val now by rememberNow(30_000)
            val minutes = maxOf(0L, (room.expiresAt() - now) / 60_000)
            Row(verticalAlignment = Alignment.CenterVertically) {
                TagPill(tr("剩约 %lld 分钟", minutes), icon = Sym.timer, fill = colors.butter)
                RulesButton(
                    tr("房间什么时候关闭"),
                    listOf(tr("没定时间的房间，30 分钟没有动静会自动关闭。"), tr("定了时间的房间，到开始时间还没开局就关闭。")),
                )
            }
        }
        is RoomStatus.Started -> Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).pressable(scale = 0.98f) { env.router.open(Route.Game(status.gameId)) },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            TagPill(tr("已开始"), icon = Sym.checkmarkSealFill, fill = colors.lime)
            Text(tr("查看球局"), style = AppTheme.Typography.footnoteBold, color = colors.ink)
            Symbol(Sym.chevronRight, size = 12, tint = colors.inkTertiary)
        }
        is RoomStatus.Closed -> NoticeBanner(Sym.xmarkOctagonFill, status.reason.message, tint = colors.surfaceMuted)
    }
}

@Composable
private fun CodeCard(room: Room) {
    val env = LocalEnv.current
    val context = LocalContext.current
    val ink = AppTheme.colors.onAccent
    val spoken = tr("房间码 %@", room.code.toList().joinToString(" "))
    Column(Modifier.card(AppTheme.colors.lavender), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("房间码"), style = AppTheme.Typography.overline, color = ink, modifier = Modifier.weight(1f))
            TagPill("${room.mode.title} · ${room.participants.size}/${room.requiredPlayerCount}", fill = Color.White)
        }
        Row(Modifier.clearAndSetSemantics { contentDescription = spoken }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (character in room.code) {
                Box(
                    Modifier.weight(1f).height(52.dp).sticker(Color.White, radius = 12.dp, shadow = AppTheme.Elevation.none, stroke = Color(0xFF17140F)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(character.toString(), style = codeStyle, color = ink)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            BrutalButton(
                onClick = {
                    SystemActions.copy(context, room.code)
                    env.appState.showToast(L10n.tr("房间码已复制"), Toast.Style.Success)
                },
                modifier = Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small,
            ) {
                Symbol(Sym.docOnDocFill, size = 13)
                Spacer(Modifier.width(6.dp))
                FitText(tr("复制"))
            }
            BrutalButton(
                onClick = { SystemActions.share(context, room.inviteText()) },
                modifier = Modifier.weight(1f), kind = ButtonKind.Inverse, size = ButtonSize.Small,
            ) {
                Symbol(Sym.paperplaneFill, size = 13)
                Spacer(Modifier.width(6.dp))
                FitText(tr("发给好友"))
            }
        }
    }
}

private val codeStyle = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Black, fontSize = 28.sp)

@Composable
private fun DetailsCard(room: Room, isOwner: Boolean, onEdit: () -> Unit) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.sm),
    ) {
        InfoRow(
            Sym.clockFill, room.slot?.formattedFull() ?: tr("时间待定"), tint = colors.peach,
            subtitle = room.slot?.let { tr("共 %@", it.formattedDuration) },
        )
        InsetDivider()
        InfoRow(
            Sym.mappinAndEllipse, room.court?.name ?: tr("球馆待定"), tint = colors.sky,
            subtitle = room.court?.let { court -> listOfNotNull(distanceText(court.location), court.address).joinToString(" · ") },
        )
        InsetDivider()
        val extras = listOfNotNull(room.event?.title(room.mode)) + room.tags.map { it.title }
        InfoRow(Sym.chartBarFill, room.levelRangeText, tint = colors.lavender, subtitle = extras.takeIf { it.isNotEmpty() }?.joinToString(" · "))
        room.costEstimate?.let { cost ->
            InsetDivider()
            CostRow(cost, if (cost.perPerson == null) tr("费用待定") else tr("AA 约 %@", cost.perPersonText))
        }
        if (room.note.isNotEmpty()) {
            InsetDivider()
            InfoRow(Sym.textBubbleFill, room.note, tint = colors.mint)
        }
        if (isOwner && room.status.isOpen) {
            InsetDivider()
            MenuRow(Sym.pencil, tr("编辑时间和球馆"), tint = colors.lime, onClick = onEdit)
        }
    }
}

/** 费用一行：图标 + 金额 + “?”。iPhone 的图标按币种（$、¥…）；安卓的图标表里没有币种符号，用钞票 */
@Composable
private fun CostRow(cost: CostSplit, title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        InfoRow(Sym.banknote, title, Modifier.weight(1f), tint = AppTheme.colors.butter)
        RulesButton(tr("费用怎么算"), listOf(cost.breakdownText))
    }
}

@Composable
private fun SeatsSection(room: Room, me: String, isOwner: Boolean, onInvite: () -> Unit, onKick: (RoomParticipant) -> Unit) {
    val mixed = room.mixedGoing
    val detail = if (mixed != null) {
        tr("男 %lld/2 · 女 %lld/2", mixed.male, mixed.female)
    } else if (room.isReady) {
        tr("已满员")
    } else {
        tr("还差 %lld 人", room.openSeats)
    }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        SectionTitle(tr("座位"), detail = detail)
        // 两列的格子：先是人（看不到名单的只占位），再是空位
        val cells: List<RoomParticipant?> = room.participants + List(room.openSeats) { null }
        cells.chunked(2).forEach { row ->
            // 同一行的两格一样高
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                for (participant in row) {
                    when {
                        participant == null -> EmptySeat(room.contains(me), room.contains(me) && room.status.isOpen, Modifier.weight(1f).fillMaxHeight(), onInvite)
                        participant.isAnonymous -> TakenSeat(Modifier.weight(1f).fillMaxHeight())
                        else -> SeatCard(participant, room, me, isOwner, Modifier.weight(1f).fillMaxHeight(), onKick)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** 看不到名单时（还没加入的公开局）：只显示这里有人 */
@Composable
private fun TakenSeat(modifier: Modifier) {
    val colors = AppTheme.colors
    Column(
        modifier.defaultMinSize(minHeight = 124.dp).sticker(colors.surfaceMuted, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm, Alignment.CenterVertically),
    ) {
        Symbol(Sym.personFill, size = 22, tint = colors.inkSecondary)
        Text(tr("已报名"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
    }
}

@Composable
private fun EmptySeat(isMember: Boolean, enabled: Boolean, modifier: Modifier, onInvite: () -> Unit) {
    val colors = AppTheme.colors
    val label = tr("空位，邀请好友")
    val stroke = colors.stroke
    Column(
        modifier
            .defaultMinSize(minHeight = 124.dp)
            .pressable(enabled = enabled, onClick = onInvite)
            .semantics(mergeDescendants = true) { contentDescription = label }
            .drawBehind {
                val w = 2.dp.toPx()
                drawRoundRect(
                    stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius(AppTheme.Radius.lg.toPx()),
                    style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))),
                )
            },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm, Alignment.CenterVertically),
    ) {
        Symbol(Sym.plus, size = 22, tint = colors.inkSecondary)
        Text(if (isMember) tr("邀请好友") else tr("空位"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
    }
}

@Composable
private fun SeatCard(participant: RoomParticipant, room: Room, me: String, isOwner: Boolean, modifier: Modifier, onKick: (RoomParticipant) -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val isMe = participant.userId == me
    val kickLabel = tr("移出 %@", participant.nickname)
    Box(modifier) {
        Column(
            Modifier
                .fillMaxSize()
                .defaultMinSize(minHeight = 124.dp)
                .pressable(enabled = !isMe) { env.appState.showPlayer(participant.userId) }
                .sticker(if (isMe) colors.lime else colors.paletteColor(participant.avatar.paletteIndex + 1), radius = AppTheme.Radius.lg)
                .padding(vertical = AppTheme.Spacing.md, horizontal = AppTheme.Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            ParticipantAvatar(participant, size = 52.dp)
            Text(
                if (isMe) tr("我") else participant.nickname, style = AppTheme.Typography.headline, color = colors.onAccent,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                LevelBadge(participant.tier, showsName = false, compact = true)
                if (participant.userId == room.ownerId) TagPill(tr("房主"), fill = colors.butter)
            }
        }
        if (isOwner && !isMe && room.status.isOpen) {
            Box(
                Modifier.align(Alignment.TopEnd).size(44.dp).pressable { onKick(participant) }.semantics { contentDescription = kickLabel },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(26.dp).sticker(Color.White, radius = 13.dp, shadow = AppTheme.Elevation.none, stroke = Color(0xFF17140F), strokeWidth = 1.5.dp), contentAlignment = Alignment.Center) {
                    Symbol(Sym.xmark, size = 11, tint = colors.onAccent)
                }
            }
        }
    }
}

@Composable
private fun WaitlistSection(room: Room, me: String) {
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionTitle(tr("候补"), Modifier.weight(1f, fill = false), detail = tr("%lld 人", room.waitlist.size))
            RulesButton(tr("候补"), listOf(tr("有人退出，候补按顺序自动递补。"), tr("递补上了会通知你。")))
        }
        room.waitlist.forEachIndexed { index, participant ->
            if (participant.isAnonymous) return@forEachIndexed
            Row(
                Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                Text("${index + 1}", style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.inkSecondary)
                ParticipantAvatar(participant, Modifier.opensProfile(participant.userId, me), size = 32.dp)
                Text(if (participant.userId == me) tr("我") else participant.nickname, style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
                LevelBadge(participant.tier, showsName = false, compact = true)
            }
        }
    }
}

@Composable
private fun InvitedSection(room: Room) {
    val env = LocalEnv.current
    val names = room.invitedUserIds.mapNotNull { env.roomManager.book.user(it)?.nickname }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        TagPill(tr("已邀请 %lld", room.invitedUserIds.size), icon = Sym.paperplaneFill, fill = AppTheme.colors.sky)
        Text(com.badie.app.l10n.ListText.and(names), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Footer(room: Room, me: String, isOwner: Boolean, onLeave: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    var working by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().drawBehind { drawRect(colors.divider, size = Size(size.width, 1.5.dp.toPx())) }
            .padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        when {
            isOwner -> {
                val title = when {
                    !room.isReady -> tr("还差 %lld 人", room.openSeats)
                    room.court == null || room.slot == null -> tr("先设置时间和球馆")
                    else -> tr("开始球局")
                }
                BrutalButton(
                    onClick = {
                        working = true
                        scope.launch {
                            try {
                                val gameId = env.roomManager.start(room)
                                haptics.success()
                                env.router.pop()
                                env.router.open(Route.Game(gameId), MainTab.Games)
                            } catch (error: RemoteError) {
                                env.appState.showError(error)
                            }
                            working = false
                        }
                    },
                    enabled = room.isReady && room.court != null && room.slot != null && !working,
                ) {
                    if (working) {
                        LoadingDots()
                        Spacer(Modifier.width(AppTheme.Spacing.sm))
                    }
                    FitText(title)
                }
                TextAction(tr("解散房间"), onLeave, color = colors.danger)
            }
            room.contains(me) || room.isWaitlisted(me) -> {
                val waiting = room.isWaitlisted(me)
                Text(if (waiting) tr("候补中") else tr("等房主开始"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                BrutalButton(if (waiting) tr("退出候补") else tr("退出房间"), onLeave, kind = ButtonKind.Secondary)
            }
            else -> JoinButton(room, me)
        }
    }
}

/** 访客：加入球局（或候补）。等级按项目算，等级或性别不符时禁用并说明原因 */
@Composable
private fun JoinButton(room: Room, me: String) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    val user = env.appState.currentUser
    val gender = user?.gender ?: Gender.Unspecified
    val level = user?.level(room.event) ?: 0
    val rules = RoomJoinRules(room, me, gender, level)
    val event = room.event
    if (rules.genderBlocked && event != null) {
        Text(event.title(room.mode), style = AppTheme.Typography.footnoteBold, color = colors.danger)
    } else if (rules.levelBlocked) {
        Text(
            tr("这个局要求 %@，你的等级是 %@", room.levelRangeText, user?.displayTier?.text ?: "Lv.$level"),
            style = AppTheme.Typography.footnoteBold, color = colors.danger,
        )
    }
    val cost = room.costEstimate?.takeIf { it.perPerson != null }?.let { " · ${it.perPersonText}" } ?: ""
    BrutalButton(
        onClick = {
            working = true
            scope.launch {
                try {
                    val joined = env.roomManager.joinPublic(room)
                    env.appState.showToast(
                        if (joined.isWaitlisted(me)) L10n.tr("已加入候补，有空位会通知你") else L10n.tr("已加入球局"), Toast.Style.Success,
                    )
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
                working = false
            }
        },
        enabled = !working && !rules.levelBlocked && !rules.genderBlocked,
    ) {
        if (working) {
            LoadingDots()
            Spacer(Modifier.width(AppTheme.Spacing.sm))
        }
        FitText(if (rules.joinsWaitlist) tr("加入候补") else tr("加入球局") + cost)
    }
}

/** 访客能不能加入（纯逻辑，方便测试） */
internal class RoomJoinRules(room: Room, me: String, gender: Gender, level: Int) {
    val genderBlocked: Boolean = room.event?.let { if (it == PlayEvent.Mixed) gender == Gender.Unspecified else it.gender != gender } ?: false
    val levelBlocked: Boolean = room.visibility == RoomVisibility.PublicListing && !room.accepts(level) && me !in room.invitedUserIds

    /** 混双男女各两个位子：自己这边满了只能候补 */
    val joinsWaitlist: Boolean = room.isFull || (room.mixedGoing?.let { gender != Gender.Unspecified && it.count(gender) >= 2 } ?: false)
}

// MARK: - 编辑房间时间与球馆

@Composable
private fun RoomDetailsEditor(room: Room, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val initial = remember { initialSchedule(room.slot) }
    var day by remember { mutableLongStateOf(initial.day) }
    var start by remember { mutableIntStateOf(initial.start) }
    var end by remember { mutableIntStateOf(initial.end) }
    var court by remember { mutableStateOf(room.court) }
    var picking by remember { mutableStateOf(false) }
    val slot = slotOn(day, start, end)
    val message = slot?.validate()?.errorMessage
    Column(Modifier.fillMaxWidth().padding(bottom = AppTheme.Spacing.lg), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
        Row(Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("时间和球馆"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        DateStrip(upcomingDays(), day, { day = it })
        Row(Modifier.padding(horizontal = AppTheme.Spacing.screen), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            TimeStepper(tr("开始"), start, 6 * 60..23 * 60, Modifier.weight(1f)) { start = it }
            TimeStepper(tr("结束"), end, 7 * 60..24 * 60, Modifier.weight(1f)) { end = it }
        }
        if (message != null) {
            Text(message, style = AppTheme.Typography.footnoteBold, color = colors.danger, modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen))
        }
        Box(
            Modifier.padding(horizontal = AppTheme.Spacing.screen).pressable(scale = 0.98f) { picking = true }
                .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md),
        ) {
            InfoRow(Sym.sportscourtFill, court?.name ?: tr("选择球馆"), tint = colors.sky) {
                Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
            }
        }
        BrutalButton(
            tr("保存"),
            onClick = {
                scope.launch {
                    try {
                        env.roomManager.updateDetails(room, court, slot)
                        env.appState.showToast(L10n.tr("已更新"), Toast.Style.Success)
                        onDismiss()
                    } catch (error: RemoteError) {
                        env.appState.showError(error)
                    }
                }
            },
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen),
            enabled = slot?.validate()?.isValid == true,
        )
    }
    if (picking) {
        BadieSheet(onDismiss = { picking = false }) { dismiss ->
            VenuePickerSheet(court?.id, onPick = {
                court = it
                dismiss()
            }, onDismiss = dismiss)
        }
    }
}

/** 编辑时间的起点：房间有时间就用房间的，没有就用推荐的 */
internal data class Schedule(val day: Long, val start: Int, val end: Int)

internal fun initialSchedule(slot: TimeSlot?, now: Long = System.currentTimeMillis()): Schedule {
    if (slot != null) {
        val start = slot.startTime.zoned()
        val end = slot.endTime.zoned()
        val endMinutes = if (com.badie.app.models.isSameDay(slot.startTime, slot.endTime)) end.hour * 60 + end.minute else 24 * 60
        return Schedule(com.badie.app.models.startOfDay(slot.startTime), start.hour * 60 + start.minute, endMinutes)
    }
    val suggested = TimeSlot.suggestedDefault(now)
    val start = suggested.startTime.zoned()
    val startMinutes = start.hour * 60 + start.minute
    return Schedule(com.badie.app.models.startOfDay(suggested.startTime), startMinutes, minOf(24 * 60, startMinutes + 120))
}

// MARK: - 发起球局

/** 路由里的模式：服务器的写法（singles / doubles），也认中文原值 */
internal fun parseMode(mode: String?): GameMode? = when (mode) {
    null -> null
    "singles", GameMode.Singles.rawValue -> GameMode.Singles
    "doubles", GameMode.Doubles.rawValue -> GameMode.Doubles
    else -> null
}

/** 发起页的校验（纯逻辑，方便测试）：时间不对先报时间，公开局还要有球馆 */
internal fun createRoomProblem(slot: TimeSlot?, visibility: RoomVisibility, court: Venue?, now: Long = System.currentTimeMillis()): String? {
    slot?.validate(now)?.errorMessage?.let { return it }
    if (visibility == RoomVisibility.PublicListing && court == null) return L10n.tr("公开球局需要选择球馆")
    return null
}

/** 发起球局：私密房间（凭房间码 / 邀请）或公开招募（附近球友可见，支持候补） */
@Composable
fun CreateRoomScreen(mode: String?, invitee: String?) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val user = env.appState.currentUser
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val initial = remember { initialSchedule(null) }
    var gameMode by remember { mutableStateOf(parseMode(mode) ?: GameMode.Doubles) }
    var visibility by remember { mutableStateOf(RoomVisibility.PrivateRoom) }
    var hasSchedule by remember { mutableStateOf(true) }
    var day by remember { mutableLongStateOf(initial.day) }
    var start by remember { mutableIntStateOf(initial.start) }
    var end by remember { mutableIntStateOf(initial.end) }
    var court by remember { mutableStateOf<Venue?>(null) }
    // TODO：约了某个人时 iPhone 按两人的性别定能选的项目（要先拉对方资料，归 FriendManager）；现在按没有对方算
    val partner: Gender? = null
    val gender = user?.gender ?: Gender.Unspecified
    val choices = PlayEvent.choices(gameMode, gender, partner)
    var event by remember { mutableStateOf(choices.firstOrNull()) }
    if (event !in choices) event = choices.firstOrNull()
    val myLevel = user?.level(event) ?: 4
    var lower by remember { mutableIntStateOf(maxOf(1, myLevel - 2)) }
    var upper by remember { mutableIntStateOf(minOf(9, myLevel + 2)) }
    var tags by remember { mutableStateOf(setOf<RoomTag>()) }
    var note by remember { mutableStateOf("") }
    var picking by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    // 常去球馆里第一家读得到的，没有就等选
    LaunchedEffect(Unit) {
        if (court == null) court = env.appState.backend.favoriteVenueIds.firstNotNullOfOrNull { env.appState.backend.venue(it) }
    }
    val slot = if (hasSchedule || visibility == RoomVisibility.PublicListing) slotOn(day, start, end) else null
    val problem = createRoomProblem(slot, visibility, court)
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("发起球局"), onBack = { env.router.pop() })
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xxl),
        ) {
            FormGroup(tr("模式")) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    for (option in GameMode.entries) ChoiceChip(option.title, gameMode == option, icon = option.icon) { gameMode = option }
                }
            }
            if (choices.size > 1) {
                FormGroup(tr("项目")) {
                    EventPicker(gameMode, gender, partner, event) { picked ->
                        event = picked
                        // 换了项目，自己的等级可能跟着换算，范围重新围着自己
                        val level = user?.level(picked) ?: 4
                        lower = maxOf(1, level - 2)
                        upper = minOf(9, level + 2)
                    }
                }
            }
            FormGroup(tr("招募方式"), rules = visibilityRules()) {
                SegmentedSticker(listOf(RoomVisibility.PrivateRoom, RoomVisibility.PublicListing), visibility, { visibility = it }) {
                    if (it == RoomVisibility.PrivateRoom) tr("仅邀请") else tr("公开到附近")
                }
            }
            FormGroup(tr("时间")) {
                if (visibility == RoomVisibility.PrivateRoom) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(tr("现在就定时间"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
                        BadieSwitch(hasSchedule, { hasSchedule = it })
                    }
                }
                if (hasSchedule || visibility == RoomVisibility.PublicListing) {
                    DateStrip(upcomingDays(), day, { day = it }, Modifier.offsetHorizontally())
                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                        TimeStepper(tr("开始"), start, 6 * 60..23 * 60, Modifier.weight(1f)) { start = it }
                        TimeStepper(tr("结束"), end, 7 * 60..24 * 60, Modifier.weight(1f)) { end = it }
                    }
                    slot?.validate()?.errorMessage?.let { message ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Symbol(Sym.exclamationmarkCircleFill, size = 13, tint = colors.danger)
                            Text(message, style = AppTheme.Typography.footnoteBold, color = colors.danger)
                        }
                    }
                }
            }
            FormGroup(if (visibility == RoomVisibility.PublicListing) tr("球馆") else tr("球馆（可选）")) {
                Row(
                    Modifier.fillMaxWidth().pressable(scale = 0.98f) { picking = true }
                        .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    IconTile(Sym.sportscourtFill, fill = colors.sky, size = 40.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(court?.name ?: tr("选择球馆"), style = AppTheme.Typography.bodyBold, color = colors.ink)
                        court?.let { venue ->
                            Text(
                                listOfNotNull(distanceText(venue.location), venue.pricingText).joinToString(" · "),
                                style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                    Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
                }
            }
            if (visibility == RoomVisibility.PublicListing) {
                FormGroup(tr("接受的水平")) {
                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                        LevelStepper(tr("最低"), lower, 1..upper, Modifier.weight(1f)) { lower = it }
                        LevelStepper(tr("最高"), upper, lower..9, Modifier.weight(1f)) { upper = it }
                    }
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        ChoiceChip(tr("不限"), lower == 1 && upper == 9) {
                            lower = 1
                            upper = 9
                        }
                        ChoiceChip(tr("我的水平 ±1"), lower == maxOf(1, myLevel - 1) && upper == minOf(9, myLevel + 1)) {
                            lower = maxOf(1, myLevel - 1)
                            upper = minOf(9, myLevel + 1)
                        }
                        ChoiceChip(tr("新手 1–3"), lower == 1 && upper == 3) {
                            lower = 1
                            upper = 3
                        }
                    }
                }
                FormGroup(tr("球局氛围")) {
                    Flow {
                        for (tag in RoomTag.entries) {
                            ChoiceChip(tag.title, tag in tags, icon = tag.icon, tint = colors.mint) { tags = if (tag in tags) tags - tag else tags + tag }
                        }
                    }
                }
            }
            FormGroup(tr("备注（可选）")) {
                BrutalTextField(tr("给球友的话"), tr("例：已订 2 小时，打完 AA；自带球"), note, { note = it }, characterLimit = 80)
            }
            val preview = if (court != null && slot != null && slot.isValidDuration) CostSplit.estimate(court!!, slot, gameMode) else null
            preview?.let { cost ->
                Box(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md)) {
                    CostRow(cost, if (cost.perPerson == null) tr("费用待定") else tr("预计 AA %@", cost.perPersonText))
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().drawBehind { drawRect(colors.divider, size = Size(size.width, 1.5.dp.toPx())) }
                .padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
        ) {
            if (problem != null) Text(problem, style = AppTheme.Typography.caption, color = colors.danger)
            BrutalButton(
                onClick = {
                    working = true
                    val draft = RoomDraft(
                        mode = gameMode, visibility = visibility, court = court, slot = slot, levelRange = lower..upper,
                        tags = RoomTag.entries.filter { it in tags }, note = note.take(80), event = event,
                    )
                    scope.launch {
                        try {
                            val room = env.roomManager.create(draft)
                            if (invitee != null) {
                                // 只能邀请球友：不是球友时服务器会拒绝，不提示
                                try {
                                    env.roomManager.invite(listOf(invitee), room)
                                } catch (_: RemoteError) {
                                }
                            }
                            haptics.success()
                            env.router.pop()
                            env.router.open(Route.Room(room.id))
                        } catch (error: RemoteError) {
                            env.appState.showError(error)
                        }
                        working = false
                    }
                },
                enabled = problem == null && !working,
            ) {
                if (working) {
                    LoadingDots()
                    Spacer(Modifier.width(AppTheme.Spacing.sm))
                }
                FitText(if (visibility == RoomVisibility.PublicListing) tr("发布球局") else tr("创建房间"))
            }
        }
    }
    if (picking) {
        BadieSheet(onDismiss = { picking = false }) { dismiss ->
            VenuePickerSheet(court?.id, onPick = {
                court = it
                dismiss()
            }, onDismiss = dismiss)
        }
    }
}

/** 日期条贴着屏幕边（抵消页面左右边距） */
private fun Modifier.offsetHorizontally(): Modifier = this.layoutWiderBy(AppTheme.Spacing.screen)

private fun Modifier.layoutWiderBy(extra: androidx.compose.ui.unit.Dp): Modifier = layout { measurable, constraints ->
    val wider = constraints.copy(maxWidth = constraints.maxWidth + (extra * 2).roundToPx(), minWidth = 0)
    val placeable = measurable.measure(wider)
    layout(constraints.maxWidth, placeable.height) { placeable.place(-extra.roundToPx(), 0) }
}

/** 招募方式的“?”：两种方式各自怎么用 */
@Composable
private fun visibilityRules(): List<String> = listOf(
    tr("仅邀请：生成 6 位房间码，分享给好友加入。"),
    tr("没定时间的房间，30 分钟没有动静会自动关闭。"),
    tr("建好房间后，房主可以在房间里再定时间和球馆。"),
    tr("公开到附近：附近水平符合的球友都能看到并报名。"),
    tr("满员后可以候补，有人退出自动递补。"),
)

// MARK: - 输入房间码 / 群号

@Composable
fun JoinRoomScreen(code: String?) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    var text by remember { mutableStateOf(Room.normalize(code ?: "")) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }
    fun join() {
        if (text.length != Room.CODE_LENGTH || working) return
        working = true
        scope.launch {
            try {
                // 正式后端的房间码和群号同一套字母，交给服务器查：群号打开球群页面（在那里加入）
                when (val result = env.roomManager.join(text)) {
                    is com.badie.app.features.rooms.RoomManager.JoinResult.Group -> {
                        haptics.success()
                        env.router.pop()
                        env.router.open(Route.Group(result.id))
                    }
                    is com.badie.app.features.rooms.RoomManager.JoinResult.Entered -> {
                        haptics.success()
                        env.router.pop()
                        env.router.open(Route.Room(result.room.id))
                    }
                }
            } catch (error: RemoteError) {
                errorText = error.message
                haptics.error()
            }
            working = false
        }
    }
    LaunchedEffect(Unit) {
        try {
            focus.requestFocus()
        } catch (_: IllegalStateException) {
        }
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("房间码 / 群号"), onBack = { env.router.pop() })
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            Text(tr("输入房间码或群号"), style = AppTheme.Typography.title, color = colors.ink)
            val label = tr("房间码")
            BasicTextField(
                text,
                { value ->
                    val normalized = Room.normalize(value)
                    text = normalized
                    errorText = null
                    if (normalized.length == Room.CODE_LENGTH) join()
                },
                Modifier
                    .fillMaxWidth()
                    .focusRequester(focus)
                    .onFocusChanged { focused = it.isFocused }
                    .semantics { contentDescription = label },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
                singleLine = true,
                decorationBox = { inner ->
                    Box {
                        Box(Modifier.size(1.dp)) { inner() }
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            for (index in 0 until Room.CODE_LENGTH) {
                                val filled = index < text.length
                                Box(
                                    Modifier.weight(1f).height(58.dp).sticker(
                                        if (index == text.length && focused) colors.lime else colors.surface, radius = 14.dp,
                                        shadow = if (filled) AppTheme.Elevation.low else AppTheme.Elevation.none,
                                        stroke = if (errorText == null) colors.stroke else colors.danger,
                                    ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (filled) Text(text[index].toString(), style = codeStyle, color = colors.ink)
                                }
                            }
                        }
                    }
                },
            )
            errorText?.let { message ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(Sym.exclamationmarkCircleFill, size = 13, tint = colors.danger)
                    Text(message, style = AppTheme.Typography.footnoteBold, color = colors.danger)
                }
            }
            BrutalButton(
                onClick = { SystemActions.paste(context)?.let { pasted -> text = Room.normalize(pasted) } },
                kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false,
            ) {
                Symbol(Sym.docOnClipboard, size = 13)
                Spacer(Modifier.width(6.dp))
                Text(tr("粘贴房间码"))
            }
        }
        BrutalButton(
            onClick = { join() },
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg),
            enabled = text.length == Room.CODE_LENGTH && !working,
        ) {
            if (working) {
                LoadingDots()
                Spacer(Modifier.width(AppTheme.Spacing.sm))
            }
            FitText(tr("加入"))
        }
    }
}

// MARK: - 附近公开球局

/** 附近球局的筛选（纯逻辑，方便测试） */
internal fun filterPublicRooms(rooms: List<Room>, mode: GameMode?, tag: RoomTag?, onlyMyLevel: Boolean, level: Int): List<Room> =
    rooms.filter { room ->
        (mode == null || room.mode == mode) && (tag == null || tag in room.tags) && (!onlyMyLevel || room.accepts(level))
    }

@Composable
fun PublicGamesScreen() {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    var modeFilter by remember { mutableStateOf<GameMode?>(null) }
    var tagFilter by remember { mutableStateOf<RoomTag?>(null) }
    var onlyMyLevel by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try {
            env.roomManager.loadNearby()
        } catch (_: RemoteError) {
        }
    }
    val me = env.appState.currentUser
    val rooms = filterPublicRooms(env.roomManager.publicRooms, modeFilter, tagFilter, onlyMyLevel, me?.displayLevel ?: 0)
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("附近球局"), onBack = { env.router.pop() })
        RefreshEverything(Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
            ) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                ) {
                    ChoiceChip(tr("适合我的水平"), onlyMyLevel, icon = Sym.chartBarFill) { onlyMyLevel = !onlyMyLevel }
                    for (mode in GameMode.entries) {
                        ChoiceChip(mode.title, modeFilter == mode) { modeFilter = if (modeFilter == mode) null else mode }
                    }
                    for (tag in RoomTag.entries) {
                        ChoiceChip(tag.title, tagFilter == tag, icon = tag.icon, tint = colors.mint) { tagFilter = if (tagFilter == tag) null else tag }
                    }
                }
                Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    if (rooms.isEmpty()) {
                        EmptyStateView(
                            Sym.sportscourt, tr("没有符合条件的球局"), Modifier.card(), tint = colors.peach, actionTitle = tr("发起球局"),
                        ) { env.router.open(Route.CreateRoom(modeFilter?.serverValue), MainTab.Games) }
                    }
                    for (room in rooms) {
                        PublicRoomCard(
                            room, room.court?.let { distanceText(it.location) }, me?.id,
                            Modifier.pressable(scale = 0.98f) { env.router.open(Route.Room(room.id)) }, width = null,
                        )
                    }
                }
            }
        }
    }
}
