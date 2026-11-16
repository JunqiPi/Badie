package com.badie.app.features.rooms

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.Room
import com.badie.app.models.RoomParticipant
import com.badie.app.models.User
import com.badie.app.models.WindowText
import com.badie.app.models.title

// 公开球局卡片（“我有场地缺人”）。对应 iPhone 的 Features/Rooms/RoomCards.swift

/** 房间里的一个人的头像 */
@Composable
fun ParticipantAvatar(participant: RoomParticipant, modifier: Modifier = Modifier, size: Dp = 44.dp) {
    AvatarView(participant.userId, participant.avatarText, participant.avatar.paletteIndex, modifier, size)
}

/** [width] 为空时占满宽度（列表里），否则是横滑里的固定宽度 */
@Composable
fun PublicRoomCard(room: Room, distanceText: String?, currentUserId: String?, modifier: Modifier = Modifier, width: Dp? = 270.dp) {
    val colors = AppTheme.colors
    val description = accessibilityText(room)
    Column(
        modifier
            .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth())
            .sticker(colors.surface, radius = AppTheme.Radius.lg)
            .padding(AppTheme.Spacing.lg)
            .clearAndSetSemantics { contentDescription = description },
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            TagPill(room.mode.title, icon = room.mode.icon, fill = colors.lavender)
            TagPill(room.levelRangeText, fill = colors.surface, foreground = colors.ink)
            room.event?.let { TagPill(it.title(room.mode), fill = colors.peach) }
            Spacer(Modifier.weight(1f))
            SeatsBadge(room, currentUserId)
        }
        room.slot?.let { slot ->
            Text(slot.formattedDate(), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            Text(slot.formattedTimeRange(), style = rounded(24, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.ink)
        }
        room.court?.let { court ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Symbol(Sym.mappinAndEllipse, size = 11, tint = colors.inkSecondary)
                Text(court.name, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (distanceText != null) Text("· $distanceText", style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Row(horizontalArrangement = Arrangement.spacedBy((-8).dp)) {
                room.participants.forEachIndexed { index, participant ->
                    val z = Modifier.zIndex((room.requiredPlayerCount - index).toFloat())
                    if (participant.isAnonymous) AnonymousSeat(z) else ParticipantAvatar(participant, z, size = 28.dp)
                }
                repeat(room.openSeats) { OpenSeatDot() }
            }
            Spacer(Modifier.weight(1f))
            val cost = room.costEstimate
            if (cost != null && cost.perPerson != null) {
                Text(cost.perPersonText, style = AppTheme.Typography.headline.copy(fontFeatureSettings = "tnum"), color = colors.ink)
            }
        }
        if (room.tags.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (tag in room.tags.take(2)) TagPill(tag.title, icon = tag.icon, fill = colors.mint)
            }
        }
    }
}

/** 还没加入的公开局看不到是谁 */
@Composable
private fun AnonymousSeat(modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Box(
        modifier.size(28.dp).drawBehind {
            drawCircle(colors.surfaceMuted)
            drawCircle(colors.stroke, radius = size.minDimension / 2 - 0.75.dp.toPx(), style = Stroke(1.5.dp.toPx()))
        },
        contentAlignment = Alignment.Center,
    ) {
        Symbol(Sym.personFill, size = 12, tint = colors.inkSecondary)
    }
}

@Composable
private fun OpenSeatDot() {
    val colors = AppTheme.colors
    Box(
        Modifier.size(28.dp).drawBehind {
            drawCircle(colors.surface)
            drawCircle(
                colors.stroke, radius = size.minDimension / 2 - 0.75.dp.toPx(),
                style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))),
            )
        },
    )
}

@Composable
private fun SeatsBadge(room: Room, me: String?) {
    val colors = AppTheme.colors
    when {
        me != null && room.contains(me) -> TagPill(tr("已加入"), icon = Sym.checkmark, fill = colors.lime)
        me != null && room.isWaitlisted(me) -> TagPill(tr("候补中"), fill = colors.butter)
        room.isFull -> TagPill(tr("满员·可候补"), fill = colors.surfaceMuted, foreground = colors.inkSecondary)
        else -> TagPill(tr("缺 %lld 人", room.openSeats), fill = colors.pink)
    }
}

@Composable
private fun accessibilityText(room: Room): String {
    val parts = mutableListOf(tr("%@球局", room.mode.title), room.levelRangeText)
    room.event?.let { parts += it.title(room.mode) }
    room.slot?.let { parts += it.formattedFull() }
    room.court?.let { parts += it.name }
    parts += if (room.isFull) tr("已满员") else tr("还缺 %lld 人", room.openSeats)
    room.costEstimate?.takeIf { it.perPerson != null }?.let { parts += tr("约 %@", it.perPersonText) }
    return parts.joinToString("，")
}

/**
 * “我的房间”里附近的人发的邀请：和谁、大概什么时候、轮到谁。对应 iPhone 的 InviteRoomCard（在 NearbyViews.swift 里）。
 * 点开进房间页；回复邀请（说好、换时间、不了）的界面归发现页那边
 */
@Composable
fun InviteRoomCard(room: Room, currentUserId: String?, user: User?, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val time = room.window?.let { WindowText.headline(it) } ?: room.slot?.formattedFull() ?: ""
    val timeText = listOfNotNull(time, room.court?.name).joinToString(" · ")
    Row(
        modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        if (user != null) AvatarView(user, size = 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(user?.nickname ?: "", style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(timeText, style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (room.invite?.awaitingId == currentUserId) {
            TagPill(tr("待回复"), fill = colors.pink)
        } else {
            TagPill(tr("等 TA 回复"), fill = colors.butter)
        }
    }
}
