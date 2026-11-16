package com.badie.app.features.matching

import androidx.compose.runtime.Composable

// 占位：快速匹配的设置弹层和匹配流程全屏页。入口的名字不要改（shell/MainTabView.kt 按这些名字接）。
// 对应的 iPhone 源文件：Features/Matching/*.swift

/** 匹配设置（半屏弹层的内容），关掉时调 onDismiss */
@Composable
fun MatchSetupSheet(onDismiss: () -> Unit) {}

/** 匹配流程（全屏）；MatchManager 说要显示时才显示 */
@Composable
fun MatchFlowOverlay() {}
