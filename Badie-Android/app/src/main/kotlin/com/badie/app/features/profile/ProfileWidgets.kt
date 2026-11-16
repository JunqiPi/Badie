package com.badie.app.features.profile

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.IconButton
import com.badie.app.design.RulesButton
import com.badie.app.design.Sym
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv

// “我的”这一块共用的小部件

/** 这一块的接口和本机设置（一个后端一份） */
@Composable
fun rememberProfileApi(): ProfileApi {
    val backend = LocalEnv.current.appState.backend
    val context = LocalContext.current.applicationContext
    return remember(backend) { ProfileApi.of(backend, context) }
}

/** 半屏弹层的抬头：大标题，可带“?”，右边关闭 */
@Composable
fun SheetHeader(title: String, onClose: (() -> Unit)?, modifier: Modifier = Modifier, rulesTitle: String? = null, rules: List<String> = emptyList()) {
    Row(modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        if (rules.isNotEmpty()) RulesButton(rulesTitle ?: title, rules)
        Spacer(Modifier.weight(1f))
        if (onClose != null) IconButton(Sym.xmark, tr("关闭"), onClick = onClose)
    }
}

/** 分区的小标题（灰色）；有规则说明时旁边放一个“?” */
@Composable
fun SectionLabel(title: String, rules: List<String> = emptyList(), content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary, modifier = Modifier.semantics { heading() })
            if (rules.isNotEmpty()) RulesButton(title, rules)
        }
        content()
    }
}

/** 开关一行：只有一行字，说明在分区的“?”里 */
@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Text(title, style = AppTheme.Typography.bodyBold, color = AppTheme.colors.ink, modifier = Modifier.weight(1f))
        BadieSwitch(checked, onChange, Modifier.semantics { contentDescription = title })
    }
}

/** 系统开关，打开是绿色（和 iPhone 的 tint 一样） */
@Composable
fun BadieSwitch(checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Switch(
        checked, onChange, modifier,
        colors = SwitchDefaults.colors(
            checkedTrackColor = colors.success, checkedThumbColor = Color.White, checkedBorderColor = colors.success,
            uncheckedTrackColor = colors.surfaceMuted, uncheckedThumbColor = Color.White, uncheckedBorderColor = colors.stroke.copy(alpha = 0.3f),
        ),
    )
}

/** 多行的输入框：标题、字数，贴纸底（一句话介绍、反馈、补充说明） */
@Composable
fun MultilineField(label: String, placeholder: String, value: String, onValueChange: (String) -> Unit, characterLimit: Int, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            val count = value.codePointCount(0, value.length)
            Text(
                "$count/$characterLimit", style = AppTheme.Typography.caption.copy(fontFeatureSettings = "tnum"),
                color = if (count > characterLimit) colors.danger else colors.inkTertiary,
            )
        }
        BasicTextField(
            value = value,
            onValueChange = { text -> onValueChange(limited(text, characterLimit)) },
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 52.dp)
                .sticker(colors.surface, radius = 14.dp, shadow = if (focused) AppTheme.Elevation.low else AppTheme.Elevation.none)
                .padding(horizontal = AppTheme.Spacing.lg, vertical = 14.dp)
                .semantics { contentDescription = label },
            textStyle = AppTheme.Typography.body.copy(color = colors.ink),
            interactionSource = interaction,
            cursorBrush = SolidColor(colors.ink),
            decorationBox = { field ->
                Box {
                    if (value.isEmpty()) Text(placeholder, style = AppTheme.Typography.body, color = colors.inkTertiary)
                    field()
                }
            },
        )
    }
}

/** 超过字数的部分截掉（表情算一个字） */
fun limited(text: String, limit: Int): String =
    if (text.codePointCount(0, text.length) <= limit) text else text.substring(0, text.offsetByCodePoints(0, limit))

/** 灰色的小字段名 */
@Composable
fun FieldLabel(text: String) {
    Text(text, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
}

/** 用浏览器、邮件之类的 App 打开；打不开返回 false */
fun Context.openLink(url: String): Boolean = try {
    startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
} catch (_: ActivityNotFoundException) {
    false
}

/** 留出和 iPhone 的 Spacer(minLength:) 一样的空 */
@Composable
fun HSpace(width: androidx.compose.ui.unit.Dp) = Spacer(Modifier.width(width))
