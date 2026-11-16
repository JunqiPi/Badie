package com.badie.app.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.badie.app.l10n.tr
import com.badie.app.models.Gender
import com.badie.app.models.User

// MARK: - 头像

/** 圆头像：照片，或者色块上的一个字 / 表情 */
@Composable
fun AvatarView(
    text: String,
    modifier: Modifier = Modifier,
    paletteIndex: Int = 0,
    size: Dp = 44.dp,
    image: ImageBitmap? = null,
    showsBorder: Boolean = true,
) {
    val colors = AppTheme.colors
    val fill = colors.paletteColor(paletteIndex)
    Box(
        modifier
            .size(size)
            .drawWithContent {
                drawCircle(fill)
                drawContent()
                if (showsBorder) {
                    val width = (if (size >= 56.dp) 2.5.dp else 2.dp).toPx()
                    drawCircle(colors.stroke, radius = this.size.minDimension / 2 - width / 2, style = Stroke(width))
                }
            }
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        if (image != null) {
            Image(image, contentDescription = null, modifier = Modifier.fillMaxSize().clip(CircleShape), contentScale = ContentScale.Crop)
        } else {
            FitText(text, Modifier.padding(size * 0.12f), style = rounded((size.value * 0.42f).toInt(), FontWeight.ExtraBold), color = colors.onAccent)
        }
    }
}

/** 某个用户的头像：有上传的照片就显示照片（没下载好之前先显示文字头像） */
@Composable
fun AvatarView(user: User, modifier: Modifier = Modifier, size: Dp = 44.dp) {
    AvatarView(user.id, user.avatarText, user.avatar.paletteIndex, modifier, size)
}

@Composable
fun AvatarView(userId: String, text: String, paletteIndex: Int, modifier: Modifier = Modifier, size: Dp = 44.dp) {
    val photos = LocalPhotos.current
    AvatarView(text, modifier, paletteIndex = paletteIndex, size = size, image = photos?.avatar(userId))
}

/** 照片从哪取：App 里由 MainActivity 提供；截图测试里没有（只显示文字头像） */
val LocalPhotos = androidx.compose.runtime.staticCompositionLocalOf<com.badie.app.backend.PhotoStore?> { null }

// MARK: - 标签胶囊（新球友、已认证等）

@Composable
fun TagPill(
    text: String,
    modifier: Modifier = Modifier,
    icon: SymbolId? = null,
    fill: Color = AppTheme.colors.surface,
    foreground: Color? = null,
) {
    val colors = AppTheme.colors
    val ink = foreground ?: colors.onAccent
    Row(
        modifier
            .sticker(fill, radius = 12.dp, shadow = AppTheme.Elevation.none, strokeWidth = 1.5.dp)
            .padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) Symbol(icon, size = 10, tint = ink)
        Text(text, style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Bold), color = ink, maxLines = 1)
    }
}

// MARK: - 选择胶囊

@Composable
fun ChoiceChip(
    title: String,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    icon: SymbolId? = null,
    tint: Color = AppTheme.colors.lime,
    onClick: () -> Unit,
) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val foreground = if (isSelected) colors.onAccent else colors.ink
    Row(
        modifier
            .pressable {
                haptics.selection()
                onClick()
            }
            .semantics { selected = isSelected }
            .defaultMinSize(minHeight = 38.dp)
            .sticker(if (isSelected) tint else colors.surface, radius = 19.dp, shadow = AppTheme.Elevation.none)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) Symbol(icon, size = 12, tint = foreground)
        Text(title, style = AppTheme.Typography.footnoteBold, color = foreground, maxLines = 1)
    }
}

/** 贴纸式的分段选择 */
@Composable
fun <Option> SegmentedSticker(
    options: List<Option>,
    selection: Option?,
    onSelect: (Option) -> Unit,
    modifier: Modifier = Modifier,
    badge: (Option) -> Int = { 0 },
    title: @Composable (Option) -> String,
) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(
        modifier.fillMaxWidth().sticker(colors.surface, radius = 16.dp, shadow = AppTheme.Elevation.none).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (option in options) {
            val isSelected = option == selection
            val fill = if (isSelected) colors.inverse else Color.Transparent
            Row(
                Modifier
                    .weight(1f)
                    .defaultMinSize(minHeight = 40.dp)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                    .drawBehind { drawRect(fill) }
                    .pressable(scale = 1f, role = Role.Tab) {
                        haptics.selection()
                        onSelect(option)
                    }
                    .semantics { selected = isSelected },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            ) {
                Text(title(option), style = AppTheme.Typography.subheadlineBold, color = if (isSelected) colors.onInverse else colors.inkSecondary, maxLines = 1)
                if (badge(option) > 0) CountBadge(badge(option))
            }
        }
    }
}

/** 定级用的性别：男 / 女，旁边的“?”里有说明（男女等级分开算，只用来定级和匹配，不代表性别认同） */
@Composable
fun GenderPicker(selection: Gender, onSelect: (Gender) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("定级用的性别"), style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
            RulesButton(
                tr("定级用的性别"),
                listOf(tr("羽毛球男女的等级分开算，这里只用来给你定级和公平匹配，不代表你的性别认同，随时可以在设置里改。")),
            )
        }
        SegmentedSticker(Gender.choices, selection.takeIf { it != Gender.Unspecified }, onSelect) { it.label }
    }
}
