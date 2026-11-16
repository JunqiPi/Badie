package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 项目：男单 / 女单 / 男双 / 女双（只和自己同性别的人打）、混双（两男两女，每边一男一女）。
 * 没有项目（null）= 不限，男女都可以，女子等级按低 1.5 级换算。
 * 混双里男生和男生比、女生和女生比，所以等级不换算，各按各的
 */
@Serializable
enum class PlayEvent(val rawValue: String) {
    @SerialName("men") Men("men"),
    @SerialName("women") Women("women"),
    @SerialName("mixed") Mixed("mixed");

    /** 发给服务器的性别限制（混双没有） */
    val gender: Gender?
        get() = when (this) {
            Men -> Gender.Male
            Women -> Gender.Female
            Mixed -> null
        }

    fun title(mode: GameMode): String = when (this) {
        Men -> if (mode == GameMode.Singles) tr("男单") else tr("男双")
        Women -> if (mode == GameMode.Singles) tr("女单") else tr("女双")
        Mixed -> tr("混双")
    }

    companion object {
        /**
         * 能选的项目（含不限 = null）：只能选自己的性别；混双只有双打，也要先选性别。
         * 直接约某个人（partner 是对方的性别）时按两个人的性别定：单打同性就是男单/女单、异性就是不限；
         * 双打两人同性可以男双/女双或不限，异性可以混双或不限
         */
        fun choices(mode: GameMode, gender: Gender, partner: Gender? = null): List<PlayEvent?> {
            if (gender == Gender.Unspecified) return listOf(null)
            val own = if (gender == Gender.Female) Women else Men
            if (partner == null || partner == Gender.Unspecified) {
                return if (mode == GameMode.Doubles) listOf(null, own, Mixed) else listOf(null, own)
            }
            val same = partner == gender
            return when (mode) {
                GameMode.Singles -> if (same) listOf(own) else listOf(null)
                GameMode.Doubles -> if (same) listOf(null, own) else listOf(null, Mixed)
            }
        }

        /** 服务器存的是性别限制和是否混双 */
        fun ofServer(gender: Gender?, mixed: Boolean): PlayEvent? {
            if (mixed) return Mixed
            return when (gender) {
                Gender.Male -> Men
                Gender.Female -> Women
                else -> null
            }
        }

        /** 选项下面的说明 */
        fun caption(event: PlayEvent?): String = when (event) {
            Mixed -> tr("每边一男一女。男生和男生比、女生和女生比，所以等级不换算。")
            Women -> tr("只有女生能加入，按女子等级算。")
            Men -> tr("只有男生能加入。")
            null -> tr("男女一起打时，女子等级按低约 1.5 级来算，这样比赛势均力敌。")
        }
    }
}

/** 不限显示单打 / 双打 */
fun PlayEvent?.title(mode: GameMode): String = this?.title(mode) ?: mode.title
