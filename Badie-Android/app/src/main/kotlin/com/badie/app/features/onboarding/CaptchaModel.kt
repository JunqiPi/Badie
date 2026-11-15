package com.badie.app.features.onboarding

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/**
 * 人机验证（Cloudflare Turnstile）的状态。令牌只能用一次，发完请求就重新取。
 * token 是空字符串表示网站没开人机验证，直接发就行
 */
@Stable
class CaptchaModel {
    var token: String? by mutableStateOf(null)
        private set

    /** Cloudflare 觉得可疑、需要点一下：这时把验证框露出来 */
    var needsInteraction by mutableStateOf(false)
        private set

    var failed by mutableStateOf(false)
        private set

    /** 每重置一次加一，网页据此重新加载 */
    var attempt by mutableIntStateOf(0)
        private set

    val isReady: Boolean get() = token != null

    fun reset() {
        token = null
        needsInteraction = false
        failed = false
        attempt += 1
    }

    /** 网站的 /captcha/ 页面传回来的消息：{token} / {interactive: true} / {error} */
    fun receive(message: String) {
        val body = try {
            Json.parseToJsonElement(message) as? JsonObject
        } catch (_: SerializationException) {
            null
        } ?: return
        val token = (body["token"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        val error = (body["error"] as? JsonPrimitive)?.contentOrNull
        when {
            token != null -> {
                this.token = token
                needsInteraction = false
            }
            (body["interactive"] as? JsonPrimitive)?.booleanOrNull == true -> needsInteraction = true
            error == "expired" -> reset()
            error != null -> failed = true
        }
    }

    fun loadFailed() {
        failed = true
    }
}
