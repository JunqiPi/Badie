package com.badie.app.remote

import com.badie.app.l10n.L10n.tr
import java.io.IOException
import java.security.MessageDigest

/**
 * 密码规则（和网页、iPhone 一样）：至少 8 位，不强制大小写、数字、符号（NIST 800-63B 的建议）；
 * 注册、重设、修改时查一下是不是泄露过的密码。查法是 k-匿名：只把 SHA-1 的前 5 位发给 Have I Been Pwned，
 * 密码本身不离开手机。查不了（离线、超时）就放行
 */
object PasswordRules {
    const val MINIMUM_LENGTH = 8
    /** Supabase 用 bcrypt，超过 72 字节的部分不起作用 */
    private const val MAXIMUM_BYTES = 72

    /** 返回要显示给用户的问题；没问题返回 null */
    suspend fun problem(password: String, lookup: Transport): String? {
        // 按用户看到的字符数算（一个表情算一个）
        if (password.codePointCount(0, password.length) < MINIMUM_LENGTH) return tr("密码至少要 8 位。")
        if (password.encodeToByteArray().size > MAXIMUM_BYTES) return tr("密码太长了，请换个短一点的。")
        if (leaked(password, lookup)) return tr("这个密码在数据泄露中出现过，请换一个。")
        return null
    }

    private suspend fun leaked(password: String, lookup: Transport): Boolean {
        val hash = MessageDigest.getInstance("SHA-1").digest(password.encodeToByteArray()).joinToString("") { "%02X".format(it) }
        // 回复里混进次数为 0 的假条目，别人看流量大小也猜不出是哪个前缀
        val request = HttpRequest("https://api.pwnedpasswords.com/range/${hash.take(5)}", "GET", mapOf("Add-Padding" to "true"), null, timeoutMillis = 4_000)
        val response = try {
            lookup(request)
        } catch (_: IOException) {
            return false
        }
        if (response.status != 200) return false
        val suffix = hash.drop(5)
        return response.body.decodeToString().lineSequence().any { line ->
            val parts = line.split(":").map { it.trim() }
            parts.size == 2 && parts[0] == suffix && (parts[1].toIntOrNull() ?: 0) > 0
        }
    }
}
