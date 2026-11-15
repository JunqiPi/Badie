package com.badie.app.features.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import com.badie.app.BuildConfig
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.InsetDivider
import com.badie.app.design.MenuRow
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TextAction
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.AppLanguage
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 设置。现在有：外观、语言、退出登录；权限、隐私、帮助、改密码、注销还没搬过来 */
@Composable
fun SettingsView() {
    val env = LocalEnv.current
    val appState = env.appState
    val scope = rememberCoroutineScope()
    var showLanguage by remember { mutableStateOf(false) }
    var showSignOut by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("设置"), onBack = { env.router.pop() })
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            Section(tr("外观")) {
                SegmentedSticker(Appearance.entries, appState.appearance, { appState.appearance = it }) {
                    when (it) {
                        Appearance.System -> tr("跟随系统")
                        Appearance.Light -> tr("浅色")
                        Appearance.Dark -> tr("深色")
                    }
                }
            }
            // 在 App 里直接选，马上生效（不用去系统设置）
            Section(tr("语言")) {
                Box(Modifier.sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.lg)) {
                    MenuRow(Sym.globe, tr("App 语言"), tint = AppTheme.colors.sky, value = AppLanguage.chosen?.let(AppLanguage::name) ?: tr("跟随系统")) {
                        showLanguage = true
                    }
                }
            }
            Section(tr("账号")) {
                BrutalButton(tr("退出登录"), { showSignOut = true }, kind = ButtonKind.Accent(AppTheme.colors.butter), size = ButtonSize.Medium)
            }
            Text(
                tr("Badie v%@", BuildConfig.VERSION_NAME), style = AppTheme.Typography.caption, color = AppTheme.colors.inkTertiary,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    if (showLanguage) {
        SheetScaffold(onDismiss = { showLanguage = false }) {
            LanguagePicker { code ->
                showLanguage = false
                // 等弹层收起再换：界面会按新语言重建
                scope.launch {
                    delay(350)
                    AppLanguage.choose(code)
                    appState.backend.syncServerLocale()
                }
            }
        }
    }
    if (showSignOut) {
        ConfirmDialog(
            title = tr("退出登录？"), message = tr("用同一邮箱登录即可恢复你的数据。"), confirmTitle = tr("退出"),
            onDismiss = { showSignOut = false },
        ) {
            showSignOut = false
            scope.launch {
                env.router.reset()
                appState.signOut()
            }
        }
    }
}

/** 分区标题 */
@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(title, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary, modifier = Modifier.semantics { heading() })
        content()
    }
}

/** 选 App 的语言：跟随系统，或 10 种里选一种；每种语言用它自己的写法 */
@Composable
fun LanguagePicker(onChoose: (String?) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val chosen = AppLanguage.chosen
    Column(Modifier.fillMaxWidth().padding(bottom = AppTheme.Spacing.xl), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
        Text(
            tr("App 语言"), style = AppTheme.Typography.title, color = colors.ink,
            modifier = Modifier.padding(top = AppTheme.Spacing.xl).padding(horizontal = AppTheme.Spacing.screen).semantics { heading() },
        )
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
                .padding(horizontal = AppTheme.Spacing.lg),
        ) {
            val options: List<String?> = listOf<String?>(null) + AppLanguage.supported
            options.forEachIndexed { index, code ->
                if (index > 0) InsetDivider()
                val isSelected = chosen == code
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.RadioButton) {
                            haptics.selection()
                            onChoose(code)
                        }
                        .semantics { selected = isSelected }
                        .padding(vertical = AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    Text(if (code == null) tr("跟随系统") else AppLanguage.name(code), style = AppTheme.Typography.bodyBold, color = colors.ink)
                    if (code == null) {
                        Text(AppLanguage.name(AppLanguage.system), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                    }
                    Spacer(Modifier.weight(1f))
                    if (isSelected) Symbol(Sym.checkmark, size = 15, tint = colors.ink)
                }
            }
        }
    }
}

/** 要用户确认的弹窗（退出登录、注销这类） */
@Composable
fun ConfirmDialog(title: String, message: String, confirmTitle: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val colors = AppTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text(title, style = AppTheme.Typography.headline, color = colors.ink) },
        text = { Text(message, style = AppTheme.Typography.subheadline, color = colors.inkSecondary) },
        confirmButton = { TextAction(confirmTitle, onConfirm, color = colors.danger) },
        dismissButton = { TextAction(tr("取消"), onDismiss, color = colors.ink) },
    )
}
