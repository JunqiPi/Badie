package com.badie.app.e2e

import androidx.test.platform.app.InstrumentationRegistry
import com.badie.app.remote.json
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * 端到端测试里的“另一个人”和准备数据：直接调电脑上的本机 Supabase（模拟器里是 10.0.2.2）。
 * 地址和本机的 key 由 e2e/run.sh 用 `am instrument -e` 传进来；secret key 只用来建测试账号和查表（本机的、临时的）
 */
object Harness {
    private val args = InstrumentationRegistry.getArguments()
    val url: String = args.getString("supabaseUrl") ?: "http://10.0.2.2:54321"
    private val publishableKey: String = args.getString("publishableKey").orEmpty()
    private val serviceKey: String = args.getString("serviceKey").orEmpty()
    private val mailpit: String = args.getString("mailpitUrl") ?: "http://10.0.2.2:54324"

    /** 这一轮的编号：邮箱里带上，几轮之间、几个测试之间互不影响；电脑那边的脚本也用它找人 */
    val run: String = args.getString("run") ?: UUID.randomUUID().toString().take(8)

    /** 推送配好了（GitHub Secrets 里有 FCM_SERVICE_ACCOUNT），推送的测试才跑 */
    val pushEnabled: Boolean = args.getString("push") == "1"

    const val PASSWORD = "shuttle rally court nine"

    /** 种子数据里的球馆（洛杉矶），新建的测试账号都把它当常去球馆 */
    const val VENUE_ID = "v-us-ca-21-badminton-club-21bc"

    private val client = OkHttpClient.Builder().callTimeout(30, TimeUnit.SECONDS).build()
    private val jsonType = "application/json".toMediaType()

    class Player(val id: String, val email: String, val name: String, val token: String)

    fun email(tag: String) = "$tag-$run@test.local"

    // MARK: 请求

    private fun send(method: String, path: String, token: String?, body: JsonElement? = null, service: Boolean = false, prefer: String? = null): JsonElement {
        val request = Request.Builder().url("$url/$path")
            .header("apikey", if (service) serviceKey else publishableKey)
            .apply {
                val bearer = if (service) serviceKey else token
                if (bearer != null) header("Authorization", "Bearer $bearer")
                if (prefer != null) header("Prefer", prefer)
            }
            .method(method, body?.toString()?.toRequestBody(jsonType) ?: if (method == "GET" || method == "DELETE") null else "".toRequestBody(jsonType))
            .build()
        client.newCall(request).execute().use { response ->
            val text = response.body.string()
            check(response.isSuccessful) { "$method $path → ${response.code}: ${text.take(500)}" }
            return if (text.isBlank()) JsonNull else Json.parseToJsonElement(text)
        }
    }

    fun rpc(player: Player, name: String, body: JsonObject = JsonObject(emptyMap())): JsonElement = send("POST", "rest/v1/rpc/$name", player.token, body)

    /** 用 secret key 查表（不受行级权限限制） */
    fun serviceSelect(table: String, query: String): JsonArray = send("GET", "rest/v1/$table?$query", null, service = true).jsonArray

    fun serviceRpc(name: String, body: JsonObject = JsonObject(emptyMap())): JsonElement = send("POST", "rest/v1/rpc/$name", null, body, service = true)

    /** 用 secret key 直接写表（比如造一场球局），返回写进去的行 */
    fun serviceInsert(table: String, body: JsonElement): JsonArray =
        send("POST", "rest/v1/$table", null, body, service = true, prefer = "return=representation").jsonArray

    /**
     * 两人（或多人）在 [VENUE_ID] 的一场单打，[startsInHours] 小时后开始（负数是已经开始过）。
     * 第一个人在 1 队，其余在 2 队
     */
    fun createGame(players: List<Player>, startsInHours: Long = 48): String {
        val start = java.time.Instant.now().plusSeconds(startsInHours * 3600)
        val game = serviceInsert(
            "games",
            json("mode" to "singles", "starts_at" to start.toString(), "ends_at" to start.plusSeconds(2 * 3600).toString(), "venue_id" to VENUE_ID),
        )[0].jsonObject["id"]!!.jsonPrimitive.content
        serviceInsert(
            "game_players",
            JsonArray(players.mapIndexed { index, p -> json("game_id" to game, "user_id" to p.id, "team" to if (index == 0) 1 else 2, "rating" to 3) }),
        )
        return game
    }

    fun insert(player: Player, table: String, body: JsonObject) {
        send("POST", "rest/v1/$table", player.token, body, prefer = "return=minimal")
    }

    // MARK: 账号

    /** 建一个已确认邮箱、有资料、常去球馆是 [VENUE_ID] 的账号（App 第一次登录时建资料的那几步，见 Backend.register） */
    fun createPlayer(tag: String, name: String, gender: String = "male"): Player {
        val email = email(tag)
        val user = send("POST", "auth/v1/admin/users", null, json("email" to email, "password" to PASSWORD, "email_confirm" to true), service = true)
        val id = user.jsonObject["id"]!!.jsonPrimitive.content
        val player = Player(id, email, name, signIn(email))
        insert(player, "profiles", json("id" to id, "nickname" to name, "country_code" to "US", "gender" to gender))
        insert(player, "favorite_venues", json("user_id" to id, "venue_id" to VENUE_ID))
        return player
    }

    /** 只建登录用的账号（没有资料）：App 里登录后会走填资料那几步 */
    fun signIn(email: String, password: String = PASSWORD): String =
        send("POST", "auth/v1/token?grant_type=password", null, json("email" to email, "password" to password))
            .jsonObject["access_token"]!!.jsonPrimitive.content

    fun userId(email: String): String? =
        send("GET", "auth/v1/admin/users?per_page=200", null, service = true).jsonObject["users"]!!.jsonArray
            .map { it.jsonObject }.firstOrNull { it["email"]?.jsonPrimitive?.contentOrNull == email }?.get("id")?.jsonPrimitive?.content

    /** 两人成为球友：B 申请，A 通过 */
    fun befriend(a: Player, b: Player) {
        rpc(b, "send_friend_request", json("p_user" to a.id))
        rpc(a, "respond_friend_request", json("p_user" to b.id, "p_accept" to true))
    }

    fun sendDm(from: Player, to: Player, text: String) {
        rpc(from, "send_message", json("p_kind" to "dm", "p_id" to to.id, "p_body" to text))
    }

    /** 会话里的消息（按时间），只要正文 */
    fun messages(player: Player, kind: String, id: String): List<String> {
        val thread = rpc(player, "open_thread", json("p_kind" to kind, "p_id" to id)).jsonObject
        return thread["messages"]?.jsonArray.orEmpty().mapNotNull { (it as? JsonObject)?.get("body")?.jsonPrimitive?.contentOrNull }
    }

    fun pushDevices(userId: String): List<JsonObject> = serviceSelect("push_devices", "user_id=eq.$userId&select=kind,token").map { it.jsonObject }

    // MARK: 邮件

    /** 发到这个邮箱的最新一封邮件里的 6 位码（本机 Supabase 的收件箱 Mailpit） */
    fun emailedCode(email: String, timeoutMillis: Long = 30_000): String {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            val list = getJson("$mailpit/api/v1/messages").jsonObject["messages"]?.jsonArray.orEmpty().map { it.jsonObject }
            val message = list.firstOrNull { m ->
                m["To"]?.jsonArray.orEmpty().any { (it as? JsonObject)?.get("Address")?.jsonPrimitive?.contentOrNull == email }
            }
            if (message != null) {
                val full = getJson("$mailpit/api/v1/message/${message["ID"]!!.jsonPrimitive.content}").jsonObject
                val text = full["Text"]?.jsonPrimitive?.contentOrNull.orEmpty().ifEmpty { full["HTML"]?.jsonPrimitive?.contentOrNull.orEmpty() }
                Regex("""\b\d{6}\b""").find(text)?.let { return it.value }
            }
            Thread.sleep(500)
        }
        error("没收到发给 $email 的验证码邮件")
    }

    private fun getJson(address: String): JsonElement =
        client.newCall(Request.Builder().url(address).build()).execute().use { Json.parseToJsonElement(it.body.string()) }

    /** 等到条件成立（服务器那边的状态），超时报错 */
    fun eventually(what: String, timeoutMillis: Long = 30_000, check: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            if (runCatching(check).getOrDefault(false)) return
            Thread.sleep(1000)
        }
        error("等了 ${timeoutMillis / 1000} 秒还没有：$what")
    }

    val JsonElement?.text: String? get() = (this as? JsonPrimitive)?.contentOrNull
}
