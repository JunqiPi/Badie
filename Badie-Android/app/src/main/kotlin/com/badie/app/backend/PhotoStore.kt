package com.badie.app.backend

import android.graphics.BitmapFactory
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.badie.app.models.stableHash
import com.badie.app.remote.RemoteError
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.io.File
import java.util.UUID
import kotlin.math.abs

/**
 * 照片头像和卡片背景。照片存在公开的 avatars 桶里（文件名随机），地址只给打过交道的人。
 * 别人的头像：见到一个人就记下来，攒 0.3 秒一起查地址（每批 100 人），下载后放进内存和本机缓存。
 * 对应 iPhone 的 MockBackend+RemoteAvatars.swift 和 AvatarPhotos
 */
@Stable
class PhotoStore(
    private val remote: SupabaseClient,
    private val scope: CoroutineScope,
    /** 下载过的照片存在这里（按地址的哈希起名，地址没变就不重新下载）；测试时为空 */
    private val cacheDir: File?,
    private val decode: (ByteArray) -> ImageBitmap? = { bytes ->
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
    },
) {
    /** 用户 ID → 头像；卡片背景的键是 card:<用户 ID>。界面读这里，下载好了自动刷新 */
    private val images = mutableStateMapOf<String, ImageBitmap>()

    /** 各人现在的照片地址（null = 没有照片） */
    private val paths = HashMap<String, String?>()
    private val checked = HashSet<String>()
    private val queue = ArrayList<String>()

    fun avatar(userId: String): ImageBitmap? {
        requestAvatar(userId)
        return images[userId]
    }

    fun cardPhoto(userId: String): ImageBitmap? = images[cardKey(userId)]

    /** 记下要查头像的人（每次启动每人查一次），0.3 秒内见到的人一起查 */
    fun requestAvatar(userId: String) {
        if (remote.session == null || !checked.add(userId)) return
        queue.add(userId)
        if (queue.size > 1) return
        scope.launch {
            delay(300)
            loadQueued()
        }
    }

    private suspend fun loadQueued() {
        val ids = queue.toList()
        queue.clear()
        for (batch in ids.chunked(100)) {
            val rows = try {
                remote.rpc<List<AvatarRow>>("avatars", json("p_users" to batch))
            } catch (_: RemoteError) {
                // 下次见到再查
                batch.forEach(checked::remove)
                continue
            }
            val found = rows.associate { it.id to it.path }
            for (id in batch) apply(id, found[id])
        }
    }

    /** 别的接口顺带给了地址（资料、卡片）：直接用，不用再查 */
    suspend fun apply(userId: String, path: String?) {
        checked.add(userId)
        load(userId, path)
    }

    suspend fun applyCard(userId: String, path: String?) = load(cardKey(userId), path)

    /** 地址变了才下载；没有照片就清掉（改回文字头像） */
    private suspend fun load(key: String, path: String?) {
        if (paths.containsKey(key) && paths[key] == path && (path == null || images[key] != null)) return
        paths[key] = path
        if (path == null) {
            images.remove(key)
            return
        }
        val bytes = readCache(path) ?: try {
            remote.download(BUCKET, path).also { writeCache(path, it) }
        } catch (_: RemoteError) {
            // 下载失败：下次再试
            paths.remove(key)
            return
        }
        decode(bytes)?.let { images[key] = it }
    }

    private fun cacheFile(path: String): File? = cacheDir?.let { File(it, "${abs(path.stableHash)}.jpg") }

    private fun readCache(path: String): ByteArray? = cacheFile(path)?.takeIf { it.exists() }?.let {
        runCatching { it.readBytes() }.getOrNull()
    }

    private fun writeCache(path: String, bytes: ByteArray) {
        val file = cacheFile(path) ?: return
        runCatching {
            file.parentFile?.mkdirs()
            file.writeBytes(bytes)
        }
    }

    // MARK: 自己的照片

    /** 文件夹里没在用的文件（以前没删成的、被管理员撤下的）：传新照片前清掉 */
    suspend fun cleanUpFolder(me: String, keeping: List<String?>) {
        val names = try {
            remote.listFiles(BUCKET, me)
        } catch (_: RemoteError) {
            return
        }
        val inUse = keeping.filterNotNull().toSet()
        for (name in names) {
            val path = "$me/$name"
            if (path !in inUse) runCatching { remote.removeFile(BUCKET, path) }
        }
    }

    /**
     * 传一张照片并设上（set 是 set_avatar 或 set_card_photo），再删掉旧的。
     * 没设成就把刚传的删掉，不留垃圾文件。返回新地址
     */
    suspend fun upload(me: String, jpeg: ByteArray, set: String, old: String?, other: String?): String {
        cleanUpFolder(me, listOf(old, other))
        val path = "$me/${UUID.randomUUID().toString().lowercase()}.jpg"
        remote.upload(BUCKET, path, jpeg, "image/jpeg")
        try {
            remote.call(set, json("p_path" to path))
        } catch (error: RemoteError) {
            runCatching { remote.removeFile(BUCKET, path) }
            throw error
        }
        if (old != null) runCatching { remote.removeFile(BUCKET, old) }
        writeCache(path, jpeg)
        val key = if (set == "set_card_photo") cardKey(me) else me
        paths[key] = path
        decode(jpeg)?.let { images[key] = it }
        return path
    }

    /** 不用照片了（改回文字头像 / 卡片改用颜色） */
    suspend fun remove(me: String, set: String, old: String?) {
        remote.call(set, json("p_path" to null))
        if (old != null) runCatching { remote.removeFile(BUCKET, old) }
        val key = if (set == "set_card_photo") cardKey(me) else me
        paths[key] = null
        images.remove(key)
    }

    /** 退出登录：别人的照片不留在内存里 */
    fun clear() {
        images.clear()
        paths.clear()
        checked.clear()
        queue.clear()
    }

    @Serializable
    private class AvatarRow(val id: String, val path: String)

    companion object {
        const val BUCKET = "avatars"

        fun cardKey(userId: String) = "card:$userId"

        /** 照片的版本号 = 地址的哈希（地址没变就是同一张） */
        fun version(path: String): Int = abs(path.stableHash)
    }
}
