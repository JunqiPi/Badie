package com.badie.app

import android.app.Application
import com.badie.app.backend.Backend
import com.badie.app.backend.CacheStore
import com.badie.app.l10n.AppLanguage
import com.badie.app.remote.KeystoreSessionStorage
import com.badie.app.remote.OkHttpTransport
import com.badie.app.remote.SupabaseClient
import com.badie.app.shell.AppEnvironment
import kotlinx.coroutines.MainScope
import java.io.File
import java.io.IOException
import java.util.Locale

class BadieApplication : Application() {
    /** 整个 App 一份，Activity 重建（转屏、换语言）时不丢 */
    val environment: AppEnvironment by lazy {
        val remote = SupabaseClient(KeystoreSessionStorage.create(this), OkHttpTransport.transport)
        val photos = com.badie.app.backend.PhotoStore(remote, MainScope(), File(cacheDir, "photos"))
        val backend = Backend(
            remote, cacheStore(), deviceCountry = { Locale.getDefault().country }, serverLocale = { AppLanguage.current }, photos = photos,
        )
        val settings = getSharedPreferences("settings", MODE_PRIVATE)
        AppEnvironment(MainScope(), backend, settings.getString("appearance", null), { settings.edit().putString("appearance", it).apply() }, this)
            .also { it.appState.start() }
    }

    /** 本机缓存：一个文件，放在 App 自己的目录里（不备份，见 data_extraction_rules.xml） */
    private fun cacheStore(): CacheStore {
        val file = File(filesDir, "cache.json")
        return CacheStore(
            load = {
                try {
                    if (file.exists()) file.readText() else null
                } catch (_: IOException) {
                    null
                }
            },
            save = { text ->
                try {
                    if (text == null) file.delete() else file.writeText(text)
                } catch (_: IOException) {
                    // 存不下只是下次打开要等网络
                }
            },
        )
    }
}
