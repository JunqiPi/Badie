package com.badie.app.features.onboarding

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.remote.BrowserSignIn
import com.badie.app.remote.FakeServer
import com.badie.app.remote.HttpResponse
import com.badie.app.remote.SocialSignIn
import com.badie.app.remote.SupabaseConfig
import com.badie.app.shell.AppState
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URI
import java.net.URLDecoder

/** Apple、Google 登录：发了什么、取消和出错怎么走、按钮什么时候显示 */
class SocialSignInTest {
    private val server = FakeServer()

    private fun TestScope.flow(saved: Set<String>? = null, save: (Set<String>) -> Unit = {}): Pair<OnboardingModel, AppState> {
        val appState = AppState(backgroundScope, TestSupport.backend(server))
        appState.finishLaunch()
        val model = OnboardingModel(
            appState, CaptchaModel(), passwordLookup = { HttpResponse(200, ByteArray(0)) }, now = { TestSupport.CLOCK },
            savedProviders = saved, saveProviders = save,
        )
        return model to appState
    }

    private fun query(url: String): Map<String, String> = URI(url).rawQuery.split("&").associate {
        val (key, value) = it.split("=", limit = 2)
        key to URLDecoder.decode(value, "UTF-8")
    }

    @Test
    fun hashes() {
        // RFC 7636 附录 B 的例子
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", SocialSignIn.pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", SocialSignIn.sha256Hex("abc"))
        val random = SocialSignIn.randomString()
        assertEquals(43, random.length)
        assertTrue("base64url，不带 =", random.all { it.isLetterOrDigit() || it == '-' || it == '_' })
    }

    @Test
    fun browserSignInUrlAndCallback() {
        val flow = BrowserSignIn("apple")
        assertTrue(flow.url.startsWith("${SupabaseConfig.URL}/auth/v1/authorize?"))
        val items = query(flow.url)
        assertEquals("apple", items["provider"])
        assertEquals("com.badie.app://auth/callback", items["redirect_to"])
        assertEquals(SocialSignIn.pkceChallenge(flow.verifier), items["code_challenge"])
        assertEquals("s256", items["code_challenge_method"])

        assertEquals("abc-123", flow.code("com.badie.app://auth/callback?code=abc-123"))
        assertNull("对方报错（比如取消）", flow.code("com.badie.app://auth/callback?error=access_denied&error_description=cancelled"))
        assertNull("不是回调地址", flow.code("https://evil.example/auth/callback?code=abc"))
    }

    @Test
    fun googleNewUserGoesToProfile() = runTest {
        val (model, appState) = flow()
        var hashed: String? = null
        server.on("POST /auth/v1/token", TestSupport.token("g"))
        server.serveProfile("[]")
        model.signInWithGoogle { clientId, nonce ->
            assertEquals(SocialSignIn.googleServerClientId, clientId)
            hashed = nonce
            "google-id-token"
        }
        assertEquals("grant_type=id_token", server.query(0))
        val body = server.json(0)
        assertEquals("google", body["provider"]?.jsonPrimitive?.content)
        assertEquals("google-id-token", body["id_token"]?.jsonPrimitive?.content)
        assertEquals("发给 Google 的是 nonce 的哈希，交给 Supabase 的是原文", hashed, SocialSignIn.sha256Hex(body["nonce"]!!.jsonPrimitive.content))
        assertEquals(OnboardingStep.Profile, model.step)
        assertEquals(AppState.Phase.Onboarding, appState.phase)
        assertNull(model.errorText)
        assertFalse(model.isWorking)
    }

    @Test
    fun googleCancelAndFailure() = runTest {
        val (model, _) = flow()
        model.signInWithGoogle { _, _ -> null }
        assertTrue("取消了不发请求", server.requests.isEmpty())
        assertNull("取消了不提示", model.errorText)

        model.signInWithGoogle { _, _ -> error("no Android client") }
        assertEquals("登录没有完成，请再试一次，或改用邮箱。", model.errorText)

        server.on("POST /auth/v1/token", """{"error_code":"bad_jwt"}""", status = 400)
        model.signInWithGoogle { _, _ -> "token" }
        assertEquals("登录没有完成，请再试一次，或改用邮箱。", model.errorText)
        assertEquals(OnboardingStep.Welcome, model.step)
        assertFalse(model.isWorking)
    }

    @Test
    fun appleExistingUserSignsIn() = runTest {
        val (model, appState) = flow()
        var opened: String? = null
        server.on("POST /auth/v1/token", TestSupport.token("a"))
        server.serveProfile("[${TestSupport.profile()}]")
        model.signInWithApple { url ->
            opened = url
            "com.badie.app://auth/callback?code=one-time"
        }
        val challenge = query(opened!!)["code_challenge"]
        assertEquals("grant_type=pkce", server.query(0))
        val body = server.json(0)
        assertEquals("one-time", body["auth_code"]?.jsonPrimitive?.content)
        assertEquals("换登录状态时交出 verifier 原文", challenge, SocialSignIn.pkceChallenge(body["code_verifier"]!!.jsonPrimitive.content))
        assertEquals(AppState.Phase.Main, appState.phase)
        assertEquals("欢迎回来，Alex", appState.toast?.message)
    }

    @Test
    fun appleCancel() = runTest {
        val (model, _) = flow()
        // 关掉了浏览器标签页
        model.signInWithApple { null }
        // 在 Apple 页面点了取消：跳回来但没有 code
        model.signInWithApple { "com.badie.app://auth/callback?error=access_denied" }
        assertTrue(server.requests.isEmpty())
        assertNull(model.errorText)

        model.signInWithApple { throw IllegalStateException("没有浏览器") }
        assertEquals("登录没有完成，请再试一次，或改用邮箱。", model.errorText)
    }

    @Test
    fun providersFollowServer() = runTest {
        var saved: Set<String>? = null
        val (model, _) = flow(save = { saved = it })
        assertEquals("第一次打开：当作都开着", setOf("apple", "google"), model.socialProviders)

        // 网络不通：还用原来的
        model.refreshProviders()
        assertEquals(setOf("apple", "google"), model.socialProviders)
        assertNull(saved)

        server.on("GET /auth/v1/settings", """{"external":{"apple":false,"google":true,"email":true}}""")
        model.refreshProviders()
        assertEquals(setOf("google", "email"), saved)
        assertEquals("Apple 没开时 Google 也不显示（和 iPhone 一样）", emptySet<String>(), model.socialProviders)

        val (other, _) = flow(saved = setOf("apple", "email"))
        assertEquals(setOf("apple"), other.socialProviders)
    }

    @Test
    fun callbackSession() {
        assertFalse("网页链接不是登录回调", BrowserAuthSession.receive("https://badie.rsvp/games/1/"))
        assertTrue("没在等的回调直接吞掉", BrowserAuthSession.receive("com.badie.app://auth/callback?code=x"))
        // 没在登录时切前后台不影响
        BrowserAuthSession.paused()
        BrowserAuthSession.resumed()
    }
}
