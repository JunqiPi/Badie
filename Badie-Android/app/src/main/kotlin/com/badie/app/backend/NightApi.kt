package com.badie.app.backend

import com.badie.app.models.GroupTonight
import com.badie.app.models.MatchFormat
import com.badie.app.models.MatchPlay
import com.badie.app.models.MatchPreview
import com.badie.app.models.MatchState
import com.badie.app.models.MyMatch
import com.badie.app.models.NightState
import com.badie.app.models.TonightItem
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.builtins.nullable

// 正式后端：球群当晚的排场和比赛。对应 iPhone 的 MockBackend+RemoteNight.swift（参数和字段照抄；收款那几个在 PaymentsApi）。
// 都是直接调数据库函数，结果不进本地缓存：界面自己拿着最新一份，每 10 秒重拉。
// （backend/MatchApi.kt 是快速匹配的，和这里的“比赛”没关系）
class NightApi(private val remote: SupabaseClient) {

    // MARK: 球群页、球局页

    /** 球群页的当天场次：排场、看排场、付钱、收款 */
    suspend fun groupTonight(groupId: String): List<GroupTonight> = remote.rpc("group_tonight", json("p_group" to groupId))

    /** 球局页最上面的“今晚” */
    suspend fun myTonight(): List<TonightItem> = remote.rpc("my_tonight")

    // MARK: 当晚

    /** 没权限时为 null */
    suspend fun nightState(sessionId: String): NightState? =
        remote.rpc("night_state", json("p_session" to sessionId), NightState.serializer().nullable)

    suspend fun nightSettings(sessionId: String, courts: Int, doubles: Boolean, balance: Boolean) =
        remote.call("night_settings", json("p_session" to sessionId, "p_courts" to courts, "p_doubles" to doubles, "p_balance" to balance))

    suspend fun nightStart(sessionId: String) = remote.call("night_start", json("p_session" to sessionId))

    /** 比赛打完，回到排场 */
    suspend fun nightResume(sessionId: String) = remote.call("night_resume", json("p_session" to sessionId))

    /** 点名：signups 为 null 是“全到了”；status 为 null 是“没到” */
    suspend fun nightMark(sessionId: String, signups: List<String>?, status: String?) =
        remote.call("night_mark", json("p_session" to sessionId, "p_signups" to signups, "p_status" to status))

    /** 现场加人（访客），返回报名 id */
    suspend fun nightAdd(sessionId: String, name: String): String =
        remote.rpc("night_add", json("p_session" to sessionId, "p_name" to name.trim()))

    suspend fun nightFinish(game: Int) = remote.call("night_finish", json("p_game" to game))

    suspend fun nightSwap(game: Int, out: String, replacement: String) =
        remote.call("night_swap", json("p_game" to game, "p_out" to out, "p_in" to replacement))

    /** next：放到下一场；false 是跳过（排到等候的最后） */
    suspend fun nightBump(signupId: String, next: Boolean) = remote.call("night_bump", json("p_signup" to signupId, "p_next" to next))

    suspend fun nightUndo(sessionId: String) = remote.call("night_undo", json("p_session" to sessionId))

    suspend fun nightHelpers(sessionId: String, users: List<String>) =
        remote.call("night_helpers", json("p_session" to sessionId, "p_users" to users))

    // MARK: 比赛

    suspend fun matchPreview(
        format: MatchFormat, play: MatchPlay, players: Int, courts: Int, points: Int, bestOf: Int,
        pools: Int?, advance: Int?, rounds: Int?, thirdPlace: Boolean,
    ): MatchPreview {
        val args = mutableListOf<Pair<String, Any?>>(
            "p_format" to format.raw, "p_play" to play.raw, "p_players" to players, "p_courts" to courts,
            "p_points" to points, "p_best_of" to bestOf, "p_third_place" to thirdPlace,
        )
        pools?.let { args += "p_pools" to it }
        advance?.let { args += "p_advance" to it }
        rounds?.let { args += "p_rounds" to it }
        return remote.rpc("match_preview", json(*args.toTypedArray()))
    }

    /** players：[{user_id} | {signup_id} | {name}]，按顺序是种子。返回比赛 id */
    suspend fun createMatch(
        name: String, venueId: String?, courts: Int, format: MatchFormat, play: MatchPlay, points: Int, bestOf: Int,
        winByTwo: Boolean, players: List<Map<String, String>>, rounds: Int?, pools: Int?, advance: Int?, thirdPlace: Boolean,
        sessionId: String?,
    ): String {
        val args = mutableListOf<Pair<String, Any?>>(
            "p_name" to name.trim(), "p_venue" to venueId, "p_courts" to courts, "p_format" to format.raw, "p_play" to play.raw,
            "p_points" to points, "p_best_of" to bestOf, "p_win_by_two" to winByTwo, "p_players" to players, "p_third_place" to thirdPlace,
        )
        rounds?.let { args += "p_rounds" to it }
        pools?.let { args += "p_pools" to it }
        advance?.let { args += "p_advance" to it }
        sessionId?.let { args += "p_session" to it }
        return remote.rpc("create_match", json(*args.toTypedArray()))
    }

    /** 没权限或已删掉时为 null */
    suspend fun matchState(matchId: String): MatchState? =
        remote.rpc("match_state", json("p_match" to matchId), MatchState.serializer().nullable)

    /** 只收合规的完整比分（不合规报 score_invalid） */
    suspend fun matchScore(game: Int, scores: List<Int>, version: Int) =
        remote.call("match_score", json("p_game" to game, "p_scores" to scores, "p_version" to version))

    /** 中途退赛：side 是退赛的一边（1 / 2），scores 是退赛前打完的局加上没打完那局 */
    suspend fun matchRetire(game: Int, side: Int, scores: List<Int>, version: Int) =
        remote.call("match_retire", json("p_game" to game, "p_side" to side, "p_scores" to scores, "p_version" to version))

    suspend fun matchFlag(game: Int) = remote.call("match_flag", json("p_game" to game))

    suspend fun matchUndo(matchId: String) = remote.call("match_undo", json("p_match" to matchId))

    /** 退赛：给了 game 就这一场算对方赢；没打的场次取消 */
    suspend fun matchWithdraw(player: String, game: Int?) =
        remote.call("match_withdraw", if (game == null) json("p_player" to player) else json("p_player" to player, "p_game" to game))

    /** 只有双打轮换搭档能中途加人（访客，输名字） */
    suspend fun matchAddPlayer(matchId: String, name: String) {
        remote.rpc<String>("match_add_player", json("p_match" to matchId, "p_name" to name.trim()))
    }

    suspend fun matchCourts(matchId: String, courts: Int) = remote.call("match_courts", json("p_match" to matchId, "p_courts" to courts))

    suspend fun matchHelpers(matchId: String, users: List<String>) = remote.call("match_helpers", json("p_match" to matchId, "p_users" to users))

    /** 出线卡在并列上时，组织者选谁出线（key 按种子顺序） */
    suspend fun matchQualify(matchId: String, keys: List<String>) = remote.call("match_qualify", json("p_match" to matchId, "p_keys" to keys))

    suspend fun matchEnd(matchId: String) = remote.call("match_end", json("p_match" to matchId))

    suspend fun matchDelete(matchId: String) = remote.call("match_delete", json("p_match" to matchId))

    suspend fun myMatches(): List<MyMatch> = remote.rpc("my_matches")
}
