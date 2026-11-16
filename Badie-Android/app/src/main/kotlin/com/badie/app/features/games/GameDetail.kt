package com.badie.app.features.games

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.InsetDivider
import com.badie.app.design.LoadingDots
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.design.Toast
import androidx.compose.ui.semantics.selected
import com.badie.app.models.DateText
import com.badie.app.models.Game
import com.badie.app.models.GameCount
import com.badie.app.models.GameStatus
import com.badie.app.models.MessageThread
import com.badie.app.models.PlayWindow
import com.badie.app.models.ResultStatus
import com.badie.app.models.User
import com.badie.app.models.VenueStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.launch
import kotlin.math.ceil

// 球局详情。对应 iPhone 的 Features/Games/GameDetailView.swift

private enum class ResultSheetPurpose { Complete, Confirm }

@Composable
fun GameDetailScreen(id: String) {
    val env = LocalEnv.current
    val book = env.roomManager.book
    val game = book.game(id)
    val context = LocalContext.current
    var showsMenu by remember { mutableStateOf(false) }
    var showsCancel by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("球局详情"), onBack = { env.router.pop() }) {
            if (game != null) {
                Box {
                    IconButton(Sym.ellipsis, tr("更多操作")) { showsMenu = true }
                    DropdownMenu(showsMenu, { showsMenu = false }, containerColor = AppTheme.colors.surface) {
                        MenuItem(tr("分享球局"), Sym.squareAndArrowUp) {
                            showsMenu = false
                            SystemActions.share(context, game.shareText())
                        }
                        if (game.isUpcoming() && game.isTimeSet) {
                            MenuItem(tr("加入日历"), Sym.calendarBadgePlus) {
                                showsMenu = false
                                SystemActions.addToCalendar(context, game)
                            }
                        }
                        if (game.isUpcoming()) {
                            MenuItem(tr("取消球局"), Sym.xmarkCircle, destructive = true) {
                                showsMenu = false
                                showsCancel = true
                            }
                        }
                    }
                }
            }
        }
        if (game != null) {
            GameDetailContent(game)
        } else {
            Spacer(Modifier.weight(1f))
            EmptyStateView(Sym.questionmarkFolder, tr("球局不存在或已被删除"))
            Spacer(Modifier.weight(1f))
        }
    }
    if (showsCancel && game != null) {
        val scope = rememberCoroutineScope()
        ConfirmAlert(
            tr("取消球局？"),
            if (game.isLateCancellation()) tr("离开赛不到 2 小时，会记为临时取消。") else tr("会通知其他球友。"),
            tr("确认取消"), onDismiss = { showsCancel = false }, cancelTitle = tr("再想想"),
        ) {
            scope.launch {
                try {
                    book.cancel(game)
                    env.appState.showToast(L10n.tr("已取消，已通知其他球友"))
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
            }
        }
    }
}

@Composable
private fun MenuItem(title: String, icon: SymbolId, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) AppTheme.colors.danger else AppTheme.colors.ink
    DropdownMenuItem(
        text = { Text(title, style = AppTheme.Typography.bodyBold, color = color) },
        leadingIcon = { Symbol(icon, size = 16, tint = color) },
        onClick = onClick,
    )
}

@Composable
private fun GameDetailContent(game: Game) {
    val env = LocalEnv.current
    val book = env.roomManager.book
    val me = env.appState.currentUser?.id
    val players = book.players(game)
    var resultSheet by remember { mutableStateOf<ResultSheetPurpose?>(null) }
    var showsSetTime by remember { mutableStateOf(false) }
    com.badie.app.shell.RefreshEverything(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            GameTicketCard(game, players, me)
            if (game.status == GameStatus.Cancelled) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                    TagPill(cancelledText(game, me, book), icon = Sym.xmarkOctagonFill, fill = AppTheme.colors.surfaceMuted, foreground = AppTheme.colors.ink)
                    if (game.cancelledLate) {
                        RulesButton(tr("临时取消"), listOf(tr("开赛前 2 小时内取消，计为临时取消")))
                    }
                }
            }
            val window = game.window
            if (game.status == GameStatus.Confirmed && window != null) SetTimeCard(window) { showsSetTime = true }
            if (game.status == GameStatus.Confirmed) ActionGrid(game)
            VenueCard(game)
            if (game.status == GameStatus.Confirmed) CheckInCard(game, players, me)
            if (game.mode == com.badie.app.models.GameMode.Doubles) TeamsCard(game, players, me)
            CostCard(game, players, me)
            if (game.status == GameStatus.Confirmed) CompleteSection(game) { resultSheet = ResultSheetPurpose.Complete }
            if (game.status == GameStatus.Completed) ResultSection(game, me) { resultSheet = ResultSheetPurpose.Confirm }
        }
    }
    if (showsSetTime) {
        BadieSheet(onDismiss = { showsSetTime = false }) { dismiss -> SetGameTimeSheet(game, dismiss) }
    }
    resultSheet?.let { purpose ->
        val confirming = purpose == ResultSheetPurpose.Confirm
        BadieSheet(onDismiss = { resultSheet = null }) { dismiss ->
            CompleteGameSheet(game, isConfirming = confirming, initial = if (confirming) suggestedSubmission(game, me) else null) { submission ->
                dismiss()
                env.appState.let { appState ->
                    appState.launchSubmission(env, game, submission, confirming)
                }
            }
        }
    }
}

/** 交赛果：结束球局后直接去评价第一位；确认赛果只提示 */
private fun com.badie.app.shell.AppState.launchSubmission(
    env: com.badie.app.shell.AppEnvironment, game: Game, submission: Submission, confirming: Boolean,
) {
    val book = env.roomManager.book
    val appState = this
    env.roomManager.scope.launch {
        try {
            if (confirming) {
                book.report(game, submission.score, submission.games, submission.choice == Choice.Unsure)
                if (submission.choice == Choice.Unsure) {
                    appState.showToast(L10n.tr("好的，这场不计入胜率"))
                } else {
                    appState.showToast(L10n.tr("已提交，双方一致后计入胜率"), Toast.Style.Success)
                }
            } else {
                book.complete(game, submission.score, submission.games, submission.choice == Choice.Unsure)
                appState.showToast(L10n.tr("球局已完成，去给球友评分"), Toast.Style.Success)
                book.pending(game.id).firstOrNull()?.let { env.router.open(Route.Survey(it.id)) }
            }
        } catch (error: RemoteError) {
            appState.showError(error)
        }
    }
}

// MARK: 定时间

/** 约成了还没定具体几点：谁都可以定；到最晚时间还没定会自动取消，不算谁的 */
@Composable
private fun SetTimeCard(window: PlayWindow, onSet: () -> Unit) {
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("具体几点？"), style = AppTheme.Typography.headline, color = AppTheme.colors.ink)
            RulesButton(
                tr("定时间"),
                listOf(tr("在群聊里商量好，谁都可以点“定时间”"), tr("%@ 前还没定，球局自动取消，不算谁爽约", DateText.deadline(window.deadline))),
            )
        }
        BrutalButton(tr("定时间"), onSet, size = ButtonSize.Medium)
    }
}

// MARK: 四个操作

@Composable
private fun ActionGrid(game: Game) {
    val env = LocalEnv.current
    val context = LocalContext.current
    val colors = AppTheme.colors
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) toggleReminder(env, game, context) else env.appState.showToast(L10n.tr("请在系统设置中允许通知"), Toast.Style.Error)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        ActionTile(Sym.locationNorthLineFill, tr("导航"), colors.sky, Modifier.weight(1f)) {
            if (!SystemActions.navigate(context, game.court)) {
                env.appState.showToast(L10n.tr("未安装%@", L10n.tr("Google 地图")), Toast.Style.Error)
            }
        }
        // 球局群聊：所有人一起沟通，不需要先加好友；赛后 48 小时关闭
        ActionTile(Sym.bubbleLeftAndBubbleRightFill, tr("群聊"), colors.lavender, Modifier.weight(1f)) {
            env.router.open(Route.GroupChat(MessageThread.gameThreadId(game.id)))
        }
        // 还没定具体几点：没有开赛时间可提醒，定好以后再出现
        if (game.isTimeSet) {
            ActionTile(
                if (game.reminderEnabled) Sym.bellBadgeFill else Sym.bellFill,
                if (game.reminderEnabled) tr("已提醒") else tr("提醒"),
                if (game.reminderEnabled) colors.lime else colors.butter,
                Modifier.weight(1f),
            ) {
                val needsPermission = Build.VERSION.SDK_INT >= 33 && !game.reminderEnabled && !ReminderService.canNotify(context)
                if (needsPermission) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else toggleReminder(env, game, context)
            }
        }
        ActionTile(Sym.squareAndArrowUpFill, tr("分享"), colors.pink, Modifier.weight(1f)) {
            SystemActions.share(context, game.shareText())
        }
    }
}

private fun toggleReminder(env: com.badie.app.shell.AppEnvironment, game: Game, context: android.content.Context) {
    val book = env.roomManager.book
    if (book.android == null) book.android = context.applicationContext
    val current = book.game(game.id) ?: game
    val target = !current.reminderEnabled
    if (book.setReminder(current, target)) {
        env.appState.showToast(
            if (target) L10n.tr("将在开赛前 1 天、2 小时、15 分钟提醒你") else L10n.tr("已关闭提醒"),
            Toast.Style.Success,
        )
    } else {
        env.appState.showToast(L10n.tr("请在系统设置中允许通知"), Toast.Style.Error)
    }
}

@Composable
private fun ActionTile(icon: SymbolId, title: String, tint: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(
        modifier.pressable(onClick = onClick).semantics(mergeDescendants = true) { contentDescription = title },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().height(54.dp).sticker(tint, radius = 16.dp, shadow = AppTheme.Elevation.low),
            contentAlignment = Alignment.Center,
        ) {
            Symbol(icon, size = 20, tint = AppTheme.colors.onAccent)
        }
        Text(title, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.ink, maxLines = 1)
    }
}

// MARK: 球馆

@Composable
private fun VenueCard(game: Game) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val venue = env.appState.backend.venue(game.court.id) ?: game.court
    Column(
        Modifier
            .fillMaxWidth()
            .pressable(scale = 0.98f) { env.router.open(Route.Venue(venue.id)) }
            .sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(venue.name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f, fill = false))
                VenueStatusPill(venue.status)
            }
            Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
        }
        Text(venue.address, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
        venue.entranceNote?.let { note ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Symbol(Sym.doorLeftHandOpen, size = 13, tint = colors.ink)
                Text(note, style = AppTheme.Typography.footnote, color = colors.ink)
            }
        }
        venue.timeZoneAbbreviation()?.let { zone ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Symbol(Sym.globe, size = 12, tint = colors.inkTertiary)
                Text(tr("当地时间 %@", zone), style = AppTheme.Typography.caption, color = colors.inkTertiary)
            }
        }
    }
}

/** 球馆可信度（iPhone 的 VenueStatusBadge） */
@Composable
internal fun VenueStatusPill(status: VenueStatus) {
    val colors = AppTheme.colors
    val fill = when (status) {
        VenueStatus.Verified -> colors.mint
        VenueStatus.Confirmed -> colors.sky
        VenueStatus.Unconfirmed -> colors.butter
    }
    TagPill(status.title, icon = status.icon, fill = fill)
}

// MARK: 签到

/** 签到、取消和履约的规则（“?”里） */
@Composable
private fun attendanceRules(): List<String> = listOf(
    tr("开赛前 30 分钟开放签到"),
    tr("签到记录会计入履约率"),
    tr("开赛 2 小时前取消，不影响履约记录"),
    tr("开赛前 2 小时内取消，计为临时取消"),
    tr("爽约和临时取消会被记录"),
    tr("多次临时取消后，约球需要先付 AA"),
)

@Composable
private fun CheckInCard(game: Game, players: List<User>, me: String?) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    val now by rememberNow(30_000)
    var working by remember { mutableStateOf(false) }
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("到场签到"), style = AppTheme.Typography.headline, color = colors.ink)
            RulesButton(tr("签到和履约"), attendanceRules())
            Spacer(Modifier.weight(1f))
            Text(tr("%lld/%lld 已到", game.checkIns.size, game.playerIds.size), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
        }
        for (player in players) {
            Row(
                Modifier.semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                AvatarView(player, Modifier.opensProfile(player.id, me), size = 32.dp)
                Text(if (player.id == me) tr("我") else player.nickname, style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
                val time = game.checkIns[player.id]
                if (time != null) {
                    TagPill(tr("%@ 已到", DateText.time(time)), icon = Sym.checkmark, fill = colors.mint)
                } else {
                    Text(tr("未签到"), style = AppTheme.Typography.footnote, color = colors.inkTertiary)
                }
            }
        }
        if (me != null && !game.hasCheckedIn(me)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                BrutalButton(
                    onClick = {
                        working = true
                        scope.launch {
                            try {
                                env.roomManager.book.checkIn(game)
                                env.appState.showToast(L10n.tr("签到成功，打得开心。"), Toast.Style.Success)
                            } catch (error: RemoteError) {
                                env.appState.showError(error)
                            }
                            working = false
                        }
                    },
                    size = ButtonSize.Medium, fullWidth = false, enabled = game.canCheckIn(now) && !working,
                ) {
                    Symbol(Sym.mappinCircleFill, size = 15)
                    Spacer(Modifier.size(6.dp))
                    Text(tr("签到"))
                }
                if (!game.canCheckIn(now) && now < game.slot.startTime) {
                    // 还没到签到时间：标出几点开放
                    TagPill(
                        tr("%@ 开放", DateText.time(game.slot.startTime - Game.CHECK_IN_WINDOW)), icon = Sym.clock,
                        fill = colors.surfaceMuted, foreground = colors.inkSecondary,
                    )
                }
            }
        }
    }
}

/** 点头像看资料（自己的不弹） */
@Composable
internal fun Modifier.opensProfile(userId: String, me: String?): Modifier {
    val appState = LocalEnv.current.appState
    if (userId == me) return this
    return pressable(onClickLabel = tr("查看资料")) { appState.showPlayer(userId) }
}

// MARK: 分组

@Composable
private fun TeamsCard(game: Game, players: List<User>, me: String?) {
    val colors = AppTheme.colors
    val lookup = players.associateBy { it.id }
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Text(tr("分组"), style = AppTheme.Typography.headline, color = colors.ink)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            game.teams.forEachIndexed { index, team ->
                Column(
                    Modifier
                        .weight(1f)
                        .sticker(if (index == 0) colors.lavender else colors.lime, radius = 16.dp, shadow = AppTheme.Elevation.none)
                        .padding(AppTheme.Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                ) {
                    Text(if (index == 0) tr("A 队") else tr("B 队"), style = AppTheme.Typography.overline, color = colors.onAccent)
                    for (userId in team) {
                        val user = lookup[userId] ?: continue
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            AvatarView(user, Modifier.opensProfile(user.id, me), size = 26.dp)
                            Text(
                                if (user.id == me) tr("我") else user.nickname, style = AppTheme.Typography.footnoteBold, color = colors.onAccent,
                                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                            )
                            Text(user.displayTier.text, style = AppTheme.Typography.caption, color = colors.onAccent)
                        }
                    }
                }
                if (index == 0) Text("VS", style = AppTheme.Typography.headline, color = colors.ink)
            }
        }
    }
}

// MARK: 费用

@Composable
private fun CostCard(game: Game, players: List<User>, me: String?) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val rules = buildList {
        add(game.cost.breakdownText)
        add(tr("平台不收服务费"))
        if (game.court.status == VenueStatus.Unconfirmed || !game.court.pricing.isKnown) add(tr("价格以球馆实际收费为准"))
    }
    Column(Modifier.card(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("AA 费用"), style = AppTheme.Typography.headline, color = colors.ink)
            RulesButton(tr("费用怎么算"), rules)
            Spacer(Modifier.weight(1f))
            val perPerson = game.cost.perPerson
            if (perPerson != null) {
                Text(game.cost.money(perPerson), style = rounded(26, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.ink)
                Text(tr("/人"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            } else {
                Text(tr("待定"), style = AppTheme.Typography.headline, color = colors.ink)
            }
        }
        InsetDivider()
        for (player in players) {
            val paid = game.hasPaid(player.id)
            val canToggle = (player.id == me || game.hostId == me) && game.status != GameStatus.Cancelled
            val paidText = if (paid) tr("已付") else tr("待付")
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                AvatarView(player, Modifier.opensProfile(player.id, me), size = 30.dp)
                Text(if (player.id == me) tr("我") else player.nickname, style = AppTheme.Typography.bodyBold, color = colors.ink)
                if (player.id == game.hostId) TagPill(tr("发起人"), fill = colors.butter)
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier
                        .defaultMinSize(minHeight = 44.dp)
                        .pressable(enabled = canToggle, onClickLabel = if (canToggle) tr("点按切换付款状态") else null) {
                            haptics.selection()
                            env.roomManager.book.togglePaid(game, player.id, env.roomManager.scope, env.appState)
                        }
                        .clearAndSetSemantics { contentDescription = "${player.nickname} $paidText" },
                    contentAlignment = Alignment.Center,
                ) {
                    TagPill(
                        paidText, icon = if (paid) Sym.checkmark else null,
                        fill = if (paid) colors.mint else colors.surface, foreground = if (paid) colors.onAccent else colors.ink,
                    )
                }
            }
        }
    }
}

// MARK: 结束球局

@Composable
private fun CompleteSection(game: Game, onComplete: () -> Unit) {
    val now by rememberNow()
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        BrutalButton(onComplete, kind = ButtonKind.Inverse, size = ButtonSize.Medium, fullWidth = false, enabled = game.canComplete(now)) {
            Symbol(Sym.flagCheckered, size = 15)
            Spacer(Modifier.size(6.dp))
            Text(tr("结束球局"))
        }
        RulesButton(tr("结束球局"), listOf(tr("球局开始后才能结束"), tr("结束后可以给球友匿名评价"), tr("互评都提交后才会计入口碑")))
    }
}

@Composable
private fun ResultSection(game: Game, me: String?, onConfirm: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val pending = env.surveyManager.pending(game.id)
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        ResultCard(game, me, onConfirm)
        if (pending.isNotEmpty()) {
            SectionTitle(tr("待评价"), detail = DateText.remaining(pending[0].expiresAt))
            for (survey in pending) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .pressable(scale = 0.98f) { env.router.open(Route.Survey(survey.id)) }
                        .sticker(colors.surface, radius = AppTheme.Radius.md)
                        .padding(AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    AvatarView(survey.opponentId, survey.opponentAvatarText, survey.opponentAvatar.paletteIndex, Modifier.opensProfile(survey.opponentId, me), size = 40.dp)
                    Text(tr("评价 %@", survey.opponentNickname), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                    Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
                }
            }
        }
        BrutalButton(
            onClick = {
                val invitee = game.otherPlayerIds(me ?: "").firstOrNull()
                env.router.open(Route.CreateRoom(game.mode.serverValue, invitee))
            },
            size = ButtonSize.Medium,
        ) {
            Symbol(Sym.arrowTriangle2Circlepath, size = 15)
            Spacer(Modifier.size(6.dp))
            Text(tr("和他们再约一场"))
        }
    }
}

/** 赛果的规则（详情页赛果卡和填赛果页的“?”共用） */
@Composable
internal fun resultRules(): List<String> = listOf(
    tr("打了几局都行，记个大概"),
    tr("双方填的一致才算数"),
    tr("胜率按局算：赢的局数 ÷ 打的局数"),
    tr("确认后计入本月胜率，平局也计局数"),
    tr("双方说法不一致时，任何一方改成一致就照常计入"),
    tr("比赛结束后 7 天内没有确认，本场不计入"),
    tr("友谊局不计胜负，有一方记不清的不计入胜率"),
)

@Composable
private fun ResultCard(game: Game, me: String?, onConfirm: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val status = game.resultStatus()
    val outcome = game.resultOutcome(me)
    val score = game.reportedScore(me)
    val hasReported = me?.let { game.report(it) } != null
    val isPlayer = me?.let { game.team(it) } != null
    // 早期没有申报记录的球局不参与确认
    val hasReports = game.resultReports.isNotEmpty()
    val canReport = hasReports && isPlayer && game.acceptsResultReports()
    val claims = otherClaims(game, me) { env.roomManager.book.user(it)?.nickname }
    Column(Modifier.card(colors.surface), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(resultHeadline(status, outcome), style = AppTheme.Typography.headline, color = colors.ink)
            if (hasReports) RulesButton(tr("赛果怎么算"), resultRules())
            Spacer(Modifier.weight(1f))
            // 确认过的局数（我方 : 对方），没有就显示比分
            val rounds = if (me != null && (status is ResultStatus.Verified || status == ResultStatus.Draw)) game.reportedGames(me) else null
            if (rounds != null) {
                Text("${rounds.mine} : ${rounds.theirs}", style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink)
            } else if (score.isNotEmpty()) {
                Text(score, style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = colors.ink)
            }
        }
        if (hasReports) {
            Flow(spacing = AppTheme.Spacing.xs) {
                val muted = status == ResultStatus.Unsure || status == ResultStatus.Expired
                TagPill(resultStatusText(status, hasReported), icon = resultIcon(status), fill = resultTint(status), foreground = if (muted) colors.ink else null)
                if (status == ResultStatus.Awaiting || (status == ResultStatus.Disputed && game.acceptsResultReports())) {
                    TagPill(confirmationTimeLeft(game), icon = Sym.hourglass, fill = colors.surface, foreground = colors.ink)
                }
            }
        }
        if ((canReport || status == ResultStatus.Disputed) && claims.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                for (claim in claims) Text(claim, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            }
        }
        if (canReport) {
            BrutalButton(onConfirm, size = ButtonSize.Medium) {
                Symbol(Sym.checkmarkSealFill, size = 15)
                Spacer(Modifier.size(6.dp))
                Text(if (hasReported) tr("修改赛果") else tr("确认赛果"))
            }
        }
    }
}

@Composable
private fun resultHeadline(status: ResultStatus, outcome: Boolean?): String = when {
    status == ResultStatus.Friendly -> tr("友谊局")
    status == ResultStatus.Draw -> tr("平局")
    outcome == true -> tr("赢了")
    outcome == false -> tr("输了")
    else -> tr("球局已完成")
}

/** 赛果状态词；怎么算写在“?”里 */
@Composable
private fun resultStatusText(status: ResultStatus, hasReported: Boolean): String = when (status) {
    ResultStatus.Awaiting -> if (hasReported) tr("等对方确认") else tr("等你确认")
    is ResultStatus.Verified, ResultStatus.Draw -> tr("已确认")
    ResultStatus.Disputed -> tr("有分歧")
    ResultStatus.Friendly -> tr("不计胜负")
    ResultStatus.Unsure -> tr("记不清 · 不计入")
    ResultStatus.Expired -> tr("已过期 · 不计入")
}

private fun resultIcon(status: ResultStatus): SymbolId = when (status) {
    ResultStatus.Awaiting -> Sym.hourglass
    is ResultStatus.Verified -> Sym.checkmarkSealFill
    ResultStatus.Disputed -> Sym.exclamationmarkTriangleFill
    ResultStatus.Friendly -> Sym.handWaveFill
    ResultStatus.Draw -> Sym.equalCircleFill
    ResultStatus.Unsure -> Sym.questionmarkCircleFill
    ResultStatus.Expired -> Sym.clockBadgeXmark
}

@Composable
private fun resultTint(status: ResultStatus): androidx.compose.ui.graphics.Color {
    val colors = AppTheme.colors
    return when (status) {
        ResultStatus.Awaiting -> colors.butter
        is ResultStatus.Verified, ResultStatus.Draw -> colors.mint
        ResultStatus.Disputed -> colors.pink
        ResultStatus.Friendly -> colors.sky
        ResultStatus.Unsure, ResultStatus.Expired -> colors.surfaceMuted
    }
}

/** 例如“还剩 3 天”；不足一天时显示小时 / 分钟 */
@Composable
private fun confirmationTimeLeft(game: Game): String {
    val deadline = game.resultDeadline
    val millis = deadline - System.currentTimeMillis()
    if (millis < 86_400_000L) return DateText.remaining(deadline)
    return tr("还剩 %lld 天", ceil(millis / 86_400_000.0).toLong())
}

/** 其他球员各自报的结果（以我方视角描述） */
@Composable
private fun otherClaims(game: Game, me: String?, name: (String) -> String?): List<String> {
    if (me == null) return emptyList()
    val mine = game.team(me) ?: return emptyList()
    return game.resultReports.filter { it.reporterId != me && it.reporterId.isNotEmpty() }.map { report ->
        val who = name(report.reporterId) ?: tr("球友")
        val games = game.games(report, me)
        val winner = report.winningTeam
        when {
            report.unsure -> tr("%@：记不清了", who)
            games != null -> tr("%@ 报：我方 %lld : %lld 对方", who, games.mine, games.theirs)
            winner == null -> tr("%@ 报：友谊局，不计胜负", who)
            winner == mine -> tr("%@ 报：我方赢", who)
            else -> tr("%@ 报：我方输", who)
        }
    }
}

@Composable
private fun cancelledText(game: Game, me: String?, book: GameBook): String {
    val who = if (game.cancelledBy == me) tr("你") else game.cancelledBy?.let { book.user(it)?.nickname } ?: tr("球友")
    return tr("%@取消了", who)
}

/** 预选：我上次报的，否则别人报的（换成我方视角）。只报了输赢、没报局数的不预填（不凭空造出 1:0） */
internal fun suggestedSubmission(game: Game, me: String?): Submission? {
    if (me == null || game.team(me) == null) return null
    val report = game.report(me) ?: game.resultReports.firstOrNull { !it.unsure } ?: return null
    if (report.unsure) return Submission(Choice.Unsure, 0, 0, "")
    game.games(report, me)?.let { return Submission(Choice.Counted, it.mine, it.theirs, report.score) }
    if (report.winningTeam == null) return Submission(Choice.Practice, 0, 0, "")
    return null
}

// MARK: - 结束球局 / 确认赛果

internal enum class Choice {
    /** 填了局数 */
    Counted,
    /** 没计分，就是练球（不计胜负） */
    Practice,
    Unsure,
}

internal data class Submission(val choice: Choice, val mine: Int, val theirs: Int, val score: String) {
    val games: GameCount? get() = if (choice == Choice.Counted) GameCount(mine, theirs) else null
}

/** 填赛果的规则（纯逻辑，方便测试） */
internal object ResultForm {
    /** 填了每局比分、又手动改了局数，两边对不上 */
    fun scoreDisagrees(score: String, mine: Int, theirs: Int): Boolean {
        val games = com.badie.app.models.GameResult.games(score) ?: return false
        return games.mine != mine || games.theirs != theirs
    }

    fun canSubmit(choice: Choice?, mine: Int, theirs: Int, score: String): Boolean = when (choice) {
        Choice.Counted -> mine + theirs >= 1 && com.badie.app.models.GameResult.isValidScore(score) && !scoreDisagrees(score, mine, theirs)
        Choice.Practice, Choice.Unsure -> true
        null -> false
    }
}

/** 一场常常打好几局：先问两边各赢了几局（不问“谁赢了”），也可以选“没计分，就是练球”或“记不清了” */
@Composable
internal fun CompleteGameSheet(game: Game, isConfirming: Boolean, initial: Submission?, onComplete: (Submission) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    var choice by remember { mutableStateOf(initial?.choice) }
    var mine by remember { mutableIntStateOf(initial?.mine ?: 0) }
    var theirs by remember { mutableIntStateOf(initial?.theirs ?: 0) }
    var score by remember { mutableStateOf(initial?.score ?: "") }
    var showsScore by remember { mutableStateOf(initial?.score?.isNotEmpty() == true) }
    val scoreIsValid = com.badie.app.models.GameResult.isValidScore(score)
    val disagrees = ResultForm.scoreDisagrees(score, mine, theirs)
    val isSingles = game.mode == com.badie.app.models.GameMode.Singles
    Column(Modifier.fillMaxWidth()) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
                Text(if (isConfirming) tr("确认赛果") else tr("这场打得怎么样"), style = AppTheme.Typography.title, color = colors.ink)
                RulesButton(tr("赛果怎么算"), resultRules())
            }
            Row(Modifier.alpha(if (choice == Choice.Counted || choice == null) 1f else 0.4f), verticalAlignment = Alignment.Top) {
                Counter(if (isSingles) tr("我") else tr("我们"), mine, Modifier.weight(1f)) {
                    mine = it
                    choice = Choice.Counted
                    haptics.selection()
                }
                Text(":", style = rounded(30, FontWeight.Black), color = colors.ink, modifier = Modifier.padding(top = 34.dp, start = 4.dp, end = 4.dp))
                Counter(tr("对方"), theirs, Modifier.weight(1f)) {
                    theirs = it
                    choice = Choice.Counted
                    haptics.selection()
                }
            }
            if (choice == Choice.Counted && mine + theirs > 0) {
                val total = mine + theirs
                val summary = when {
                    mine == theirs -> tr("一共 %lld 局 · 平局", total)
                    mine > theirs -> tr("一共 %lld 局 · 我方赢得多", total)
                    else -> tr("一共 %lld 局 · 对方赢得多", total)
                }
                Text(
                    summary, style = AppTheme.Typography.subheadlineBold, color = colors.onAccent,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().sticker(colors.lime, radius = AppTheme.Radius.sm, shadow = AppTheme.Elevation.none).padding(vertical = AppTheme.Spacing.sm),
                )
            }
            if (showsScore) {
                com.badie.app.design.BrutalTextField(
                    tr("每局比分（可选）"), tr("如 21:18 19:21 21:15"), score,
                    { value ->
                        score = value.take(40)
                        // 填了每局比分就按比分数出两边各赢几局
                        val games = com.badie.app.models.GameResult.games(score)
                        if (com.badie.app.models.GameResult.isValidScore(score) && games != null) {
                            mine = games.mine
                            theirs = games.theirs
                            choice = Choice.Counted
                        }
                    },
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Ascii),
                    errorText = when {
                        !scoreIsValid -> tr("比分只能填数字，如 21:18 19:21。")
                        choice == Choice.Counted && disagrees -> tr("比分和上面的局数对不上。")
                        else -> null
                    },
                    characterLimit = 40,
                )
            } else {
                Row(
                    Modifier.defaultMinSize(minHeight = 44.dp).pressable { showsScore = true },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Symbol(Sym.plus, size = 13, tint = colors.inkSecondary)
                    Text(tr("填每局比分（可选）"), style = AppTheme.Typography.subheadlineBold, color = colors.inkSecondary)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(tr("或者"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                OptionRow(tr("没计分，就是练球"), Sym.handWaveFill, choice == Choice.Practice) {
                    haptics.selection()
                    choice = if (choice == Choice.Practice) null else Choice.Practice
                }
                OptionRow(tr("记不清了"), Sym.questionmarkCircle, choice == Choice.Unsure) {
                    haptics.selection()
                    choice = if (choice == Choice.Unsure) null else Choice.Unsure
                }
            }
        }
        BrutalButton(
            if (isConfirming) tr("提交赛果") else tr("完成"),
            onClick = {
                val picked = choice ?: return@BrutalButton
                onComplete(Submission(picked, mine, theirs, if (picked == Choice.Counted) score else ""))
            },
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.lg),
            enabled = ResultForm.canSubmit(choice, mine, theirs, score),
        )
    }
}

/** 一边的局数：− 数字 +（0–15） */
@Composable
private fun Counter(title: String, value: Int, modifier: Modifier = Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val label = tr("%@赢的局数", title)
    Column(
        modifier.semantics(mergeDescendants = true) { contentDescription = "$label $value" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
    ) {
        Text(title, style = AppTheme.Typography.headline, color = colors.ink)
        Row(
            Modifier.sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.xs, vertical = AppTheme.Spacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StepButton(Sym.minus, tr("少一局"), enabled = value > 0) { onChange(maxOf(0, value - 1)) }
            Text(
                "$value", style = rounded(34, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.ink,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.defaultMinSize(minWidth = 36.dp),
            )
            StepButton(Sym.plus, tr("多一局")) { onChange(minOf(15, value + 1)) }
        }
        Text(tr("赢的局数"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
    }
}

@Composable
internal fun StepButton(icon: SymbolId, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.size(36.dp, 44.dp).pressable(scale = 0.85f, enabled = enabled, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Symbol(icon, size = 16, tint = if (enabled) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
    }
}

@Composable
private fun OptionRow(title: String, icon: SymbolId, selected: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val ink = if (selected) colors.onAccent else colors.ink
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(scale = 0.98f, onClick = onClick)
            .semantics { this.selected = selected }
            .defaultMinSize(minHeight = 52.dp)
            .sticker(if (selected) colors.lime else colors.surface, radius = AppTheme.Radius.md, shadow = if (selected) AppTheme.Elevation.low else AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { Symbol(icon, size = 16, tint = ink) }
        Text(title, style = AppTheme.Typography.bodyBold, color = ink, modifier = Modifier.weight(1f))
        Symbol(if (selected) Sym.checkmarkCircleFill else Sym.circle, size = 20, tint = ink)
    }
}

// MARK: - 定时间

/** 约成了但还没定具体几点：在窗口里挑一个开始时间（打满窗口里的时长）。对应 iPhone 的 SetGameTimeSheet（在 NearbyViews.swift 里） */
@Composable
internal fun SetGameTimeSheet(game: Game, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val window = game.window
    val starts = remember(window) { window?.possibleStarts() ?: emptyList() }
    var selection by remember { mutableStateOf(starts.firstOrNull()) }
    var working by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    val duration = window?.duration ?: 7_200_000L
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(tr("定时间"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl))
        if (starts.isEmpty()) {
            Text(tr("这个时间来不及了"), style = AppTheme.Typography.bodyBold, color = colors.danger)
        } else {
            // iPhone 是滚轮；这里是一列可选的时间
            Column(
                Modifier.fillMaxWidth().height(240.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
            ) {
                for (start in starts) {
                    val chosen = start == selection
                    Text(
                        timeLabel(start, duration), style = AppTheme.Typography.bodyBold.copy(fontFeatureSettings = "tnum"),
                        color = if (chosen) colors.onAccent else colors.ink,
                        modifier = Modifier
                            .fillMaxWidth()
                            .pressable(scale = 0.98f) {
                                haptics.selection()
                                selection = start
                            }
                            .semantics { selected = chosen }
                            .sticker(if (chosen) colors.lime else colors.surface, radius = AppTheme.Radius.sm, shadow = AppTheme.Elevation.none)
                            .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md),
                    )
                }
            }
        }
        errorText?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = colors.danger) }
        BrutalButton(tr("定下来"), onClick = {
            val start = selection ?: return@BrutalButton
            working = true
            errorText = null
            scope.launch {
                try {
                    env.roomManager.book.setTime(game, start)
                    haptics.success()
                    env.appState.showToast(L10n.tr("定好了：%@", timeLabelPlain(start, duration)), Toast.Style.Success)
                    onDismiss()
                } catch (error: RemoteError) {
                    errorText = inviteError(error)
                }
                working = false
            }
        }, enabled = !working && starts.isNotEmpty())
    }
}

/** “周六 14:00–16:00” */
@Composable
private fun timeLabel(start: Long, duration: Long): String = timeLabelPlain(start, duration)

private fun timeLabelPlain(start: Long, duration: Long): String =
    "${com.badie.app.models.WindowText.dayName(start)} ${DateText.time(start)}–${DateText.time(start + duration)}"

/** 定时间出错时的话（iPhone 的 InviteText.error 里和定时间有关的几条） */
private fun inviteError(error: RemoteError): String {
    val code = (error as? RemoteError.Server)?.code
    return when (code) {
        "invalid_window", "invalid_slot" -> L10n.tr("这个时间来不及了")
        "overlapping" -> L10n.tr("这个时间你已经有球局或待确认的约球了。")
        "too_late" -> L10n.tr("来不及了，换个时间吧")
        "time_already_set" -> L10n.tr("时间已经定好了")
        else -> error.message
    }
}
