package com.badie.app

import com.badie.app.backend.Backend
import com.badie.app.backend.CacheStore
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteSession
import com.badie.app.remote.SessionStorage
import com.badie.app.remote.SupabaseClient

/** 测试用的后端：连假服务器，不存盘，时间固定 */
object TestSupport {
    const val CLOCK = 1_800_000_000_000L
    const val USER_ID = "6f1c2c3e-0000-4000-8000-000000000001"

    fun backend(server: FakeServer = FakeServer(), session: RemoteSession? = null, pushToken: String? = null): Backend = Backend(
        SupabaseClient(SessionStorage({ session }, {}), server.transport, now = { CLOCK }),
        CacheStore.memory, now = { CLOCK }, deviceCountry = { "US" }, serverLocale = { "zh-Hans" }, pushToken = { pushToken },
    )

    fun session() = RemoteSession("old", "r-old", CLOCK + 3_600_000, USER_ID, "alex@example.com")

    fun token(access: String) =
        """{"access_token":"$access","refresh_token":"r-$access","expires_in":3600,"token_type":"bearer","user":{"id":"$USER_ID","email":"alex@example.com"}}"""

    fun profile(extra: String = "") =
        """{"id":"$USER_ID","nickname":"Alex","country_code":"US","rating":4.0,"assessed_at":"2026-10-17T23:17:25+00:00","show_on_boards":true,"challenge_policy":"everyone","locale":"zh-Hans","gender":"male"$extra}"""

    /** 读资料要两个请求：资料和收藏的球馆 */
    fun FakeServer.serveProfile(rows: String) {
        on("GET /rest/v1/profiles", rows)
        on("GET /rest/v1/favorite_venues", "[]")
    }
}
