import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var locationManager: LocationManager

    private enum Tab: Hashable {
        case edit, preview

        var title: String {
            switch self {
            case .edit: String(localized: "编辑")
            case .preview: String(localized: "预览")
            }
        }
    }

    /// 两个照片格子：卡片照片（600×800）和头像（320×320），分开存
    private enum PhotoSlot: Identifiable {
        case card, avatar
        var id: Self { self }
    }

    @State private var tab: Tab = .edit
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
    @State private var showsCardPicker = false
    @State private var showsAvatarPicker = false
    @State private var photoMenu: PhotoSlot?
    @State private var slots: [RecurringTimeSlot] = []
    @State private var showsSlotEditor = false
    @State private var slotToDelete: RecurringTimeSlot?
    @State private var scrollTarget: ProfileField?
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: String(localized: "编辑资料"))
            SegmentedSticker(options: [Tab.edit, Tab.preview], selection: $tab, title: { $0.title })
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.md)
            if tab == .edit {
                editForm
            } else if let user = previewUser {
                MyCardPreviewContent(user: user, slots: slots)
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .frame(maxHeight: .infinity)
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
            // 从“我的”页的“资料 N/4”进来：跳到缺的那一项
            if let field = appState.editProfileFocus {
                appState.editProfileFocus = nil
                focus(field)
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
        .sheet(isPresented: $showsSlotEditor) {
            RecurringSlotEditor { slot in addSlot(slot) }
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 编辑

    private var editForm: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    photosSection
                    cardColorSection
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        sectionLabel(String(localized: "资料"))
                        BrutalTextField(label: String(localized: "昵称"), placeholder: String(localized: "2-12 个字"), text: $nickname,
                                        contentType: .nickname,
                                        errorText: nickname.isEmpty || MockBackend.isValidNickname(nickname) ? nil : String(localized: "昵称需为 2-12 个字符"),
                                        characterLimit: 12)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            fieldLabel(String(localized: "常打"))
                            HStack(spacing: AppTheme.Spacing.sm) {
                                ChoiceChip(title: String(localized: "单打"), isSelected: preferredMode == .singles) { preferredMode = .singles }
                                ChoiceChip(title: String(localized: "双打"), isSelected: preferredMode == .doubles) { preferredMode = .doubles }
                                ChoiceChip(title: String(localized: "都行"), isSelected: preferredMode == nil) { preferredMode = nil }
                            }
                        }
                        venueRow
                            .id(ProfileField.venue)
                    }
                    timesSection
                        .id(ProfileField.usualTimes)
                    BrutalTextField(label: String(localized: "一句话介绍"), placeholder: String(localized: "例：双打找固定搭档，周末有空"), text: $bio,
                                    characterLimit: 60, axis: .vertical)
                    GenderPicker(selection: $gender)
                    if photo == nil {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            fieldLabel(String(localized: "没照片时的头像"))
                            AvatarPaletteEditor(avatar: $avatar)
                        }
                    }
                    if let user = appState.currentUser {
                        levelSection(user)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(AppTheme.Motion.standard) { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
    }

    /// 先切到“编辑”；照片直接打开相册，其他滚到那一项
    private func focus(_ field: ProfileField) {
        tab = .edit
        Task {
            // 等页面推进来再弹相册 / 滚动
            try? await Task.sleep(for: .milliseconds(400))
            switch field {
            case .cardPhoto: showsCardPicker = true
            case .avatarPhoto: showsAvatarPicker = true
            case .usualTimes, .venue: scrollTarget = field
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Typography.subheadlineBold)
            .foregroundStyle(AppTheme.Colors.ink)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: 照片：卡片照片（大）+ 头像（小），分开传

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 0) {
                sectionLabel(String(localized: "照片"))
                RulesButton(title: String(localized: "卡片背景"), points: [
                    String(localized: "别人在首页刷到你时，看到的就是这张卡片"),
                    String(localized: "上传的照片会显示给其他球友"),
                    String(localized: "不传照片时用这个颜色"),
                ])
                .padding(.vertical, -8)
            }
            if let user = previewUser {
                PhotoSlotsLayout(spacing: AppTheme.Spacing.sm) {
                    cardSlot(user)
                    avatarSlot(user)
                }
            }
        }
        .photosPicker(isPresented: $showsCardPicker, selection: $cardItem, matching: .images)
        .confirmationDialog(Text(verbatim: ""), isPresented: Binding(get: { photoMenu != nil }, set: { if !$0 { photoMenu = nil } }),
                            titleVisibility: .hidden, presenting: photoMenu) { slot in
            Button("换一张") {
                if slot == .card { showsCardPicker = true } else { showsAvatarPicker = true }
            }
            Button("移除照片", role: .destructive) { removePhoto(slot) }
        }
    }

    private func cardSlot(_ user: User) -> some View {
        let cover = AvatarPhotos.cardImage(userId: user.id, avatar: user.avatar)
        return photoSlot(label: String(localized: "卡片"), accessibility: String(localized: "卡片照片"), hasPhoto: cover != nil,
                         isUploading: isUploadingCard) {
            CardCover(color: user.cardColor, photo: cover)
        } action: {
            if cover != nil { photoMenu = .card } else { showsCardPicker = true }
        }
    }

    private func avatarSlot(_ user: User) -> some View {
        photoSlot(label: String(localized: "头像"), accessibility: String(localized: "头像照片"), hasPhoto: photo != nil,
                  isUploading: isUploadingPhoto) {
            if let photo {
                Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill() }
            } else {
                ZStack {
                    AppTheme.Colors.surfaceMuted
                    AvatarView(text: user.avatarText, paletteIndex: avatar.paletteIndex, size: 64)
                }
            }
        } action: {
            if photo != nil { photoMenu = .avatar } else { showsAvatarPicker = true }
        }
        .photosPicker(isPresented: $showsAvatarPicker, selection: $photoItem, matching: .images)
    }

    /// 一个照片格子：没照片时中间一个相机；左下角写“卡片”/“头像”；点了选照片，有照片时换一张或移除
    private func photoSlot<Content: View>(label: String, accessibility: String, hasPhoto: Bool, isUploading: Bool,
                                          @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        return Button(action: action) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if isUploading {
                        Color.black.opacity(0.35)
                        ProgressView().tint(.white)
                    } else if !hasPhoto {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.onAccent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(AppTheme.Colors.lime))
                            .overlay(Circle().strokeBorder(AppTheme.Colors.onAccent, lineWidth: 2))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    TagPill(text: label, fill: .white, foreground: AppTheme.Colors.onAccent)
                        .padding(AppTheme.Spacing.sm)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .disabled(isUploading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(.isButton)
    }

    private func removePhoto(_ slot: PhotoSlot) {
        switch slot {
        case .card:
            appState.backend.removeCardPhoto()
        case .avatar:
            appState.backend.removeAvatarPhoto()
            photo = nil
        }
    }

    // MARK: 卡片颜色（没传卡片照片时用）

    /// 还没保存的改动也显示出来：昵称、常打、头像颜色、卡片颜色
    private var previewUser: User? {
        guard var user = appState.currentUser else { return nil }
        if MockBackend.isValidNickname(nickname) { user.nickname = nickname }
        user.preferredMode = preferredMode
        user.avatar.symbol = avatar.symbol
        user.avatar.paletteIndex = avatar.paletteIndex
        user.avatar.cardColor = cardColor
        return user
    }

    private var cardColorSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            sectionLabel(String(localized: "没照片时的卡片颜色"))
            if let user = previewUser {
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

    // MARK: 常去球馆（收藏的球馆）

    private var venueRow: some View {
        let favorites = locationManager.favoriteCourts
        let value: String = {
            guard let first = favorites.first else { return String(localized: "未设置") }
            return favorites.count > 1 ? "\(first.name) +\(favorites.count - 1)" : first.name
        }()
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            fieldLabel(String(localized: "常去球馆"))
            Button {
                router.open(.courts)
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text(value)
                        .font(AppTheme.Typography.subheadlineBold)
                        .foregroundStyle(favorites.isEmpty ? AppTheme.Colors.inkTertiary : AppTheme.Colors.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: 48)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: .zero)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: 空闲时间（就是“常用时间”：最多 5 段，每段 1–8 小时，改了马上存）

    private var timesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            sectionLabel(String(localized: "空闲时间"))
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(sortedSlots) { slot in
                    Button {
                        slotToDelete = slot
                    } label: {
                        Text(UsualTimeText.chip(slot))
                            .font(AppTheme.Typography.footnoteBold)
                            .foregroundStyle(slot.isActive ? AppTheme.Colors.onAccent : AppTheme.Colors.inkSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 38)
                            .background(Capsule().fill(slot.isActive ? AppTheme.Colors.lime : AppTheme.Colors.surfaceMuted))
                            .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text(verbatim: slot.displayText))
                }
                if slots.canAddMore {
                    Button {
                        showsSlotEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("加一段")
                                .lineLimit(1)
                        }
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(Capsule().fill(AppTheme.Colors.surface))
                        .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: AppTheme.Stroke.width))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .confirmationDialog(Text(verbatim: slotToDelete?.displayText ?? ""),
                            isPresented: Binding(get: { slotToDelete != nil }, set: { if !$0 { slotToDelete = nil } }),
                            titleVisibility: .visible, presenting: slotToDelete) { slot in
            Button(String(localized: "删除 \(slot.displayText)"), role: .destructive) {
                slots.removeAll { $0.id == slot.id }
                persistSlots()
            }
        }
    }

    /// 周一排第一，同一天按开始时间
    private var sortedSlots: [RecurringTimeSlot] {
        slots.sorted { a, b in
            let x = (a.dayOfWeek + 5) % 7
            let y = (b.dayOfWeek + 5) % 7
            return x != y ? x < y : a.startMinutes < b.startMinutes
        }
    }

    private func addSlot(_ slot: RecurringTimeSlot) {
        guard slots.canAddMore else { return }
        // 同一段加两次：不重复存
        if slots.contains(where: { $0.dayOfWeek == slot.dayOfWeek && $0.startMinutes == slot.startMinutes && $0.endMinutes == slot.endMinutes }) {
            appState.showToast(String(localized: "已经有这一段了"))
            return
        }
        slots.append(slot)
        persistSlots()
    }

    private func persistSlots() {
        do {
            try appState.backend.saveRecurringSlots(slots)
        } catch {
            appState.showError(error)
            slots = appState.backend.recurringSlots()
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
        slots = appState.backend.recurringSlots()
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

/// 编辑资料的两个照片格子：卡片 3:4 占三分之二宽；头像正方形，和卡片顶端对齐
private struct PhotoSlotsLayout: Layout {
    var spacing: CGFloat

    private func unitWidth(_ width: CGFloat) -> CGFloat { max(0, width - spacing) / 3 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return CGSize(width: width, height: unitWidth(width) * 8 / 3)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let unit = unitWidth(bounds.width)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: unit * 2, height: unit * 8 / 3))
        subviews[1].place(at: CGPoint(x: bounds.minX + unit * 2 + spacing, y: bounds.minY),
                          proposal: ProposedViewSize(width: unit, height: unit))
    }
}

/// 资料完成度：“我的”页上的“资料 N/4”。按这个顺序提示下一项，点了跳到编辑资料里的那一项。
/// 常打不算：选“都行”和没填在服务器上都是空的，分不出来
enum ProfileField: Hashable, CaseIterable {
    case cardPhoto, avatarPhoto, usualTimes, venue

    var hint: String {
        switch self {
        case .cardPhoto: String(localized: "传一张卡片照片")
        case .avatarPhoto: String(localized: "传一张头像照片")
        case .usualTimes: String(localized: "填空闲时间，更容易被约")
        case .venue: String(localized: "选常去的球馆")
        }
    }

    /// 还缺的几项（空闲时间只算打开的）
    static func missing(user: User, slots: [RecurringTimeSlot], hasVenue: Bool) -> [ProfileField] {
        allCases.filter { field in
            switch field {
            case .cardPhoto: user.avatar.cardPhotoVersion == nil
            case .avatarPhoto: user.avatar.photoVersion == nil
            case .usualTimes: slots.activeSlots.isEmpty
            case .venue: !hasVenue
            }
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
