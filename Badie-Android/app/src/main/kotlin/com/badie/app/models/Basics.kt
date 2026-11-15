package com.badie.app.models

import com.badie.app.design.Sym
import com.badie.app.design.SymbolId
import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

// MARK: - 稳定哈希（跨启动、跨平台一致，用于取色等；和 iPhone、网站同一个算法）

val String.stableHash: Int
    get() {
        var hash = 5381UL
        for (byte in encodeToByteArray()) hash = hash * 33UL + byte.toUByte().toULong()
        return (hash and 0x7FFF_FFFFUL).toInt()
    }

// MARK: - 高水平认证

/**
 * 7 级起只凭能查到的证据认证，问卷和球友评价都到不了。
 * rawValue 和名字不一样，是存下来的值，不能改。
 */
enum class VerificationStatus(val rawValue: String) {
    Unverified("unverified"),
    /** 赛事成绩：tournamentsoftware.com 上公开的签表和成绩 */
    Tournament("regionalChampion"),
    /** 全国排名（USAB）或运动员技术等级证书 */
    National("nationalChampion"),
    /** BWF 世界排名 / 国际赛赛果（bwfbadminton.com 球员页） */
    Bwf("bwfPlayer");

    /** 这类证据最多能认证到哪一档 */
    val maxTier: SkillTier
        get() = when (this) {
            Unverified -> unverifiedMaxTier
            Tournament -> SkillTier(8)
            National -> SkillTier(8, SkillTier.Modifier.Plus)
            Bwf -> SkillTier(9, SkillTier.Modifier.Plus)
        }

    /** 这类证据最低从哪一档起认证 */
    val minTier: SkillTier
        get() = when (this) {
            Unverified -> SkillTier(1, SkillTier.Modifier.Minus)
            Tournament, National -> SkillTier(7, SkillTier.Modifier.Minus)
            Bwf -> SkillTier(9, SkillTier.Modifier.Minus)
        }

    val title: String
        get() = when (this) {
            Unverified -> tr("未认证")
            Tournament -> tr("赛事成绩")
            National -> tr("全国排名 / 运动员等级证书")
            Bwf -> tr("BWF 世界排名")
        }

    val badgeText: String?
        get() = when (this) {
            Unverified -> null
            Tournament -> tr("赛果认证")
            National -> tr("等级认证")
            Bwf -> tr("BWF 认证")
        }

    companion object {
        /** 没有认证时最高显示的档位：问卷最高 6+，球友评价最多推到 7− */
        val unverifiedMaxTier = SkillTier(7, SkillTier.Modifier.Minus)

        fun of(rawValue: String?): VerificationStatus = entries.firstOrNull { it.rawValue == rawValue } ?: Unverified

        /** 服务器的写法：tournament / national / bwf；别的都不算认证 */
        fun ofServer(value: String?): VerificationStatus? = when (value) {
            "tournament" -> Tournament
            "national" -> National
            "bwf" -> Bwf
            else -> null
        }
    }
}

/**
 * 定级用的性别：羽毛球男女的等级分开算（女子 4 级是女生里的强手），男女同场时女子等级按低 1.5 级换算。
 * 只用来定级和匹配，不代表性别认同。以前的数据可能是 Unspecified（没选）
 */
enum class Gender(val rawValue: String) {
    Unspecified("unspecified"), Male("male"), Female("female");

    /** 发给服务器的值（没选 = null） */
    val serverJSON: JsonElement get() = if (this == Unspecified) JsonNull else JsonPrimitive(rawValue)

    /** “只限女生 / 只限男生” */
    val onlyLabel: String
        get() = when (this) {
            Female -> tr("只限女生")
            Male -> tr("只限男生")
            Unspecified -> tr("不限")
        }

    /** 排行榜分男女；没填的算男子榜（和服务器一致） */
    val board: Gender get() = if (this == Female) Female else Male

    val boardLabel: String get() = if (this == Female) tr("女子榜") else tr("男子榜")

    /** 资料页：这个等级是男子还是女子的 */
    val ladderLabel: String?
        get() = when (this) {
            Female -> tr("女子等级")
            Male -> tr("男子等级")
            Unspecified -> null
        }

    val label: String
        get() = when (this) {
            Unspecified -> tr("不透露")
            Male -> tr("男")
            Female -> tr("女")
        }

    companion object {
        /** 注册、设置里能选的 */
        val choices = listOf(Male, Female)
        /** 男女同场时，女子等级换算到男子等级要减的级数 */
        const val WOMEN_OFFSET = 1.5

        fun ofServer(value: String?): Gender = entries.firstOrNull { it.rawValue == value } ?: Unspecified
    }
}

// MARK: - 单打、双打

/** rawValue 是存下来的值，不能改；显示用 title */
enum class GameMode(val rawValue: String, val versusText: String, val icon: SymbolId, val requiredPlayers: Int) {
    Singles("单打", "1 vs 1", Sym.personFill, 2),
    Doubles("双打", "2 vs 2", Sym.person2Fill, 4);

    val title: String
        get() = when (this) {
            Singles -> tr("单打")
            Doubles -> tr("双打")
        }

    val serverValue: String get() = if (this == Singles) "singles" else "doubles"

    companion object {
        fun ofServer(value: String): GameMode = if (value == "singles") Singles else Doubles
    }
}

// MARK: - 谁可以向我发起挑战

enum class ChallengePolicy(val rawValue: String) {
    Everyone("everyone"), SimilarLevel("similarLevel"), Friends("friends"), Nobody("nobody");

    val title: String
        get() = when (this) {
            Everyone -> tr("所有人")
            SimilarLevel -> tr("水平相近的人")
            Friends -> tr("仅球友")
            Nobody -> tr("不接受")
        }

    /** 服务器的写法：similar 对应“水平相近” */
    val serverValue: String get() = if (this == SimilarLevel) "similar" else rawValue

    val detail: String
        get() = when (this) {
            Everyone -> tr("任何同一国家/地区的球友都能向你发起挑战")
            SimilarLevel -> tr("只接受和你相差 1 级以内的挑战")
            Friends -> tr("只有加了球友的人能挑战你")
            Nobody -> tr("别人看不到“发起挑战”")
        }

    companion object {
        fun ofServer(value: String): ChallengePolicy =
            if (value == "similar") SimilarLevel else entries.firstOrNull { it.rawValue == value } ?: SimilarLevel
    }
}

// MARK: - 卡片背景的颜色

enum class CardColor(val rawValue: String) {
    Lime("lime"), Lavender("lavender"), Peach("peach"), Sky("sky"), Pink("pink"), Mint("mint"), Butter("butter"), Ink("ink");

    val displayName: String
        get() = when (this) {
            Lime -> tr("柠檬绿")
            Lavender -> tr("淡紫")
            Peach -> tr("蜜桃")
            Sky -> tr("天蓝")
            Pink -> tr("粉")
            Mint -> tr("薄荷")
            Butter -> tr("奶黄")
            Ink -> tr("墨黑")
        }

    companion object {
        /** 没选过的人：按用户 ID 给一个浅色（不给墨黑）。iPhone 和网站用同样的算法 */
        fun default(userId: String): CardColor {
            val light = entries.filter { it != Ink }
            return light[userId.stableHash % light.size]
        }

        fun of(rawValue: String?): CardColor? = entries.firstOrNull { it.rawValue == rawValue }
    }
}
