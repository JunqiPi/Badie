package com.badie.app.shell

import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.staticCompositionLocalOf
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import com.badie.app.backend.Backend
import com.badie.app.features.games.SurveyManager
import com.badie.app.features.groups.GroupManager
import com.badie.app.features.matching.MatchManager
import com.badie.app.features.messages.InboxManager
import com.badie.app.features.messages.MessageManager
import com.badie.app.features.rooms.RoomManager
import com.badie.app.features.social.FriendManager
import com.badie.app.features.venues.LocationManager
import com.badie.app.design.Appearance
import com.badie.app.design.Toast
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.User
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Stable
class AppState(
    private val scope: CoroutineScope,
    val backend: Backend,
    /** 上次选的外观 */
    savedAppearance: String? = null,
    private val saveAppearance: (String) -> Unit = {},
) {
    enum class Phase { Launching, Onboarding, Main }

    var phase by mutableStateOf(Phase.Launching)
        private set

    var toast by mutableStateOf<Toast?>(null)

    /** 外观（跟随系统、浅色、深色）；改了就记到本机 */
    /** 正在看的球友资料（弹层） */
    var presentedPlayer by mutableStateOf<String?>(null)

    /** 新记了一次爽约，弹说明 */
    var showsStrikes by mutableStateOf(false)

    fun showPlayer(userId: String) {
        presentedPlayer = userId
    }

    var appearance: Appearance
        get() = appearanceState
        set(value) {
            appearanceState = value
            saveAppearance(value.name)
        }
    private var appearanceState by mutableStateOf(Appearance.entries.firstOrNull { it.name == savedAppearance } ?: Appearance.System)

    val currentUser: User? get() = backend.currentUser

    private var toastJob: Job? = null

    init {
        // 登录失效（换不到新的令牌）：清掉本机的登录状态，退回登录页
        backend.remote.onSessionExpired = {
            backend.signOutLocally()
            syncPhase()
        }
    }

    /** 打开 App：先用缓存里的用户进主界面，后台再核对登录状态 */
    fun start() {
        scope.launch {
            backend.restoreSession()
            syncPhase()
        }
    }

    /** 启动页放完：有用户进主界面，没有进登录 */
    fun finishLaunch() {
        if (phase == Phase.Launching) phase = if (currentUser != null) Phase.Main else Phase.Onboarding
    }

    /** 登录、注册、退出以后：按有没有用户换页面（启动页还没放完就先不动） */
    fun syncPhase() {
        if (phase != Phase.Launching) phase = if (currentUser != null) Phase.Main else Phase.Onboarding
    }

    suspend fun signOut() {
        backend.signOut()
        syncPhase()
    }

    /** 顶部的提示条，2.6 秒后自己消失 */
    fun showToast(message: String, style: Toast.Style = Toast.Style.Info) {
        toastJob?.cancel()
        val shown = Toast(message, style)
        toast = shown
        toastJob = scope.launch {
            delay(TOAST_MILLIS)
            if (toast?.id == shown.id) toast = null
        }
    }

    fun showError(error: Throwable) {
        showToast(error.message?.takeIf { it.isNotEmpty() } ?: tr("出了点问题，请重试。"), Toast.Style.Error)
    }

    companion object {
        const val TOAST_MILLIS = 2600L
    }
}

/** 管理器都拿这些：在哪跑协程、后端、全局状态、Android 的 Context（单元测试里为空） */
class ManagerContext(val scope: CoroutineScope, val backend: Backend, val appState: AppState, val android: Context?)

/** 整个 App 共用的状态和管理器，对应 iPhone 的 AppEnvironment */
class AppEnvironment(
    scope: CoroutineScope,
    backend: Backend,
    savedAppearance: String? = null,
    saveAppearance: (String) -> Unit = {},
    android: Context? = null,
) {
    val appState = AppState(scope, backend, savedAppearance, saveAppearance)
    val router = Router()
    private val context = ManagerContext(scope, backend, appState, android)
    val locationManager = LocationManager(context)
    val matchManager = MatchManager(context, locationManager)
    val friendManager = FriendManager(context)
    val messageManager = MessageManager(context)
    val roomManager = RoomManager(context, location = locationManager)
    val surveyManager = SurveyManager(context)
    val inboxManager = InboxManager(context)
    val groupManager = GroupManager(context, locationManager)
    /** 收款：价格、你还没付、收款记录（见 features/groups/PaymentScreens.kt） */
    val payments = com.badie.app.backend.PaymentsApi(backend.remote)
    /** 从网站下载安装的正式包：有新版本时提示（见 SideloadUpdates） */
    val updates = SideloadUpdates.forApp(android)
}

val LocalEnv = staticCompositionLocalOf<AppEnvironment> { error("没有提供 AppEnvironment") }
