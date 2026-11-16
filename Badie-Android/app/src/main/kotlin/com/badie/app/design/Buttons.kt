package com.badie.app.design

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp

// MARK: - 主按钮：描边 + 垂直硬投影，按下时压平

sealed interface ButtonKind {
    /** 柠檬绿，页面最重要的行动 */
    data object Primary : ButtonKind
    /** 墨色（深色模式是米白），次重要的强行动 */
    data object Inverse : ButtonKind
    /** 白色表面，次要行动 */
    data object Secondary : ButtonKind
    /** 危险操作 */
    data object Destructive : ButtonKind
    /** 自定的马卡龙色 */
    data class Accent(val color: Color) : ButtonKind
}

enum class ButtonSize(val minHeight: Dp, val horizontalPadding: Dp, val radius: Dp, val depth: Dp) {
    Large(56.dp, AppTheme.Spacing.xl, 18.dp, AppTheme.Elevation.buttonDepth),
    Medium(46.dp, AppTheme.Spacing.lg, 14.dp, 3.dp),
    Small(36.dp, AppTheme.Spacing.md, 12.dp, 2.dp);

    val font: TextStyle
        get() = when (this) {
            Large -> AppTheme.Typography.headline
            Medium -> AppTheme.Typography.subheadlineBold
            Small -> AppTheme.Typography.footnoteBold
        }
}

@Composable
fun BrutalButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ButtonKind = ButtonKind.Primary,
    size: ButtonSize = ButtonSize.Large,
    fullWidth: Boolean = true,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = AppTheme.colors
    val fill = if (!enabled) colors.surfaceMuted else when (kind) {
        ButtonKind.Primary -> colors.lime
        ButtonKind.Inverse -> colors.inverse
        ButtonKind.Secondary -> colors.surface
        ButtonKind.Destructive -> colors.dangerFill
        is ButtonKind.Accent -> kind.color
    }
    val foreground = if (!enabled) colors.inkTertiary else when (kind) {
        ButtonKind.Primary, is ButtonKind.Accent -> colors.onAccent
        ButtonKind.Inverse -> colors.onInverse
        ButtonKind.Secondary -> colors.ink
        ButtonKind.Destructive -> Color.White
    }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val depth = if (enabled) size.depth else 0.dp
    val sink by animateDpAsState(if (pressed && enabled) depth else 0.dp, AppTheme.Motion.press(), label = "sink")
    val shape = RoundedCornerShape(size.radius)
    Row(
        modifier
            .then(if (fullWidth) Modifier.fillMaxWidth() else Modifier)
            .defaultMinSize(minHeight = size.minHeight)
            .drawBehind {
                // 投影不动，按钮面往下沉
                translate(top = depth.toPx()) { drawSticker(colors.shadow, colors.shadow, colors.shadow, size.radius, AppTheme.Elevation.none) }
                translate(top = sink.toPx()) { drawSticker(fill, colors.stroke, colors.shadow, size.radius, AppTheme.Elevation.none) }
            }
            .clip(shape)
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .offset { IntOffset(0, sink.roundToPx()) }
            .padding(horizontal = size.horizontalPadding),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides foreground, LocalTextStyle provides size.font, content = { content() })
    }
}

/** 只有一行字的按钮；字放不下时最多缩到八成 */
@Composable
fun BrutalButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ButtonKind = ButtonKind.Primary,
    size: ButtonSize = ButtonSize.Large,
    fullWidth: Boolean = true,
    enabled: Boolean = true,
) {
    BrutalButton(onClick, modifier, kind, size, fullWidth, enabled) { FitText(title) }
}

/** 一行字，放不下时缩小（默认最小到八成，iPhone 的 minimumScaleFactor），再放不下才省略 */
@Composable
fun FitText(
    text: String, modifier: Modifier = Modifier, style: TextStyle = LocalTextStyle.current, color: Color = LocalContentColor.current,
    minimumScale: Float = 0.8f,
) {
    BasicText(
        text, modifier, style = style, color = { color }, maxLines = 1, overflow = TextOverflow.Ellipsis,
        autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * minimumScale, maxFontSize = style.fontSize),
    )
}

// MARK: - 文字按钮（低强调）

@Composable
fun TextAction(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = AppTheme.colors.inkSecondary, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.6f else 1f, label = "alpha")
    Box(
        modifier
            .defaultMinSize(minHeight = 44.dp)
            .graphicsLayer { this.alpha = alpha }
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = AppTheme.Typography.subheadlineBold, color = color)
    }
}

// MARK: - 行动按钮的内容：文字 + 右边的圆角箭头块

@Composable
fun RowScope.ArrowButtonLabel(title: String, arrowFill: Color = AppTheme.colors.lime) {
    FitText(title, Modifier.weight(1f))
    Spacer(Modifier.width(AppTheme.Spacing.sm))
    Box(
        Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).drawBehind { drawRect(arrowFill) },
        contentAlignment = Alignment.Center,
    ) {
        Symbol(Sym.arrowRight, size = 17, tint = AppTheme.colors.onAccent)
    }
}
