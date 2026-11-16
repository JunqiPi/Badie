package com.badie.app.features.rooms

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.ScreenHeader
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv

// 占位：这一块还没搬。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面），里面随便改。
// 对应的 iPhone 源文件：Features/Rooms/*.swift

@Composable
fun RoomScreen(id: String) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

@Composable
fun CreateRoomScreen(mode: String?, invitee: String?) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("发起球局"), onBack = { router.pop() })
    }
}

@Composable
fun JoinRoomScreen(code: String?) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("输入房间码 / 群号"), onBack = { router.pop() })
    }
}

@Composable
fun PublicGamesScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

