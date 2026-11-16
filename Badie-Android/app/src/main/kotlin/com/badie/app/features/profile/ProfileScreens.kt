package com.badie.app.features.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.ScreenHeader
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv

// 占位：这一块还没搬。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面），里面随便改。
// 对应的 iPhone 源文件：Features/Profile/*.swift, Features/LevelCard/*.swift, Features/Support/*.swift

@Composable
fun ProfileScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        LargeTitleHeader(tr("我的")) {
            com.badie.app.design.IconButton(com.badie.app.design.Sym.gearshapeFill, tr("设置")) { router.open(com.badie.app.shell.Route.Settings) }
        }
    }
}

@Composable
fun EditProfileScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("编辑资料"), onBack = { router.pop() })
    }
}

@Composable
fun RecurringSlotsScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("常用时间"), onBack = { router.pop() })
    }
}

@Composable
fun LevelGuideScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

@Composable
fun VerificationScreen() {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
    }
}

