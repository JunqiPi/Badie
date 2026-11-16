package com.badie.app.features.profile

import androidx.compose.runtime.Composable

// 占位：等级卡片（看、翻面、分享、存到相册），半屏弹层的内容。“我的”、定级结果、球友资料都会调它，名字和参数不要改。
// 对应 iPhone 的 Features/LevelCard/LevelCardViews.swift 里的 LevelCardSheet
// userId 为空 = 自己的卡片

@Composable
fun LevelCardSheet(userId: String? = null, onDismiss: () -> Unit) {}
