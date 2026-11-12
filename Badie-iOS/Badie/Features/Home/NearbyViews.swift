import PhotosUI
import SwiftUI

// MARK: - 常在附近：卡片

/// 常在附近的人：和按天的卡片同一个样子，只是不写时间，写 TA 常去的球馆和常打的项目
struct NearbyCardView: View {
    let user: User?
    let card: MockBackend.NearbyPlayer
    /// 第一行显示的球馆（选了球馆筛选时是选的那家）
    var venue: MockBackend.DayCandidate.Venue?
    var onProfile: (() -> Void)?

    var body: some View {
        let photo = user.flatMap { AvatarPhotos.cardImage(userId: $0.id, avatar: $0.avatar) }
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let user {
                    CardCover(color: user.cardColor, photo: photo) {
                        AvatarView(user: user, size: 140)
                            .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
                    }
                } else {
                    AppTheme.Colors.surfaceMuted
                }
            }
            .overlay(alignment: .topLeading) {
                NearbyChip().padding(AppTheme.Spacing.md)
            }
            .overlay(alignment: .bottomLeading) {
                if let user, photo != nil {
                    AvatarView(user: user, size: 64)
                        .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 2, y: 3))
                        .padding(.leading, AppTheme.Spacing.lg)
                        .offset(y: 32)
                }
            }
            .zIndex(1)
            info
                .padding(.top, photo != nil ? 36 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let user {
                HStack(spacing: AppTheme.Spacing.sm) {
                    NicknameText(user: user)
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    LevelBadge(tier: user.displayTier)
                    if card.recentNoShows == 0 { ReliableBadge() }
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if let name = (venue ?? card.venues.first)?.name {
                    Label(String(localized: "常去 \(name)"), systemImage: "mappin.and.ellipse").lineLimit(1)
                }
                if let mode = card.preferredMode {
                    Label(mode.title, systemImage: "figure.badminton")
                }
                if card.recentNoShows > 0 {
                    Label(String(localized: "近 180 天爽约 \(card.recentNoShows) 次"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }
            .font(AppTheme.Typography.bodyBold)
            .foregroundStyle(AppTheme.Colors.ink)
            if let onProfile {
                Button("看资料", action: onProfile)
                    .buttonStyle(TextActionStyle())
            }
        }
        .padding(AppTheme.Spacing.lg)
    }
}

/// 卡片左上角的小标签
struct NearbyChip: View {
    var body: some View {
        TagPill(text: String(localized: "常在附近"), fill: AppTheme.Colors.surface, foreground: AppTheme.Colors.ink)
    }
}

/// 这天的卡片刷完了，接着是常在附近的人（虚线框）
struct NearbyDivider: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("这天的刷完了")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            Text("接着看常在附近打的人")
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).fill(AppTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            .strokeBorder(AppTheme.Colors.stroke, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 第一次右滑前：让附近的人也能看到你 / 加一张照片

struct WishPromptSheet: View {
    enum Kind: String, Identifiable {
        /// 没打开“在同馆常客里显示我”
        case visibility
        /// 没有卡片背景照片
        case photo

        var id: String { rawValue }
    }

    let kind: Kind
    var onConfirm: () -> Void
    var onCancel: () -> Void
    /// 选了照片（只有 .photo）
    var onPhoto: (PhotosPickerItem) -> Void = { _ in }

    @EnvironmentObject private var appState: AppState
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(kind == .visibility ? String(localized: "先让附近的人也能看到你") : String(localized: "加一张照片？"))
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            if kind == .photo, let user = appState.currentUser {
                HStack(spacing: AppTheme.Spacing.md) {
                    AvatarView(user: user, size: 48)
                    Text("别人刷到你时看到的就是这张卡")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.Spacing.md)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
            }
            Spacer(minLength: 0)
            if kind == .photo {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("选照片").frame(maxWidth: .infinity)
                }
                .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                Button("先不加", action: onConfirm)
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
            } else {
                Button("打开", action: onConfirm)
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                Button("不了", action: onCancel)
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onChange(of: photoItem) { _, item in
            if let item { onPhoto(item) }
        }
    }
}

// MARK: - 别人想和我打球

/// 首页“想一起打 N”点开：一次一张，不了 / 好
struct PlayWishSheet: View {
    let wishes: [MockBackend.PlayWish]
    /// 回完一个（accepted = 点了好）
    let onAnswered: (MockBackend.PlayWish, _ accepted: Bool, MockBackend.PlaySuggestion?) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendManager: FriendManager
    @Environment(\.dismiss) private var dismiss
    @State private var answered: Set<String> = []
    @State private var isWorking = false

    private var current: MockBackend.PlayWish? { wishes.first { !answered.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if let wish = current {
                let user = friendManager.user(id: wish.userId)
                Text(String(localized: "\(user?.nickname ?? "")想和你打球"))
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.top, AppTheme.Spacing.xl)
                if let user { miniCard(user, wish: wish) }
                Spacer(minLength: 0)
                HStack(spacing: AppTheme.Spacing.md) {
                    Button("不了") { answer(wish, accept: false) }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
                    Button("好") { answer(wish, accept: true) }
                        .buttonStyle(BrutalButtonStyle(kind: .primary, size: .large, fullWidth: true))
                }
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private func miniCard(_ user: User, wish: MockBackend.PlayWish) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            AvatarView(user: user, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                NicknameText(user: user)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LevelBadge(tier: user.displayTier)
                    if wish.recentNoShows == 0 { ReliableBadge() }
                }
                if let venue = wish.sharedVenue {
                    Text("也常去 \(venue)")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func answer(_ wish: MockBackend.PlayWish, accept: Bool) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let suggestion = try await appState.backend.respondPlayWish(from: wish.userId, accept: accept)
                if accept { Haptics.success() } else { Haptics.selection() }
                answered.insert(wish.id)
                onAnswered(wish, accept, suggestion)
                // 点了好要去“你们都想一起打”；回完了也关掉
                if accept || current == nil { dismiss() }
            } catch {
                appState.showError(error)
            }
        }
    }
}

// MARK: - 你们都想一起打

struct PlayMatch: Identifiable {
    let userId: String
    let suggestion: MockBackend.PlaySuggestion?

    var id: String { userId }
}

/// 双方都想一起打：已经加为球友，推荐一个都常去的球馆和都有空的时间
struct PlayMatchView: View {
    let match: PlayMatch
    /// 点了约球、发消息：由弹出这一页的地方关页面再跳（在卡片页上要连卡片页一起关）
    var onOpen: ((Route, MainTab) -> Void)?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var friendManager: FriendManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let other = friendManager.user(id: match.userId)
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
                Spacer()
            }
            Spacer(minLength: 0)
            HStack(spacing: -24) {
                MyAvatarView(size: 104)
                if let other { AvatarView(user: other, size: 104) }
            }
            .accessibilityHidden(true)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("你们都想一起打")
                    .font(AppTheme.Typography.title)
                Text("已加为球友")
                    .font(AppTheme.Typography.bodyBold)
            }
            .foregroundStyle(AppTheme.Colors.onAccent)
            .multilineTextAlignment(.center)
            if let suggestion = match.suggestion {
                suggestionCard(suggestion)
            }
            Spacer(minLength: 0)
            if let suggestion = match.suggestion, suggestion.startsAt != nil {
                Button("约这个时间") {
                    open(.createRoomWith(invitee: match.userId, venueId: suggestion.venueId,
                                         startsAt: suggestion.startsAt, endsAt: suggestion.endsAt), in: .games)
                }
                .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .large, fullWidth: true))
            } else {
                Button("约球") {
                    open(.createRoomWith(invitee: match.userId, venueId: match.suggestion?.venueId, startsAt: nil, endsAt: nil), in: .games)
                }
                .buttonStyle(BrutalButtonStyle(kind: .inverse, size: .large, fullWidth: true))
            }
            Button("发消息") { open(.chat(userId: match.userId), in: .messages) }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .large, fullWidth: true))
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.vertical, AppTheme.Spacing.lg)
        .background(AppTheme.Colors.lime.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private func suggestionCard(_ suggestion: MockBackend.PlaySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let start = suggestion.startsAt {
                let time = suggestion.endsAt.map { "\(start.formatted(date: .omitted, time: .shortened))–\($0.formatted(date: .omitted, time: .shortened))" }
                    ?? start.formatted(date: .omitted, time: .shortened)
                Text(verbatim: "\(start.formatted(.dateTime.weekday(.abbreviated))) \(time)")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .monospacedDigit()
            }
            if let venue = suggestion.venueName {
                Label(venue, systemImage: "mappin.and.ellipse")
                    .font(suggestion.startsAt == nil ? AppTheme.Typography.headline : AppTheme.Typography.footnoteBold)
                    .foregroundStyle(suggestion.startsAt == nil ? AppTheme.Colors.ink : AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
    }

    private func open(_ route: Route, in tab: MainTab) {
        if let onOpen {
            onOpen(route, tab)
        } else {
            dismiss()
            router.open(route, in: tab)
        }
    }
}
