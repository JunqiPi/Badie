package com.badie.app.features.social

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.Backend
import com.badie.app.backend.CacheStore
import com.badie.app.backend.PhotoStore
import com.badie.app.remote.FakeServer
import com.badie.app.remote.SessionStorage
import com.badie.app.remote.SupabaseClient
import com.badie.app.shell.AppEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.serialization.json.jsonPrimitive

/** 球友、私信、球群的测试：登录好的后端（连假服务器），照片不下载 */
object SocialTestSupport {
    const val ME = TestSupport.USER_ID
    const val BLAKE = "6f1c2c3e-0000-4000-8000-000000000002"
    const val CASEY = "6f1c2c3e-0000-4000-8000-000000000003"

    /** [scope] 用 runTest 的 backgroundScope：后台的工作要 runCurrent() 才跑，照片的延时永远不到 */
    suspend fun environment(server: FakeServer, scope: CoroutineScope): AppEnvironment {
        val remote = SupabaseClient(SessionStorage({ TestSupport.session() }, {}), server.transport, now = { TestSupport.CLOCK })
        val backend = Backend(
            remote, CacheStore.memory, now = { TestSupport.CLOCK }, deviceCountry = { "US" }, serverLocale = { "zh-Hans" },
            photos = PhotoStore(remote, scope, cacheDir = null),
        )
        server.serveProfile("[${TestSupport.profile()}]")
        backend.refreshProfile()
        server.requests.clear()
        return AppEnvironment(scope, backend)
    }

    fun FakeServer.text(index: Int, key: String): String? = json(index)[key]?.jsonPrimitive?.content

    /** 发到这个函数的第 nth 个请求的序号 */
    fun FakeServer.call(name: String, nth: Int = 0): Int = requests.indices.filter { path(it) == "/rest/v1/rpc/$name" }[nth]
}
