import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var nickname = ""
    @State private var bio = ""
    @State private var gender: Gender = .unspecified
    @State private var preferredMode: GameMode?
    @State private var avatar = Avatar(symbol: "", paletteIndex: 0)
    @State private var showReassess = false
    @State private var showGuide = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cropItem: AvatarCropSheet.Item?
    @State private var photo: UIImage?
    @State private var isUploadingPhoto = false
    @State private var cardColor: CardColor?
    @State private var cardItem: PhotosPickerItem?
    @State private var cardCropItem: AvatarCropSheet.Item?
    @State private var isUploadingCard = false
    @State private var showsCardPreview = false
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "编辑资料"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    avatarSection
                    cardSection
                    BrutalTextField(label: String(localized: "昵称"), placeholder: String(localized: "2-12 个字"), text: $nickname,
                                    contentType: .nickname,
                                    errorText: nickname.isEmpty || MockBackend.isValidNickname(nickname) ? nil : String(localized: "昵称需为 2-12 个字符"),
                                    characterLimit: 12)
                    BrutalTextField(label: String(localized: "一句话介绍"), placeholder: String(localized: "例：双打找固定搭档，周末有空"), text: $bio,
                                    characterLimit: 60, axis: .vertical)
                    GenderPicker(selection: $gender)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        fieldLabel(String(localized: "常打"))
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ChoiceChip(title: String(localized: "单打"), isSelected: preferredMode == .singles) { preferredMode = .singles }
                            ChoiceChip(title: String(localized: "双打"), isSelected: preferredMode == .doubles) { preferredMode = .doubles }
                            ChoiceChip(title: String(localized: "都行"), isSelected: preferredMode == nil) { preferredMode = nil }
                        }
                    }
                    if let user = appState.currentUser {
                        levelSection(user)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isSaving { LoadingDots() }
                    Text("保存")
                }
            }
            .buttonStyle(.brutalPrimary)
            .disabled(!MockBackend.isValidNickname(nickname) || isSaving)
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .onAppear(perform: load)
        .onAppear {
            // 从等级页的链接进来、还没定级：直接开始测级
            if appState.opensAssessment {
                appState.opensAssessment = false
                showReassess = true
            }
        }
        .sheet(isPresented: $showReassess) {
            ReassessSheet()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGuide) {
            SkillLevelGuideView(highlight: appState.currentUser?.displayTier)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .sheet(item: $cropItem) { item in
            AvatarCropSheet(image: item.image) { jpeg in Task { await upload(jpeg) } }
        }
        .onChange(of: cardItem) { _, item in
            guard let item else { return }
            Task { await loadCardPhoto(item) }
        }
        .sheet(item: $cardCropItem) { item in
            AvatarCropSheet(image: item.image, shape: .card) { jpeg in Task { await uploadCard(jpeg) } }
        }
        .fullScreenCover(isPresented: $showsCardPreview) {
            if let user = previewUser {
                MyCardPreview(user: user)
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                if appState.currentUser != nil {
                    AvatarView(
                        text: avatar.symbol.isEmpty ? (nickname.first.map { String($0) } ?? "🏸") : avatar.symbol,
                        paletteIndex: avatar.paletteIndex,
                        size: 104,
                        image: photo
                    )
                    .background(Circle().fill(Color(hex: 0x17140F)).offset(x: 3, y: 4))
                    .overlay {
                        if isUploadingPhoto {
                            Circle().fill(Color.black.opacity(0.35))
                            ProgressView().tint(.white)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) { CameraBadge() }
                }
            }
            .buttonStyle(PressableStyle())
            .disabled(isUploadingPhoto)
            .accessibilityLabel("从相册选择头像")
            .frame(maxWidth: .infinity)
            if photo != nil {
                Button("移除照片，使用文字头像") {
                    appState.backend.removeAvatarPhoto()
                    photo = nil
                }
                .buttonStyle(TextActionStyle())
            } else {
                AvatarPaletteEditor(avatar: $avatar)
            }
        }
    }

    // MARK: 卡片背景（别人在首页刷到你时看到的卡片）

    /// 还没保存的改动也显示出来：昵称、头像颜色、卡片颜色
    private var previewUser: User? {
        guard var user = appState.currentUser else { return nil }
        if MockBackend.isValidNickname(nickname) { user.nickname = nickname }
        user.avatar.symbol = avatar.symbol
        user.avatar.paletteIndex = avatar.paletteIndex
        user.avatar.cardColor = cardColor
        return user
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                fieldLabel(String(localized: "卡片背景"))
                RulesButton(title: String(localized: "卡片背景"), points: [
                    String(localized: "别人在首页刷到你时，看到的就是这张卡片"),
                    String(localized: "上传的照片会显示给其他球友"),
                    String(localized: "不传照片时用这个颜色"),
                ])
                .padding(.vertical, -8)
            }
            if let user = previewUser {
                let cover = AvatarPhotos.cardImage(userId: user.id, avatar: user.avatar)
                VStack(alignment: .leading, spacing: 0) {
                    CardCover(color: user.cardColor, photo: cover)
                    .frame(height: 132)
                    .overlay {
                        if isUploadingCard {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if cover != nil {
                            AvatarView(text: user.avatarText, paletteIndex: avatar.paletteIndex, size: 40, image: photo)
                                .padding(.leading, AppTheme.Spacing.md)
                                .offset(y: 20)
                        }
                    }
                    .zIndex(1)
                    NicknameText(user: user)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, cover != nil ? 24 : AppTheme.Spacing.sm)
                        .padding(.bottom, AppTheme.Spacing.sm)
                }
                .background(AppTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                .accessibilityHidden(true)

                HStack(spacing: AppTheme.Spacing.sm) {
                    PhotosPicker(selection: $cardItem, matching: .images) {
                        Label("上传背景照片", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small))
                    .disabled(isUploadingCard)
                    Button {
                        showsCardPreview = true
                    } label: {
                        Label("预览", systemImage: "eye")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                }
                if cover != nil {
                    Button("移除背景照片") { appState.backend.removeCardPhoto() }
                        .buttonStyle(TextActionStyle())
                } else {
                    HStack(spacing: 0) {
                        ForEach(CardColor.allCases) { color in
                            let selected = color == user.cardColor
                            Button {
                                Haptics.selection()
                                cardColor = color
                                appState.backend.setCardColor(color)
                            } label: {
                                Circle()
                                    .fill(color.fill)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                                    .padding(4)
                                    .overlay(Circle().strokeBorder(selected ? AppTheme.Colors.ink : .clear, lineWidth: 2.5))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.name)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private func loadCardPhoto(_ item: PhotosPickerItem) async {
        defer { cardItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = await AvatarPhotos.image(fromPhoto: data) else {
            appState.showToast(String(localized: "无法读取这张照片"), style: .error)
            return
        }
        cardCropItem = AvatarCropSheet.Item(image: image)
    }

    private func uploadCard(_ jpeg: Data) async {
        isUploadingCard = true
        defer { isUploadingCard = false }
        do {
            try await appState.backend.uploadCardPhoto(jpeg)
            appState.showToast(String(localized: "卡片背景已更新"), style: .success)
        } catch {
            appState.showError(error)
        }
    }

    // MARK: 等级（只能通过问卷或球友评价改变）

    private func levelSection(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                fieldLabel(String(localized: "等级"))
                RulesButton(title: String(localized: "等级"), points: levelRules(user))
                    .padding(.vertical, -8)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    LevelBadge(tier: user.displayTier)
                    VerifiedBadge(status: user.verificationStatus)
                    if user.needsAssessment {
                        TagPill(text: String(localized: "未定级"), fill: AppTheme.Colors.butter)
                    }
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        showGuide = true
                    } label: {
                        Label("对照表", systemImage: "list.number")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                    if let assessment = user.assessment, !assessment.canRetake() {
                        Text("下次可重测：\(DateText.shortDay(assessment.nextRetakeDate()))")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    } else {
                        Button {
                            showReassess = true
                        } label: {
                            Label(user.assessment == nil ? String(localized: "开始定级") : String(localized: "重新测评"),
                                  systemImage: user.assessment == nil ? "checklist" : "arrow.counterclockwise")
                        }
                        .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small))
                    }
                }
                Divider()
                Button {
                    router.open(.verification)
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                        Text(verificationTitle(user))
                            .font(AppTheme.Typography.subheadlineBold)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.Colors.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .card(AppTheme.Colors.surface, shadow: .zero)
        }
    }

    /// 原来写在等级卡片上的说明
    private func levelRules(_ user: User) -> [String] {
        [
            SkillLevel.descriptor(for: user.displayLevel),
            user.needsAssessment
                ? String(localized: "你跳过了定级，现在暂按 Lv.\(SkillAssessment.provisionalLevel) 匹配。花一分钟做完定级，匹配会准很多。")
                : user.isNewPlayer
                ? String(localized: "等级来自定级问卷；打满 5 场并获得评价后会按球友评价自动校准。")
                : String(localized: "你已有 \(user.reputation.evaluationCount) 次球友评价，等级主要由球友评价决定。"),
            String(localized: "问卷最高 6+。打过州 / 地区公开赛最高组、有全国排名、运动员等级证书或 BWF 世界排名，可以凭证据认证 7− 到 9+"),
        ]
    }

    private func verificationTitle(_ user: User) -> String {
        if appState.backend.myVerificationRequest()?.status == .pending { return String(localized: "高水平认证 · 审核中") }
        if user.verificationStatus != .unverified { return String(localized: "已认证 \(user.tierCap.text) · 申请更高档位") }
        return String(localized: "申请高水平认证")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Typography.footnoteBold)
            .foregroundStyle(AppTheme.Colors.inkSecondary)
    }

    private func load() {
        guard !didLoad, let user = appState.currentUser else { return }
        didLoad = true
        nickname = user.nickname
        bio = user.bio
        gender = user.gender
        preferredMode = user.preferredMode
        avatar = user.avatar
        cardColor = user.avatar.cardColor
        photo = AvatarPhotos.image(userId: user.id, avatar: user.avatar)
    }

    /// 选完照片先去裁剪页调整，确定了再上传
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = await AvatarPhotos.image(fromPhoto: data) else {
            appState.showToast(String(localized: "无法读取这张照片"), style: .error)
            return
        }
        cropItem = AvatarCropSheet.Item(image: image)
    }

    private func upload(_ jpeg: Data) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let user = try await appState.backend.uploadAvatarPhoto(jpeg)
            photo = AvatarPhotos.image(userId: user.id, avatar: user.avatar)
            appState.showToast(String(localized: "头像已更新"), style: .success)
        } catch {
            appState.showError(error)
        }
    }

    private func save() async {
        guard var user = appState.currentUser else { return }
        isSaving = true
        defer { isSaving = false }
        user.nickname = nickname
        user.bio = bio
        user.gender = gender
        user.preferredMode = preferredMode
        user.avatar.symbol = avatar.symbol
        user.avatar.paletteIndex = avatar.paletteIndex
        user.avatar.cardColor = cardColor
        if await appState.updateProfile(user) {
            router.pop()
        }
    }
}

/// 头像右下角的相机标：点头像就能换照片
struct CameraBadge: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppTheme.Colors.onAccent)
            .frame(width: 38, height: 38)
            .background(Circle().fill(AppTheme.Colors.lime))
            .overlay(Circle().strokeBorder(Color(hex: 0x17140F), lineWidth: 2))
            .offset(x: 4, y: 4)
            .accessibilityHidden(true)
    }
}
