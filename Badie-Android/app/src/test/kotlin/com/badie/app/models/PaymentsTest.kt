package com.badie.app.models

import com.badie.app.backend.GroupsApi
import com.badie.app.features.groups.LedgerExport
import com.badie.app.l10n.L10n.tr
import com.badie.app.remote.RemoteJSON
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** 收款：服务器给的 JSON 能读出来（金额是 numeric 10.00、访客没有用户 id）、价格文字、导出的表格。对应 iPhone 的 ClubNightTests 里收款的部分 */
class PaymentsTest {

    @Test
    fun decodesLedgerAndDues() {
        val ledger = RemoteJSON.decode<GroupLedger>(
            """{"sessions":[{"id":"s-1","starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00","venue":"LABC",
                "tz":"America/Los_Angeles","amount":12.50,"payee":"Kevin","owes":12,"paid":12},
               {"id":"s-2","starts_at":"2026-11-11T19:00:00-08:00","ends_at":"2026-11-11T22:00:00-08:00","venue":"LABC",
                "tz":"America/Los_Angeles","amount":null,"payee":"Kevin","owes":0,"paid":0}],
               "owed":[{"id":"u-2","name":"Amy","guest":false,"sessions":2,"amount":25.00,"signups":["a","b"]},
                       {"id":null,"name":"Tony","guest":true,"sessions":1,"amount":12.50,"signups":["c"]}]}""".toByteArray(),
        )
        assertEquals(12.5, ledger.sessions.first().amount!!, 0.001)
        assertNull(ledger.sessions.last().amount)
        assertEquals("u-2", ledger.owed!!.first().userId)
        assertEquals("guest:tony", ledger.owed!!.last().key)
        assertEquals(listOf("c"), ledger.owed!!.last().signups)
        // 往前翻的页没有“谁还欠着”
        assertNull(RemoteJSON.decode<GroupLedger>("""{"sessions":[],"owed":null}""".toByteArray()).owed)

        val dues = RemoteJSON.decode<List<MyDue>>(
            """[{"session_id":"s-1","group_id":"g-1","group":"LABC 周三","starts_at":"2026-11-18T19:00:00-08:00",
                "ends_at":"2026-11-18T22:00:00-08:00","tz":"America/Los_Angeles","amount":12.00,"to":"Kevin","to_id":"u-1",
                "handles":{"venmo":"kevin-w","zelle":"kevin@example.com"}}]""".toByteArray(),
        )
        assertEquals(12.0, dues.first().amount, 0.001)
        assertEquals("kevin-w", dues.first().handles?.venmo)
        assertFalse(dues.first().handles!!.isEmpty)
    }

    @Test
    fun priceTextAndSchedules() {
        assertNull(FeeText.price(null))
        assertEquals(tr("免费"), FeeText.price(0.0))
        assertEquals("12.50", FeeText.plain(12.5))
        assertEquals("$12", FeeText.text(12.0))
        assertTrue(GroupSchedule.areValid(listOf(GroupSchedule("a", 4, 1140, 1320, 12, price = 0.0))))
        assertFalse(GroupSchedule.areValid(listOf(GroupSchedule("a", 4, 1140, 1320, 12, price = 1001.0))))
        // 发给服务器：没写价格是 null（服务器当成“不写”），写了就是数字
        val sent = GroupsApi.serverSchedules(listOf(GroupSchedule("a", 4, 1140, 1320, 12), GroupSchedule("b", 7, 840, 1020, 16, price = 15.0)))
        assertTrue(sent[0].containsKey("price"))
        assertNull(sent[0]["price"])
        assertEquals(15.0, sent[1]["price"])
    }

    @Test
    fun exportsCsvInVenueTime() {
        val rows = listOf(
            LedgerRow(Instant.parse("2026-11-19T03:00:00Z"), "America/Los_Angeles", "LABC, El Monte", "Amy", false, 12.0, true, Instant.parse("2026-11-19T05:00:00Z"), true),
            LedgerRow(Instant.parse("2026-11-19T03:00:00Z"), "America/Los_Angeles", "LABC, El Monte", "Tony \"T\"", true, 12.0, false, null, false),
        )
        val csv = LedgerExport.csv(rows, listOf("Date", "Time", "Court", "Player", "Guest", "Amount", "Paid", "Marked by them"), "Guest", "Self", "Exempt")
        val lines = csv.removePrefix(Char(0xFEFF).toString()).split("\r\n")
        assertEquals("Date,Time,Court,Player,Guest,Amount,Paid,Marked by them", lines[0])
        assertEquals("2026-11-18,19:00,\"LABC, El Monte\",Amy,,12,2026-11-18,Self", lines[1])
        assertEquals("2026-11-18,19:00,\"LABC, El Monte\",\"Tony \"\"T\"\"\",Guest,12,Exempt,", lines[2])
    }
}
