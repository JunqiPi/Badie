package com.badie.app.remote

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.serialization.json.Json
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 登录状态存在 App 自己的文件里，用系统密钥库里的密钥加密（密钥拿不出这台手机）。
 * 对应 iPhone 的钥匙串。解不开（换了手机、密钥没了）就当没登录
 */
object KeystoreSessionStorage {
    private const val ALIAS = "supabase-session"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    fun create(context: Context): SessionStorage {
        val file = File(context.applicationContext.noBackupFilesDir, "session")
        return SessionStorage(
            load = {
                try {
                    if (file.exists()) Json.decodeFromString<RemoteSession>(decrypt(file.readBytes()).decodeToString()) else null
                } catch (_: Exception) {
                    null
                }
            },
            save = { session ->
                try {
                    if (session == null) file.delete() else file.writeBytes(encrypt(Json.encodeToString(RemoteSession.serializer(), session).encodeToByteArray()))
                } catch (_: Exception) {
                    // 存不下只是下次要重新登录
                    file.delete()
                }
            },
        )
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** 存的是：1 字节的 IV 长度 + IV + 密文 */
    private fun encrypt(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.doFinal(plain)
        return byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + sealed
    }

    private fun decrypt(stored: ByteArray): ByteArray {
        val ivSize = stored[0].toInt()
        if (ivSize !in 12..16 || stored.size <= 1 + ivSize) throw GeneralSecurityException("bad session file")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, stored, 1, ivSize))
        return cipher.doFinal(stored, 1 + ivSize, stored.size - 1 - ivSize)
    }
}
