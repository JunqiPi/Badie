package com.badie.app.features.matching

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.ArrowButtonLabel
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ChoiceChip
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InfoRow
import com.badie.app.design.InsetDivider
import com.badie.app.design.LevelBadge
import com.badie.app.design.LoadingDots
import com.badie.app.design.NewPlayerBadge
import com.badie.app.design.PraiseTagsView
import com.badie.app.design.ReliableBadge
import com.badie.app.design.RulesButton
import com.badie.app.design.StarburstBadge
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.markedText
import com.badie.app.design.pressable
import com.badie.app.design.reduceMotion
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.GameMode
import com.badie.app.models.MatchOffer
import com.badie.app.models.MatchTicket
import com.badie.app.models.MatchTiming
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import com.badie.app.models.title
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTab
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 对应 iPhone 的 Features/Matching/MatchFlowView.swift 和 TicketViews.swift：
// 全屏匹配流程：提交请求 → 挂起等待 / 找到搭子（多方确认）→ 约成；或暂停、结束

@Composable
internal fun MatchFlowHost() {
    val manager = LocalEnv.current.matchManager
    AnimatedVisibility(manager.isFlowPresented, enter = fadeIn() + slideInVertically { it / 8 }, exit = fadeOut()) {
        BackHandler { manager.closeFlow() }
        Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas).windowInsetsPadding(WindowInsets.safeDrawing)) {
            MatchFlowView()
        }
    }
}

/** 流程里现在该看哪一页 */
@Composable
fun MatchFlowView() {
    val manager = LocalEnv.current.matchManager
    val phase = manager.phase
    val ticket = manager.flowTicket
    val key = when {
        phase is MatchManager.Phase.Submitting -> "searching"
        phase is MatchManager.Phase.Failed -> "failed"
        ticket == null -> "searching"
        else -> "${ticket.id}-${ticket.status::class.simpleName}"
    }
    Crossfade(key, label = "flow") { current ->
        when {
            current == "failed" -> Failure((phase as? MatchManager.Phase.Failed)?.message.orEmpty())
            current == "searching" || ticket == null -> SearchingView()
            else -> when (ticket.status) {
                MatchTicket.Status.Searching -> TicketWaitingView(ticket)
                is MatchTicket.Status.Offered, is MatchTicket.Status.Matched ->
                    manager.offer(ticket)?.let { OfferView(ticket, it) } ?: TicketWaitingView(ticket)
                else -> TicketEndedView(ticket)
            }
        }
    }
}

@Composable
private fun Failure(message: String) {
    val manager = LocalEnv.current.matchManager
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        EmptyStateView(Sym.exclamationmarkTriangleFill, tr("没能发起请求"), message = message, tint = AppTheme.colors.pink)
        Spacer(Modifier.weight(1f))
        BrutalButton(tr("返回"), { manager.closeFlow() }, Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl), kind = ButtonKind.Secondary)
    }
}

// MARK: - 搜索中

@Composable
fun SearchingView() {
    val env = LocalEnv.current
    val manager = env.matchManager
    val draft = manager.draft
    val colors = AppTheme.colors
    val still = reduceMotion()
    val levelText = if (draft.skillTolerance >= MatchRequest.ANY_SKILL) tr("所有水平") else tr("水平 ±%lld 级", draft.skillTolerance)
    val statuses = listOf(
        tr("正在查看 %lld 个球馆附近的球友…", draft.courtIds.size),
        tr("筛选 %@ 的球友…", levelText),
        tr("比对你们都有空的时间…"),
        tr("只匹配也能去这些球馆的球友…"),
    )
    var statusIndex by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1400)
            statusIndex += 1
        }
    }
    val pulse = rememberInfiniteTransition(label = "pulse")
    val ink = Color(0xFF17140F)
    Column(
        Modifier.fillMaxSize().background(colors.lime).padding(vertical = AppTheme.Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen)) {
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭（请求会继续）")) { manager.closeFlow() }
        }
        Spacer(Modifier.weight(1f))
        Box(Modifier.height(300.dp).fillMaxWidth().clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            for (ring in 0 until 3) {
                val progress by pulse.animateFloat(
                    0f, 1f,
                    infiniteRepeatable(tween(2200, delayMillis = ring * 700, easing = LinearEasing), RepeatMode.Restart), label = "ring$ring",
                )
                val value = if (still) 0f else progress
                Box(
                    Modifier.size(140.dp).scale(0.9f + 1.2f * value).graphicsLayer { alpha = 0.9f * (1 - value) }.drawBehind {
                        drawCircle(ink.copy(alpha = 0.5f), radius = size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                    },
                )
            }
            env.appState.currentUser?.let { me ->
                Box(Modifier.drawBehind { drawCircle(ink, center = center.copy(x = center.x + 3.dp.toPx(), y = center.y + 4.dp.toPx())) }) {
                    AvatarView(me, size = 96.dp)
                }
            }
        }
        Column(
            Modifier.padding(horizontal = AppTheme.Spacing.screen).semantics(mergeDescendants = true) {},
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            Text(tr("正在找搭子"), style = AppTheme.Typography.title, color = colors.onAccent)
            Crossfade(statusIndex % statuses.size, label = "status") { index ->
                Text(statuses[index], style = AppTheme.Typography.subheadlineBold, color = colors.onAccent.copy(alpha = 0.75f), textAlign = TextAlign.Center)
            }
            draft.slot()?.let { slot ->
                Row(Modifier.padding(top = AppTheme.Spacing.xs), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    TagPill(draft.mode.title, icon = draft.mode.icon, fill = Color.White)
                    TagPill(slot.formattedFull(), icon = Sym.clockFill, fill = Color.White)
                }
            }
        }
        Spacer(Modifier.weight(1f))
    }
}

// MARK: - 找到搭子：多方确认

/** 一个匹配提议。所有人确认才成局；有人没确认时显示“补位中”，不显示是谁 */
@Composable
fun OfferView(ticket: MatchTicket, offer: MatchOffer) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val still = reduceMotion()
    val me = env.appState.currentUser
    val mySeat = offer.seat(ticket.userId)
    val isMatched = offer.gameId != null
    val awaitsMe = offer.isOpen && mySeat?.response == MatchOffer.Response.Pending
    // 局中其他人（不含已离开的座位）
    val others = offer.seats.filter { it.userId != ticket.userId && !it.isVacant }.mapNotNull { manager.user(it.userId) }
    val animates = !still && (awaitsMe || isMatched)
    var collided by remember(offer.id) { mutableStateOf(!animates) }
    var showDetails by remember(offer.id) { mutableStateOf(!animates) }
    var confirmsCancel by remember { mutableStateOf(false) }
    LaunchedEffect(offer.id) {
        if (!animates) return@LaunchedEffect
        collided = true
        delay(AppTheme.Motion.collisionMillis.toLong())
        haptics.impact()
        delay(300)
        showDetails = true
    }
    val progress by animateFloatAsState(if (collided) 1f else 0f, tween(AppTheme.Motion.collisionMillis), label = "collide")

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(Sym.xmark, tr("关闭")) { manager.closeFlow() }
            Text(
                tr("%@ · 匹配度 %lld%%", offer.mode.title, offer.compatibility), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary,
                textAlign = TextAlign.Center, modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.size(44.dp))
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            val headline = when {
                isMatched -> tr("约好*搭子*了。")
                awaitsMe -> tr("找到*搭子*了。")
                else -> tr("等*大家*确认")
            }
            Text(
                markedText(headline), style = AppTheme.Typography.display, color = colors.ink, textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = AppTheme.Spacing.md).semantics { heading() },
            )
            Box(Modifier.fillMaxWidth().height(if (offer.mode == GameMode.Doubles) 250.dp else 210.dp), contentAlignment = Alignment.Center) {
                if (offer.mode == GameMode.Singles && me != null && others.isNotEmpty()) {
                    val opponent = others.first()
                    PlayerCard(me, tr("我"), colors.surface, Modifier.offset { androidx.compose.ui.unit.IntOffset(((-260 + 178 * progress) * density).toInt(), 0) }.rotate(-20 + 13 * progress))
                    PlayerCard(
                        opponent, opponent.nickname, colors.lime,
                        Modifier.offset { androidx.compose.ui.unit.IntOffset(((260 - 178 * progress) * density).toInt(), 0) }.rotate(20 - 13 * progress).pressable { env.appState.showPlayer(opponent.id) },
                    )
                    StarburstBadge("VS", Modifier.offset(y = 66.dp).scale(0.1f + 0.9f * progress).graphicsLayer { alpha = progress }, size = 76.dp)
                } else {
                    DoublesStage(ticket, offer, progress)
                }
            }
            AnimatedVisibility(showDetails, enter = fadeIn() + slideInVertically { it / 3 }) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
                    if (!isMatched) ConfirmationCard(ticket, offer, awaitsMe)
                    PlayersCard(ticket, others)
                    DetailsCard(offer)
                }
            }
        }
        AnimatedVisibility(showDetails, enter = fadeIn() + slideInVertically { it }) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                val gameId = offer.gameId
                when {
                    gameId != null -> {
                        BrutalButton(onClick = {
                            manager.closeFlow()
                            env.router.show(Route.Game(gameId), MainTab.Games)
                        }) {
                            Symbol(Sym.ticketFill, size = 15)
                            Spacer(Modifier.width(6.dp))
                            Text(tr("查看球局"))
                        }
                        others.firstOrNull()?.let { opponent ->
                            TextAction(tr("发消息"), {
                                manager.closeFlow()
                                env.router.show(Route.Chat(opponent.id), MainTab.Messages)
                            })
                        }
                    }
                    awaitsMe -> Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                        val scope = rememberCoroutineScope()
                        BrutalButton(
                            tr("这次不行"), {
                                haptics.tap()
                                scope.launch { manager.respond(false) }
                            },
                            Modifier.width(128.dp), kind = ButtonKind.Secondary, fullWidth = false, enabled = !manager.isResponding,
                        )
                        BrutalButton(onClick = { scope.launch { manager.respond(true) } }, Modifier.weight(1f), enabled = !manager.isResponding) {
                            if (manager.isResponding) {
                                LoadingDots()
                                Spacer(Modifier.width(AppTheme.Spacing.sm))
                            }
                            Text(tr("确认约球"))
                        }
                    }
                    else -> {
                        BrutalButton(tr("好"), { manager.closeFlow() })
                        TextAction(tr("取消"), { confirmsCancel = true })
                    }
                }
            }
        }
    }
    if (confirmsCancel) {
        CancelDialog(tr("还没约成，取消不影响任何记录；其他人会继续帮 TA 们找人。"), tr("再等等"), onDismiss = { confirmsCancel = false }) {
            manager.cancelTicket(ticket.id)
        }
    }
}

@Composable
private fun PlayerCard(user: User, title: String, fill: Color, modifier: Modifier = Modifier) {
    Column(
        modifier.size(140.dp, 170.dp).sticker(fill, radius = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm, Alignment.CenterVertically),
    ) {
        AvatarView(user, size = 60.dp)
        Text(title, style = AppTheme.Typography.headline, color = AppTheme.colors.onAccent, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = AppTheme.Spacing.sm))
        LevelBadge(user.displayTier)
    }
}

@Composable
private fun DoublesStage(ticket: MatchTicket, offer: MatchOffer, progress: Float) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val colors = AppTheme.colors
    val vacant = offer.seats.filter { it.isVacant }.map { it.userId }.toSet()
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
        offer.teams.forEachIndexed { index, team ->
            val sign = if (index == 0) -1 else 1
            Column(
                Modifier.offset(x = (sign * 240 * (1 - progress)).dp).rotate(sign * 4 * progress),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                for (userId in team) {
                    if (userId in vacant) {
                        VacantCard()
                    } else {
                        manager.user(userId)?.let { user ->
                            MiniPlayerCard(
                                user, isMe = user.id == ticket.userId, fill = if (index == 0) colors.lavender else colors.lime,
                                modifier = Modifier.pressable { if (user.id != ticket.userId) env.appState.showPlayer(user.id) },
                            )
                        }
                    }
                }
            }
            if (index == 0) {
                StarburstBadge("VS", Modifier.scale(0.1f + 0.9f * progress).graphicsLayer { alpha = progress }, size = 64.dp)
            }
        }
    }
}

@Composable
private fun MiniPlayerCard(user: User, isMe: Boolean, fill: Color, modifier: Modifier = Modifier) {
    Row(
        modifier.width(132.dp).sticker(fill, radius = 16.dp, shadow = AppTheme.Elevation.low).padding(AppTheme.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        AvatarView(user, size = 36.dp)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(if (isMe) tr("我") else user.nickname, style = AppTheme.Typography.subheadlineBold, color = AppTheme.colors.onAccent, maxLines = 1, overflow = TextOverflow.Ellipsis)
            LevelBadge(user.displayTier, showsName = false, compact = true)
        }
    }
}

/** 有人这次来不了：只显示“补位中”，不显示是谁 */
@Composable
private fun VacantCard() {
    val colors = AppTheme.colors
    val label = tr("有一个位置正在找人补上")
    Row(
        Modifier
            .width(132.dp)
            .drawBehind {
                drawRoundRect(
                    colors.inkTertiary, cornerRadius = CornerRadius(16.dp.toPx()),
                    style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))),
                )
            }
            .padding(AppTheme.Spacing.sm)
            .clearAndSetSemantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Box(Modifier.size(36.dp).background(colors.surfaceMuted, RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
            Symbol(Sym.personFillQuestionmark, size = 16, tint = colors.inkSecondary)
        }
        Text(tr("补位中…"), style = AppTheme.Typography.subheadlineBold, color = colors.inkSecondary)
    }
}

/** 确认进度：谁确认了、还在等谁；拒绝/超时的座位只显示“补位中”。黄底（轮到我确认）上用固定的深色字 */
@Composable
private fun ConfirmationCard(ticket: MatchTicket, offer: MatchOffer, awaitsMe: Boolean) {
    val manager = LocalEnv.current.matchManager
    val colors = AppTheme.colors
    val ink = if (awaitsMe) colors.onAccent else colors.ink
    val secondary = if (awaitsMe) colors.onAccent.copy(alpha = 0.75f) else colors.inkSecondary
    // 每 30 秒重算剩余时间
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = System.currentTimeMillis()
        }
    }
    val mySeat = offer.seat(ticket.userId)
    val deadline = if (awaitsMe && mySeat != null) {
        tr("%@前确认", DateText.deadline(mySeat.respondBy, now)) + " · " + MatchTiming.remainingText(mySeat.respondBy, now)
    } else {
        tr("%@前确认", DateText.deadline(offer.lockAt, now))
    }
    Column(
        Modifier.fillMaxWidth().sticker(if (awaitsMe) colors.butter else colors.surface, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("确认进度"), style = AppTheme.Typography.headline, color = ink)
            RulesButton(
                tr("约成规则"),
                listOf(
                    tr("所有人都确认才成局，谁没确认不会告诉其他人。"),
                    tr("最晚%@前全部确认，否则自动取消，不计入任何记录。", DateText.deadline(offer.lockAt)),
                    tr("选“这次不行”不扣分，会继续帮你找其他人。"),
                    tr("确认后，开赛前 2 小时内取消会计入履约记录。"),
                ),
            )
            Spacer(Modifier.weight(1f))
            Text(tr("%lld/%lld 已确认", offer.acceptedCount, offer.seats.size), style = AppTheme.Typography.footnoteBold, color = secondary)
        }
        for (seat in offer.seats) {
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                if (seat.isVacant) {
                    Box(Modifier.size(32.dp).background(colors.surfaceMuted, RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                        Symbol(Sym.personFillQuestionmark, size = 14, tint = colors.ink)
                    }
                    Text(tr("空位"), style = AppTheme.Typography.subheadlineBold, color = secondary, modifier = Modifier.weight(1f))
                    TagPill(tr("补位中"), icon = Sym.arrowTriangle2Circlepath, fill = colors.surfaceMuted, foreground = colors.ink)
                } else {
                    val user = manager.user(seat.userId) ?: return@Row
                    AvatarView(user, size = 32.dp)
                    Text(
                        if (user.id == ticket.userId) tr("我") else user.nickname, style = AppTheme.Typography.subheadlineBold, color = ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                    // 正式后端不告诉别人谁确认了：只显示自己的
                    if (user.id == ticket.userId) {
                        if (seat.response == MatchOffer.Response.Accepted) {
                            TagPill(tr("已确认"), icon = Sym.checkmark, fill = colors.mint)
                        } else {
                            TagPill(tr("等待确认"), icon = Sym.hourglass, fill = colors.surface, foreground = colors.ink)
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Symbol(Sym.clockBadgeExclamationmarkFill, size = 13, tint = if (awaitsMe) ink else secondary)
            Text(deadline, style = AppTheme.Typography.footnoteBold, color = if (awaitsMe) ink else secondary)
        }
    }
}

/** 其他球友：水平差、靠谱徽章与球友印象（不显示任何评分数字） */
@Composable
private fun PlayersCard(ticket: MatchTicket, others: List<User>) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val me = env.appState.currentUser
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        for (user in others) {
            Column(Modifier.fillMaxWidth().pressable(scale = 1f) { env.appState.showPlayer(user.id) }, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(user.nickname, style = AppTheme.Typography.headline, color = colors.ink)
                    val level = SkillTier.differenceText((me?.displayTier ?: user.displayTier).steps(user.displayTier))
                    val subtitle = user.location?.let { "$level · ${DistanceFormatter.approximate(it.distanceKm(ticket.origin))}" } ?: level
                    Text(subtitle, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1, modifier = Modifier.weight(1f))
                    if (user.isNewPlayer) NewPlayerBadge() else if (user.isReliable) ReliableBadge()
                }
                PraiseTagsView(user.reputation.publicTags.take(2), emptyText = null)
            }
        }
    }
}

@Composable
private fun DetailsCard(offer: MatchOffer) {
    val colors = AppTheme.colors
    Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg)) {
        InfoRow(
            Sym.clockFill, offer.slot.formattedFull(), tint = colors.peach,
            subtitle = if (offer.commonOverlap.duration > offer.slot.duration) tr("共同有空 %@", offer.commonOverlap.formattedTimeRange()) else null,
        )
        InsetDivider()
        InfoRow(Sym.mappinAndEllipse, offer.court.name, tint = colors.sky, subtitle = offer.court.address)
        InsetDivider()
        InfoRow(
            Sym.banknote, if (offer.cost.perPerson == null) tr("费用待定") else tr("AA 约 %@", offer.cost.perPersonText),
            tint = colors.butter, subtitle = offer.cost.breakdownText,
        )
        if (offer.mode == GameMode.Doubles) {
            InsetDivider()
            InfoRow(Sym.person2Fill, tr("已按水平分队"), tint = colors.lavender) {
                RulesButton(tr("已按水平分队"), listOf(tr("两队平均等级差不超过 1 级。")))
            }
        }
    }
}

@Composable
private fun CancelDialog(message: String, keepTitle: String, onDismiss: () -> Unit, onCancel: () -> Unit) {
    val colors = AppTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text(tr("取消这个约球请求？"), style = AppTheme.Typography.headline, color = colors.ink) },
        text = { Text(message, style = AppTheme.Typography.subheadline, color = colors.inkSecondary) },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                onCancel()
            }) { Text(tr("取消请求"), style = AppTheme.Typography.subheadlineBold, color = colors.danger) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(keepTitle, style = AppTheme.Typography.subheadlineBold, color = colors.ink) } },
    )
}

// MARK: - 请求状态（卡片上只放状态词）

/** 请求现在的状态：一个词、图标、颜色，要不要我操作 */
class TicketStatus(val title: String, val icon: SymbolId, val tint: Color, /** 需要我操作（等我确认 / 已暂停） */ val needsAction: Boolean)

@Composable
fun ticketStatus(ticket: MatchTicket, offer: MatchOffer?, now: Long = System.currentTimeMillis()): TicketStatus {
    val colors = AppTheme.colors
    return when (ticket.status) {
        MatchTicket.Status.Searching -> TicketStatus(
            if (ticket.isLastMinute) tr("临时局 · 正在找") else tr("在找搭子") + " · " + tr("%@前确认", DateText.deadline(ticket.deadline, now)),
            Sym.hourglass, colors.sky, false,
        )
        is MatchTicket.Status.Offered -> {
            val seat = offer?.seat(ticket.userId)
            when {
                seat != null && seat.response == MatchOffer.Response.Pending ->
                    TicketStatus(tr("待你确认") + " · " + MatchTiming.remainingText(seat.respondBy, now), Sym.boltFill, colors.lime, true)
                offer != null && offer.vacantCount > 0 -> TicketStatus(tr("补位中"), Sym.arrowTriangle2Circlepath, colors.butter, false)
                else -> TicketStatus(tr("已确认 %lld/%lld", offer?.acceptedCount ?: 1, offer?.seats?.size ?: 2), Sym.checkmarkCircleFill, colors.mint, false)
            }
        }
        is MatchTicket.Status.Matched -> TicketStatus(tr("约成了"), Sym.sportscourtFill, colors.lime, false)
        MatchTicket.Status.Paused -> TicketStatus(tr("已暂停"), Sym.pauseCircleFill, colors.peach, true)
        MatchTicket.Status.Expired -> TicketStatus(tr("没约到"), Sym.clockBadgeXmark, colors.surfaceMuted, false)
        MatchTicket.Status.Cancelled -> TicketStatus(tr("已取消"), Sym.xmarkCircleFill, colors.surfaceMuted, false)
    }
}

/** 球局页上的请求卡片（点了打开流程） */
@Composable
fun TicketStatusCard(ticket: MatchTicket, offer: MatchOffer?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = AppTheme.colors
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = System.currentTimeMillis()
        }
    }
    val status = ticketStatus(ticket, offer, now)
    // 亮绿底上用固定的深色字（深色模式下 ink 是浅色）
    val ink = if (status.needsAction) colors.onAccent else colors.ink
    val secondary = if (status.needsAction) colors.onAccent.copy(alpha = 0.75f) else colors.inkSecondary
    Row(
        modifier.fillMaxWidth().pressable(onClick = onClick).sticker(if (status.needsAction) colors.lime else colors.surface, radius = AppTheme.Radius.lg)
            .padding(AppTheme.Spacing.lg).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(status.icon, fill = status.tint, size = 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(tr("约球请求 · %@", ticket.event.title(ticket.mode)), style = AppTheme.Typography.overline, color = secondary)
            Text(ticket.slot.formattedFull(), style = AppTheme.Typography.headline, color = ink)
            Text(status.title, style = AppTheme.Typography.footnoteBold, color = if (status.needsAction) ink else secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Symbol(Sym.chevronRight, size = 13, tint = ink)
    }
}

/** 请求摘要：项目·时间 / 球馆 / 距离·实力差 */
@Composable
fun TicketSummaryCard(ticket: MatchTicket) {
    val manager = LocalEnv.current.matchManager
    val colors = AppTheme.colors
    LaunchedEffect(ticket.courtIds) { manager.loadVenues(ticket.courtIds) }
    val names = manager.courts(ticket.courtIds).map { it.name }
    val venueTitle = when {
        names.isEmpty() -> tr("%lld 个球馆", ticket.courtIds.size)
        names.size > 1 -> tr("%@ 等 %lld 家", names.first(), names.size)
        else -> names.first()
    }
    // 服务器不给请求的范围，用现在的附近范围
    val radius = DistanceFormatter.radius(if (ticket.radiusKm > 0) ticket.radiusKm else manager.radiusKm)
    val rangeTitle = if (ticket.skillTolerance >= MatchRequest.ANY_SKILL) tr("%@ · 实力不限", radius) else tr("%@ · 实力差 ±%lld 级", radius, ticket.skillTolerance)
    Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg)) {
        InfoRow(ticket.mode.icon, "${ticket.event.title(ticket.mode)} · ${ticket.slot.formattedFull()}", tint = colors.lavender)
        InsetDivider()
        InfoRow(Sym.mappinAndEllipse, venueTitle, tint = colors.sky)
        InsetDivider()
        InfoRow(Sym.arrowLeftAndRight, rangeTitle, tint = colors.peach)
    }
}

// MARK: - 请求已挂起，正在找

@Composable
fun TicketWaitingView(ticket: MatchTicket) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val colors = AppTheme.colors
    val (available, compatible) = manager.poolSummary(ticket)
    var confirmsCancel by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TagPill(if (ticket.isLastMinute) tr("临时局 · 正在找") else tr("在找搭子"), icon = Sym.circleFill, fill = colors.lime)
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭（请求会继续）")) { manager.closeFlow() }
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            Text(tr("找到就通知你"), style = AppTheme.Typography.display, color = colors.ink, modifier = Modifier.semantics { heading() })
            TicketSummaryCard(ticket)
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                StatTile(available.toString(), if (ticket.isLastMinute) tr("此刻在找") else tr("那天有空"), Modifier.weight(1f))
                StatTile(compatible.toString(), tr("都合适"), Modifier.weight(1f))
            }
            DeadlineTag(ticket)
            if (manager.suggestions.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Text(tr("想快一点"), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.semantics { heading() })
                    @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        for (suggestion in manager.suggestions) ChoiceChip(suggestion.title, isSelected = false) {}
                    }
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.md),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
                UnderlinedAction(tr("修改"), tr("修改请求")) {
                    // 关掉流程，打开填好原条件的设置页；保存时换掉这个请求
                    manager.prepareEdit(ticket)
                    manager.closeFlow()
                    scope.launch {
                        delay(450)
                        env.router.isMatchSetupPresented = true
                    }
                }
                UnderlinedAction(tr("取消"), tr("取消请求")) { confirmsCancel = true }
            }
            BrutalButton(tr("好"), { manager.closeFlow() }, kind = ButtonKind.Inverse)
        }
    }
    if (confirmsCancel) {
        CancelDialog(tr("还没约成，取消不影响任何记录。"), tr("继续找"), onDismiss = { confirmsCancel = false }) { manager.cancelTicket(ticket.id) }
    }
}

@Composable
private fun UnderlinedAction(title: String, label: String, onClick: () -> Unit) {
    Box(Modifier.height(44.dp).pressable(scale = 1f, onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Text(title, style = AppTheme.Typography.subheadlineBold.copy(textDecoration = TextDecoration.Underline), color = AppTheme.colors.inkSecondary)
    }
}

/** “周三 17:00前确认” + “?”（确认期限、到点没约成怎么办） */
@Composable
private fun DeadlineTag(ticket: MatchTicket) {
    val colors = AppTheme.colors
    val points = if (ticket.isLastMinute) {
        listOf(
            tr("临时局只找附近此刻也在找人的球友。"),
            tr("找到人后需要在 5–10 分钟内确认，最晚开赛前 20 分钟约成。"),
            tr("到点没约成会自动结束，不计入任何记录。"),
            tr("找到合适的人会马上通知你，不用一直开着 App。"),
        )
    } else {
        listOf(
            tr("最晚%@（开赛前 2 小时）前所有人都要确认，都确认了才算约成。", DateText.deadline(ticket.deadline)),
            tr("到点没约成会自动结束，不计入任何记录。"),
            tr("只和也能去这些球馆（或 150 米内同一处）的球友匹配。"),
            tr("找到合适的人会马上通知你，不用一直开着 App。"),
        )
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        TagPill(tr("%@前确认", DateText.deadline(ticket.deadline)), icon = Sym.timer, fill = colors.surface, foreground = colors.ink)
        RulesButton(tr("约成规则"), points)
    }
}

// MARK: - 暂停 / 结束 / 取消

@Composable
fun TicketEndedView(ticket: MatchTicket) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val canGoLastMinute = !ticket.isLastMinute && MatchTiming.canRequest(ticket.slot.startTime)
    val status = ticket.status
    val icon = when (status) {
        MatchTicket.Status.Paused -> Sym.pauseCircleFill
        MatchTicket.Status.Expired -> Sym.clockBadgeXmark
        else -> Sym.xmarkCircleFill
    }
    val title = when (status) {
        MatchTicket.Status.Paused -> tr("你错过了一个匹配")
        MatchTicket.Status.Expired -> tr("这次没约到人")
        else -> tr("请求已取消")
    }
    // 原来写在页面上的说明，收进“?”
    val points = when (status) {
        MatchTicket.Status.Paused -> listOf(tr("为了不让别人白等，错过确认的请求会先暂停。"), tr("还想打的话点“继续找”，不影响任何记录。"))
        MatchTicket.Status.Expired -> buildList {
            add(tr("%@ 到了确认截止时间还没凑齐，请求已结束。", ticket.slot.formattedFull()))
            add(tr("不计入任何记录。"))
            if (canGoLastMinute) add(tr("转临时局：只找此刻也在找人的球友，找到后会替你接受，等对方确认。"))
            add(tr("发起球局：发起公开球局，让球友来找你。"))
        }
        else -> emptyList()
    }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen)) {
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭")) { manager.closeFlow() }
        }
        Spacer(Modifier.weight(1f))
        Column(Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen), horizontalAlignment = Alignment.CenterHorizontally) {
            EmptyStateView(icon, title, tint = if (status == MatchTicket.Status.Paused) colors.peach else colors.surfaceMuted)
            if (points.isNotEmpty()) RulesButton(title, points)
        }
        Spacer(Modifier.weight(1f))
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            EndedActions(ticket, canGoLastMinute) { haptics.tap() }
        }
    }
}

@Composable
private fun ColumnScope.EndedActions(ticket: MatchTicket, canGoLastMinute: Boolean, tap: () -> Unit) {
    val env = LocalEnv.current
    val manager = env.matchManager
    when (ticket.status) {
        MatchTicket.Status.Paused -> {
            BrutalButton(tr("继续找"), {
                tap()
                manager.resumeTicket(ticket.id)
            })
            UnderlinedAction(tr("取消"), tr("取消请求")) { manager.cancelTicket(ticket.id) }
        }
        MatchTicket.Status.Expired -> {
            if (canGoLastMinute) {
                BrutalButton(onClick = { manager.retryAsLastMinute(ticket) }) { ArrowButtonLabel(tr("转临时局")) }
            }
            BrutalButton(
                tr("发起球局"), {
                    manager.closeFlow()
                    env.router.open(Route.CreateRoom(ticket.mode.serverValue), MainTab.Games)
                },
                kind = if (canGoLastMinute) ButtonKind.Secondary else ButtonKind.Primary,
            )
        }
        else -> BrutalButton(tr("关闭"), { manager.closeFlow() }, kind = ButtonKind.Secondary)
    }
}
