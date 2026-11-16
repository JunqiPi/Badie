package com.badie.app.features.social

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.LevelBadge
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TextAction
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.User

// 球友、私信、球群几页共用的小组件（iPhone 分散在 JoinRoomView 的 SearchField、MessagesView 的 PlayerRow 这些地方）

/** 搜索框：放大镜 + 输入 + 清除。对应 iPhone 的 SearchField */
@Composable
fun SearchField(text: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Row(
        modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).sticker(colors.surface, radius = 14.dp, shadow = AppTheme.Elevation.none)
            .padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(Sym.magnifyingglass, size = 16, tint = colors.inkSecondary)
        BasicTextField(
            value = text, onValueChange = onChange, singleLine = true,
            modifier = Modifier.weight(1f).semantics { contentDescription = placeholder },
            textStyle = AppTheme.Typography.body.copy(color = colors.ink),
            cursorBrush = SolidColor(colors.ink),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
            decorationBox = { field ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) Text(placeholder, style = AppTheme.Typography.body, color = colors.inkTertiary, maxLines = 1)
                    field()
                }
            },
        )
        if (text.isNotEmpty()) {
            val label = tr("清除搜索")
            Box(
                Modifier.size(44.dp).clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { onChange("") }
                    .semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) { Symbol(Sym.xmarkCircleFill, size = 17, tint = colors.inkTertiary) }
        } else {
            Spacer(Modifier.width(AppTheme.Spacing.sm))
        }
    }
}

/** 多行输入框（贴纸外框），可选标题和字数。对应 iPhone 的 BrutalTextField(axis: .vertical) / TextField(axis: .vertical) */
@Composable
fun MultilineField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    label: String? = null,
    characterLimit: Int? = null,
    minLines: Int = 1,
    maxLines: Int = 5,
    radius: Dp = 14.dp,
    invalid: Boolean = false,
) {
    val colors = AppTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        if (label != null || characterLimit != null) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(label ?: "", style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                if (characterLimit != null) {
                    val count = value.codePointCount(0, value.length)
                    Text(
                        "$count/$characterLimit", style = AppTheme.Typography.caption.copy(fontFeatureSettings = "tnum"),
                        color = if (count > characterLimit) colors.danger else colors.inkTertiary,
                    )
                }
            }
        }
        BasicTextField(
            value = value, onValueChange = onChange, minLines = minLines, maxLines = maxLines,
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp)
                .sticker(
                    colors.surface, radius = radius, shadow = if (focused) AppTheme.Elevation.low else AppTheme.Elevation.none,
                    stroke = if (invalid) colors.danger else colors.stroke,
                )
                .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md)
                .semantics { contentDescription = label ?: placeholder },
            textStyle = AppTheme.Typography.body.copy(color = colors.ink),
            cursorBrush = SolidColor(colors.ink),
            interactionSource = interaction,
            decorationBox = { field ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) Text(placeholder, style = AppTheme.Typography.body, color = colors.inkTertiary)
                    field()
                }
            },
        )
    }
}

/** 开关行：粗体标题 + 开关（iPhone 的 Toggle，绿色） */
@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, extra: @Composable RowScope.() -> Unit = {}) {
    val colors = AppTheme.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        Text(title, style = AppTheme.Typography.bodyBold, color = colors.ink)
        extra()
        Spacer(Modifier.weight(1f))
        Switch(
            checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = colors.success, checkedThumbColor = Color.White, checkedBorderColor = colors.success),
            modifier = Modifier.semantics { contentDescription = title },
        )
    }
}

/** 要用户确认的弹窗（删除、退出、解散这类）：确认按钮是红色 */
@Composable
fun ConfirmDialog(title: String, message: String?, confirmTitle: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val colors = AppTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text(title, style = AppTheme.Typography.headline, color = colors.ink) },
        text = message?.let { { Text(it, style = AppTheme.Typography.subheadline, color = colors.inkSecondary) } },
        confirmButton = {
            TextAction(confirmTitle, {
                onDismiss()
                onConfirm()
            }, color = colors.danger)
        },
        dismissButton = { TextAction(tr("取消"), onDismiss, color = colors.ink) },
    )
}

/** 一行球友：头像、昵称、等级，下面一行说明；右边放按钮。对应 iPhone MessagesView.swift 的 PlayerRow */
@Composable
fun PlayerRow(user: User, subtitle: String? = null, onClick: () -> Unit, trailing: @Composable RowScope.() -> Unit = {}) {
    val colors = AppTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(vertical = AppTheme.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(
            Modifier.weight(1f).clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            AvatarView(user, size = 44.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        user.nickname, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    LevelBadge(user.displayTier, showsName = false, compact = true)
                }
                Text(
                    subtitle ?: "${user.displayLevelText} · ${user.publicSummary}", style = AppTheme.Typography.footnote, color = colors.inkSecondary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        }
        trailing()
    }
}

/** 系统分享（iPhone 的 ShareLink） */
fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** 复制到剪贴板 */
fun copyText(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText("Badie", text))
}
