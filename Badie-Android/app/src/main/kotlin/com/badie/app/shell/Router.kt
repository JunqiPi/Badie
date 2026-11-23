package com.badie.app.shell

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import com.badie.app.design.Sym
import com.badie.app.design.SymbolId

// MARK: - 标签页

/** Home 是第一个标签“发现”（刷卡找人）；名字和 iPhone 一样没改，推送在用 */
enum class MainTab(val titleKey: String, val icon: SymbolId, val selectedIcon: SymbolId) {
    Home("发现", Sym.heart, Sym.heartFill),
    Games("球局", Sym.ticket, Sym.ticketFill),
    Messages("消息", Sym.bubbleLeftAndBubbleRight, Sym.bubbleLeftAndBubbleRightFill),
    Profile("我的", Sym.personCropCircle, Sym.personCropCircleFill),
}

// MARK: - 导航目的地（和 iPhone 的 Route 一一对应）

sealed interface Route {
    data class Game(val id: String) : Route
    data class Room(val id: String) : Route
    /** mode：预选单打或双打；invitee：建好后邀请的人 */
    data class CreateRoom(val mode: String? = null, val invitee: String? = null) : Route
    data class JoinRoom(val code: String? = null) : Route
    data object PublicGames : Route
    data class Chat(val userId: String) : Route
    data object Friends : Route
    data object AddFriend : Route
    data object Surveys : Route
    data class Survey(val pendingId: String) : Route
    data object EditProfile : Route
    data object Settings : Route
    data object RecurringSlots : Route
    data object BlockedUsers : Route
    data object Notifications : Route
    data object Courts : Route
    data object GameHistory : Route
    data class Venue(val id: String) : Route
    /** 快速匹配的球馆多选（可带初始搜索词） */
    data class MatchVenues(val query: String? = null) : Route
    /** 添加球馆 */
    data object AddVenue : Route
    /** 群聊（球局群、球群） */
    data class GroupChat(val threadId: String) : Route
    data class Group(val id: String) : Route
    /** 找球群（附近的固定局） */
    data object Groups : Route
    /** 创建球群（可预选球馆） */
    data class CreateGroup(val venueId: String? = null) : Route
    /** 群主编辑球群 */
    data class EditGroup(val id: String) : Route
    /** 1–9 级对照表 */
    data object LevelGuide : Route
    /** 高水平认证申请 */
    data object Verification : Route
    /** 全球周榜 */
    data object Leaderboard : Route
    /** 场馆月榜 */
    data class VenueLeaderboard(val venueId: String) : Route
    /** 收到和发出的挑战 */
    data object Challenges : Route
    /** 当晚：排场、比赛、收款（球群某一场的组织者和帮手）；pay 是直接打开收款 */
    data class Night(val sessionId: String, val pay: Boolean = false) : Route
    /** 新建比赛（从“当晚”开时带上那一场）、比赛页 */
    data class CreateMatch(val sessionId: String? = null) : Route
    data class Match(val id: String) : Route
    /** 我的 → 比赛 */
    data object MyMatches : Route
    /** 球群的收款记录（组织者），和其中某一场的收款 */
    data class GroupPayments(val groupId: String) : Route
    data class SessionPayments(val sessionId: String) : Route
    /** 我的 → 收款方式 */
    data object PaymentHandles : Route
}

// MARK: - 路由器：每个标签页一条独立的导航栈

@Stable
class Router {
    var selectedTab by mutableStateOf(MainTab.Home)
        private set

    /** 每跳一次页面加一：全屏页（匹配流程）看到它变了就自己关掉，不然新页面在它后面看不见 */
    var navigations by mutableIntStateOf(0)
        private set

    private val paths: Map<MainTab, SnapshotStateList<Route>> = MainTab.entries.associateWith { mutableStateListOf() }

    /** 中间“+”按钮的创建菜单 */
    var isCreateMenuPresented by mutableStateOf(false)

    /** 快速匹配设置页 */
    var isMatchSetupPresented by mutableStateOf(false)

    fun path(tab: MainTab): List<Route> = paths.getValue(tab)

    /** 当前标签页在根页面时才显示悬浮标签栏 */
    val isTabBarVisible: Boolean get() = path(selectedTab).isEmpty()

    fun select(tab: MainTab) {
        if (selectedTab == tab) {
            // 再点一次回到根页面
            paths.getValue(tab).clear()
        } else {
            selectedTab = tab
        }
    }

    /** 在指定标签页（默认当前页）推入页面 */
    fun open(route: Route, tab: MainTab? = null) {
        navigations += 1
        val target = tab ?: selectedTab
        selectedTab = target
        val path = paths.getValue(target)
        if (path.lastOrNull() != route) path.add(route)
    }

    /** 回到某个标签页的根页面 */
    fun showRoot(tab: MainTab) {
        navigations += 1
        selectedTab = tab
        paths.getValue(tab).clear()
    }

    /** 切到某个标签页，并把它的导航栈换成这一个页面 */
    fun show(route: Route, tab: MainTab) {
        navigations += 1
        selectedTab = tab
        paths.getValue(tab).apply { clear(); add(route) }
    }

    /** 退出登录时清空所有导航状态 */
    fun reset() {
        paths.values.forEach { it.clear() }
        selectedTab = MainTab.Home
        isCreateMenuPresented = false
        isMatchSetupPresented = false
    }

    /** 当前看的就是这个页面（正在看的会话来了新消息，不用再弹通知） */
    fun isShowing(route: Route): Boolean = path(selectedTab).lastOrNull() == route

    fun pop() {
        paths.getValue(selectedTab).removeLastOrNull()
    }
}
