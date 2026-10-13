import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, phone, code, profile, level, preferences

    /// 进度条中的序号（欢迎页不计）
    var progressIndex: Int { rawValue }
    static let progressTotal = 5
}

/// 注册/登录表单数据
struct OnboardingForm {
    /// 国内号码（不含国家码）
    var phone = ""
    /// 国家/地区（默认跟随设备地区，首发市场为美国）
    var phoneCountry: CountryInfo = .deviceCountry
    var phoneNumber: PhoneNumber { PhoneNumber(country: phoneCountry, national: phone) }
    var agreed = false
    var code = ""
    var issuedCode: String?
    var nickname = ""
    var gender: Gender = .unspecified
    var avatar = Avatar(symbol: "", paletteIndex: 0)
    var level: Int?
    var preferredMode: GameMode?
    var timePresets: Set<TimePreset> = []
    /// 常去球馆（注册后设为收藏，快速匹配默认选中）
    var favoriteVenueIds: [String] = []
}

/// 常用时间快捷选项（注册时生成“常用时间”）
enum TimePreset: String, CaseIterable, Identifiable, Hashable {
    case weekdayEvening = "工作日晚上"
    case weekendMorning = "周末上午"
    case weekendAfternoon = "周末下午"
    case earlyMorning = "早起晨练"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .weekdayEvening: return "moon.stars.fill"
        case .weekendMorning: return "sun.max.fill"
        case .weekendAfternoon: return "sun.haze.fill"
        case .earlyMorning: return "sunrise.fill"
        }
    }

    var slots: [RecurringTimeSlot] {
        switch self {
        case .weekdayEvening:
            return [RecurringTimeSlot(dayOfWeek: 3, startHour: 19, endHour: 21),
                    RecurringTimeSlot(dayOfWeek: 5, startHour: 19, endHour: 21)]
        case .weekendMorning:
            return [RecurringTimeSlot(dayOfWeek: 7, startHour: 9, endHour: 12)]
        case .weekendAfternoon:
            return [RecurringTimeSlot(dayOfWeek: 1, startHour: 14, endHour: 17)]
        case .earlyMorning:
            return [RecurringTimeSlot(dayOfWeek: 2, startHour: 7, endHour: 9)]
        }
    }
}

struct OnboardingFlow: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager

    @State private var step: OnboardingStep = .welcome
    @State private var form = OnboardingForm()
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var resendRemaining = 0
    @State private var showVenuePicker = false
    @FocusState private var codeFocused: Bool
    @FocusState private var phoneFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    content
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, step == .welcome ? AppTheme.Spacing.xxl : AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            step = appState.onboardingInitialStep
        }
        .task(id: resendRemaining) {
            guard resendRemaining > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            resendRemaining -= 1
        }
    }

    // MARK: Header with progress

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            IconButton(systemName: "chevron.left", accessibilityLabel: "上一步") { goBack() }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.surfaceMuted)
                    Capsule()
                        .fill(AppTheme.Colors.lime)
                        .frame(width: max(14, proxy.size.width * CGFloat(step.progressIndex) / CGFloat(OnboardingStep.progressTotal)))
                    Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2)
                }
            }
            .frame(height: 14)
            .accessibilityElement()
            .accessibilityLabel("第 \(step.progressIndex) 步，共 \(OnboardingStep.progressTotal) 步")
            Text("\(step.progressIndex)/\(OnboardingStep.progressTotal)")
                .font(AppTheme.Typography.footnoteBold)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.vertical, AppTheme.Spacing.sm)
        .animation(AppTheme.Motion.standard, value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .phone: phoneStep
        case .code: codeStep
        case .profile: profileStep
        case .level: levelStep
        case .preferences: preferencesStep
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            Wordmark(size: 30)
            WelcomeCardFan()
                .frame(height: 230)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                (Text("今晚，\n找个") + Text(markedText: "搭子") + Text("\n打一场。"))
                    .font(AppTheme.Typography.display)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .lineSpacing(4)
                    .accessibilityLabel("今晚，找个搭子打一场。")
                Text("按水平、时间、距离帮你匹配附近球友；费用 AA 透明，到场签到，靠谱的人更容易约到球。")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                TagPill(text: "水平匹配", icon: "chart.bar.fill", fill: AppTheme.Colors.lavender)
                TagPill(text: "AA 透明", icon: Money.icon(for: CountryInfo.deviceCountry.currencyCode), fill: AppTheme.Colors.peach)
                TagPill(text: "到场签到", icon: "checkmark.seal.fill", fill: AppTheme.Colors.mint)
            }
        }
    }

    // MARK: Phone

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle("先用手机号\n登录或注册", subtitle: "未注册的手机号验证后会自动创建账号")
            HStack(spacing: AppTheme.Spacing.sm) {
                Menu {
                    Picker("国家/地区", selection: $form.phoneCountry) {
                        ForEach(CountryInfo.phoneCountries) { country in
                            Text("\(country.flag) \(country.nameZh) +\(country.callingCode)").tag(country)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(form.phoneCountry.flag) +\(form.phoneCountry.callingCode)")
                            .font(AppTheme.Typography.bodyBold)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(AppTheme.Colors.ink)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(minWidth: 84, minHeight: 52)
                    .sticker(AppTheme.Colors.surfaceMuted, radius: 14, shadow: .zero)
                }
                .accessibilityLabel("国家或地区")
                .accessibilityValue("\(form.phoneCountry.nameZh)，+\(form.phoneCountry.callingCode)")
                .onChange(of: form.phoneCountry) { _, _ in errorText = nil }
                TextField(form.phoneCountry.phone.example.isEmpty ? "请输入手机号" : form.phoneCountry.phone.example, text: $form.phone)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($phoneFocused)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(minHeight: 52)
                    .sticker(AppTheme.Colors.surface, radius: 14, shadow: phoneFocused ? AppTheme.Elevation.low : .zero,
                             stroke: errorText == nil ? AppTheme.Colors.stroke : AppTheme.Colors.danger)
                    .onChange(of: form.phone) { _, value in
                        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(15))
                        if digits != value { form.phone = digits }
                        errorText = nil
                    }
            }
            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            Button {
                Haptics.selection()
                form.agreed.toggle()
            } label: {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Image(systemName: form.agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(form.agreed ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                    Text("我已阅读并同意《用户协议》和《隐私政策》，了解手机号仅用于登录与安全验证，不会展示给其他球友。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(form.agreed ? [.isSelected, .isButton] : .isButton)
        }
        .onAppear { phoneFocused = true }
    }

    // MARK: Code

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle("输入验证码", subtitle: "已发送至 \(form.phoneNumber.masked)")
            ZStack {
                TextField("", text: $form.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .opacity(0.02)
                    .onChange(of: form.code) { _, value in
                        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        if digits != value { form.code = digits }
                        errorText = nil
                        if digits.count == 6 { submitCode() }
                    }
                    .accessibilityLabel("验证码")
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { index in
                        let characters = Array(form.code)
                        let filled = index < characters.count
                        Text(filled ? String(characters[index]) : "")
                            .font(.system(.title, design: .rounded, weight: .black))
                            .foregroundStyle(AppTheme.Colors.ink)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .sticker(index == characters.count && codeFocused ? AppTheme.Colors.lime : AppTheme.Colors.surface,
                                     radius: 14, shadow: filled ? AppTheme.Elevation.low : .zero)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { codeFocused = true }

            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            }

            if let issued = form.issuedCode {
                NoticeBanner(icon: "message.badge.filled.fill", text: "演示环境不发真实短信，验证码：\(issued)",
                             tint: AppTheme.Colors.sky, actionTitle: "填入") {
                    form.code = issued
                }
            }

            Button(resendRemaining > 0 ? "\(resendRemaining) 秒后可重新发送" : "重新发送验证码") {
                Task { await sendCode() }
            }
            .buttonStyle(TextActionStyle())
            .disabled(resendRemaining > 0 || isWorking)
        }
        .onAppear { codeFocused = true }
    }

    // MARK: Profile

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle("怎么称呼你？", subtitle: "昵称和头像会展示给球友，手机号不会")
            HStack {
                Spacer()
                AvatarView(text: form.avatar.symbol.isEmpty ? (form.nickname.first.map { String($0) } ?? "🏸") : form.avatar.symbol,
                           paletteIndex: form.avatar.paletteIndex, size: 96)
                    .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
                Spacer()
            }
            AvatarPaletteEditor(avatar: $form.avatar)
            BrutalTextField(label: "昵称", placeholder: "2-12 个字", text: $form.nickname,
                            contentType: .nickname, errorText: errorText, characterLimit: 12)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("性别（可选）")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                SegmentedSticker(options: Gender.allCases, selection: $form.gender, title: { $0.label })
                Text("仅用于“女生友好”等球局筛选，可随时修改")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
    }

    // MARK: Level

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            stepTitle("你现在打到什么水平？", subtitle: "按描述如实选择即可，打几场后会根据球友评价自动校准")
            SkillLevelList(selection: $form.level)
            Text("等级描述参考民间常用的业余自评标准，并非羽协官方等级。8-9 级需上传赛事证明审核。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Preferences

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle("最后一步", subtitle: "这些偏好用于默认匹配设置，之后都能改")
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("常打")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                HStack(spacing: AppTheme.Spacing.sm) {
                    ChoiceChip(title: "单打", icon: GameMode.singles.icon, isSelected: form.preferredMode == .singles) {
                        form.preferredMode = .singles
                    }
                    ChoiceChip(title: "双打", icon: GameMode.doubles.icon, isSelected: form.preferredMode == .doubles) {
                        form.preferredMode = .doubles
                    }
                    ChoiceChip(title: "都行", isSelected: form.preferredMode == nil) {
                        form.preferredMode = nil
                    }
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("一般什么时候有空")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                FlowLayout(spacing: AppTheme.Spacing.sm) {
                    ForEach(TimePreset.allCases) { preset in
                        ChoiceChip(title: preset.rawValue, icon: preset.icon, isSelected: form.timePresets.contains(preset),
                                   tint: AppTheme.Colors.peach) {
                            if form.timePresets.contains(preset) {
                                form.timePresets.remove(preset)
                            } else {
                                form.timePresets.insert(preset)
                            }
                        }
                    }
                }
            }
            favoriteVenuesCard
            locationCard
        }
        .sheet(isPresented: $showVenuePicker) {
            VenuePickerView(mode: .multiple(max: 3), selection: $form.favoriteVenueIds, allowsAdding: false)
                .presentationDragIndicator(.visible)
        }
    }

    /// 常去球馆：选一次，以后快速匹配默认就是它们（选同一家的人才会被匹配到一起）
    private var favoriteVenuesCard: some View {
        let venues = locationManager.courts(ids: form.favoriteVenueIds)
        return Button {
            showVenuePicker = true
        } label: {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "figure.badminton", fill: AppTheme.Colors.lime, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(venues.isEmpty ? "常去哪几个球馆？（选填）" : "常去球馆")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                    if venues.isEmpty {
                        Text("比如 LABC、Elite Rally。选好后快速匹配会默认用它们")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(venues) { venue in
                            Text("\(venue.name) · \(venue.postalAddress.city)")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .padding(.top, 4)
            }
            .card()
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var locationCard: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            IconTile(systemName: locationManager.isAuthorized ? "location.fill" : "location", fill: AppTheme.Colors.sky, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(locationManager.isAuthorized ? "已开启定位" : "开启定位")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text("用于找附近的球馆和球友，只在使用 App 时获取")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !locationManager.isAuthorized && !locationManager.isDenied {
                Button("允许") { locationManager.requestAuthorization() }
                    .buttonStyle(.brutal(.primary, size: .small, fullWidth: false))
            } else if locationManager.isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.success)
            }
        }
        .card()
    }

    // MARK: Footer CTA

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                primaryAction()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isWorking { LoadingDots() }
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.brutal(step == .welcome ? .inverse : .primary))
            .disabled(!canContinue || isWorking)
            if step == .welcome {
                Text("登录即可体验，附近球友为演示数据")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.md)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "手机号登录 / 注册"
        case .phone: return "获取验证码"
        case .code: return "验证"
        case .profile, .level: return "下一步"
        case .preferences: return "完成，开始约球"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome: return true
        case .phone: return form.phoneNumber.national.count >= form.phoneCountry.phone.lengths.lowerBound && form.agreed
        case .code: return form.code.count == 6
        case .profile: return MockBackend.isValidNickname(form.nickname)
        case .level: return form.level != nil
        case .preferences: return true
        }
    }

    // MARK: Actions

    private func primaryAction() {
        errorText = nil
        switch step {
        case .welcome:
            advance(to: .phone)
        case .phone:
            guard form.phoneNumber.isValid else {
                errorText = BackendError.invalidPhone.errorDescription
                return
            }
            Task {
                await sendCode()
                if form.issuedCode != nil { advance(to: .code) }
            }
        case .code:
            submitCode()
        case .profile:
            guard MockBackend.isValidNickname(form.nickname) else {
                errorText = BackendError.invalidNickname.errorDescription
                return
            }
            advance(to: .level)
        case .level:
            advance(to: .preferences)
        case .preferences:
            Task { await finish() }
        }
    }

    private func sendCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            form.issuedCode = try await appState.requestCode(phone: form.phoneNumber.e164)
            form.code = ""
            resendRemaining = 60
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
        }
    }

    private func submitCode() {
        guard form.code.count == 6, !isWorking else { return }
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                switch try await appState.verify(phone: form.phoneNumber.e164, code: form.code) {
                case .signedIn(let user):
                    appState.showToast("欢迎回来，\(user.nickname)", style: .success)
                case .needsProfile:
                    advance(to: .profile)
                }
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription
                form.code = ""
                Haptics.error()
            }
        }
    }

    private func finish() async {
        guard let level = form.level else { return }
        isWorking = true
        defer { isWorking = false }
        let slots = Array(form.timePresets.sorted { $0.rawValue < $1.rawValue }.flatMap(\.slots).prefix(TimeSlotConstants.maximumRecurringSlots))
        do {
            try await appState.register(
                phone: form.phoneNumber.e164,
                nickname: form.nickname,
                gender: form.gender,
                avatar: form.avatar,
                level: level,
                preferredMode: form.preferredMode,
                recurringSlots: slots,
                location: locationManager.currentLocation.map { Coordinate($0.coordinate) }
            )
            for venueId in form.favoriteVenueIds where !locationManager.isFavorite(venueId) {
                locationManager.toggleFavorite(venueId)
            }
        } catch {
            appState.showError(error)
        }
    }

    private func advance(to next: OnboardingStep) {
        Haptics.tap()
        withAnimation(AppTheme.Motion.standard) { step = next }
    }

    private func goBack() {
        errorText = nil
        let previous: OnboardingStep
        switch step {
        case .welcome, .phone: previous = .welcome
        case .code: previous = .phone
        case .profile: previous = .phone
        case .level: previous = .profile
        case .preferences: previous = .level
        }
        withAnimation(AppTheme.Motion.standard) { step = previous }
    }

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

// MARK: - 欢迎页插画：扇形展开的球友卡片

private struct WelcomeCardFan: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = false

    private let cards: [(String, Int, Color, Double)] = [
        ("小红", 7, AppTheme.Colors.lavender, -14),
        ("阿杰", 4, AppTheme.Colors.peach, 0),
        ("小明", 6, AppTheme.Colors.sky, 14)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                VStack(spacing: AppTheme.Spacing.sm) {
                    AvatarView(text: String(card.0.prefix(1)), paletteIndex: index + 3, size: 54)
                    Text(card.0)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.onAccent)
                    LevelBadge(level: card.1)
                }
                .frame(width: 128, height: 168)
                .sticker(card.2, radius: 22)
                .rotationEffect(.degrees(spread || reduceMotion ? card.3 : 0), anchor: .bottom)
                .offset(x: (spread || reduceMotion) ? CGFloat(index - 1) * 78 : 0, y: index == 1 ? -10 : 6)
                .zIndex(index == 1 ? 1 : 0)
            }
            ShuttlecockMark(size: 64)
                .rotationEffect(.degrees(-24))
                .offset(x: 118, y: -96)
            StarburstBadge(text: "GO", fill: AppTheme.Colors.lime, size: 64)
                .offset(x: -126, y: 78)
        }
        .onAppear {
            withAnimation(AppTheme.Motion.bouncy.delay(0.15)) { spread = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 头像编辑（调色板 + 表情）

struct AvatarPaletteEditor: View {
    @Binding var avatar: Avatar

    private let symbols = ["", "🏸", "😎", "🐯", "🦊", "🐼", "⚡️", "🍑"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(0..<AppTheme.Colors.palette.count, id: \.self) { index in
                    Button {
                        Haptics.selection()
                        avatar.paletteIndex = index
                    } label: {
                        Circle()
                            .fill(AppTheme.Colors.paletteColor(index))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: avatar.paletteIndex == index ? 3.5 : 2))
                            .overlay {
                                if avatar.paletteIndex == index {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(AppTheme.Colors.onAccent)
                                }
                            }
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("颜色 \(index + 1)")
                    .accessibilityAddTraits(avatar.paletteIndex == index ? [.isSelected, .isButton] : .isButton)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(symbols, id: \.self) { symbol in
                        ChoiceChip(title: symbol.isEmpty ? "昵称首字" : symbol, isSelected: avatar.symbol == symbol) {
                            avatar.symbol = symbol
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - 技能等级列表（1-7 可选，8-9 锁定）

struct SkillLevelList: View {
    @Binding var selection: Int?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(Array(SkillLevel.range), id: \.self) { level in
                let locked = level > SkillLevel.maxSelfSelectable
                let selected = selection == level
                Button {
                    guard !locked else { return }
                    Haptics.selection()
                    withAnimation(AppTheme.Motion.standard) { selection = level }
                } label: {
                    HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                        Text("\(level)")
                            .scaledFont(size: 22, relativeTo: .title3)
                            .foregroundStyle(selected ? AppTheme.Colors.lime : AppTheme.Colors.onAccent)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color(hex: 0x17140F) : AppTheme.Colors.paletteColor(level)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SkillLevel.name(for: level))
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(locked ? AppTheme.Colors.inkTertiary : AppTheme.Colors.ink)
                            Text(SkillLevel.descriptor(for: level))
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(locked ? AppTheme.Colors.inkTertiary : AppTheme.Colors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: locked ? "lock.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(locked ? AppTheme.Colors.inkTertiary : AppTheme.Colors.ink)
                    }
                    .padding(AppTheme.Spacing.md)
                    .sticker(selected ? AppTheme.Colors.lime.opacity(0.35) : AppTheme.Colors.surface,
                             radius: AppTheme.Radius.md, shadow: selected ? AppTheme.Elevation.low : .zero)
                    .opacity(locked ? 0.7 : 1)
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("等级 \(level) \(SkillLevel.name(for: level))，\(SkillLevel.descriptor(for: level))\(locked ? "，需赛事认证" : "")")
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

// MARK: - 文字高亮（柠檬色马克笔）

extension Text {
    /// 柠檬绿底色 + 墨色文字（深浅模式都可读）
    init(markedText: String) {
        var attributed = AttributedString(markedText)
        attributed.backgroundColor = AppTheme.Colors.lime
        attributed.foregroundColor = AppTheme.Colors.onAccent
        self.init(attributed)
    }
}
