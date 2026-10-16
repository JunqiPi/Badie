# Badie 正式后端规划

> 状态：规划稿（2026-10）。前提：个人开发、纯非营利、预算尽量低；**先做美国，再到全世界（中国大陆也能用）；iOS + 同功能同风格的网页端**。
> 现在的 App 用本机模拟后端 `MockBackend`，所有数据只在自己手机上；本文规划换成真正的共享后端。
> 价格与线路数据多来自厂商和社区帖子，下单前需晚高峰实测；合规部分不是法律意见。

## 1. 会有多少人用（按这个规模设计，不为百万用户过度设计）

| 情景 | 月活 半年 / 1 年 / 2 年 | 2 年时高峰同时在线 | 高峰请求/秒 |
|---|---|---|---|
| 悲观（没打进任何球群） | 100 / 300 / 500 | ~10 | <2 |
| **可能**（1–3 个城市、几家俱乐部用起来） | 800 / 2,000 / 5,000 | ~100 | ~15 |
| 乐观（打通球馆/俱乐部，口碑扩散） | 5,000 / 15,000 / 50,000 | ~1,200 | ~200 |

依据：不投营销的独立 App 首年下载中位数大约在 1,000 以内；同类产品里 Spond 用约 10 年做到 330 万月活，Reclub 用 7 年做到 80 万+ 安装，都是靠俱乐部组织者整群迁入。
估算假设（无公开数据可核）：约球是低频需求，日活/月活取 15–25%；每个日活每天 50–100 次请求；晚 7–10 点高峰占全天 20%，突发按 3 倍。

**结论：真正的瓶颈是冷启动（每个城市先要有足够多的人），不是服务器。** 一台小服务器能撑到乐观情景的第 1 年。

## 2. 选型结论（按社区实际反馈，2026-10）

社区原帖能直接找到的不多，多数证据来自开发者博客、官方文档和 GitHub 发布记录；下面已区分事实与个例。

### 后端：托管 Supabase（美西）

| 方案 | 结论 | 原因 |
|---|---|---|
| **托管 Supabase** | **首选** | 登录（Apple/Google/邮箱验证码）、Postgres + PostGIS（附近查询）、实时聊天、头像存储、SQL 函数一套齐全；本质是标准 Postgres，`pg_dump` 就能整体迁走，锁定最低；SQL/Postgres 资料最多，AI 写得最稳 |
| PocketBase + VPS | 第二选择 | 最便宜（每月约 6 美元），管理后台好用；但还没到 1.0，v0.23 那次升级要手改代码（“是重写不是升级”），AI 容易写成旧版 API；单人维护 |
| 自写 Go/TS 服务 + Postgres | 退路 | 最灵活，但登录、聊天、后台、备份、安全补丁全要自己做和维护 |
| Cloudflare Workers + D1 | 不选 | 没有地理索引，单库 10GB 上限，平台专有 API 多 |
| Firebase | 不选 | 没有硬性花费上限（官方承认预算告警不会停服），地理查询繁琐，NoSQL 数据难迁出 |

Supabase 的已知坑和对策：

- **行级权限（RLS）写错会泄露数据**：所有表默认开启 RLS；赛果、榜单、挑战等敏感写入只走服务端 SQL 函数；客户端永远不放 service_role 密钥。
- **RLS 拖慢查询**：策略里用 `(select auth.uid())`，相关列加索引。
- **推送不内置**：用数据库 webhook + Edge Function 调 APNs 和 Web Push。
- **Swift SDK 仍在快速修 bug**（近期修过 Realtime 相关问题）：锁定版本，升级前跑测试。

### 网页端：公开页面用 Astro 静态生成，登录后的应用用 React 单页应用（理由见第 3.5 节）

| 方案 | 结论 | 原因 |
|---|---|---|
| **React 19 + Vite + React Router** | **首选** | 训练数据最多，AI 写得最准；生态最全；需要登录、不靠搜索引擎的应用用单页应用最简单 |
| SvelteKit | 不选 | 包更小，但 AI 常写成旧的 Svelte 4 写法（社区为此专门做了测评和补救工具） |
| Expo（React Native + Web） | 暂不选 | 网页是二等公民，设计系统要重写；等确定要做原生安卓再考虑 |
| Flutter Web | 不选 | 首屏要先下载 3–4MB 引擎，不适合手机浏览器打开 |

搭配：

- **样式**：Tailwind v4，把 iOS `Theme.swift` 的颜色、描边、偏移阴影、圆角映射成 CSS 变量（基础变量 → 语义变量两层），深色模式同样支持；交互组件用无样式的 Radix，外观全部自己画，保证和 iOS 同风格。
- **多语言**：脚本从 `Localizable.xcstrings` 生成 10 种语言的 JSON（`%@`、`%lld` 转成 `{name}`，复数转 ICU 格式），用 i18next + ICU；翻译只维护 iOS 这一份。
- **地图**：Apple MapKit JS，和 iOS 共用 Place ID；每天 25 万次地图加载、2.5 万次搜索类调用免费。地图代码包一层薄接口，必要时可换 MapLibre。
- **PWA**：可安装、Web Push。安卓 Chrome 上成熟；iPhone 用户用原生 App，不受 iOS 网页推送限制影响。以后想上 Play 商店，可以把 PWA 打包成 TWA，不写原生代码。
- **托管**：Cloudflare Pages（免费）。

## 3. 架构

```
iOS App（SwiftUI）──┐
                     ├── Supabase（美西）
网页端（Astro + React）┘     ├─ Auth：Apple / Google / 邮箱验证码
   ↑                       ├─ Postgres + PostGIS：数据、附近查询、RLS 权限
   │                       ├─ SQL 函数：赛果确认、胜率/榜单（定时任务算好写表）、匹配、限流、挑战规则
   │                       ├─ Realtime：聊天、匹配状态
   │                       ├─ Storage：头像（客户端压到 30KB 以下，带缓存头）
   │                       └─ Edge Function：APNs + Web Push 推送
   └── Cloudflare Pages（公开页静态 HTML + /app 单页应用，全球 CDN）
备份：GitHub Actions 定时 pg_dump 到 Cloudflare R2（免费额度内）
```

- **规则只写一份，放在服务端**：iOS 和网页只负责显示和提交。现在 App 里的 `Rankings`、`Challenge`、匹配等规则代码，就是移植成 SQL 函数的蓝本。
- **审核**：先用 Supabase 后台的表格编辑器处理举报；量大了再做一个简单的管理页面（网页端里加一个管理员路由）。

## 3.5 公开页面与搜索（SEO / AI 搜索）

### 证据说了什么

- **AI 爬虫不执行 JavaScript**（Vercel/MERJ 日志分析，2024-12）：GPTBot、ChatGPT 搜索、ClaudeBot、PerplexityBot 都只读原始 HTML；只有 Googlebot 和 Applebot 会渲染。纯 React 单页应用的页面在 ChatGPT、Claude、Perplexity 眼里是空的。
- **AI 搜索基本还是传统搜索**：Google 官方说 AI 功能不需要特殊优化，强调“别处没有的信息”；AI Overviews 引用的页面里，排名前 10 的占比已降到约 38%（Ahrefs），排名有帮助但不是决定因素。
- **“GEO 写作技巧”证据很弱**：原始 GEO 论文（KDD 2024）称最多提升约 40%，但 NeurIPS 2025 的复现（C-SEO Bench）发现多数方法无效甚至有害。可抓取性 + 独特数据才是核心。
- **结构化数据对 AI 引用没有明显作用**（Ahrefs 对照实验）：关键信息必须写在可见的页面正文里，JSON-LD 只算加分项。
- **llms.txt 没有证据被使用**，Google 明确说不用。可以放一个，不投入精力。
- **站外渠道分量很重**：Reddit 是三大 AI 平台被引用最多的域名之一，ChatGPT 偏爱 Wikipedia，Perplexity 和 Google AI 偏爱 Reddit、YouTube。
- **AI 带来的点击很少**（Cloudflare：抓取与带来访问的比例从约 200:1 到数万:1）。目标是“被提及、被推荐”，不是流量。

### 架构因此调整

- **一个 Astro 项目，部署在 Cloudflare Pages**：
  - 公开页面由 Astro 输出纯 HTML（几乎不带 JavaScript），爬虫和 AI 都能读。
  - 登录后的应用是 React 单页应用，挂在 `/app/*` 下，加 `noindex`。交互组件和设计样式两边共用。
- **哪些页面公开、需要被搜到**：首页、场馆页、城市页、公开球群页、公开约球页、隐私和条款页。
- **哪些只在应用内**：消息、资料编辑、报名、设置、排行榜详情。
- **网址结构**：`/{语言}/courts/{国家}/{城市}/{场馆}`，例如 `/en/courts/us/san-jose/bay-badminton-center`。
- **生成方式**：每天由 GitHub Actions 从 Supabase 拉数据重新构建一次；变化快的约球页由 Cloudflare 函数现场生成并缓存。Cloudflare Pages 免费版每个站最多 2 万个文件，所以场馆页只预生成英文和当地语言，其余语言现场生成。

### 页面要有“别处没有的信息”，否则不放出来

- **场馆页**：球场数、开放时间、收费、球友确认时间、这里活跃的球群和固定场次、最近 30 天约球次数、场馆榜前几名（只显示同意公开的人）。
- **城市页**：至少 3 家场馆或有活跃球群才生成。
- **没有任何独特信息的场馆页先加 `noindex`**，有球友贡献后再放开（避免被 Google 当成批量生成的低质量页面）。
- **数据来源与许可**：
  - 开放数据的场馆在页面上标注来源和许可证（英国 OGL、新加坡、台湾等要求署名）。
  - **从 Apple 地图来的信息不公开发布**：Apple 开发者协议限制存储和再发布地图数据。场馆表加 `source`、`license` 字段，公开页只展示开放数据和用户自己填写、确认的内容；仅有 Apple 来源信息的场馆不生成公开页。
- **基础项**：JSON-LD（场馆 `SportsActivityLocation`、球群 `SportsClub`、约球 `Event`）、按语言拆分的 sitemap + hreflang、每页的分享卡片图（构建时生成）、网站顶部的 App 下载横幅、iOS 通用链接。
- **robots.txt**：允许 Googlebot、Bingbot、OAI-SearchBot、PerplexityBot、Claude 的搜索爬虫、Applebot。

### 站外（非营利、不刷量）

1. 在 r/badminton 和各城市版块以开发者身份如实回答“哪里能打球”，表明身份。
2. 拍几段短视频放 YouTube：App 演示、城市球馆指南。
3. 联系各地羽毛球协会、俱乐部，请他们链接对应的场馆页和球群页。
4. 登录 Product Hunt、AlternativeTo、非营利和开源目录。
5. 有了第三方媒体报道后，再考虑建 Wikidata 条目；不自己写 Wikipedia 词条。

### App Store（ASO）

- 标题、副标题各 30 字符，关键词字段 100 字符（逗号分隔、不加空格、不重复标题里的词）。
- 10 种语言分别本地化关键词和截图；美国区还会索引西班牙语（墨西哥）等本地化的关键词。
- 用“App 内活动”宣传赛事，用“自定义产品页”针对不同城市；尽早引导满意的用户评分。

### 怎么衡量（都免费）

- Google Search Console、Bing Webmaster Tools（有 Copilot 引用报告）。
- Cloudflare 的 AI 爬虫访问统计、Cloudflare Web Analytics 按来源区分 chatgpt.com、perplexity.ai 等。
- 每月用固定约 20 个问题（如“badminton courts in San Jose”）手动问各家 AI，每题问几次，记在表格里。

## 4. 球馆共享

| 来源 | 存什么 | 共享方式 |
|---|---|---|
| 开放数据（HK/SG/TW/GB/东京/韩国） | 随 App 打包 | 不进服务器，按许可显示署名 |
| 用户手动添加 | 用户填的名字、地址、图钉坐标 | 存服务器，附近的人立即可见（“待确认”），3 位不同球友确认后变“球友确认” |
| 用户从 Apple 地图选点添加 | **只存 Apple Place ID** + 用户确认的名字和位置 | Apple 允许长期保存 Place ID；别人的手机用 ID 向 Apple 取最新详情 |
| App 自动从 Apple 地图收录 | 只在本机缓存 | 不上传（Apple 条款不允许批量存储再分发）；有人在这家馆发起匹配时，才作为“选点添加”上传 Place ID |

去重：服务器端按 Place ID、名称相似度、距离（< 80m）判重，规则同 `VenueSearch.duplicates`。

## 5. 数据表（对应现在的 `Database`）

第一批：`users`、`venues`、`venue_reports`、`favorites`、`friendships`、`friend_requests`、`blocks`、`reports`。
第二批：`tickets`、`offers`、`games`、`result_reports`、`match_records`、`challenges`、`surveys`。
第三批：`threads`、`messages`、`groups`、`group_sessions`、`inbox`、`verification_requests`。
演示用的 `bots`、`seededUserIds` 只留在 `MockBackend`。

## 5.5 仓库结构：一个仓库，不拆分

```
Badie/
├─ Badie-iOS/        SwiftUI App（现有）
├─ web/              Astro 公开页 + React 应用（/app）
├─ supabase/         后端：数据库迁移、SQL 函数、RLS 规则、Edge Functions、种子数据
├─ shared/           两端共用：设计变量（颜色、描边、阴影）、从 xcstrings 导出的翻译、球馆开放数据
└─ .github/workflows 各自按路径触发的 CI（改 web/ 不跑 iOS 构建，反之亦然）
```

- **后端不单独建仓库**：用 Supabase 后，“后端代码”就是 `supabase/` 里的迁移文件、SQL 函数和少量 Edge Functions，用 Supabase CLI 部署。
- **好处**：改一个功能时，数据库、iOS、网页可以放在同一次提交里，不会出现“后端改了、客户端没跟上”；翻译和设计变量只维护一份；AI 助手一次能看到全部代码。
- **代价**：CI 要按路径分开触发（现有 iOS 工作流已经这样做）；密钥一律放在 GitHub Secrets 和 Supabase 后台，绝不提交进仓库。
- **什么时候再拆**：有了多人协作、需要分别授权时再考虑，现在没有必要。

## 6. 开发顺序

1. **iOS 抽接口**（不需要服务器）：`AppState` 和各个 Manager 现在直接依赖 `MockBackend`（在外部用到约 140 个方法）。按领域拆出协议，`MockBackend` 实现它们，行为不变、测试照跑。
2. **Supabase 第一块：账号 + 球馆**。表结构、RLS、附近查询、球馆去重和确认；SQL 迁移文件放在仓库里，CI 用本地 Supabase 跑测试。
3. **iOS 接上 Supabase**：`RemoteBackend` 按领域逐个接上；开关切换模拟/正式，演示模式和 CI 截图继续用模拟后端。
4. **网页端第一版**：公开的场馆页、城市页（Astro），以及应用里的登录、个人资料、附近球馆、添加球馆。
5. **之后每块功能服务端先行、两端跟上**：匹配与对局 → 赛果与榜单 → 聊天与球群 → 挑战。

## 7. 每月成本

| 阶段 | Supabase | 其他 | 合计（含 Apple 年费、域名摊销约 9 美元） |
|---|---|---|---|
| 开发、内测 | Free（0） | 0 | ~US$9 |
| 上线后 ~5k 月活 | Free 或 Pro（0–25） | 0 | ~US$9–34 |
| ~5 万月活 | Pro + 可能升级算力（25–60） | 0 | ~US$35–70 |

- **Free 版什么时候必须升 Pro**：Free 版连续 7 天没有请求才会暂停，有真实用户每天在用就不会停；但 Free 版没有自动备份（我们用 pg_dump 自己备）、数据库 500MB、存储 1GB、每月流量 5GB。任一项接近上限，或想要官方备份和支持时再升 Pro。
- 网页托管、MapKit JS（免费额度内）、APNs、Web Push、R2 备份都不花钱。
- **Apple 开发者年费 99 美元是唯一躲不开的固定成本**，减免只给经认证的非营利组织，个人不行。
- 想再省：Supabase 可以自托管，或迁到 PocketBase/自写服务 + 6 美元 VPS，`pg_dump` 导出即可。

## 8. 中国大陆：支持使用，但第一期不上中国区 App Store

- 中国区 App Store 上架必须有 ICP 备案号，个人主体基本备不了带聊天的 App（社区经验，以当地通信管理局答复为准）。
- 大陆用户可以用其他地区的 Apple ID 下载 iOS 版，或直接用网页端。Supabase 美西和 Google 登录在大陆可能不稳定，到时再加反向代理或迁移，现在不为此付出成本。

其余合规：

1. 隐私政策：英文为主，覆盖 GDPR（英国/欧盟用户）、CCPA（加州）；中文版写明数据存放在境外及用途，并取得单独同意。
2. 不收集敏感个人信息：服务器只存场馆坐标和粗略城市，不存用户实时位置，“附近”尽量在手机上算。
3. 举报、删除、封号能力，保留处理日志。
4. App 内可以删除账号；提供 Apple 登录。
5. 上线前在主要市场实测：接口、实时订阅、推送、头像加载（大陆用户的体验也测一下）。

## 9. 开工前要准备的

- 注册 Supabase（美西区域）、Cloudflare 账号，注册域名。
- Apple 开发者后台：“Sign in with Apple”服务（含网页回调）、APNs 密钥、MapKit JS 密钥。
- Google Cloud：OAuth 客户端（Google 登录）。
