package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import java.util.Locale

// MARK: - 技能等级（9 级，每级再分 −/本级/+，共 27 档，见 SkillTier）
//
// 1–2 级看基本动作；3 技术会不会 → 4 主动球好不好 → 5 被动球能否摆脱 → 6 俱乐部里的位置。
// 问卷最高 6+，球友评价最多推到 7−；7 州级、8 国家级、9 国际级只凭证据认证。
// 文字和 iPhone 的 Models/User.swift 一字不差（文字表里的 key）。

object SkillLevel {
    val range = 1..9
    /** 问卷能给到的最高级（俱乐部高手） */
    const val MAX_SELF_SELECTABLE = 6

    fun name(level: Int): String = when (level) {
        1 -> tr("萌新")
        2 -> tr("入门")
        3 -> tr("初级")
        4 -> tr("中级")
        5 -> tr("中高级")
        6 -> tr("俱乐部高手")
        7 -> tr("州级")
        8 -> tr("国家级")
        9 -> tr("国际级")
        else -> tr("初级")
    }

    /** 一句话概括（列表、徽章说明） */
    fun descriptor(level: Int): String = anchors(level).firstOrNull() ?: ""

    /** 可观察的行为锚点：对照这些动作判断自己在哪一级 */
    fun anchors(level: Int): List<String> = when (level) {
        1 -> listOf(tr("对拉不到 5 拍"), tr("高远球到不了中场"))
        2 -> listOf(tr("发球基本能进区"), tr("慢速对拉 5–10 拍"), tr("走着够球，还没有步法"))
        3 -> listOf(tr("学技术的阶段：发球、正反手高远、吊、杀、搓放网、挑球、接杀逐项学会"), tr("质量时好时坏，对拉十几拍就容易断"), tr("双打知道攻前后、守左右"))
        4 -> listOf(tr("主动球（舒服位置）全部打得不错，包括反手不被动时能回到对方中后场"), tr("双打会攻守轮转"), tr("但被动球、极限球基本做不到，一被压就丢分"))
        5 -> listOf(tr("被动球、极限球有机会摆脱：被压到底线、调到死角也能过渡出来"), tr("技术特点开始明显：有自己的得分手段和打法"), tr("战术开始明显，会用落点和节奏调动对手"))
        6 -> listOf(tr("俱乐部里的佼佼者，日常局很少输"), tr("杀、吊、网前、防守没有明显短板"), tr("会用假动作和节奏变化组织进攻"))
        7 -> listOf(tr("州级水平：州 / 地区公开赛最高组能打进 8 强"), tr("中国：二级运动员（省级比赛前八）"), tr("需要上传证据审核"))
        8 -> listOf(tr("USAB 认证赛最高组正赛能赢球，或有全国排名"), tr("或一级运动员、运动健将"), tr("需要上传证据审核"))
        9 -> listOf(tr("bwfbadminton.com 能查到本人的世界排名或国际赛赢球记录"), tr("只有 BWF ID 不够（老将赛也要 BWF ID）"), tr("需要上传证据审核"))
        else -> emptyList()
    }

    /** 每级各技术分项的标准（分项名 to 标准） */
    fun dimensionNotes(level: Int): List<Pair<String, String>> = when (level) {
        1 -> listOf(tr("握拍") to tr("苍蝇拍式握法"), tr("意识") to tr("知道要把球打到对方难接的地方，但多数时候还做不到"))
        2 -> listOf(tr("握拍") to tr("正反手握拍基本正确，但转换不顺"),
            tr("发球") to tr("会发正手高远和反手网前，质量不高"),
            tr("网前") to tr("基本是轻放过去，时高时远，常不过网"),
            tr("正手后场") to tr("挥拍对了，但发力、时机、击球点还不对，多靠挥手臂"),
            tr("反手后场") to tr("基本不会，只能绕头打或者放弃"),
            tr("进攻") to tr("杀球多半下网、出界"))
        3 -> listOf(tr("握拍、发球") to tr("基本没问题"),
            tr("步法") to tr("能区分垫步、跨步，全场六个点能走到但不流畅"),
            tr("发力") to tr("能区分手臂和手腕发力，对内旋、外旋有基本概念"),
            tr("正手后场") to tr("高远能底线到底线但球速慢；吊、杀质量有限"),
            tr("反手后场") to tr("能正确挥拍但常出错，回球只到中场或略偏后"),
            tr("网前") to tr("放网基本能控制，搓球、勾对角刚开始用，失误多"))
        4 -> listOf(tr("步法") to tr("全场步法正确并能用在打球中，但启动和移动速度不够"),
            tr("发力") to tr("能用上手腕和内外旋，但力量有限"),
            tr("正手后场") to tr("拉、吊、杀都能轻松完成，球速一般，落点凭感觉"),
            tr("反手后场") to tr("能回到对方中后场，但不能底线到底线；反手吊不稳"),
            tr("网前") to tr("挑球能到底线，正反手搓球正确，勾对角常用但质量一般"),
            tr("进攻") to tr("能组织进攻，但速度和角度一般，很难一拍致命"),
            tr("防守") to tr("只能挡直线网前或挑高，不能变线（被动球做不到）"),
            tr("双打") to tr("发接发、移动补位、封网有基本意识"))
        5 -> listOf(tr("步法") to tr("全场多点步法轻松，启动和移动速度中上"),
            tr("发力") to tr("前臂内外旋和手腕发力熟练，开始体会手指发力"),
            tr("后场") to tr("平高、高远、各种吊杀熟练，落点基本到位；反手直线斜线吊都会，后场回后场轻松"),
            tr("网前") to tr("挑、搓熟练，开始会展搓和推球"),
            tr("中场") to tr("平抽挡比较好"),
            tr("进攻") to tr("直线、斜线进攻规范，力量速度中上，有一定威胁"),
            tr("防守") to tr("防守熟练，回球基本到位（被动球多数能摆脱）"))
        6 -> listOf(tr("步法") to tr("像本能一样自然，全场没有盲点"),
            tr("发力") to tr("手指发力熟练：网前精细控制、杀球额外爆发都靠它"),
            tr("动作一致性") to tr("拉吊杀动作一致，对手很难提前判断"),
            tr("反手") to tr("底线到底线轻松，反手劈吊熟练，机会好时反手杀有威力"),
            tr("网前") to tr("搓、勾、推、扑都熟练并用在实战里"),
            tr("中后场") to tr("快速平抽挡；被动低位也能把球抽到底线"),
            tr("进攻") to tr("杀球有暴击音，按对方站位用重杀、劈杀、点杀"),
            tr("防守") to tr("防住不是绝对机会的杀球并控制落点，对方杀得一般时能反抽"),
            tr("战术") to tr("单打主动控制、找弱点；双打抢网、保持主动，找配合盲区"))
        7 -> listOf(tr("技术") to tr("没有明显缺陷，而且至少有一两项绝活：杀球凌厉、防守杀不死、假动作逼真或网前炉火纯青"),
            tr("战术") to tr("单双打战术熟练，但限制与反限制的对抗中，关键时刻还不够冷静"),
            tr("稳定性") to tr("在业余里很高，和专业选手比失误还多"),
            tr("自测参考") to tr("和全国性业余赛的冠军对打，21 分制输分不超过 10 分"))
        8 -> listOf(tr("技术") to tr("任何单项技术都不是问题"),
            tr("战术") to tr("所有战术都能熟练运用，遇到战术大师时应变还不够"),
            tr("稳定性") to tr("业余球友看来稳得可怕，和顶尖高手只差毫厘"),
            tr("背景") to tr("多为前省队、在全国比赛有成绩"))
        9 -> listOf(tr("背景") to tr("国际赛选手、前国家队"),
            tr("技战术") to tr("和更顶尖选手的差距主要在体能和手感"))
        else -> emptyList()
    }

    /** 大致对应的美国赛事组别（各赛事分组不同，仅供参考）。只对美国地区的用户显示（其他国家没有这套组别） */
    fun usFlight(level: Int, region: String? = Locale.getDefault().country): String? = if (region != "US") null else when (level) {
        3 -> tr("E 组")
        4 -> tr("D 组")
        5 -> tr("C 组")
        6 -> tr("B / A 组")
        7 -> tr("州 / 地区公开赛最高组")
        8 -> tr("Open 组 / 全国排名")
        9 -> tr("BWF 国际赛")
        else -> null
    }

    /** 球龄（弱参考：练得多的人进步快，不能只看年限） */
    fun typicalExperience(level: Int): String = when (level) {
        1 -> tr("通常不到 3 个月")
        2 -> tr("通常不到 1 年")
        3 -> tr("通常 1–2 年")
        4 -> tr("通常 2–4 年")
        5 -> tr("通常 3–6 年")
        6 -> tr("通常 5 年以上且受过训练")
        7 -> tr("体校 / 青训出身")
        8 -> tr("体校 / 省队出身")
        else -> tr("职业 / 国家队背景")
    }

    /** 每一档的具体标准 */
    fun tierCriteria(tier: SkillTier): List<String> = when (tier.level to tier.modifier) {
        1 to SkillTier.Modifier.Minus -> listOf(tr("正手发球 10 个里 ≤3 个进区"))
        1 to SkillTier.Modifier.Base -> listOf(tr("正手发球 10 个里 4–6 个进区"))
        1 to SkillTier.Modifier.Plus -> listOf(tr("正手发球 ≥7 个进区，慢速对拉 ≥5 拍"))
        2 to SkillTier.Modifier.Minus -> listOf(tr("中后场正手高远 10 个里 1–2 个过后场第一条线"))
        2 to SkillTier.Modifier.Base -> listOf(tr("高远 10 个里 3–4 个到后场，慢速对拉 5–10 拍"))
        2 to SkillTier.Modifier.Plus -> listOf(tr("高远 10 个里 ≥5 个到后场"))
        3 to SkillTier.Modifier.Minus -> listOf(tr("技术学了大半，还有一两项不会（常见是反手、发力）"))
        3 to SkillTier.Modifier.Base -> listOf(tr("全部技术都会做（所有分项到 3 级），但质量一般、时好时坏"))
        3 to SkillTier.Modifier.Plus -> listOf(tr("全部技术都会，一两项打得不错（到 4 级），但稳定性不足"))
        4 to SkillTier.Modifier.Minus -> listOf(tr("多数分项到 4 级，个别还在 3 级；实战失误还多"))
        4 to SkillTier.Modifier.Base -> listOf(tr("主动球全部不错（所有分项到 4 级，包括反手），双打有基本意识；但被动球、极限球做不到"))
        4 to SkillTier.Modifier.Plus -> listOf(tr("主动球全部不错，一两项精通（到 5 级），稳定性略有提升；被动球仍是短板"))
        5 to SkillTier.Modifier.Minus -> listOf(tr("被动球、极限球有时能过渡出来：回到对方后场或网前，让自己回位"))
        5 to SkillTier.Modifier.Base -> listOf(tr("被动球多数能摆脱；技术特点和战术开始明显（有自己的得分手段，会用落点和节奏调动对手）"))
        5 to SkillTier.Modifier.Plus -> listOf(tr("战术和技巧明显结合：用落点、节奏、假动作组织进攻，会随对手调整"))
        6 to SkillTier.Modifier.Minus -> listOf(tr("和俱乐部里最强的几个人互有胜负；多数分项到 5 级，多拍很稳"))
        6 to SkillTier.Modifier.Base -> listOf(tr("俱乐部准霸主：日常局很少输，常有人请教；有一两项到 6 级的绝活"))
        6 to SkillTier.Modifier.Plus -> listOf(tr("俱乐部霸主：俱乐部对抗的主力，开始打业余 / 半专业比赛"))
        7 to SkillTier.Modifier.Minus -> listOf(tr("州 / 地区赛次高组冠军，或最高组正赛赢过 1 场"), tr("或三级运动员（2025 新标准）、旧二级"))
        7 to SkillTier.Modifier.Base -> listOf(tr("州 / 地区公开赛最高组（Open / A）8 强"), tr("或二级运动员（2025 新标准）"))
        7 to SkillTier.Modifier.Plus -> listOf(tr("州 / 地区公开赛最高组 4 强或冠军"))
        8 to SkillTier.Modifier.Minus -> listOf(tr("USAB 认证赛最高组（Open）正赛赢过 1 场，进入 USAB 排名表"), tr("或 2025 年前的一级证书"))
        8 to SkillTier.Modifier.Base -> listOf(tr("USAB 全国排名有正式名次，或认证赛最高组 8 强"), tr("或一级运动员"))
        8 to SkillTier.Modifier.Plus -> listOf(tr("USAB 任一项目前 5，或全国成年锦标赛 4 强"), tr("或运动健将"))
        9 to SkillTier.Modifier.Minus -> listOf(tr("BWF 世界排名任一项目前 500"), tr("或单站 ≥1,370 积分：International Series 8 强，或 IC / Super 100 正赛赢 1 场"))
        9 to SkillTier.Modifier.Base -> listOf(tr("BWF 世界排名前 100"), tr("或 Super 300 及以上赛事正赛赢过 1 场"))
        9 to SkillTier.Modifier.Plus -> listOf(tr("BWF 世界排名前 20"), tr("或奥运会 / 世锦赛 8 强、Super 750 及以上 4 强"))
        else -> listOf(tier.modifier.meaning)
    }

    /** 每类证据能认证的范围（认证页用） */
    fun evidenceSummary(kind: VerificationStatus): String = when (kind) {
        VerificationStatus.Unverified -> ""
        VerificationStatus.Tournament -> tr("tournamentsoftware.com 上公开的签表和成绩（签位 ≥8，7 起 ≥16）：次高组冠军或最高组正赛赢球 → 7−，州 / 地区公开赛最高组 8 强 → 7，4 强 → 7+，USAB 认证赛最高组正赛赢球 → 8−，8 强 → 8")
        VerificationStatus.National -> tr("USAB 全国排名，或运动员技术等级电子证书：三级 → 7−，二级 → 7，一级 → 8，运动健将 → 8+（2025 年前的证书低一档）")
        VerificationStatus.Bwf -> tr("bwfbadminton.com 上本人的球员页，看近 24 个月的世界排名和赛果。只有 BWF ID 不够")
    }

    fun displayText(level: Int): String = "Lv.$level ${name(level)}"

    fun clamp(level: Int): Int = level.coerceIn(range.first, range.last)
}
