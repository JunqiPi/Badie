package com.badie.app.design

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/** 触感反馈：轻点、重击、选择、成功、出错，用法和 iPhone 一样 */
class Haptics(private val view: View) {
    fun tap() = perform(HapticFeedbackConstants.VIRTUAL_KEY)

    fun impact() = perform(HapticFeedbackConstants.LONG_PRESS)

    fun selection() = perform(HapticFeedbackConstants.CLOCK_TICK)

    fun success() = perform(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)

    fun error() = perform(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)

    private fun perform(constant: Int) {
        view.performHapticFeedback(constant)
    }
}

@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    return remember(view) { Haptics(view) }
}
