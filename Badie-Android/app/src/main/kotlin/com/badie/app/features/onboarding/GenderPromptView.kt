package com.badie.app.features.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.GenderPicker
import com.badie.app.l10n.tr
import com.badie.app.models.Gender
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.launch

/** 以前注册、还没选性别的人：打开 App 先补上（男女的等级分开算）。不能关 */
@Composable
fun GenderPromptView() {
    val appState = LocalEnv.current.appState
    val scope = rememberCoroutineScope()
    var gender by remember { mutableStateOf(Gender.Unspecified) }
    var isSaving by remember { mutableStateOf(false) }
    BackHandler {}
    Column(
        Modifier.fillMaxSize().background(AppTheme.colors.canvas).windowInsetsPadding(WindowInsets.safeDrawing).padding(AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg, Alignment.CenterVertically),
    ) {
        Text(tr("还有一件事"), style = AppTheme.Typography.subheadlineBold, color = AppTheme.colors.inkSecondary)
        Text(tr("按男子还是女子等级？"), style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
        GenderPicker(gender, { gender = it })
        BrutalButton(
            tr("继续"),
            onClick = {
                scope.launch {
                    isSaving = true
                    try {
                        appState.backend.updateGender(gender)
                    } catch (error: RemoteError) {
                        appState.showError(error)
                    }
                    isSaving = false
                }
            },
            enabled = gender != Gender.Unspecified && !isSaving,
        )
    }
}
