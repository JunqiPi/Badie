package com.badie.app.features.games

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.ScreenHeader
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv

// 占位：这一块还没搬。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面），里面随便改。
// 对应的 iPhone 源文件：Features/Games/*.swift, Features/Surveys/*.swift

@Composable
fun GamesScreen() {
    Column(Modifier.fillMaxSize()) {
        LargeTitleHeader(tr("球局"))
    }
}

@Composable
fun GameDetailScreen(id: String) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

@Composable
fun GameHistoryScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("历史球局"), onBack = { router.pop() })
    }
}

@Composable
fun SurveyListScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("待评价"), onBack = { router.pop() })
    }
}

@Composable
fun SurveyFormScreen(pendingId: String) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

