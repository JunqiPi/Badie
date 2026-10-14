import SwiftUI

struct RoomLobbyView: View {
    let roomId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var friendManager: FriendManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var showInvite = false
    @State private var invitees: Set<String> = []
    @State private var kickTarget: RoomParticipant?
    @State private var showLeaveConfirm = false
    @State private var showEditDetails = false
    @State private var isWorking = false

    private var room: Room? {
        roomManager.myRooms.first { $0.id == roomId } ?? roomManager.room(id: roomId)
    }

    private var me: String? { appState.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: room?.visibility == .publicListing ? "公开球局" : "私密房间") {
                if let room {
                    ShareLink(item: room.inviteText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .frame(width: 44, height: 44)
                            .sticker(AppTheme.Colors.surface, radius: 14, shadow: AppTheme.Elevation.low)
                    }
                    .accessibilityLabel("分享房间")
                }
            }
            if let room {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        statusBanner(room)
                        codeCard(room)
                        detailsCard(room)
                        seatsSection(room)
                        if !room.waitlist.isEmpty { waitlistSection(room) }
                        if !room.invitedUserIds.isEmpty { invitedSection(room) }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                footer(room)
            } else {
                Spacer()
                EmptyStateView(icon: "door.left.hand.closed", title: "房间不存在或已关闭")
                Spacer()
            }
        }
        .sheet(isPresented: $showInvite) {
            if let room {
                FriendPickerSheet(
                    title: "邀请好友",
                    maxSelection: room.openSeats,
                    excluded: Set(room.participants.map(\.userId) + room.invitedUserIds),
                    selection: $invitees
                ) {
                    Task { await invite(room) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showEditDetails) {
            if let room {
                RoomDetailsEditor(room: room)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("移出 \(kickTarget?.nickname ?? "")？", isPresented: Binding(get: { kickTarget != nil }, set: { if !$0 { kickTarget = nil } })) {
            Button("取消", role: .cancel) { kickTarget = nil }
            Button("移出", role: .destructive) {
                if let target = kickTarget, let room {
                    Task { await kick(target, from: room) }
                }
                kickTarget = nil
            }
        } message: {
            Text("对方会收到通知，候补中的球友会自动递补。")
        }
        .alert(leaveTitle, isPresented: $showLeaveConfirm) {
            Button("取消", role: .cancel) {}
            Button(isOwner ? "解散" : "退出", role: .destructive) {
                Task { await leave() }
            }
        }
    }

    private var isOwner: Bool { room.map { $0.ownerId == me } ?? false }

    private var leaveTitle: String { isOwner ? "解散房间？所有人都会收到通知" : "退出房间？" }

    // MARK: Sections

    @ViewBuilder
    private func statusBanner(_ room: Room) -> some View {
        switch room.status {
        case .open:
            if room.visibility == .privateRoom {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let minutes = max(0, Int(room.expiresAt().timeIntervalSince(context.date) / 60))
                    NoticeBanner(icon: "timer", text: "30 分钟无活动会自动关闭 · 剩约 \(minutes) 分钟", tint: AppTheme.Colors.butter)
                }
            }
        case .started(let gameId):
            Button {
                router.open(.game(id: gameId))
            } label: {
                NoticeBanner(icon: "checkmark.seal.fill", text: "球局已开始组队，点击查看球局详情", tint: AppTheme.Colors.lime)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        case .closed(let reason):
            NoticeBanner(icon: "xmark.octagon.fill", text: reason.message, tint: AppTheme.Colors.surfaceMuted)
        }
    }

    private func codeCard(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("房间码")
                    .font(AppTheme.Typography.overline)
                Spacer()
                TagPill(text: "\(room.mode.title) · \(room.participants.count)/\(room.requiredPlayerCount)", fill: .white)
            }
            HStack(spacing: 6) {
                ForEach(Array(room.code.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(.title, design: .monospaced, weight: .black))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .sticker(.white, radius: 12, shadow: .zero, stroke: Color(hex: 0x17140F))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("房间码 \(room.code.map(String.init).joined(separator: " "))")
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    UIPasteboard.general.string = room.code
                    appState.showToast("房间码已复制", style: .success)
                } label: {
                    Label("复制", systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: true))
                ShareLink(item: room.inviteText) {
                    Label("发给好友", systemImage: "paperplane.fill")
                }
                .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .small, fullWidth: true))
            }
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .card(AppTheme.Colors.lavender)
    }

    private func detailsCard(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(icon: "clock.fill", tint: AppTheme.Colors.peach,
                    title: room.slot?.formattedFull ?? "时间待定",
                    subtitle: room.slot.map { "共 \($0.formattedDuration)" } ?? "房主可以随时设置")
            InsetDivider()
            InfoRow(icon: "mappin.and.ellipse", tint: AppTheme.Colors.sky,
                    title: room.court?.name ?? "球馆待定",
                    subtitle: room.court.map { "\($0.formattedDistance(from: locationManager.coordinate)) · \($0.address)" })
            InsetDivider()
            InfoRow(icon: "chart.bar.fill", tint: AppTheme.Colors.lavender,
                    title: room.levelRangeText,
                    subtitle: room.tags.isEmpty ? nil : room.tags.map(\.rawValue).joined(separator: " · "))
            if let cost = room.costEstimate {
                InsetDivider()
                InfoRow(icon: Money.icon(for: cost.currencyCode), tint: AppTheme.Colors.butter,
                        title: cost.perPerson == nil ? "费用待定" : "AA 约 \(cost.perPersonText)", subtitle: cost.breakdownText)
            }
            if !room.note.isEmpty {
                InsetDivider()
                InfoRow(icon: "text.bubble.fill", tint: AppTheme.Colors.mint, title: room.note)
            }
            if isOwner && room.status.isOpen {
                InsetDivider()
                MenuRow(icon: "pencil", tint: AppTheme.Colors.lime, title: "编辑时间和球馆") {
                    showEditDetails = true
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private func seatsSection(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(title: "座位", detail: room.isReady ? "已满员" : "还差 \(room.openSeats) 人")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.md), GridItem(.flexible(), spacing: AppTheme.Spacing.md)],
                      spacing: AppTheme.Spacing.md) {
                ForEach(room.participants) { participant in
                    seatCard(participant, room: room)
                }
                ForEach(0..<room.openSeats, id: \.self) { _ in
                    Button {
                        invitees = []
                        showInvite = true
                    } label: {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .heavy))
                            Text(room.contains(me ?? "") ? "邀请好友" : "空位")
                                .font(AppTheme.Typography.footnoteBold)
                        }
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 124)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .strokeBorder(AppTheme.Colors.stroke, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!room.contains(me ?? "") || !room.status.isOpen)
                    .accessibilityLabel("空位，邀请好友")
                }
            }
        }
    }

    private func seatCard(_ participant: RoomParticipant, room: Room) -> some View {
        let isRoomOwner = participant.userId == room.ownerId
        let isMe = participant.userId == me
        return VStack(spacing: AppTheme.Spacing.sm) {
            AvatarView(participant: participant, size: 52)
            Text(isMe ? "我" : participant.nickname)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.onAccent)
                .lineLimit(1)
            HStack(spacing: 4) {
                LevelBadge(tier: participant.tier, showsName: false, compact: true)
                if isRoomOwner { TagPill(text: "房主", fill: AppTheme.Colors.butter) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 124)
        .padding(.vertical, AppTheme.Spacing.sm)
        .sticker(isMe ? AppTheme.Colors.lime : AppTheme.Colors.paletteColor(participant.avatar.paletteIndex + 1), radius: AppTheme.Radius.lg)
        .overlay(alignment: .topTrailing) {
            if isOwner && !isMe && room.status.isOpen {
                Button {
                    kickTarget = participant
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(AppTheme.Colors.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white))
                        .overlay(Circle().strokeBorder(Color(hex: 0x17140F), lineWidth: 1.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("移出 \(participant.nickname)")
            }
        }
        .onTapGesture {
            if !isMe { appState.showPlayer(participant.userId) }
        }
        .accessibilityElement(children: .contain)
    }

    private func waitlistSection(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: "候补", detail: "\(room.waitlist.count) 人 · 有人退出自动递补")
            ForEach(Array(room.waitlist.enumerated()), id: \.element.id) { index, participant in
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("\(index + 1)")
                        .font(AppTheme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    AvatarView(participant: participant, size: 32)
                        .opensProfile(participant.userId)
                    Text(participant.userId == me ? "我" : participant.nickname)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Spacer()
                    LevelBadge(tier: participant.tier, showsName: false, compact: true)
                }
                .padding(AppTheme.Spacing.md)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
            }
        }
    }

    private func invitedSection(_ room: Room) -> some View {
        let names = room.invitedUserIds.compactMap { friendManager.user(id: $0)?.nickname }
        return NoticeBanner(icon: "paperplane.fill", text: "已邀请 \(names.joined(separator: "、"))，等待回应…", tint: AppTheme.Colors.sky)
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ room: Room) -> some View {
        if room.status.isOpen {
            VStack(spacing: AppTheme.Spacing.sm) {
                if isOwner {
                    Button {
                        Task { await start(room) }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            if isWorking { LoadingDots() }
                            Text(startTitle(room))
                        }
                    }
                    .buttonStyle(.brutalPrimary)
                    .disabled(!room.isReady || room.court == nil || room.slot == nil || isWorking)
                    Button("解散房间") { showLeaveConfirm = true }
                        .buttonStyle(TextActionStyle(color: AppTheme.Colors.danger))
                } else if room.contains(me ?? "") || room.isWaitlisted(me ?? "") {
                    Text(room.isWaitlisted(me ?? "") ? "你在候补名单中，有空位会自动加入并通知你" : "等待房主开始，满员后会自动组局")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    Button(room.isWaitlisted(me ?? "") ? "退出候补" : "退出房间") { showLeaveConfirm = true }
                        .buttonStyle(.brutalSecondary)
                } else {
                    joinButton(room)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
            .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { InsetDivider() }
        }
    }

    @ViewBuilder
    private func joinButton(_ room: Room) -> some View {
        let level = appState.currentUser?.displayLevel ?? 0
        if room.visibility == .publicListing && !room.accepts(level: level) {
            Text("这个局要求 \(room.levelRangeText)，你的等级是 Lv.\(level)")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.danger)
        }
        Button {
            Task { await join(room) }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                if isWorking { LoadingDots() }
                Text(room.isFull ? "加入候补" : "加入球局" + (room.costEstimate.flatMap { $0.perPerson == nil ? nil : " · \($0.perPersonText)" } ?? ""))
            }
        }
        .buttonStyle(.brutalPrimary)
        .disabled(isWorking || (room.visibility == .publicListing && !room.accepts(level: level)))
    }

    private func startTitle(_ room: Room) -> String {
        if !room.isReady { return "还差 \(room.openSeats) 人才能开始" }
        if room.court == nil || room.slot == nil { return "先设置时间和球馆" }
        return "开始球局"
    }

    // MARK: Actions

    private func invite(_ room: Room) async {
        let ids = Array(invitees)
        showInvite = false
        guard !ids.isEmpty else { return }
        do {
            try await roomManager.invite(ids, to: room)
            appState.showToast("邀请已发送", style: .success)
        } catch {
            appState.showError(error)
        }
    }

    private func kick(_ participant: RoomParticipant, from room: Room) async {
        do {
            try await roomManager.kick(participant, from: room)
            appState.showToast("已移出 \(participant.nickname)")
        } catch {
            appState.showError(error)
        }
    }

    private func leave() async {
        guard let room else { return }
        do {
            try await roomManager.leave(room)
            appState.showToast(isOwner ? "房间已解散" : "已退出")
            router.pop()
        } catch {
            appState.showError(error)
        }
    }

    private func join(_ room: Room) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let joined = try await roomManager.joinPublic(room)
            appState.showToast(joined.isWaitlisted(me ?? "") ? "已加入候补，有空位会通知你" : "已加入球局", style: .success)
        } catch {
            appState.showError(error)
        }
    }

    private func start(_ room: Room) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let game = try await roomManager.start(room)
            Haptics.success()
            router.pop()
            router.open(.game(id: game.id), in: .games)
        } catch {
            appState.showError(error)
        }
    }
}

// MARK: - 编辑房间时间与球馆

struct RoomDetailsEditor: View {
    let room: Room

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var roomManager: RoomManager
    @Environment(\.dismiss) private var dismiss

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var startMinutes = 19 * 60
    @State private var endMinutes = 21 * 60
    @State private var courtId: String?
    @State private var showCourtPicker = false
    @EnvironmentObject private var locationManager: LocationManager

    private var slot: TimeSlot? {
        TimeSlot.on(day, startHour: startMinutes / 60, startMinute: startMinutes % 60, endHour: endMinutes / 60, endMinute: endMinutes % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            HStack {
                Text("时间和球馆")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            DateStrip(days: (0..<TimeSlotConstants.maximumDaysAhead).compactMap {
                Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date()))
            }, selection: $day)
            HStack(spacing: AppTheme.Spacing.md) {
                TimeStepper(title: "开始", minutes: $startMinutes, range: (6 * 60)...(23 * 60))
                TimeStepper(title: "结束", minutes: $endMinutes, range: (7 * 60)...(24 * 60))
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            if let message = slot?.validate().errorMessage {
                Text(message)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .padding(.horizontal, AppTheme.Spacing.screen)
            }
            Button {
                showCourtPicker = true
            } label: {
                InfoRow(icon: "sportscourt.fill", tint: AppTheme.Colors.sky,
                        title: courtId.flatMap { locationManager.court(id: $0)?.name } ?? "选择球馆",
                        subtitle: "点按更换")
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.Spacing.screen)
            Spacer()
            Button("保存") {
                Task {
                    do {
                        try await roomManager.updateDetails(room, court: courtId.flatMap { locationManager.court(id: $0) }, slot: slot)
                        appState.showToast("已更新", style: .success)
                        dismiss()
                    } catch {
                        appState.showError(error)
                    }
                }
            }
            .buttonStyle(.brutalPrimary)
            .disabled(slot?.validate().isValid != true)
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showCourtPicker) {
            CourtPickerSheet(selectedId: $courtId, slot: slot)
        }
        .onAppear {
            courtId = room.court?.id ?? locationManager.nearbyCourts.first?.id
            if let slot = room.slot {
                let calendar = Calendar.current
                day = calendar.startOfDay(for: slot.startTime)
                startMinutes = calendar.component(.hour, from: slot.startTime) * 60 + calendar.component(.minute, from: slot.startTime)
                endMinutes = calendar.isDate(slot.endTime, inSameDayAs: slot.startTime)
                    ? calendar.component(.hour, from: slot.endTime) * 60 + calendar.component(.minute, from: slot.endTime)
                    : 24 * 60
            } else {
                let suggested = TimeSlot.suggestedDefault()
                day = Calendar.current.startOfDay(for: suggested.startTime)
            }
        }
    }
}
