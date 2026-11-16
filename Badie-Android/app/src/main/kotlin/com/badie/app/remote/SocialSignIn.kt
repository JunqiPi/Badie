package com.badie.app.remote

import java.net.URI
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

// MARK: - Apple / Google 登录用的一次性随机串（对应 iPhone 的 Services/Remote/SocialSignIn.swift）

/**
 * Google：发给 Google 的是 nonce 的 SHA-256，交给 Supabase 的是原文，Supabase 核对两者对得上，别人截到身份令牌也没法重放。
 * Apple：安卓没有系统的 Apple 登录，走 Supabase 的网页授权（PKCE）：发出去的是 verifier 的哈希，换登录状态时才交出原文
 */
object SocialSignIn {
    /**
     * Google 登录要的“服务器客户端 ID”：Google Cloud 里网页类型的 OAuth 客户端（Supabase 的 Google 设置里填的那个，公开的，不是密钥）。
     * 身份令牌签给这个 ID，Supabase 认得。安卓类型的客户端（包名 + 签名证书的 SHA-1）也要在同一个 Google Cloud 项目里建好，
     * 凭据管理器才肯给令牌，见 Badie-Android/docs/RELEASE.md。设为 null 时不显示 Google 按钮
     */
    val googleServerClientId: String? = "302163183222-r66sbsp292mnkm3p3u4g6bodauk80vt6.apps.googleusercontent.com"

    /** Apple 授权完跳回 App 的地址（AndroidManifest.xml 里 MainActivity 认这个 scheme）。要加进 Supabase 的 Redirect URLs */
    const val CALLBACK_SCHEME = "com.badie.app"
    const val CALLBACK = "$CALLBACK_SCHEME://auth/callback"

    private val random = SecureRandom()

    fun randomString(bytes: Int = 32): String = base64URL(ByteArray(bytes).also(random::nextBytes))

    /** 十六进制的 SHA-256（Google 的 nonce） */
    fun sha256Hex(text: String): String = sha256(text).joinToString("") { "%02x".format(it) }

    /** PKCE 的 S256：SHA-256 再 base64url（不带 =） */
    fun pkceChallenge(verifier: String): String = base64URL(sha256(verifier))

    private fun sha256(text: String): ByteArray = MessageDigest.getInstance("SHA-256").digest(text.toByteArray())

    private fun base64URL(data: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(data)
}

/**
 * 在浏览器里走 Supabase 的第三方登录（安卓上的 Apple 登录）：打开 [url]，Supabase 转到 Apple，授权完跳回 [SocialSignIn.CALLBACK]，
 * 带一次性的 code；拿 code 和 [verifier] 换登录状态（[SupabaseClient.exchangeCode]）。
 * Apple 那边用的是网站的服务 ID（com.badie.web），和网页登录同一套
 */
class BrowserSignIn(val provider: String, val redirect: String = SocialSignIn.CALLBACK) {
    val verifier = SocialSignIn.randomString()

    val url: String
        get() = "${SupabaseConfig.URL}/auth/v1/authorize?" + listOf(
            "provider" to provider,
            "redirect_to" to redirect,
            "code_challenge" to SocialSignIn.pkceChallenge(verifier),
            "code_challenge_method" to "s256",
        ).joinToString("&") { (key, value) -> "$key=${URLEncoder.encode(value, "UTF-8")}" }

    /** 跳回来的地址里取 code；不是我们的回调地址、对方报错（比如点了取消）时为空 */
    fun code(callback: String): String? {
        if (!callback.startsWith(redirect)) return null
        val uri = try {
            URI(callback)
        } catch (_: java.net.URISyntaxException) {
            return null
        }
        return uri.rawQuery?.split("&")?.firstNotNullOfOrNull { item ->
            val pair = item.split("=", limit = 2)
            if (pair.first() == "code") java.net.URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8").takeIf { it.isNotEmpty() } else null
        }
    }
}
