package com.badie.app.features.venues

import android.content.Context
import androidx.core.content.edit
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.badie.app.backend.Backend
import com.badie.app.backend.confirmVenue
import com.badie.app.backend.fetchVenue
import com.badie.app.backend.regularCounts
import com.badie.app.l10n.L10n.tr
import com.badie.app.location.LocationProvider
import com.badie.app.models.Coordinate
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.DistanceUnit
import com.badie.app.models.UserPreferences
import com.badie.app.models.Venue
import com.badie.app.remote.RemoteError
import com.badie.app.shell.ManagerContext
import kotlinx.coroutines.launch

/** 快速匹配最多选几家球馆（iPhone 的 MatchDraft.maxCourts） */
const val MAX_MATCH_VENUES = 3

/**
 * 位置、附近的球馆、常去球馆、附近范围。对应 iPhone 的 Managers/LocationManager.swift。
 * 在 shell/AppState.kt 的 AppEnvironment 里建好，构造参数不要改。
 *
 * 和 iPhone 不同的地方：
 * - iPhone 一直跟着位置更新（移动 500 米以上就重拉附近的球馆）；这里在打开球馆页、下拉刷新时取一次位置（5 分钟内取过就不再取）。
 * - 球馆目录不打包，附近的球馆都从服务器拉（venues_near）。
 * - 老用户自动补常去球馆不做：服务器已经替老用户补过一家（见 STATUS.md）。
 */
@Stable
class LocationManager internal constructor(
    private val context: ManagerContext,
    private val settings: Settings,
    private val source: LocationSource?,
    private val now: () -> Long,
) {
    constructor(context: ManagerContext) : this(
        context,
        Settings.of(context.android),
        context.android?.let { LocationSource.of(it) },
        System::currentTimeMillis,
    )

    /** 存在本机的小设置（附近范围、问过定位没有、确认过的球馆） */
    interface Settings {
        fun double(key: String): Double?
        fun setDouble(key: String, value: Double)
        fun strings(key: String): Set<String>
        fun setStrings(key: String, value: Set<String>)

        companion object {
            fun of(android: Context?): Settings = android?.let(::Preferences) ?: Memory()
        }

        class Memory : Settings {
            private val values = HashMap<String, Any>()
            override fun double(key: String) = values[key] as? Double
            override fun setDouble(key: String, value: Double) {
                values[key] = value
            }
            @Suppress("UNCHECKED_CAST")
            override fun strings(key: String) = values[key] as? Set<String> ?: emptySet()
            override fun setStrings(key: String, value: Set<String>) {
                values[key] = value
            }
        }

        private class Preferences(android: Context) : Settings {
            private val preferences = android.getSharedPreferences("settings", Context.MODE_PRIVATE)
            override fun double(key: String) = preferences.getString(key, null)?.toDoubleOrNull()
            override fun setDouble(key: String, value: Double) = preferences.edit { putString(key, value.toString()) }
            override fun strings(key: String): Set<String> = preferences.getStringSet(key, null)?.toSet() ?: emptySet()
            override fun setStrings(key: String, value: Set<String>) = preferences.edit { putStringSet(key, value) }
        }
    }

    /** 当前位置从哪来（测试里换成假的） */
    interface LocationSource {
        val isAuthorized: Boolean
        suspend fun current(): Coordinate?

        companion object {
            fun of(android: Context): LocationSource {
                val provider = LocationProvider(android)
                return object : LocationSource {
                    override val isAuthorized get() = provider.isAuthorized
                    override suspend fun current() = provider.current()
                }
            }
        }
    }

    private val backend: Backend get() = context.backend

    /** 给了定位权限 */
    var isAuthorized by mutableStateOf(source?.isAuthorized ?: false)
        private set

    /** 问过定位权限（拒绝过一次以后系统不再弹窗） */
    var hasAskedPermission by mutableStateOf(settings.strings(KEY_ASKED).isNotEmpty())
        private set

    /** 这台设备能定位（单元测试和截图里没有） */
    val canLocate: Boolean get() = source != null

    /** 问过、没给 */
    val isDenied: Boolean get() = hasAskedPermission && !isAuthorized

    var currentLocation by mutableStateOf<Coordinate?>(null)
        private set
    private var locatedAt = 0L

    /** 附近范围内的球馆（服务器的球馆库），按距离排 */
    var nearbyCourts by mutableStateOf<List<Venue>>(emptyList())
        private set

    var preferences by mutableStateOf(
        UserPreferences.default.let { default ->
            settings.double(KEY_RADIUS)?.takeIf(default::isValidTravelRadius)?.let { UserPreferences(it) } ?: default
        },
    )
        private set

    /** 各球馆的常去人数（读过的才有） */
    private val regularCounts = mutableStateMapOf<String, Int>()

    /** 常去球馆和球馆缓存在后端里，不是界面能跟着变的状态：变了就加一 */
    private var version by mutableIntStateOf(0)

    private var lastLoad: Triple<Coordinate, Double, Long>? = null

    // MARK: 读

    /** 算距离用的坐标：有定位用定位，没有用默认城市 */
    val coordinate: Coordinate get() = currentLocation ?: Coordinate.fallbackCenter

    val distanceUnit: DistanceUnit get() = DistanceUnit.current

    /** “10 公里内” / “6 英里内” */
    val radiusText: String get() = tr("%@内", DistanceFormatter.radius(preferences.travelRadiusKm))

    val favoriteCourtIds: List<String>
        get() {
            // 换了账号、改了收藏都会变
            backend.currentUser
            version
            return backend.favoriteVenueIds
        }

    fun court(id: String): Venue? {
        version
        return backend.venue(id)?.let(::withMyConfirmation)
    }

    fun courts(ids: List<String>): List<Venue> = ids.mapNotNull(::court)

    /** 常去球馆，按距离排 */
    val favoriteCourts: List<Venue> get() = courts(favoriteCourtIds).sortedBy { it.distanceKm(coordinate) }

    fun isFavorite(id: String): Boolean = id in favoriteCourtIds

    /** 范围内离我最近的球馆。只在拿到真实定位时给，没定位时不按默认城市猜 */
    val nearestCourtToUser: Venue?
        get() = currentLocation?.let { Venue.nearest(nearbyCourts, it, preferences.travelRadiusKm) }

    /** 这里有多少人常去（读过才有，没读过是 0） */
    fun regularsCount(venueId: String): Int = regularCounts[venueId] ?: 0

    // MARK: 定位

    /** 系统权限弹窗的结果 */
    fun permissionAnswered(granted: Boolean) {
        hasAskedPermission = true
        settings.setStrings(KEY_ASKED, setOf("1"))
        isAuthorized = granted || (source?.isAuthorized ?: false)
        context.scope.launch { safely { start() } }
    }

    /** 打开球馆页时：给了权限就取一次位置，再拉附近的球馆 */
    suspend fun start(forceLocation: Boolean = false, forceCourts: Boolean = false) {
        isAuthorized = source?.isAuthorized ?: false
        val source = source
        if (isAuthorized && source != null && (forceLocation || currentLocation == null || now() - locatedAt > LOCATION_MAX_AGE)) {
            source.current()?.let {
                currentLocation = it
                locatedAt = now()
            }
        }
        refreshCourts(forceCourts)
    }

    /** 下拉刷新：重新取位置、重拉附近的球馆和常去人数 */
    suspend fun refresh() {
        start(forceLocation = true, forceCourts = true)
        version++
    }

    /** 更新附近范围（1–50 公里）并存到本机 */
    fun updateTravelRadius(radiusKm: Double): Boolean {
        if (!preferences.isValidTravelRadius(radiusKm)) return false
        preferences = UserPreferences(radiusKm)
        settings.setDouble(KEY_RADIUS, radiusKm)
        context.scope.launch { safely { refreshCourts() } }
        return true
    }

    /** 从服务器拉范围内的球馆：同一片区域（5 公里内、半径没变大）10 分钟内只拉一次 */
    suspend fun refreshCourts(force: Boolean = false) {
        val center = coordinate
        val radius = preferences.travelRadiusKm
        val last = lastLoad
        if (!force && last != null && last.first.distanceKm(center) < 5 && last.second >= radius && now() - last.third < 600_000) {
            // 范围变小了：从已有的里面筛
            nearbyCourts = nearbyCourts.filter { it.distanceKm(center) <= radius }
            return
        }
        lastLoad = Triple(center, radius, now())
        val found = try {
            backend.venuesNear(center, radius)
        } catch (error: RemoteError) {
            lastLoad = null
            throw error
        }
        nearbyCourts = found.sortedBy { it.distanceKm(center) }
        loadRegularCounts(nearbyCourts.map { it.id } + favoriteCourtIds)
    }

    /** 读这几家的常去人数（失败就先不显示） */
    suspend fun loadRegularCounts(ids: List<String>) {
        if (ids.isEmpty()) return
        try {
            regularCounts.putAll(backend.regularCounts(ids))
        } catch (_: RemoteError) {
        }
    }

    /** 单独读一家的常去人数；失败返回 null */
    suspend fun fetchRegularsCount(venueId: String): Int? = try {
        backend.regularCounts(listOf(venueId))[venueId]?.also { regularCounts[venueId] = it }
    } catch (_: RemoteError) {
        null
    }

    // MARK: 常去球馆

    /** 收藏或取消（马上改本机的，服务器没改成功就提示并恢复） */
    fun toggleFavorite(id: String) {
        val on = !isFavorite(id)
        context.scope.launch {
            try {
                backend.setFavoriteVenue(id, on)
            } catch (error: RemoteError) {
                context.appState.showError(error)
            }
            version++
            fetchRegularsCount(id)
        }
        version++
    }

    // MARK: 球馆缓存

    /** 读一家球馆：缓存里有就用缓存，没有就问服务器 */
    suspend fun loadCourt(id: String): Venue? = court(id) ?: backend.fetchVenue(id)?.also { version++ }?.let(::withMyConfirmation)

    /** 新加的球馆（或服务器返回的同一家）：放进缓存，界面跟着变 */
    fun courtAdded(venue: Venue) {
        backend.cacheVenue(venue)
        version++
    }

    /** 按名字、别名、缩写、地址找：服务器按名字和地址找到的，加上附近的、常去的，再按匹配度和距离排（最多 15 家） */
    suspend fun searchCourts(query: String): List<VenueSearch.Hit> {
        val known = nearbyCourts + favoriteCourts
        val remote = try {
            backend.searchVenues(query)
        } catch (_: RemoteError) {
            emptyList()
        }
        version++
        val hits = VenueSearch.search(remote + known, query, coordinate, limit = 15)
        loadRegularCounts(hits.map { it.venue.id }.filter { it !in regularCounts })
        return hits.map { it.copy(venue = withMyConfirmation(it.venue)) }
    }

    // MARK: 确认地址

    private val confirmedKey: String get() = "$KEY_CONFIRMED.${backend.currentUser?.id.orEmpty()}"

    /** 我确认过这家的地址（服务器不告诉别人确认过谁，记在本机） */
    fun hasConfirmed(id: String): Boolean {
        version
        return id in settings.strings(confirmedKey)
    }

    suspend fun confirmVenue(id: String) {
        val confirmed = backend.confirmVenue(id)
        settings.setStrings(confirmedKey, settings.strings(confirmedKey) + confirmed.id + id)
        nearbyCourts = nearbyCourts.map { if (it.id == confirmed.id) confirmed else it }
        version++
    }

    /** 本机记的“我确认过”加到球馆上（来源说明里的 n/3 位确认），状态以服务器为准 */
    private fun withMyConfirmation(venue: Venue): Venue {
        val me = backend.currentUser?.id ?: return venue
        if (venue.id !in settings.strings(confirmedKey) || me in venue.confirmedBy) return venue
        return venue.addingConfirmation(me, now()).copy(status = venue.status)
    }

    private suspend fun safely(block: suspend () -> Unit) {
        try {
            block()
        } catch (_: RemoteError) {
        }
    }

    companion object {
        const val KEY_RADIUS = "travelRadiusKm"
        private const val KEY_ASKED = "locationAsked"
        private const val KEY_CONFIRMED = "confirmedVenues"
        private const val LOCATION_MAX_AGE = 5 * 60_000L
    }
}
