import SwiftUI

/// 输入 6 位房间码加入
struct JoinRoomView: View {
    var initialCode: String = ""

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var groupManager: GroupManager

    @State private var code = ""
    @State private var errorText: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "房间码 / 群号"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("输入好友发来的\n6 位房间码或群号")
                            .font(AppTheme.Typography.title)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !appState.isRemote {
                            Text("房间码由字母和数字组成，不含 0、O、1、I、L")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                    }
                    ZStack {
                        TextField("", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .focused($focused)
                            .opacity(0.02)
                            .onChange(of: code) { _, value in
                                let normalized = Room.normalize(value)
                                if normalized != value { code = normalized }
                                errorText = nil
                                if normalized.count == Room.codeLength { Task { await join() } }
                            }
                            .accessibilityLabel("房间码")
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(0..<Room.codeLength, id: \.self) { index in
                                let characters = Array(code)
                                Text(index < characters.count ? String(characters[index]) : "")
                                    .font(.system(.title, design: .monospaced, weight: .black))
                                    .foregroundStyle(AppTheme.Colors.ink)
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .sticker(index == characters.count && focused ? AppTheme.Colors.lime : AppTheme.Colors.surface,
                                             radius: 14, shadow: index < characters.count ? AppTheme.Elevation.low : .zero,
                                             stroke: errorText == nil ? AppTheme.Colors.stroke : AppTheme.Colors.danger)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle.fill")
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }

                    Button {
                        if let pasted = UIPasteboard.general.string {
                            code = Room.normalize(pasted)
                        }
                    } label: {
                        Label("粘贴房间码", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: false))
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.md)
            }
            Button {
                Task { await join() }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isWorking { LoadingDots() }
                    Text("加入")
                }
            }
            .buttonStyle(.brutalPrimary)
            .disabled(code.count != Room.codeLength || isWorking)
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .onAppear {
            if code.isEmpty { code = Room.normalize(initialCode) }
            focused = true
        }
    }

    private func join() async {
        guard code.count == Room.codeLength, !isWorking else { return }
        // 正式后端的房间码和群号同一套字母，交给服务器查
        guard appState.isRemote || Room.isValidCode(code) else {
            errorText = String(localized: "房间码格式不对，请检查是否输入了 0/O/1/I/L")
            Haptics.error()
            return
        }
        // 群号：打开球群页面（在那里加入）
        isWorking = true
        let found = await groupManager.find(code: code)
        isWorking = false
        if let group = found {
            Haptics.success()
            router.pop()
            router.open(.group(id: group.id))
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let room = try await roomManager.join(code: code)
            Haptics.success()
            router.pop()
            router.open(.room(id: room.id))
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
            Haptics.error()
        }
    }
}

// MARK: - 附近公开球局列表

struct PublicGamesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var roomManager: RoomManager
    @EnvironmentObject private var locationManager: LocationManager

    @State private var modeFilter: GameMode?
    @State private var tagFilter: RoomTag?
    @State private var onlyMyLevel = false

    private var rooms: [Room] {
        let level = appState.currentUser?.displayLevel ?? 0
        return roomManager.publicRooms.filter { room in
            (modeFilter == nil || room.mode == modeFilter) &&
                (tagFilter == nil || room.tags.contains(tagFilter!)) &&
                (!onlyMyLevel || room.accepts(level: level))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "附近球局"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ChoiceChip(title: String(localized: "适合我的水平"), icon: "chart.bar.fill", isSelected: onlyMyLevel) { onlyMyLevel.toggle() }
                            ForEach(GameMode.allCases) { mode in
                                ChoiceChip(title: mode.title, isSelected: modeFilter == mode) {
                                    modeFilter = modeFilter == mode ? nil : mode
                                }
                            }
                            ForEach(RoomTag.allCases) { tag in
                                ChoiceChip(title: tag.title, icon: tag.icon, isSelected: tagFilter == tag, tint: AppTheme.Colors.mint) {
                                    tagFilter = tagFilter == tag ? nil : tag
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.screen)
                        .padding(.vertical, 4)
                    }
                    VStack(spacing: AppTheme.Spacing.md) {
                        if rooms.isEmpty {
                            EmptyStateView(icon: "sportscourt", title: String(localized: "没有符合条件的球局"),
                                           message: String(localized: "换个筛选条件，或者自己发起一个。"), tint: AppTheme.Colors.peach,
                                           actionTitle: String(localized: "发起球局")) {
                                router.open(.createRoom(modeFilter, invitee: nil), in: .games)
                            }
                            .card()
                        }
                        ForEach(rooms) { room in
                            Button {
                                router.open(.room(id: room.id))
                            } label: {
                                PublicRoomCard(room: room,
                                               distanceText: room.court.map { $0.formattedDistance(from: locationManager.coordinate) },
                                               currentUserId: appState.currentUser?.id, width: nil)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                }
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .refreshable { roomManager.reload() }
        }
    }
}

// MARK: - 好友多选（邀请进房间）

struct FriendPickerSheet: View {
    let title: String
    var maxSelection: Int
    var excluded: Set<String> = []
    @Binding var selection: Set<String>
    let onConfirm: () -> Void

    @EnvironmentObject private var friendManager: FriendManager
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var friends: [User] {
        friendManager.searchFriends(query: query).filter { !excluded.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack {
                Text(title)
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.top, AppTheme.Spacing.xl)
            SearchField(text: $query, placeholder: String(localized: "搜索球友昵称"))
            Text("最多可邀请 \(maxSelection) 人 · 已选 \(selection.count)")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 0) {
                    if friends.isEmpty {
                        EmptyStateView(icon: "person.2", title: String(localized: "没有可邀请的球友"),
                                       message: String(localized: "先去“消息 - 球友”添加一些球友吧。"))
                    }
                    ForEach(friends) { friend in
                        let selected = selection.contains(friend.id)
                        Button {
                            Haptics.selection()
                            if selected {
                                selection.remove(friend.id)
                            } else if selection.count < maxSelection {
                                selection.insert(friend.id)
                            }
                        } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                AvatarView(user: friend, size: 44)
                                    .opensProfile(friend.id, allowsInvite: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.nickname)
                                        .font(AppTheme.Typography.bodyBold)
                                        .foregroundStyle(AppTheme.Colors.ink)
                                    Text("\(friend.displayLevelText) · \(friend.publicSummary)")
                                        .font(AppTheme.Typography.footnote)
                                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(selected ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                            }
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .contentShape(Rectangle())
                            .opacity(!selected && selection.count >= maxSelection ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            Button("邀请 \(selection.count) 位球友", action: onConfirm)
                .buttonStyle(.brutalPrimary)
                .disabled(selection.isEmpty)
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            TextField(placeholder, text: $text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: 48)
        .sticker(AppTheme.Colors.surface, radius: 14, shadow: .zero)
    }
}
