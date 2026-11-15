package com.badie.app.design

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.badie.app.l10n.tr

// MARK: - 输入框

/** 一行的输入框：贴纸底，聚焦时出投影，出错时描红边。登录页的邮箱、密码用它 */
@Composable
fun StickerTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    style: TextStyle = rounded(20, FontWeight.Bold),
    invalid: Boolean = false,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    contentType: ContentType? = null,
    focusRequester: FocusRequester? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val colors = AppTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .sticker(
                colors.surface, radius = 14.dp, shadow = if (focused) AppTheme.Elevation.low else AppTheme.Elevation.none,
                stroke = if (invalid) colors.danger else colors.stroke,
            )
            .padding(start = AppTheme.Spacing.lg, end = if (trailing == null) AppTheme.Spacing.lg else AppTheme.Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .weight(1f)
                .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
                .semantics {
                    contentDescription = placeholder
                    if (contentType != null) this.contentType = contentType
                },
            textStyle = style.copy(color = colors.ink),
            singleLine = true,
            keyboardOptions = keyboardOptions,
            keyboardActions = keyboardActions,
            visualTransformation = visualTransformation,
            interactionSource = interaction,
            cursorBrush = SolidColor(colors.ink),
            decorationBox = { field ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) Text(placeholder, style = style, color = colors.inkTertiary, maxLines = 1)
                    field()
                }
            },
        )
        trailing?.invoke()
    }
}

/** 密码输入框：右边的眼睛显示 / 隐藏。告诉系统这是密码，密码管理器才会自动填；注册时还会建议一个强密码 */
@Composable
fun PasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = tr("密码"),
    /** 注册、重设、修改时是新密码 */
    isNew: Boolean = false,
    invalid: Boolean = false,
    onSubmit: () -> Unit = {},
) {
    var shown by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val label = if (shown) tr("隐藏密码") else tr("显示密码")
    StickerTextField(
        value, onValueChange, placeholder, modifier,
        invalid = invalid,
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
            keyboardType = KeyboardType.Password, imeAction = ImeAction.Go,
        ),
        keyboardActions = KeyboardActions(onGo = { onSubmit() }),
        visualTransformation = if (shown) VisualTransformation.None else PasswordVisualTransformation(),
        contentType = if (isNew) ContentType.NewPassword else ContentType.Password,
        focusRequester = focus,
        trailing = {
            Box(
                Modifier
                    .size(44.dp)
                    .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
                        shown = !shown
                        focus.requestFocus()
                    }
                    .semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) {
                Symbol(if (shown) Sym.eyeSlashFill else Sym.eyeFill, size = 17, tint = AppTheme.colors.inkSecondary)
            }
        },
    )
}

/** 带标签的输入框（昵称、备注等）：上面是标签和字数，下面可以显示出错的原因 */
@Composable
fun BrutalTextField(
    label: String,
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    errorText: String? = null,
    characterLimit: Int? = null,
) {
    val colors = AppTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            if (characterLimit != null) {
                val count = value.codePointCount(0, value.length)
                Text(
                    "$count/$characterLimit", style = AppTheme.Typography.caption.copy(fontFeatureSettings = "tnum"),
                    color = if (count > characterLimit) colors.danger else colors.inkTertiary,
                )
            }
        }
        StickerTextField(
            value, onValueChange, placeholder, style = AppTheme.Typography.body, invalid = errorText != null, keyboardOptions = keyboardOptions,
        )
        if (errorText != null) {
            Text(errorText, style = AppTheme.Typography.caption, color = colors.danger)
        }
    }
}

/** 6 位验证码：六个格子，轮到的那一格是柠檬色。只收数字 */
@Composable
fun CodeField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, focusRequester: FocusRequester? = null) {
    val colors = AppTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val label = tr("验证码")
    BasicTextField(
        value = value,
        onValueChange = { text -> onValueChange(text.filter { it in '0'..'9' }.take(6)) },
        modifier = modifier
            .fillMaxWidth()
            .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
            .semantics { contentDescription = label; contentType = ContentType.SmsOtpCode },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
        interactionSource = interaction,
        cursorBrush = SolidColor(androidx.compose.ui.graphics.Color.Transparent),
        textStyle = TextStyle(color = androidx.compose.ui.graphics.Color.Transparent),
        decorationBox = {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                repeat(6) { index ->
                    val filled = index < value.length
                    Box(
                        Modifier
                            .weight(1f)
                            .defaultMinSize(minHeight = 58.dp)
                            .sticker(
                                if (index == value.length && focused) colors.lime else colors.surface,
                                radius = 14.dp, shadow = if (filled) AppTheme.Elevation.low else AppTheme.Elevation.none,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(if (filled) value[index].toString() else "", style = rounded(28, FontWeight.Black), color = colors.ink)
                    }
                }
            }
        },
    )
}
