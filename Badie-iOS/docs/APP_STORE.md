# iPhone App 上架流程

> 按顺序做。2026-10 核对过 Apple 的官方要求；“实际经验”来自开发者论坛和博客，标在括号里。
> **任何密钥（.p8 文件、密码）都不要发到聊天里，也不要提交到仓库。**
> 第 0、1 步不花钱，可以先做；从第 2 步开始需要 Apple Developer Program（每年 $99）。

## 0. 现在就能做

1. **决定用个人还是公司身份注册**
   - 个人：App Store 上“开发者”一栏显示你的**真名**。只要身份证件，一般 1～3 天批下来（有人卡了几周，多是付款或证件对不上）。
   - 公司：显示公司名，但要先有公司（LLC 等，个体户的商号不行）和邓白氏编码（D-U-N-S，免费，D&B 最多 5 个工作日，再等 Apple 最多 2 天）。
   - 没有公司就用个人。以后成立公司可以找 Apple 客服把账号转过去。
2. **审核用的演示账号**（审核员必须能登录，否则直接被拒）
   - Cloudflare Email Routing 加一个地址 `review@badie.rsvp` 转到你的邮箱。
   - 在 badie.rsvp 用它和一个密码注册，填好昵称、定级，加一两家球馆到“我的球馆”，最好和你的主账号互加好友、约过一场，让审核员能看到真实内容。
   - 邮箱和密码填在第 4 步的 App Review Information 里。
3. **上架前要补的代码：内容过滤**（审核规则 1.2：有用户发的内容，就要有过滤、举报、屏蔽和联系方式）
   - 举报、屏蔽、联系我们（`/contact/`）、用户协议里的“零容忍、24 小时内处理举报”都已经有了。
   - **还缺：昵称、消息、球群名、评价的不当词过滤。** 上架前要做。
   - 用户协议写了“24 小时内处理举报”，你要说到做到：有人举报时管理员会收到通知，记得及时看。
4. **想好商店信息**
   - App 名称（30 字以内，全 App Store 唯一；`Badie` 被占用就用 `Badie: Badminton Partners`）。
   - 副标题（30 字以内）、描述、关键词（100 个字符以内，逗号分隔）。
   - 截图：CI 每次会生成模拟器截图，可以在此基础上做。

## 1. 注册 Apple Developer Program

1. iPhone 上装 **Apple Developer** App → Account → 用你的 Apple ID 登录（建议开双重认证）→ Enroll Now。
2. 选 Individual（个人），按提示拍身份证件照片，**用你本人名下的信用卡**付 $99（用别人的卡会被要求补材料，拖很久）。
3. 等确认邮件。超过 1～3 天没消息，在 developer.apple.com/contact 联系客服。

## 2. 账号批下来后（约 1 小时）

1. **Xcode 签名**：Mac 上装 **Xcode 26 或更新版本**（2026-04-28 起，上传的 App 必须用 Xcode 26 / iOS 26 SDK 构建）。
   - Xcode → Settings → Accounts → 加上你的 Apple ID。
   - 打开 `Badie-iOS/Badie.xcodeproj` → 选 Badie target → Signing & Capabilities → Team 选你的账号（保持 Automatically manage signing）。Sign in with Apple 和 Push Notifications 已经在 entitlements 里，Xcode 会自动同步到 App ID。
   - 记下 Team ID（Membership 页面，10 位字母数字）。
2. **Apple 登录**：按 `DEPLOY.md` 第 4.5 节 “Apple” 的 1～5 步做。做完 App 和网站会自动出现 Apple 按钮，App 里的 Google 按钮也会同时出现（App 从服务器读取开了哪些登录方式，不用发新版）。
3. **iPhone 推送**：Keys → 新建一把只勾 **Apple Push Notifications service (APNs)** 的 Key（和 Apple 登录的 Key 分开，换起来互不影响），Environment 选 **Sandbox & Production**，Key type 选 **Team Scoped**。下载 `.p8`（只能下载一次）。
   - Supabase → Edge Functions → Secrets：`APNS_KEY_ID`、`APNS_PRIVATE_KEY`（粘 `.p8` 全部内容），`APPLE_TEAM_ID` 和 Apple 登录共用。
   - 自己用 Xcode 装到手机上的是开发版，走 Apple 的测试推送环境；TestFlight 和 App Store 版走正式环境。代码已经自动区分。
4. **Apple 隐藏邮箱能收到我们的邮件**：`DEPLOY.md` 第 4.5 节 Apple 第 5 步（注册 `badie.rsvp`、`send.badie.rsvp`）。我们的邮件都有 DKIM 签名，满足 Apple 的要求。
5. （可选）**网站和 App 共用保存的密码**：需要 Team ID，要做时告诉我，我加好配置后填一个 Team ID 就生效。

## 3. 构建和 TestFlight

1. Xcode 顶部设备选 **Any iOS Device (arm64)** → Product → **Archive** → 弹出的 Organizer 里 Distribute App → **App Store Connect** → Upload。
   - 版本号 1.0；每上传一次，Build 号（`CURRENT_PROJECT_VERSION`）要加 1。
   - 已经设置了“只用系统自带的 HTTPS 加密”（`ITSAppUsesNonExemptEncryption = NO`），上传后不会再问出口合规。
   - 隐私清单（`PrivacyInfo.xcprivacy`）已经带上：不追踪用户，只用到 UserDefaults 存本 App 的设置。
2. 上传后 10～30 分钟出现在 App Store Connect → TestFlight。
3. **内部测试**（你自己和最多 100 个 App Store Connect 成员，不用审核）：手机装 TestFlight App 安装，按第 6 节逐项试。
4. **外部测试**（可选，最多 1 万人，用邮箱或公开链接邀请）：每个版本的第一个 Build 要过 Beta 审核（一般几小时到一两天），要填测试说明和反馈邮箱（`support@badie.rsvp`）。Build 90 天后过期。

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

**Pricing and Availability**：Free；国家和地区先选美国（以后再加）。

**版本页（1.0）**
- 截图：iPhone 6.9 英寸（1320 × 2868）和 6.3 英寸（1206 × 2622）各一组最稳，每组 1～10 张，PNG 不能带透明通道。只上 iPhone，不用 iPad 截图。
- Description、Keywords、Support URL `https://badie.rsvp/contact/`、Marketing URL `https://badie.rsvp`、Privacy Policy URL `https://badie.rsvp/privacy/`、Copyright `2026 你的名字`。
- Build：选第 3 步上传的 Build。
- **App Review Information**：
  - 演示账号的邮箱和密码（第 0 步建的），勾 Sign-in required。
  - 联系人：你的名字、电话、邮箱（只给审核员看）。
  - Notes（英文写给审核员）示例：
    > Badie helps badminton players find partners at their level and courts nearby. Sign in with the demo account (email + password). To test matching, open Play, pick a time and courts; a match needs a second player, so the demo account already has a past game and a friend. Report and block: open any player profile → Report / Block. Account deletion: Settings → Delete account (Sign in with Apple accounts are revoked through Apple’s REST API). Location is only used to show courts nearby and is not stored.

## 5. 提交审核和上架

1. 版本页右上角 **Add for Review → Submit**。Apple 说 90% 在 48 小时内审完；2026 年的实际记录多数在一天内（年初有过一两周的积压）。第一次提交通常比更新慢，每次被拒都重新排队。
2. 发布方式建议选 **Manually release**：审核通过后你自己点发布，可以先在 TestFlight 再确认一遍。
3. 被拒了：在 App Store Connect 的 Resolution Center 回复或改了重新提交。常见原因和对应情况：
   - 1.2 用户内容：要有过滤、举报、屏蔽、联系方式，协议里写明零容忍（**过滤还没做，见第 0 步**）。
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
- 附近球馆（允许 / 拒绝定位两种情况）、约球、聊天、举报、屏蔽。
- 设置 → 联系我们能打开邮件；设置 → 注销账号能走完，Apple 登录的账号注销后在 iPhone 设置 → Apple ID → 使用 Apple 登录 里消失。

## 参考

- 注册：https://developer.apple.com/programs/enroll/ ，D-U-N-S：https://developer.apple.com/help/account/membership/D-U-N-S/
- 构建要求：https://developer.apple.com/news/upcoming-requirements/
- 审核规则：https://developer.apple.com/app-store/review/guidelines/
- 隐私标签：https://developer.apple.com/app-store/app-privacy-details/
- 年龄分级：https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/
- 截图尺寸：https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- DSA 商家声明：https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- TestFlight：https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- 注销账号：https://developer.apple.com/support/offering-account-deletion-in-your-app/
- 审核时长（实际记录）：https://www.runway.team/appreviewtimes
