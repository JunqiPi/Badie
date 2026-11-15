package com.badie.app.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// MARK: - 提示条

data class Toast(val message: String, val style: Style = Style.Info, val id: Long = System.nanoTime()) {
    enum class Style { Info, Success, Error }
}

@Composable
fun ToastView(toast: Toast, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val (icon, fill) = when (toast.style) {
        Toast.Style.Info -> Sym.infoCircleFill to colors.sky
        Toast.Style.Success -> Sym.checkmarkCircleFill to colors.lime
        Toast.Style.Error -> Sym.exclamationmarkTriangleFill to colors.pink
    }
    Row(
        modifier
            .padding(horizontal = AppTheme.Spacing.screen)
            .sticker(fill, radius = 16.dp, shadow = AppTheme.Elevation.low)
            .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(icon, size = 16, tint = colors.onAccent)
        Text(toast.message, style = AppTheme.Typography.subheadlineBold, color = colors.onAccent)
    }
}

// MARK: - 空状态

@Composable
fun EmptyStateView(
    icon: SymbolId,
    title: String,
    modifier: Modifier = Modifier,
    message: String? = null,
    tint: Color = AppTheme.colors.lavender,
    actionTitle: String? = null,
    action: (() -> Unit)? = null,
) {
    Column(
        modifier.fillMaxWidth().padding(AppTheme.Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(icon, Modifier.rotate(-6f), fill = tint, size = 64.dp)
        Text(title, style = AppTheme.Typography.title3, color = AppTheme.colors.ink, textAlign = TextAlign.Center)
        if (message != null) {
            Text(message, style = AppTheme.Typography.subheadline, color = AppTheme.colors.inkSecondary, textAlign = TextAlign.Center)
        }
        if (actionTitle != null && action != null) {
            BrutalButton(actionTitle, action, Modifier.padding(top = AppTheme.Spacing.xs), size = ButtonSize.Medium, fullWidth = false)
        }
    }
}

// MARK: - 横幅（定位关闭、演示模式等）

@Composable
fun NoticeBanner(
    icon: SymbolId,
    text: String,
    modifier: Modifier = Modifier,
    tint: Color = AppTheme.colors.butter,
    actionTitle: String? = null,
    action: (() -> Unit)? = null,
) {
    Row(
        modifier
            .fillMaxWidth()
            .sticker(tint, radius = 16.dp, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Symbol(icon, size = 16, tint = AppTheme.colors.onAccent)
        Text(text, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.onAccent, modifier = Modifier.weight(1f))
        if (actionTitle != null && action != null) {
            BrutalButton(actionTitle, action, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
        }
    }
}
