package com.badie.app.backend

import android.content.Context
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.CardColor
import com.badie.app.models.ContactInfoDetector
import com.badie.app.models.DISTANT_FUTURE
import com.badie.app.models.Gender
import com.badie.app.models.MyStrikes
import com.badie.app.models.PrivacySettings
import com.badie.app.models.Rankings
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.ServerUsualTime
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.User
import com.badie.app.models.UserPreferences
import com.badie.app.models.VerificationRequest
import com.badie.app.models.VerificationStatus
import com.badie.app.models.activeSlots
import com.badie.app.models.serverJSON
import com.badie.app.remote.InstantSerializer
import com.badie.app.remote.RemoteError
import com.badie.app.remote.RemoteJSON
import com.badie.app.remote.json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.WeakHashMap

/** 本机存的小东西（按键存字符串）：常用时间、附近范围、问过哪些权限。测试里用 [memory] */
class ProfileStore(val load: (String) -> String?, val save: (String, String?) -> Unit) {
    companion object {
        val memory: ProfileStore
            get() {
                val values = HashMap<String, String>()
                return ProfileStore({ values[it] }, { key, value -> if (value == null) values.remove(key) else values[key] = value })
            }

        /** 存在 App 自己的 SharedPreferences 里（和外观同一个文件） */
        fun preferences(context: Context): ProfileStore {
            val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
            return ProfileStore({ prefs.getString(it, null) }, { key, value -> prefs.edit { if (value == null) remove(key) else putString(key, value) } })
        }
    }
}

/** 球馆的名字和城市（“我的”页、等级卡片上用） */
@Serializable
data class VenueName(val id: String, val name: String, val city: String? = null)

/** 我的爽约：近 180 天算数的次数，和暂停约球到什么时候（永久是 [DISTANT_FUTURE]） */
data class StrikeSummary(val recent: Int, val suspendedUntil: Long?)

/**
 * “我的”、编辑资料、设置、认证、反馈要调的接口和本机的设置。
 * 对应 iPhone 的 MockBackend+Remote.swift（注销、资料）、+RemoteVerification、+RemoteRequests（反馈）、
 * +RemoteRankings（my_record）、+RemoteSocial（my_strikes）里的那几个函数，和 MockBackend 里存常用时间的部分
 */
@Stable
class ProfileApi(
    val backend: Backend,
    private val store: ProfileStore,
    private val scope: CoroutineScope,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val remote get() = backend.remote

    // MARK: 常用时间（就是“空闲时间”：最多 5 段，每段 1–8 小时）

    /** 按用户存：自己的以本机为准（关掉的几段只在本机），打开的几段同步到 profiles.usual_times */
    private val slotsByUser = mutableStateMapOf<String, List<RecurringTimeSlot>>()

    /** 当前用户的常用时间 */
    fun recurringSlots(): List<RecurringTimeSlot> {
        val id = backend.currentUser?.id ?: return emptyList()
        return slotsByUser[id] ?: loadSlots(id).also { slotsByUser[id] = it }
    }

    private fun slotsKey(userId: String) = "recurringSlots-$userId"

    private fun loadSlots(userId: String): List<RecurringTimeSlot> = try {
        store.load(slotsKey(userId))?.let { storeJson.decodeFromString(ListSerializer(RecurringTimeSlot.serializer()), it) } ?: emptyList()
    } catch (_: SerializationException) {
        emptyList()
    } catch (_: IllegalArgumentException) {
        emptyList()
    }

    private fun keepSlots(userId: String, slots: List<RecurringTimeSlot>) {
        slotsByUser[userId] = slots
        store.save(slotsKey(userId), storeJson.encodeToString(ListSerializer(RecurringTimeSlot.serializer()), slots))
    }

    /** 存常用时间：超过 5 段、时长不对就报错；改了马上存本机，后台把打开的几段传到资料里（附近的人能看到） */
    fun saveRecurringSlots(slots: List<RecurringTimeSlot>) {
        val id = backend.currentUser?.id ?: throw RemoteError.NotSignedIn
        if (slots.size > TimeSlotConstants.MAXIMUM_RECURRING_SLOTS) {
            throw BackendError(tr("最多保存 %lld 个常用时间", TimeSlotConstants.MAXIMUM_RECURRING_SLOTS))
        }
        if (!slots.all { it.isValidDuration }) throw BackendError(tr("每个时间段需要 1-8 小时"))
        keepSlots(id, slots)
        val times = slots.activeSlots.map { it.serverJSON }
        scope.launch {
            try {
                remote.update("profiles", "id=eq.$id", json("usual_times" to times))
            } catch (_: RemoteError) {
                // 下次改的时候再传
            }
        }
    }

    /**
     * 登录时对一下空闲时间：服务器有就用服务器的（网站上也能改，本机关掉的几段留着）；
     * 服务器上还没有、本机有，补传一次。对应 iPhone 的 syncUsualTimes
     */
    suspend fun syncUsualTimes() {
        val id = backend.currentUser?.id ?: return
        val rows = remote.select<List<UsualTimesRow>>("profiles", "id=eq.$id&select=usual_times")
        val server = rows.firstOrNull()?.usualTimes ?: emptyList()
        val local = recurringSlots()
        val uploadedKey = "usualTimesUploaded-$id"
        if (server.isEmpty()) {
            val active = local.activeSlots
            if (active.isEmpty() || store.load(uploadedKey) != null) return
            store.save(uploadedKey, "1")
            try {
                remote.update("profiles", "id=eq.$id", json("usual_times" to active.map { it.serverJSON }))
            } catch (_: RemoteError) {
            }
            return
        }
        store.save(uploadedKey, "1")
        if (server.toSet() == local.activeSlots.map { it.serverValue }.toSet()) return
        val fromServer = server.mapNotNull(RecurringTimeSlot::ofServer)
        val inactive = local.filter { !it.isActive && it.serverValue !in server }
        keepSlots(id, (fromServer + inactive).take(TimeSlotConstants.MAXIMUM_RECURRING_SLOTS))
    }

    // MARK: 附近范围（只存在本机）

    var travelRadiusKm by mutableDoubleStateOf(
        store.load(TRAVEL_RADIUS_KEY)?.toDoubleOrNull()?.takeIf { UserPreferences.default.isValidTravelRadius(it) }
            ?: UserPreferences.DEFAULT_TRAVEL_RADIUS,
    )
        private set

    fun updateTravelRadius(km: Double) {
        val clamped = km.coerceIn(UserPreferences.MINIMUM_TRAVEL_RADIUS, UserPreferences.MAXIMUM_TRAVEL_RADIUS)
        travelRadiusKm = clamped
        store.save(TRAVEL_RADIUS_KEY, clamped.toString())
    }

    /** 记一下问过某个系统权限（设置页据此区分“未设置”和“已关闭”） */
    fun markAsked(permission: String) = store.save("asked-$permission", "1")

    fun wasAsked(permission: String): Boolean = store.load("asked-$permission") != null

    // MARK: 常去球馆的名字（只有 id 在资料里；名字和城市单独读一次）

    /** 常去球馆：id → 名字和城市 */
    private val venueNames = mutableStateMapOf<String, VenueName>()

    /** 常去球馆，按收藏的先后；名字还没读到的用读过的球馆 */
    fun favoriteVenues(): List<VenueName> = backend.favoriteVenueIds.mapNotNull { id ->
        venueNames[id] ?: backend.venue(id)?.let { VenueName(it.id, it.name, it.city) }
    }

    suspend fun refreshFavoriteVenues() {
        val ids = backend.favoriteVenueIds.filter { it !in venueNames }
        if (ids.isEmpty()) return
        val rows = remote.select<List<VenueName>>("venues", "id=in.(${ids.joinToString(",")})&select=id,name,city")
        rows.forEach { venueNames[it.id] = it }
    }

    // MARK: 资料

    /** 隐私开关：先改本机，再同步；没同步上恢复并报错 */
    suspend fun updatePrivacy(privacy: PrivacySettings) = backend.updateProfile(
        json(
            "show_on_boards" to privacy.showsOnLeaderboards, "challenge_policy" to privacy.challengePolicy.serverValue,
            "discoverable" to privacy.findableByNickname, "show_as_regular" to privacy.showsAsRegular,
            "allow_message_requests" to privacy.allowsMessageRequests, "email_alerts" to privacy.emailAlerts,
            "show_searching" to privacy.showsWhenSearching,
        ),
    ) { it.copy(privacy = privacy) }

    /** 卡片颜色：点了就存 */
    suspend fun setCardColor(color: CardColor) {
        val user = backend.currentUser ?: return
        if (user.avatar.cardColor == color) return
        backend.updateProfile(json("card_color" to color.rawValue)) { it.copy(avatar = it.avatar.copy(cardColor = color)) }
    }

    /** 定级用的性别（设置页的“等级”） */
    suspend fun updateGender(gender: Gender) {
        val user = backend.currentUser ?: return
        if (gender == user.gender || gender == Gender.Unspecified) return
        backend.updateGender(gender)
    }

    /**
     * 编辑资料的“保存”：昵称、性别、卡片颜色、常打传到服务器；一句话介绍和文字头像只存在本机（和 iPhone 一样）。
     * 对应 iPhone 的 MockBackend.updateProfile
     */
    suspend fun saveProfile(edited: User) {
        val user = backend.currentUser ?: throw RemoteError.NotSignedIn
        if (!Backend.isValidNickname(edited.nickname)) throw BackendError(tr("昵称需为 2-12 个字符"))
        if (advertises(edited.nickname) || advertises(edited.bio)) throw BackendError(tr("昵称和简介里不能留联系方式或链接"))
        val nickname = edited.nickname.trim()
        val gender = if (edited.gender == Gender.Unspecified) user.gender else edited.gender
        // 常打每次都传（“都行”就是空）；其余的有改动才传
        val values = buildList<Pair<String, Any?>> {
            if (nickname != user.nickname || gender != user.gender) {
                add("nickname" to nickname)
                add("gender" to gender.serverJSON)
            }
            if (edited.avatar.cardColor != user.avatar.cardColor) add("card_color" to edited.avatar.cardColor?.rawValue)
            add("preferred_mode" to edited.preferredMode?.serverValue)
        }
        backend.updateProfile(json(*values.toTypedArray())) {
            it.copy(
                nickname = nickname,
                bio = edited.bio.take(60),
                gender = gender,
                preferredMode = edited.preferredMode,
                avatar = it.avatar.copy(symbol = edited.avatar.symbol, paletteIndex = edited.avatar.paletteIndex, cardColor = edited.avatar.cardColor),
            )
        }
    }

    // MARK: 本月胜率、爽约

    /** 本月的胜率（my_record）；服务器只给本月的，上个月拿不到 */
    var winRate by mutableStateOf<Rankings.WinRate?>(null)
        private set

    suspend fun refreshRecord() {
        val record = remote.rpc<RemoteWinRate>("my_record")
        winRate = Rankings.WinRate(record.games, record.wins, record.opponents, record.gap, record.rounds, record.roundWins)
    }

    var strikes by mutableStateOf<StrikeSummary?>(null)
        private set

    suspend fun refreshStrikes() {
        val raw = remote.rpc<RemoteMyStrikes>("my_strikes")
        strikes = StrikeSummary(raw.recent, raw.suspendedUntil?.let(::suspension))
    }

    // MARK: 高水平认证

    /** 我最近的一次申请（撤回的不算） */
    var verification by mutableStateOf<VerificationRequest?>(null)
        private set

    suspend fun refreshVerification() {
        val me = backend.currentUser?.id ?: return
        val latest = remote.rpc<RemoteVerification?>("my_verification")
        verification = latest?.let { item ->
            val kind = VerificationStatus.ofServer(item.kind) ?: return@let null
            val status = VerificationRequest.Status.entries.firstOrNull { it.name.lowercase() == item.status } ?: return@let null
            VerificationRequest(
                item.id, me, kind, item.claimedRating, item.evidence, item.nameOnRecord, item.note, item.createdAt.toEpochMilli(), status,
                item.reviewedAt?.toEpochMilli(), item.reviewNote, item.approvedRating,
            )
        }
    }

    suspend fun submitVerification(kind: VerificationStatus, tier: SkillTier, evidenceURL: String, nameOnRecord: String, note: String) {
        remote.call(
            "request_verification",
            json(
                "p_kind" to kind.serverValue, "p_rating" to tier.rating, "p_evidence" to evidenceURL.trim(),
                "p_name" to nameOnRecord.trim(), "p_note" to note.trim(),
            ),
        )
        refreshVerification()
        if (verification == null) throw RemoteError.Server("bad_response")
    }

    suspend fun withdrawVerification() {
        remote.call("withdraw_verification")
        verification = null
    }

    // MARK: 帮助与反馈

    suspend fun submitFeedback(kind: String, text: String, context: Map<String, String>) {
        remote.call("submit_feedback", json("p_kind" to kind, "p_body" to text, "p_context" to context))
    }

    // MARK: 账号

    suspend fun updatePassword(password: String) = backend.updatePassword(password)

    /**
     * 注销：先把资料里的照片清掉、删掉文件夹里的全部照片（账号删了以后就没权限删了），再删账号，最后清本机。
     * 服务器会取消以后的球局并通知其他人、把球群交给下一位组织者。对应 iPhone 的 remoteDeleteAccount。
     * 安卓还没有 Apple 登录和推送，所以没有撤销 Apple 授权、注销推送登记这两步
     */
    suspend fun deleteAccount() {
        val me = backend.currentUser?.id ?: throw RemoteError.NotSignedIn
        if (backend.avatarPath != null) ignoring { remote.call("set_avatar", json("p_path" to null)) }
        if (backend.cardPhotoPath != null) ignoring { remote.call("set_card_photo", json("p_path" to null)) }
        ignoring { backend.photos.cleanUpFolder(me, keeping = emptyList()) }
        remote.call("delete_account")
        store.save(slotsKey(me), null)
        slotsByUser.remove(me)
        winRate = null
        strikes = null
        verification = null
        backend.signOut()
    }

    private suspend fun ignoring(block: suspend () -> Unit) {
        try {
            block()
        } catch (_: RemoteError) {
        }
    }

    @Serializable
    private class UsualTimesRow(val usualTimes: List<ServerUsualTime>? = null)

    @Serializable
    private class RemoteWinRate(
        val games: Int, val wins: Int, val opponents: Int, val gap: Double, val rounds: Int? = null, val roundWins: Int? = null,
    )

    @Serializable
    private class RemoteMyStrikes(val suspendedUntil: String? = null, val recent: Int)

    @Serializable
    private class RemoteVerification(
        val id: String,
        val kind: String,
        val claimedRating: Double,
        val evidence: String,
        val nameOnRecord: String,
        val note: String,
        val status: String,
        @Serializable(InstantSerializer::class) val createdAt: Instant,
        @Serializable(InstantSerializer::class) val reviewedAt: Instant? = null,
        val reviewNote: String? = null,
        val approvedRating: Double? = null,
    )

    companion object {
        private const val TRAVEL_RADIUS_KEY = "travelRadiusKm"
        private val storeJson = Json { ignoreUnknownKeys = true }
        private val instances = WeakHashMap<Backend, ProfileApi>()

        /** 一个后端一份（“我的”、设置、编辑资料共用） */
        fun of(backend: Backend, context: Context?): ProfileApi = synchronized(instances) {
            instances.getOrPut(backend) {
                ProfileApi(backend, context?.let(ProfileStore::preferences) ?: ProfileStore.memory, MainScope())
            }
        }

        /** 昵称、简介里留了联系方式或链接 */
        fun advertises(text: String): Boolean = ContactInfoDetector.mentionsOffPlatformContact(text) || ContactInfoDetector.containsLink(text)

        /** “infinity” 是永久 */
        fun suspension(value: String): Long? =
            if (value == "infinity") DISTANT_FUTURE else RemoteJSON.parseDate(value)?.toEpochMilli()
    }
}

/** 爽约胶囊上的字：“暂停约球至 …”或“已暂停约球” */
fun StrikeSummary.suspensionText(): String? = suspendedUntil?.let { MyStrikes.suspensionText(it) }
