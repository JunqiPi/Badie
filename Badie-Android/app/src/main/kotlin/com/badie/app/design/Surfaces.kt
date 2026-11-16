package com.badie.app.design

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import com.badie.app.l10n.tr

// MARK: - 贴纸式表面：填充 + 墨色描边 + 硬投影

/** 画一块贴纸：先画错开的硬投影，再画填充，描边画在边缘以内 */
internal fun DrawScope.drawSticker(fill: Color, stroke: Color, shadow: Color, radius: Dp, offset: DpOffset, strokeWidth: Dp = AppTheme.Stroke.width) {
    val r = radius.toPx().coerceAtMost(size.minDimension / 2)
    if (offset != AppTheme.Elevation.none) {
        drawRoundRect(shadow, topLeft = Offset(offset.x.toPx(), offset.y.toPx()), size = size, cornerRadius = CornerRadius(r))
    }
    drawRoundRect(fill, cornerRadius = CornerRadius(r))
    val w = strokeWidth.toPx()
    drawRoundRect(
        stroke, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w),
        cornerRadius = CornerRadius((r - w / 2).coerceAtLeast(0f)), style = Stroke(w),
    )
}

/** 贴纸卡片背景（默认白色表面 + 描边 + 右下硬投影） */
@Composable
fun Modifier.sticker(
    fill: Color = AppTheme.colors.surface,
    radius: Dp = AppTheme.Radius.lg,
    shadow: DpOffset = AppTheme.Elevation.card,
    stroke: Color = AppTheme.colors.stroke,
    strokeWidth: Dp = AppTheme.Stroke.width,
): Modifier {
    val shadowColor = AppTheme.colors.shadow
    return drawBehind { drawSticker(fill, stroke, shadowColor, radius, shadow, strokeWidth) }
}

/** 带内边距的卡片，占满宽度 */
@Composable
fun Modifier.card(
    fill: Color = AppTheme.colors.surface,
    padding: Dp = AppTheme.Spacing.lg,
    radius: Dp = AppTheme.Radius.lg,
    shadow: DpOffset = AppTheme.Elevation.card,
): Modifier = fillMaxWidth().sticker(fill, radius, shadow).padding(padding)

/** 按下时轻微缩小的点击（卡片、图标按钮）。没有水波纹，和 iPhone 一致 */
@Composable
fun Modifier.pressable(
    scale: Float = 0.96f,
    enabled: Boolean = true,
    role: Role = Role.Button,
    onClickLabel: String? = null,
    onClick: () -> Unit,
): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val current by animateFloatAsState(if (pressed) scale else 1f, AppTheme.Motion.press(), label = "press")
    return graphicsLayer { scaleX = current; scaleY = current }
        .clickable(interaction, indication = null, enabled = enabled, onClickLabel = onClickLabel, role = role, onClick = onClick)
}

// MARK: - 图标贴片（马卡龙底色 + 描边 + 图标）

@Composable
fun IconTile(
    symbol: SymbolId,
    modifier: Modifier = Modifier,
    fill: Color = AppTheme.colors.lime,
    size: Dp = 40.dp,
    iconColor: Color = AppTheme.colors.onAccent,
) {
    Box(
        modifier.size(size).sticker(fill, radius = size * 0.3f, shadow = AppTheme.Elevation.none).clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Symbol(symbol, size = (size.value * 0.45f).toInt(), tint = iconColor)
    }
}

/** 中性图标按钮（返回、设置等），点击区域 44 */
@Composable
fun IconButton(
    symbol: SymbolId,
    accessibilityLabel: String,
    modifier: Modifier = Modifier,
    /** 给了强调色时图标用 onAccent，否则是中性表面加墨色图标 */
    accent: Color? = null,
    badge: Int = 0,
    onClick: () -> Unit,
) {
    val unread = if (badge > 0) tr("%lld 条未读", badge) else ""
    Box(
        modifier
            .pressable(onClick = onClick)
            .semantics { contentDescription = accessibilityLabel; stateDescription = unread },
    ) {
        Box(
            Modifier.size(44.dp).sticker(accent ?: AppTheme.colors.surface, radius = 14.dp, shadow = AppTheme.Elevation.low),
            contentAlignment = Alignment.Center,
        ) {
            Symbol(symbol, size = 17, tint = if (accent == null) AppTheme.colors.ink else AppTheme.colors.onAccent)
        }
        if (badge > 0) {
            CountBadge(badge, Modifier.align(Alignment.TopEnd).offset(6.dp, (-6).dp))
        }
    }
}

/** 红色数字角标 */
@Composable
fun CountBadge(count: Int, modifier: Modifier = Modifier) {
    val canvas = AppTheme.colors.canvas
    val fill = AppTheme.colors.dangerFill
    Box(
        modifier
            .defaultMinSize(20.dp, 20.dp)
            .drawBehind { drawSticker(fill, canvas, canvas, 10.dp, AppTheme.Elevation.none) }
            .padding(horizontal = 5.dp)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Text(if (count > 99) "99+" else count.toString(), style = rounded(11, FontWeight.ExtraBold), color = Color.White, maxLines = 1)
    }
}

// MARK: - 屏幕标题栏（自绘，不用系统导航栏）

@Composable
fun ScreenHeader(
    title: String,
    modifier: Modifier = Modifier,
    /** 不给就不显示返回键 */
    onBack: (() -> Unit)? = null,
    trailing: @Composable RowScope.() -> Unit = {},
) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(horizontal = AppTheme.Spacing.screen)
            .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.md)
            .defaultMinSize(minHeight = 44.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, maxLines = 1,
            overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 56.dp).semantics { heading() },
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) {
                IconButton(Sym.chevronLeft, tr("返回"), onClick = onBack)
            }
            Spacer(Modifier.weight(1f))
            trailing()
        }
    }
}

/** 大标题（标签页的根页面） */
@Composable
fun LargeTitleHeader(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: @Composable RowScope.() -> Unit = {},
) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (subtitle != null) {
                Text(subtitle, style = AppTheme.Typography.subheadlineBold, color = AppTheme.colors.inkSecondary)
            }
            Text(title, style = AppTheme.Typography.display, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        }
        trailing()
    }
}

// MARK: - 分区标题

@Composable
fun SectionTitle(
    title: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    actionTitle: String? = null,
    action: (() -> Unit)? = null,
) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = AppTheme.Typography.title3, color = AppTheme.colors.ink, modifier = Modifier.alignByBaseline().semantics { heading() })
        if (detail != null) {
            Text(
                detail, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary,
                modifier = Modifier.alignByBaseline().padding(start = AppTheme.Spacing.sm),
            )
        }
        Spacer(Modifier.weight(1f))
        if (actionTitle != null && action != null) {
            Box(Modifier.defaultMinSize(minHeight = 44.dp).clickable(onClick = action, role = Role.Button), contentAlignment = Alignment.Center) {
                Text(actionTitle, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
            }
        }
    }
}

// MARK: - 统计格

@Composable
fun StatTile(value: String, label: String, modifier: Modifier = Modifier, /** 给了强调色时文字用 onAccent */ accent: Color? = null) {
    Column(
        modifier
            .fillMaxWidth()
            .sticker(accent ?: AppTheme.colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md)
            .clearAndSetSemantics { contentDescription = "$label $value" },
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        // 放不下时缩小到六成（“0.9 英里”这类长一点的值）
        FitText(
            value, style = rounded(24, FontWeight.Black).copy(fontFeatureSettings = "tnum"),
            color = if (accent == null) AppTheme.colors.ink else AppTheme.colors.onAccent, minimumScale = 0.6f,
        )
        Text(
            label, style = AppTheme.Typography.caption, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = if (accent == null) AppTheme.colors.inkSecondary else AppTheme.colors.onAccent.copy(alpha = 0.75f),
        )
    }
}

// MARK: - 信息行（图标贴片 + 标题 + 说明）

@Composable
fun InfoRow(
    icon: SymbolId,
    title: String,
    modifier: Modifier = Modifier,
    tint: Color = AppTheme.colors.sky,
    subtitle: String? = null,
    trailing: @Composable RowScope.() -> Unit = {},
) {
    Row(
        modifier.fillMaxWidth().padding(vertical = AppTheme.Spacing.sm).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(icon, fill = tint, size = 36.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = AppTheme.Typography.bodyBold, color = AppTheme.colors.ink)
            if (subtitle != null) {
                Text(subtitle, style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
            }
        }
        trailing()
    }
}

/** 列表菜单行（“我的”页等） */
@Composable
fun MenuRow(
    icon: SymbolId,
    title: String,
    modifier: Modifier = Modifier,
    tint: Color = AppTheme.colors.lavender,
    value: String? = null,
    badge: Int = 0,
    isDestructive: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier.fillMaxWidth().clickable(onClick = onClick, role = Role.Button).padding(vertical = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(icon, fill = tint, size = 34.dp)
        Text(
            title, style = AppTheme.Typography.bodyBold, modifier = Modifier.weight(1f),
            color = if (isDestructive) AppTheme.colors.danger else AppTheme.colors.ink,
        )
        if (badge > 0) CountBadge(badge)
        if (value != null) {
            Text(value, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
        }
        Symbol(Sym.chevronRight, size = 13, tint = AppTheme.colors.inkTertiary)
    }
}

/** 卡片里的分割线 */
@Composable
fun InsetDivider(modifier: Modifier = Modifier) {
    val color = AppTheme.colors.divider
    Spacer(modifier.fillMaxWidth().height(AppTheme.Stroke.hairline).drawBehind { drawRect(color) })
}

/** 小圆点（标签栏选中、未读） */
@Composable
fun Dot(color: Color, size: Dp, modifier: Modifier = Modifier) {
    Spacer(modifier.size(size).clip(CircleShape).drawBehind { drawRect(color) })
}
