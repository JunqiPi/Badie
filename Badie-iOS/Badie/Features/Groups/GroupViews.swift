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
                TagPill(text: group.levelText, icon: "chart.bar.fill", fill: AppTheme.Colors.surfaceMuted, foreground: AppTheme.Colors.ink)
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
                IconButton(systemName: "plus", accessibilityLabel: String(localized: "建一个球群")) {
                    router.open(.createGroup(venueId: nil))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    NoticeBanner(icon: "list.bullet.clipboard.fill",
                                 text: String(localized: "固定时间、固定球馆的局。报名在 App 里点一下，满了自动候补，有人退出自动递补，不用在微信群里接龙。"),
                                 tint: AppTheme.Colors.sky)
                    if !groupManager.myGroups.isEmpty {
                        section(String(localized: "我加入的"), groups: groupManager.myGroups)
                    }
                    let nearby = groupManager.groups(near: locationManager.coordinate, radiusKm: locationManager.preferences.travelRadiusKm)
                        .filter { group in !groupManager.myGroups.contains { $0.id == group.id } }
                    if nearby.isEmpty {
                        EmptyStateView(icon: "person.3", title: String(localized: "附近还没有球群"),
                                       message: String(localized: "你常和固定的人打球的话，建一个群，把报名从微信群搬过来。"),
                                       tint: AppTheme.Colors.lavender, actionTitle: String(localized: "建一个球群")) {
                            router.open(.createGroup(venueId: nil))
                        }
                    } else {
                        section(String(localized: "附近的球群"), groups: nearby)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
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
    @State private var sessionDetail: GroupSession?

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
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
            } else {
                EmptyStateView(icon: "person.3", title: String(localized: "没有找到这个球群"))
                Spacer()
            }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .confirmationDialog("退出这个球群？", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("退出", role: .destructive) {
                do {
                    try groupManager.leave(groupId)
                    appState.showToast(String(localized: "已退出，已报名的场次也一并取消"))
                    router.pop()
                } catch {
                    appState.showError(error)
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
            if !group.summary.isEmpty {
                Text(group.summary)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 6) {
                TagPill(text: group.levelText, icon: "chart.bar.fill", fill: AppTheme.Colors.lime)
                TagPill(text: group.joinPolicy.title, icon: "person.badge.plus", fill: AppTheme.Colors.surfaceMuted,
                        foreground: AppTheme.Colors.ink)
                TagPill(text: String(localized: "群号 \(group.inviteCode)"), icon: "number", fill: AppTheme.Colors.surfaceMuted,
                        foreground: AppTheme.Colors.ink)
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

    // MARK: Join

    private func joinCard(_ group: PlayGroup) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let me, group.isPending(me) {
                Label("已申请加入，等组织者同意", systemImage: "hourglass")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
            } else {
                Text(group.joinPolicy == .open ? String(localized: "水平符合就能直接加入，加入后就能报名每周的场次。") : String(localized: "这个群需要组织者同意。"))
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Button {
                    do {
                        let joined = try groupManager.join(group.id)
                        Haptics.success()
                        appState.showToast(joined.isMember(me ?? "") ? String(localized: "已加入「\(joined.name)」") : String(localized: "已提交申请，组织者同意后通知你"),
                                           style: .success)
                    } catch {
                        appState.showError(error)
                    }
                } label: {
                    Text(group.joinPolicy == .open ? String(localized: "加入球群") : String(localized: "申请加入"))
                }
                .buttonStyle(.brutalPrimary)
            }
            if !group.schedules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.schedules) { schedule in
                        Label("\(schedule.weekdayTitle) \(schedule.timeText) · \(schedule.capacity) 个名额", systemImage: "calendar")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
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
            SectionTitle(title: String(localized: "接下来的场次"), detail: String(localized: "开场前 2 小时内退出算临时取消"))
            if sessions.isEmpty {
                Text("未来两周没有场次")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            ForEach(sessions) { session in
                SessionRow(session: session, userId: me ?? "") {
                    sessionDetail = session
                }
            }
        }
    }

    // MARK: Members

    private func membersSection(_ group: PlayGroup) -> some View {
        let members = group.memberIds.compactMap { groupManager.user($0) }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: String(localized: "组织者与常来的人"), detail: nil)
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
                            try? groupManager.approve(userId, in: group.id)
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
    let onOpen: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var groupManager: GroupManager

    var body: some View {
        let status = session.status(of: userId)
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.slot.formattedFull)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
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
        .padding(AppTheme.Spacing.md)
        .sticker(status == .signedUp ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface,
                 radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func signUp() {
        do {
            switch try groupManager.signUp(session.id) {
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

    private func cancel() {
        let late = session.slot.startTime.timeIntervalSince(Date()) < GroupSession.lateCancellationWindow
        do {
            try groupManager.cancelSignup(session.id)
            appState.showToast(late ? String(localized: "已取消（开场前 2 小时内，计入临时取消）") : String(localized: "已取消，名额让给候补"))
        } catch {
            appState.showError(error)
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
                            Text(groupManager.venue(of: group)?.name ?? group.name)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        Spacer()
                        IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                    }
                    .padding(.top, AppTheme.Spacing.xl)
                    roster(title: String(localized: "已报名 \(session.signedUp.count)/\(session.capacity)"), ids: session.signedUp)
                    if !session.waitlist.isEmpty {
                        roster(title: String(localized: "候补（有人退出按顺序递补）"), ids: session.waitlist)
                    }
                    if let me = appState.currentUser?.id, group.isOrganizer(me), !session.isCancelled {
                        Button("取消这一场") {
                            do {
                                try groupManager.cancelSession(session.id)
                                appState.showToast(String(localized: "已取消，已报名的人会收到通知"))
                                dismiss()
                            } catch {
                                appState.showError(error)
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

    private func roster(title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, userId in
                    if let user = groupManager.user(userId) {
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
}

// MARK: - 建群

struct CreateGroupView: View {
    var initialVenueId: String?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var name = ""
    @State private var summary = ""
    @State private var venueId: String?
    @State private var weekday = 5
    @State private var startMinutes = 19 * 60 + 30
    @State private var endMinutes = 22 * 60
    @State private var capacity = 12
    @State private var lowerLevel = 1
    @State private var upperLevel = 9
    @State private var joinPolicy: PlayGroup.JoinPolicy = .open
    @State private var showVenuePicker = false
    @State private var didSetup = false

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

    private var validationMessage: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !PlayGroup.nameLimit.contains(trimmed.count) { return String(localized: "球群名称需要 2–20 个字") }
        if venue == nil { return String(localized: "选择固定的球馆") }
        if endMinutes - startMinutes < 60 { return String(localized: "每场至少 1 小时") }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "建一个球群"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    section(String(localized: "名称")) {
                        BrutalTextField(label: String(localized: "球群名称"), placeholder: String(localized: "例：周四晚双打群"), text: $name, characterLimit: 20)
                        BrutalTextField(label: String(localized: "介绍（可选）"), placeholder: String(localized: "例：轮换上场，新手友好；费用按人头在前台付"),
                                        text: $summary, characterLimit: 120, axis: .vertical)
                    }
                    section(String(localized: "固定球馆")) {
                        Button {
                            showVenuePicker = true
                        } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                IconTile(systemName: "sportscourt.fill", fill: AppTheme.Colors.sky, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(venue?.name ?? String(localized: "选择球馆"))
                                        .font(AppTheme.Typography.bodyBold)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                    Text(venue?.address ?? String(localized: "搜索球馆名、简称或地址"))
                                        .font(AppTheme.Typography.footnote)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
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
                    section(String(localized: "每周固定场次")) {
                        HStack(spacing: 6) {
                            ForEach(weekdays.indices, id: \.self) { index in
                                ChoiceChip(title: weekdays[index].1, isSelected: weekday == weekdays[index].0) {
                                    weekday = weekdays[index].0
                                }
                            }
                        }
                        HStack(spacing: AppTheme.Spacing.md) {
                            TimeStepper(title: String(localized: "开始"), minutes: $startMinutes, range: (6 * 60)...(23 * 60))
                            TimeStepper(title: String(localized: "结束"), minutes: $endMinutes, range: (7 * 60)...(24 * 60))
                        }
                        Stepper(value: $capacity, in: GroupSchedule.capacityRange, step: 2) {
                            Text("每场 \(capacity) 个名额，满了自动候补")
                                .font(AppTheme.Typography.bodyBold)
                                .foregroundStyle(AppTheme.Colors.ink)
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
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            VStack(spacing: AppTheme.Spacing.xs) {
                if let message = validationMessage {
                    Text(message)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.danger)
                }
                Button("建群") { create() }
                    .buttonStyle(.brutalPrimary)
                    .disabled(validationMessage != nil)
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
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            venueId = initialVenueId ?? locationManager.favoriteCourtIds.first { locationManager.court(id: $0) != nil }
            let level = appState.currentUser?.displayLevel ?? 4
            lowerLevel = max(1, level - 2)
            upperLevel = min(9, level + 2)
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

    private func create() {
        guard let venueId else { return }
        let schedule = GroupSchedule(id: "s1", weekday: weekday, startMinutes: startMinutes, endMinutes: endMinutes,
                                     capacity: capacity, feeNote: nil)
        do {
            let group = try groupManager.create(name: name, venueId: venueId, schedules: [schedule],
                                                levelRange: lowerLevel...upperLevel, joinPolicy: joinPolicy, summary: summary)
            Haptics.success()
            appState.showToast(String(localized: "已建群，群号 \(group.inviteCode)，可以分享到微信"), style: .success)
            router.pop()
            router.open(.group(id: group.id))
        } catch {
            appState.showError(error)
        }
    }
}
