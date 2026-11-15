package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import com.badie.app.l10n.ListText
import kotlin.math.ceil
import kotlin.math.floor

// MARK: - 定级问卷：每个选项对应一个等级，自动算出 1− 到 6+
//
// 技术、比赛能力各取平均，但不能比自己最弱的一项高出 1 级以上；两者以弱的为准，强的那边最多再加 2/3 级。
// 5+ 往上看在俱乐部里的位置，6+ 还要有比赛或青训经历。经历给保底。
// iPhone 的 Models/SkillAssessment.swift 和网页的 web/src/app/assessment.ts 是同一套题和算法，三端要算出同样的结果。

class AssessmentOption(
    val id: Int,
    val text: String,
    /** 技术、比赛能力：这个答案对应的等级（可以是 2.5 这样的半级）；经历题：保底分值；俱乐部位置：对应的 6 级档位 */
    val value: Double?,
)

class AssessmentQuestion(val id: String, val kind: Kind, val title: String, val hint: String, val options: List<AssessmentOption>) {
    enum class Kind {
        /** 技术分项 */
        Technique,
        /** 比赛能力：被动球、双打、稳定性、战术 */
        Game,
        /** 在俱乐部里的位置（只看 5+ 往上） */
        Standing,
        /** 比赛 / 训练经历（给保底） */
        Experience,
        /** 最近一年是否常打 */
        Recency,
    }
}

/** 一个技术分项的结果（“反手后场 3−”） */
data class AssessmentDimension(val id: String, val name: String, val rating: Double) {
    /** 按档位显示：2.5 → “3−” */
    val code: String get() = SkillTier.ofRating(maxOf(rating, 1 - 1.0 / 3)).code
}

data class SkillAssessmentResult(
    val tier: SkillTier,
    /** 经历和技术对不上（保底比结果高 2 级以上） */
    val needsCalibration: Boolean,
    /** 最近一年不常打 */
    val isReturning: Boolean,
    /** 选了参加过 A / Open 组：提示申请认证 */
    val suggestsVerification: Boolean,
    /** 卡在哪里（比如“想到 4 级先补短板：反手后场、平抽挡”）；没被卡住时为 null，结果页提示下一档的标准 */
    val limitingGate: String?,
    /** 各技术分项的等级 */
    val dimensions: List<AssessmentDimension> = emptyList(),
    /** 打法（六个维度 + 打法类型）；答案不全时为 null */
    val play: PlayProfile? = null,
    /** “离 5 级还差：反手后场”：下一级和最弱的一项；没有时为 null */
    val nextGap: AssessmentGap? = null,
) {
    val level: Int get() = tier.level

    /** 技术特点：最强的分项（比整体高时才算） */
    val strengths: List<AssessmentDimension>
        get() {
            val top = dimensions.maxOfOrNull { it.rating } ?: return emptyList()
            val low = dimensions.minOf { it.rating }
            return if (top > low) dimensions.filter { it.rating == top } else emptyList()
        }
}

// MARK: - 打法：六个维度 + 七种打法

enum class PlayAxis(val rawValue: String) {
    Attack("attack"), Net("net"), Defense("defense"), Speed("speed"), Footwork("footwork"), Tactics("tactics");

    val title: String
        get() = when (this) {
            Attack -> tr("进攻")
            Net -> tr("网前")
            Defense -> tr("防守")
            Speed -> tr("速度")
            Footwork -> tr("步法")
            Tactics -> tr("战术")
        }
}

enum class PlayStyle(val rawValue: String, /** 卡片画面里重复的大字（装饰，不翻译） */ val ghostWord: String) {
    Cannon("cannon", "SMASH"),
    Net("net", "NET"),
    Wall("wall", "WALL"),
    Quick("quick", "SPRING"),
    Engine("engine", "MOTOR"),
    Captain("captain", "TACTICS"),
    Allround("allround", "ALL-ROUND"),
    /** 新星：问卷结果 1–2 级时不看六项，都是新星 */
    Rookie("rookie", "ROOKIE");

    val title: String
        get() = when (this) {
            Cannon -> tr("杀球重炮手")
            Net -> tr("网前魔术师")
            Wall -> tr("铁壁")
            Quick -> tr("弹簧腿")
            Engine -> tr("小马达")
            Captain -> tr("战术师")
            Allround -> tr("六边形战士")
            Rookie -> tr("新星")
        }

    /** 一句话 */
    val line: String
        get() = when (this) {
            Cannon -> tr("后场一板定输赢。有机会就杀。")
            Net -> tr("一个搓球让对面起高球。")
            Wall -> tr("怎么打都打不死。")
            Quick -> tr("中场越快越舒服。")
            Engine -> tr("满场跑，球球都到位。")
            Captain -> tr("你在调动全场。")
            Allround -> tr("没有短板。")
            Rookie -> tr("刚起步，进步最快的时候。")
        }

    /** 最佳搭档；六边形战士和新星和谁都行（null） */
    val partner: PlayStyle?
        get() = when (this) {
            Cannon -> Net
            Net -> Cannon
            Wall -> Quick
            Quick -> Wall
            Engine -> Captain
            Captain -> Engine
            Allround, Rookie -> null
        }

    val partnerText: String get() = partner?.title ?: tr("谁都行")

    companion object {
        /** 最高的一项是哪个维度 */
        fun of(axis: PlayAxis): PlayStyle = when (axis) {
            PlayAxis.Attack -> Cannon
            PlayAxis.Net -> Net
            PlayAxis.Defense -> Wall
            PlayAxis.Speed -> Quick
            PlayAxis.Footwork -> Engine
            PlayAxis.Tactics -> Captain
        }
    }
}

data class PlayProfile(
    /** 六个维度的等级（可以是 3.5 这样的半级） */
    val axes: Map<PlayAxis, Double>,
    val style: PlayStyle,
    /** 最强一拍：技术题里等级最高的一项 */
    val bestShot: AssessmentDimension?,
) {
    fun value(axis: PlayAxis): Double = axes[axis] ?: 0.0

    /** 卡片上的数字：四舍五入到整级（1–9） */
    fun displayValue(axis: PlayAxis): Int = roundHalfAway(value(axis)).toInt().coerceIn(1, 9)
}

/** 离下一级还差的一项 */
data class AssessmentGap(/** 下一级（整数） */ val level: Int, val dimension: AssessmentDimension)

/** 定级结果的摘要（存到用户资料里） */
data class SkillAssessmentSummary(
    val level: Int,
    val needsCalibration: Boolean,
    val isReturning: Boolean,
    /** 定级时间，毫秒 */
    val assessedAt: Long,
    /** 细分档位分值；为空时按整数等级 */
    val rating: Double? = null,
    /** 问卷答案（题目 ID → 选项序号）：算打法用。服务器上本来就存着（profiles.assessment），没有时不显示打法 */
    val answers: Map<String, Int>? = null,
) {
    /** 打法：有答案时才有 */
    val play: PlayProfile? get() = answers?.let(SkillAssessment::playProfile)

    val tier: SkillTier get() = SkillTier.ofRating(rating ?: level.toDouble())

    fun canRetake(now: Long): Boolean = now - assessedAt >= RETAKE_INTERVAL_MILLIS

    fun nextRetakeDate(): Long = assessedAt + RETAKE_INTERVAL_MILLIS

    companion object {
        /** 多久可以重测一次（避免反复刷等级） */
        const val RETAKE_INTERVAL_MILLIS = 90L * 86_400_000
    }
}

object SkillAssessment {
    /** 问卷能给到的最高档（俱乐部霸主） */
    val maxTier = SkillTier(SkillLevel.MAX_SELF_SELECTABLE, SkillTier.Modifier.Plus)

    private const val THIRD = 1.0 / 3

    /** 跳过定级时暂用的等级（之后在资料页补测） */
    const val PROVISIONAL_LEVEL = 3

    // MARK: Questions

    /** 题目的文字跟着当前语言走，所以每次现取 */
    val questions: List<AssessmentQuestion>
        get() = listOf(
            AssessmentQuestion(
                "clear", AssessmentQuestion.Kind.Technique, tr("正手高远球"), tr("站在后场打高远球："),
                listOf(
                    AssessmentOption(0, tr("到不了中场"), 1.0),
                    AssessmentOption(1, tr("大多落在中场"), 2.0),
                    AssessmentOption(2, tr("能到后场，但到不了底线、球速慢"), 2.5),
                    AssessmentOption(3, tr("打球中能稳定底线到底线"), 3.0),
                    AssessmentOption(4, tr("知道平高球和高远球的区别，知道什么时候打哪种，能控制弧度和落点"), 4.0),
                    AssessmentOption(5, tr("和吊球、杀球动作一致，对手判断不出你打什么"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "smash", AssessmentQuestion.Kind.Technique, tr("正手杀球"), tr("后场有机会时杀球："),
                listOf(
                    AssessmentOption(0, tr("不会杀，或者一杀就下网、出界，经常打杆"), 1.0),
                    AssessmentOption(1, tr("知道怎么往下压，但力量打不透"), 1.5),
                    AssessmentOption(2, tr("能杀下去、有一定球速，但对方不难接"), 2.5),
                    AssessmentOption(3, tr("机会好的时候偶尔能把力量打透，开始有角度、有威胁"), 3.0),
                    AssessmentOption(4, tr("开始懂得重杀、轻杀、点杀的妙用，杀完能跟上网前"), 4.0),
                    AssessmentOption(5, tr("重杀、劈杀、点杀用得轻车熟路，按对方站位选用"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "drop", AssessmentQuestion.Kind.Technique, tr("正手吊球"), tr("会不会吊球？会不会劈吊、滑板？"),
                listOf(
                    AssessmentOption(0, tr("还不会吊"), 0.0),
                    AssessmentOption(1, tr("能吊过网，但常偏高、偏远"), 1.0),
                    AssessmentOption(2, tr("直线、斜线能吊到前发球线附近"), 2.0),
                    AssessmentOption(3, tr("会劈吊或滑板其中一种，但不稳定，角度掌握不好，常高于网带，会被抓"), 3.0),
                    AssessmentOption(4, tr("劈吊、滑板都会，但稳定性不足，球速也不够，偶尔反而陷入被动"), 4.0),
                    AssessmentOption(5, tr("劈吊、滑板都熟练，和高远、杀球动作一致，球速快、过网就落"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "backhand", AssessmentQuestion.Kind.Technique, tr("反手后场"), tr("球到了反手后场："),
                listOf(
                    AssessmentOption(0, tr("只能绕头打，或者放弃"), 1.0),
                    AssessmentOption(1, tr("能用反手打，但只能到中场或中前场；对手一打你的反手你就被动"), 2.0),
                    AssessmentOption(2, tr("不被动时，能从己方中后场回到对方后场"), 3.0),
                    AssessmentOption(3, tr("会反手吊直线、斜线，有一定球速不会被抓；后场回后场的高远球很轻松"), 5.0),
                    AssessmentOption(4, tr("反手高远底线到底线；被动时反手过渡依然非常熟练"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "net", AssessmentQuestion.Kind.Technique, tr("网前搓放"), tr("放网、搓球、勾对角："),
                listOf(
                    AssessmentOption(0, tr("轻放过去，时高时远，常不过网"), 1.0),
                    AssessmentOption(1, tr("放网能贴网，搓球、勾对角刚开始用"), 2.0),
                    AssessmentOption(2, tr("正反手都会搓，勾对角常用但不够贴网"), 3.0),
                    AssessmentOption(3, tr("搓球熟练，会展搓和推后场"), 4.0),
                    AssessmentOption(4, tr("搓、勾、推、扑都熟练，动作一致"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "drive", AssessmentQuestion.Kind.Technique, tr("平抽挡"), tr("中场来了快的平球："),
                listOf(
                    AssessmentOption(0, tr("基本接不住"), 1.0),
                    AssessmentOption(1, tr("能挡回去，但没有速度"), 2.0),
                    AssessmentOption(2, tr("能平抽对攻几拍"), 2.5),
                    AssessmentOption(3, tr("平抽挡比较好，能主动加速"), 4.0),
                    AssessmentOption(4, tr("快速平抽对抗不吃亏，被动低位也能抽到底线"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "footwork", AssessmentQuestion.Kind.Technique, tr("步法"), tr("你在场上的移动："),
                listOf(
                    AssessmentOption(0, tr("走着够球"), 1.0),
                    AssessmentOption(1, tr("会跑去接，但没有固定步法"), 1.5),
                    AssessmentOption(2, tr("会垫步、跨步，六个点能走到但不流畅"), 2.5),
                    AssessmentOption(3, tr("全场步法正确，但启动和移动不够快"), 3.0),
                    AssessmentOption(4, tr("全场步法轻松，启动和移动速度中上"), 4.0),
                    AssessmentOption(5, tr("步法像本能一样，全场没有盲点"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "passive", AssessmentQuestion.Kind.Game, tr("接杀和被动球"), tr("接对方重杀，或被压到底线、调到死角时："),
                listOf(
                    AssessmentOption(0, tr("基本接不到，或者直接失误"), 2.0),
                    AssessmentOption(1, tr("只能挡直线网前或挑高，不能变线，对方很容易得分"), 3.0),
                    AssessmentOption(2, tr("有时能过渡出来：回到对方后场或网前，让自己回位"), 4.0),
                    AssessmentOption(3, tr("防守熟练，回球基本到位，多数能摆脱被动"), 5.0),
                    AssessmentOption(4, tr("能防住不是绝对机会的杀球并控制落点，对方杀得一般时能反抽"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "doubles", AssessmentQuestion.Kind.Game, tr("双打"), tr("打双打时，你对站位和配合的掌握？"),
                listOf(
                    AssessmentOption(0, tr("不清楚该站哪"), 1.5),
                    AssessmentOption(1, tr("知道进攻前后站、防守左右站"), 2.5),
                    AssessmentOption(2, tr("发接发、移动补位、封网都有基本意识"), 3.5),
                    AssessmentOption(3, tr("会主动抢网，后场注意保持进攻"), 4.5),
                    AssessmentOption(4, tr("能找对手的空档和配合盲区"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "stability", AssessmentQuestion.Kind.Game, tr("稳定性"), tr("对拉和实战里，你的失误多不多？"),
                listOf(
                    AssessmentOption(0, tr("对拉不到 5 拍就断"), 1.0),
                    AssessmentOption(1, tr("慢速能对拉 5–10 拍"), 2.0),
                    AssessmentOption(2, tr("能连续对拉十几拍，但实战一快就失误多"), 3.0),
                    AssessmentOption(3, tr("实战失误比以前少了，但关键分还会紧"), 4.0),
                    AssessmentOption(4, tr("多拍相持很稳，很少主动失误"), 5.0),
                    AssessmentOption(5, tr("高强度打到第三局也很稳"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "tactics", AssessmentQuestion.Kind.Game, tr("战术"), tr("比赛时你主要怎么得分？"),
                listOf(
                    AssessmentOption(0, tr("主要是把球打过去，等对方失误"), 2.0),
                    AssessmentOption(1, tr("会找对方的弱点打（比如反手）"), 3.0),
                    AssessmentOption(2, tr("会用落点和节奏调动对手：压后场、吊前场"), 4.0),
                    AssessmentOption(3, tr("战术和技巧结合：用假动作、变线组织连续进攻，随对手调整"), 5.0),
                    AssessmentOption(4, tr("能针对不同对手提前定打法，并在场上执行"), 6.0),
                ),
            ),
            AssessmentQuestion(
                "standing", AssessmentQuestion.Kind.Standing, tr("在俱乐部里的位置"), tr("和你常一起打的俱乐部或固定局比，你大概在什么位置？"),
                listOf(
                    AssessmentOption(0, tr("还在中下游"), null),
                    AssessmentOption(1, tr("中游，和大多数人有来有回"), null),
                    AssessmentOption(2, tr("中上游，能赢大多数人"), null),
                    AssessmentOption(3, tr("崭露头角：和最强的几个人互有胜负"), 6 - THIRD),
                    AssessmentOption(4, tr("准霸主：日常局很少输，常有人找你请教"), 6.0),
                    AssessmentOption(5, tr("霸主：俱乐部对抗的主力，开始打业余 / 半专业比赛"), 6 + THIRD),
                ),
            ),
            AssessmentQuestion(
                "experience", AssessmentQuestion.Kind.Experience, tr("比赛和训练经历"), tr("选最高的一项"),
                listOf(
                    AssessmentOption(0, tr("都没有"), null),
                    AssessmentOption(1, tr("上过 20 节以上的课"), 2.0),
                    AssessmentOption(2, tr("打过 E 组或 D 组比赛"), 3.0),
                    AssessmentOption(3, tr("C / B 组进过前四，或青训 2 年以上"), 5 - THIRD),
                    AssessmentOption(4, tr("参加过 A 组或 Open 组"), 6 - THIRD),
                ),
            ),
            AssessmentQuestion(
                "recency", AssessmentQuestion.Kind.Recency, tr("最近一年"), tr("最近一年，你平均每月打球至少 2 次吗？"),
                listOf(
                    AssessmentOption(0, tr("是，一直在打"), 1.0),
                    AssessmentOption(1, tr("没有，最近打得少（以前打得多）"), 0.0),
                ),
            ),
        )

    fun question(id: String): AssessmentQuestion? = questions.firstOrNull { it.id == id }

    // MARK: Scoring

    /** 按 1/3 级取整（3.4 → 3+） */
    private fun toThirds(rating: Double): Double = roundHalfAway(rating * 3) / 3

    /** 一组题的水平：取平均，但不能比最弱的一项高出 1 级以上（短板限制等级） */
    private fun pillar(levels: List<Double>): Double {
        val weakest = levels.minOrNull() ?: return 1.0
        return minOf(levels.sum() / levels.size, weakest + 1)
    }

    /** 根据答案（题目 ID → 选项序号）计算细分档位；没答完返回 null */
    fun evaluate(answers: Map<String, Int>): SkillAssessmentResult? {
        val questions = questions
        if (!questions.all { answers[it.id] != null }) return null
        fun option(id: String): Int = answers[id] ?: 0
        fun value(question: AssessmentQuestion): Double? = question.options.getOrNull(option(question.id))?.value
        fun scored(kind: AssessmentQuestion.Kind): List<AssessmentDimension> =
            questions.filter { it.kind == kind }.mapNotNull { question ->
                value(question)?.let { AssessmentDimension(question.id, question.title, it) }
            }

        val isReturning = option("recency") == 1
        val suggestsVerification = option("experience") == 4
        val technique = scored(AssessmentQuestion.Kind.Technique)
        val game = scored(AssessmentQuestion.Kind.Game)

        // 0. 完全的新手：高远到不了中场、还没有步法
        if (option("clear") == 0 && option("footwork") == 0) {
            val untouched = option("net") == 0 && option("doubles") == 0
            return SkillAssessmentResult(
                tier = SkillTier(1, if (untouched) SkillTier.Modifier.Minus else SkillTier.Modifier.Base),
                needsCalibration = false, isReturning = isReturning, suggestsVerification = false, limitingGate = null,
                dimensions = technique, play = profile(questions, answers, level = 1),
            )
        }

        // 1. 技术和比赛能力：各自取平均、受最弱一项限制；两者以弱的为准，强的那边最多加 2/3 级
        val pillars = listOf(pillar(technique.map { it.rating }), pillar(game.map { it.rating })).sorted()
        var rating = toThirds(pillars[0] + minOf(2 * THIRD, (pillars[1] - pillars[0]) / 2))

        // 2. 下一档要补什么：最弱的几项（最多 3 项）。3− 的下一档是 3，3 和 3+ 的下一档是 4
        val target = if (rating - floor(rating) > 0.5) ceil(rating).toInt() else floor(rating).toInt() + 1
        // 稳定排序：一样弱的按题目顺序（和网页的 Array.sort 一致）
        val weakest = (technique + game).filter { it.rating < target }.sortedBy { it.rating }.take(3)
        var limitingGate: String? =
            if (weakest.isEmpty()) null else tr("想到 %lld 级先补短板：%@", target, ListText.and(weakest.map { it.name }))
        var nextGap: AssessmentGap? = weakest.firstOrNull()?.let { AssessmentGap(target, it) }

        // 3. 6 级看俱乐部里的位置：没到“崭露头角”最高 5+；6+ 还要有比赛或青训经历
        val standingQuestion = questions.firstOrNull { it.id == "standing" }
        if (rating >= 6 - THIRD - 0.01 && standingQuestion != null) {
            nextGap = null
            val standing = value(standingQuestion)
            if (standing != null) {
                rating = minOf(standing, rating + THIRD)
                limitingGate = null
                if (rating >= 6 + THIRD - 0.01 && option("experience") < 3) {
                    rating = 6.0
                    limitingGate = tr("想到 6+：要有比赛或青训经历")
                }
            } else {
                rating = 5 + THIRD
                limitingGate = tr("想到 6−：要在你常打的俱乐部里排进最强的那几个")
            }
        }

        // 4. 经历保底（回归球友减 1 级）
        var guaranteed = questions.firstOrNull { it.id == "experience" }?.let(::value) ?: 1.0
        if (isReturning) guaranteed -= 1
        val capped = toThirds(minOf(maxOf(rating, guaranteed, 1 - THIRD), maxTier.rating))
        val needsCalibration = guaranteed - rating >= 2 - 0.01

        val tier = minOf(SkillTier.ofRating(capped), maxTier)
        return SkillAssessmentResult(
            tier = tier, needsCalibration = needsCalibration, isReturning = isReturning, suggestsVerification = suggestsVerification,
            limitingGate = if (guaranteed > rating) null else limitingGate, dimensions = technique,
            play = profile(questions, answers, tier.level), nextGap = if (guaranteed > rating) null else nextGap,
        )
    }

    // MARK: 打法

    /** 打法：要答完全部题目（新星要看问卷定出的等级） */
    fun playProfile(answers: Map<String, Int>): PlayProfile? = evaluate(answers)?.play

    /**
     * 六个维度和打法类型，六项只看技术题和比赛能力题的答案。
     * 进攻 = 杀球；网前 = 网前、吊球的平均；防守 = 被动球、稳定性的平均；速度 = 平抽挡；步法 = 步法；战术 = 战术、双打的平均。
     * 问卷定出 1–2 级：新星。否则最高和最低差不超过半级：六边形战士；再否则看最高的一项
     * （一样高时按进攻、网前、防守、速度、步法、战术的顺序）。
     */
    private fun profile(questions: List<AssessmentQuestion>, answers: Map<String, Int>, level: Int): PlayProfile? {
        val levels = HashMap<String, Double>()
        for (question in questions) {
            if (question.kind != AssessmentQuestion.Kind.Technique && question.kind != AssessmentQuestion.Kind.Game) continue
            val value = answers[question.id]?.let { question.options.getOrNull(it) }?.value ?: return null
            levels[question.id] = value
        }
        fun answer(id: String): Double = levels[id] ?: 0.0
        val axes = linkedMapOf(
            PlayAxis.Attack to answer("smash"),
            PlayAxis.Net to (answer("net") + answer("drop")) / 2,
            PlayAxis.Defense to (answer("passive") + answer("stability")) / 2,
            PlayAxis.Speed to answer("drive"),
            PlayAxis.Footwork to answer("footwork"),
            PlayAxis.Tactics to (answer("tactics") + answer("doubles")) / 2,
        )
        val top = axes.values.max()
        val low = axes.values.min()
        val style = when {
            level <= 2 -> PlayStyle.Rookie
            top - low <= 0.5 -> PlayStyle.Allround
            else -> PlayStyle.of(PlayAxis.entries.first { axes[it] == top })
        }
        // 最强一拍：技术题里等级最高的一项（一样高时按题目顺序）
        val techniques = questions.filter { it.kind == AssessmentQuestion.Kind.Technique }
        val bestLevel = techniques.maxOfOrNull { answer(it.id) } ?: 0.0
        val best = techniques.firstOrNull { answer(it.id) == bestLevel }
        return PlayProfile(axes, style, best?.let { AssessmentDimension(it.id, it.title, bestLevel) })
    }

    /** 演示：典型的中级球友（主动球不错、反手和网前还差一点，定出 4） */
    val demoAnswers: Map<String, Int> = mapOf(
        "clear" to 4, "smash" to 4, "drop" to 4, "backhand" to 2, "net" to 3, "drive" to 3, "footwork" to 4,
        "passive" to 2, "doubles" to 2, "stability" to 3, "tactics" to 2, "standing" to 1, "experience" to 2, "recency" to 0,
    )

    /** 演示：等级卡片用，杀球最好（杀球重炮手），等级还是 4 */
    val levelCardDemoAnswers: Map<String, Int> = demoAnswers + ("smash" to 5)
}
