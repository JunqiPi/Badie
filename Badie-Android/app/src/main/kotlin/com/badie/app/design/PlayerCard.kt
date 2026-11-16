package com.badie.app.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.badie.app.l10n.tr
import com.badie.app.models.CardColor
import com.badie.app.models.User

// 对应 iPhone 的 DesignSystem/PlayerCard.swift（发现页、我的卡片预览、球馆页都用）

/** 卡片背景的颜色 */
val CardColor.fill: Color
    @Composable get() = when (this) {
        CardColor.Lime -> AppTheme.colors.lime
        CardColor.Lavender -> AppTheme.colors.lavender
        CardColor.Peach -> AppTheme.colors.peach
        CardColor.Sky -> AppTheme.colors.sky
        CardColor.Pink -> AppTheme.colors.pink
        CardColor.Mint -> AppTheme.colors.mint
        CardColor.Butter -> AppTheme.colors.butter
        CardColor.Ink -> Color(0xFF17140F)
    }

/** 卡片上半部分：有背景照片就铺满照片；没有就是卡片颜色 + 白色的球场线 */
@Composable
fun CardCover(color: CardColor, photo: ImageBitmap?, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().clearAndSetSemantics {}) {
        if (photo != null) {
            Image(photo, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            val fill = color.fill
            Canvas(Modifier.fillMaxSize()) {
                drawRect(fill)
                val left = 28.dp.toPx()
                val top = 16.dp.toPx()
                val w = size.width - 2 * left
                val h = size.height - 2 * top
                if (w <= 0 || h <= 0) return@Canvas
                val line = Color.White.copy(alpha = 0.85f)
                val width = 3.dp.toPx()
                fun l(x1: Float, y1: Float, x2: Float, y2: Float) =
                    drawLine(line, Offset(left + w * x1, top + h * y1), Offset(left + w * x2, top + h * y2), width)
                drawRect(line, Offset(left, top), androidx.compose.ui.geometry.Size(w, h), style = Stroke(width))
                // 网、两边的前发球线；中线；单打边线
                l(0f, 0.5f, 1f, 0.5f); l(0f, 0.32f, 1f, 0.32f); l(0f, 0.68f, 1f, 0.68f)
                l(0.5f, 0f, 0.5f, 0.32f); l(0.5f, 0.68f, 0.5f, 1f)
                l(0.08f, 0f, 0.08f, 1f); l(0.92f, 0f, 0.92f, 1f)
            }
        }
    }
}

/**
 * 发现页的大卡片：上面约四分之三是照片（没照片是卡片颜色 + 球场线），左上角一个白色小标签；
 * 下面一块白色信息区：名字和等级、一行信息、[footer]
 */
@Composable
fun CoverCard(
    user: User?,
    /** 左上角：“3.2 公里 · 常去 X” / “周六 14:00–17:00 · 单打” */
    pill: String?,
    /** 名字下面一行：“双打 · 靠谱” */
    line: String,
    modifier: Modifier = Modifier,
    onProfile: (() -> Unit)? = null,
    footer: @Composable ColumnScope.() -> Unit = {},
) {
    val colors = AppTheme.colors
    val shape = RoundedCornerShape(AppTheme.Radius.lg)
    val photos = LocalPhotos.current
    val profileLabel = tr("看资料")
    Column(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 240.dp)
            .sticker(colors.surface, radius = AppTheme.Radius.lg)
            // 描边最后画，盖在照片上面
            .drawWithContent {
                drawContent()
                val w = AppTheme.Stroke.width.toPx()
                drawRoundRect(
                    colors.stroke, Offset(w / 2, w / 2), androidx.compose.ui.geometry.Size(size.width - w, size.height - w),
                    androidx.compose.ui.geometry.CornerRadius(AppTheme.Radius.lg.toPx() - w / 2), style = Stroke(w),
                )
            }
            .clip(shape)
            .then(if (onProfile != null) Modifier.pressable(scale = 1f, onClick = onProfile) else Modifier)
            .semantics {
                if (onProfile != null) customActions = listOf(CustomAccessibilityAction(profileLabel) { onProfile(); true })
            },
    ) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (user != null) CardCover(user.cardColor, photos?.cardPhoto(user.id)) else Box(Modifier.fillMaxSize().drawBehind { drawRect(colors.surfaceMuted) })
            if (!pill.isNullOrEmpty()) {
                Text(
                    pill, style = AppTheme.Typography.footnoteBold, color = colors.onAccent, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .padding(AppTheme.Spacing.md)
                        .sticker(Color.White, radius = 14.dp, shadow = AppTheme.Elevation.none, stroke = colors.onAccent, strokeWidth = 1.5.dp)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
        }
        Spacer(Modifier.fillMaxWidth().height(3.dp).drawBehind { drawRect(colors.stroke) })
        Column(
            Modifier.fillMaxWidth().drawBehind { drawRect(colors.surface) }.padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
        ) {
            if (user != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    NicknameText(user, Modifier.weight(1f, fill = false), style = AppTheme.Typography.title3)
                    LevelBadge(user.displayTier)
                }
            }
            if (line.isNotEmpty()) Text(line, style = AppTheme.Typography.subheadlineBold, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            footer()
        }
    }
}

/** 卡片下面的圆按钮（✕ ♥ ★），带贴纸投影 */
@Composable
fun RoundActionLabel(icon: SymbolId, tint: Color, modifier: Modifier = Modifier, foreground: Color = AppTheme.colors.onAccent, size: Dp = 64.dp) {
    val colors = AppTheme.colors
    Box(
        modifier.size(size).drawBehind {
            val r = this.size.minDimension / 2
            drawCircle(colors.shadow, r, center.copy(x = center.x + 3.dp.toPx(), y = center.y + 4.dp.toPx()))
            drawCircle(tint, r)
            drawCircle(colors.stroke, r - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
        },
        contentAlignment = Alignment.Center,
    ) {
        Symbol(icon, size = (size.value * 0.36f).toInt(), tint = foreground)
    }
}

/** 近 180 天爽约过：卡片底部一个粉色小标签 */
@Composable
fun NoShowPill(count: Int, modifier: Modifier = Modifier) {
    TagPill(tr("近 180 天爽约 %lld 次", count), modifier, icon = Sym.exclamationmarkTriangleFill, fill = AppTheme.colors.pink)
}

/** 一个人：圆头像 + 下面的名字。发现页顶上那一排（正在看的那张卡加一圈柠檬绿）、球馆页的“最近在这打过”和“常客” */
@Composable
fun PersonBubble(user: User, modifier: Modifier = Modifier, isCurrent: Boolean = false, size: Dp = 52.dp, onClick: () -> Unit) {
    val colors = AppTheme.colors
    Column(
        modifier
            .pressable(role = Role.Button, onClick = onClick)
            .clearAndSetSemantics { contentDescription = user.nickname; selected = isCurrent },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
    ) {
        Box(
            Modifier.clip(CircleShape).drawBehind {
                if (isCurrent) {
                    drawCircle(colors.lime)
                    drawCircle(colors.stroke, this.size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                }
            }.padding(4.dp),
        ) { AvatarView(user, size = size) }
        Text(
            user.nickname, style = AppTheme.Typography.caption, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(size + 16.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}
