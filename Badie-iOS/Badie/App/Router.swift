import SwiftUI
import Combine

// MARK: - 标签页

enum MainTab: String, CaseIterable, Identifiable {
    case home, games, messages, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "首页")
        case .games: return String(localized: "球局")
        case .messages: return String(localized: "消息")
        case .profile: return String(localized: "我的")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .games: return "ticket"
        case .messages: return "bubble.left.and.bubble.right"
        case .profile: return "person.crop.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .games: return "ticket.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

// MARK: - 导航目的地

enum Route: Hashable {
    case game(id: String)
    case room(id: String)
    case createRoom(GameMode?, invitee: String?)
    case joinRoom(code: String?)
    case publicGames
    case chat(userId: String)
    case friends
    case addFriend
    case surveys
    case survey(pendingId: String)
    case editProfile
    case settings
    case recurringSlots
    case blockedUsers
    case notifications
    case courts
    case gameHistory
    case venue(id: String)
    /// 快速匹配的球馆多选（可带初始搜索词）
    case matchVenues(query: String?)
    /// 添加球馆（演示时可预填，并自动检查重复）
    case addVenue(prefill: VenuePrefill?)
    /// 群聊（球局群 / 球群）
    case groupChat(threadId: String)
    case group(id: String)
    /// 找球群（附近的固定局）
    case groups
    /// 创建球群（可预选球馆）
    case createGroup(venueId: String?)
    /// 1–9 级对照表
    case levelGuide
    /// 高水平认证申请
    case verification
}

/// 添加球馆的预填内容（地图链接、演示截图）
struct VenuePrefill: Hashable {
    var name: String
    var coordinate: Coordinate
    var address: PostalAddress?
    var checksDuplicates = false
}

// MARK: - 路由器：每个标签页一条独立的导航栈

@MainActor
final class Router: ObservableObject {
    @Published var selectedTab: MainTab = .home
    @Published var paths: [MainTab: [Route]] = [:]
    /// 中间“+”按钮的创建菜单
    @Published var isCreateMenuPresented = false
    /// 快速匹配设置页
    @Published var isMatchSetupPresented = false
    /// 打开匹配设置时滚动到的位置（演示截图用）
    var matchSetupAnchor: String?

    func binding(for tab: MainTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { self.paths[tab] = $0 }
        )
    }

    /// 当前标签页处于根页面时显示悬浮标签栏
    var isTabBarVisible: Bool {
        (paths[selectedTab] ?? []).isEmpty
    }

    func select(_ tab: MainTab) {
        if selectedTab == tab {
            // 再次点击回到根页面
            paths[tab] = []
        } else {
            selectedTab = tab
        }
    }

    /// 在指定标签页（默认当前页）推入页面
    func open(_ route: Route, in tab: MainTab? = nil) {
        let target = tab ?? selectedTab
        if target != selectedTab {
            selectedTab = target
        }
        var path = paths[target] ?? []
        if path.last != route {
            path.append(route)
        }
        paths[target] = path
    }

    /// 切换到某个标签页并重置为指定页面
    func show(_ route: Route, in tab: MainTab) {
        selectedTab = tab
        paths[tab] = [route]
    }

    /// 退出登录时清空所有导航状态
    func reset() {
        paths = [:]
        selectedTab = .home
        isCreateMenuPresented = false
        isMatchSetupPresented = false
    }

    func pop() {
        var path = paths[selectedTab] ?? []
        guard !path.isEmpty else { return }
        path.removeLast()
        paths[selectedTab] = path
    }
}
