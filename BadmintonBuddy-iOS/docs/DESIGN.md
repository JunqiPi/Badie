# 羽毛球搭子 v3 · 设计说明（Court Pop）

本文记录这次全面改版的设计过程与结论，按设计师的真实工作步骤组织：
**发现 → 定义 → 构思 → 高保真验证 → 系统化 → 实现与走查**。

---

## 1. 发现（Discover）

### 1.1 现状审计

| 问题 | 影响 |
|---|---|
| Xcode 工程只编译 12 个文件，`Managers/`、`Models/`、`Services/` 等都没进 target，`BadmintonCourt` 也不满足 `Hashable` | 旧版**无法编译** |
| 好友、私信、房间、问卷只有空的 Manager（大量 `TODO`），没有界面 | 规格文档标为完成，实际不可用 |
| 匹配是 2–4 秒随机定时器，忽略时间段、水平、球馆 | 核心价值不成立 |
| 确认页写死“朝阳区体育中心 / 今天 19:00” | 信息错误 |
| 每次登录都新建用户，无持久化，无验证 | 退出即丢数据 |
| 定位在北京以外时附近球馆为空，按钮永远不可用 | 模拟器默认定位下无法匹配 |
| 仅深色模式、固定字号、未处理减弱动态效果 | 不满足无障碍要求 |
| 计时器不释放（在线人数、匹配省略号） | 内存/性能隐患 |

### 1.2 用户研究（证据优先，区分营销与事实）

数据来源标注：**[用户]** 真实用户帖子/评论，**[媒体]** 报道，**[厂商]** 官方自述（未独立验证），**[论文]** 学术研究。

| 发现 | 证据 | 对设计的影响 |
|---|---|---|
| 订场难、订场贵是头号痛点 | 北京晚场 235 元/时、热门时段预订率 91% [媒体] | 加入**“我有场地缺人”公开球局**，让已有场地的人补位 |
| 时间、水平、距离很难同时对上 | 小红书相关笔记过万、知乎反复求助 [媒体/用户] | 匹配同时考虑三者，并在无结果时**给出能真正产生结果的放宽建议** |
| 自报水平不可信、新手被嫌弃 | 知乎、豆瓣用户吐槽 [用户] | 1–9 级**行为化描述**；新球友显示“待校准”；对手赛后三选一校准；球局氛围标签（新手友好） |
| 放鸽子、AA 收钱尴尬 | 知乎组织者经验 [用户]；Meetup 组织者称 40% 爽约 [用户] | **到场签到 + 履约档案**、开赛前 2 小时内取消计为临时取消、AA 明细与“已付”标记 |
| 微信接龙混乱 | 两人同时操作会漏掉报名 [用户] | 公开局有人数上限、**候补自动递补** |
| 提醒能显著降低爽约 | 21 项随机对照试验的元分析：爽约约 −25%，多次提醒更好 [论文 Robotham 2016] | 开赛前 **1 天 / 2 小时 / 15 分钟三次提醒** |
| 评分会通胀、会报复 | Airbnb 评分普遍偏高 [论文 Zervas]；双盲评价减少报复 [论文 Fradkin] | **双盲互评**：双方都提交或 48 小时后才计入；只展示汇总；准时以签到等客观数据为主 |
| 资料完整更易获得信任 | BlaBlaCar × NYU 调查 [厂商] | 资料卡展示等级、口碑、履约率、距离；手机号永不展示 |
| Playtomic 的分摊付款与按位预付口碑好 | App Store 4.8 / 1.4 万评分 [用户] | AA 明细透明、平台不收服务费（真实支付需后端接入） |

> 注意：中国羽协 1–9 级需参赛获得，与民间自评不同。App 内等级明确标注为“自评，参考民间业余标准，非羽协官方等级”。

---

## 2. 定义（Define）

**核心任务（JTBD）**：“今晚 / 这周某个时间，在我能去的球馆，找到水平差不多、靠谱的人打一场。”

**设计原则**

1. **一眼可读**：大数字、强对比、墨色描边；时间、价格、人数用圆体数字突出。
2. **有分量的触感**：硬投影按钮按下时“压平”，配合触感反馈；动画都能被“减弱动态效果”关闭。
3. **信任可见**：任何出现球友的地方都带等级、准时率、履约率；新球友明确标注“待校准”。
4. **少一步**：默认今晚 19–21、常用时间、最近的球馆、偏好模式；首页一键“开始匹配”。
5. **活力不吵闹**：柠檬绿只用于最重要的行动；其余用马卡龙“贴纸色”区分信息类型。

---

## 3. 构思（Ideate）：参考图拆解

| 参考 | 借鉴 | 没有照搬 |
|---|---|---|
| 01 标签栏合集 | 悬浮 Dock + 中间 FAB，4–5 项、48pt 点击区、选中态清晰 | 玻璃拟态（与描边风格冲突） |
| 02 游戏化消费 App | 日期条、头像叠放、“已有 N 人”社交证明、黑色胶囊主按钮 | 3D 表情头像（无素材，改为首字/表情 + 色块） |
| 03 新粗野主义 NFT | 柠檬绿 + 墨色粗描边 + 硬投影；三格统计；粗细对比的大标题 | 加密货币语义 |
| 04 UI Kit | 胶囊筛选、分段控件、爆炸星形徽章（用作 VS） | 波点背景 |
| 05 复古课程 App | 米白画布、带描边的卡片、“Featured” 粉色标签、中间 + 号的标签栏 | 衬线字（中文回落到苹方，混排不统一，改用圆体数字） |
| 06 Pelorous | 列表菜单的彩色图标贴片、日期选中胶囊、“保存并继续”式箭头按钮 | — |
| 07 账单分摊 | 票据形状卡片（左右缺口）→ **球局票**；AA 分摊；深紫夜色 → **深色模式画布** | 拟物阴影 |

**风格命名：Court Pop**：米白球场底 · 墨色描边 · 硬投影 · 荧光柠檬主色 · 马卡龙贴纸辅色。

---

## 4. 高保真验证（Prototype）

在写 SwiftUI 之前，先用 HTML 做了风格板 + 4 个关键页面（首页、找到搭子、球局票、我的）的浅色/深色高保真稿，渲染后自查并迭代了一轮：

- 深色模式第一版描边几乎不可见 → 改为浅紫灰描边，并做了对比度复核（见下表）；
- 柠檬色马克笔高亮在深色下“白字压亮绿”不可读 → 高亮文字统一改为墨色；
- VS 星形压住对手昵称 → 下移到卡片下方。

最终界面以 CI 中的模拟器截图做走查（`scripts/ci_screenshots.sh`，浅色/深色各 19 个页面）。第一轮走查（Design QA）发现并修复：

- 悬浮标签栏四周会露出滚动内容（首页日期条、我的页卡片）→ 标签栏后加画布色渐隐底；
- 通知未读底色（黄色 35% 透明）在深色下变成发灰的橄榄色 → 改为“未读 = 浮起的白卡，已读 = 平铺的浅灰卡”，靠层级而非色相区分；
- 房间详情里“编辑时间和球馆”是一行孤立文字链接 → 改成与其他信息行对齐的菜单行（带图标与箭头）。

---

## 5. 设计系统（`BadmintonBuddy/DesignSystem/`）

### 5.1 颜色 Token（浅色 / 深色）

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| canvas | `#F5F0E6` | `#16131D` | 页面背景 |
| surface | `#FFFFFF` | `#221E2B` | 卡片 |
| surfaceMuted | `#EDE6D8` | `#2C2737` | 次级底色、禁用 |
| ink | `#17140F` | `#F4EFE6` | 正文/标题 |
| inkSecondary | `#5B554B` | `#B9B2A6` | 次要文字 |
| inkTertiary | `#8C8579` | `#857D90` | 装饰/禁用（不承载关键信息） |
| stroke | `#17140F` | `#756A90` | 描边 |
| shadow | `#17140F` | `#07060A` | 硬投影 |
| lime | `#D4F33F` | 同 | 主行动（只作填充色） |
| lavender / peach / pink / sky / butter / mint | 马卡龙 | 略加深 | 社交 / 球局 / 评价 / 地点 / 成就 / 状态 |
| onAccent | `#17140F` | 同 | 所有强调色上的文字 |
| danger / dangerFill | `#C92A2F` / `#D22F35` | `#FF6B6E` / 同 | 错误文字 / 角标 |

**对比度复核（WCAG 2.1）**

| 组合 | 对比度 | 结论 |
|---|---|---|
| ink / canvas（浅） | 16.2 : 1 | AAA |
| inkSecondary / canvas（浅） | 6.5 : 1 | AA |
| onAccent / lime | 14.6 : 1 | AAA |
| onAccent / 各马卡龙色 | 10.7–14.4 : 1 | AAA |
| ink / surface（深） | 14.2 : 1 | AAA |
| inkSecondary / surface（深） | 7.8 : 1 | AAA |
| danger / canvas（浅 / 深） | 4.8 / 6.6 : 1 | AA |
| 白字 / 红色角标 | 5.0 : 1 | AA（由 3.9 调整而来） |
| 描边 / 画布（深，非文字） | 3.7 : 1 | 满足 1.4.11 的 3:1（由 1.9 调整而来） |

规则：**柠檬绿永远不当文字色放在浅色背景上**；强调色上的文字统一用 onAccent。

### 5.2 字体

全部基于系统文本样式（自动支持动态字体），`design: .rounded`：Display = largeTitle Black，Title / Title2 Heavy，Headline Bold，Body Medium……
固定大字号（票据时间、统计数字）用 `scaledFont(size:)`（`@ScaledMetric`），同样跟随动态字体缩放。中文回落为苹方。

### 5.3 间距、圆角、描边、投影、动效

- 4pt 栅格：2 / 4 / 8 / 12 / 16 / 20 / 24 / 32；页面边距 20。
- 圆角：10 / 14 / 20 / 26（连续曲率）。
- 描边 2pt；卡片硬投影 (3, 4)；按钮垂直投影 4pt，按下时下沉 4pt（“压平”）。
- 动效：standard spring(0.35, 0.78)；press 0.12s；碰撞动画 0.7s。系统开启“减弱动态效果”时，跳过弹跳、旋转、粒子与轨道动画。

### 5.4 组件

`StickerBackground`（`.sticker()` / `.card()`）、`BrutalButtonStyle`（primary / inverse / secondary / destructive / accent × large / medium / small）、`IconTile`、`IconButton`、`CountBadge`、`AvatarView` / `AvatarStack`、`LevelBadge`、`TagPill`、`NewPlayerBadge`、`ChoiceChip`、`SegmentedSticker`、`DateStrip`、`TimeStepper`、`LevelStepper`、`RatingPicker` / `StarsView`、`BrutalTextField`、`SearchField`、`StatTile`、`InfoRow`、`MenuRow`、`SectionTitle`、`ScreenHeader` / `LargeTitleHeader`、`TicketShape`、`Starburst(Badge)`、`ShuttlecockMark`、`Wordmark`、`ToastView`、`NoticeBanner`、`EmptyStateView`、`LoadingDots`、`ProgressBar`、`FlowLayout`、`FloatingTabBar`。

---

## 6. 信息架构与核心流程

```
启动 → 欢迎 → 手机号(+隐私同意) → 验证码 →（新用户）昵称/头像 → 自评等级 → 偏好(模式/常用时间/定位)
                                         ↘（老用户）直接进入
主框架（悬浮标签栏）
├─ 首页：下一场球票 · 快速约球卡 · 哪天有空(可约人数) · 待评价 · 附近球局 · 附近球友 · 附近球馆地图
├─ 球局：发起球局 / 房间码 · 我的房间 · 即将开始 / 已结束 · 历史
├─ ＋：快速匹配 / 发起球局 / 输入房间码
├─ 消息：聊天（已读回执、输入中、房间邀请卡、快捷回复、屏蔽/举报）· 球友（申请、搜索、加好友）
└─ 我的：资料 · 口碑与等级校准 · 履约记录 · 球友 · 常用时间 · 出行范围 · 球馆收藏 · 屏蔽名单 · 设置
```

**快速匹配**：设置（模式 / 14 天内日期 / 1–8 小时时段 / ≤3 个球馆 / 水平差）→ 搜索动画 → 找到搭子（口碑三格、共同空闲时间、球馆、AA 明细、双打自动平衡分组）→ 确认 / 换一个 → 球局票。
没有结果时：只展示**确实能找到人的**放宽方式（扩大水平差 / 前后放宽时间 / 扩大范围 / 换一天），或转为发起公开球局。

**球局生命周期**：确认 → 提醒（三次）/ 加入日历 / 导航（Apple · 高德 · 百度）/ 聊天 → 开赛前 30 分钟签到 → 结束并记录结果 → 双盲互评（到场情况 / 水平三选一校准 / 球品 / 标签）→ 口碑与综合等级更新。

---

## 7. 无障碍

- 所有图标按钮都有 `accessibilityLabel`，选中态带 `.isSelected`；卡片合并为单个可读元素。
- 动态字体：全部使用文本样式或 `@ScaledMetric`。
- 减弱动态效果：启动弹跳、匹配雷达、轨道头像、碰撞动画均降级为静态或淡入。
- 点击区域不小于 44×44pt；时间与等级步进器支持 VoiceOver 的上下滑动调整（`accessibilityAdjustableAction`）。
- 颜色不是唯一信息来源：状态同时有文字（“已付 / 待付”“已读 / 已送达”）。

---

## 8. 需求对照

| 需求 | 实现 |
|---|---|
| 1 真实地图与定位 | MapKit 地图、定位权限引导与“前往设置”、出行半径 1–50 公里、北京收录球馆 + 其他城市 Apple 地图搜索 + 示例回退、位置不可用提示 |
| 2 9 级水平 | 1–7 自评 / 8–9 认证锁定；30% 自评 + 70% 球友评价；不足 5 次显示“新球友·待校准”；对手三选一校准 |
| 3 好友与房间 | 申请/通过/拒绝/删除、6 位房间码（去易混字符）、邀请好友、满员可开局、房主踢人（通知对方）、30 分钟无活动自动关闭、公开局候补递补 |
| 4 时间段匹配 | 14 天、1–8 小时、≥30 分钟重叠、水平优先再按距离、显示共同空闲时间、放宽建议、最多 5 个常用时间 |
| 5 私信 | 最近 50 条、已送达/已读、未读角标、1000 字上限、屏蔽（不通知对方）、删除仅对自己生效、本地持久化 |
| 6 赛后评价 | 完成球局生成问卷、48 小时有效、过期不计入、防重复提交、口碑汇总、确认前展示对方口碑并可“换一个” |
| 7 性能可靠 | 计时器统一用 `TimelineView` / `.task`，随视图销毁；数据 JSON 持久化（原子写入）；网络层可替换 |
| 8 无障碍与本地化 | 见第 7 节；界面文案为简体中文 |
| 9 数据持久化 | JSON 编码、解析失败给出路径信息、模型 Codable 往返测试 |

## 9. 球馆：怎么保证大家选的是同一家（首发美国，面向全球）

> 问题来源：“我会选 LABC / Elite Rally 然后在地图上找，万一找不到呢？”匹配只有在两个人选中**同一个球馆**时才成立。

### 9.1 先看真实情况（2026-10 实测）

| 观察 | 证据 | 结论 |
|---|---|---|
| 同一家球馆，不同来源写着不同城市 | Elite Rally（4800 Rivergrade Rd Unit B）：Yelp 写 Baldwin Park，Atly 写 Irwindale，另一篇文章写 Santa Fe Springs | 名称、城市都不可靠，必须看**完整地址 + 地图位置** |
| 按名称搜会搜到错的地方 | OpenStreetMap 搜 “Los Angeles Badminton Club” 返回 40 公里外 Manhattan Beach 的 “Badminton Club Pool”（游泳池）；Elite Rally 在 OSM 里不存在 | 不能只靠第三方地图的名称匹配 |
| 地图平台没有“羽毛球”分类 | Apple `MKPointOfInterestCategory` 84 个分类里有网球、排球，没有羽毛球 | 只能关键词搜索 + **自建球馆库** |
| 用户添加的球场目录容易变脏 | Pickleball+ App Store 评论 [用户]：信息过时、有人把自家房子加成球场；Places2Play 需要审核 [厂商] | 新球馆要有“待确认”状态和举报机制 |
| 重复球馆来自“直接新建” | The Events Calendar 组织者 [用户]：“大量重复的场馆”，因为回车就新建 | “添加球馆”放在结果底部，先查重再新建 |
| 只显示名字不够 | Baymard 自动补全研究：突出差异部分、移动端 4–8 条；Teevan 等 MobileHCI 2011：约 60% 的本地搜索不在身边 [论文] | 每行显示地址；按距离排序但**不限制**范围 |

### 9.2 方案

1. **平台球馆库是唯一标准**：匹配、房间、球局只比较我们自己的球馆 ID。Apple Place ID（iOS 18+）只作为附加字段用于查重（Apple 说明同一地点可能有多个 ID，因此连同 `alternateIdentifiers` 一起比较）。
2. **一个搜索框，两层结果**：先“已选 / 常去 / 附近”，输入后先显示球馆库（名称、别名、英文缩写 LABC、中文拼音首字母、街道、城市、邮编都能搜），再显示 Apple 地图联想（最多 6 条）。
3. **每一行都有地址**：名称（高亮匹配部分）+ 距离 / 街道·城市·州 / 可信度（已核实 · 球友确认 · 待确认）+ 场地数 + 常去人数。完整地址、地图在核对页和详情页。
4. **地图结果先核对再入库**：地图预览 + 完整地址 + 查重（Place ID 相同 → 直接选已有；200 米内名称相近 → “是同一个吗？”；40 米内同一栋楼 → 让用户判断，不自动合并，因为同楼可能有不同场馆）。
5. **找不到就添加**：移动地图让图钉对准入口 → 自动识别地址（可改）→ 名称 / 简称 / 单元 / 入口说明 / 场地数 → 查重 → 加入。也可粘贴 Google / Apple 地图链接（群聊里最常见的分享方式），自动解析坐标、名称或 Place ID。
6. **可信度会成长**：新加入为“待确认”，3 位不同球友确认（或在此签到打过球）后变为“球友确认”；显示“最近确认”时间。一个人举报不会下架，2 人以上举报的待确认球馆暂时从搜索中隐藏、等待人工核实（添加者本人仍可见）。
7. **少选几次**：常去球馆默认进入快速匹配；常去不受出行范围限制。

### 9.3 全球化（数据层已就绪）

| 项 | 做法 |
|---|---|
| 地址 | 结构化存储（街道、单元、城市、州/省、邮编、国家码），按国家习惯格式化（美式由小到大，中日韩台由大到小） |
| 时区 | 球馆存 IANA 时区；营业时间按球馆当地时间判断，时区与设备不同时标注 |
| 距离 | 跟随设备地区：美国、英国用英里，其他用公里；出行范围滑杆同步换算 |
| 币种与收费方式 | 每个球馆存 ISO-4217 币种；支持“按场地小时”和美国常见的“按人次 drop-in”，价格未知时显示“费用待定”而不是编造 |
| 手机号 | E.164 存储；13 个国家/地区的号码规则；默认跟随设备地区（首发 +1） |
| 导航 | 按球馆所在国家给出常用 App：美国 Apple / Google / Waze（Universal Link，没装 App 也能打开网页）；国内高德 / 百度；韩国 Naver / KakaoMap |
| 坐标系 | 每个球馆记录坐标系；中国大陆的地图数据按 GCJ-02 处理，导航到高德/百度时据此传参，避免 100–700 米偏移 |

### 9.4 分阶段路线（基于数据许可与覆盖调研）

| 阶段 | 地区 | 数据来源 | 可长期存储的内容 |
|---|---|---|---|
| 现在 | 美国 | 平台收录 + Apple 地图（免费、无需 Key） | Apple Place ID（Apple 明确豁免存储限制）；名称/地址/坐标以用户确认的版本入库 |
| 下一步 | 加、英、澳、新、马、港、台、印 | 同上；用 Overture Places（`badminton_court` 分类，美国 213 / 印尼 1,343 / 马来西亚 975 / 台湾 508 条，CDLA-Permissive 许可）和 Foursquare OS Places（Apache-2.0）做种子，人工复核 | 开放数据可存；Google Places 只存 place_id（坐标最多缓存 30 天） |
| 之后 | 韩国 | Kakao / Naver 本地搜索（Apple 地图在韩国受数据出口限制） | 只存对方的地点 ID |
| 单独评估 | 中国大陆 | 需要本地主体与 ICP 备案；高德/百度条款禁止存储其数据 | 只存我们自己（用户确认）的数据 |

> OpenStreetMap 的 `sport=badminton` 多数是露天场地（91.6% 为 `leisure=pitch`），且 ODbL 共享条款会传染到合并后的库，所以不并入球馆库。

### 9.5 首批收录（美国 32 家）

数据与来源在 `data/us_venues.json`（每家含 4 个以上来源链接、地址冲突说明、价格出处），用 `scripts/gen_us_venues.py` 生成 `Models/CuratedVenues+US.swift`。南加州 10 家：LABC、Elite Rally、SGVBC、Arena（Pomona）、Santa Fe Springs BC、OCBC、PickleBall Badminton Center（Lakewood）、Manhattan Beach BC（会员制）、SMASH! San Diego、OC SMASH（状态存疑，标为待确认）；其余为湾区、西雅图、纽约/新泽西、休斯顿/达拉斯、芝加哥、波士顿。已排除确认关门的球馆（Yan Long、Arcadia BC、IBC Irvine、Bintang 南旧金山等）。

### 9.6 主要来源

- 选择体验：[Meetup 添加场馆](https://help.meetup.com/hc/en-us/articles/30950090563597-How-to-add-a-location-or-venue-to-your-event) · [Luma](https://help.luma.com/p/featuring-your-event-on-luma) · [TeamSnap 场地](https://helpme.teamsnap.com/article/1342-add-schedule-locations) · [Reclub 手动添加](https://help.reclub.co/hc/reclub-help/articles/1770103887-improved-location-search-adding) · [Baymard 自动补全研究](https://baymard.com/research-articles/autocomplete-design) · [Teevan 等 MobileHCI 2011](https://www.microsoft.com/en-us/research/?p=161675) · [Yelp 去重工程博客](https://engineeringblog.yelp.com/2015/05/seeing-double-on-yelp.html) · [The Events Calendar 用户反馈](https://theeventscalendar.com/support/forums/topic/avoid-duplicate-organizers-and-venues/) · [Pickleball+ App Store 评论](https://apps.apple.com/us/app/pickleball/id1262785848)
- 地图与数据：[Apple Place ID 说明](https://developer.apple.com/documentation/mapkit/identifying-unique-locations-with-place-ids) · [WWDC25 Go further with MapKit](https://developer.apple.com/videos/play/wwdc2025/204/) · [MKPointOfInterestCategory](https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory) · [Google Places 政策](https://developers.google.com/maps/documentation/places/web-service/policies) · [Overture Places](https://docs.overturemaps.org/guides/places/) · [Foursquare OS Places](https://docs.foursquare.com/data-products/docs/access-fsq-os-places) · [OSM sport=badminton](https://taginfo.openstreetmap.org/tags/sport=badminton) · [韩国地图数据出口](https://www.maproomblog.com/2026/02/google-maps-granted-access-to-south-koreas-map-data-with-conditions/) · [高德 URI](https://lbs.amap.com/api/amap-mobile/guide/ios/route) · [百度 URI](https://lbsyun.baidu.com/faq/api?title=webapi/uri/ios)

---

## 10. 已知限制

- **没有真实服务端**：附近球友、公开球局为本机模拟（设置页明确告知），可“重置演示数据”。`MockBackend` 以事件流对外，替换为真实 API 时 Manager 层无需改动。
- **支付**：AA 只做“已付/待付”标记，未接入真实支付。
- **球馆库目前只在本机**：添加、确认、举报都写入本机模拟后端；多人共享需要真实服务端与人工审核队列。
- **Apple 地图数据条款**：Place ID 可长期保存；其余地图内容（名称、地址、坐标）条款上只允许临时缓存，正式上线前需法务确认“用户确认后入库”的做法。
- **Place ID 需要 iOS 18**：iOS 17 设备只能靠坐标 + 名称查重。
- 8–9 级的赛事证明上传与审核需要后端支持，目前仅展示锁定说明。
