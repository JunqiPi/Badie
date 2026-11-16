package com.badie.app.features.venues

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.ScreenHeader
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv

// 占位：这一块还没搬。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面），里面随便改。
// 对应的 iPhone 源文件：Features/Venues/*.swift, Features/Courts/CourtsView.swift

@Composable
fun CourtsScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("球馆"), onBack = { router.pop() })
    }
}

@Composable
fun VenueScreen(id: String) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

@Composable
fun MatchVenuesScreen(query: String?) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("选择球馆"), onBack = { router.pop() })
    }
}

@Composable
fun AddVenueScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("添加球馆"), onBack = { router.pop() })
    }
}

