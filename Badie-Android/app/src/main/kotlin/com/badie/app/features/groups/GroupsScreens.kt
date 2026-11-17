package com.badie.app.features.groups

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.backend.BackendError
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.ProgressBar
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StickerTextField
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.features.social.ConfirmDialog
import com.badie.app.features.social.MultilineField
import com.badie.app.features.social.ToggleRow
import com.badie.app.features.social.shareText
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.Coordinate
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.Gender
import com.badie.app.models.GroupActivity
import com.badie.app.models.GroupSchedule
import com.badie.app.models.GroupSession
import com.badie.app.models.PlayGroup
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.characterCount
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

// 找球群、球群详情、场次名单、建群和编辑。对应 iPhone 的 Features/Groups/GroupViews.swift

// MARK: - 球群卡片（找球群、球馆页）

@Composable
fun GroupCard(group: PlayGroup, venue: Venue?, activity: GroupActivity, modifier: Modifier = Modifier, status: String? = null) {
    val colors = AppTheme.colors
    Column(
        modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.lg).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            IconTile(Sym.person3Fill, fill = colors.lavender, size = 44.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(group.name, style = AppTheme.Typography.headline, color = colors.ink)
                venue?.let { Text(it.name, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            status?.let { TagPill(it, fill = colors.lime) }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            group.schedules.forEach { TagPill("${it.weekdayTitle} ${it.timeText}", icon = Sym.calendar, fill = colors.surfaceMuted, foreground = colors.ink) }
            if (group.venueIds.size > 1) {
                TagPill(tr("%lld 个球馆", group.venueIds.size), icon = Sym.mappinAndEllipse, fill = colors.surfaceMuted, foreground = colors.ink)
            }
            if (group.isCoached) TagPill(tr("教练带课"), icon = Sym.graduationcapFill, fill = colors.sky)
            TagPill(group.levelText, icon = Sym.chartBarFill, fill = colors.surfaceMuted, foreground = colors.ink)
            group.audience?.let { TagPill(it.onlyLabel, fill = colors.peach) }
        }
        IconLine(Sym.waveformPathEcg, activity.text, AppTheme.Typography.caption)
    }
}

@Composable
private fun IconLine(icon: SymbolId, text: String, style: androidx.compose.ui.text.TextStyle, color: androidx.compose.ui.graphics.Color = AppTheme.colors.inkSecondary) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Symbol(icon, size = (style.fontSize.value * 0.9f).toInt(), tint = color)
        Text(text, style = style, color = color)
    }
}

// MARK: - 找球群

@Composable
fun GroupsScreen() {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    LaunchedEffect(groupManager.radiusKm, groupManager.location.currentLocation) {
        try {
            groupManager.loadNearby(groupManager.currentCenter(), groupManager.radiusKm)
        } catch (_: RemoteError) {
        }
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("球群 · 固定局"), onBack = { env.router.pop() }) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                RulesButton(tr("球群怎么用"), GroupRules.points())
                IconButton(Sym.plus, tr("建一个球群")) { env.router.open(Route.CreateGroup()) }
            }
        }
        RefreshEverything(Modifier.fillMaxSize(), extra = { groupManager.loadNearby(groupManager.currentCenter(), groupManager.radiusKm) }) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
            ) {
                val mine = groupManager.myGroups
                if (mine.isNotEmpty()) GroupSection(tr("我加入的"), mine)
                val nearby = groupManager.nearbyGroups().filter { group -> mine.none { it.id == group.id } }
                if (nearby.isEmpty()) {
                    EmptyStateView(Sym.person3, tr("附近还没有球群"), tint = AppTheme.colors.lavender, actionTitle = tr("建群")) {
                        env.router.open(Route.CreateGroup())
                    }
                } else {
                    GroupSection(tr("附近的球群"), nearby)
                }
            }
        }
    }
}

@Composable
private fun GroupSection(title: String, groups: List<PlayGroup>) {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    val me = groupManager.currentUserId
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(title, detail = tr("%lld 个", groups.size))
        groups.forEach { group ->
            GroupCard(
                group, groupManager.venue(group), groupManager.activity(group.id),
                Modifier.pressable(scale = 0.98f) { env.router.open(Route.Group(group.id)) },
                status = if (me != null && group.isPending(me)) tr("待审核") else null,
            )
        }
    }
}

// MARK: - 球群详情：场次报名、候补、成员、群聊

@Composable
fun GroupScreen(id: String) {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    val android = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmsLeave by remember { mutableStateOf(false) }
    var confirmsDisband by remember { mutableStateOf(false) }
    var sessionDetail by remember { mutableStateOf<String?>(null) }
    var isLoading by remember(id) { mutableStateOf(groupManager.group(id) == null) }
    LaunchedEffect(id) {
        if (groupManager.group(id) == null) {
            try {
                groupManager.loadGroup(id)
            } catch (_: RemoteError) {
            }
        } else {
            groupManager.refreshIfStale(id)
        }
        isLoading = false
    }
    val group = groupManager.group(id)
    val me = env.appState.currentUser?.id
    val disbanded = tr("球群已解散，成员会收到通知")
    val left = tr("已退出，已报名的场次也一并取消")

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(group?.name ?: tr("球群"), onBack = { env.router.pop() }) {
            val venue = group?.let(groupManager::venue)
            if (group != null && venue != null) {
                IconButton(Sym.squareAndArrowUp, tr("邀请（可以发到微信）")) { shareText(android, group.inviteText(venue.name)) }
            }
        }
        when {
            group != null -> RefreshEverything(Modifier.fillMaxSize(), extra = { groupManager.loadGroup(id) }) {
                Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
                ) {
                    GroupHeader(group)
                    if (me != null && group.isMember(me)) SessionsSection(group) { sessionDetail = it } else JoinCard(group)
                    MembersSection(group)
                    if (me != null && group.isOrganizer(me) && group.pendingIds.isNotEmpty()) PendingSection(group)
                    if (me != null && group.isMember(me) && group.ownerId != me) {
                        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            TextAction(tr("退出球群"), { confirmsLeave = true }, color = AppTheme.colors.danger)
                        }
                    }
                    if (group.ownerId == me) {
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            BrutalButton(tr("编辑球群和场次"), { env.router.open(Route.EditGroup(group.id)) }, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
                            TextAction(tr("解散球群"), { confirmsDisband = true }, color = AppTheme.colors.danger)
                        }
                    }
                }
            }
            isLoading -> Box(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = AppTheme.colors.ink)
            }
            else -> EmptyStateView(Sym.person3, tr("没有找到这个球群"))
        }
    }
    if (confirmsDisband) {
        ConfirmDialog(tr("解散这个球群？"), tr("以后的场次和报名都会删掉，不能恢复。"), tr("解散"), onDismiss = { confirmsDisband = false }) {
            scope.launch {
                try {
                    groupManager.disband(id)
                    env.appState.showToast(disbanded)
                    env.router.pop()
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
            }
        }
    }
    if (confirmsLeave) {
        ConfirmDialog(tr("退出这个球群？"), tr("已报名的场次会一并取消，名额让给候补。"), tr("退出"), onDismiss = { confirmsLeave = false }) {
            scope.launch {
                try {
                    groupManager.leave(id)
                    env.appState.showToast(left)
                    env.router.pop()
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
            }
        }
    }
    sessionDetail?.let { sessionId ->
        SheetScaffold(onDismiss = { sessionDetail = null }) { SessionSheet(sessionId) { sessionDetail = null } }
    }
}

@Composable
private fun GroupHeader(group: PlayGroup) {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    val colors = AppTheme.colors
    val me = env.appState.currentUser?.id
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        groupManager.venue(group)?.let { CourtLink(it) }
        // 其他球馆（和主球馆一样的样子，点开球馆页）
        groupManager.otherVenues(group).forEach { CourtLink(it) }
        if (group.summary.isNotEmpty()) Text(group.summary, style = AppTheme.Typography.subheadline, color = colors.ink)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (group.isCoached) TagPill(tr("教练带课"), icon = Sym.graduationcapFill, fill = colors.sky)
            TagPill(group.levelText, icon = Sym.chartBarFill, fill = colors.lime)
            group.audience?.let { TagPill(it.onlyLabel, fill = colors.peach) }
            TagPill(group.joinPolicy.title, icon = Sym.personBadgePlus, fill = colors.surfaceMuted, foreground = colors.ink)
            TagPill(tr("群号 %@", group.inviteCode), icon = Sym.number, fill = colors.surfaceMuted, foreground = colors.ink)
        }
        group.feeLines.forEach { IconLine(Sym.banknote, it, AppTheme.Typography.subheadline, colors.ink) }
        IconLine(Sym.waveformPathEcg, groupManager.activity(group.id).text, AppTheme.Typography.footnoteBold)
        if (me != null && group.isMember(me)) {
            BrutalButton({
                env.messageManager.groupChatId(group.id, group.name, group.memberIds)?.let { env.router.open(Route.GroupChat(it)) }
            }, kind = ButtonKind.Secondary, size = ButtonSize.Medium) {
                Symbol(Sym.bubbleLeftAndBubbleRightFill, size = 15)
                Spacer(Modifier.size(AppTheme.Spacing.sm))
                Text(tr("球群群聊"))
            }
        }
    }
}

/** 球群的一个球馆：点开球馆页 */
@Composable
private fun CourtLink(venue: Venue) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    Row(
        Modifier.fillMaxWidth().pressable(scale = 1f) { env.router.open(Route.Venue(venue.id)) },
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(Sym.mappinAndEllipse, fill = colors.sky, size = 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(venue.name, style = AppTheme.Typography.bodyBold, color = colors.ink)
            Text(venue.address, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 2)
        }
        Symbol(Sym.chevronRight, size = 14, tint = colors.inkTertiary)
    }
}

@Composable
private fun JoinCard(group: PlayGroup) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val me = env.appState.currentUser?.id
    val requested = tr("已提交申请，组织者同意后通知你")
    Column(Modifier.card(fill = colors.butter), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        if (me != null && group.isPending(me)) {
            IconLine(Sym.hourglass, tr("等组织者同意"), AppTheme.Typography.bodyBold, colors.onAccent)
        } else {
            val joinedText = tr("已加入「%@」", group.name)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalButton(if (group.joinPolicy == PlayGroup.JoinPolicy.Open) tr("加入球群") else tr("申请加入"), {
                    scope.launch {
                        try {
                            val joined = env.groupManager.join(group.id)
                            haptics.success()
                            env.appState.showToast(if (joined.isMember(me ?: "")) joinedText else requested, Toast.Style.Success)
                        } catch (error: RemoteError) {
                            env.appState.showError(error)
                        } catch (error: BackendError) {
                            env.appState.showError(error)
                        }
                    }
                }, Modifier.weight(1f))
                RulesButton(tr("怎么加入"), GroupRules.joinPoints(group))
            }
        }
        if (group.schedules.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                group.schedules.forEach {
                    IconLine(Sym.calendar, tr("%@ %@ · %lld 个名额", it.weekdayTitle, it.timeText, it.capacity), AppTheme.Typography.footnote, colors.onAccent.copy(alpha = 0.75f))
                }
            }
        }
    }
}

@Composable
private fun SessionsSection(group: PlayGroup, onOpen: (String) -> Unit) {
    val env = LocalEnv.current
    val sessions = env.groupManager.sessions(group.id)
    val me = env.appState.currentUser?.id ?: ""
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("接下来的场次"), style = AppTheme.Typography.title3, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(tr("报名和候补"), GroupRules.points())
        }
        if (sessions.isEmpty()) Text(tr("未来两周没有场次"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
        sessions.forEach { session -> SessionRow(session, me) { onOpen(session.id) } }
    }
}

@Composable
private fun MembersSection(group: PlayGroup) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val me = env.appState.currentUser?.id
    val members = group.memberIds.mapNotNull(env.groupManager::user)
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("成员"), detail = tr("%lld 人", members.size))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.Top) {
            members.take(16).forEach { member ->
                Column(Modifier.width(60.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    AvatarView(member, Modifier.pressable { if (member.id != me) env.appState.showPlayer(member.id) }, size = 48.dp)
                    Text(if (member.id == me) tr("我") else member.nickname, style = AppTheme.Typography.caption, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (group.isOrganizer(member.id)) Text(tr("组织者"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
                }
            }
        }
    }
}

@Composable
private fun PendingSection(group: PlayGroup) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(tr("加入申请"), detail = tr("%lld 人", group.pendingIds.size))
        group.pendingIds.forEach { userId ->
            val user = env.groupManager.user(userId) ?: return@forEach
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                AvatarView(user, Modifier.pressable { env.appState.showPlayer(user.id) }, size = 40.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(user.nickname, style = AppTheme.Typography.bodyBold, color = colors.ink)
                    Text("${user.displayLevelText} · ${user.publicSummary}", style = AppTheme.Typography.caption, color = colors.inkSecondary)
                }
                BrutalButton(tr("同意"), {
                    scope.launch {
                        try {
                            env.groupManager.approve(userId, group.id)
                        } catch (_: RemoteError) {
                        }
                    }
                }, size = ButtonSize.Small, fullWidth = false)
            }
        }
    }
}

// MARK: - 场次行

@Composable
fun SessionRow(session: GroupSession, userId: String, onOpen: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val status = session.status(userId)
    val signedUpToast = tr("已报名：%@", session.slot.formattedFull())
    val lateToast = tr("已取消（开场前 2 小时内，计入临时取消）")
    val cancelledToast = tr("已取消，名额让给候补")

    fun signUp() {
        scope.launch {
            try {
                when (val result = env.groupManager.signUp(session.id)) {
                    SignupResult.Confirmed -> {
                        haptics.success()
                        env.appState.showToast(signedUpToast, Toast.Style.Success)
                    }
                    is SignupResult.Waitlisted -> env.appState.showToast(L10n.tr("已候补第 %lld 位，有人退出会自动递补并通知你", result.position))
                }
            } catch (error: RemoteError) {
                env.appState.showError(error)
            } catch (error: BackendError) {
                env.appState.showError(error)
            }
        }
    }

    fun cancel() {
        val late = session.slot.startTime - System.currentTimeMillis() < GroupSession.LATE_CANCELLATION_WINDOW
        scope.launch {
            try {
                env.groupManager.cancelSignup(session.id)
                env.appState.showToast(if (late) lateToast else cancelledToast)
            } catch (error: RemoteError) {
                env.appState.showError(error)
            } catch (error: BackendError) {
                env.appState.showError(error)
            }
        }
    }

    Row(
        Modifier.fillMaxWidth()
            .sticker(if (status == GroupSession.Status.SignedUp) colors.lime.copy(alpha = 0.35f) else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Column(Modifier.weight(1f).pressable(scale = 1f, onClick = onOpen), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(session.slot.formattedFull(), style = AppTheme.Typography.bodyBold, color = colors.ink)
            env.groupManager.sessionVenueName(session)?.let { venueName ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(Sym.mappinAndEllipse, size = 12, tint = colors.inkSecondary)
                    Text(venueName, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(tr("已报 %lld/%lld", session.signedUp.size, session.capacity), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                if (session.waitlist.isNotEmpty()) Text(tr("· 候补 %lld", session.waitlist.size), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
            ProgressBar(session.signedUp.size.toFloat() / maxOf(1, session.capacity), Modifier.widthIn(max = 160.dp))
        }
        when (status) {
            GroupSession.Status.SignedUp -> BrutalButton(tr("已报名 ✓"), ::cancel, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
            is GroupSession.Status.Waitlisted ->
                BrutalButton(tr("候补第 %lld", status.position), ::cancel, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
            GroupSession.Status.None -> BrutalButton(if (session.isFull) tr("候补") else tr("报名"), ::signUp, size = ButtonSize.Small, fullWidth = false)
        }
    }
}

// MARK: - 某一场的报名名单

@Composable
fun SessionSheet(sessionId: String, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    val scope = rememberCoroutineScope()
    val cancelled = tr("已取消，已报名的人会收到通知")
    val session = groupManager.session(sessionId)
    val group = session?.let { groupManager.group(it.groupId) }
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        if (session == null || group == null) return@Column
        Column(
            Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(session.slot.formattedFull(), style = AppTheme.Typography.title2, color = AppTheme.colors.ink)
                    Text(
                        groupManager.sessionVenueName(session) ?: groupManager.venue(group)?.name ?: group.name,
                        style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary,
                    )
                }
                IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
            }
            Roster(tr("已报名 %lld/%lld", session.signedUp.size, session.capacity), session.signedUp)
            if (session.waitlist.isNotEmpty()) Roster(tr("候补 %lld", session.waitlist.size), session.waitlist)
            val me = env.appState.currentUser?.id
            if (me != null && group.isOrganizer(me) && !session.isCancelled) {
                TextAction(tr("取消这一场"), {
                    scope.launch {
                        try {
                            groupManager.cancelSession(session.id)
                            env.appState.showToast(cancelled)
                            onDismiss()
                        } catch (error: RemoteError) {
                            env.appState.showError(error)
                        } catch (error: BackendError) {
                            env.appState.showError(error)
                        }
                    }
                }, color = AppTheme.colors.danger)
            }
        }
    }
}

@Composable
private fun Roster(title: String, ids: List<String>) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val me = env.appState.currentUser?.id
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(title, style = AppTheme.Typography.headline, color = colors.ink)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            ids.forEachIndexed { index, userId ->
                val user = env.groupManager.user(userId) ?: return@forEachIndexed
                val label = "${index + 1}. ${user.nickname}"
                Row(
                    Modifier.clip(CircleShape).background(colors.surface).border(1.dp, colors.stroke, CircleShape)
                        .pressable { if (user.id != me) env.appState.showPlayer(user.id) }
                        .padding(horizontal = AppTheme.Spacing.sm, vertical = 4.dp)
                        .clearAndSetSemantics { contentDescription = label },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    AvatarView(user, size = 28.dp)
                    Text(if (userId == me) tr("我") else user.nickname, style = AppTheme.Typography.footnoteBold, color = colors.ink)
                }
            }
        }
    }
}

// MARK: - 建群

/** 建球群；带 editingGroupId 时是群主编辑（球馆和谁能来不能改） */
@Composable
fun CreateGroupScreen(venueId: String?, editingGroupId: String? = null) {
    val env = LocalEnv.current
    val groupManager = env.groupManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val isEditing = editingGroupId != null
    val me = env.appState.currentUser

    var name by rememberSaveable { mutableStateOf("") }
    var summary by rememberSaveable { mutableStateOf("") }
    var pickedVenueId by rememberSaveable { mutableStateOf<String?>(null) }
    var pickedVenue by remember { mutableStateOf<Venue?>(null) }
    val schedules = remember { mutableStateListOf(GroupSchedule(UUID.randomUUID().toString(), 5, 19 * 60 + 30, 22 * 60, 12)) }
    var lowerLevel by rememberSaveable { mutableIntStateOf(1) }
    var upperLevel by rememberSaveable { mutableIntStateOf(9) }
    var joinPolicy by rememberSaveable { mutableStateOf(PlayGroup.JoinPolicy.Open) }
    var audience by rememberSaveable { mutableStateOf<Gender?>(null) }
    // 教练带课：每场 1–40 人，水平范围只作提示
    var coached by rememberSaveable { mutableStateOf(false) }
    var showVenuePicker by remember { mutableStateOf(false) }
    // 主球馆以外的球馆（一共最多 5 个）；有几个球馆时每个场次选在哪个
    val extraVenueIds = remember { mutableStateListOf<String>() }
    // 正在换的那个其他球馆（null = 再加一个）；-1 = 没在选
    var extraIndex by remember { mutableStateOf<Int?>(-1) }
    var didSetup by rememberSaveable { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        if (didSetup) return@LaunchedEffect
        didSetup = true
        val editing = editingGroupId?.let(groupManager::group)
        if (editing != null) {
            name = editing.name
            summary = editing.summary
            if (editing.schedules.isNotEmpty()) {
                schedules.clear()
                schedules.addAll(editing.schedules)
            }
            lowerLevel = editing.levelRange.first
            upperLevel = editing.levelRange.last
            joinPolicy = editing.joinPolicy
            coached = editing.isCoached
            pickedVenueId = editing.venueId
            extraVenueIds.clear()
            extraVenueIds.addAll(editing.venueIds.drop(1))
            return@LaunchedEffect
        }
        if (isEditing) return@LaunchedEffect
        pickedVenueId = venueId ?: env.appState.backend.favoriteVenueIds.firstOrNull { env.appState.backend.venue(it) != null }
        pickedVenue = pickedVenueId?.let(env.appState.backend::venue)
        val level = me?.levelFor(audience) ?: 4
        lowerLevel = maxOf(1, level - 2)
        upperLevel = minOf(9, level + 2)
    }

    // 所有球馆，主球馆在前
    val allVenueIds = listOfNotNull(pickedVenueId) + extraVenueIds
    val allCourts = allVenueIds.mapNotNull(groupManager::venue)

    /** 主球馆换成了其他球馆里的一个、或者删了球馆：去掉重复，场次回到主球馆 */
    fun normalizeCourts() {
        pickedVenueId?.let { main -> extraVenueIds.removeAll { it == main } }
        val ids = listOfNotNull(pickedVenueId) + extraVenueIds
        schedules.indices.forEach { index ->
            val court = schedules[index].venueId
            if (court != null && (court !in ids || court == ids.firstOrNull())) schedules[index] = schedules[index].copy(venueId = null)
        }
    }

    val validation: String? = run {
        val trimmed = name.trim()
        when {
            trimmed.characterCount !in PlayGroup.NAME_LIMIT -> tr("球群名称需要 2–20 个字")
            !isEditing && pickedVenueId == null -> tr("选择固定的球馆")
            schedules.any { it.endMinutes - it.startMinutes < 60 } -> tr("每场至少 1 小时")
            schedules.any { it.endMinutes - it.startMinutes > 720 } -> tr("每场最长 12 小时")
            else -> null
        }
    }
    val saved = tr("已保存")

    fun save() {
        isSaving = true
        scope.launch {
            try {
                if (editingGroupId != null) {
                    groupManager.update(editingGroupId, name, schedules.toList(), lowerLevel..upperLevel, joinPolicy, summary, coached, allVenueIds)
                    env.appState.showToast(saved, Toast.Style.Success)
                    env.router.pop()
                } else {
                    val venue = pickedVenueId ?: return@launch
                    val group = groupManager.create(
                        name, venue, schedules.toList(), lowerLevel..upperLevel, joinPolicy, summary, audience, coached, extraVenueIds.toList(),
                    )
                    haptics.success()
                    env.appState.showToast(L10n.tr("已建群，群号 %@，可以分享到微信", group.inviteCode), Toast.Style.Success)
                    env.router.pop()
                    env.router.open(Route.Group(group.id))
                }
            } catch (error: RemoteError) {
                env.appState.showError(error)
            } catch (error: BackendError) {
                env.appState.showError(error)
            }
            isSaving = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(if (isEditing) tr("编辑球群") else tr("建一个球群"), onBack = { env.router.pop() })
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xxl),
        ) {
            FormSection(tr("名称")) {
                MultilineField(name, { name = it }, tr("例：周四晚双打群"), label = tr("球群名称"), characterLimit = 20, maxLines = 1)
                MultilineField(summary, { summary = it }, tr("例：轮换上场，新手友好；费用按人头在前台付"), label = tr("介绍（可选）"), characterLimit = 120, minLines = 2)
            }
            ToggleRow(tr("教练带课"), coached, { on ->
                coached = on
                // 关掉“教练带课”以后回到普通群的 4–40 人（步长 2）
                if (!on) schedules.indices.forEach { schedules[it] = schedules[it].copy(capacity = maxOf(4, schedules[it].capacity + schedules[it].capacity % 2)) }
            }) {
                RulesButton(tr("教练带课"), listOf(tr("每场最少 1 人，最多 40 人。"), tr("水平范围只作参考。")))
            }
            if (!isEditing) {
                FormSection(tr("固定球馆")) {
                    Row(
                        Modifier.fillMaxWidth().pressable(scale = 0.98f) { showVenuePicker = true }
                            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(Sym.sportscourtFill, fill = colors.sky, size = 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(pickedVenue?.name ?: tr("选择球馆"), style = AppTheme.Typography.bodyBold, color = colors.ink)
                            pickedVenue?.address?.let { Text(it, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        }
                        Symbol(Sym.chevronRight, size = 14, tint = colors.inkTertiary)
                    }
                }
            }
            if (pickedVenueId != null) {
                FormSection(tr("其他球馆")) {
                    extraVenueIds.forEachIndexed { index, id ->
                        CourtButton(groupManager.venue(id), id, onRemove = {
                            extraVenueIds.remove(id)
                            normalizeCourts()
                        }) { extraIndex = index }
                    }
                    if (allVenueIds.size < PlayGroup.MAX_VENUES) CourtButton(null, tr("再加一个球馆")) { extraIndex = null }
                }
            }
            FormSection(tr("每周固定场次")) {
                schedules.forEachIndexed { index, schedule ->
                    ScheduleEditor(
                        schedule, coached, canDelete = schedules.size > 1, courts = allCourts,
                        courtId = schedule.venueId?.takeIf { it in allVenueIds } ?: allVenueIds.firstOrNull(),
                        onChange = { schedules[index] = it },
                    ) { schedules.removeAt(index) }
                }
                if (schedules.size < PlayGroup.MAX_SCHEDULES) {
                    TextAction(tr("再加一个场次"), {
                        val last = schedules.last()
                        schedules.add(GroupSchedule(UUID.randomUUID().toString(), last.weekday % 7 + 1, last.startMinutes, last.endMinutes, last.capacity))
                    })
                }
            }
            if (!isEditing) {
                FormSection(tr("谁能来")) {
                    AudiencePicker(me?.gender?.takeIf { it != Gender.Unspecified }?.let(::listOf).orEmpty(), audience) { choice ->
                        audience = choice
                        // 换了谁能来，自己的等级可能跟着换算：范围重新围着自己
                        val level = me?.levelFor(choice) ?: 4
                        lowerLevel = maxOf(1, level - 2)
                        upperLevel = minOf(9, level + 2)
                    }
                }
            }
            FormSection(tr("接受的水平")) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    LevelStepper(tr("最低"), lowerLevel, 1..upperLevel, Modifier.weight(1f)) { lowerLevel = it }
                    LevelStepper(tr("最高"), upperLevel, lowerLevel..9, Modifier.weight(1f)) { upperLevel = it }
                }
            }
            FormSection(tr("加入方式")) {
                SegmentedSticker(PlayGroup.JoinPolicy.entries, joinPolicy, { joinPolicy = it }) { it.title }
            }
        }
        Column(Modifier.fillMaxWidth().background(colors.canvas)) {
            InsetDivider()
            Column(
                Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
            ) {
                if (validation != null && (isEditing || name.isNotEmpty())) Text(validation, style = AppTheme.Typography.caption, color = colors.danger)
                BrutalButton(if (isEditing) tr("保存") else tr("建群"), ::save, enabled = validation == null && !isSaving)
            }
        }
    }
    if (showVenuePicker) {
        SheetScaffold(onDismiss = { showVenuePicker = false }, fullHeight = true) {
            GroupVenuePicker(pickedVenueId) { venue ->
                pickedVenueId = venue.id
                pickedVenue = venue
                showVenuePicker = false
                normalizeCourts()
            }
        }
    }
    val replacing = extraIndex
    if (replacing != -1) {
        SheetScaffold(onDismiss = { extraIndex = -1 }, fullHeight = true) {
            GroupVenuePicker(replacing?.let(extraVenueIds::getOrNull)) { venue ->
                extraIndex = -1
                // 选好了：换掉那一家，或者加在最后（和已有的重复就不加）
                if (venue.id == pickedVenueId || venue.id in extraVenueIds) return@GroupVenuePicker
                if (replacing != null && replacing in extraVenueIds.indices) {
                    extraVenueIds[replacing] = venue.id
                } else if (allVenueIds.size < PlayGroup.MAX_VENUES) {
                    extraVenueIds.add(venue.id)
                }
                env.appState.backend.cacheVenue(venue)
                normalizeCourts()
            }
        }
    }
}

/** 建群时的一个其他球馆：和固定球馆一样的样子，点开换一家，右边可以删；没有球馆时是“再加一个球馆” */
@Composable
private fun CourtButton(court: Venue?, title: String, onRemove: (() -> Unit)? = null, onClick: () -> Unit) {
    val colors = AppTheme.colors
    Row(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(
            Modifier.weight(1f).pressable(scale = 0.98f, onClick = onClick),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconTile(Sym.sportscourtFill, fill = colors.sky, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(court?.name ?: title, style = AppTheme.Typography.bodyBold, color = colors.ink)
                court?.address?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (onRemove == null) Symbol(Sym.chevronRight, size = 14, tint = colors.inkTertiary)
        }
        if (onRemove != null) {
            val label = tr("移除%@", court?.name ?: title)
            Box(
                Modifier.size(44.dp).pressable(scale = 0.9f, onClick = onRemove).semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) { Symbol(Sym.xmarkCircleFill, size = 22, tint = colors.inkTertiary) }
        }
    }
}

@Composable
private fun FormSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Text(title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        content()
    }
}

/** 星期一到星期日（简写）和对应的值（1 = 周日） */
@Composable
private fun weekdays(): List<Pair<Int, String>> =
    listOf(2 to tr("一"), 3 to tr("二"), 4 to tr("三"), 5 to tr("四"), 6 to tr("五"), 7 to tr("六"), 1 to tr("日"))

@Composable
private fun ScheduleEditor(
    schedule: GroupSchedule, coached: Boolean, canDelete: Boolean, courts: List<Venue>, courtId: String?,
    onChange: (GroupSchedule) -> Unit, onDelete: () -> Unit,
) {
    val colors = AppTheme.colors
    val capacityRange = GroupSchedule.capacityRange(coached)
    val step = if (coached) 1 else 2
    Column(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            weekdays().forEach { (value, title) ->
                ChoiceChip(title, isSelected = schedule.weekday == value, modifier = Modifier.weight(1f)) { onChange(schedule.copy(weekday = value)) }
            }
        }
        // 几个球馆时选这一场在哪个（主球馆存成 null）
        if (courts.size > 1) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                courts.forEach { court ->
                    ChoiceChip(court.name, isSelected = courtId == court.id) {
                        onChange(schedule.copy(venueId = court.id.takeIf { it != courts.first().id }))
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            TimeStepper(tr("开始"), schedule.startMinutes, 6 * 60..23 * 60, Modifier.weight(1f)) { onChange(schedule.copy(startMinutes = it)) }
            TimeStepper(tr("结束"), schedule.endMinutes, 7 * 60..24 * 60, Modifier.weight(1f)) { onChange(schedule.copy(endMinutes = it)) }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("每场 %lld 个名额", schedule.capacity), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
            StepButtons(
                canDecrease = schedule.capacity - step in capacityRange, canIncrease = schedule.capacity + step in capacityRange,
                onDecrease = { onChange(schedule.copy(capacity = schedule.capacity - step)) },
                onIncrease = { onChange(schedule.copy(capacity = schedule.capacity + step)) },
            )
        }
        MultilineField(
            schedule.feeNote.orEmpty(), { onChange(schedule.copy(feeNote = it.ifEmpty { null })) }, "", label = tr("费用说明（选填）"),
            characterLimit = GroupSchedule.FEE_NOTE_LIMIT,
        )
        if (canDelete) TextAction(tr("删掉这个场次"), onDelete, color = colors.danger)
    }
}

/** iPhone 的 Stepper：一组“− +” */
@Composable
private fun StepButtons(canDecrease: Boolean, canIncrease: Boolean, onDecrease: () -> Unit, onIncrease: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(Modifier.sticker(colors.surfaceMuted, radius = 10.dp, shadow = AppTheme.Elevation.none, strokeWidth = 1.5.dp), verticalAlignment = Alignment.CenterVertically) {
        StepIcon(Sym.minus, "−", canDecrease) {
            haptics.selection()
            onDecrease()
        }
        Spacer(Modifier.width(1.5.dp).size(1.5.dp, 20.dp).background(colors.divider))
        StepIcon(Sym.plus, "+", canIncrease) {
            haptics.selection()
            onIncrease()
        }
    }
}

@Composable
private fun StepIcon(icon: SymbolId, label: String, enabled: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    Box(
        Modifier.size(48.dp, 36.dp).pressable(scale = 0.9f, enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Symbol(icon, size = 14, tint = if (enabled) colors.ink else colors.inkTertiary) }
}

/** 等级加减（1–9）。对应 iPhone CreateRoomView.swift 的 LevelStepper */
@Composable
private fun LevelStepper(title: String, level: Int, range: IntRange, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val label = tr("%@等级", title)
    val value = tr("%lld 级", level)
    Row(
        modifier.sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(vertical = 4.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = value
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepIcon(Sym.minus, "−", level - 1 in range) {
            haptics.selection()
            onChange(level - 1)
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, style = AppTheme.Typography.caption, color = colors.inkSecondary)
            Text("Lv.$level", style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink)
        }
        StepIcon(Sym.plus, "+", level + 1 in range) {
            haptics.selection()
            onChange(level + 1)
        }
    }
}

/** 时间加减（每次 30 分钟），点时间从列表里选。对应 iPhone MatchSetupView.swift 的 TimeStepper */
@Composable
private fun TimeStepper(title: String, minutes: Int, range: IntRange, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var menu by remember { mutableStateOf(false) }
    val label = tr("%@时间", title)
    val value = tr("%lld 点 %@ 分", minutes / 60, String.format(Locale.ROOT, "%02d", minutes % 60))
    fun adjust(delta: Int) {
        val next = minutes + delta
        if (next in range) {
            haptics.selection()
            onChange(next)
        }
    }
    Column(
        modifier.sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(vertical = AppTheme.Spacing.sm, horizontal = AppTheme.Spacing.xs)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = value
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = AppTheme.Typography.caption, color = colors.inkSecondary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepIcon(Sym.minus, "−", minutes - 30 in range) { adjust(-30) }
            Box(Modifier.weight(1f).defaultMinSize(minHeight = 40.dp).pressable(scale = 0.96f) { menu = true }, contentAlignment = Alignment.Center) {
                Text(clock(minutes), style = AppTheme.Typography.title3.copy(fontFeatureSettings = "tnum"), color = colors.ink, maxLines = 1)
                DropdownMenu(menu, { menu = false }, containerColor = colors.surface, modifier = Modifier.fillMaxHeight(0.5f)) {
                    (range step 30).forEach { option ->
                        DropdownMenuItem(
                            text = { Text(clock(option), style = AppTheme.Typography.body, color = colors.ink) },
                            trailingIcon = if (option == minutes) ({ Symbol(Sym.checkmark, size = 14, tint = colors.ink) }) else null,
                            onClick = {
                                haptics.selection()
                                onChange(option)
                                menu = false
                            },
                        )
                    }
                }
            }
            StepIcon(Sym.plus, "+", minutes + 30 in range) { adjust(30) }
        }
    }
}

private fun clock(minutes: Int): String = String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)

/** “谁能来”：不限，或只限自己的性别（null = 不限）。对应 iPhone GenderViews.swift 的 AudiencePicker */
@Composable
private fun AudiencePicker(options: List<Gender>, selection: Gender?, onSelect: (Gender?) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        ChoiceChip(tr("不限"), isSelected = selection == null) { onSelect(null) }
        options.forEach { gender -> ChoiceChip(gender.onlyLabel, isSelected = selection == gender) { onSelect(gender) } }
        RulesButton(tr("谁能来"), listOf(tr("男女一起打时，女子等级按低约 1.5 级来算，这样比赛势均力敌。"), tr("只有符合条件的人能看到和加入。")), Modifier.align(Alignment.CenterVertically))
    }
}

/** 公开局、球群按参加的人算等级：只限女生按女子等级，男女都能来时女子等级按低 1.5 级换算（iPhone GenderViews.swift 的 level(for:)） */
private fun User.levelFor(audience: Gender?): Int {
    val offset = if (gender == Gender.Female && audience != Gender.Female) Gender.WOMEN_OFFSET else 0.0
    return (displayTier.rating - offset).roundToInt().coerceIn(1, 9)
}

/** 选一家球馆（建群用）：附近的，或者按名字、地址搜 */
@Composable
private fun GroupVenuePicker(selectedId: String?, onPick: (Venue) -> Unit) {
    val env = LocalEnv.current
    val backend = env.appState.backend
    val colors = AppTheme.colors
    var query by remember { mutableStateOf("") }
    var nearby by remember { mutableStateOf<List<Venue>>(emptyList()) }
    var hits by remember { mutableStateOf<List<Venue>?>(null) }
    var center by remember { mutableStateOf(Coordinate.fallbackCenter) }
    LaunchedEffect(Unit) {
        center = env.groupManager.currentCenter()
        nearby = try {
            backend.venuesNear(center, env.groupManager.radiusKm)
        } catch (_: RemoteError) {
            emptyList()
        }
    }
    LaunchedEffect(query) {
        if (query.isBlank()) {
            hits = null
            return@LaunchedEffect
        }
        delay(300)
        hits = try {
            backend.searchVenues(query, center)
        } catch (_: RemoteError) {
            emptyList()
        }
    }
    val favorites = backend.favoriteVenueIds.mapNotNull(backend::venue)
    Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
        Text(
            tr("选择球馆"), style = AppTheme.Typography.title, color = colors.ink,
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.md).semantics { heading() },
        )
        StickerTextField(query, { query = it }, tr("搜索球馆"), Modifier.padding(horizontal = AppTheme.Spacing.screen), style = AppTheme.Typography.body)
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(AppTheme.Spacing.screen),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            val found = hits
            val list = found ?: (favorites + nearby.filter { venue -> favorites.none { it.id == venue.id } })
            if (found != null && found.isEmpty()) EmptyStateView(Sym.magnifyingglass, tr("没有找到“%@”", query.trim()))
            list.forEach { venue ->
                val isOn = venue.id == selectedId
                Row(
                    Modifier.fillMaxWidth().pressable(scale = 0.98f) { onPick(venue) }
                        .sticker(if (isOn) colors.lime else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                        .padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(venue.name, style = AppTheme.Typography.bodyBold, color = if (isOn) colors.onAccent else colors.ink)
                        Text(
                            listOf(DistanceFormatter.string(venue.distanceKm(center)), venue.compactAddress).filter { it.isNotEmpty() }.joinToString(" · "),
                            style = AppTheme.Typography.footnote, color = if (isOn) colors.onAccent else colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                    if (isOn) Symbol(Sym.checkmark, size = 15, tint = colors.onAccent)
                }
            }
        }
    }
}

// MARK: - 球群规则（“?”里的要点）

object GroupRules {
    @Composable
    fun points(): List<String> = listOf(
        tr("固定时间、固定球馆的局。"),
        tr("一键报名，满了自动候补。"),
        tr("有人退出，候补按顺序递补，并通知你。"),
        tr("开场前 2 小时内退出，算临时取消。"),
    )

    @Composable
    fun joinPoints(group: PlayGroup): List<String> {
        val points = mutableListOf<String>()
        if (group.joinPolicy == PlayGroup.JoinPolicy.Approval) {
            points += tr("这个群需要组织者同意。")
        } else if (!group.isCoached) {
            points += tr("水平符合就能直接加入。")
        }
        points += tr("加入后就能报名每周的场次。")
        return points + points()
    }
}
