package com.badie.app.features.social

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.LevelBadge
import com.badie.app.design.NewPlayerBadge
import com.badie.app.design.NicknameText
import com.badie.app.design.PraiseTagsView
import com.badie.app.design.ReliableBadge
import com.badie.app.design.RulesButton
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.VerifiedBadge
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.features.messages.MessagePermission
import com.badie.app.features.rankings.ChallengeComposerSheet
import com.badie.app.l10n.tr
import com.badie.app.models.ChallengeAvailability
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.MyStrikes
import com.badie.app.models.ReportReason
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import com.badie.app.models.UsualTimeText
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import kotlinx.coroutines.launch
import java.time.ZoneId

// 球友资料卡、举报、我的爽约记录。
// 对应 iPhone 的 Features/Social/PlayerProfileSheet.swift、Features/Messages/ChatView.swift 的 ReportSheet、Features/Social/StrikesSheet.swift

/** 球友资料（半屏弹层的内容）：等级、口碑、履约，以及加好友 / 私信 / 约球 / 屏蔽 */
@Composable
fun PlayerProfileSheet(userId: String, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    var showReport by remember { mutableStateOf(false) }
    var showChallenge by remember { mutableStateOf(false) }
    // 手机上还没有这个人的资料时先去服务器拉，拉完才判断找不到
    var isLoading by remember(userId) { mutableStateOf(false) }
    LaunchedEffect(userId) {
        isLoading = friendManager.user(userId) == null
        friendManager.refreshPlayer(userId)
        try {
            friendManager.refreshGames()
        } catch (_: RemoteError) {
        }
        isLoading = false
    }
    val user = friendManager.user(userId)
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        when {
            user != null -> Column(
                Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.xl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
            ) {
                Header(user)
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    StatTile(user.gamesBand, tr("打过"), Modifier.weight(1f))
                    StatTile(user.preferredMode?.title ?: tr("都可以"), tr("偏好"), Modifier.weight(1f))
                }
                UsualTimesLine(user)
                WinRateLine(user)
                ReputationCard(user)
                ConnectionCard(user)
                if (user.bio.isNotEmpty()) {
                    Text("“${user.bio}”", style = AppTheme.Typography.body, color = AppTheme.colors.ink, modifier = Modifier.card())
                }
                Actions(user, onDismiss, onReport = { showReport = true }, onChallenge = { showChallenge = true })
            }
            isLoading -> Box(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xxl, bottom = AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = AppTheme.colors.ink)
            }
            else -> EmptyStateView(Sym.personFillQuestionmark, tr("找不到这位球友"))
        }
    }
    if (showReport) {
        SheetScaffold(onDismiss = { showReport = false }, fullHeight = true) {
            ReportSheet(userId, user?.nickname ?: tr("TA")) { showReport = false }
        }
    }
    if (showChallenge) {
        SheetScaffold(onDismiss = { showChallenge = false }) { ChallengeComposerSheet(userId) { showChallenge = false } }
    }
}

@Composable
private fun Header(user: User) {
    val friendManager = LocalEnv.current.friendManager
    val colors = AppTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
        val shadow = colors.shadow
        AvatarView(
            user,
            Modifier.drawBehind { drawCircle(shadow, center = center.copy(x = center.x + 3.dp.toPx(), y = center.y + 4.dp.toPx())) },
            size = 76.dp,
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NicknameText(user, style = AppTheme.Typography.title2)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                LevelBadge(user.displayTier)
                if (user.isReliable) ReliableBadge()
                if (user.isNewPlayer) NewPlayerBadge()
                VerifiedBadge(user.verificationStatus)
                // 男女等级分开算：标出这个等级是男子还是女子的
                user.gender.ladderLabel?.let { TagPill(it, fill = colors.surface, foreground = colors.ink) }
                val (recent, until) = friendManager.noShows(user.id)
                if (recent > 0) TagPill(tr("近 180 天爽约 %lld 次", recent), fill = colors.pink)
                if (until != null) TagPill(MyStrikes.suspensionText(until), fill = colors.surfaceMuted, foreground = colors.ink)
            }
            friendManager.distance(user.id)?.let {
                Text(tr("离你 %@", DistanceFormatter.approximate(it)), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
        }
    }
}

@Composable
private fun IconLine(icon: SymbolId, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Symbol(icon, size = 13, tint = AppTheme.colors.inkSecondary)
        Text(text, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
    }
}

/** 空闲时间归纳成一行：“常有空：工作日晚上 · 周末下午” */
@Composable
private fun UsualTimesLine(user: User) {
    val slots = LocalEnv.current.friendManager.cache.usualTimes[user.id].orEmpty()
    UsualTimeText.summary(slots)?.let { IconLine(Sym.calendar, tr("常有空：%@", it)) }
}

/** 场次够了才公开胜率，否则不显示 */
@Composable
private fun WinRateLine(user: User) {
    val rate = LocalEnv.current.friendManager.cache.winRates[user.id] ?: return
    if (rate.isPublic) IconLine(Sym.chartBarFill, tr("本月胜率 %lld%%（%lld 场 · %lld 位对手）", rate.percentage, rate.games, rate.opponents))
}

/** 别人只看到正面印象和“靠谱”徽章；评分数字只在内部用于匹配排序 */
@Composable
private fun ReputationCard(user: User) {
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("球友印象"), style = AppTheme.Typography.headline, color = AppTheme.colors.ink)
            RulesButton(
                tr("球友印象"),
                listOf(
                    tr("评价的球友满 5 位才显示印象"),
                    if (user.isNewPlayer) {
                        tr("评价不足 5 次，等级为问卷定级 %@，仅供参考", SkillTier.ofRating(user.selfRating).text)
                    } else {
                        tr("等级由问卷与球友评价综合得出")
                    },
                ),
            )
        }
        PraiseTagsView(user.reputation.publicTags, emptyText = tr("暂无印象"))
    }
}

/** 你们的交集：一起打过几场、共同球友（帮助判断“这个人靠不靠谱、是不是圈子里的人”） */
@Composable
private fun ConnectionCard(user: User) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val together = env.friendManager.gamesTogether(user.id)
    val mutual = env.friendManager.mutualFriends(user.id)
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Text(tr("你们的交集"), style = AppTheme.Typography.headline, color = colors.ink)
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            IconTile(Sym.sportscourtFill, fill = colors.lime, size = 36.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (together.isEmpty()) tr("还没一起打过") else tr("一起打过 %lld 场", together.size),
                    style = AppTheme.Typography.bodyBold, color = colors.ink,
                )
                together.firstOrNull()?.let { last ->
                    Text(
                        tr("最近一次：%@ · %@", DateText.relativeDay(last.startsAt), last.venueName),
                        style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1,
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            IconTile(Sym.person2Fill, fill = colors.lavender, size = 36.dp)
            Text(
                if (mutual.isEmpty()) tr("没有共同球友") else tr("共同球友 %lld 位", mutual.size),
                style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f),
            )
            Row {
                mutual.take(4).forEachIndexed { index, friend ->
                    AvatarView(friend, Modifier.offset(x = (-8 * index).dp).pressable { env.appState.showPlayer(friend.id) }, size = 30.dp)
                }
            }
        }
    }
}

/** 能挑战就显示按钮；对方不接受挑战时整块隐藏；其他情况灰掉并说明原因 */
@Composable
private fun ChallengeButton(user: User, onChallenge: () -> Unit) {
    val env = LocalEnv.current
    val availability = when (env.friendManager.cache.challengeStatus[user.id]) {
        "available" -> ChallengeAvailability.Available
        "friends_only" -> ChallengeAvailability.FriendsOnly
        "level_out_of_range" -> ChallengeAvailability.LevelOutOfRange
        "already_pending" -> ChallengeAvailability.AlreadyPending
        "too_many_outgoing" -> ChallengeAvailability.TooManyOutgoing
        "daily_limit" -> ChallengeAvailability.DailyLimitReached
        "target_busy" -> ChallengeAvailability.TargetBusy
        else -> ChallengeAvailability.Unavailable
    }
    if (user.id == env.appState.currentUser?.id || availability == ChallengeAvailability.NotAccepting) return
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        BrutalButton(
            onChallenge, kind = ButtonKind.Accent(AppTheme.colors.peach), size = ButtonSize.Medium,
            enabled = availability == ChallengeAvailability.Available,
        ) { IconLabel(Sym.flag2CrossedFill, tr("发起单打挑战")) }
        availability.reason()?.let {
            Text(it, style = AppTheme.Typography.caption, color = AppTheme.colors.inkTertiary, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun RowScope.IconLabel(icon: SymbolId, title: String) {
    Symbol(icon, size = 15)
    Spacer(Modifier.size(AppTheme.Spacing.sm))
    Text(title, maxLines = 1)
}

/** 私信按钮：按关系决定能不能聊、在哪聊（陌生人不能直接私信） */
@Composable
private fun RowScope.MessageButton(user: User, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val messageManager = env.messageManager
    when (val permission = messageManager.permission(user.id)) {
        MessagePermission.Allowed, MessagePermission.PendingRequest -> BrutalButton({
            onDismiss()
            env.router.open(Route.Chat(user.id), MainTab.Messages)
        }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium) { IconLabel(Sym.bubbleLeftFill, tr("私信")) }
        is MessagePermission.Request -> BrutalButton({
            onDismiss()
            env.router.open(Route.Chat(user.id), MainTab.Messages)
        }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium) { IconLabel(Sym.envelopeFill, tr("发消息请求")) }
        is MessagePermission.GameChat -> BrutalButton({
            val threadId = messageManager.gameChatId(permission.gameId)
            onDismiss()
            env.router.open(Route.GroupChat(threadId), MainTab.Messages)
        }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium) { IconLabel(Sym.person3Fill, tr("球局群聊")) }
        MessagePermission.FriendsOnly, MessagePermission.NewAccount, MessagePermission.Blocked -> Unit
    }
}

@Composable
private fun Actions(user: User, onDismiss: () -> Unit, onReport: () -> Unit, onChallenge: () -> Unit) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val messageManager = env.messageManager
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val isBlocked = messageManager.isBlocked(user.id)
    val removed = tr("已删除")
    val blocked = tr("已屏蔽，对方不会收到通知")
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        if (isBlocked) {
            BrutalButton(tr("解除屏蔽"), { messageManager.unblock(user.id) }, kind = ButtonKind.Secondary)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                MessageButton(user, onDismiss)
                if (friendManager.isFriend(user.id)) {
                    BrutalButton({
                        onDismiss()
                        env.router.open(Route.CreateRoom(invitee = user.id), MainTab.Games)
                    }, Modifier.weight(1f), size = ButtonSize.Medium) { IconLabel(Sym.sportscourtFill, tr("约 TA 打球")) }
                } else {
                    FriendActionButtonLarge(user.id, Modifier.weight(1f))
                }
            }
            ChallengeButton(user, onChallenge)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg, Alignment.CenterHorizontally)) {
            if (friendManager.isFriend(user.id)) {
                TextAction(tr("删除球友"), {
                    scope.launch {
                        try {
                            friendManager.remove(user.id)
                        } catch (_: RemoteError) {
                        }
                        env.appState.showToast(removed)
                    }
                })
            }
            if (!isBlocked) {
                TextAction(tr("屏蔽"), {
                    messageManager.block(user.id)
                    env.appState.showToast(blocked)
                    onDismiss()
                })
            }
            TextAction(tr("举报"), onReport, color = colors.danger)
        }
    }
}

@Composable
private fun FriendActionButtonLarge(userId: String, modifier: Modifier) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    val scope = rememberCoroutineScope()
    val added = tr("已添加为球友")
    val sent = tr("申请已发送")
    val incoming = friendManager.incomingRequest(userId)
    when {
        friendManager.hasPendingRequest(userId) ->
            BrutalButton(tr("已申请，等待通过"), {}, modifier, kind = ButtonKind.Secondary, size = ButtonSize.Medium, enabled = false)
        incoming != null -> BrutalButton(tr("通过好友申请"), {
            scope.launch {
                try {
                    friendManager.respond(incoming, true)
                } catch (_: RemoteError) {
                }
                env.appState.showToast(added, Toast.Style.Success)
            }
        }, modifier, size = ButtonSize.Medium)
        else -> BrutalButton({
            scope.launch {
                try {
                    friendManager.sendRequest(userId)
                    env.appState.showToast(sent, Toast.Style.Success)
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
            }
        }, modifier, size = ButtonSize.Medium) { IconLabel(Sym.personBadgePlus, tr("加球友")) }
    }
}

// MARK: - 举报

@Composable
fun ReportSheet(userId: String, nickname: String, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    var reason by remember { mutableStateOf<ReportReason?>(null) }
    var detail by remember { mutableStateOf("") }
    var alsoBlock by remember { mutableStateOf(true) }
    val thanks = tr("举报已提交，感谢你让社区更安全")
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("举报 %@", nickname), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f, fill = false))
            RulesButton(tr("举报"), listOf(tr("举报信息只有平台能看到。"), tr("我们会在 24 小时内处理。")))
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
        }
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            ReportReason.entries.forEach { option ->
                val isSelected = reason == option
                Row(
                    Modifier.fillMaxWidth()
                        .pressable(scale = 1f, role = Role.RadioButton) {
                            haptics.selection()
                            reason = option
                        }
                        .semantics { selected = isSelected }
                        .sticker(if (isSelected) colors.pink else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                        .padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(option.title, style = AppTheme.Typography.bodyBold, color = if (isSelected) colors.onAccent else colors.ink, modifier = Modifier.weight(1f))
                    Symbol(if (isSelected) Sym.largecircleFillCircle else Sym.circle, size = 20, tint = if (isSelected) colors.onAccent else colors.inkTertiary)
                }
            }
        }
        MultilineField(detail, { detail = it }, tr("发生了什么？"), label = tr("补充说明（可选）"), characterLimit = 200, minLines = 2)
        ToggleRow(tr("同时屏蔽对方"), alsoBlock, { alsoBlock = it })
        BrutalButton(tr("提交举报"), {
            val chosen = reason ?: return@BrutalButton
            scope.launch {
                env.messageManager.report(userId, chosen, detail.take(200), alsoBlock)
                env.appState.showToast(thanks, Toast.Style.Success)
                onDismiss()
            }
        }, kind = ButtonKind.Destructive, enabled = reason != null)
    }
}

// MARK: - 爽约记录

/** 爽约记录：现在能不能约球、每一次的情况；48 小时内可以申诉 */
@Composable
fun StrikesSheet(onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val friendManager = env.friendManager
    LaunchedEffect(Unit) {
        friendManager.markStrikesSeen()
        if (friendManager.strikes == null) friendManager.refreshStrikes()
    }
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        val strikes = friendManager.strikes ?: return@Column
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(
                strikes.suspendedUntil?.let { MyStrikes.suspensionText(it) } ?: tr("近 180 天爽约 %lld 次", strikes.recent),
                style = AppTheme.Typography.title2, color = AppTheme.colors.ink, modifier = Modifier.weight(1f, fill = false),
            )
            RulesButton(
                tr("爽约规则"),
                listOf(tr("180 天内第二次：7 天不能约球"), tr("第三次：以后不能约球"), tr("180 天内没再爽约就重新计数"), tr("爽约后 48 小时内可以申诉")),
            )
        }
        strikes.strikes.forEach { StrikeRow(it) }
    }
}

@Composable
private fun StrikeRow(strike: MyStrikes.Strike) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var appealing by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    val locale = LocalConfiguration.current.locales[0]
    val submitted = tr("申诉已提交，我们会在 24 小时内回复。")
    Column(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                listOfNotNull(dayText(strike.gameStartsAt, strike.timeZone ?: ZoneId.systemDefault(), locale), strike.venue).joinToString(" · "),
                style = AppTheme.Typography.subheadlineBold, color = colors.ink, modifier = Modifier.weight(1f),
            )
            statusText(strike.status)?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary) }
        }
        if (appealing) {
            Text(tr("发生了什么？"), style = AppTheme.Typography.footnoteBold, color = colors.ink)
            MultilineField(text, { text = it }, tr("比如：去了，只是忘了签到。"), minLines = 3, maxLines = 6, radius = AppTheme.Radius.md)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalButton(tr("提交申诉"), {
                    isSending = true
                    scope.launch {
                        try {
                            env.friendManager.appealStrike(strike.id, text.trim())
                            appealing = false
                            env.appState.showToast(submitted, Toast.Style.Success)
                        } catch (error: RemoteError) {
                            env.appState.showError(error)
                        }
                        isSending = false
                    }
                }, size = ButtonSize.Small, fullWidth = false, enabled = !isSending && text.trim().length >= 5)
                TextAction(tr("取消"), { appealing = false })
            }
        } else if (strike.canAppeal) {
            BrutalButton(tr("申诉"), {
                text = ""
                appealing = true
            }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
        }
    }
}

/** “11月2日周日”：按那场球的球馆时区 */
private fun dayText(millis: Long, zone: ZoneId, locale: java.util.Locale): String = try {
    val format = android.icu.text.DateFormat.getInstanceForSkeleton("MMMdEEE", locale)
    format.timeZone = android.icu.util.TimeZone.getTimeZone(zone.id)
    format.format(java.util.Date(millis))
} catch (_: RuntimeException) {
    DateText.relativeDay(millis, zone = zone)
}

@Composable
private fun statusText(status: MyStrikes.Status): String? = when (status) {
    MyStrikes.Status.Active -> null
    MyStrikes.Status.Appealed -> tr("申诉审核中")
    MyStrikes.Status.Upheld -> tr("申诉未通过")
    MyStrikes.Status.Overturned -> tr("申诉后已撤销")
}
