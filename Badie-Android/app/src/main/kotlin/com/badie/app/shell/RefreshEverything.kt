package com.badie.app.shell

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.badie.app.remote.RemoteError
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * 下拉刷新：不管在哪一页，都把该刷新的全部刷新一遍（资料、请求和球局、好友和消息、球群、开放的局、通知、附近球馆）。
 * 对应 iPhone 的 RefreshEverything。[extra] 是这一页自己还要多刷的
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefreshEverything(modifier: Modifier = Modifier, extra: (suspend () -> Unit)? = null, content: @Composable () -> Unit) {
    val env = LocalEnv.current
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                env.refreshEverything()
                extra?.invoke()
                refreshing = false
            }
        },
        modifier = modifier,
    ) { content() }
}

/** 全部重新读一遍；哪一项没读到不影响别的 */
suspend fun AppEnvironment.refreshEverything() = coroutineScope {
    val jobs = listOf<suspend () -> Unit>(
        { appState.backend.refreshProfile() },
        { locationManager.refresh() },
        { matchManager.refresh() },
        { friendManager.refresh() },
        { messageManager.refresh() },
        { roomManager.refresh() },
        { surveyManager.refresh() },
        { inboxManager.refresh() },
        { groupManager.refresh() },
    )
    jobs.map { job ->
        async {
            try {
                job()
            } catch (_: RemoteError) {
            }
        }
    }.awaitAll()
}
