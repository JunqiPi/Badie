# iPhone App 上架流程

> 按顺序做。2026-10 核对过 Apple 的官方要求；“实际经验”来自开发者论坛和博客，标在括号里。
> **任何密钥（.p8 文件、密码）都不要发到聊天里，也不要提交到仓库。**
> 第 0、1 步不花钱，可以先做；从第 2 步开始需要 Apple Developer Program（每年 $99）。

**现状（2026-10-24）**：1.0 已提交审核（Build `20261023.2350`），选的是**手动发布**：审核通过后在版本页点 Release This Version 才上架。
上架后把 App Store 链接告诉工程 agent：网站加下载按钮和 Safari 智能横幅，关于页的“iPhone App 测试中”改掉。

## 0. 现在就能做

1. **决定用个人还是公司身份注册**
   - 个人：App Store 上“开发者”一栏显示你的**真名**。只要身份证件，一般 1～3 天批下来（有人卡了几周，多是付款或证件对不上）。
   - 公司：显示公司名，但要先有公司（LLC 等，个体户的商号不行）和邓白氏编码（D-U-N-S，免费，D&B 最多 5 个工作日，再等 Apple 最多 2 天）。
   - 没有公司就用个人。以后成立公司可以找 Apple 客服把账号转过去。
2. **审核用的演示账号**（审核员必须能登录，否则直接被拒）
   - Cloudflare Email Routing 加一个地址 `review@badie.rsvp` 转到你的邮箱。
   - 在 badie.rsvp 用它和一个密码注册，填好昵称、定级，加一两家球馆到“我的球馆”，最好和你的主账号互加好友、约过一场，让审核员能看到真实内容。
   - 邮箱和密码填在第 4 步的 App Review Information 里。
3. **审核规则 1.2（用户内容）已经齐了**：过滤、举报、屏蔽、联系方式、用户协议里的“零容忍、24 小时内处理举报”。
   - 过滤在服务器上做，网页和 App 都生效：昵称、球群名、球馆名有不当词存不了；消息、简介、备注、约战留言里的不当词换成 `***`。
     英文词表来自 LDNOOBW（CC BY 4.0），去掉了容易误伤的词；中文等是自己整理的。漏掉的词在 `blocked_terms` 表里加一行就生效。
   - 举报原因有“不当内容（昵称、头像、消息）”，头像这类图片靠举报 + 人工处理。
   - **24 小时内处理举报要说到做到**：有人举报时管理员会收到通知，在网站的 `/admin/` 页处理（改掉昵称、撤下照片、封号或驳回），
     能看到被举报人最近 30 天发给举报人的消息。你的账号要在 `admin_users` 表里（Supabase → Table Editor 加一行）。
   - 同一页还有**爽约申诉**：选“撤销”或“维持”。7 天没处理会自动维持，所以要按时看。
4. **商店信息**：10 种语言的最终文案在 `STORE_LISTING.md`（名称、副标题、关键词、推广文本、描述）。
   - 截图：GitHub → Actions → **App Store screenshots** → Run workflow，跑完下载 `app-store-screenshots-6.9-inch` 和 `app-store-screenshots-6.3-inch`。
     每个尺寸下按语言分文件夹（en、zh-Hans、zh-Hant、ja、ko、id、ms、th、vi、hi），每种 8 张，文件名开头的 1–8 是上传顺序。
     每张上方有一行标题（文字在 `Badie-iOS/scripts/store_captions.json`，`*重点*` 用柠檬绿标出，中日文太长要手动加 `\n` 断行）。

## 1. 注册 Apple Developer Program

1. iPhone 上装 **Apple Developer** App → Account → 用你的 Apple ID 登录（建议开双重认证）→ Enroll Now。
2. 选 Individual（个人），按提示拍身份证件照片，**用你本人名下的信用卡**付 $99（用别人的卡会被要求补材料，拖很久）。
3. 等确认邮件。超过 1～3 天没消息，在 developer.apple.com/contact 联系客服。

## 2. 账号批下来后（约 1 小时，网页上就能做，不需要 Mac）

1. **注册 App ID**：developer.apple.com → Account → Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App：
   - Description `Badie`，Bundle ID 选 Explicit，填 `com.badie.app`。
   - Capabilities 勾 **Push Notifications**、**Sign In with Apple**（Enable as a primary App ID）、**Associated Domains**、**Communication Notifications** → Continue → Register。
     少勾了云端构建会报描述文件缺权限，回来 Edit 补上再跑一次就行。
     通知扩展的 App ID（`com.badie.app.NotificationService`）不用自己建，云端构建第一次运行时会自动注册。
   - 记下 Team ID（Account → Membership details，10 位字母数字；Apple 登录和推送的配置都要用）。
2. **Apple 登录**：按 `DEPLOY.md` 第 4.5 节 “Apple” 的 1～5 步做（App ID 上一步已经建好）。做完 App 和网站会自动出现 Apple 按钮，App 里的 Google 按钮也会同时出现（App 从服务器读取开了哪些登录方式，不用发新版）。
3. **iPhone 推送**：和 Apple 登录共用一把私钥，第 2 步做完就有了（`DEPLOY.md` 第 4.5 节第 2 步建 Key 时同时勾 APNs）。
   - 已经单独建过 APNs 的 Key、在 Supabase 里加了 `APNS_KEY_ID`、`APNS_PRIVATE_KEY` 的，也没关系，会优先用它。
   - 用 Xcode 直接装到手机上的是开发版，走 Apple 的测试推送环境；TestFlight 和 App Store 版走正式环境。代码已经自动区分。
4. **Apple 隐藏邮箱能收到我们的邮件**：`DEPLOY.md` 第 4.5 节 Apple 第 5 步（注册 `badie.rsvp`、`send.badie.rsvp`）。我们的邮件都有 DKIM 签名，满足 Apple 的要求。
5. **通用链接和共用密码**已经配好（Team ID `PU482V2DWN` 写在网站的 `.well-known/apple-app-site-association` 里）：
   - 邀请链接 `badie.rsvp/join/?code=…`、邮件里的球局和球群链接，装了 App 的点开直接进 App，没装的在网页上打开。
     从 Instagram、Telegram 的内置浏览器点开不会跳 App（它们的限制），网页上照样能用。
   - 在 Safari 里给 badie.rsvp 存的密码，App 登录时会自动出现在键盘上方。
   - Apple 经自己的 CDN 缓存这个文件，改了以后不会马上生效；App 是安装或更新时才去取的。

## 3. 构建和 TestFlight

两种方式选一种。上传的 App 必须用 **Xcode 26 或更新版本**构建（2026-04-28 起的要求），两种方式都满足。

**方式一：GitHub 云端构建（不需要 Mac）**

1. **先建 App 记录**：App Store Connect → My Apps → **+** → New App（填法见第 4 节开头）。没有这条记录传不上去。
2. **建 API 密钥**：App Store Connect → Users and Access → **Integrations** → App Store Connect API → **Team Keys**。
   - 第一次用要先点 Request Access 同意条款（账号持有人才能点）。
   - Generate API Key：名字 `GitHub Actions`，Access 选 **Admin**（要用它建证书；建好后改不了权限，选错只能删了重建）。
   - 记下页面上的 **Issuer ID** 和这把密钥的 **Key ID**，下载 `.p8`（**只能下载一次**）。
3. **存进 GitHub**：仓库 → Settings → Secrets and variables → Actions → New repository secret，加三条（直接粘进去，**不要发到聊天里**）：
   - `ASC_KEY_ID`：Key ID
   - `ASC_ISSUER_ID`：Issuer ID
   - `ASC_PRIVATE_KEY`：用记事本打开 `.p8`，全选复制，包括 `-----BEGIN PRIVATE KEY-----` 和 `-----END PRIVATE KEY-----` 两行
   - 存好后把下载的 `.p8` 放进密码管理器，或者删掉（丢了可以吊销再建一把）。
4. GitHub → Actions → **TestFlight** → Run workflow（分支选 main）。约 20 分钟，跑完页面上会显示版本和 Build 号。
   - 每次运行会用这把密钥建一张名为 “Badie GitHub Actions” 的发布证书和描述文件，下一次运行开始时吊销上一张，所以 Certificates 页面上会一直留着一张，不用管。已经传上去的 Build 不受吊销影响。
   - Build 号是上传时的 UTC 时间（如 `20261021.1530`），每次自动变大，不用手动改。
   - 上传前会检查推送和 Apple 登录的权限都在。报错 “Bundle ID 还没注册” 就是第 2 节第 1 步没做；报证书数量到上限就到 Certificates 页面吊销用不到的发布证书。

**方式二：用自己的 Mac**

1. 装 Xcode 26 或更新版本 → Settings → Accounts → 加上你的 Apple ID。
2. 打开 `Badie-iOS/Badie.xcodeproj` → 选 Badie target → Signing & Capabilities → Team 选你的账号（保持 Automatically manage signing）。
3. 顶部设备选 **Any iOS Device (arm64)** → Product → **Archive** → Organizer 里 Distribute App → **App Store Connect** → Upload（Build 号让 Xcode 自动管理）。

**两种方式都一样的**
- 版本号 1.0。已经设置了“只用系统自带的 HTTPS 加密”（`ITSAppUsesNonExemptEncryption = NO`），上传后不会再问出口合规。
- 隐私清单（`PrivacyInfo.xcprivacy`）已经带上：不追踪用户，只用到 UserDefaults 存本 App 的设置。
- 上传后 10～30 分钟出现在 App Store Connect → TestFlight，处理完会收到邮件。
- **内部测试**（你自己和最多 100 个 App Store Connect 成员，不用审核）：手机装 TestFlight App 安装，按第 6 节逐项试。
- **外部测试**（可选，最多 1 万人，用邮箱或公开链接邀请）：每个版本的第一个 Build 要过 Beta 审核（一般几小时到一两天），要填测试说明和反馈邮箱（`support@badie.rsvp`）。Build 90 天后过期。

## 4. App Store Connect 填资料

My Apps → **+** → New App：平台 iOS，名称，主语言 English (U.S.)，Bundle ID `com.badie.app`，SKU `badie-ios`。

**App Information**
- Category：Sports（第二分类可选 Social Networking）。
- Content Rights：选“包含第三方内容”，并确认有权使用（球馆数据来自政府开放数据和 OpenStreetMap，都是开放许可）。
- **Age Rating**：问卷照实答（有用户发的内容、有私信、没有无限制上网）。用户协议规定 13 岁以上，**最后把年龄分级改成 13+**，和协议一致。2026-09 起问卷里关于社交功能的问题是必答的。
- **EU 数字服务法（DSA）**：即使不在欧盟上架也要声明。Badie 免费、没有广告和收费，选**非商家（Not a trader）**，这样不用公开地址和电话。以后加了广告或收费再改成商家（可以用邮政信箱和虚拟号码）。

**App Privacy（隐私标签）**：不追踪用户（Tracking：No）。收集的数据都选“与身份关联、用于 App 功能”：

| 类别 | 选项 | 说明 |
|---|---|---|
| Contact Info | Email Address、Name | 登录邮箱；Google / Apple 登录时给的名字 |
| User Content | Photos or Videos | 头像 |
| User Content | Emails or Text Messages | 聊天消息 |
| User Content | Other User Content | 昵称、等级问卷、评价、球局、加的球馆 |
| Identifiers | User ID | 账号 ID |
| Other Data | Other Data Types | 性别（男女等级分开算，只用于定级和匹配） |

- 位置**不用勾**：只在搜附近球馆时发一次，不保存（Apple 的定义里不算“收集”）。
- 没有统计、崩溃收集、广告 SDK，所以 Usage Data、Diagnostics 都不勾。

**Pricing and Availability**：Free。地区选了**除中国大陆以外的全部国家和地区**（中国大陆要 ICP 备案和国内主体）。
Mac（Apple 芯片）勾上：iPhone 版在 Mac 上是固定的手机大小窗口，功能都能用；Vision Pro 不勾（没法测）。

**版本页（1.0）**
- 截图：必填的是 “iPhone with Dynamic Island (medium display)”，传 6.3 英寸那组；“large display” 可选，传 6.9 英寸那组更清晰。
  iPhone Duo、Face ID、Home Button 那几个尺寸不用传，会自动缩放。iPad 标签在选好 Build 后就不再要求（App 只支持 iPhone）。
  Header（商店页顶部大横幅，5244 × 2950）是可选的，第一版没传，下次更新时可以补。
- **每种语言都要单独填**：Description、Keywords、Support URL `https://badie.rsvp/contact/`，以及 App Privacy 页上的 Privacy Policy URL `https://badie.rsvp/privacy/`。
  只填英文的话，提交时会对每种语言报“This field is required”。切换语言前先点 Save，不然没保存的会丢。
- Marketing URL `https://badie.rsvp`、Copyright `2026 你的名字`。
- Build：选第 3 步上传的 Build。
- **App Review Information**：
  - 演示账号的邮箱和密码（第 0 步建的），勾 Sign-in required。
  - 联系人：你的名字、电话、邮箱（只给审核员看）。
  - Notes（英文写给审核员，1.0 提交时用的）：
    > Badie helps badminton players find partners at their level and courts nearby. It is free, with no ads or purchases.
    > Demo account: sign in with the email and password above (Sign in with email, then Password). The account already has a friend and a past game so you can see real content.
    > Matching: open Play, pick a time and up to 3 courts, then Start matching. A match needs a second real player, so it may stay in "searching" during review. The past game, chat, leaderboard and player profiles show what a confirmed game looks like.
    > User-generated content (Guideline 1.2): offensive words are filtered on the server (names containing them can't be saved, and they're masked in messages). Report or block: open any player profile and tap Report or Block. Reports are reviewed within 24 hours on our admin page. Missed games: if most of the other players say someone didn't show up and they didn't check in, it is recorded. Within 180 days, the first time is a warning, the second blocks joining games for 7 days, the third permanently. Players can appeal within 48 hours.
    > Account deletion: Me tab → Settings (gear icon) → Delete account and data. Sign in with Apple accounts are revoked through Apple's REST API.
    > Location is only used to show courts nearby and is not stored.
- 发布方式选了 **Manually release this version**。

## 5. 提交审核和上架

1. 版本页右上角 **Add for Review → Submit**。Apple 说 90% 在 48 小时内审完；2026 年的实际记录多数在一天内（年初有过一两周的积压）。第一次提交通常比更新慢，每次被拒都重新排队。
2. 发布方式建议选 **Manually release**：审核通过后你自己点发布，可以先在 TestFlight 再确认一遍。
3. 被拒了：在 App Store Connect 的 Resolution Center 回复或改了重新提交。常见原因和对应情况：
   - 1.2 用户内容：要有过滤、举报、屏蔽、联系方式，协议里写明零容忍（都已经做了，见第 0 步）。开发者论坛里有人因为审核员的截图里看不到协议被拒：
     我们注册时要勾选同意，下面就是用户协议的链接。
   - 2.1 审核员登录不了或后台没开：演示账号要能用；Supabase 免费项目 7 天没活动会暂停，已有每天的保活任务。
   - 4.8 登录：有 Google 就要有 Apple 登录（已经是原生的 Apple 登录）。
   - 5.1.1(v) 注销账号：App 里能直接注销并删除数据，Apple 登录的会撤销授权（已做）。
   - Apple 登录后又要用户填姓名、邮箱会被拒：我们只问昵称，并且自动填好 Apple 给的名字，问题不大。
   - 权限说明要具体、要有各语言版本（位置说明已有 10 种语言）。
4. 上架后：把 App Store 链接告诉我，我在网站上加下载按钮和 Safari 的智能横幅，“关于”页面里的“iPhone App 测试中”也改掉。

## 6. TestFlight 自测清单

- 新邮箱 + 密码注册 → 收到确认码 → 填昵称 → 定级；退出后用密码和 Face ID 自动填充登录；“忘记密码？”能收到重置码。
- Apple 登录（选“隐藏邮箱”试一次，确认能收到验证码类邮件）、Google 登录。
- 允许通知后，用另一个账号给自己发好友申请，锁屏也能收到推送。
- 另一个账号（有头像）给自己发私信：锁屏通知左边是对方的头像；点开直接进这个私信；正开着这个私信时不弹通知。
- 在备忘录里写 `https://badie.rsvp/join/?code=房间码`，点它直接打开 App 的加入页（通用链接）。
- 附近球馆（允许 / 拒绝定位两种情况）、约球、聊天、举报、屏蔽。
- 设置 → 联系我们能打开邮件；设置 → 注销账号能走完，Apple 登录的账号注销后在 iPhone 设置 → Apple ID → 使用 Apple 登录 里消失。

## 参考

- 注册：https://developer.apple.com/programs/enroll/ ，D-U-N-S：https://developer.apple.com/help/account/membership/D-U-N-S/
- 构建要求：https://developer.apple.com/news/upcoming-requirements/
- App Store Connect API 密钥：https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api
- 云端 Mac 上装证书（GitHub 文档）：https://docs.github.com/en/actions/use-cases-and-examples/deploying/installing-an-apple-certificate-on-macos-runners-for-xcode-development
- 审核规则：https://developer.apple.com/app-store/review/guidelines/
- 隐私标签：https://developer.apple.com/app-store/app-privacy-details/
- 年龄分级：https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/
- 截图尺寸：https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- DSA 商家声明：https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- TestFlight：https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- 注销账号：https://developer.apple.com/support/offering-account-deletion-in-your-app/
- 审核时长（实际记录）：https://www.runway.team/appreviewtimes
