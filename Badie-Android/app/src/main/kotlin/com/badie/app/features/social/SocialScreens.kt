package com.badie.app.features.social

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.ScreenHeader
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv

// 占位：这一块还没搬。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面），里面随便改。
// 对应的 iPhone 源文件：Features/Social/*.swift

@Composable
fun FriendsScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("球友"), onBack = { router.pop() })
    }
}

@Composable
fun AddFriendScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("加球友"), onBack = { router.pop() })
    }
}

@Composable
fun BlockedUsersScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("屏蔽名单"), onBack = { router.pop() })
    }
}

