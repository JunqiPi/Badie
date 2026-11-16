package com.badie.app.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.zIndex
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.badie.app.l10n.ListText
import com.badie.app.l10n.tr
import com.badie.app.models.SkillTier
import com.badie.app.models.SurveyTag
import com.badie.app.models.User
import com.badie.app.models.VerificationStatus

// 对应 iPhone 的 DesignSystem/Identity.swift 里剩下的几个

/** 重叠的一排头像，多出来的显示“+3” */
@Composable
fun AvatarStack(users: List<User>, modifier: Modifier = Modifier, size: Dp = 32.dp, maxCount: Int = 4) {
    val colors = AppTheme.colors
    val names = users.joinToString(tr("、")) { it.nickname }
    Row(modifier.clearAndSetSemantics { contentDescription = names }, horizontalArrangement = Arrangement.spacedBy(-size * 0.32f)) {
        users.take(maxCount).forEachIndexed { index, user ->
            AvatarView(user, Modifier.zIndex((maxCount - index).toFloat()), size = size)
        }
        if (users.size > maxCount) {
            Box(
                Modifier.size(size).drawBehind {
                    drawCircle(colors.surfaceMuted)
                    drawCircle(colors.stroke, radius = this.size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                },
                contentAlignment = Alignment.Center,
            ) {
                Text("+${users.size - maxCount}", style = rounded((size.value * 0.36f).toInt(), FontWeight.ExtraBold), color = colors.ink)
            }
        }
    }
}

/** 等级徽章：深底柠檬色字，“Lv.4+ 中级” */
@Composable
fun LevelBadge(tier: SkillTier, modifier: Modifier = Modifier, showsName: Boolean = true, compact: Boolean = false) {
    val label = tr("等级 %@，%@", tier.spokenText, tier.name)
    Box(
        modifier
            .clip(RoundedCornerShape(7.dp))
            .drawBehind { drawRect(Color(0xFF17140F)) }
            .padding(horizontal = if (compact) 5.dp else 7.dp, vertical = if (compact) 1.5.dp else 3.dp)
            .clearAndSetSemantics { contentDescription = label },
    ) {
        Text(
            if (showsName) tier.displayText else tier.text,
            style = if (compact) rounded(10, FontWeight.ExtraBold) else AppTheme.Typography.caption.copy(fontWeight = FontWeight.ExtraBold),
            color = AppTheme.colors.lime, maxLines = 1, softWrap = false,
        )
    }
}

@Composable
fun LevelBadge(level: Int, modifier: Modifier = Modifier, showsName: Boolean = true, compact: Boolean = false) =
    LevelBadge(SkillTier(level), modifier, showsName, compact)

@Composable
fun NewPlayerBadge(modifier: Modifier = Modifier) {
    val label = tr("新球友，评价不足 5 次，水平待校准")
    TagPill(tr("新球友 · 待校准"), modifier.clearAndSetSemantics { contentDescription = label }, icon = Sym.sparkles, fill = AppTheme.colors.butter)
}

/** “靠谱”徽章：只看客观履约记录（打满 3 场、没有爽约、临时取消 ≤1 次） */
@Composable
fun ReliableBadge(modifier: Modifier = Modifier) {
    val label = tr("靠谱：打满 3 场，没有爽约")
    TagPill(tr("靠谱"), modifier.clearAndSetSemantics { contentDescription = label }, icon = Sym.checkmarkShieldFill, fill = AppTheme.colors.mint)
}

/** 球友给得最多的正面标签（月度快照）；没到展示门槛时显示一句说明 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PraiseTagsView(tags: List<SurveyTag>, modifier: Modifier = Modifier, emptyText: String? = tr("5 位以上球友评价后显示")) {
    if (tags.isEmpty()) {
        if (emptyText != null) Text(emptyText, modifier, style = AppTheme.Typography.footnote, color = AppTheme.colors.inkTertiary)
        return
    }
    val label = tr("球友印象：%@", ListText.and(tags.map { it.title }))
    FlowRow(
        modifier.clearAndSetSemantics { contentDescription = label },
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        for (tag in tags) TagPill(tag.title, icon = Sym.handThumbsupFill, fill = AppTheme.colors.lime)
    }
}

@Composable
fun VerifiedBadge(status: VerificationStatus, modifier: Modifier = Modifier) {
    status.badgeText?.let { TagPill(it, modifier, icon = Sym.checkmarkSealFill, fill = AppTheme.colors.lime) }
}

/** 星级（球品 1–5 星） */
@Composable
fun RatingPicker(rating: Int, onChange: (Int) -> Unit, modifier: Modifier = Modifier, maximum: Int = 5) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        for (value in 1..maximum) {
            val label = tr("%lld 星", value)
            Box(
                Modifier
                    .size(44.dp)
                    .pressable(scale = 0.85f) {
                        haptics.selection()
                        onChange(value)
                    }
                    .semantics { contentDescription = label; selected = value == rating; role = Role.RadioButton },
                contentAlignment = Alignment.Center,
            ) {
                Symbol(if (value <= rating) Sym.starFill else Sym.star, size = 30, tint = if (value <= rating) colors.star else colors.inkTertiary)
            }
        }
    }
}

/** 昵称 + 灰一点的编号（“阿杰#0042”）：昵称可以重名，昵称 + 编号不会 */
@Composable
fun NicknameText(user: User, modifier: Modifier = Modifier, style: androidx.compose.ui.text.TextStyle = AppTheme.Typography.bodyBold, color: Color = AppTheme.colors.ink) {
    Row(modifier.semantics(mergeDescendants = true) {}) {
        Text(user.nickname, Modifier.weight(1f, fill = false), style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(user.tagText, style = style, color = color.copy(alpha = color.alpha * 0.5f), maxLines = 1, softWrap = false)
    }
}
