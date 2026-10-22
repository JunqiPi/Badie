# Badie 的故事和推广口径

> 网站首页、关于页、App 欢迎页和各平台推广都按这里说。要改说法，先改这里，再改页面。

## 一句话

- 中文：**不用自己开口找人，Badie 按水平帮你找球友。免费。**
- English: **No need to ask strangers for a game. Badie finds badminton players at your level for you. Free.**

## 为什么做 Badie

1. **不敢开口**：很多人社恐，不敢在球馆里找陌生人，也不敢在网上约；就算约到了，也不知道对面什么水平。创始人一开始就是这样。所以找人这一步由 Badie 来做，并且按水平配。
2. **让美国和欧洲的羽毛球圈子活跃起来**：很多人不是不爱打，而是因为第 1 点打得少。找人不尴尬了，打球的人和次数才会多起来。
3. **固定球友有事就没球打**：不用干坐一晚，Badie 帮你找同一时间、水平相当的人。
4. **刚到新地方谁也不认识**：不管是上学还是工作搬过去，第一周就能找到球馆、固定局和球友。

## 每个痛点都要落到真实功能

推广时说的每一点，都要能在产品里找到对应的功能：

| 痛点 | 球友会怎么说 | Badie 怎么解决 |
|---|---|---|
| 不敢开口 | “我不好意思在球馆里问人” | 快速匹配：选时间和球馆，系统找人；双方都确认才成局 |
| 不知道对面水平 | “约到的人要么太强要么太弱” | 1–9 级定级问卷；只配水平相近的人；打完双方互评，等级会被校准 |
| 固定球友有事 | “搭子放鸽子了，今晚没球打” | 快速匹配，或者开临时局（只找现在就有空的人） |
| 刚到新城市 | “搬过来谁也不认识” | 附近球馆目录、每周的固定局、开放的球局 |
| 怕遇到不靠谱的人 | “约好的人没来” | 爽约和临时取消会被记录，靠谱的人更容易约到球 |
| 男女差距大 | “不想和男生打”“想打混双” | 男女等级分开算；约球、开局可以选男单、女单、男双、女双、混双 |

## 说话的分寸

- **App 里少写解释**：一屏一句话就够，App 的欢迎页只有“羽毛球搭子？就在今日！”。为什么做、怎么用这类说明放在网站的关于页和商店页。
- **只说做到了的事**：免费、按水平匹配、双方确认赛果、爽约会被记录、精确位置不离开设备。
- **不说没有的东西**：不报用户数，不说“最大”“第一”“最火”。
- **覆盖范围照实说**：球馆目录目前覆盖 7 个国家和地区，欧洲只有英国。所以对外说“**目标**是让美国和欧洲打球的人更多”，不说“已经覆盖欧洲”。
- **创始人的故事用第一人称讲**：你自己发帖时用“我”，最有说服力。网站上写的是“创始人”。
- **真实反馈比我们自己说的有用**：上线后收集球友的原话（征得同意），用作推广素材。
- **社区里先当球友，再当开发者**：Reddit、Facebook 群这类社区大多限制自我推广，发之前先看版规，并说明这是你自己做的。

## 现成的文案

**英文短帖**（Reddit、Facebook 群）

> I was too shy to find badminton partners, so I built an app for it.
>
> When I started playing, I didn't dare walk up to strangers at the gym or post in group chats. And when I did get a game, I never knew if the other person was way better or just starting out.
>
> Badie does that part for you: tell it when you're free and which courts you can get to, and it finds players at your level. It also helps when your usual partner cancels, or when you've just moved somewhere new.
>
> It's free and works in any browser: badie.rsvp. I'd love feedback from other players.

**中文**（小红书、微信）

> 社恐也能约到羽毛球｜我做了个免费找球友的网站
>
> 刚开始打球的时候，我不敢在球馆里找陌生人，也不好意思在群里约；约到了也不知道对面什么水平。
>
> 所以我做了 Badie：告诉它你什么时候有空、能去哪些球馆，它按水平帮你找球友。固定球友放鸽子、刚搬到新城市，也能用。
>
> 免费，网页就能用：badie.rsvp

**15 秒短视频**

1. 0–3 秒：站在球馆门口犹豫。字幕：“想打球，但不敢找陌生人？”
2. 3–6 秒：手机弹出“今晚去不了了”。字幕：“固定球友临时有事？”
3. 6–9 秒：拖着箱子到新城市。字幕：“刚搬到新地方？”
4. 9–15 秒：打开 Badie，选时间，匹配成功，上场。字幕：“Badie 按水平帮你找球友。免费。badie.rsvp”

## 这些话现在出现在哪里

- 网站首页“为什么是 Badie”、关于页的故事和目标：`web/src/app/Home.tsx`、`web/src/app/Levels.tsx`（三种情况的卡片是同一份，首页和关于页共用）。
- 给搜索引擎看的静态版：`web/src/pages/index.astro`、`web/src/pages/about/index.astro`。
- App 欢迎页的一句话：`Badie/Features/Onboarding/OnboardingFlow.swift`。
