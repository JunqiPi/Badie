package com.badie.app.features.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import com.badie.app.design.AppTheme
import com.badie.app.design.RulesButton
import com.badie.app.design.TextAction
import com.badie.app.l10n.tr

// 球局、房间、评价几页共用的小零件

/** 要用户确认的弹窗（取消球局、解散房间这类）：确认是红字 */
@Composable
fun ConfirmAlert(
    title: String,
    message: String?,
    confirmTitle: String,
    onDismiss: () -> Unit,
    cancelTitle: String = tr("取消"),
    onConfirm: () -> Unit,
) {
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
        dismissButton = { TextAction(cancelTitle, onDismiss, color = colors.ink) },
    )
}

/** 开关（成功色），和 iPhone 的 Toggle().tint(success) 一样 */
@Composable
fun BadieSwitch(checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Switch(
        checked, onChange, modifier,
        colors = SwitchDefaults.colors(
            checkedTrackColor = colors.success, checkedThumbColor = colors.surface, checkedBorderColor = colors.stroke,
            uncheckedTrackColor = colors.surfaceMuted, uncheckedThumbColor = colors.surface, uncheckedBorderColor = colors.stroke,
        ),
    )
}

/** 一排放不下会换行（iPhone 的 FlowLayout） */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun Flow(modifier: Modifier = Modifier, spacing: Dp = AppTheme.Spacing.sm, content: @Composable FlowRowScope.() -> Unit) {
    FlowRow(
        modifier, horizontalArrangement = Arrangement.spacedBy(spacing), verticalArrangement = Arrangement.spacedBy(spacing),
        itemVerticalAlignment = Alignment.CenterVertically, content = content,
    )
}

/** 分组：标题（可带“?”）+ 内容 */
@Composable
fun FormGroup(title: String, modifier: Modifier = Modifier, rules: List<String>? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink,
                modifier = Modifier.weight(1f, fill = false).semantics { heading() },
            )
            if (rules != null) RulesButton(title, rules, Modifier.padding(start = AppTheme.Spacing.xxs))
            Spacer(Modifier.weight(0.001f))
        }
        content()
    }
}
