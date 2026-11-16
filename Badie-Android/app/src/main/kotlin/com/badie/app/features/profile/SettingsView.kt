package com.badie.app.features.profile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.badie.app.BuildConfig
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.GenderPicker
import com.badie.app.design.InsetDivider
import com.badie.app.design.LegalLinksRow
import com.badie.app.design.MenuRow
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.AppLanguage
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.location.LocationProvider
import com.badie.app.models.ChallengePolicy
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.Gender
import com.badie.app.models.PrivacySettings
import com.badie.app.models.TimeSlotConstants
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 设置（“我的”右上角的齿轮）。对应 iPhone 的 Features/Profile/SettingsView.swift */
@Composable
fun SettingsView() {
    val env = LocalEnv.current
    val appState = env.appState
    val api = rememberProfileApi()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showLanguage by remember { mutableStateOf(false) }
    var showSignOut by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var showPassword by remember { mutableStateOf(false) }
    var showHelp by remember { mutableStateOf(false) }
    var showTips by remember { mutableStateOf(false) }
    var showRadius by remember { mutableStateOf(false) }
    var confirmHideRegular by remember { mutableStateOf(false) }
    val showsSupport = remember { TipJar.isAvailable(context) }
    // 从系统设置回来时重新读权限
    var resumed by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { resumed++ }
    val permissions = remember(resumed) { PermissionState.read(context, api) }

    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { resumed++ }
    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { resumed++ }

    val user = appState.currentUser
    fun updatePrivacy(change: (PrivacySettings) -> PrivacySettings) {
        val privacy = appState.currentUser?.privacy ?: return
        scope.launch {
            try {
                api.updatePrivacy(change(privacy))
            } catch (error: RemoteError) {
                appState.showError(error)
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("设置"), onBack = { env.router.pop() })
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            SectionLabel(tr("外观")) {
                SegmentedSticker(Appearance.entries, appState.appearance, { appState.appearance = it }) {
                    when (it) {
                        Appearance.System -> tr("跟随系统")
                        Appearance.Light -> tr("浅色")
                        Appearance.Dark -> tr("深色")
                    }
                }
            }
            // 在 App 里直接选，马上生效（不用去系统设置）
            SectionLabel(tr("语言")) {
                MenuCard(shadow = false) {
                    MenuRow(Sym.globe, tr("App 语言"), tint = AppTheme.colors.sky, value = AppLanguage.chosen?.let(AppLanguage::name) ?: tr("跟随系统")) {
                        showLanguage = true
                    }
                }
            }
            SectionLabel(tr("权限")) {
                MenuCard(shadow = false) {
                    MenuRow(Sym.bellBadgeFill, tr("球局提醒"), tint = AppTheme.colors.butter, value = permissions.notificationText) {
                        if (permissions.notifications == PermissionState.Status.NotDetermined && Build.VERSION.SDK_INT >= 33) {
                            api.markAsked(Manifest.permission.POST_NOTIFICATIONS)
                            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            context.openNotificationSettings()
                        }
                    }
                    InsetDivider()
                    MenuRow(Sym.locationFill, tr("定位"), tint = AppTheme.colors.sky, value = permissions.locationText) {
                        if (permissions.location == PermissionState.Status.NotDetermined) {
                            api.markAsked(Manifest.permission.ACCESS_COARSE_LOCATION)
                            locationLauncher.launch(LocationProvider.PERMISSIONS)
                        } else {
                            context.openAppSettings()
                        }
                    }
                    InsetDivider()
                    MenuRow(Sym.mapFill, tr("附近范围"), tint = AppTheme.colors.mint, value = DistanceFormatter.radius(LocalEnv.current.locationManager.preferences.travelRadiusKm)) {
                        showRadius = true
                    }
                }
            }
            // 定级用的性别（男女等级分开算）
            SectionLabel(tr("等级")) {
                Box(Modifier.card(AppTheme.colors.surface, shadow = AppTheme.Elevation.none)) {
                    GenderPicker(user?.gender ?: Gender.Unspecified, { gender ->
                        scope.launch {
                            try {
                                api.updateGender(gender)
                                appState.showToast(L10n.tr("资料已保存"), Toast.Style.Success)
                            } catch (error: RemoteError) {
                                appState.showError(error)
                            }
                        }
                    })
                }
            }
            // 主要靠推送；邮件是给想要的人自己打开的
            SectionLabel(tr("邮件"), rules = listOf(tr("匹配、确认和取消的消息也会发到你的登录邮箱"))) {
                Box(Modifier.card(AppTheme.colors.surface, shadow = AppTheme.Elevation.none)) {
                    ToggleRow(tr("约球消息也发邮件"), user?.privacy?.emailAlerts ?: false, { on -> updatePrivacy { it.copy(emailAlerts = on) } })
                }
            }
            SectionLabel(tr("约球偏好")) {
                MenuCard(shadow = false) {
                    MenuRow(
                        Sym.calendarBadgeClock, tr("常用时间"), tint = AppTheme.colors.peach,
                        value = "${api.recurringSlots().size}/${TimeSlotConstants.MAXIMUM_RECURRING_SLOTS}",
                    ) { env.router.open(Route.RecurringSlots) }
                    InsetDivider()
                    MenuRow(Sym.handRaisedFill, tr("屏蔽名单"), tint = AppTheme.colors.pink) { env.router.open(Route.BlockedUsers) }
                }
            }
            SectionLabel(tr("谁能看到我、联系我"), rules = visibilityRules()) {
                val privacy = user?.privacy ?: PrivacySettings()
                Column(Modifier.card(AppTheme.colors.surface, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    ToggleRow(tr("在首页显示我"), privacy.showsWhenSearching, { on -> updatePrivacy { it.copy(showsWhenSearching = on) } })
                    InsetDivider()
                    // 打开直接存，关掉先确认（附近的人就约不了你了）
                    ToggleRow(tr("在同馆常客里显示我"), privacy.showsAsRegular, { on ->
                        if (on) updatePrivacy { it.copy(showsAsRegular = true) } else confirmHideRegular = true
                    })
                    InsetDivider()
                    ToggleRow(tr("接收消息请求"), privacy.allowsMessageRequests, { on -> updatePrivacy { it.copy(allowsMessageRequests = on) } })
                    InsetDivider()
                    ToggleRow(tr("可以按昵称找到我"), privacy.findableByNickname, { on -> updatePrivacy { it.copy(findableByNickname = on) } })
                    InsetDivider()
                    ChallengePolicyRow(privacy.challengePolicy) { policy -> updatePrivacy { it.copy(challengePolicy = policy) } }
                    InsetDivider()
                    ToggleRow(tr("出现在排行榜上"), privacy.showsOnLeaderboards, { on -> updatePrivacy { it.copy(showsOnLeaderboards = on) } })
                }
            }
            SectionLabel(
                tr("隐私与安全"),
                rules = listOf(
                    tr("邮箱只用于登录与安全验证，不会展示给任何球友"),
                    tr("位置只用于计算距离，球友看到的是大概范围（如“5 英里内”），不是精确距离"),
                    tr("陌生人不能直接私信你：好友可以聊，同一场球局用球局群聊，同球群只能发一条消息请求"),
                    tr("评价匿名汇总，不展示单条评价与评价人"),
                    tr("屏蔽对方不会通知对方"),
                ),
            ) {
                Box(Modifier.card(AppTheme.colors.surface, shadow = AppTheme.Elevation.none)) { LegalLinksRow() }
            }
            SectionLabel(tr("帮助")) {
                MenuCard {
                    MenuRow(Sym.questionmarkBubbleFill, tr("帮助与反馈"), tint = AppTheme.colors.sky) { showHelp = true }
                    if (showsSupport) {
                        InsetDivider()
                        MenuRow(Sym.cupAndSaucerFill, tr("支持 Badie"), tint = AppTheme.colors.peach) { showTips = true }
                    }
                }
            }
            SectionLabel(tr("账号")) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    BrutalButton(tr("设置或修改密码"), { showPassword = true }, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
                    BrutalButton(tr("退出登录"), { showSignOut = true }, kind = ButtonKind.Accent(AppTheme.colors.butter), size = ButtonSize.Medium)
                    TextAction(tr("注销账号并删除数据"), { showDelete = true }, Modifier.fillMaxWidth(), color = AppTheme.colors.danger)
                }
            }
            Text(
                tr("Badie v%@", BuildConfig.VERSION_NAME), style = AppTheme.Typography.caption, color = AppTheme.colors.inkTertiary,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    if (showLanguage) {
        SheetScaffold(onDismiss = { showLanguage = false }) {
            LanguagePicker { code ->
                showLanguage = false
                // 等弹层收起再换：界面会按新语言重建
                scope.launch {
                    delay(350)
                    AppLanguage.choose(code)
                    appState.backend.syncServerLocale()
                }
            }
        }
    }
    if (showRadius) {
        BadieSheet(onDismiss = { showRadius = false }) { dismiss -> com.badie.app.features.venues.TravelRadiusSheet(dismiss) }
    }
    if (showPassword) {
        BadieSheet(onDismiss = { showPassword = false }) { dismiss -> PasswordSheet(api, dismiss) }
    }
    if (showHelp) {
        BadieSheet(onDismiss = { showHelp = false }) { dismiss -> HelpSheet(api, dismiss) }
    }
    if (showTips) {
        BadieSheet(onDismiss = { showTips = false }) { dismiss -> TipJarSheet(dismiss) }
    }
    if (showSignOut) {
        ConfirmDialog(
            title = tr("退出登录？"), message = tr("用同一邮箱登录即可恢复你的数据。"), confirmTitle = tr("退出"),
            onDismiss = { showSignOut = false },
        ) {
            showSignOut = false
            scope.launch {
                env.router.reset()
                appState.signOut()
            }
        }
    }
    if (confirmHideRegular) {
        ConfirmDialog(
            title = tr("要关掉吗？"), message = tr("我们只用你的常去球馆，让附近的球友找到你、约你打球。关掉后，别人就约不了你了。"),
            confirmTitle = tr("关掉"), cancelTitle = tr("保持打开"),
            onDismiss = { confirmHideRegular = false },
        ) {
            confirmHideRegular = false
            updatePrivacy { it.copy(showsAsRegular = false) }
        }
    }
    if (showDelete) {
        ConfirmDialog(
            title = tr("注销账号？"),
            message = tr("将删除你的资料、球友、私信、评价和球局记录，且无法恢复。以后的球局会取消并通知其他球友；你管理的球群交给下一位组织者。"),
            confirmTitle = tr("永久删除"),
            onDismiss = { showDelete = false },
        ) {
            showDelete = false
            scope.launch {
                try {
                    api.deleteAccount()
                    env.router.reset()
                    appState.syncPhase()
                    appState.showToast(L10n.tr("账号与数据已删除"))
                } catch (error: RemoteError) {
                    appState.showError(error)
                }
            }
        }
    }
}

/** 一组菜单行：白底贴纸 */
@Composable
fun MenuCard(modifier: Modifier = Modifier, shadow: Boolean = true, content: @Composable () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = if (shadow) AppTheme.Elevation.card else AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.lg),
    ) { content() }
}

/** “谁能挑战我”：点开选四种之一 */
@Composable
private fun ChallengePolicyRow(policy: ChallengePolicy, onSelect: (ChallengePolicy) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val colors = AppTheme.colors
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { expanded = true },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            Text(tr("谁能挑战我"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(policy.title, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                Symbol(Sym.chevronUpChevronDown, size = 11, tint = colors.inkSecondary)
            }
        }
        DropdownMenu(expanded, { expanded = false }, containerColor = colors.surface) {
            for (option in ChallengePolicy.entries) {
                DropdownMenuItem(
                    text = { Text(option.title, style = AppTheme.Typography.body, color = colors.ink) },
                    onClick = {
                        expanded = false
                        if (option != policy) onSelect(option)
                    },
                    trailingIcon = if (option == policy) ({ Symbol(Sym.checkmark, size = 13, tint = colors.ink) }) else null,
                    modifier = Modifier.semantics { selected = option == policy },
                )
            }
        }
    }
}

/** 原来写在每个开关下面的说明 */
private fun visibilityRules(): List<String> = buildList {
    add(L10n.tr("找球友时，附近的人在首页能看到你的昵称、头像、等级和想打的时间、球馆，看不到联系方式"))
    add(L10n.tr("同馆常客只显示昵称、等级和球馆，不显示时间和位置"))
    add(L10n.tr("打开“在同馆常客里显示我”，也会出现在附近的人里：别人能看到你的昵称、等级、常去的球馆和常用时间，可以约你"))
    add(L10n.tr("消息请求来自同球群的人；关闭后只有球友能私信你，球局群聊不受影响"))
    add(L10n.tr("按昵称找到你的人能看到你的昵称和等级，可以发好友申请"))
    for (policy in ChallengePolicy.entries) add(L10n.tr("挑战 · %@：%@", policy.title, policy.detail))
    add(L10n.tr("关闭上榜后你仍能看榜，但不会上榜"))
}

/** 系统权限现在的状态：“已开启 / 已关闭 / 未设置”“使用期间 / 已关闭 / 未设置” */
class PermissionState(val notifications: Status, val location: Status) {
    enum class Status { Authorized, Denied, NotDetermined }

    val notificationText: String
        get() = when (notifications) {
            Status.Authorized -> L10n.tr("已开启")
            Status.Denied -> L10n.tr("已关闭")
            Status.NotDetermined -> L10n.tr("未设置")
        }

    val locationText: String
        get() = when (location) {
            Status.Authorized -> L10n.tr("使用期间")
            Status.Denied -> L10n.tr("已关闭")
            Status.NotDetermined -> L10n.tr("未设置")
        }

    companion object {
        fun read(context: Context, api: ProfileApi): PermissionState {
            val notificationsOn = NotificationManagerCompat.from(context).areNotificationsEnabled()
            // Android 13 起要问；以前的系统默认就是开的，只能在系统设置里关
            val notifications = when {
                notificationsOn -> Status.Authorized
                Build.VERSION.SDK_INT >= 33 && !api.wasAsked(Manifest.permission.POST_NOTIFICATIONS) -> Status.NotDetermined
                else -> Status.Denied
            }
            val granted = LocationProvider.PERMISSIONS.any { ContextCompat.checkSelfPermission(context, it) == android.content.pm.PackageManager.PERMISSION_GRANTED }
            val location = when {
                granted -> Status.Authorized
                api.wasAsked(Manifest.permission.ACCESS_COARSE_LOCATION) -> Status.Denied
                else -> Status.NotDetermined
            }
            return PermissionState(notifications, location)
        }
    }
}

/** 这个 App 的通知设置页 */
private fun Context.openNotificationSettings() {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
    try {
        startActivity(intent)
    } catch (_: android.content.ActivityNotFoundException) {
        openAppSettings()
    }
}

/** 这个 App 的系统设置页（权限在里面） */
private fun Context.openAppSettings() {
    try {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:$packageName".toUri()))
    } catch (_: android.content.ActivityNotFoundException) {
    }
}

/** 选 App 的语言：跟随系统，或 10 种里选一种；每种语言用它自己的写法 */
@Composable
fun LanguagePicker(onChoose: (String?) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val chosen = AppLanguage.chosen
    Column(Modifier.fillMaxWidth().padding(bottom = AppTheme.Spacing.xl), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
        Text(
            tr("App 语言"), style = AppTheme.Typography.title, color = colors.ink,
            modifier = Modifier.padding(top = AppTheme.Spacing.xl).padding(horizontal = AppTheme.Spacing.screen).semantics { heading() },
        )
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
                .padding(horizontal = AppTheme.Spacing.lg),
        ) {
            val options: List<String?> = listOf<String?>(null) + AppLanguage.supported
            options.forEachIndexed { index, code ->
                if (index > 0) InsetDivider()
                val isSelected = chosen == code
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.RadioButton) {
                            haptics.selection()
                            onChoose(code)
                        }
                        .semantics { selected = isSelected }
                        .padding(vertical = AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
                ) {
                    Text(if (code == null) tr("跟随系统") else AppLanguage.name(code), style = AppTheme.Typography.bodyBold, color = colors.ink)
                    if (code == null) {
                        Text(AppLanguage.name(AppLanguage.system), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                    }
                    Spacer(Modifier.weight(1f))
                    if (isSelected) Symbol(Sym.checkmark, size = 15, tint = colors.ink)
                }
            }
        }
    }
}

/** 要用户确认的弹窗（退出登录、注销这类） */
@Composable
fun ConfirmDialog(title: String, message: String, confirmTitle: String, onDismiss: () -> Unit, cancelTitle: String? = null, onConfirm: () -> Unit) {
    val colors = AppTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text(title, style = AppTheme.Typography.headline, color = colors.ink) },
        text = { Text(message, style = AppTheme.Typography.subheadline, color = colors.inkSecondary) },
        confirmButton = { TextAction(confirmTitle, onConfirm, color = colors.danger) },
        dismissButton = { TextAction(cancelTitle ?: tr("取消"), onDismiss, color = colors.ink) },
    )
}
