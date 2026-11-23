package com.badie.app.features.night

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StickerTextField
import com.badie.app.design.TextAction
import com.badie.app.design.pressable
import com.badie.app.design.sticker
import com.badie.app.l10n.tr

// 选一项的半屏（iPhone 的 confirmationDialog）、输一行字的弹窗（iPhone 的 alert 加 TextField）

/** 半屏里的一个选项；destructive 是红字 */
data class ChoiceOption(val title: String, val destructive: Boolean = false, val action: () -> Unit)

@Composable
fun ChoiceSheet(title: String, options: List<ChoiceOption>, onDismiss: () -> Unit, message: String? = null) {
    val colors = AppTheme.colors
    SheetScaffold(onDismiss = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            Text(title, style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.md).semantics { heading() })
            message?.let { Text(it, style = AppTheme.Typography.subheadline, color = colors.inkSecondary) }
            Spacer(Modifier.size(AppTheme.Spacing.xs))
            options.forEach { option ->
                Box(
                    Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp)
                        .pressable(scale = 0.98f) {
                            onDismiss()
                            option.action()
                        }
                        .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
                        .padding(horizontal = AppTheme.Spacing.lg),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(
                        option.title, style = AppTheme.Typography.headline, color = if (option.destructive) colors.danger else colors.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
fun TextInputDialog(
    title: String,
    confirmTitle: String,
    onDismiss: () -> Unit,
    message: String? = null,
    placeholder: String = "",
    initial: String = "",
    keyboard: KeyboardType = KeyboardType.Text,
    onConfirm: (String) -> Unit,
) {
    val colors = AppTheme.colors
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text(title, style = AppTheme.Typography.headline, color = colors.ink) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                message?.let { Text(it, style = AppTheme.Typography.subheadline, color = colors.inkSecondary) }
                StickerTextField(text, { text = it }, placeholder, style = AppTheme.Typography.body, keyboardOptions = KeyboardOptions(keyboardType = keyboard))
            }
        },
        confirmButton = {
            TextAction(confirmTitle, {
                onDismiss()
                onConfirm(text)
            }, color = colors.ink)
        },
        dismissButton = { TextAction(tr("取消"), onDismiss, color = colors.inkSecondary) },
    )
}
