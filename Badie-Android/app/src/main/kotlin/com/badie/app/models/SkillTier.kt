package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/** 四舍五入，正好一半时往远离 0 的方向（和 iPhone 的 rounded() 一样；Kotlin 自带的 round 是往偶数靠） */
fun roundHalfAway(value: Double): Double = if (value >= 0) floor(value + 0.5) else ceil(value - 0.5)

// MARK: - 细分档位：每级分 −、本级、+ 三档（1− … 9+，共 27 档）
//
// 水平用连续分值记录，显示时取最近的三分之一档：4− = 3.67，4 = 4.00，4+ = 4.33。

class SkillTier private constructor(val level: Int, val modifier: Modifier) : Comparable<SkillTier> {
    enum class Modifier(val rawValue: Int, val symbol: String) {
        Minus(-1, "−"),
        Base(0, ""),
        Plus(1, "+");

        /** 1–7 级里 −/本级/+ 的通用含义 */
        val meaning: String
            get() = when (this) {
                Minus -> tr("刚达到这一级，部分动作还不稳定")
                Base -> tr("这一级的动作都能稳定做到")
                Plus -> tr("这一级很稳定，已经有下一级的部分能力")
            }
    }

    /** 第几档（0 = 1−，26 = 9+） */
    val index: Int get() = (level - 1) * 3 + modifier.rawValue + 1

    /** 连续分值：4− = 3.67，4 = 4.00，4+ = 4.33 */
    val rating: Double get() = level + modifier.rawValue / 3.0

    /** “4+” */
    val code: String get() = "$level${modifier.symbol}"

    /** “Lv.4+” */
    val text: String get() = "Lv.$code"

    /** 档位名称：1–5 级用本级名称；6 级起每档差距大，单独命名 */
    val name: String
        get() = when (level to modifier) {
            6 to Modifier.Minus -> tr("崭露头角")
            6 to Modifier.Plus -> tr("俱乐部顶尖")
            7 to Modifier.Minus -> tr("准州级")
            7 to Modifier.Base -> tr("州级选手")
            7 to Modifier.Plus -> tr("州级精英")
            8 to Modifier.Minus -> tr("准国家级")
            8 to Modifier.Base -> tr("国家级")
            8 to Modifier.Plus -> tr("国家顶尖")
            9 to Modifier.Minus -> tr("国际选手")
            9 to Modifier.Base -> tr("国际职业")
            9 to Modifier.Plus -> tr("世界顶尖")
            else -> SkillLevel.name(level)
        }

    /** “Lv.4+ 中级”“Lv.9+ 世界顶尖” */
    val displayText: String get() = "$text $name"

    /** 读屏：“4 级加” */
    val spokenText: String
        get() = when (modifier) {
            Modifier.Minus -> tr("%lld 级减", level)
            Modifier.Base -> tr("%lld 级", level)
            Modifier.Plus -> tr("%lld 级加", level)
        }

    fun offset(steps: Int): SkillTier = ofIndex(index + steps)

    /** 差几档（对方 − 我） */
    fun steps(to: SkillTier): Int = to.index - index

    override fun compareTo(other: SkillTier): Int = index.compareTo(other.index)

    override fun equals(other: Any?): Boolean = other is SkillTier && other.index == index

    override fun hashCode(): Int = index

    override fun toString(): String = text

    companion object {
        const val COUNT = 27

        operator fun invoke(level: Int, modifier: Modifier = Modifier.Base): SkillTier = SkillTier(SkillLevel.clamp(level), modifier)

        /** 第几档（0 = 1−，26 = 9+），超出范围的夹在两头 */
        fun ofIndex(index: Int): SkillTier {
            val clamped = index.coerceIn(0, COUNT - 1)
            return SkillTier(clamped / 3 + 1, Modifier.entries.first { it.rawValue == clamped % 3 - 1 })
        }

        /** 由连续分值取最近的一档 */
        fun ofRating(rating: Double): SkillTier = ofIndex(roundHalfAway(rating * 3).toInt() - 2)

        val all: List<SkillTier> = (0 until COUNT).map(::ofIndex)

        /** “7 到 8+”（不用连字符，避免和 − 混在一起） */
        fun rangeText(lower: SkillTier, upper: SkillTier): String =
            if (lower == upper) lower.code else tr("%@ 到 %@", lower.code, upper.code)

        /** “同水平”“高 1 档”“低 1 级”“高 1 级 1 档” */
        fun differenceText(steps: Int): String {
            if (steps == 0) return tr("同水平")
            val levels = abs(steps) / 3
            val rest = abs(steps) % 3
            return when {
                steps > 0 && levels == 0 -> tr("高 %lld 档", rest)
                steps > 0 && rest == 0 -> tr("高 %lld 级", levels)
                steps > 0 -> tr("高 %lld 级 %lld 档", levels, rest)
                levels == 0 -> tr("低 %lld 档", rest)
                rest == 0 -> tr("低 %lld 级", levels)
                else -> tr("低 %lld 级 %lld 档", levels, rest)
            }
        }
    }
}
