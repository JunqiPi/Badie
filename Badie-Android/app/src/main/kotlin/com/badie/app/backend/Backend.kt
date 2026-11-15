package com.badie.app.backend

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Avatar
import com.badie.app.models.CardColor
import com.badie.app.models.ChallengePolicy
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.PrivacySettings
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillAssessmentResult
import com.badie.app.models.SkillAssessmentSummary
import com.badie.app.models.SkillLevel
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.InstantSerializer
import com.badie.app.remote.RemoteError
import com.badie.app.remote.RemoteSession
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.time.Instant

/** 登录以后：老用户直接进 App，新用户去填资料 */
sealed interface AuthOutcome {
    data class SignedIn(val user: User) : AuthOutcome
    data class NeedsProfile(val email: String) : AuthOutcome
}

/** 本机不合规的输入（服务器的错误是 RemoteError） */
class BackendError(override val message: String) : Exception(message)

/** 存在本机的缓存：离线时先用它进主界面。退出登录就清掉 */
@Serializable
data class CachedState(val user: User? = null, val favoriteVenueIds: List<String> = emptyList())

class CacheStore(val load: () -> String?, val save: (String?) -> Unit) {
    companion object {
        /** 测试用：不存 */
        val memory get() = CacheStore({ null }, {})
    }
}

/**
 * 账号、资料和各项功能的数据都从这里走：调服务器，把结果记在本机当缓存，界面读缓存。
 * 对应 iPhone 的 MockBackend 里连正式后端的那部分（MockBackend+Remote*.swift）。演示数据那部分最后再搬
 */
class Backend(
    val remote: SupabaseClient,
    private val cache: CacheStore,
    private val now: () -> Long = System::currentTimeMillis,
    /** 设备的地区（两位字母），注册时记到资料里 */
    private val deviceCountry: () -> String,
    /** 通知和邮件用 App 当前的界面语言 */
    private val serverLocale: () -> String,
) {
    private var state: CachedState = loadCache()
        set(value) {
            field = value
            currentUser = value.user
            cache.save(if (value.user == null) null else cacheJson.encodeToString(CachedState.serializer(), value))
        }

    /** 当前登录的用户（界面跟着它变） */
    var currentUser: User? by mutableStateOf(state.user)
        private set

    /** 管理员才看得到演示模式的开关 */
    var isAdmin: Boolean by mutableStateOf(false)
        private set

    val favoriteVenueIds: List<String> get() = state.favoriteVenueIds

    private fun loadCache(): CachedState = try {
        cache.load()?.let { cacheJson.decodeFromString(CachedState.serializer(), it) } ?: CachedState()
    } catch (_: SerializationException) {
        CachedState()
    } catch (_: IllegalArgumentException) {
        CachedState()
    }

    // MARK: 登录

    suspend fun sendCode(email: String, captchaToken: String?) = remote.sendCode(normalizedEmail(email), captchaToken)

    /** 输入邮件里的 6 位码：type 是 email（验证码登录）、signup（确认注册的邮箱）或 recovery（重设密码） */
    suspend fun verify(email: String, code: String, type: String = "email"): AuthOutcome =
        outcome(remote.verify(normalizedEmail(email), code, type))

    /** 邮箱 + 密码注册：要先确认邮箱时返回 null（确认码已发出） */
    suspend fun signUp(email: String, password: String, captchaToken: String?): AuthOutcome? =
        remote.signUp(normalizedEmail(email), password, captchaToken)?.let { outcome(it) }

    suspend fun signIn(email: String, password: String, captchaToken: String?): AuthOutcome =
        outcome(remote.signIn(normalizedEmail(email), password, captchaToken))

    suspend fun sendPasswordReset(email: String, captchaToken: String?) = remote.sendPasswordReset(normalizedEmail(email), captchaToken)

    suspend fun resendSignupCode(email: String, captchaToken: String?) = remote.resendSignupCode(normalizedEmail(email), captchaToken)

    suspend fun updatePassword(password: String) = remote.updatePassword(password)

    /** 登录成功（密码、验证码、Apple、Google 都一样）：有资料就直接登录，没有就去填资料 */
    private suspend fun outcome(session: RemoteSession): AuthOutcome {
        val user = refreshProfile()
        return if (user != null) AuthOutcome.SignedIn(user) else AuthOutcome.NeedsProfile(session.email ?: "")
    }

    /** 第一次登录：建资料（含定级用的性别），做过问卷就保存定级。头像的颜色和表情目前只存在本机 */
    suspend fun register(nickname: String, gender: Gender, avatar: Avatar, assessment: SkillAssessmentSummary?, answers: Map<String, Int>): User {
        val userId = remote.session?.userId ?: throw RemoteError.NotSignedIn
        if (!isValidNickname(nickname)) throw BackendError(tr("昵称需为 2-12 个字符"))
        remote.insert(
            "profiles",
            json("id" to userId, "nickname" to nickname.trim(), "country_code" to registrationCountry(), "gender" to gender.serverJSON),
        )
        if (assessment != null) {
            remote.call("save_assessment", json("p_rating" to assessment.tier.rating, "p_answers" to answers))
        }
        val user = (refreshProfile() ?: throw RemoteError.Server("no_profile")).copy(avatar = avatar)
        state = state.copy(user = user)
        return user
    }

    /** 注册时记的地区：只认我们列出来的那些，别的按美国算（和 iPhone 一样） */
    private fun registrationCountry(): String = deviceCountry().uppercase().takeIf { it in COUNTRIES } ?: COUNTRIES.first()

    /** 启动时：本机有登录状态就刷新资料；登录失效或资料没建完就回到登录页。离线时先用缓存 */
    suspend fun restoreSession() {
        if (remote.session == null) return signOutLocally()
        try {
            if (refreshProfile() == null) signOutLocally()
        } catch (_: RemoteError.NotSignedIn) {
            signOutLocally()
        } catch (_: RemoteError) {
            // 网络问题：保持缓存里的登录状态
        }
    }

    /** 只清本机的登录状态（服务器那边已经失效，或者从没登录过） */
    fun signOutLocally() {
        isAdmin = false
        if (state.user != null) state = CachedState()
    }

    /** 退出登录：清掉这个账号留在本机的东西，换账号登录时不会看到 */
    suspend fun signOut() {
        remote.signOut()
        signOutLocally()
    }

    // MARK: 资料

    /** 读自己的资料和收藏写进缓存；还没建资料时返回 null */
    suspend fun refreshProfile(): User? {
        val session = remote.session ?: throw RemoteError.NotSignedIn
        val profile = remote.select<List<RemoteProfile>>("profiles", "id=eq.${session.userId}&select=*").firstOrNull() ?: return null
        val favorites = remote.select<List<FavoriteRow>>("favorite_venues", "select=venue_id&order=created_at").map { it.venueId }
        // 写缓存之前查：设置页据此决定显不显示演示模式的开关
        isAdmin = try {
            remote.rpc<Boolean>("is_admin")
        } catch (_: RemoteError) {
            false
        }
        val user = user(profile, email = session.email)
        state = CachedState(user, favorites)
        if (profile.locale != serverLocale()) {
            try {
                remote.update("profiles", "id=eq.${profile.id}", json("locale" to serverLocale()))
            } catch (_: RemoteError) {
                // 下次登录再对
            }
        }
        return user
    }

    /** 服务器的资料换成本机的用户；本机才有的东西（头像的颜色和表情、定级时的标记）接着用原来的 */
    private fun user(profile: RemoteProfile, email: String?): User {
        val tier = SkillTier.ofRating(profile.rating)
        val known = state.user?.takeIf { it.id == profile.id }
            ?: User(id = profile.id, nickname = profile.nickname, phone = email ?: "", selfReportedLevel = tier.level)
        val assessedAt = profile.assessedAt?.toEpochMilli()
        val assessment = assessedAt?.let {
            val kept = known.assessment?.takeIf { it.assessedAt == assessedAt }
                ?: SkillAssessmentSummary(tier.level, needsCalibration = false, isReturning = false, assessedAt = assessedAt, rating = profile.rating)
            kept.copy(answers = profile.answers)
        }
        val kind = VerificationStatus.ofServer(profile.verifiedKind)
        return known.copy(
            nickname = profile.nickname,
            tag = profile.tag,
            friendCode = profile.friendCode,
            selfReportedLevel = minOf(tier.level, SkillLevel.MAX_SELF_SELECTABLE),
            selfReportedRating = profile.rating,
            assessment = assessment,
            assessmentSkippedAt = if (assessedAt == null) known.assessmentSkippedAt ?: now() else known.assessmentSkippedAt,
            joinDate = profile.createdAt?.toEpochMilli() ?: known.joinDate,
            privacy = PrivacySettings(
                showsAsRegular = profile.showAsRegular ?: false,
                allowsMessageRequests = profile.allowMessageRequests ?: true,
                challengePolicy = ChallengePolicy.ofServer(profile.challengePolicy),
                showsOnLeaderboards = profile.showOnBoards,
                findableByNickname = profile.discoverable ?: true,
                emailAlerts = profile.emailAlerts ?: false,
                showsWhenSearching = profile.showSearching ?: true,
            ),
            gender = Gender.ofServer(profile.gender),
            preferredMode = profile.preferredMode?.let(GameMode::ofServer) ?: known.preferredMode,
            avatar = known.avatar.copy(cardColor = CardColor.of(profile.cardColor)),
        ).let { user ->
            if (kind != null && profile.verifiedRating != null) {
                user.applyingVerification(kind, SkillTier.ofRating(profile.verifiedRating))
            } else {
                user.applyingVerification(VerificationStatus.Unverified, tier)
            }
        }
    }

    /** 定级（注册后补测，或 90 天后重测） */
    suspend fun saveAssessment(result: SkillAssessmentResult, answers: Map<String, Int>): User {
        val tier = minOf(result.tier, SkillAssessment.maxTier)
        remote.call("save_assessment", json("p_rating" to tier.rating, "p_answers" to answers))
        val user = refreshProfile() ?: throw RemoteError.NotSignedIn
        val marked = user.copy(assessment = user.assessment?.copy(needsCalibration = result.needsCalibration, isReturning = result.isReturning))
        state = state.copy(user = marked)
        return marked
    }

    /** 改资料或隐私：先改本机的，再同步到服务器；没同步上就按服务器的数据恢复 */
    suspend fun updateProfile(values: JsonObject, change: (User) -> User) {
        val user = state.user ?: throw RemoteError.NotSignedIn
        state = state.copy(user = change(user))
        try {
            remote.update("profiles", "id=eq.${user.id}", values)
        } catch (error: RemoteError) {
            try {
                refreshProfile()
            } catch (_: RemoteError) {
                state = state.copy(user = user)
            }
            throw error
        }
    }

    /** 在 App 里换了语言：通知、邮件也跟着换。没同步上的话，下次读资料时会再对一次 */
    suspend fun syncServerLocale() {
        val id = state.user?.id ?: return
        try {
            remote.update("profiles", "id=eq.$id", json("locale" to serverLocale()))
        } catch (_: RemoteError) {
        }
    }

    /** 以前注册、还没选性别的人补选 */
    suspend fun updateGender(gender: Gender) = updateProfile(json("gender" to gender.serverJSON)) { it.copy(gender = gender) }

    /** 在常去球馆的“同馆常客”、附近的人里显示我 */
    suspend fun updateShowsAsRegular(shows: Boolean) =
        updateProfile(json("show_as_regular" to shows)) { it.copy(privacy = it.privacy.copy(showsAsRegular = shows)) }

    /** 常打单打还是双打（null = 都行） */
    suspend fun updatePreferredMode(mode: GameMode?) =
        updateProfile(json("preferred_mode" to mode?.serverValue)) { it.copy(preferredMode = mode) }

    companion object {
        private val cacheJson = Json { ignoreUnknownKeys = true }

        /** 注册时能记的地区，第一个是默认的（iPhone 的 CountryInfo.all） */
        val COUNTRIES = listOf("US", "CA", "CN", "HK", "TW", "SG", "MY", "JP", "KR", "GB", "AU", "IN", "ID", "TH", "VN", "PH", "DK", "NZ", "DE", "FR")

        private val emailPattern = Regex("""^[^@\s]+@[^@\s]+\.[^@\s]+$""")

        fun normalizedEmail(email: String): String = email.trim().lowercase()

        fun isValidEmail(email: String): Boolean = emailPattern.matches(normalizedEmail(email))

        /** 昵称 2–12 个字（表情算一个字） */
        fun isValidNickname(nickname: String): Boolean {
            val trimmed = nickname.trim()
            return trimmed.codePointCount(0, trimmed.length) in 2..12
        }
    }
}

/** 自己的资料（profiles 表只能读到本人这一行） */
@Serializable
class RemoteProfile(
    val id: String,
    val nickname: String,
    val countryCode: String? = null,
    val rating: Double,
    @Serializable(InstantSerializer::class) val assessedAt: Instant? = null,
    val showOnBoards: Boolean,
    val challengePolicy: String,
    val discoverable: Boolean? = null,
    val showAsRegular: Boolean? = null,
    val showSearching: Boolean? = null,
    val allowMessageRequests: Boolean? = null,
    val emailAlerts: Boolean? = null,
    val verifiedKind: String? = null,
    val verifiedRating: Double? = null,
    val avatarPath: String? = null,
    val cardColor: String? = null,
    val cardPhotoPath: String? = null,
    val locale: String,
    val gender: String? = null,
    @Serializable(InstantSerializer::class) val createdAt: Instant? = null,
    val tag: Int? = null,
    val friendCode: String? = null,
    /** 常打单打还是双打（null = 都行） */
    val preferredMode: String? = null,
    /** 问卷答案（题目 ID → 选项序号），算打法用 */
    val assessment: JsonElement? = null,
) {
    /** 问卷答案：格式不对就当没有，不让整份资料读不出来 */
    val answers: Map<String, Int>?
        get() {
            val entries = (assessment as? JsonObject)?.entries ?: return null
            return entries.associate { (key, value) -> key to ((value as? JsonPrimitive)?.intOrNull ?: return null) }
        }
}

@Serializable
private class FavoriteRow(val venueId: String)
