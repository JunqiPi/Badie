package com.badie.app.features.onboarding

import android.annotation.SuppressLint
import android.graphics.Color
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.badie.app.remote.SupabaseConfig

/**
 * 打开网站上的 /captcha/ 页面（站点密钥只配在网站上），页面通过 BadieCaptcha.postMessage 把令牌交回来。
 * 平时看不见，需要用户点的时候由外面把高度放开
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CaptchaView(model: CaptchaModel, modifier: Modifier = Modifier) {
    val attempt = model.attempt
    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.cacheMode = WebSettings.LOAD_NO_CACHE
                setBackgroundColor(Color.TRANSPARENT)
                isVerticalScrollBarEnabled = false
                // 页面只会往这里发一条 JSON；回调不在主线程，交回主线程再改状态
                addJavascriptInterface(
                    object {
                        @JavascriptInterface
                        fun postMessage(message: String) {
                            post { model.receive(message) }
                        }
                    },
                    "BadieCaptcha",
                )
                webViewClient = object : WebViewClient() {
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                        if (request.isForMainFrame) model.loadFailed()
                    }
                }
                tag = -1
            }
        },
        update = { view ->
            if (view.tag != attempt) {
                view.tag = attempt
                view.loadUrl(SupabaseConfig.CAPTCHA_PAGE)
            }
        },
        onRelease = { it.destroy() },
    )
}
