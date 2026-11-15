package com.badie.app.remote

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.time.Instant

/** 正式后端客户端：请求格式、登录状态、换令牌、错误码（用假服务器，不联网）。对应 iPhone 的 SupabaseClientTests */
class SupabaseClientTest {
    private val server = FakeServer()
    private val userId = "6f1c2c3e-0000-4000-8000-000000000001"
    private var clock = 1_800_000_000_000L
    private val saved = mutableListOf<RemoteSession?>()

    private fun client(session: RemoteSession? = null) =
        SupabaseClient(SessionStorage({ session }, { saved += it }), server.transport, now = { clock })

    private fun token(access: String, expiresIn: Int = 3600) =
        """{"access_token":"$access","refresh_token":"r-$access","expires_in":$expiresIn,"token_type":"bearer","user":{"id":"$userId","email":"alex@example.com"}}"""

    private fun session(expiresInSeconds: Long) = RemoteSession("old", "r-old", clock + expiresInSeconds * 1000, userId, "alex@example.com")

    private fun text(index: Int, key: String) = server.json(index)[key]?.jsonPrimitive?.content

    @Test
    fun parsesPostgresTimestamps() {
        val expected = RemoteJSON.parseDate("2026-10-18T02:00:00Z")
        assertNotNull(expected)
        assertEquals(expected, RemoteJSON.parseDate("2026-10-18T02:00:00+00:00"))
        assertEquals(expected, RemoteJSON.parseDate("2026-10-18T02:00:00+00"))
        assertEquals(expected, RemoteJSON.parseDate("2026-10-17T19:00:00-07:00"))
        val fractional = RemoteJSON.parseDate("2026-10-18T02:00:00.123456+00:00")!!
        assertEquals(123, fractional.toEpochMilli() - expected!!.toEpochMilli())
        assertNull(RemoteJSON.parseDate("tomorrow"))
    }

    @Serializable
    private data class Row(val id: String, val displayName: String, @Serializable(InstantSerializer::class) val createdAt: Instant, val note: String?)

    @Test
    fun decodesSnakeCaseAndMissingFields() {
        val row = RemoteJSON.decode<Row>("""{"id":"1","display_name":"Alex","created_at":"2026-10-17T23:17:25.123456+00:00","extra":true}""".encodeToByteArray())
        assertEquals("Alex", row.displayName)
        assertNull(row.note)
        assertEquals(Instant.parse("2026-10-17T23:17:25.123456Z"), row.createdAt)
        try {
            RemoteJSON.decode<Row>("""{"id":"1"}""".encodeToByteArray())
            fail("缺了必须的字段应该报错")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.Server("bad_response"), e)
        }
    }

    @Test
    fun appleSendsIdTokenAndRawNonce() = runTest {
        server.on("POST /auth/v1/token", token("apple"))
        val client = client()
        client.signInWithIdToken(provider = "apple", idToken = "id-token", nonce = "raw-nonce")

        assertEquals("grant_type=id_token", server.query(0))
        assertEquals("apple", text(0, "provider"))
        assertEquals("id-token", text(0, "id_token"))
        assertEquals("raw-nonce", text(0, "nonce"))
        assertEquals("apple", client.session?.accessToken)
        assertEquals("登录状态要存下来", "apple", saved.last()?.accessToken)
    }

    @Test
    fun onlyShowsProvidersSwitchedOnInSupabase() = runTest {
        server.on("GET /auth/v1/settings", """{"external":{"apple":true,"google":false,"email":true},"disable_signup":false}""")
        assertEquals(setOf("apple", "email"), client().enabledProviders())
        // 网络不通时是 null，不当成“都没开”
        assertNull(SupabaseClient(SessionStorage.memory, { throw IOException("offline") }).enabledProviders())
    }

    @Test
    fun readsSignInMethodsAndCallsFunctions() = runTest {
        server.on("GET /auth/v1/user", """{"id":"u","app_metadata":{"provider":"email","providers":["email","apple"]}}""")
        server.on("POST /functions/v1/apple-revoke", "")
        val client = client(session(3600))
        val methods = client.signInMethods()
        client.invoke("apple-revoke", json("code" to "c-1"))

        assertEquals(listOf("email", "apple"), methods)
        assertEquals("c-1", text(1, "code"))
        assertEquals("Bearer old", server.requests[1].headers["Authorization"])
    }

    @Test
    fun passwordSignUpWaitsForTheEmailCode() = runTest {
        server.on("POST /auth/v1/signup", """{"id":"u","email":"a@b.co","identities":[{"identity_id":"i","provider":"email","identity_data":{"email_verified":false}}]}""")
        server.on("POST /auth/v1/verify", token("confirmed"))
        val client = client()
        val session = client.signUp("a@b.co", "shuttle rally", captchaToken = "cap")
        assertNull("还要输入邮件里的确认码", session)
        assertEquals("shuttle rally", text(0, "password"))
        assertEquals("cap", server.json(0)["gotrue_meta_security"]?.jsonObject?.get("captcha_token")?.jsonPrimitive?.content)

        client.verify("a@b.co", "123456", type = "signup")
        assertEquals("signup", text(1, "type"))
        assertEquals("confirmed", client.session?.accessToken)
    }

    @Test
    fun signingUpAnExistingEmailSaysSo() = runTest {
        // 防探测时服务器返回一个没有登录方式的账号，而不是报错
        server.on("POST /auth/v1/signup", """{"id":"u","email":"a@b.co","identities":[]}""")
        try {
            client().signUp("a@b.co", "shuttle rally")
            fail("已注册的邮箱应该报错")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.Server("user_already_exists"), e)
        }
    }

    @Test
    fun passwordSignInResetAndChange() = runTest {
        server.on("POST /auth/v1/token", """{"error_code":"invalid_credentials","msg":"Invalid login credentials"}""", status = 400)
        server.on("POST /auth/v1/token", token("pw"))
        server.on("POST /auth/v1/recover", "{}")
        server.on("PUT /auth/v1/user", """{"id":"u"}""")
        val client = client()
        try {
            client.signIn("a@b.co", "wrong one")
            fail("密码错了应该报错")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.Server("invalid_credentials"), e)
        }
        client.signIn("a@b.co", "shuttle rally")
        assertEquals("grant_type=password", server.query(1))
        assertEquals("a@b.co", text(1, "email"))
        assertEquals("pw", client.session?.accessToken)

        client.sendPasswordReset("a@b.co")
        client.updatePassword("drop shot at dawn")
        assertEquals("/auth/v1/recover", server.path(2))
        assertEquals("PUT", server.requests[3].method)
        assertEquals("drop shot at dawn", text(3, "password"))
        assertEquals("Bearer pw", server.requests[3].headers["Authorization"])
    }

    @Test
    fun verifySendsCodeAndKeepsSession() = runTest {
        server.on("POST /auth/v1/verify", token("fresh"))
        val client = client()
        val session = client.verify("alex@example.com", "123456")

        assertEquals(userId, session.userId)
        assertEquals(clock + 3_600_000, session.expiresAt)
        assertEquals("fresh", client.session?.accessToken)
        val request = server.requests[0]
        assertEquals(SupabaseConfig.PUBLISHABLE_KEY, request.headers["apikey"])
        assertNull("登录前不带用户令牌", request.headers["Authorization"])
        assertEquals("email", text(0, "type"))
        assertEquals("123456", text(0, "token"))
    }

    @Test
    fun captchaTokenGoesWithTheCodeRequest() = runTest {
        server.on("POST /auth/v1/otp", "{}")
        server.on("POST /auth/v1/otp", "{}")
        server.on("POST /auth/v1/otp", """{"code":400,"error_code":"captcha_failed","msg":"captcha protection: request disallowed"}""", status = 400)
        val client = client()
        client.sendCode("alex@example.com", captchaToken = "turnstile-token")
        client.sendCode("alex@example.com", captchaToken = "")

        assertEquals("turnstile-token", server.json(0)["gotrue_meta_security"]?.jsonObject?.get("captcha_token")?.jsonPrimitive?.content)
        assertNull("网站没开人机验证时不带", server.json(1)["gotrue_meta_security"])
        try {
            client.sendCode("alex@example.com")
            fail("应该报错")
        } catch (e: RemoteError) {
            assertEquals("人机验证没有通过，请再试一次。", e.message)
        }
    }

    @Test
    fun databaseErrorBecomesReadableMessage() = runTest {
        server.on("POST /rest/v1/rpc/submit_ticket", """{"code":"22023","message":"too_soon","details":null,"hint":null}""", status = 400)
        val client = client(session(3600))
        try {
            client.call("submit_ticket", json("p_mode" to "doubles"))
            fail("应该报错")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.Server("too_soon"), e)
            assertNotEquals("有专门的提示", RemoteError.Server("unknown").message, e.message)
        }
        assertEquals("Bearer old", server.requests[0].headers["Authorization"])
        assertEquals("http_500", RemoteJSON.errorCode("oops".encodeToByteArray(), 500))
    }

    @Test
    fun expiringTokenIsRefreshedFirst() = runTest {
        server.on("POST /auth/v1/token", token("new"))
        server.on("POST /rest/v1/rpc/my_record", "{}")
        val client = client(session(30))
        client.call("my_record")

        assertEquals(listOf("/auth/v1/token", "/rest/v1/rpc/my_record"), listOf(server.path(0), server.path(1)))
        assertEquals("r-old", text(0, "refresh_token"))
        assertEquals("Bearer new", server.requests[1].headers["Authorization"])
        assertEquals("new", client.session?.accessToken)
    }

    @Test
    fun revokedRefreshTokenSignsOut() = runTest {
        server.on("POST /auth/v1/token", """{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}""", status = 400)
        val client = client(session(-10))
        var expired = false
        client.onSessionExpired = { expired = true }
        try {
            client.call("my_record")
            fail("应该要求重新登录")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.NotSignedIn, e)
        }
        assertNull(client.session)
        assertTrue(expired)
        assertNull("存着的登录状态也要清掉", saved.last())
    }

    @Test
    fun networkFailureIsReported() = runTest {
        val client = SupabaseClient(SessionStorage.memory, { throw IOException("offline") })
        try {
            client.sendCode("alex@example.com")
            fail("应该报网络错误")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.Network, e)
            assertEquals("请检查网络后重试。", e.message)
        }
    }

    @Test
    fun tablesAndFiles() = runTest {
        server.on("GET /rest/v1/favorite_venues", """[{"venue_id":"v-us-ca-labc"}]""")
        server.on("PATCH /rest/v1/profiles", "")
        server.on("DELETE /rest/v1/favorite_venues", "")
        server.on("POST /storage/v1/object/list/avatars", """[{"name":"a.jpg"},{"name":"b.jpg"}]""")
        server.onPrefix("POST /storage/v1/object/avatars/", """{"Key":"x"}""")
        server.onPrefix("GET /storage/v1/object/public/avatars/", "jpeg")
        val client = client(session(3600))

        @Serializable
        data class Favorite(val venueId: String)
        assertEquals(listOf(Favorite("v-us-ca-labc")), client.select<List<Favorite>>("favorite_venues", "select=venue_id"))
        assertEquals("select=venue_id", server.query(0))

        client.update("profiles", "id=eq.$userId", json("nickname" to "Alex", "show_on_boards" to false))
        assertEquals("PATCH", server.requests[1].method)
        assertEquals("false", text(1, "show_on_boards"))
        client.delete("favorite_venues", "venue_id=eq.v1")
        assertNull(server.requests[2].body)

        assertEquals(listOf("a.jpg", "b.jpg"), client.listFiles("avatars", userId))
        assertEquals(userId, text(3, "prefix"))
        client.upload("avatars", "$userId/abc.jpg", byteArrayOf(1, 2, 3), "image/jpeg")
        assertEquals("image/jpeg", server.requests[4].headers["Content-Type"])
        assertEquals(3, server.requests[4].body?.size)
        assertEquals("jpeg", client.download("avatars", "$userId/abc.jpg").decodeToString())
        assertFalse("公开文件不用带登录状态", server.requests[5].headers.containsKey("Authorization"))
    }

    @Test
    fun signOutClearsTheSessionEvenOffline() = runTest {
        val client = client(session(3600))
        client.signOut()
        assertEquals("/auth/v1/logout", server.path(0))
        assertNull(client.session)
    }
}
