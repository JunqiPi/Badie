package com.badie.app.features.home

import androidx.compose.runtime.Composable

// 占位：约某个人打球 / 提议换个时间（半屏弹层的内容）。发现页、球友资料、聊天里改约时间都会调它，名字和参数不要改。
// 对应 iPhone 的 Features/Home/NearbyViews.swift 里的 InviteComposeSheet
// counterRoomId 不为空时是“对这个邀请提议换个时间”（purpose: .counter(roomId:)）

@Composable
fun InviteComposeSheet(userId: String, counterRoomId: String? = null, onDismiss: () -> Unit) {}
