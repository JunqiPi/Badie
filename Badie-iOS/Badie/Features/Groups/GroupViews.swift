import SwiftUI

// MARK: - 球群卡片（找球群、球馆页）

struct GroupCard: View {
    let group: PlayGroup
    let venue: BadmintonCourt?
    let activity: GroupActivity
    var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "person.3.fill", fill: AppTheme.Colors.lavender, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if let venue {
                        Text(venue.name)
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let status {
                    TagPill(text: status, fill: AppTheme.Colors.lime)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(group.schedules) { schedule in
                    TagPill(text: "\(schedule.weekdayTitle) \(schedule.timeText)", icon: "calendar", fill: AppTheme.Colors.surfaceMuted,
                            foreground: AppTheme.Colors.ink)
                }
                if group.venueIds.count > 1 {
                    TagPill(text: String(localized: "\(group.venueIds.count) 个球馆"), icon: "mappin.and.ellipse", fill: AppTheme.Colors.surfaceMuted,
                            foreground: AppTheme.Colors.ink)
                }
                if group.isCoached {
                    TagPill(text: String(localized: "教练带课"), icon: "graduationcap.fill", fill: AppTheme.Colors.sky)
                }
                TagPill(text: group.levelText, icon: "chart.bar.fill", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.ink)
                if let audience = group.audience {
                    TagPill(text: audience.onlyLabel, fill: AppTheme.Colors.peach)
                }
            }
            Label(activity.text, systemImage: "waveform.path.ecg")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 找球群

struct GroupsView: View {
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "球群 · 固定局")) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    RulesButton(title: String(localized: "球群怎么用"), points: GroupRules.points)
                    IconButton(systemName: "plus", accessibilityLabel: String(localized: "建一个球群")) {
                        router.open(.createGroup(venueId: nil))
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    if !groupManager.myGroups.isEmpty {
                        section(String(localized: "我加入的"), groups: groupManager.myGroups)
                    }
                    let nearby = groupManager.groups(near: locationManager.coordinate, radiusKm: locationManager.preferences.travelRadiusKm)
                        .filter { group in !groupManager.myGroups.contains { $0.id == group.id } }
                    if nearby.isEmpty {
                        EmptyStateView(icon: "person.3", title: String(localized: "附近还没有球群"),
                                       tint: AppTheme.Colors.lavender, actionTitle: String(localized: "建群")) {
                            router.open(.createGroup(venueId: nil))
                        }
                    } else {
                        section(String(localized: "附近的球群"), groups: nearby)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .refreshesEverything()
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func section(_ title: String, groups: [PlayGroup]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: title, detail: String(localized: "\(groups.count) 个"))
            ForEach(groups) { group in
                Button {
                    router.open(.group(id: group.id))
                } label: {
                    GroupCard(group: group, venue: groupManager.venue(of: group), activity: groupManager.activity(of: group.id),
                              status: groupManager.currentUserId.map { group.isPending($0) } == true ? String(localized: "待审核") : nil)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
    }
}

// MARK: - 球群详情：场次报名、候补、成员、群聊

struct GroupDetailView: View {
    let groupId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var messageManager: MessageManager
    @EnvironmentObject private var router: Router

    @State private var confirmsLeave = false
    @State private var confirmsDisband = false
    @State private var sessionDetail: GroupSession?
    /// 当天的场次（排场、看排场、付钱），见 TonightViews.swift
    @State private var tonight: [GroupTonight] = []

    private var group: PlayGroup? {
        _ = groupManager.revision
        return groupManager.group(id: groupId)
    }

    private var me: String? { appState.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: group?.name ?? String(localized: "球群")) {
                if let group, let venue = groupManager.venue(of: group) {
                    ShareLink(item: group.inviteText(venueName: venue.name)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .frame(width: 44, height: 44)
                            .sticker(AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
                    }
                    .accessibilityLabel("邀请（可以发到微信）")
                }
            }
            if let group {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        header(group)
                        if let me, group.isMember(me) {
                            sessionsSection(group)
                        } else {
                            joinCard(group)
                        }
                        membersSection(group)
                        if let me, group.isOrganizer(me), !group.pendingIds.isEmpty {
                            pendingSection(group)
                        }
                        if let me, group.isMember(me), group.ownerId != me {
                            Button("退出球群") { confirmsLeave = true }
                                .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                                .frame(maxWidth: .infinity)
                        }
                        if let me, group.isOrganizer(me), group.guestSignup?.allowed == true, let link = group.guestSignup?.link {
                            Button {
                                UIPasteboard.general.string = link.absoluteString
                                appState.showToast(String(localized: "已复制报名链接"), style: .success)
                            } label: {
                                Label("复制报名链接", systemImage: "link")
                            }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                            .frame(maxWidth: .infinity)
                        }
                        if group.ownerId == me {
                            VStack(spacing: AppTheme.Spacing.sm) {
                                Button("编辑球群和场次") { router.open(.editGroup(id: group.id)) }
                                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
                                Button("解散球群") { confirmsDisband = true }
                                    .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
            .refreshesEverything()
            } else {
                EmptyStateView(icon: "person.3", title: String(localized: "没有找到这个球群"))
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .confirmationDialog("解散这个球群？", isPresented: $confirmsDisband, titleVisibility: .visible) {
            Button("解散", role: .destructive) {
                Task {
                    do {
                        try await groupManager.disband(groupId)
                        appState.showToast(String(localized: "球群已解散，成员会收到通知"))
                        router.pop()
                    } catch {
                        appState.showError(error)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("以后的场次和报名都会删掉，不能恢复。")
        }
        .confirmationDialog("退出这个球群？", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("退出", role: .destructive) {
                Task {
                    do {
                        try await groupManager.leave(groupId)
                        appState.showToast(String(localized: "已退出，已报名的场次也一并取消"))
                        router.pop()
                    } catch {
                        appState.showError(error)
                    }
                }
            }
        } message: {
            Text("已报名的场次会一并取消，名额让给候补。")
        }
        .sheet(item: $sessionDetail) { session in
            SessionSheet(sessionId: session.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: groupManager.revision) {
            if let list = try? await appState.backend.remoteGroupTonight(groupId) { tonight = list }
        }
    }

    // MARK: Header

    private func header(_ group: PlayGroup) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let venue = groupManager.venue(of: group) {
                Button {
                    router.open(.venue(id: venue.id))
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        IconTile(systemName: "mappin.and.ellipse", fill: AppTheme.Colors.sky, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(venue.name)
                                .font(AppTheme.Typography.bodyBold)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Text(venue.address)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(groupManager.otherVenues(of: group), id: \.id) { venue in
                courtLink(venue)
            }
            if !group.summary.isEmpty {
                Text(group.summary)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 6) {
                if group.isCoached {
                    TagPill(text: String(localized: "教练带课"), icon: "graduationcap.fill", fill: AppTheme.Colors.sky)
                }
                TagPill(text: group.levelText, icon: "chart.bar.fill", fill: AppTheme.Colors.lime)
                if let audience = group.audience {
                    TagPill(text: audience.onlyLabel, fill: AppTheme.Colors.peach)
                }
                TagPill(text: group.joinPolicy.title, icon: "person.badge.plus", fill: AppTheme.Colors.surfaceMuted,
                        foreground: AppTheme.Colors.ink)
                TagPill(text: String(localized: "群号 \(group.inviteCode)"), icon: "number", fill: AppTheme.Colors.surfaceMuted,
                        foreground: AppTheme.Colors.ink)
            }
            ForEach(group.feeLines, id: \.self) { line in
                Label(line, systemImage: "banknote")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(groupManager.activity(of: group.id).text, systemImage: "waveform.path.ecg")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            if let me, group.isMember(me) {
                Button {
                    if let threadId = messageManager.groupChatId(for: group.id) {
                        router.open(.groupChat(threadId: threadId))
                    }
                } label: {
                    Label("球群群聊", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium))
            }
        }
        .card()
    }

    /// 其他球馆（和主球馆一样的样子，点开球馆页）
    private func courtLink(_ venue: BadmintonCourt) -> some View {
        Button {
            router.open(.venue(id: venue.id))
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "mappin.and.ellipse", fill: AppTheme.Colors.sky, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text(venue.address)
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Join

    private func joinCard(_ group: PlayGroup) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let me, group.isPending(me) {
                Label("等组织者同意", systemImage: "hourglass")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.onAccent)
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        Task {
                            do {
                                let joined = try await groupManager.join(group.id)
                                Haptics.success()
                                appState.showToast(joined.isMember(me ?? "") ? String(localized: "已加入「\(joined.name)」") : String(localized: "已提交申请，组织者同意后通知你"),
                                                   style: .success)
                            } catch {
                                appState.showError(error)
                            }
                        }
                    } label: {
                        Text(group.joinPolicy == .open ? String(localized: "加入球群") : String(localized: "申请加入"))
                    }
                    .buttonStyle(.brutalPrimary)
                    RulesButton(title: String(localized: "怎么加入"), points: GroupRules.joinPoints(group))
                }
            }
            if !group.schedules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.schedules) { schedule in
                        Label("\(schedule.weekdayTitle) \(schedule.timeText) · \(schedule.capacity) 个名额", systemImage: "calendar")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.onAccent.opacity(0.75))
                    }
                }
            }
        }
        .card(AppTheme.Colors.butter)
    }

    // MARK: Sessions

    private func sessionsSection(_ group: PlayGroup) -> some View {
        let sessions = groupManager.sessions(groupId: group.id)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("接下来的场次")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                RulesButton(title: String(localized: "报名和候补"), points: GroupRules.points)
                Spacer(minLength: 0)
            }
            if sessions.isEmpty {
                Text("未来两周没有场次")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            // 已经结束、还在收款的场次
            ForEach(tonight.filter { item in !sessions.contains { $0.id == item.id } }) { item in
                TonightPastRow(item: item, groupId: group.id)
            }
            ForEach(sessions) { session in
                SessionRow(session: session, userId: me ?? "", tonight: tonight.first { $0.id == session.id }) {
                    sessionDetail = session
                }
            }
        }
    }

    // MARK: Members

    private func membersSection(_ group: PlayGroup) -> some View {
        let members = group.memberIds.compactMap { groupManager.user($0) }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: String(localized: "成员"), detail: String(localized: "\(members.count) 人"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    ForEach(members.prefix(16)) { member in
                        VStack(spacing: 4) {
                            AvatarView(user: member, size: 48)
                                .opensProfile(member.id)
                            Text(member.id == me ? String(localized: "我") : member.nickname)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.ink)
                                .lineLimit(1)
                            if group.isOrganizer(member.id) {
                                Text("组织者")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                            }
                        }
                        .frame(width: 60)
                    }
                }
            }
        }
    }

    private func pendingSection(_ group: PlayGroup) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: String(localized: "加入申请"), detail: String(localized: "\(group.pendingIds.count) 人"))
            ForEach(group.pendingIds, id: \.self) { userId in
                if let user = groupManager.user(userId) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        AvatarView(user: user, size: 40)
                            .opensProfile(user.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.nickname)
                                .font(AppTheme.Typography.bodyBold)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Text("\(user.displayLevelText) · \(user.publicSummary)")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        Spacer()
                        Button("同意") {
                            Task { try? await groupManager.approve(userId, in: group.id) }
                        }
                        .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
                    }
                }
            }
        }
    }
}

// MARK: - 场次行

struct SessionRow: View {
    let session: GroupSession
    let userId: String
    /// 当天的场次：白底加阴影，多一个排场 / 看排场 / 付钱的按钮
    var tonight: GroupTonight? = nil
    let onOpen: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var groupManager: GroupManager

    var body: some View {
        let status = session.status(of: userId)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.slot.formattedFull)
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        if let venueName = groupManager.sessionVenueName(session) {
                            Label(venueName, systemImage: "mappin.and.ellipse")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text("已报 \(session.signedUp.count)/\(session.capacity)")
                            if !session.waitlist.isEmpty { Text("· 候补 \(session.waitlist.count)") }
                        }
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        ProgressBar(progress: Double(session.signedUp.count) / Double(max(1, session.capacity)))
                            .frame(maxWidth: 160)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                // 开场后：看排场、付钱换掉报名按钮（一行只有一个按钮）
                if let tonight, TonightPlayerButton.replacesSignup(tonight) {
                    TonightPlayerButton(item: tonight, groupId: session.groupId)
                } else {
                    switch status {
                    case .signedUp:
                        Button("已报名 ✓") { cancel() }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                            .accessibilityHint("取消报名")
                    case .waitlisted(let position):
                        Button("候补第 \(position)") { cancel() }
                            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                            .accessibilityHint("取消候补")
                    case .none:
                        Button(session.isFull ? String(localized: "候补") : String(localized: "报名")) { signUp() }
                            .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
                    }
                }
            }
            if let tonight {
                TonightRunButton(item: tonight)
            }
        }
        .padding(AppTheme.Spacing.md)
        .sticker(rowFill(status), radius: AppTheme.Radius.md, shadow: tonight != nil ? AppTheme.Elevation.card : .zero)
    }

    /// 当天的场次白底加阴影；报了名的其他场次淡柠檬绿
    private func rowFill(_ status: GroupSession.Status) -> Color {
        if tonight == nil, status == .signedUp { return AppTheme.Colors.lime.opacity(0.35) }
        return AppTheme.Colors.surface
    }

    private func signUp() {
        Task {
            do {
                switch try await groupManager.signUp(session.id) {
                case .confirmed:
                    Haptics.success()
                    appState.showToast(String(localized: "已报名：\(session.slot.formattedFull)"), style: .success)
                case .waitlisted(let position):
                    appState.showToast(String(localized: "已候补第 \(position) 位，有人退出会自动递补并通知你"))
                }
            } catch {
                appState.showError(error)
            }
        }
    }

    private func cancel() {
        let late = session.slot.startTime.timeIntervalSince(Date()) < GroupSession.lateCancellationWindow
        Task {
            do {
                try await groupManager.cancelSignup(session.id)
                appState.showToast(late ? String(localized: "已取消（开场前 2 小时内，计入临时取消）") : String(localized: "已取消，名额让给候补"))
            } catch {
                appState.showError(error)
            }
        }
    }
}

// MARK: - 某一场的报名名单

struct SessionSheet: View {
    let sessionId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var groupManager: GroupManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = groupManager.revision
        ScrollView {
            if let session = groupManager.session(id: sessionId), let group = groupManager.group(id: session.groupId) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.slot.formattedFull)
                                .font(AppTheme.Typography.title2)
                                .foregroundStyle(AppTheme.Colors.ink)
                            Text(groupManager.sessionVenueName(session) ?? groupManager.venue(of: group)?.name ?? group.name)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        Spacer()
                        IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                    }
                    .padding(.top, AppTheme.Spacing.xl)
                    let organizer = appState.currentUser.map { group.isOrganizer($0.id) } ?? false
                    roster(title: String(localized: "已报名 \(session.signedUp.count)/\(session.capacity)"), ids: session.signedUp,
                           session: session, organizer: organizer)
                    if !session.waitlist.isEmpty {
                        roster(title: String(localized: "候补 \(session.waitlist.count)"), ids: session.waitlist, session: session, organizer: organizer)
                    }
                    if organizer, let dropped = session.lateCancels, !dropped.isEmpty {
                        lateCancels(dropped)
                    }
                    if organizer, !session.isCancelled {
                        Button("取消这一场") {
                            Task {
                                do {
                                    try await groupManager.cancelSession(session.id)
                                    appState.showToast(String(localized: "已取消，已报名的人会收到通知"))
                                    dismiss()
                                } catch {
                                    appState.showError(error)
                                }
                            }
                        }
                        .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func roster(title: String, ids: [String], session: GroupSession, organizer: Bool) -> some View {
        // 访客和报了名的成员同名：可能是同一个人注册后又报了一次，给组织者标出来
        let memberNames = Set((session.signedUp + session.waitlist).filter { session.guests?[$0] == nil }
            .compactMap { groupManager.user($0)?.nickname.lowercased() })
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, userId in
                    if let guest = session.guests?[userId] {
                        guestChip(guest, id: userId, session: session, canRemove: organizer && !session.isCancelled,
                                  sameName: organizer && memberNames.contains(guest.name.lowercased()))
                    } else if let user = groupManager.user(userId) {
                        HStack(spacing: 6) {
                            AvatarView(user: user, size: 28)
                            Text(userId == appState.currentUser?.id ? String(localized: "我") : user.nickname)
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.ink)
                        }
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.Colors.surface))
                        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1))
                        .opensProfile(user.id)
                        .accessibilityLabel("\(index + 1). \(user.nickname)")
                    }
                }
            }
        }
    }

    /// 访客：名字后面标“访客”；组织者点开可以移出这一场（和移出成员一样，候补递补）
    @ViewBuilder
    private func guestChip(_ guest: GroupGuest, id: String, session: GroupSession, canRemove: Bool, sameName: Bool) -> some View {
        let chip = HStack(spacing: 6) {
            Text(guest.name.prefix(1).uppercased())
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(AppTheme.Colors.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppTheme.Colors.surfaceMuted))
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
                .accessibilityHidden(true)
            Text(guest.name)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.ink)
            pill(String(localized: "访客"), fill: AppTheme.Colors.mint)
            if sameName {
                pill(String(localized: "同名"), fill: AppTheme.Colors.surfaceMuted, color: AppTheme.Colors.ink)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, AppTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(AppTheme.Colors.surface))
        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1))
        if canRemove {
            Menu {
                Section(String(localized: "\(guest.name) · 访客 · 报名于 \(guest.signedUpAt.formatted(.dateTime.month().day()))")) {
                    Button(role: .destructive) {
                        removeGuest(id, from: session.id)
                    } label: {
                        Label("移出这一场", systemImage: "minus.circle")
                    }
                }
            } label: {
                chip
            }
        } else {
            chip
        }
    }

    private func pill(_ text: String, fill: Color, color: Color = AppTheme.Colors.onAccent) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
    }

    /// 开场前 2 小时内退出的人（只有组织者看得到）
    private func lateCancels(_ people: [GroupLateCancel]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("临时退出 \(people.count)")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                        if person.guest {
                            pill(String(localized: "访客"), fill: AppTheme.Colors.mint)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.Colors.surfaceMuted))
                }
            }
        }
    }

    private func removeGuest(_ guestId: String, from sessionId: String) {
        Task {
            do {
                try await groupManager.removeGuest(guestId, from: sessionId)
                appState.showToast(String(localized: "已移出这一场"))
            } catch {
                appState.showError(error)
            }
        }
    }
}

// MARK: - 建群

/// 建球群；带 editingGroupId 时是群主编辑（球馆和谁能来不能改）
struct CreateGroupView: View {
    var initialVenueId: String?
    var editingGroupId: String?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var name = ""
    @State private var summary = ""
    @State private var venueId: String?
    /// 主球馆以外的球馆（一共最多 5 个）；有几个球馆时每个场次选在哪个
    @State private var extraVenueIds: [String] = []
    /// 正在换的那个其他球馆（nil = 再加一个）
    @State private var extraIndex: Int?
    @State private var pickedExtraId: String?
    @State private var showExtraPicker = false
    @State private var schedules = [GroupSchedule(id: UUID().uuidString, weekday: 5, startMinutes: 19 * 60 + 30, endMinutes: 22 * 60,
                                                  capacity: 12, feeNote: nil)]
    @State private var lowerLevel = 1
    @State private var upperLevel = 9
    @State private var joinPolicy: PlayGroup.JoinPolicy = .open
    @State private var audience: Gender?
    /// 教练带课：每场 1–40 人，水平范围只作提示
    @State private var coached = false
    @State private var showVenuePicker = false
    @State private var didSetup = false
    @State private var isSaving = false
    /// 访客报名（只在编辑时有）：开关和每场上限随“保存”一起存；复制、重置链接马上生效
    @State private var guestsAllowed = false
    /// nil = 每场名额的一半
    @State private var guestLimit: Int?
    @State private var confirmsResetLink = false

    private var isEditing: Bool { editingGroupId != nil }

    private var editingGroup: PlayGroup? { editingGroupId.flatMap { groupManager.group(id: $0) } }

    /// 名额最多的那一场：访客上限不超过它
    private var maxCapacity: Int { schedules.map(\.capacity).max() ?? 4 }

    private var shownGuestLimit: Int { min(maxCapacity, guestLimit ?? GuestSignup.defaultLimit(capacity: maxCapacity)) }

    private let weekdays = [
        (2, String(localized: "一", comment: "星期一（简写）")),
        (3, String(localized: "二", comment: "星期二（简写）")),
        (4, String(localized: "三", comment: "星期三（简写）")),
        (5, String(localized: "四", comment: "星期四（简写）")),
        (6, String(localized: "五", comment: "星期五（简写）")),
        (7, String(localized: "六", comment: "星期六（简写）")),
        (1, String(localized: "日", comment: "星期日（简写）"))
    ]

    private var venue: BadmintonCourt? { venueId.flatMap { locationManager.court(id: $0) } }

    /// 所有球馆，主球馆在前
    private var allVenueIds: [String] { (venueId.map { [$0] } ?? []) + extraVenueIds }

    private var allCourts: [BadmintonCourt] { allVenueIds.compactMap { locationManager.court(id: $0) } }

    /// 这个场次在哪个球馆（没选或选的球馆删掉了就是主球馆）
    private func courtId(of schedule: GroupSchedule) -> String? {
        schedule.venueId.flatMap { allVenueIds.contains($0) ? $0 : nil } ?? allVenueIds.first
    }

    private var validationMessage: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !PlayGroup.nameLimit.contains(trimmed.count) { return String(localized: "球群名称需要 2–20 个字") }
        if !isEditing && venue == nil { return String(localized: "选择固定的球馆") }
        if schedules.contains(where: { $0.endMinutes - $0.startMinutes < 60 }) { return String(localized: "每场至少 1 小时") }
        if schedules.contains(where: { $0.endMinutes - $0.startMinutes > 720 }) { return String(localized: "每场最长 12 小时") }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: isEditing ? String(localized: "编辑球群") : String(localized: "建一个球群"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    section(String(localized: "名称")) {
                        BrutalTextField(label: String(localized: "球群名称"), placeholder: String(localized: "例：周四晚双打群"), text: $name, characterLimit: 20)
                        BrutalTextField(label: String(localized: "介绍（可选）"), placeholder: String(localized: "例：轮换上场，新手友好；费用按人头在前台付"),
                                        text: $summary, characterLimit: 120, axis: .vertical)
                    }
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text("教练带课")
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        RulesButton(title: String(localized: "教练带课"),
                                    points: [String(localized: "每场最少 1 人，最多 40 人。"),
                                             String(localized: "水平范围只作参考。")])
                        Spacer(minLength: 0)
                        Toggle(String(localized: "教练带课"), isOn: $coached.animation(AppTheme.Motion.standard))
                            .labelsHidden()
                            .tint(AppTheme.Colors.success)
                    }
                    if !isEditing {
                        section(String(localized: "固定球馆")) { venueButton }
                    }
                    if venueId != nil {
                        section(String(localized: "其他球馆")) { extraVenuesEditor }
                    }
                    section(String(localized: "每周固定场次")) {
                        ForEach($schedules) { $schedule in
                            scheduleEditor($schedule)
                        }
                        if schedules.count < PlayGroup.maxSchedules {
                            Button {
                                var next = schedules.last ?? schedules[0]
                                next = GroupSchedule(id: UUID().uuidString, weekday: next.weekday % 7 + 1, startMinutes: next.startMinutes,
                                                     endMinutes: next.endMinutes, capacity: next.capacity, feeNote: nil)
                                schedules.append(next)
                            } label: {
                                Label("再加一个场次", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(TextActionStyle())
                        }
                    }
                    if !isEditing {
                        section(String(localized: "谁能来")) {
                            AudiencePicker(options: appState.currentUser.map { $0.gender == .unspecified ? [] : [$0.gender] } ?? [],
                                           selection: $audience)
                        }
                    }
                    section(String(localized: "接受的水平")) {
                        HStack(spacing: AppTheme.Spacing.md) {
                            LevelStepper(title: String(localized: "最低"), level: $lowerLevel, range: 1...upperLevel)
                            LevelStepper(title: String(localized: "最高"), level: $upperLevel, range: lowerLevel...9)
                        }
                    }
                    section(String(localized: "加入方式")) {
                        SegmentedSticker(options: PlayGroup.JoinPolicy.allCases, selection: $joinPolicy) { $0.title }
                    }
                    if let group = editingGroup {
                        section(String(localized: "访客报名")) { guestSignupEditor(group) }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            VStack(spacing: AppTheme.Spacing.xs) {
                if let message = validationMessage, isEditing || !name.isEmpty {
                    Text(message)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.danger)
                }
                Button(isEditing ? String(localized: "保存") : String(localized: "建群")) { save() }
                    .buttonStyle(.brutalPrimary)
                    .disabled(validationMessage != nil || isSaving)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
            .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { InsetDivider() }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showVenuePicker) {
            CourtPickerSheet(selectedId: $venueId, slot: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: setup)
        // 主球馆换成了其他球馆里的一个、或者删了球馆：去掉重复，场次回到主球馆
        .onChange(of: allVenueIds) { _, ids in
            normalizeCourts(ids)
        }
        // 关掉“教练带课”以后回到普通群的 4–40 人（步长 2）
        .onChange(of: coached) { _, coached in
            guard !coached else { return }
            for index in schedules.indices {
                schedules[index].capacity = max(4, schedules[index].capacity + schedules[index].capacity % 2)
            }
        }
        // 换了谁能来，自己的等级可能跟着换算：范围重新围着自己
        .onChange(of: audience) { _, audience in
            guard !isEditing else { return }
            let level = appState.currentUser?.level(for: audience) ?? 4
            lowerLevel = max(1, level - 2)
            upperLevel = min(9, level + 2)
        }
    }

    private var venueButton: some View {
        Button {
            showVenuePicker = true
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "sportscourt.fill", fill: AppTheme.Colors.sky, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue?.name ?? String(localized: "选择球馆"))
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if let address = venue?.address {
                        Text(address)
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            .padding(AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    /// 其他球馆：和固定球馆一样的样子，点开换一家，右边可以删
    private var extraVenuesEditor: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ForEach(Array(extraVenueIds.enumerated()), id: \.element) { index, id in
                courtButton(locationManager.court(id: id), title: id, onRemove: { extraVenueIds.removeAll { $0 == id } },
                            action: { pickExtra(index) })
            }
            if allVenueIds.count < PlayGroup.maxVenues {
                courtButton(nil, title: String(localized: "再加一个球馆"), action: { pickExtra(nil) })
            }
        }
        .sheet(isPresented: $showExtraPicker, onDismiss: applyExtraPick) {
            CourtPickerSheet(selectedId: $pickedExtraId, slot: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func courtButton(_ court: BadmintonCourt?, title: String, onRemove: (() -> Void)? = nil,
                             action: @escaping () -> Void) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: action) {
                HStack(spacing: AppTheme.Spacing.md) {
                    IconTile(systemName: "sportscourt.fill", fill: AppTheme.Colors.sky, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(court?.name ?? title)
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                        if let address = court?.address {
                            Text(address)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if onRemove == nil {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "移除\(court?.name ?? title)"))
            }
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func pickExtra(_ index: Int?) {
        extraIndex = index
        pickedExtraId = index.map { extraVenueIds[$0] }
        showExtraPicker = true
    }

    /// 选好了：换掉那一家，或者加在最后（和已有的重复就不加）
    private func applyExtraPick() {
        defer {
            extraIndex = nil
            pickedExtraId = nil
        }
        guard let id = pickedExtraId, id != venueId, !extraVenueIds.contains(id) else { return }
        if let index = extraIndex, extraVenueIds.indices.contains(index) {
            extraVenueIds[index] = id
        } else if allVenueIds.count < PlayGroup.maxVenues {
            extraVenueIds.append(id)
        }
    }

    private func normalizeCourts(_ ids: [String]) {
        if let venueId, extraVenueIds.contains(venueId) {
            extraVenueIds.removeAll { $0 == venueId }
        }
        for index in schedules.indices where schedules[index].venueId.map({ !ids.contains($0) }) ?? false {
            schedules[index].venueId = nil
        }
    }

    private func scheduleEditor(_ schedule: Binding<GroupSchedule>) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: 6) {
                ForEach(weekdays.indices, id: \.self) { index in
                    ChoiceChip(title: weekdays[index].1, isSelected: schedule.wrappedValue.weekday == weekdays[index].0) {
                        schedule.wrappedValue.weekday = weekdays[index].0
                    }
                }
            }
            if allCourts.count > 1 {
                FlowLayout(spacing: 6) {
                    ForEach(allCourts, id: \.id) { court in
                        ChoiceChip(title: court.name, isSelected: courtId(of: schedule.wrappedValue) == court.id) {
                            schedule.wrappedValue.venueId = court.id == allVenueIds.first ? nil : court.id
                        }
                    }
                }
            }
            HStack(spacing: AppTheme.Spacing.md) {
                TimeStepper(title: String(localized: "开始"), minutes: schedule.startMinutes, range: (6 * 60)...(23 * 60))
                TimeStepper(title: String(localized: "结束"), minutes: schedule.endMinutes, range: (7 * 60)...(24 * 60))
            }
            Stepper(value: schedule.capacity, in: GroupSchedule.capacityRange(coached: coached), step: coached ? 1 : 2) {
                Text("每场 \(schedule.wrappedValue.capacity) 个名额")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
            }
            BrutalTextField(label: String(localized: "费用说明（选填）"), placeholder: "",
                            text: Binding(get: { schedule.wrappedValue.feeNote ?? "" },
                                          set: { schedule.wrappedValue.feeNote = $0.isEmpty ? nil : $0 }),
                            characterLimit: GroupSchedule.feeNoteLimit, axis: .vertical)
            if schedules.count > 1 {
                Button("删掉这个场次", role: .destructive) {
                    schedules.removeAll { $0.id == schedule.wrappedValue.id }
                }
                .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
            }
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    /// 允许不注册的人报名：每场访客上限、报名链接（复制、重置）
    private func guestSignupEditor(_ group: PlayGroup) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            VStack(spacing: 0) {
                Toggle(isOn: $guestsAllowed.animation(AppTheme.Motion.standard)) {
                    Text("允许不注册的人报名")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                }
                .tint(AppTheme.Colors.success)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: 60)
                if guestsAllowed {
                    InsetDivider()
                    Stepper(value: Binding(get: { shownGuestLimit }, set: { guestLimit = $0 }), in: 1...maxCapacity) {
                        Text("每场访客最多 \(shownGuestLimit) 人")
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundStyle(AppTheme.Colors.ink)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(minHeight: 60)
                    InsetDivider()
                    // 链接在第一次打开、保存后才有
                    if group.guestSignup?.allowed == true, let link = group.guestSignup?.link {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                IconTile(systemName: "link", fill: AppTheme.Colors.sky, size: 36)
                                Text(link.absoluteString.replacingOccurrences(of: "https://", with: ""))
                                    .font(AppTheme.Typography.bodyBold)
                                    .foregroundStyle(AppTheme.Colors.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Button {
                                    UIPasteboard.general.string = link.absoluteString
                                    appState.showToast(String(localized: "已复制报名链接"), style: .success)
                                } label: {
                                    Label("复制报名链接", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: true))
                                Button("重置链接") { confirmsResetLink = true }
                                    .buttonStyle(TextActionStyle())
                            }
                        }
                        .padding(AppTheme.Spacing.md)
                    } else {
                        Text("保存后就有报名链接")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.Spacing.md)
                    }
                }
            }
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            Text("关掉后链接失效")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
        .confirmationDialog("重置报名链接？", isPresented: $confirmsResetLink, titleVisibility: .visible) {
            Button("重置链接", role: .destructive) { resetGuestLink(group.id) }
        } message: {
            Text("旧链接会马上失效")
        }
    }

    private func resetGuestLink(_ groupId: String) {
        Task {
            do {
                try await groupManager.resetGuestLink(groupId)
                appState.showToast(String(localized: "已换新链接，旧链接已失效"), style: .success)
            } catch {
                appState.showError(error)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let editingGroupId, let group = groupManager.group(id: editingGroupId) {
            name = group.name
            summary = group.summary
            schedules = group.schedules.isEmpty ? schedules : group.schedules
            lowerLevel = group.levelRange.lowerBound
            upperLevel = group.levelRange.upperBound
            joinPolicy = group.joinPolicy
            coached = group.isCoached
            venueId = group.venueId
            extraVenueIds = Array(group.venueIds.dropFirst())
            guestsAllowed = group.guestSignup?.allowed ?? false
            guestLimit = group.guestSignup?.limit
            return
        }
        venueId = initialVenueId ?? locationManager.favoriteCourtIds.first { locationManager.court(id: $0) != nil }
        let level = appState.currentUser?.level(for: audience) ?? 4
        lowerLevel = max(1, level - 2)
        upperLevel = min(9, level + 2)
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let editingGroupId {
                    let guestsBefore = editingGroup?.guestSignup
                    try await groupManager.update(editingGroupId, name: name, schedules: schedules, levelRange: lowerLevel...upperLevel,
                                                  joinPolicy: joinPolicy, summary: summary, coached: coached, venueIds: allVenueIds)
                    if guestsAllowed != (guestsBefore?.allowed ?? false) || guestLimit != guestsBefore?.limit {
                        try await groupManager.setGuestSignup(editingGroupId, allowed: guestsAllowed, limit: guestLimit)
                    }
                    appState.showToast(String(localized: "已保存"), style: .success)
                    router.pop()
                    return
                }
                guard let venueId else { return }
                let group = try await groupManager.create(name: name, venueId: venueId, schedules: schedules,
                                                          levelRange: lowerLevel...upperLevel, joinPolicy: joinPolicy, summary: summary,
                                                          audience: audience, coached: coached, otherVenueIds: extraVenueIds)
                Haptics.success()
                appState.showToast(String(localized: "已建群，群号 \(group.inviteCode)，可以分享到微信"), style: .success)
                router.pop()
                router.open(.group(id: group.id))
            } catch {
                appState.showError(error)
            }
        }
    }
}

// MARK: - 球群规则（“?”里的要点）

enum GroupRules {
    static var points: [String] {
        [String(localized: "固定时间、固定球馆的局。"),
         String(localized: "一键报名，满了自动候补。"),
         String(localized: "有人退出，候补按顺序递补，并通知你。"),
         String(localized: "开场前 2 小时内退出，算临时取消。")]
    }

    static func joinPoints(_ group: PlayGroup) -> [String] {
        var points: [String] = []
        if group.joinPolicy == .approval {
            points.append(String(localized: "这个群需要组织者同意。"))
        } else if !group.isCoached {
            points.append(String(localized: "水平符合就能直接加入。"))
        }
        points.append(String(localized: "加入后就能报名每周的场次。"))
        return points + Self.points
    }
}
