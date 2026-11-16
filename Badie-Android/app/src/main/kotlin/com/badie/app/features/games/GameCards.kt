package com.badie.app.features.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarStack
import com.badie.app.design.DashedDivider
import com.badie.app.design.FitText
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TicketShape
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.design.pressable
import com.badie.app.design.SymbolId
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.Game
import com.badie.app.models.GameStatus
import com.badie.app.models.ResultStatus
import com.badie.app.models.User
import com.badie.app.models.WindowText
import com.badie.app.models.addingDays
import com.badie.app.models.isSameDay
import kotlinx.coroutines.delay
import java.time.ZoneId

// 球局卡片：票据卡（球局页的“下一场”、详情页头部）和列表行。对应 iPhone 的 Features/Games/GameCards.swift

/** 每隔一段时间变一次的“现在”（倒计时、签到开放这类跟着时间变的） */
@Composable
fun rememberNow(periodMillis: Long = 60_000): State<Long> = produceState(System.currentTimeMillis(), periodMillis) {
    while (true) {
        delay(periodMillis)
        value = System.currentTimeMillis()
    }
}

/** 球局的底色：约好了是桃色，打完了是薄荷色，取消了是灰的 */
@Composable
fun Game.tint(): Color = when (status) {
    GameStatus.Confirmed -> AppTheme.colors.peach
    GameStatus.Completed -> AppTheme.colors.mint
    GameStatus.Cancelled -> AppTheme.colors.surfaceMuted
}

/** 票据卡上的小胶囊：白底（或别的色）+ 细描边 */
@Composable
fun TicketChip(text: String, fill: Color, foreground: Color = AppTheme.colors.onAccent) {
    val stroke = AppTheme.colors.onAccent
    Text(
        text, style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Black), color = foreground, maxLines = 1,
        modifier = Modifier
            .drawBehind {
                val radius = CornerRadius(size.height / 2)
                drawRoundRect(fill, cornerRadius = radius)
                val w = 1.5.dp.toPx()
                drawRoundRect(stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius((size.height - w) / 2), style = Stroke(w))
            }
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}

/** 带投影的票据形状（右下错开的硬投影 + 填充 + 描边） */
private fun Modifier.ticket(shape: Shape, fill: Color, stroke: Color, shadow: Color): Modifier = drawBehind {
    val outline = shape.createOutline(size, layoutDirection, this)
    drawContext.transform.translate(3.dp.toPx(), 4.dp.toPx())
    drawOutline(outline, shadow)
    drawContext.transform.translate(-3.dp.toPx(), -4.dp.toPx())
    drawOutline(outline, fill)
    drawOutline(outline, stroke, style = Stroke(2.dp.toPx()))
}

@Composable
fun GameTicketCard(game: Game, players: List<User>, currentUserId: String?, modifier: Modifier = Modifier, compact: Boolean = false) {
    val now by rememberNow()
    val colors = AppTheme.colors
    val ink = colors.onAccent
    val window = game.window
    val hasOthers = players.any { it.id != currentUserId }
    val shape = if (compact) androidx.compose.foundation.shape.RoundedCornerShape(22.dp) else TicketShape(notchPosition = 0.55f)
    val description = tr("%@球局，%@，%@，%@", game.mode.title, timeText(game), game.court.name, playersText(players, currentUserId))
    Column(
        modifier
            .fillMaxWidth()
            .ticket(shape, game.tint(), colors.stroke, colors.shadow)
            .padding(if (compact) AppTheme.Spacing.lg else AppTheme.Spacing.xl)
            .clearAndSetSemantics { contentDescription = description },
        verticalArrangement = Arrangement.spacedBy(if (compact) AppTheme.Spacing.sm else AppTheme.Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TicketChip("${game.mode.title} · ${game.statusText}", Color.White)
            Spacer(Modifier.weight(1f))
            StatusChip(game, currentUserId, now)
        }
        if (window != null) {
            // 还没定具体几点：大字写“周六 下午”，小字写“14:00–18:00 之间 · 球馆”
            FitText(WindowText.headline(window, now), style = rounded(if (compact) 30 else 40, FontWeight.Black), color = ink)
            Text(
                "${WindowText.between(window)} · ${game.court.name}", style = AppTheme.Typography.bodyBold.copy(fontFeatureSettings = "tnum"),
                color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            if (!compact) {
                DashedDivider(Modifier.padding(vertical = AppTheme.Spacing.xs))
                Text(game.court.address, style = AppTheme.Typography.footnote, color = ink.copy(alpha = 0.75f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        } else {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    DateText.time(game.slot.startTime), color = ink, maxLines = 1,
                    style = rounded(if (compact) 34 else 44, FontWeight.Black).copy(fontFeatureSettings = "tnum"),
                    modifier = Modifier.alignByBaseline(),
                )
                Text(
                    "–${DateText.time(game.slot.endTime)}", color = ink, maxLines = 1,
                    style = rounded(if (compact) 18 else 22, FontWeight.Black).copy(fontFeatureSettings = "tnum"),
                    modifier = Modifier.alignByBaseline(),
                )
            }
            if (compact) {
                // 球局页：“今天 · 球馆名”一行，地址在详情里
                Text("${dayText(game, now)} · ${game.court.name}", style = AppTheme.Typography.bodyBold, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            } else {
                Text(game.slot.formattedDate(now), style = AppTheme.Typography.bodyBold, color = ink)
                DashedDivider(Modifier.padding(vertical = AppTheme.Spacing.xs))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(game.court.name, style = AppTheme.Typography.headline, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(game.court.address, style = AppTheme.Typography.footnote, color = ink.copy(alpha = 0.75f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            AvatarStack(players, size = if (compact) 30.dp else 36.dp)
            if (!hasOthers) {
                Text(tr("等待球友加入"), style = AppTheme.Typography.footnoteBold, color = ink, maxLines = 1)
            }
            Spacer(Modifier.weight(1f))
            if (game.cost.perPerson != null) {
                Text(game.cost.perPersonText, style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = ink)
            }
        }
    }
}

@Composable
private fun StatusChip(game: Game, currentUserId: String?, now: Long) {
    val colors = AppTheme.colors
    when (game.status) {
        GameStatus.Confirmed -> when {
            !game.isTimeSet -> TicketChip(tr("待定时间"), colors.butter)
            game.isInProgress(now) -> TicketChip(tr("进行中"), colors.lime)
            game.slot.endTime <= now -> TicketChip(tr("待完成"), colors.butter)
            else -> TicketChip(DateText.countdown(game.slot.startTime, now), Color(0xFF17140F), colors.lime)
        }
        GameStatus.Completed -> {
            val status = game.resultStatus(now)
            when {
                status == ResultStatus.Awaiting && game.resultReports.isNotEmpty() -> TicketChip(tr("待确认"), colors.butter)
                status == ResultStatus.Disputed -> TicketChip(tr("有分歧"), colors.pink)
                else -> TicketChip(if (game.resultOutcome(currentUserId, now) == true) tr("已获胜") else tr("已完成"), colors.surface)
            }
        }
        GameStatus.Cancelled -> TicketChip(if (game.cancelledLate) tr("临时取消") else tr("已取消"), colors.surface)
    }
}

@Composable
private fun timeText(game: Game): String =
    game.window?.let { "${WindowText.headline(it)} ${WindowText.between(it)}" } ?: game.slot.formattedFull()

/** “今天”“明天”，再往后是日期 */
@Composable
private fun dayText(game: Game, now: Long): String {
    val zone = ZoneId.systemDefault()
    if (isSameDay(game.slot.date, now, zone)) return tr("今天")
    if (isSameDay(game.slot.date, addingDays(now, 1, zone), zone)) return tr("明天")
    return DateText.shortDay(game.slot.date)
}

/** 读屏用的一句话（界面上只放头像） */
@Composable
private fun playersText(players: List<User>, currentUserId: String?): String {
    val others = players.filter { it.id != currentUserId }.map { it.nickname }
    if (others.isEmpty()) return tr("等待球友加入")
    if (others.size == 1) return tr("你和 %@", others[0])
    val more = if (others.size > 2) tr(" 等 %lld 人", others.size) else ""
    return tr("你和 %@%@", others.take(2).joinToString(tr("、")), more)
}

// MARK: - 列表行卡片

@Composable
fun GameRowCard(game: Game, players: List<User>, currentUserId: String?, modifier: Modifier = Modifier, pendingSurveyCount: Int = 0) {
    val colors = AppTheme.colors
    Row(
        modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Column(
            Modifier.size(56.dp, 62.dp).sticker(game.tint(), radius = 14.dp, shadow = AppTheme.Elevation.none),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(DateText.weekday(game.slot.startTime), style = AppTheme.Typography.caption, color = colors.onAccent)
            Text(
                game.slot.startTime.let { java.time.Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).dayOfMonth }.toString(),
                style = rounded(24, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.onAccent,
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "${game.mode.title} · ${game.window?.let { WindowText.headline(it) } ?: game.slot.formattedTimeRange()}",
                    style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                )
                if (game.status == GameStatus.Cancelled) {
                    TagPill(if (game.cancelledLate) tr("临时取消") else tr("已取消"), fill = colors.surfaceMuted, foreground = colors.inkSecondary)
                }
            }
            Text(game.court.name, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AvatarStack(players.filter { it.id != currentUserId }, size = 24.dp)
                if (pendingSurveyCount > 0) {
                    TagPill(tr("待评价 %lld", pendingSurveyCount), icon = Sym.starFill, fill = colors.pink)
                } else if (game.status == GameStatus.Completed) {
                    val text = resultText(game, currentUserId)
                    if (text.isNotEmpty()) {
                        Text(text, style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1)
                    }
                    val status = game.resultStatus()
                    if (status == ResultStatus.Awaiting && game.resultReports.isNotEmpty()) {
                        TagPill(tr("待确认"), fill = colors.butter)
                    } else if (status == ResultStatus.Disputed) {
                        TagPill(tr("有分歧"), fill = colors.pink)
                    }
                }
            }
        }
        Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
    }
}

@Composable
private fun resultText(game: Game, currentUserId: String?): String {
    val score = game.reportedScore(currentUserId)
    return when (game.resultOutcome(currentUserId)) {
        true -> tr("胜 %@", score)
        false -> tr("负 %@", score)
        null -> score
    }
}

// MARK: - 赛果展示（iPhone 写在 GameCards.swift 的 extension Game 里）

/** 某位球员视角的胜负：赛果确认后以确认结果为准，否则看他自己的申报；null = 未知或不计胜负 */
fun Game.resultOutcome(userId: String?, now: Long = System.currentTimeMillis()): Boolean? {
    // 早期的球局没有申报记录，沿用当时记下的结果
    if (resultReports.isEmpty()) return result?.didWin
    if (userId == null) return null
    val mine = team(userId) ?: return null
    val status = resultStatus(now)
    if (status is ResultStatus.Verified) return status.winningTeam == mine
    return report(userId)?.winningTeam?.let { it == mine }
}

/** 展示用的比分：优先本人申报的 */
fun Game.reportedScore(userId: String?): String {
    val mine = userId?.let { report(it) }
    if (mine != null && mine.score.isNotEmpty()) return mine.score
    return resultReports.firstOrNull { it.score.isNotEmpty() }?.score ?: result?.score ?: ""
}

/** 待办小标签：图标 + 一个词 + 红色数字（“挑战 1”“待评价 2”）。对应 iPhone 的 CountPill */
@Composable
fun CountPill(icon: SymbolId, title: String, count: Int, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val danger = colors.dangerFill
    val label = if (count > 0) "$title $count" else title
    Row(
        modifier
            .pressable(onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = label }
            .defaultMinSize(minHeight = 36.dp)
            .sticker(colors.surface, radius = 18.dp, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Symbol(icon, size = 12, tint = colors.ink)
        Text(title, style = AppTheme.Typography.footnoteBold, color = colors.ink, maxLines = 1)
        if (count > 0) {
            Text(
                "$count", style = rounded(11, FontWeight.ExtraBold).copy(fontFeatureSettings = "tnum"), color = Color.White,
                modifier = Modifier
                    .drawBehind { drawRoundRect(danger, cornerRadius = CornerRadius(size.height / 2)) }
                    .padding(horizontal = 6.dp, vertical = 1.dp),
            )
        }
    }
}
