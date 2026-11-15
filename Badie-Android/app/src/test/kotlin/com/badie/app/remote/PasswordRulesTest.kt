package com.badie.app.remote

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.IOException

class PasswordRulesTest {
    /** "password" 的 SHA-1 是 5BAA6 1E4C9B93F3F0682250B6CF8331B7EE68FD8 */
    private fun list(vararg lines: String): Transport = { request ->
        assertEquals("只发前 5 位", "https://api.pwnedpasswords.com/range/5BAA6", request.url)
        assertEquals("true", request.headers["Add-Padding"])
        HttpResponse(200, lines.joinToString("\r\n").encodeToByteArray())
    }

    @Test
    fun rules() = runTest {
        assertEquals("密码至少要 8 位。", PasswordRules.problem("short", list()))
        assertEquals(
            "这个密码在数据泄露中出现过，请换一个。",
            PasswordRules.problem("password", list("0018A45C4D1DEF81644B54AB7F969B88D65:1", "1E4C9B93F3F0682250B6CF8331B7EE68FD8:9545824")),
        )
        assertNull("次数为 0 的是混进来的假条目", PasswordRules.problem("password", list("1E4C9B93F3F0682250B6CF8331B7EE68FD8:0")))
        assertNull("查不了就放行", PasswordRules.problem("correct horse battery") { throw IOException("offline") })
        assertEquals("密码太长了，请换个短一点的。", PasswordRules.problem("x".repeat(73), list()))
    }
}
