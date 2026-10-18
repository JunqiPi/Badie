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
    @State private var photo: UIImage?
    @State private var isUploadingPhoto = false
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "编辑资料"))
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    avatarSection
                    BrutalTextField(label: String(localized: "昵称"), placeholder: String(localized: "2-12 个字"), text: $nickname,
                                    contentType: .nickname,
                                    errorText: nickname.isEmpty || MockBackend.isValidNickname(nickname) ? nil : String(localized: "昵称需为 2-12 个字符"),
                                    characterLimit: 12)
                    BrutalTextField(label: String(localized: "一句话介绍"), placeholder: String(localized: "例：双打找固定搭档，周末有空"), text: $bio,
                                    characterLimit: 60, axis: .vertical)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        fieldLabel(String(localized: "性别（仅用于球局筛选）"))
                        SegmentedSticker(options: Gender.allCases, selection: $gender, title: { $0.label })
                    }
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
    }

    private var avatarSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack(alignment: .bottomTrailing) {
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
                }
                // 正式后端还不存照片：只用文字头像
                if !appState.isRemote {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.onAccent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(AppTheme.Colors.lime))
                            .overlay(Circle().strokeBorder(Color(hex: 0x17140F), lineWidth: 2))
                    }
                    .accessibilityLabel("从相册选择头像")
                }
            }
            .frame(maxWidth: .infinity)
            if photo != nil && !appState.isRemote {
                Button("移除照片，使用文字头像") {
                    appState.backend.removeAvatarPhoto()
                    photo = nil
                }
                .buttonStyle(TextActionStyle())
            } else {
                AvatarPaletteEditor(avatar: $avatar)
            }
            if !appState.isRemote {
                Text("上传的照片会显示给其他球友")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
    }

    // MARK: 等级（只能通过问卷或球友评价改变）

    private func levelSection(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            fieldLabel(String(localized: "等级"))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    LevelBadge(tier: user.displayTier)
                    VerifiedBadge(status: user.verificationStatus)
                    Text(SkillLevel.descriptor(for: user.displayLevel))
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .lineLimit(2)
                }
                Text(user.needsAssessment
                     ? String(localized: "你跳过了定级，现在暂按 Lv.\(SkillAssessment.provisionalLevel) 匹配。花一分钟做完定级，匹配会准很多。")
                     : user.isNewPlayer
                     ? String(localized: "等级来自定级问卷；打满 5 场并获得评价后会按球友评价自动校准。")
                     : String(localized: "你已有 \(user.reputation.evaluationCount) 次球友评价，等级主要由球友评价决定。"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verificationTitle(user))
                                .font(AppTheme.Typography.subheadlineBold)
                            Text("问卷最高 6+。打过州 / 地区公开赛最高组、有全国排名、运动员等级证书或 BWF 世界排名，可以凭证据认证 7− 到 9+")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
        photo = AvatarPhotos.image(userId: user.id, avatar: user.avatar)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = AvatarPhotos.jpegData(from: image) else {
            appState.showToast(String(localized: "无法读取这张照片"), style: .error)
            return
        }
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
        user.avatar = avatar
        if await appState.updateProfile(user) {
            router.pop()
        }
    }
}
