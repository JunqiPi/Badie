package com.badie.app.features.social

import androidx.compose.runtime.Composable

// 占位：球友资料弹层、爽约说明弹层、重要通知弹层。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接）。
// 对应的 iPhone 源文件：Features/Social/PlayerProfileSheet.swift、StrikesSheet.swift、Features/Messages（UrgentNoticeSheet）

/** 球友资料（半屏弹层的内容） */
@Composable
fun PlayerProfileSheet(userId: String, onDismiss: () -> Unit) {}

/** 新记了一次爽约：说明会怎样、可以申诉 */
@Composable
fun StrikesSheet(onDismiss: () -> Unit) {}
