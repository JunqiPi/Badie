package com.badie.app.features.onboarding

import android.app.Activity
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.badie.app.remote.SocialSignIn
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.CompletableDeferred

/** 拿 Google 的身份令牌（令牌里的 nonce 是传进来的哈希）。用户取消了返回 null */
fun interface GoogleCredentials {
    suspend fun idToken(serverClientId: String, hashedNonce: String): String?
}

/** 在浏览器里打开授权页，等它跳回 App，返回跳回来的地址。用户没登录就回来了返回 null */
fun interface BrowserAuth {
    suspend fun open(url: String): String?
}

/** 系统的凭据管理器：底部弹出 Google 账号选择（没有 Google 账号时引导添加） */
class CredentialManagerGoogle(private val activity: Activity) : GoogleCredentials {
    override suspend fun idToken(serverClientId: String, hashedNonce: String): String? {
        val option = GetSignInWithGoogleOption.Builder(serverClientId).setNonce(hashedNonce).build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val credential = try {
            CredentialManager.create(activity).getCredential(activity, request).credential
        } catch (_: GetCredentialCancellationException) {
            return null
        } catch (error: NoCredentialException) {
            // 手机上没有能用的 Google 账号，或者 Google Cloud 里还没有这个包名和签名的安卓客户端
            throw IllegalStateException("google_no_credential", error)
        }
        check(credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) { "google_no_token" }
        return GoogleIdTokenCredential.createFrom(credential.data).idToken
    }
}

/**
 * 浏览器标签页（Custom Tabs）里的授权：打开以后挂起，等 MainActivity 收到 [SocialSignIn.CALLBACK] 开头的地址（[receive]）。
 * 用户没走完就退回 App（关掉标签页、按返回）时，MainActivity 先后调 [paused]、[resumed]，算取消。都在主线程调
 */
object BrowserAuthSession {
    private var pending: CompletableDeferred<String?>? = null
    /** 打开授权页以后 App 让出了前台（之后回到前台而没有带回地址，就是没走完） */
    private var left = false

    fun opener(activity: Activity) = BrowserAuth { url ->
        pending?.complete(null)
        val deferred = CompletableDeferred<String?>()
        pending = deferred
        left = false
        try {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, url.toUri())
        } catch (error: android.content.ActivityNotFoundException) {
            // 手机上没有浏览器
            pending = null
            throw error
        }
        deferred.await()
    }

    /** 收到一个 App 内的地址：是登录回调就交给正在等的授权（没在等就忽略），返回是不是登录回调 */
    fun receive(link: String): Boolean {
        if (!link.startsWith("${SocialSignIn.CALLBACK_SCHEME}://")) return false
        pending?.complete(link)
        pending = null
        left = false
        return true
    }

    fun paused() {
        if (pending != null) left = true
    }

    fun resumed() {
        if (!left) return
        left = false
        pending?.complete(null)
        pending = null
    }
}
