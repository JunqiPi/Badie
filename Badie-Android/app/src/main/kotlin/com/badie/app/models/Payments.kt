package com.badie.app.models

import android.net.Uri
import com.badie.app.l10n.L10n.tr
import com.badie.app.remote.InstantSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.Locale
import kotlin.math.roundToLong

// MARK: - 收款（球群的价格、你还没付、收款记录）
// 对应 iPhone 的 Models/ClubNight.swift 里收款的那几样。钱不经过 Badie：只给 Venmo / Cash App / PayPal 链接，Zelle 复制

/** 收款方式（“我的 → 收款方式”）：都可以不填 */
@Serializable
data class PaymentHandles(
    val venmo: String? = null,
    val cashapp: String? = null,
    val paypal: String? = null,
    val zelle: String? = null,
) {
    val isEmpty: Boolean get() = listOf(venmo, cashapp, paypal, zelle).all { it.isNullOrEmpty() }
}

object FeeText {
    /** $12、$12.50（只有美元） */
    fun text(amount: Double): String = "$" + plain(amount)

    /** 12、12.50：链接里用 */
    fun plain(amount: Double): String {
        val cents = (amount * 100).roundToLong()
        if (cents % 100 == 0L) return (cents / 100).toString()
        return String.format(Locale.ROOT, "%d.%02d", cents / 100, cents % 100)
    }

    /** 每场的价格：0 写“免费”，null 不写 */
    fun price(price: Double?): String? = when (price) {
        null -> null
        0.0 -> tr("免费")
        else -> tr("每人 %@", text(price))
    }
}

object PayLinks {
    fun venmo(name: String, amount: Double?, note: String): Uri {
        val builder = Uri.Builder().scheme("https").authority("venmo.com").appendPath(name).appendQueryParameter("txn", "pay")
        amount?.let { builder.appendQueryParameter("amount", FeeText.plain(it)) }
        return builder.appendQueryParameter("note", note).build()
    }

    fun cashApp(tag: String, amount: Double?): Uri =
        Uri.parse("https://cash.app/$" + Uri.encode(tag) + (amount?.let { "/" + FeeText.plain(it) } ?: ""))

    fun payPal(name: String, amount: Double?): Uri =
        Uri.parse("https://paypal.me/" + Uri.encode(name) + (amount?.let { "/" + FeeText.plain(it) + "USD" } ?: ""))

    /** 公开看板：/live/<码>/ */
    fun board(code: String): String = "https://badie.rsvp/live/$code/"
}

/** 我还没付的一场（my_dues）：开过的、写了金额的场次，60 天内 */
@Serializable
data class MyDue(
    val sessionId: String,
    val groupId: String,
    val group: String,
    @Serializable(InstantSerializer::class) val startsAt: Instant,
    @Serializable(InstantSerializer::class) val endsAt: Instant,
    val tz: String? = null,
    val amount: Double,
    val to: String,
    val toId: String,
    val handles: PaymentHandles? = null,
)

/** 收款记录（group_ledger，只有组织者）：开过的场次（新的在前），第一页还有谁还欠着 */
@Serializable
data class GroupLedger(val sessions: List<Session>, val owed: List<Owed>? = null) {
    @Serializable
    data class Session(
        val id: String,
        @Serializable(InstantSerializer::class) val startsAt: Instant,
        @Serializable(InstantSerializer::class) val endsAt: Instant,
        val venue: String,
        val tz: String? = null,
        val amount: Double? = null,
        val payee: String? = null,
        /** 要付几人、付了几人 */
        val owes: Int,
        val paid: Int,
    )

    /** 谁还欠着：注册用户按人、访客按名字合起来；signups 是那几行报名 */
    @Serializable
    data class Owed(
        @SerialName("id") val userId: String? = null,
        val name: String,
        val guest: Boolean,
        val sessions: Int,
        val amount: Double,
        val signups: List<String>,
    ) {
        val key: String get() = userId ?: ("guest:" + name.lowercase(Locale.ROOT))
    }

    companion object {
        /** 一页几场；少于这个数就是翻到头了 */
        const val PAGE_SIZE = 20
    }
}

/** 导出成表格的一行（group_ledger_rows） */
@Serializable
data class LedgerRow(
    @Serializable(InstantSerializer::class) val startsAt: Instant,
    val tz: String? = null,
    val venue: String,
    val name: String,
    val guest: Boolean,
    val amount: Double? = null,
    val owes: Boolean,
    @Serializable(InstantSerializer::class) val paidAt: Instant? = null,
    val paidSelf: Boolean,
)

/** 某一场的收款（night_pay，只有组织者） */
@Serializable
data class NightPay(
    val amount: Double? = null,
    val amountSet: Boolean? = null,
    val payee: String? = null,
    val payeeIsMe: Boolean? = null,
    val hasHandles: Boolean? = null,
    @Serializable(InstantSerializer::class) val remindedAt: Instant? = null,
    val canRemind: Boolean? = null,
    val people: List<Person>,
) {
    @Serializable
    data class Person(
        val id: String,
        val name: String,
        val guest: Boolean,
        val status: String? = null,
        /** 访客留了邮箱（能收提醒邮件） */
        val email: Boolean? = null,
        val owes: Boolean,
        val paid: Boolean,
        val paidSelf: Boolean? = null,
    )

    val owing: List<Person> get() = people.filter { it.owes }
    val unpaid: List<Person> get() = owing.filter { !it.paid }
    val paid: List<Person> get() = people.filter { it.paid }
    /** 不用付的（报了名没来、组织者点了不用付） */
    val exempt: List<Person> get() = people.filter { !it.owes && !it.paid }
}

/** 某一场的时间（night_state 里只用这几项） */
@Serializable
data class SessionTimes(
    val group: String,
    val venue: String,
    val tz: String? = null,
    @Serializable(InstantSerializer::class) val startsAt: Instant,
    @Serializable(InstantSerializer::class) val endsAt: Instant,
    val role: String,
)
