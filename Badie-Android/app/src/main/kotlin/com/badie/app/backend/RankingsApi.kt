package com.badie.app.backend

import com.badie.app.models.Gender
import com.badie.app.models.Venue
import com.badie.app.remote.EpochMillisSerializer
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.Serializable
import java.net.URLEncoder
import java.time.Instant

/**
 * 排行榜、我的战绩、挑战要调的数据库函数（只管请求和解码，缓存在 features/rankings/RankingManager）。
 * 对应 iPhone 的 MockBackend+RemoteRankings.swift 里的 Remote* 类型和几个 rpc 调用
 */
class RankingsApi(private val remote: SupabaseClient) {

    // MARK: 返回的数据

    /** my_record：我本月的胜率 */
    @Serializable
    data class WinRate(
        val games: Int = 0,
        val wins: Int = 0,
        val opponents: Int = 0,
        val gap: Double = 0.0,
        val rounds: Int? = null,
        val roundWins: Int? = null,
    )

    @Serializable
    data class BoardEntry(
        val id: String,
        val nickname: String,
        val rating: Double,
        val rank: Int,
        /** 周榜积分；场馆榜没有 */
        val points: Int? = null,
        val games: Int,
        val wins: Int,
    )

    @Serializable
    data class WeeklyBoard(
        val entries: List<BoardEntry> = emptyList(),
        val me: Mine? = null,
        val progress: Progress? = null,
        val eligible: Boolean = true,
    ) {
        @Serializable
        data class Mine(val rank: Int, val points: Int)

        @Serializable
        data class Progress(val games: Int, val opponents: Int, val points: Int)
    }

    @Serializable
    data class VenueBoard(val bands: List<Band> = emptyList()) {
        @Serializable
        data class Band(val band: Int, val entries: List<BoardEntry> = emptyList())
    }

    @Serializable
    data class Player(val id: String, val nickname: String, val rating: Double? = null)

    @Serializable
    data class Challenges(val incoming: List<Item> = emptyList(), val outgoing: List<Item> = emptyList()) {
        @Serializable
        data class Venue(val name: String, val tz: String? = null)

        @Serializable
        data class Item(
            val id: String,
            @Serializable(EpochMillisSerializer::class) val startsAt: Long,
            @Serializable(EpochMillisSerializer::class) val endsAt: Long,
            val message: String? = null,
            @Serializable(EpochMillisSerializer::class) val expiresAt: Long? = null,
            val status: String? = null,
            val gameId: String? = null,
            val venue: Venue,
            val player: Player,
            /** 双打：发起人带的搭档 */
            val partner: Player? = null,
        )
    }

    @Serializable
    data class Friends(val friends: List<Player> = emptyList())

    @Serializable
    private class CountryRow(val countryCode: String? = null)

    // MARK: 榜单

    /** scope：global / country；offset：0 = 本周，1 = 上周 */
    suspend fun weeklyBoard(scope: String, offset: Int, gender: Gender): WeeklyBoard =
        remote.rpc("weekly_board", json("p_scope" to scope, "p_offset" to offset, "p_gender" to gender.rawValue))

    /** offset：0 = 本月，1 = 上月 */
    suspend fun venueBoard(venueId: String, offset: Int, gender: Gender): VenueBoard =
        remote.rpc("venue_board", json("p_venue" to venueId, "p_offset" to offset, "p_gender" to gender.rawValue))

    suspend fun myRecord(): WinRate = remote.rpc("my_record")

    // MARK: 挑战

    /** 和我有关的挑战：收到的（待回复）和发出的（14 天内） */
    suspend fun myChallenges(): Challenges = remote.rpc("my_challenges")

    /** 发起挑战，返回挑战的 ID */
    suspend fun sendChallenge(targetId: String, venueId: String, startTime: Long, endTime: Long, message: String, partnerId: String?): String =
        remote.rpc(
            "send_challenge",
            json(
                "p_target" to targetId,
                "p_venue" to venueId,
                "p_starts_at" to Instant.ofEpochMilli(startTime).toString(),
                "p_ends_at" to Instant.ofEpochMilli(endTime).toString(),
                "p_message" to message.trim(),
                "p_partner" to partnerId,
            ),
        )

    /** 接受或婉拒；接受时返回生成的球局 ID */
    suspend fun respondChallenge(id: String, accept: Boolean, partnerId: String?): String? =
        remote.rpc("respond_challenge", json("p_challenge" to id, "p_accept" to accept, "p_partner" to partnerId))

    suspend fun withdrawChallenge(id: String) = remote.call("withdraw_challenge", json("p_challenge" to id))

    // MARK: 顺带要用的

    /** 举报榜单上的人（刷榜 = other，广告 = scam），说明写“来自排行榜” */
    suspend fun report(userId: String, reason: String, details: String) =
        remote.call("report_user", json("p_user" to userId, "p_reason" to reason, "p_details" to details.take(500)))

    /** 我的球友（挑战带搭档时从里面选） */
    suspend fun friends(): List<Player> = remote.rpc<Friends>("my_friends").friends

    /** 被挑战的人的昵称（只拿名字，资料卡的其余部分归球友资料页） */
    suspend fun player(id: String): Player? = remote.rpc("player_card", json("p_user" to id))

    /** 我资料里的国家/地区：服务器的“本国榜”按它算 */
    suspend fun myCountry(userId: String): String? =
        remote.select<List<CountryRow>>("profiles", "id=eq.$userId&select=country_code").firstOrNull()?.countryCode

    /** 按 ID 读球馆（常去球馆、榜单页带进来的球馆） */
    suspend fun venues(ids: List<String>): List<Venue> {
        if (ids.isEmpty()) return emptyList()
        val list = URLEncoder.encode(ids.joinToString(",", "(", ")") { "\"$it\"" }, "UTF-8")
        return remote.select("venues", "select=$COLUMNS&id=in.$list")
    }

    companion object {
        private const val COLUMNS = "id,name,aliases,lat,lon,street,unit,city,region,postal_code,country_code,status,location_approximate," +
            "time_zone_id,apple_place_id,court_count,pricing,pricing_note,currency_code,phone,website,entrance_note,source,created_at,play_times"
    }
}
