package com.badie.app.shell

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.BuildConfig
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.pressable
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.remote.HttpRequest
import com.badie.app.remote.OkHttpTransport
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.IOException

/**
 * 从网站直接下载安装的 App（https://badie.rsvp/android/）不会自己更新：打开 App 时（一天最多查一次）读网站上的
 * version.json，有更新的版本就在标签栏上面提一句，点“下载”用浏览器下新的安装包。
 * 从 Google Play 装的不查（Play 自己会更新），调试包也不查。version.json 由发版工作流生成，见 docs/RELEASE.md。
 */
@Serializable
data class AndroidRelease(
    val versionCode: Long,
    val versionName: String,
    val url: String,
    val sha256: String? = null,
    val minSdk: Int = 1,
)

/** 存检查结果的地方（App 里是 SharedPreferences，测试里是一张表） */
interface UpdateStore {
    operator fun get(key: String): String?
    operator fun set(key: String, value: String?)
}

@Stable
class SideloadUpdates(
    /** 正式包、不是从 Play 装的 */
    private val enabled: Boolean,
    private val installedVersionCode: Long,
    private val sdk: Int,
    private val store: UpdateStore,
    /** 读 version.json：200 返回内容，其他状态返回 null，连不上抛 IOException */
    private val fetch: suspend () -> String?,
    private val now: () -> Long = System::currentTimeMillis,
) {
    /** 有新版本、还没关掉过：标签栏上面显示 */
    var available by mutableStateOf<AndroidRelease?>(null)

    /** 打开 App 时调：距上次查不到一天就用上次的结果 */
    suspend fun checkIfDue() {
        if (!enabled) return
        val time = now()
        val last = store[LAST_CHECK]?.toLongOrNull() ?: 0L
        if (time - last >= DAY_MILLIS || time < last) {
            try {
                val body = fetch()
                store[LAST_CHECK] = time.toString()
                // 网站上还没有安装包（404）时也算查过了，明天再查
                if (body != null && parse(body) != null) store[LATEST] = body
            } catch (_: IOException) {
                // 没网：下次打开再查
            }
        }
        available = store[LATEST]?.let(::parse)?.takeIf(::shouldOffer)
    }

    /** 关掉这一版的提示；有更新的版本时再提 */
    fun dismiss() {
        available?.let { store[DISMISSED] = it.versionCode.toString() }
        available = null
    }

    private fun shouldOffer(release: AndroidRelease) =
        isNewer(release.versionCode, installedVersionCode) && release.minSdk <= sdk && release.versionCode.toString() != store[DISMISSED]

    companion object {
        const val VERSION_URL = "https://badie.rsvp/android/version.json"
        const val APK_URL = "https://badie.rsvp/android/badie.apk"
        const val PLAY_STORE = "com.android.vending"
        const val DAY_MILLIS = 24L * 60 * 60 * 1000
        private const val LAST_CHECK = "lastCheck"
        private const val LATEST = "latest"
        private const val DISMISSED = "dismissed"
        private val json = Json { ignoreUnknownKeys = true }

        fun isNewer(remote: Long, installed: Long) = remote > installed

        fun installedFromPlay(installer: String?) = installer == PLAY_STORE

        /** 只有自己下载安装的正式包要查 */
        fun shouldCheck(debug: Boolean, installer: String?) = !debug && !installedFromPlay(installer)

        fun parse(text: String): AndroidRelease? = try {
            json.decodeFromString<AndroidRelease>(text).takeIf { it.versionCode > 0 }
        } catch (_: Exception) {
            null
        }

        /** 只打开自己网站上的地址，别的一律换成固定的下载地址 */
        fun downloadUrl(release: AndroidRelease) = release.url.takeIf { it.startsWith("https://badie.rsvp/") } ?: APK_URL

        /** 测试和截图里用：什么都不查 */
        fun disabled() = SideloadUpdates(false, 0, 0, MemoryStore(), { null })

        fun forApp(context: Context?): SideloadUpdates {
            if (context == null) return disabled()
            val prefs = context.getSharedPreferences("updates", Context.MODE_PRIVATE)
            return SideloadUpdates(
                enabled = shouldCheck(BuildConfig.DEBUG, installerOf(context)),
                installedVersionCode = BuildConfig.VERSION_CODE.toLong(),
                sdk = Build.VERSION.SDK_INT,
                store = PrefsStore(prefs),
                fetch = {
                    val response = OkHttpTransport.transport(HttpRequest(VERSION_URL, "GET", mapOf("Accept" to "application/json"), null, 15_000))
                    if (response.status == 200) String(response.body) else null
                },
            )
        }

        /** 是哪个 App 装的（Play 是 com.android.vending，浏览器下载的是系统的软件包安装程序） */
        private fun installerOf(context: Context): String? = try {
            if (Build.VERSION.SDK_INT >= 30) {
                context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getInstallerPackageName(context.packageName)
            }
        } catch (_: Exception) {
            null
        }
    }
}

class MemoryStore : UpdateStore {
    private val values = HashMap<String, String>()
    override fun get(key: String) = values[key]
    override fun set(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }
}

private class PrefsStore(private val prefs: SharedPreferences) : UpdateStore {
    override fun get(key: String): String? = prefs.getString(key, null)
    override fun set(key: String, value: String?) {
        prefs.edit().putString(key, value).apply()
    }
}

/** 标签栏上面的一条：新版本、下载、关掉 */
@Composable
fun UpdateBanner(release: AndroidRelease, onDownload: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .sticker(colors.lime, radius = 16.dp, shadow = AppTheme.Elevation.low)
            .padding(start = AppTheme.Spacing.md, top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.sm, end = AppTheme.Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(Sym.arrowDownCircleFill, size = 18, tint = colors.onAccent)
        Text(
            tr("Badie %@ 可以更新了", release.versionName),
            style = AppTheme.Typography.footnoteBold,
            color = colors.onAccent,
            modifier = Modifier.weight(1f),
        )
        BrutalButton(tr("下载"), onDownload, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
        val close = tr("关闭")
        Box(
            Modifier.size(40.dp).pressable(onClick = onDismiss).semantics { contentDescription = close },
            contentAlignment = Alignment.Center,
        ) {
            Symbol(Sym.xmark, size = 14, tint = colors.onAccent)
        }
    }
}
