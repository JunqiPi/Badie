import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var host: AppHost
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showRadius = false
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var showReset = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "设置"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    section(String(localized: "外观")) {
                        SegmentedSticker(options: AppAppearance.allCases, selection: $appState.appearance, title: { $0.title })
                    }

                    // iOS 在 App 的系统设置页里提供“首选语言”，切换后系统会重启 App
                    section(String(localized: "语言")) {
                        MenuRow(icon: "globe", tint: AppTheme.Colors.sky, title: String(localized: "App 语言"),
                                value: currentLanguageName) {
                            openSystemSettings()
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    }

                    section(String(localized: "权限")) {
                        VStack(spacing: 0) {
                            MenuRow(icon: "bell.badge.fill", tint: AppTheme.Colors.butter, title: String(localized: "球局提醒"),
                                    value: notificationText) {
                                Task { await handleNotificationTap() }
                            }
                            InsetDivider()
                            MenuRow(icon: "location.fill", tint: AppTheme.Colors.sky, title: String(localized: "定位"),
                                    value: locationText) {
                                if locationManager.authorizationStatus == .notDetermined {
                                    locationManager.requestAuthorization()
                                } else {
                                    openSystemSettings()
                                }
                            }
                            InsetDivider()
                            MenuRow(icon: "map.fill", tint: AppTheme.Colors.mint, title: String(localized: "出行范围"),
                                    value: DistanceFormatter.radius(km: locationManager.preferences.travelRadiusKm)) {
                                showRadius = true
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    }

                    section(String(localized: "约球偏好")) {
                        VStack(spacing: 0) {
                            MenuRow(icon: "calendar.badge.clock", tint: AppTheme.Colors.peach, title: String(localized: "常用时间"),
                                    value: "\(appState.backend.recurringSlots().count)/\(TimeSlotConstants.maximumRecurringSlots)") {
                                router.open(.recurringSlots)
                            }
                            InsetDivider()
                            MenuRow(icon: "hand.raised.fill", tint: AppTheme.Colors.pink, title: String(localized: "屏蔽名单")) {
                                router.open(.blockedUsers)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    }

                    section(String(localized: "谁能看到我、联系我")) {
                        VStack(spacing: AppTheme.Spacing.md) {
                            // 正式后端没有同馆常客和消息请求
                            if !appState.isRemote {
                                Toggle(isOn: privacyBinding(\.showsAsRegular)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("在常去球馆的“同馆常客”里显示我")
                                            .font(AppTheme.Typography.bodyBold)
                                            .foregroundStyle(AppTheme.Colors.ink)
                                        Text("只显示昵称、等级和球馆，不显示时间和位置")
                                            .font(AppTheme.Typography.caption)
                                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                                    }
                                }
                                InsetDivider()
                                Toggle(isOn: privacyBinding(\.allowsMessageRequests)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("允许同球群的人给我发消息请求")
                                            .font(AppTheme.Typography.bodyBold)
                                            .foregroundStyle(AppTheme.Colors.ink)
                                        Text("关闭后只有球友能私信你；球局群聊不受影响")
                                            .font(AppTheme.Typography.caption)
                                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                                    }
                                }
                                InsetDivider()
                            }
                            challengePolicyRow
                            InsetDivider()
                            Toggle(isOn: privacyBinding(\.showsOnLeaderboards)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("出现在排行榜上")
                                        .font(AppTheme.Typography.bodyBold)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                    Text("关闭后你仍能看榜，但不会上榜")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                }
                            }
                        }
                        .tint(AppTheme.Colors.success)
                        .card(AppTheme.Colors.surface, shadow: .zero)
                    }

                    section(String(localized: "隐私与安全")) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            privacyLine(appState.isRemote ? String(localized: "邮箱只用于登录与安全验证，不会展示给任何球友")
                                                          : String(localized: "手机号只用于登录与安全验证，不会展示给任何球友"))
                            privacyLine(String(localized: "位置只用于计算距离，球友看到的是大概范围（如“5 英里内”），不是精确距离"))
                            privacyLine(appState.isRemote ? String(localized: "陌生人不能直接私信你：好友可以聊，同一场球局用球局群聊")
                                                          : String(localized: "陌生人不能直接私信你：好友可以聊，同一场球局用球局群聊，同球群只能发一条消息请求"))
                            privacyLine(String(localized: "评价匿名汇总，不展示单条评价与评价人"))
                            privacyLine(String(localized: "屏蔽对方不会通知对方"))
                        }
                        .card(AppTheme.Colors.surface, shadow: .zero)
                    }

                    if !appState.isRemote {
                        section(String(localized: "演示模式")) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("附近球友、公开球局都是本机模拟数据，会自动回复消息、加入球局和互评。服务器上的数据不受影响。")
                                    .font(AppTheme.Typography.footnote)
                                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    if DemoMode.isEnabled {
                                        Button("退出演示模式") { host.setDemoMode(false) }
                                            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
                                    }
                                    Button("重置演示数据") { showReset = true }
                                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                                }
                            }
                            .card(AppTheme.Colors.surface, shadow: .zero)
                        }
                    } else if appState.isAdmin {
                        // 只有服务器上的管理员看得到：用来给别人演示还没接入服务器的功能
                        section(String(localized: "管理员")) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("演示模式用本机模拟的球友和球局，房间、公开球局、同馆常客等功能都能体验。不会改动服务器上的数据，其他用户看不到这个开关。")
                                    .font(AppTheme.Typography.footnote)
                                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("进入演示模式") { host.setDemoMode(true) }
                                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                            }
                            .card(AppTheme.Colors.surface, shadow: .zero)
                        }
                    }

                    section(String(localized: "账号")) {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Button("退出登录") { showSignOut = true }
                                .buttonStyle(BrutalButtonStyle(kind: .accent(AppTheme.Colors.butter), size: .medium))
                            Button("注销账号并删除数据") { showDelete = true }
                                .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                        }
                    }

                    Text("Badie v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0")")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .task { await refreshNotificationStatus() }
        .sheet(isPresented: $showRadius) {
            TravelRadiusSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .alert("退出登录？", isPresented: $showSignOut) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { appState.signOut() }
        } message: {
            Text(appState.isRemote ? String(localized: "用同一邮箱登录即可恢复你的数据。") : String(localized: "数据保存在本机，用同一手机号登录即可恢复。"))
        }
        .alert("注销账号？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) { appState.deleteAccount() }
        } message: {
            Text(appState.isRemote ? String(localized: "将删除你的资料、球友、私信、评价和球局记录，且无法恢复。以后的球局会取消并通知其他球友；你管理的球群交给下一位组织者。")
                                   : String(localized: "将删除你的资料、球友关系、聊天记录、球局与评价，且无法恢复。"))
        }
        .alert("重置演示数据？", isPresented: $showReset) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { appState.resetDemoData() }
        } message: {
            Text("会清空本机所有账号和数据，回到初次打开的状态。")
        }
    }

    // MARK: Helpers

    private func privacyBinding(_ keyPath: WritableKeyPath<PrivacySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.currentUser?.privacy[keyPath: keyPath] ?? false },
            set: { value in
                guard var privacy = appState.currentUser?.privacy else { return }
                privacy[keyPath: keyPath] = value
                appState.backend.updatePrivacy(privacy)
            }
        )
    }

    private var challengePolicy: Binding<ChallengePolicy> {
        Binding(
            get: { appState.currentUser?.privacy.challengePolicy ?? .similarLevel },
            set: { value in
                guard var privacy = appState.currentUser?.privacy else { return }
                privacy.challengePolicy = value
                appState.backend.updatePrivacy(privacy)
            }
        )
    }

    private var challengePolicyRow: some View {
        Menu {
            Picker("谁可以向我发起挑战", selection: challengePolicy) {
                ForEach(ChallengePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("谁可以向我发起挑战")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text(challengePolicy.wrappedValue.detail)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                HStack(spacing: 4) {
                    Text(challengePolicy.wrappedValue.title)
                        .font(AppTheme.Typography.footnoteBold)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func privacyLine(_ text: String) -> some View {
        Label {
            Text(text)
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(AppTheme.Colors.success)
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return String(localized: "已开启")
        case .denied: return String(localized: "已关闭")
        default: return String(localized: "未设置")
        }
    }

    private var locationText: String {
        if locationManager.isAuthorized { return String(localized: "使用期间") }
        if locationManager.isDenied { return String(localized: "已关闭") }
        return String(localized: "未设置")
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func handleNotificationTap() async {
        if notificationStatus == .notDetermined {
            _ = await ReminderService.requestAuthorization()
            await refreshNotificationStatus()
        } else {
            openSystemSettings()
        }
    }

    private var currentLanguageName: String? {
        guard let id = Bundle.main.preferredLocalizations.first else { return nil }
        return Locale(identifier: id).localizedString(forIdentifier: id)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 常用时间（最多 5 个）

struct RecurringSlotsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var slots: [RecurringTimeSlot] = []
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "常用时间")) {
                if slots.canAddMore {
                    IconButton(systemName: "plus", accessibilityLabel: String(localized: "添加常用时间"), accent: AppTheme.Colors.lime) {
                        showEditor = true
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("快速匹配会优先使用最近的常用时间。最多保存 \(TimeSlotConstants.maximumRecurringSlots) 个，还可添加 \(slots.remainingSlots) 个。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if slots.isEmpty {
                        EmptyStateView(icon: "calendar.badge.plus", title: String(localized: "还没有常用时间"), tint: AppTheme.Colors.peach,
                                       actionTitle: String(localized: "添加")) { showEditor = true }
                    }
                    ForEach($slots) { $slot in
                        HStack(spacing: AppTheme.Spacing.md) {
                            IconTile(systemName: "calendar", fill: slot.isActive ? AppTheme.Colors.peach : AppTheme.Colors.surfaceMuted, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.dayOfWeekName)
                                    .font(AppTheme.Typography.headline)
                                Text(slot.formattedTimeRange)
                                    .font(AppTheme.Typography.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                            }
                            .foregroundStyle(AppTheme.Colors.ink)
                            Spacer()
                            Toggle("启用", isOn: $slot.isActive)
                                .labelsHidden()
                                .tint(AppTheme.Colors.success)
                                .onChange(of: slot.isActive) { _, _ in persist() }
                            Button {
                                slots.removeAll { $0.id == slot.id }
                                persist()
                            } label: {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(AppTheme.Colors.danger)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("删除 \(slot.displayText)")
                        }
                        .padding(AppTheme.Spacing.md)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear { slots = appState.backend.recurringSlots() }
        .sheet(isPresented: $showEditor) {
            RecurringSlotEditor { slot in
                slots.append(slot)
                persist()
            }
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.visible)
        }
    }

    private func persist() {
        do {
            try appState.backend.saveRecurringSlots(slots)
        } catch {
            appState.showError(error)
            slots = appState.backend.recurringSlots()
        }
    }
}

struct RecurringSlotEditor: View {
    let onSave: (RecurringTimeSlot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dayOfWeek = 4
    @State private var startMinutes = 19 * 60
    @State private var endMinutes = 21 * 60

    private var candidate: RecurringTimeSlot {
        RecurringTimeSlot(dayOfWeek: dayOfWeek, startHour: startMinutes / 60, startMinute: startMinutes % 60,
                          endHour: endMinutes / 60, endMinute: endMinutes % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("添加常用时间")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    ChoiceChip(title: RecurringTimeSlot.weekdayNames[day - 1], isSelected: dayOfWeek == day) {
                        dayOfWeek = day
                    }
                }
            }
            HStack(spacing: AppTheme.Spacing.md) {
                TimeStepper(title: String(localized: "开始"), minutes: $startMinutes, range: (6 * 60)...(23 * 60))
                TimeStepper(title: String(localized: "结束"), minutes: $endMinutes, range: (7 * 60)...(24 * 60))
            }
            if !candidate.isValidDuration {
                Text("时间段需要 1-8 小时")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            Spacer(minLength: 0)
            Button("保存") {
                onSave(candidate)
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
            .disabled(!candidate.isValidDuration)
            .padding(.bottom, AppTheme.Spacing.md)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

// MARK: - 屏蔽名单

struct BlockedUsersView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var messageManager: MessageManager

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "屏蔽名单"))
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    if messageManager.blockedUsers.isEmpty {
                        EmptyStateView(icon: "hand.raised", title: String(localized: "没有屏蔽任何人"), tint: AppTheme.Colors.mint)
                    }
                    ForEach(messageManager.blockedUsers) { blocked in
                        HStack(spacing: AppTheme.Spacing.md) {
                            if let user = messageManager.user(id: blocked.blockedUserId) {
                                AvatarView(user: user, size: 40)
                                    .opensProfile(user.id, allowsInvite: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.nickname)
                                        .font(AppTheme.Typography.headline)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                    Text("屏蔽于 \(DateText.compact(blocked.blockedAt))")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                }
                            }
                            Spacer()
                            Button("解除") {
                                messageManager.unblock(blocked.blockedUserId)
                                appState.showToast(String(localized: "已解除屏蔽"))
                            }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                        }
                        .padding(AppTheme.Spacing.md)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
}
