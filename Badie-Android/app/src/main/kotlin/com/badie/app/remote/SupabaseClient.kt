package com.badie.app.remote

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.serializer
import java.io.IOException

// MARK: - 正式后端（Supabase）

/**
 * 服务器地址和 publishable key。这个 key 本来就是公开的（网页里也有），数据靠数据库的行级权限和函数里的校验保护；
 * secret key 绝不放进 App
 */
object SupabaseConfig {
    const val URL = "https://yeffnjdpjejlplqryjfx.supabase.co"
    const val PUBLISHABLE_KEY = "sb_publishable_oTHxEWYt2Gg8omKs98IHoQ_jNM0Blig"
    /** 网站上的人机验证页（见 web/src/pages/captcha.astro） */
    const val CAPTCHA_PAGE = "https://badie.rsvp/captcha/"
}

class HttpRequest(val url: String, val method: String, val headers: Map<String, String>, val body: ByteArray?, val timeoutMillis: Long = 20_000)

class HttpResponse(val status: Int, val body: ByteArray)

/** 发请求的方式：正式用 OkHttp，测试里换成假服务器。网络不通时抛 IOException */
typealias Transport = suspend (HttpRequest) -> HttpResponse

/** 登录状态存在哪 */
class SessionStorage(val load: () -> RemoteSession?, val save: (RemoteSession?) -> Unit) {
    companion object {
        /** 测试用：不存 */
        val memory get() = SessionStorage({ null }, {})
    }
}

/** 调 Supabase：邮箱验证码、密码、Apple、Google 登录（Auth）+ 数据库函数和表（REST）+ 照片（Storage） */
class SupabaseClient(
    private val storage: SessionStorage,
    private val transport: Transport,
    private val now: () -> Long = System::currentTimeMillis,
) {
    @Volatile
    var session: RemoteSession? = storage.load()
        private set(value) {
            field = value
            storage.save(value)
        }

    /** 登录失效（refresh token 被吊销或过期）时通知外面退回登录页 */
    var onSessionExpired: (() -> Unit)? = null

    private val refreshing = Mutex()

    // MARK: 登录

    /** 发 6 位验证码到邮箱（没注册过的邮箱会自动建账号）；开了人机验证时要带上 Turnstile 令牌 */
    suspend fun sendCode(email: String, captchaToken: String? = null) {
        send("auth/v1/otp", body = withCaptcha(json("email" to email, "create_user" to true), captchaToken), authorized = false)
    }

    /** 输入邮件里的 6 位码：type 是 email（验证码登录）、signup（确认注册的邮箱）或 recovery（重设密码） */
    suspend fun verify(email: String, code: String, type: String = "email"): RemoteSession {
        val data = send("auth/v1/verify", body = json("type" to type, "email" to email, "token" to code), authorized = false)
        return RemoteJSON.session(data, now()).also { session = it }
    }

    /**
     * 邮箱 + 密码注册：服务器把 6 位确认码发到邮箱，确认后才能登录（返回 null）。
     * 邮箱已注册时，服务器要么报 user_already_exists，要么（防止探测邮箱）返回没有登录方式的账号，两种都当作已注册
     */
    suspend fun signUp(email: String, password: String, captchaToken: String? = null): RemoteSession? {
        val data = send("auth/v1/signup", body = withCaptcha(json("email" to email, "password" to password), captchaToken), authorized = false)
        try {
            return RemoteJSON.session(data, now()).also { session = it }
        } catch (_: RemoteError.Server) {
            // 还要输确认码：回来的是账号，不是登录状态
        }
        val identities = try {
            RemoteJSON.decode<Account>(data).identities
        } catch (_: RemoteError.Server) {
            null
        }
        if (identities?.isEmpty() == true) throw RemoteError.Server("user_already_exists")
        return null
    }

    @Serializable
    private class Account(val identities: List<JsonObject>? = null)

    suspend fun signIn(email: String, password: String, captchaToken: String? = null): RemoteSession {
        val data = send(
            "auth/v1/token?grant_type=password",
            body = withCaptcha(json("email" to email, "password" to password), captchaToken), authorized = false,
        )
        return RemoteJSON.session(data, now()).also { session = it }
    }

    /** 忘记密码：发 6 位重设码（邮箱没注册也一样返回成功，不让人探测） */
    suspend fun sendPasswordReset(email: String, captchaToken: String? = null) {
        send("auth/v1/recover", body = withCaptcha(json("email" to email), captchaToken), authorized = false)
    }

    /** 注册确认码没收到：重发 */
    suspend fun resendSignupCode(email: String, captchaToken: String? = null) {
        send("auth/v1/resend", body = withCaptcha(json("type" to "signup", "email" to email), captchaToken), authorized = false)
    }

    /** 设置或修改密码（已登录） */
    suspend fun updatePassword(password: String) {
        send("auth/v1/user", method = "PUT", body = json("password" to password))
    }

    /** 开了人机验证时，登录服务的请求都要带上 Turnstile 令牌 */
    private fun withCaptcha(body: JsonObject, captchaToken: String?): JsonObject {
        if (captchaToken.isNullOrEmpty()) return body
        return JsonObject(body + ("gotrue_meta_security" to json("captcha_token" to captchaToken)))
    }

    /** Apple / Google：把对方给的身份令牌和原始 nonce 交给 Supabase 换登录状态 */
    suspend fun signInWithIdToken(provider: String, idToken: String, nonce: String?): RemoteSession {
        val data = send(
            "auth/v1/token?grant_type=id_token",
            body = JsonObject(json("provider" to provider, "id_token" to idToken) + (if (nonce == null) emptyMap() else json("nonce" to nonce))),
            authorized = false,
        )
        return RemoteJSON.session(data, now()).also { session = it }
    }

    /** 浏览器里的第三方登录（[BrowserSignIn]）跳回来以后：用一次性的 code 和 PKCE 的原文换登录状态 */
    suspend fun exchangeCode(authCode: String, codeVerifier: String): RemoteSession {
        val data = send(
            "auth/v1/token?grant_type=pkce",
            body = json("auth_code" to authCode, "code_verifier" to codeVerifier),
            authorized = false,
        )
        return RemoteJSON.session(data, now()).also { session = it }
    }

    /** 后台开了哪些登录方式（公开接口）；网络不通时为 null，不当成“都没开” */
    suspend fun enabledProviders(): Set<String>? = try {
        val settings = RemoteJSON.decode<AuthSettings>(send("auth/v1/settings", method = "GET", authorized = false))
        settings.external.filterValues { it }.keys
    } catch (_: RemoteError) {
        null
    }

    @Serializable
    private class AuthSettings(val external: Map<String, Boolean>)

    /** 这个账号用过哪些方式登录（email / apple / google） */
    suspend fun signInMethods(): List<String> =
        RemoteJSON.decode<AuthUser>(send("auth/v1/user", method = "GET")).appMetadata.providers.orEmpty()

    @Serializable
    private class AuthUser(val appMetadata: Meta) {
        @Serializable
        class Meta(val providers: List<String>? = null)
    }

    /** 调服务器函数：POST /functions/v1/<name> */
    suspend fun invoke(function: String, body: JsonObject) {
        send("functions/v1/$function", body = body)
    }

    suspend fun signOut() {
        if (session != null) {
            try {
                send("auth/v1/logout", body = json())
            } catch (_: RemoteError) {
                // 服务器那边退不掉也照样清掉本机的登录状态
            }
        }
        session = null
    }

    // MARK: 数据

    /** 调数据库函数：POST /rest/v1/rpc/<name> */
    suspend inline fun <reified T> rpc(name: String, args: JsonObject = json()): T = rpc(name, args, serializer<T>())

    suspend fun <T> rpc(name: String, args: JsonObject, serializer: KSerializer<T>): T =
        RemoteJSON.decode(serializer, send("rest/v1/rpc/$name", body = args))

    /** 调没有返回值的数据库函数 */
    suspend fun call(name: String, args: JsonObject = json()) {
        send("rest/v1/rpc/$name", body = args)
    }

    /** 读表：GET /rest/v1/<table>?<query>（只能读到行级权限允许的行） */
    suspend inline fun <reified T> select(table: String, query: String): T = select(table, query, serializer<T>())

    suspend fun <T> select(table: String, query: String, serializer: KSerializer<T>): T =
        RemoteJSON.decode(serializer, send("rest/v1/$table?$query", method = "GET"))

    suspend fun insert(table: String, row: JsonObject) {
        send("rest/v1/$table", body = row)
    }

    suspend fun update(table: String, query: String, values: JsonObject) {
        send("rest/v1/$table?$query", method = "PATCH", body = values)
    }

    suspend fun delete(table: String, query: String) {
        send("rest/v1/$table?$query", method = "DELETE")
    }

    // MARK: 文件（头像照片）

    /** 上传到存储桶：POST /storage/v1/object/<bucket>/<path> */
    suspend fun upload(bucket: String, path: String, data: ByteArray, contentType: String) {
        send("storage/v1/object/$bucket/$path", rawBody = data, contentType = contentType)
    }

    suspend fun removeFile(bucket: String, path: String) {
        send("storage/v1/object/$bucket/$path", method = "DELETE")
    }

    /** 文件夹里的文件名（不含文件夹），最多 100 个 */
    suspend fun listFiles(bucket: String, folder: String): List<String> {
        val data = send("storage/v1/object/list/$bucket", body = json("prefix" to folder, "limit" to 100))
        return RemoteJSON.decode(ListSerializer(StoredFile.serializer()), data).map { it.name }
    }

    @Serializable
    private class StoredFile(val name: String)

    /** 下载公开桶里的文件（不需要登录） */
    suspend fun download(bucket: String, path: String): ByteArray =
        send("storage/v1/object/public/$bucket/$path", method = "GET", authorized = false)

    // MARK: 请求

    private suspend fun send(
        path: String,
        method: String = "POST",
        body: JsonObject? = null,
        rawBody: ByteArray? = null,
        contentType: String? = null,
        authorized: Boolean = true,
    ): ByteArray {
        val headers = mutableMapOf("apikey" to SupabaseConfig.PUBLISHABLE_KEY, "Accept" to "application/json")
        if (authorized) headers["Authorization"] = "Bearer ${validSession().accessToken}"
        val payload = when {
            body != null -> {
                headers["Content-Type"] = "application/json"
                body.toString().encodeToByteArray()
            }
            rawBody != null -> {
                contentType?.let { headers["Content-Type"] = it }
                rawBody
            }
            else -> null
        }
        val response = try {
            transport(HttpRequest("${SupabaseConfig.URL}/$path", method, headers, payload))
        } catch (_: IOException) {
            throw RemoteError.Network
        }
        if (response.status !in 200..299) throw RemoteError.Server(RemoteJSON.errorCode(response.body, response.status))
        return response.body
    }

    /** 访问令牌快过期时先换新的（同时只换一次）；refresh token 失效就算退出登录 */
    private suspend fun validSession(): RemoteSession {
        val current = session ?: throw RemoteError.NotSignedIn
        if (current.expiresAt > now() + 60_000) return current
        return refreshing.withLock {
            // 等的时候别的请求可能已经换好了
            val latest = session ?: throw RemoteError.NotSignedIn
            if (latest.expiresAt > now() + 60_000) return@withLock latest
            try {
                val data = send("auth/v1/token?grant_type=refresh_token", body = json("refresh_token" to latest.refreshToken), authorized = false)
                RemoteJSON.session(data, now()).also { session = it }
            } catch (_: RemoteError.Server) {
                session = null
                onSessionExpired?.invoke()
                throw RemoteError.NotSignedIn
            }
        }
    }
}
