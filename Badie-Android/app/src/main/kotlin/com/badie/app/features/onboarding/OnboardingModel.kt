package com.badie.app.features.onboarding

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.AuthOutcome
import com.badie.app.backend.Backend
import com.badie.app.design.Toast
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Avatar
import com.badie.app.models.Coordinate
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillAssessmentResult
import com.badie.app.models.SkillAssessmentSummary
import com.badie.app.models.Venue
import com.badie.app.remote.BrowserSignIn
import com.badie.app.remote.PasswordRules
import com.badie.app.remote.RemoteError
import com.badie.app.remote.SocialSignIn
import com.badie.app.remote.Transport
import com.badie.app.shell.AppState
import kotlinx.coroutines.CancellationException

enum class OnboardingStep {
    Welcome, Email, Code, Profile, Level, Preferences;

    /** 进度条里的序号（欢迎页不算） */
    val progressIndex: Int get() = ordinal

    companion object {
        const val PROGRESS_TOTAL = 5
    }
}

/** 邮件里的 6 位码用来做什么：确认注册的邮箱、验证码登录、重设密码（就是服务器校验时的 type） */
/** 常去球馆最多选几家 */
const val MAX_FAVORITE_VENUES = 3

enum class CodePurpose(val rawValue: String) { Signup("signup"), Email("email"), Recovery("recovery") }

/**
 * 登录和注册的流程：每一步填了什么、现在能不能继续、点了按钮做什么。界面只管照着画。
 * 对应 iPhone 的 OnboardingFlow（正式后端那一路）
 */
@Stable
class OnboardingModel(
    private val appState: AppState,
    val captcha: CaptchaModel,
    /** 查密码有没有泄露过用的请求 */
    private val passwordLookup: Transport,
    private val now: () -> Long = System::currentTimeMillis,
    /** 从哪一步开始（截图用） */
    initialStep: OnboardingStep = OnboardingStep.Welcome,
    /** 上次问到的后台开了的第三方登录（apple / google）；第一次打开时为空，当作都开着 */
    savedProviders: Set<String>? = null,
    private val saveProviders: (Set<String>) -> Unit = {},
) {
    private val backend: Backend get() = appState.backend

    var step by mutableStateOf(initialStep)
        private set

    var agreed by mutableStateOf(false)
    var email by mutableStateOf("")
    var password by mutableStateOf("")
    /** true 是注册，false 是登录 */
    var newAccount by mutableStateOf(false)
    var codePurpose by mutableStateOf(CodePurpose.Email)
        private set
    var code by mutableStateOf("")
        private set
    var nickname by mutableStateOf("")
    var gender by mutableStateOf(Gender.Unspecified)
    var avatar by mutableStateOf(Avatar("", 0))
    /** 定级问卷的答案（题目 ID → 选项） */
    val assessmentAnswers = mutableStateMapOf<String, Int>()
    /** 暂时跳过定级（先按 Lv.3 匹配） */
    var skippedAssessment by mutableStateOf(false)
        private set
    var preferredMode by mutableStateOf<GameMode?>(null)
    /** 常去球馆（必选，最多 3 家；注册后设为收藏，快速匹配默认选中，附近的人也按它找人） */
    val favoriteVenueIds = mutableStateListOf<String>()
    /** 真实的位置；没开定位时为空（列表的距离按默认城市算，但不替人选最近的球馆） */
    var location by mutableStateOf<Coordinate?>(null)
        private set
    /** 附近的球馆，按距离排 */
    var nearbyVenues by mutableStateOf<List<Venue>>(emptyList())
        private set
    /** 已经替用户选过最近的球馆（只选一次，用户删掉后不再选回来） */
    private var venuePreselected = false

    var isWorking by mutableStateOf(false)
        private set
    var errorText by mutableStateOf<String?>(null)
    /** 还要等几秒才能重新发验证码 */
    var resendRemaining by mutableIntStateOf(0)

    val assessmentResult: SkillAssessmentResult? get() = SkillAssessment.evaluate(assessmentAnswers)

    /** 问卷自动算出的等级；跳过时暂用 Lv.3 */
    val level: Int? get() = assessmentResult?.level ?: if (skippedAssessment) SkillAssessment.PROVISIONAL_LEVEL else null

    val isResettingPassword: Boolean get() = codePurpose == CodePurpose.Recovery

    val primaryTitle: String
        get() = when (step) {
            OnboardingStep.Welcome -> tr("邮箱登录 / 注册")
            OnboardingStep.Email -> if (newAccount) tr("注册") else tr("登录")
            OnboardingStep.Code -> if (isResettingPassword) tr("保存新密码并登录") else tr("验证")
            OnboardingStep.Profile, OnboardingStep.Level -> tr("下一步")
            OnboardingStep.Preferences -> tr("开始约球")
        }

    val canContinue: Boolean
        get() = when (step) {
            OnboardingStep.Welcome -> true
            OnboardingStep.Email -> email.isNotEmpty() && password.isNotEmpty() && captcha.isReady && (agreed || !newAccount)
            OnboardingStep.Code -> code.length == 6 && (!isResettingPassword || password.isNotEmpty())
            OnboardingStep.Profile -> Backend.isValidNickname(nickname) && gender != Gender.Unspecified
            OnboardingStep.Level -> level != null
            OnboardingStep.Preferences -> favoriteVenueIds.isNotEmpty()
        }

    fun toggleNewAccount() {
        newAccount = !newAccount
        errorText = null
    }

    /** 改了输入：出错的提示收起来 */
    fun edited() {
        errorText = null
    }

    /** 输验证码：只收 6 位数字；输满自动提交（重设密码还要填新密码，不自动提交） */
    suspend fun updateCode(value: String) {
        code = value.filter { it in '0'..'9' }.take(6)
        errorText = null
        if (code.length == 6 && !isResettingPassword) submitCode()
    }

    suspend fun primaryAction() {
        errorText = null
        when (step) {
            OnboardingStep.Welcome -> step = OnboardingStep.Email
            OnboardingStep.Email -> {
                if (!Backend.isValidEmail(email)) {
                    errorText = tr("邮箱地址好像不对。")
                    return
                }
                submitPassword()
            }
            OnboardingStep.Code -> submitCode()
            OnboardingStep.Profile -> {
                if (!Backend.isValidNickname(nickname)) {
                    errorText = tr("昵称需为 2-12 个字符")
                    return
                }
                step = OnboardingStep.Level
            }
            OnboardingStep.Level -> step = OnboardingStep.Preferences
            OnboardingStep.Preferences -> finish()
        }
    }

    // MARK: 常去球馆

    /** 拿到（或拿不到）位置以后：读附近的球馆；知道真实位置时先替用户选上最近的一家（可以改） */
    suspend fun locationUpdated(coordinate: Coordinate?) {
        if (coordinate != null) location = coordinate
        val center = location ?: Coordinate.fallbackCenter
        nearbyVenues = try {
            backend.venuesNear(center, Venue.DEFAULT_TRAVEL_RADIUS_KM).sortedBy { it.distanceKm(center) }
        } catch (_: RemoteError) {
            nearbyVenues
        }
        val here = location ?: return
        if (venuePreselected || favoriteVenueIds.isNotEmpty()) return
        val nearest = Venue.nearest(nearbyVenues, here, Venue.DEFAULT_TRAVEL_RADIUS_KM) ?: return
        venuePreselected = true
        favoriteVenueIds.add(nearest.id)
    }

    /** 选或取消一家；最多 3 家 */
    fun toggleVenue(id: String) {
        if (id in favoriteVenueIds) favoriteVenueIds.remove(id)
        else if (favoriteVenueIds.size < MAX_FAVORITE_VENUES) favoriteVenueIds.add(id)
    }

    fun venue(id: String): Venue? = backend.venue(id)

    suspend fun searchVenues(query: String): List<Venue> = try {
        val center = location ?: Coordinate.fallbackCenter
        backend.searchVenues(query).sortedBy { it.distanceKm(center) }
    } catch (_: RemoteError) {
        emptyList()
    }

    fun skipAssessment() {
        skippedAssessment = true
        step = OnboardingStep.Preferences
    }

    fun goBack() {
        errorText = null
        step = when (step) {
            OnboardingStep.Welcome, OnboardingStep.Email -> OnboardingStep.Welcome
            OnboardingStep.Code, OnboardingStep.Profile -> OnboardingStep.Email
            OnboardingStep.Level -> OnboardingStep.Profile
            OnboardingStep.Preferences -> OnboardingStep.Level
        }
    }

    /** 邮箱 + 密码登录或注册。注册后要输入邮件里的码确认邮箱 */
    private suspend fun submitPassword() = working {
        if (newAccount) {
            PasswordRules.problem(password, passwordLookup)?.let {
                errorText = it
                return@working
            }
        }
        // 令牌只能用一次：不管成没成功都换一个新的
        val token = captcha.token
        try {
            if (!newAccount) {
                signedIn(backend.signIn(email, password, token))
            } else {
                val outcome = backend.signUp(email, password, token)
                if (outcome != null) signedIn(outcome) else codeSent(CodePurpose.Signup)
            }
        } catch (error: RemoteError) {
            val known = (error as? RemoteError.Server)?.code
            when (known) {
                // 已经注册过：切回登录
                "user_already_exists" -> newAccount = false
                // 注册了但还没确认邮箱：去输确认码
                "email_not_confirmed" -> {
                    codePurpose = CodePurpose.Signup
                    step = OnboardingStep.Code
                }
            }
            errorText = error.message
        } finally {
            captcha.reset()
        }
    }

    /** 忘记密码、改用验证码登录、重发注册确认码：都是往邮箱发 6 位码 */
    suspend fun sendEmailCode(purpose: CodePurpose) {
        errorText = null
        if (!Backend.isValidEmail(email)) {
            errorText = tr("请先填写邮箱。")
            return
        }
        working {
            val token = captcha.token
            try {
                when (purpose) {
                    CodePurpose.Recovery -> backend.sendPasswordReset(email, token)
                    CodePurpose.Signup -> backend.resendSignupCode(email, token)
                    CodePurpose.Email -> backend.sendCode(email, token)
                }
                // 重设密码：清掉刚才填错的旧密码，让人填新的
                if (purpose == CodePurpose.Recovery && codePurpose != CodePurpose.Recovery) password = ""
                codeSent(purpose)
            } catch (error: RemoteError) {
                errorText = error.message
            } finally {
                captcha.reset()
            }
        }
    }

    private fun codeSent(purpose: CodePurpose) {
        codePurpose = purpose
        code = ""
        resendRemaining = 60
        step = OnboardingStep.Code
    }

    private suspend fun submitCode() {
        if (code.length != 6 || isWorking) return
        working {
            val resetting = isResettingPassword
            if (resetting) {
                PasswordRules.problem(password, passwordLookup)?.let {
                    errorText = it
                    return@working
                }
            }
            try {
                val outcome = backend.verify(email, code, codePurpose.rawValue)
                if (resetting) {
                    try {
                        backend.updatePassword(password)
                        appState.showToast(tr("密码已保存"), Toast.Style.Success)
                    } catch (_: RemoteError) {
                        appState.showToast(tr("已登录，但新密码没保存，可以在设置里重新设置。"), Toast.Style.Error)
                    }
                }
                signedIn(outcome)
            } catch (error: RemoteError) {
                errorText = error.message
                code = ""
            }
        }
    }

    // MARK: Apple、Google 登录

    /** 后台开了的第三方登录。先用记下的结果马上显示，后台问到新的再换 */
    var providers by mutableStateOf(savedProviders ?: setOf("apple", "google"))
        private set

    /**
     * 欢迎页显示哪几个按钮。和 iPhone 一样：Apple 没开时 Google 也不显示
     * （iPhone 是因为 App Store 审核规则 4.8，安卓照搬，两边一致）
     */
    val socialProviders: Set<String>
        get() {
            if ("apple" !in providers) return emptySet()
            return providers.intersect(if (SocialSignIn.googleServerClientId == null) setOf("apple") else setOf("apple", "google"))
        }

    /** 问服务器开了哪些，并记下来；网络不通就还用上一次的结果 */
    suspend fun refreshProviders() {
        val fresh = backend.remote.enabledProviders() ?: return
        providers = fresh
        saveProviders(fresh)
    }

    /** 通过 Apple 继续：在浏览器里走 Supabase 的 Apple 授权，跳回来以后用 code 换登录状态 */
    suspend fun signInWithApple(browser: BrowserAuth) = attemptSignIn {
        val flow = BrowserSignIn("apple")
        val callback = browser.open(flow.url) ?: return@attemptSignIn null
        val code = flow.code(callback) ?: return@attemptSignIn null
        backend.signInWithCode(code, flow.verifier)
    }

    /** 使用 Google 账号继续：凭据管理器给身份令牌，像 iPhone 一样交给 Supabase */
    suspend fun signInWithGoogle(google: GoogleCredentials) = attemptSignIn {
        val clientId = SocialSignIn.googleServerClientId ?: return@attemptSignIn null
        val nonce = SocialSignIn.randomString()
        val idToken = google.idToken(clientId, SocialSignIn.sha256Hex(nonce)) ?: return@attemptSignIn null
        backend.signInWithIdToken("google", idToken, nonce)
    }

    /** 自己取消了（返回 null）不提示；别的错误统一一句话 */
    private suspend fun attemptSignIn(attempt: suspend () -> AuthOutcome?) {
        if (isWorking) return
        errorText = null
        working {
            try {
                attempt()?.let { signedIn(it) }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                errorText = tr("登录没有完成，请再试一次，或改用邮箱。")
            }
        }
    }

    /** 登录成功：老用户直接进 App，新用户去填资料 */
    private fun signedIn(outcome: AuthOutcome) {
        when (outcome) {
            is AuthOutcome.SignedIn -> {
                // 重设密码时已经提示过“密码已保存”，不再盖掉
                if (!isResettingPassword) appState.showToast(tr("欢迎回来，%@", outcome.user.nickname), Toast.Style.Success)
                appState.syncPhase()
            }
            is AuthOutcome.NeedsProfile -> step = OnboardingStep.Profile
        }
    }

    private suspend fun finish() {
        val level = level ?: return
        if (favoriteVenueIds.isEmpty()) return
        val result = assessmentResult
        working {
            try {
                backend.register(
                    nickname, gender, avatar,
                    assessment = result?.let {
                        SkillAssessmentSummary(level, it.needsCalibration, it.isReturning, assessedAt = now(), rating = it.tier.rating)
                    },
                    answers = assessmentAnswers.toMap(),
                )
            } catch (error: Exception) {
                appState.showError(error)
                return@working
            }
            // 资料建好就算注册成功；下面几项没存上不拦着进 App，以后在设置里能改。
            // 注册后默认在附近的人里显示（就是设置里的“在同馆常客里显示我”，之后可以在设置里关）
            try {
                if (backend.currentUser?.privacy?.showsAsRegular == false) backend.updateShowsAsRegular(true)
                backend.saveFavoriteVenues(favoriteVenueIds.toList())
                if (preferredMode != null) backend.updatePreferredMode(preferredMode)
            } catch (_: RemoteError) {
            }
            appState.showToast(tr("注册成功，欢迎加入"), Toast.Style.Success)
            appState.syncPhase()
        }
    }

    private suspend fun working(block: suspend () -> Unit) {
        isWorking = true
        try {
            block()
        } finally {
            isWorking = false
        }
    }
}
