package com.badie.app.backend

import com.badie.app.models.GroupLedger
import com.badie.app.models.LedgerRow
import com.badie.app.models.MyDue
import com.badie.app.models.NightPay
import com.badie.app.models.PaymentHandles
import com.badie.app.models.SessionTimes
import com.badie.app.remote.SupabaseClient
import com.badie.app.remote.json
import kotlinx.serialization.builtins.nullable
import java.time.Instant

// 正式后端：收款（价格、你还没付、收款记录、某一场的收款、收款方式）。
// 对应 iPhone 的 MockBackend+RemoteNight.swift 里收款的那几个（参数和字段照抄）
class PaymentsApi(private val remote: SupabaseClient) {

    // MARK: 我还没付的、收款记录

    /** groupId 为 null 是所有球群 */
    suspend fun myDues(groupId: String? = null): List<MyDue> =
        remote.rpc("my_dues", if (groupId == null) json() else json("p_group" to groupId))

    /** before 为 null 是第一页（带“谁还欠着”）；往前翻传上一页最后一场的开始时间 */
    suspend fun groupLedger(groupId: String, before: Instant? = null): GroupLedger =
        remote.rpc("group_ledger", json("p_group" to groupId, "p_before" to before?.toString(), "p_limit" to GroupLedger.PAGE_SIZE))

    suspend fun groupLedgerRows(groupId: String): List<LedgerRow> = remote.rpc("group_ledger_rows", json("p_group" to groupId))

    /** 一次标几行已付（收款记录里“标成已付”），返回改了几行 */
    suspend fun markSignupsPaid(signupIds: List<String>, paid: Boolean): Int =
        remote.rpc("mark_signups_paid", json("p_signups" to signupIds, "p_paid" to paid))

    // MARK: 某一场

    /** 没权限时为 null */
    suspend fun sessionTimes(sessionId: String): SessionTimes? =
        remote.rpc("night_state", json("p_session" to sessionId), SessionTimes.serializer().nullable)

    suspend fun nightPay(sessionId: String): NightPay = remote.rpc("night_pay", json("p_session" to sessionId))

    /** 每人多少钱（null = 不填，0 = 这一场免费） */
    suspend fun setSessionFee(sessionId: String, amount: Double?) =
        remote.call("set_session_fee", json("p_session" to sessionId, "p_amount" to amount))

    suspend fun markSignupPaid(signupId: String, paid: Boolean) = remote.call("mark_signup_paid", json("p_signup" to signupId, "p_paid" to paid))

    /** true 加回来，false 不用付 */
    suspend fun setSignupOwes(signupId: String, owes: Boolean) = remote.call("set_signup_owes", json("p_signup" to signupId, "p_owes" to owes))

    /** 返回提醒了几个人 */
    suspend fun remindUnpaid(sessionId: String): Int = remote.rpc("remind_unpaid", json("p_session" to sessionId))

    /** 付钱的人自己点“我付了”（false 是改回来） */
    suspend fun iPaid(sessionId: String, paid: Boolean) = remote.call("i_paid", json("p_session" to sessionId, "p_paid" to paid))

    // MARK: 收款方式

    suspend fun myPaymentHandles(): PaymentHandles = remote.rpc("my_payment_handles")

    /** 空字符串 = 不填 */
    suspend fun setPaymentHandles(handles: PaymentHandles) = remote.call(
        "set_payment_handles",
        json(
            "p_venmo" to (handles.venmo ?: ""), "p_cashapp" to (handles.cashapp ?: ""),
            "p_paypal" to (handles.paypal ?: ""), "p_zelle" to (handles.zelle ?: ""),
        ),
    )
}
