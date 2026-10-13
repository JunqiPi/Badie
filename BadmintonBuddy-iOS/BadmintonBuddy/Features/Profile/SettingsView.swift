import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showRadius = false
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var showReset = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "设置")
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    section("外观") {
                        SegmentedSticker(options: AppAppearance.allCases, selection: $appState.appearance, title: { $0.title })
                    }

                    section("权限") {
                        VStack(spacing: 0) {
                            settingRow(icon: "bell.badge.fill", tint: AppTheme.Colors.butter, title: "球局提醒",
                                       value: notificationText) {
                                Task { await handleNotificationTap() }
                            }
                            InsetDivider()
                            settingRow(icon: "location.fill", tint: AppTheme.Colors.sky, title: "定位",
                                       value: locationText) {
                                if locationManager.authorizationStatus == .notDetermined {
                                    locationManager.requestAuthorization()
                                } else {
                                    openSystemSettings()
                                }
                            }
                            InsetDivider()
                            settingRow(icon: "map.fill", tint: AppTheme.Colors.mint, title: "出行范围",
                                       value: DistanceFormatter.radius(km: locationManager.preferences.travelRadiusKm)) {
                                showRadius = true
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    }

                    section("约球偏好") {
                        VStack(spacing: 0) {
                            MenuRow(icon: "calendar.badge.clock", tint: AppTheme.Colors.peach, title: "常用时间",
                                    value: "\(appState.backend.recurringSlots().count)/\(TimeSlotConstants.maximumRecurringSlots)") {
                                router.open(.recurringSlots)
                            }
                            InsetDivider()
                            MenuRow(icon: "hand.raised.fill", tint: AppTheme.Colors.pink, title: "屏蔽名单") {
                                router.open(.blockedUsers)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    }

                    section("隐私与安全") {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            privacyLine("手机号只用于登录与安全验证，不会展示给任何球友")
                            privacyLine("位置只用于计算距离，球友看到的是大概距离而非精确位置")
                            privacyLine("评价匿名汇总，不展示单条评价与评价人")
                            privacyLine("屏蔽对方不会通知对方")
                        }
                        .card(AppTheme.Colors.surface, shadow: .zero)
                    }

                    section("演示数据") {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Text("当前没有接入线上服务：附近球友、公开球局为本机模拟数据，会自动回复消息、加入球局和互评，方便完整体验流程。")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("重置演示数据") { showReset = true }
                                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                        }
                        .card(AppTheme.Colors.surface, shadow: .zero)
                    }

                    section("账号") {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Button("退出登录") { showSignOut = true }
                                .buttonStyle(BrutalButtonStyle(kind: .accent(AppTheme.Colors.butter), size: .medium))
                            Button("注销账号并删除数据") { showDelete = true }
                                .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                        }
                    }

                    Text("羽毛球搭子 v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0")")
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
            Text("数据保存在本机，用同一手机号登录即可恢复。")
        }
        .alert("注销账号？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) { appState.deleteAccount() }
        } message: {
            Text("将删除你的资料、球友关系、聊天记录、球局与评价，且无法恢复。")
        }
        .alert("重置演示数据？", isPresented: $showReset) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { appState.resetDemoData() }
        } message: {
            Text("会清空本机所有账号和数据，回到初次打开的状态。")
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func settingRow(icon: String, tint: Color, title: String, value: String, action: @escaping () -> Void) -> some View {
        MenuRow(icon: icon, tint: tint, title: title, value: value, action: action)
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
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已关闭"
        default: return "未设置"
        }
    }

    private var locationText: String {
        if locationManager.isAuthorized { return "使用期间" }
        if locationManager.isDenied { return "已关闭" }
        return "未设置"
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
            ScreenHeader(title: "常用时间") {
                if slots.canAddMore {
                    IconButton(systemName: "plus", accessibilityLabel: "添加常用时间", accent: AppTheme.Colors.lime) {
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
                        EmptyStateView(icon: "calendar.badge.plus", title: "还没有常用时间", tint: AppTheme.Colors.peach,
                                       actionTitle: "添加") { showEditor = true }
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
                TimeStepper(title: "开始", minutes: $startMinutes, range: (6 * 60)...(23 * 60))
                TimeStepper(title: "结束", minutes: $endMinutes, range: (7 * 60)...(24 * 60))
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
            ScreenHeader(title: "屏蔽名单")
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    if messageManager.blockedUsers.isEmpty {
                        EmptyStateView(icon: "hand.raised", title: "没有屏蔽任何人", tint: AppTheme.Colors.mint)
                    }
                    ForEach(messageManager.blockedUsers) { blocked in
                        HStack(spacing: AppTheme.Spacing.md) {
                            if let user = messageManager.user(id: blocked.blockedUserId) {
                                AvatarView(user: user, size: 40)
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
                                appState.showToast("已解除屏蔽")
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
