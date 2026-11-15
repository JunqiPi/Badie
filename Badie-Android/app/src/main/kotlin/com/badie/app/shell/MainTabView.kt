package com.badie.app.shell

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.badie.app.design.AppTheme
import com.badie.app.design.CountBadge
import com.badie.app.design.Dot
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.ScreenHeader
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.SymbolId
import com.badie.app.design.drawSticker
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.profile.SettingsView
import com.badie.app.l10n.tr
import kotlinx.coroutines.launch

/** 导航栈里的一项：标签页的根页面，或者推进去的页面 */
private sealed interface StackKey {
    data class Root(val tab: MainTab) : StackKey
    data class Pushed(val route: Route) : StackKey
}

/** 主框架：四个标签页各自一条导航栈 + 悬浮标签栏 + 中间的“+” */
@Composable
fun MainTabView() {
    val router = LocalEnv.current.router
    val holder = rememberSaveableStateHolder()
    var pendingCreateAction by remember { mutableStateOf<CreateAction?>(null) }

    Box(Modifier.fillMaxSize()) {
        // 一次只画当前的标签页；别的标签页的页面状态（滚动位置等）存着，切回来还在
        val tab = router.selectedTab
        holder.SaveableStateProvider(tab) {
            val stack = listOf<StackKey>(StackKey.Root(tab)) + router.path(tab).map { StackKey.Pushed(it) }
            NavDisplay(
                backStack = stack,
                onBack = { router.pop() },
                entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator()),
                entryProvider = { key ->
                    NavEntry(key) {
                        Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas).windowInsetsPadding(WindowInsets.safeDrawing)) {
                            when (key) {
                                is StackKey.Root -> TabRoot(key.tab)
                                is StackKey.Pushed -> RouteDestination(key.route)
                            }
                        }
                    }
                },
            )
        }

        AnimatedVisibility(
            router.isTabBarVisible,
            Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(AppTheme.Motion.standard()) { it } + fadeIn(),
            exit = slideOutVertically(AppTheme.Motion.standard()) { it } + fadeOut(),
        ) {
            FloatingTabBar(badges = emptyMap()) { router.isCreateMenuPresented = true }
        }
    }

    if (router.isCreateMenuPresented) {
        BadieSheet(onDismiss = {
            router.isCreateMenuPresented = false
            // 菜单收起后才执行
            pendingCreateAction?.let { action ->
                pendingCreateAction = null
                when (action) {
                    CreateAction.QuickMatch -> router.isMatchSetupPresented = true
                    CreateAction.CreateRoom -> router.open(Route.CreateRoom(), MainTab.Games)
                    CreateAction.Groups -> router.open(Route.Groups, MainTab.Games)
                    CreateAction.JoinRoom -> router.open(Route.JoinRoom(), MainTab.Games)
                }
            }
        }) { dismiss ->
            CreateMenuSheet { action ->
                pendingCreateAction = action
                dismiss()
            }
        }
    }
}

/** 各标签页的根页面。页面还没搬过来的，先只有标题 */
@Composable
private fun TabRoot(tab: MainTab) {
    val router = LocalEnv.current.router
    Column(Modifier.fillMaxSize()) {
        LargeTitleHeader(tr(tab.titleKey)) {
            if (tab == MainTab.Profile) IconButton(Sym.gearshapeFill, tr("设置")) { router.open(Route.Settings) }
        }
    }
}

/** 推进导航栈的页面。还没搬过来的先只有返回栏 */
@Composable
private fun RouteDestination(route: Route) {
    val router = LocalEnv.current.router
    if (route == Route.Settings) return SettingsView()
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(
            title = when (route) {
                is Route.CreateRoom -> tr("发起球局")
                Route.Groups -> tr("固定局 · 球群")
                is Route.JoinRoom -> tr("输入房间码 / 群号")
                else -> ""
            },
            onBack = { router.pop() },
        )
    }
}

// MARK: - 半屏弹层：圆角 28，带拖动条

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BadieSheet(onDismiss: () -> Unit, content: @Composable (dismiss: () -> Unit) -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val handle = AppTheme.colors.inkTertiary
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = AppTheme.colors.canvas,
        tonalElevation = 0.dp,
        dragHandle = {
            Spacer(
                Modifier.padding(top = AppTheme.Spacing.sm).size(36.dp, 5.dp).drawBehind {
                    drawRoundRect(handle.copy(alpha = 0.5f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2))
                },
            )
        },
    ) {
        Box {
            // 先放收起的动画，放完再通知关闭
            content { scope.launch { state.hide() }.invokeOnCompletion { onDismiss() } }
            ToastHost()
        }
    }
}

// MARK: - 悬浮标签栏

@Composable
fun FloatingTabBar(badges: Map<MainTab, Int>, onCreate: () -> Unit) {
    val canvas = AppTheme.colors.canvas
    Box(
        Modifier
            .fillMaxWidth()
            // 标签栏后面铺实色到屏幕底边，上方渐隐，滚动的内容不会从标签栏四周露出来
            .drawBehind {
                val fade = 36.dp.toPx()
                drawRect(Brush.verticalGradient(listOf(canvas.copy(alpha = 0f), canvas), startY = -fade, endY = 0f), topLeft = androidx.compose.ui.geometry.Offset(0f, -fade), size = androidx.compose.ui.geometry.Size(size.width, fade))
                drawRect(canvas)
            }
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(horizontal = AppTheme.Spacing.lg)
            .padding(bottom = AppTheme.Spacing.sm),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(68.dp)
                .sticker(AppTheme.colors.surface, radius = 26.dp, shadow = DpOffset(0.dp, 4.dp))
                .padding(horizontal = AppTheme.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TabButton(MainTab.Home, badges)
            TabButton(MainTab.Games, badges)
            CreateButton(onCreate)
            TabButton(MainTab.Messages, badges)
            TabButton(MainTab.Profile, badges)
        }
    }
}

@Composable
private fun RowScope.TabButton(tab: MainTab, badges: Map<MainTab, Int>) {
    val router = LocalEnv.current.router
    val haptics = rememberHaptics()
    val isSelected = router.selectedTab == tab
    val count = badges[tab] ?: 0
    val title = tr(tab.titleKey)
    val pending = if (count > 0) tr("%lld 条未处理", count) else ""
    val color = if (isSelected) AppTheme.colors.ink else AppTheme.colors.inkTertiary
    Column(
        Modifier
            .weight(1f)
            .defaultMinSize(minHeight = 56.dp)
            .pressable(scale = 0.9f, role = Role.Tab) {
                haptics.selection()
                router.select(tab)
            }
            .clearAndSetSemantics {
                contentDescription = title
                stateDescription = pending
                selected = isSelected
                role = Role.Tab
                onClick { router.select(tab); true }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
    ) {
        Box {
            Symbol(if (isSelected) tab.selectedIcon else tab.icon, size = 20, tint = color)
            if (count > 0) CountBadge(count, Modifier.align(Alignment.TopEnd).offset(12.dp, (-8).dp))
        }
        Text(title, style = rounded(11, FontWeight.Bold), color = color, maxLines = 1)
        Dot(if (isSelected) AppTheme.colors.ink else Color.Transparent, 5.dp)
    }
}

@Composable
private fun RowScope.CreateButton(onCreate: () -> Unit) {
    val haptics = rememberHaptics()
    val colors = AppTheme.colors
    val label = tr("约球")
    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .offset(y = (-18).dp)
                .size(62.dp)
                .pressable(scale = 0.92f, onClickLabel = tr("快速匹配、发起球局或输入房间码")) {
                    haptics.impact()
                    onCreate()
                }
                .drawBehind {
                    drawCircle(colors.shadow, center = center.copy(y = center.y + 4.dp.toPx()))
                    drawSticker(colors.lime, colors.stroke, colors.shadow, 31.dp, AppTheme.Elevation.none)
                }
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Symbol(Sym.plus, size = 26, tint = colors.onAccent)
        }
    }
}

// MARK: - “+”菜单

enum class CreateAction { QuickMatch, CreateRoom, Groups, JoinRoom }

@Composable
fun CreateMenuSheet(onSelect: (CreateAction) -> Unit) {
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Text(tr("约一场"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl))
        CreateOption(Sym.boltFill, colors.lime, tr("快速匹配")) { onSelect(CreateAction.QuickMatch) }
        CreateOption(Sym.sportscourtFill, colors.peach, tr("发起球局")) { onSelect(CreateAction.CreateRoom) }
        CreateOption(Sym.person3Fill, colors.sky, tr("固定局 · 球群")) { onSelect(CreateAction.Groups) }
        CreateOption(Sym.number, colors.lavender, tr("输入房间码 / 群号")) { onSelect(CreateAction.JoinRoom) }
    }
}

@Composable
private fun CreateOption(icon: SymbolId, tint: Color, title: String, onClick: () -> Unit) {
    val haptics = rememberHaptics()
    Row(
        Modifier
            .fillMaxWidth()
            .pressable {
                haptics.tap()
                onClick()
            }
            .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg)
            .padding(AppTheme.Spacing.lg)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        IconTile(icon, fill = tint, size = 52.dp)
        Text(title, style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.weight(1f))
        Symbol(Sym.chevronRight, size = 14, tint = AppTheme.colors.inkTertiary)
    }
}
