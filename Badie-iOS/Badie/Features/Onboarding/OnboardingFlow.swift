import AuthenticationServices
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, phone, code, profile, level, preferences

    /// 进度条中的序号（欢迎页不计）
    var progressIndex: Int { rawValue }
    static let progressTotal = 5
}

struct OnboardingForm {
    /// 国内号码（不含国家码）
    var phone = ""
    /// 国家/地区（默认跟随设备地区，首发市场为美国）
    var phoneCountry: CountryInfo = .deviceCountry
    var phoneNumber: PhoneNumber { PhoneNumber(country: phoneCountry, national: phone) }
    var agreed = false
    /// 正式后端用邮箱 + 密码登录；newAccount 为 true 是注册
    var email = ""
    var password = ""
    var newAccount = false
    var codePurpose: CodePurpose = .email
    var code = ""
    var codeSent = false
    var issuedCode: String?
    var nickname = ""
    var gender: Gender = .unspecified
    var avatar = Avatar(symbol: "", paletteIndex: 0)
    /// 定级问卷答案（题目 ID → 选项）
    var assessmentAnswers: [String: Int] = [:]
    var assessmentResult: SkillAssessmentResult? { SkillAssessment.evaluate(assessmentAnswers) }
    /// 暂时跳过定级（先按 Lv.3 匹配）
    var skippedAssessment = false
    /// 问卷自动算出的等级；跳过时暂用 Lv.3
    var level: Int? { assessmentResult?.level ?? (skippedAssessment ? SkillAssessment.provisionalLevel : nil) }
    var preferredMode: GameMode?
    var timePresets: Set<TimePreset> = []
    /// 常去球馆（注册后设为收藏，快速匹配默认选中）
    var favoriteVenueIds: [String] = []
}

/// 邮件里的 6 位码用来做什么：确认注册的邮箱、验证码登录、重设密码（就是 Supabase 校验时的 type）
enum CodePurpose: String {
    case signup, email, recovery
}

/// 常用时间快捷选项（注册时生成“常用时间”）
enum TimePreset: String, CaseIterable, Identifiable, Hashable {
    case weekdayEvening = "工作日晚上"
    case weekendMorning = "周末上午"
    case weekendAfternoon = "周末下午"
    case earlyMorning = "早起晨练"

    var id: String { rawValue }

    /// 展示用标题（本地化）
    var title: String {
        switch self {
        case .weekdayEvening: return String(localized: "工作日晚上")
        case .weekendMorning: return String(localized: "周末上午")
        case .weekendAfternoon: return String(localized: "周末下午")
        case .earlyMorning: return String(localized: "早起晨练")
        }
    }

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
    @EnvironmentObject private var host: AppHost
    @EnvironmentObject private var locationManager: LocationManager

    @State private var step: OnboardingStep = .welcome
    @State private var form = OnboardingForm()
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var resendRemaining = 0
    @StateObject private var captcha = CaptchaModel()
    @State private var showVenuePicker = false
    @FocusState private var codeFocused: Bool
    @FocusState private var phoneFocused: Bool
    /// 后台开了的第三方登录（apple / google），没开的不显示按钮。先用记下的结果马上显示，后台问到新的再换
    @State private var refreshedProviders: Set<String>?
    private var providers: Set<String> { refreshedProviders ?? appState.socialProviders }
    /// App Store 审核规则 4.8：有 Google 这类第三方登录，就必须同时提供能隐藏邮箱的登录（Apple）。
    /// 所以 Apple 没开时，App 里也不显示 Google（网页不受影响）
    private var socialProviders: Set<String> { providers.contains("apple") ? providers.intersection(["apple", "google"]) : [] }
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 0) {
            if step == .welcome {
                welcome
            } else {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        content
                    }
                    .padding(.horizontal, AppTheme.Spacing.screen)
                    .padding(.top, AppTheme.Spacing.sm)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            footer
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            step = appState.onboardingInitialStep
            if !appState.onboardingDemoAnswers.isEmpty { form.assessmentAnswers = appState.onboardingDemoAnswers }
        }
        .task {
            if appState.isRemote { refreshedProviders = await appState.refreshSocialProviders() }
            #if DEBUG
            // 截图时把 Apple、Google 按钮也显示出来，看欢迎页一屏放不放得下
            if UserDefaults.standard.string(forKey: "BBDemoScreen") == "welcome" { refreshedProviders = ["apple", "google"] }
            #endif
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
            IconButton(systemName: "chevron.left", accessibilityLabel: String(localized: "上一步")) { goBack() }
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
        case .welcome: EmptyView()
        case .phone: if appState.isRemote { emailStep } else { phoneStep }
        case .code: codeStep
        case .profile: profileStep
        case .level: levelStep
        case .preferences: preferencesStep
        }
    }

    // MARK: Welcome

    /// 只有 logo 和一句话，登录按钮在下面：一屏放得下，不用滚动（屏幕矮时 logo 自动缩小）
    private var welcome: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer(minLength: AppTheme.Spacing.md)
            AppLogo()
                .frame(minWidth: 88, maxWidth: 168, minHeight: 88, maxHeight: 168)
            Wordmark(size: 34)
            Text(marking: String(localized: "羽毛球搭子？\n就在*今日*！"))
                .font(AppTheme.Typography.display)
                .foregroundStyle(AppTheme.Colors.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.7)
            Spacer(minLength: AppTheme.Spacing.md)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Phone

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle(String(localized: "先用手机号\n登录或注册"), subtitle: String(localized: "未注册的手机号验证后会自动创建账号"))
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
                TextField(form.phoneCountry.phone.example.isEmpty ? String(localized: "请输入手机号") : form.phoneCountry.phone.example, text: $form.phone)
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

    // MARK: Email（正式后端）

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                stepTitle(form.newAccount ? String(localized: "注册 Badie") : String(localized: "用邮箱登录"),
                          subtitle: form.newAccount ? String(localized: "用邮箱和密码注册，我们会发一个验证码确认邮箱。")
                                                    : String(localized: "用注册时的邮箱和密码登录。"))
                Button(form.newAccount ? String(localized: "已有账号？去登录") : String(localized: "还没有账号？注册一个")) {
                    form.newAccount.toggle()
                    errorText = nil
                }
                .buttonStyle(TextActionStyle(color: AppTheme.Colors.ink))
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                TextField(String(localized: "邮箱"), text: $form.email)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .keyboardType(.emailAddress)
                    // .username：钥匙串把密码存到这个邮箱名下，下次自动填
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($phoneFocused)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(minHeight: 52)
                    .sticker(AppTheme.Colors.surface, radius: 14, shadow: phoneFocused ? AppTheme.Elevation.low : .zero,
                             stroke: errorText == nil ? AppTheme.Colors.stroke : AppTheme.Colors.danger)
                    .onChange(of: form.email) { _, _ in errorText = nil }
                    .accessibilityLabel("邮箱")
                PasswordField(text: $form.password, isNew: form.newAccount, invalid: errorText != nil) {
                    if canContinue { primaryAction() }
                }
                .onChange(of: form.password) { _, _ in errorText = nil }
                if form.newAccount {
                    Text("至少 8 位，用一句好记的话最方便。")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
            }
            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if form.newAccount {
                Button {
                    Haptics.selection()
                    form.agreed.toggle()
                } label: {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        Image(systemName: form.agreed ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(form.agreed ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                        Text("我已阅读并同意《用户协议》和《隐私政策》，了解邮箱仅用于登录与安全验证，不会展示给其他球友。")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(form.agreed ? [.isSelected, .isButton] : .isButton)
                LegalLinks()
            } else {
                // 忘了密码，或者以前用验证码登录、还没设过密码
                HStack {
                    Button("忘记密码？") { Task { await sendEmailCode(.recovery) } }
                    Spacer()
                    Button("改用邮箱验证码登录") { Task { await sendEmailCode(.email) } }
                }
                .buttonStyle(TextActionStyle())
                .disabled(isWorking || !captcha.isReady)
            }
        }
        .onAppear { phoneFocused = true }
    }

    // MARK: Code

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle(appState.isRemote && form.codePurpose == .recovery ? String(localized: "重设密码") : String(localized: "输入验证码"),
                      subtitle: String(localized: "已发送至 \(appState.isRemote ? form.email : form.phoneNumber.masked)"))
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
                        if digits.count == 6 && !(appState.isRemote && form.codePurpose == .recovery) { submitCode() }
                    }
                    .accessibilityLabel("验证码")
                HStack(spacing: AppTheme.Spacing.sm) {
                    let characters = Array(form.code)
                    ForEach(0..<6, id: \.self) { index in
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

            if appState.isRemote && form.codePurpose == .recovery {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    PasswordField(text: $form.password, placeholder: String(localized: "新密码"), isNew: true, invalid: errorText != nil) {
                        if canContinue { primaryAction() }
                    }
                    .onChange(of: form.password) { _, _ in errorText = nil }
                    Text("至少 8 位，用一句好记的话最方便。")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.inkTertiary)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.danger)
            }

            if let issued = form.issuedCode {
                NoticeBanner(icon: "message.badge.filled.fill", text: String(localized: "演示环境不发真实短信，验证码：\(issued)"),
                             tint: AppTheme.Colors.sky, actionTitle: String(localized: "填入")) {
                    form.code = issued
                }
            }

            Button(resendRemaining > 0 ? String(localized: "\(resendRemaining) 秒后可重新发送") : String(localized: "重新发送验证码")) {
                Task {
                    if appState.isRemote { await sendEmailCode(form.codePurpose) } else { await sendCode() }
                }
            }
            .buttonStyle(TextActionStyle())
            .disabled(resendRemaining > 0 || isWorking || (appState.isRemote && !captcha.isReady))
        }
        .onAppear { codeFocused = true }
    }

    // MARK: Profile

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle(String(localized: "怎么称呼你？"), subtitle: String(localized: "昵称和头像会展示给球友，手机号不会"))
            HStack {
                Spacer()
                AvatarView(text: form.avatar.symbol.isEmpty ? (form.nickname.first.map { String($0) } ?? "🏸") : form.avatar.symbol,
                           paletteIndex: form.avatar.paletteIndex, size: 96)
                    .background(Circle().fill(AppTheme.Colors.shadow).offset(x: 3, y: 4))
                Spacer()
            }
            AvatarPaletteEditor(avatar: $form.avatar)
            BrutalTextField(label: String(localized: "昵称"), placeholder: String(localized: "2-12 个字"), text: $form.nickname,
                            contentType: .nickname, errorText: errorText, characterLimit: 12)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                GenderPicker(selection: $form.gender)
            }
        }
    }

    // MARK: Level

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            stepTitle(String(localized: "测一下你的水平"), subtitle: String(localized: "\(SkillAssessment.questions.count) 道题，按你能稳定做到的选，自动算出你的等级（细分到 −、本级、+）"))
            SkillAssessmentView(answers: $form.assessmentAnswers)
            if form.assessmentResult == nil {
                Button {
                    form.skippedAssessment = true
                    advance(to: .preferences)
                } label: {
                    Text("暂时跳过，先按 Lv.\(SkillAssessment.provisionalLevel) 匹配")
                        .font(AppTheme.Typography.footnoteBold)
                        .underline()
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("之后可以在资料页完成定级")
            }
            Text("问卷最高到 6+（俱乐部顶尖）；7 起是州级以上，凭赛果、全国排名、运动员等级证书或 BWF 世界排名认证。打满 5 场后会按球友评价自动校准。")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Preferences

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            stepTitle(String(localized: "最后一步"), subtitle: String(localized: "这些偏好用于默认匹配设置，之后都能改"))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("常打")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                HStack(spacing: AppTheme.Spacing.sm) {
                    ChoiceChip(title: String(localized: "单打"), icon: GameMode.singles.icon, isSelected: form.preferredMode == .singles) {
                        form.preferredMode = .singles
                    }
                    ChoiceChip(title: String(localized: "双打"), icon: GameMode.doubles.icon, isSelected: form.preferredMode == .doubles) {
                        form.preferredMode = .doubles
                    }
                    ChoiceChip(title: String(localized: "都行"), isSelected: form.preferredMode == nil) {
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
                        ChoiceChip(title: preset.title, icon: preset.icon, isSelected: form.timePresets.contains(preset),
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
                    (venues.isEmpty ? Text("常去哪几个球馆？（选填）") : Text("常去球馆"))
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
                (locationManager.isAuthorized ? Text("已开启定位") : Text("开启定位"))
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
            // 发验证码前的人机验证：填邮箱和输入验证码（重新发送）两步都要
            if appState.isRemote && (step == .phone || step == .code) {
                captchaArea
            }
            if step == .welcome && !socialProviders.isEmpty {
                socialButtons
            }
            Button {
                primaryAction()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isWorking { LoadingDots() }
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.brutal(step == .welcome ? (socialProviders.isEmpty ? .inverse : .secondary) : .primary))
            .disabled(!canContinue || isWorking)
            if step == .welcome && !socialProviders.isEmpty {
                termsNote
            }
            if step == .welcome && !appState.isRemote {
                Text("登录即可体验，附近球友为演示数据")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                if DemoMode.isEnabled {
                    Button("退出演示模式") { host.setDemoMode(false) }
                        .buttonStyle(TextActionStyle())
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.md)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
    }

    /// 通过 Apple / Google 继续（Apple 放第一个：按 Apple 的规定不能比别的第三方登录不显眼）
    @ViewBuilder
    private var socialButtons: some View {
        if let errorText {
            Text(errorText)
                .font(AppTheme.Typography.footnoteBold)
                .foregroundStyle(AppTheme.Colors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if socialProviders.contains("apple") {
            Button {
                attemptSignIn {
                    let credential = try await AppleSignIn().run()
                    // Apple 只在第一次授权时给名字：先记下来当昵称的默认值
                    if form.nickname.isEmpty, let name = credential.givenName { form.nickname = name }
                    return try await appState.signInWithApple(idToken: credential.idToken, nonce: credential.nonce)
                }
            } label: {
                Label("通过 Apple 继续", systemImage: "apple.logo")
            }
            .buttonStyle(.brutal(.inverse))
        }
        if socialProviders.contains("google") {
            Button {
                attemptSignIn { try await appState.signInWithGoogle(webAuthenticationSession) }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image("GoogleLogo").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                    Text("使用 Google 账号继续")
                }
            }
            .buttonStyle(.brutal(.secondary))
        }
    }

    /// 第三方登录不打勾，所以用一行字说明：继续就算同意；协议和隐私政策可以点开
    private var termsNote: some View {
        Text("继续即表示你同意\(legalLink(String(localized: "用户协议"), LegalLinks.terms))和\(legalLink(String(localized: "隐私政策"), LegalLinks.privacy))。")
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.inkTertiary)
            .tint(AppTheme.Colors.inkSecondary)
            .multilineTextAlignment(.center)
    }

    private func legalLink(_ title: String, _ url: URL) -> AttributedString {
        var text = AttributedString(title)
        text.link = url
        text.underlineStyle = .single
        return text
    }

    /// 平时看不见；Cloudflare 要人点一下时才展开验证框
    private var captchaArea: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            CaptchaView(model: captcha)
                .frame(height: captcha.needsInteraction ? 72 : 1)
                .opacity(captcha.needsInteraction ? 1 : 0.01)
                .accessibilityHidden(!captcha.needsInteraction)
            if captcha.failed {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text("人机验证没加载出来，请检查网络后重试。")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") { captcha.reset() }
                        .buttonStyle(TextActionStyle())
                }
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return appState.isRemote ? String(localized: "邮箱登录 / 注册") : String(localized: "手机号登录 / 注册")
        case .phone:
            guard appState.isRemote else { return String(localized: "获取验证码") }
            return form.newAccount ? String(localized: "注册") : String(localized: "登录")
        case .code:
            return appState.isRemote && form.codePurpose == .recovery ? String(localized: "保存新密码并登录") : String(localized: "验证")
        case .profile, .level: return String(localized: "下一步")
        case .preferences: return String(localized: "完成，开始约球")
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome: return true
        case .phone:
            if appState.isRemote { return !form.email.isEmpty && !form.password.isEmpty && captcha.isReady && (form.agreed || !form.newAccount) }
            return form.phoneNumber.national.count >= form.phoneCountry.phone.lengths.lowerBound && form.agreed
        case .code: return form.code.count == 6 && (form.codePurpose != .recovery || !form.password.isEmpty)
        case .profile: return MockBackend.isValidNickname(form.nickname) && form.gender != .unspecified
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
            if appState.isRemote {
                guard MockBackend.isValidEmail(form.email) else {
                    errorText = String(localized: "邮箱地址好像不对。")
                    return
                }
                Task { await submitPassword() }
                return
            } else {
                guard form.phoneNumber.isValid else {
                    errorText = BackendError.invalidPhone.errorDescription
                    return
                }
            }
            Task {
                await sendCode()
                if form.codeSent { advance(to: .code) }
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
            if appState.isRemote {
                // 令牌只能用一次：不管成没成功都换一个新的，留给“重新发送”
                defer { captcha.reset() }
                try await appState.requestCode(email: form.email, captchaToken: captcha.token)
            } else {
                form.issuedCode = try await appState.requestCode(phone: form.phoneNumber.e164)
            }
            form.codeSent = true
            form.code = ""
            resendRemaining = 60
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
        }
    }

    /// 正式后端：邮箱 + 密码登录或注册。注册后要输入邮件里的码确认邮箱
    private func submitPassword() async {
        isWorking = true
        defer { isWorking = false }
        if form.newAccount, let problem = await PasswordRules.problem(form.password) {
            errorText = problem
            return
        }
        // 令牌只能用一次：不管成没成功都换一个新的
        defer { captcha.reset() }
        do {
            if !form.newAccount {
                signedIn(try await appState.signIn(email: form.email, password: form.password, captchaToken: captcha.token))
            } else if let outcome = try await appState.signUp(email: form.email, password: form.password, captchaToken: captcha.token) {
                signedIn(outcome)
            } else {
                codeSent(.signup)
            }
        } catch let RemoteError.server(code) where code == "user_already_exists" {
            form.newAccount = false
            errorText = RemoteError.server("user_already_exists").errorDescription
        } catch let RemoteError.server(code) where code == "email_not_confirmed" {
            form.codePurpose = .signup
            advance(to: .code)
            errorText = RemoteError.server("email_not_confirmed").errorDescription
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
            Haptics.error()
        }
    }

    /// 忘记密码、改用验证码登录、重发注册确认码：都是往邮箱发 6 位码
    private func sendEmailCode(_ purpose: CodePurpose) async {
        errorText = nil
        guard MockBackend.isValidEmail(form.email) else {
            errorText = String(localized: "请先填写邮箱。")
            return
        }
        isWorking = true
        defer { isWorking = false }
        defer { captcha.reset() }
        do {
            switch purpose {
            case .recovery: try await appState.sendPasswordReset(email: form.email, captchaToken: captcha.token)
            case .signup: try await appState.resendSignupCode(email: form.email, captchaToken: captcha.token)
            case .email: try await appState.requestCode(email: form.email, captchaToken: captcha.token)
            }
            // 重设密码：清掉刚才填错的旧密码，让人填新的
            if purpose == .recovery && form.codePurpose != .recovery { form.password = "" }
            codeSent(purpose)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
        }
    }

    private func codeSent(_ purpose: CodePurpose) {
        form.codePurpose = purpose
        form.codeSent = true
        form.code = ""
        resendRemaining = 60
        if step != .code { advance(to: .code) }
    }

    private func submitCode() {
        guard form.code.count == 6, !isWorking else { return }
        Task {
            isWorking = true
            defer { isWorking = false }
            let resetting = appState.isRemote && form.codePurpose == .recovery
            if resetting, let problem = await PasswordRules.problem(form.password) {
                errorText = problem
                return
            }
            do {
                let outcome = appState.isRemote
                    ? try await appState.verify(email: form.email, code: form.code, type: form.codePurpose.rawValue)
                    : try await appState.verify(phone: form.phoneNumber.e164, code: form.code)
                if resetting {
                    do {
                        try await appState.updatePassword(form.password)
                        appState.showToast(String(localized: "密码已保存"), style: .success)
                    } catch {
                        appState.showToast(String(localized: "已登录，但新密码没保存，可以在设置里重新设置。"), style: .error)
                    }
                }
                signedIn(outcome)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription
                form.code = ""
                Haptics.error()
            }
        }
    }

    /// 登录成功：老用户直接进 App，新用户去填资料
    private func signedIn(_ outcome: AuthOutcome) {
        switch outcome {
        case .signedIn(let user):
            appState.showToast(String(localized: "欢迎回来，\(user.nickname)"), style: .success)
        case .needsProfile:
            advance(to: .profile)
        }
    }

    /// Apple / Google 登录：自己关掉弹窗不提示；返回 nil 表示在对方页面取消了
    private func attemptSignIn(_ attempt: @escaping () async throws -> AuthOutcome?) {
        guard !isWorking else { return }
        errorText = nil
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                if let outcome = try await attempt() { signedIn(outcome) }
            } catch where AppleSignIn.isCancel(error) {
                return
            } catch {
                errorText = String(localized: "登录没有完成，请再试一次，或改用邮箱。")
                Haptics.error()
            }
        }
    }

    private func finish() async {
        guard let level = form.level else { return }
        let result = form.assessmentResult
        isWorking = true
        defer { isWorking = false }
        let slots = Array(form.timePresets.sorted { $0.rawValue < $1.rawValue }.flatMap(\.slots).prefix(TimeSlotConstants.maximumRecurringSlots))
        do {
            if appState.isRemote {
                try await appState.registerRemote(
                    nickname: form.nickname, gender: form.gender, avatar: form.avatar,
                    assessment: result.map {
                        SkillAssessmentSummary(level: level, needsCalibration: $0.needsCalibration,
                                               isReturning: $0.isReturning, assessedAt: Date(), rating: $0.tier.rating)
                    },
                    answers: form.assessmentAnswers
                )
                try? appState.backend.saveRecurringSlots(slots)
                if result == nil { appState.backend.markAssessmentSkipped() }
                for venueId in form.favoriteVenueIds where !locationManager.isFavorite(venueId) {
                    locationManager.toggleFavorite(venueId)
                }
                return
            }
            try await appState.register(
                phone: form.phoneNumber.e164,
                nickname: form.nickname,
                gender: form.gender,
                avatar: form.avatar,
                level: level,
                preferredMode: form.preferredMode,
                recurringSlots: slots,
                location: locationManager.currentLocation.map { Coordinate($0.coordinate) },
                assessment: result.map {
                    SkillAssessmentSummary(level: level, needsCalibration: $0.needsCalibration,
                                           isReturning: $0.isReturning, assessedAt: Date(), rating: $0.tier.rating)
                }
            )
            if result == nil { appState.backend.markAssessmentSkipped() }
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
        case .code, .profile: previous = .phone
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
                        ChoiceChip(title: symbol.isEmpty ? String(localized: "昵称首字") : symbol, isSelected: avatar.symbol == symbol) {
                            avatar.symbol = symbol
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - 文字高亮（柠檬色马克笔）

extension Text {
    /// 柠檬绿底色 + 墨色文字（深浅模式都可读）
    /// *星号* 之间的部分高亮，如 "找个*搭子*打一场"；整句一起翻译，高亮词位置随语言变
    init(marking text: String) {
        var result = AttributedString()
        for (index, part) in text.split(separator: "*", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            if !index.isMultiple(of: 2) {
                piece.backgroundColor = AppTheme.Colors.lime
                piece.foregroundColor = AppTheme.Colors.onAccent
            }
            result += piece
        }
        self.init(result)
    }
}
