# 上线步骤：Supabase + Cloudflare

> 按顺序做。**任何密钥、密码都不要发到聊天里**，直接填进 GitHub：仓库 → Settings → Secrets and variables → Actions。
> 本仓库是公开的：Secrets 安全，但 Actions 日志和产物任何人都能看，所以不在 CI 里打印密钥，也不把数据库备份传成产物。

## 填到 GitHub 的值一览

| 名字 | 放在 | 来自 |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | Secrets | Supabase 账号 → Access Tokens |
| `SUPABASE_DB_PASSWORD` | Secrets | 建 Supabase 项目时生成的数据库密码 |
| `CLOUDFLARE_API_TOKEN` | Secrets | Cloudflare → My Profile → API Tokens |
| `CLOUDFLARE_ACCOUNT_ID` | Secrets | Cloudflare → Workers & Pages → Account Details |
| `SUPABASE_PROJECT_REF` | Variables | 项目网址 `supabase.com/dashboard/project/<这一段>` |
| `SUPABASE_URL` | Variables | `https://<project ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Variables | Project Settings → API Keys → Publishable key（`sb_publishable_…`，可以公开） |
| `SITE_URL` | Variables | `https://badie.rsvp` |
| `TURNSTILE_SITE_KEY` | Variables | Cloudflare → Turnstile 的 Site Key（可以公开） |

**Secret key（`sb_secret_…`）不需要放进 GitHub，也绝不能进前端。**

## 1. Cloudflare 账号和域名

1. 注册 Cloudflare（免费计划）。
2. Domain Registration → Register Domains，买域名（按成本价，没有加价）。注意：在 Cloudflare 买的域名只能用 Cloudflare 的 DNS。
3. My Profile → API Tokens → Create Token → Create Custom Token：权限选 **Account → Cloudflare Pages → Edit**，存为 Secret `CLOUDFLARE_API_TOKEN`。
4. Workers & Pages 页面右侧 Account Details 里复制 Account ID，存为 Secret `CLOUDFLARE_ACCOUNT_ID`。
5. Variables 里加 `SITE_URL`。

## 2. Supabase 项目

1. 注册 Supabase，新建 organization（Free）和项目 `badie`。
2. **Region 选 West US (North California)，`us-west-1`，建好后不能改。**
3. 数据库密码点 Generate，存进密码管理器，再存为 Secret `SUPABASE_DB_PASSWORD`。
4. 建项目页面里 Data API 保持开启；“Automatically expose new tables” 不勾也可以（迁移里已经显式授权）。
5. 账号头像 → Access Tokens → Generate new token，存为 Secret `SUPABASE_ACCESS_TOKEN`。
6. Variables 里加 `SUPABASE_PROJECT_REF`、`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。

## 3. 发验证码的邮件（必须做，否则用户收不到验证码）

Supabase 自带的邮件只发给项目成员、每小时 2 封，而且 2026-06 之后的免费新项目不能改模板（默认模板里没有验证码）。所以要配自己的发信服务：

1. 注册 Resend，先用免费版（每月 3,000 封、**每天 100 封，登录验证码和约球通知共用**）。大多数人用 Google / Apple 登录、不发邮件；邮箱验证码只在新设备第一次登录时发（之后一直保持登录），所以起步阶段主要的量是约球通知。在 Resend 后台看每天发了多少，接近每天 70 封时升级 Pro（$20/月，每月 5 万封），或者先给 App 加推送通知把一部分邮件换掉。
   - 为什么选 Resend（2026-10 调研）：两条发信路径（验证码 SMTP、通知的批量 API）都已经在用；不用审核、当天能发；5 万～10 万封每月的价格在免审核的服务里最低。风险是违规（退信超过 4%、投诉超过 0.08%）会被直接停号，所以注册时邮箱填错的要少。
   - 备用：Postmark（独立送达测试排第二、用户口碑最好，但 5 万封以上贵约 3 倍）。建议先注册好放着（人工审核，一般 24 小时内），出问题时 Supabase 的 SMTP 改成 `smtp.postmarkapp.com`、端口 587，几分钟就能切。
   - 以后每月超过 10 万封再考虑 Amazon SES（每 10 万封约 $10，但要申请生产权限，常被拒）。Cloudflare 的发信服务还在测试版、没有批量接口，暂不考虑。
2. Domains → Add Domain，填 `badie.rsvp`（Resend 的 SPF/MX 放在 `send.badie.rsvp` 子域，不影响根域收信）；选 Cloudflare 自动配置，或按提示手动加记录（SPF、DKIM、MX，全部设成 DNS only），再加：
   - DMARC：`_dmarc.badie.rsvp` TXT `v=DMARC1; p=none; rua=mailto:dmarc@badie.rsvp`；2～4 周报告干净后改成 `p=quarantine`。
   - 根域 SPF：`badie.rsvp` TXT `v=spf1 include:amazonses.com ~all`（Apple 隐藏邮箱的转发要求注册的域名有 SPF，见 4.5）。如果开了 Cloudflare Email Routing，和它的 `include:_spf.mx.cloudflare.net` 合成一条。
   - 等 Resend 显示 Verified。
3. API Keys → Create（Sending access），**直接粘到下一步，不用存进 GitHub**。
4. Supabase → Authentication → Emails → SMTP Settings：开启；Host `smtp.resend.com`，Port `465`，Username `resend`，Password 填 Resend API key；发件人 `noreply@badie.rsvp`，名称 `Badie`。
5. Authentication → Emails → Templates：**Magic Link 和 Confirm signup 两个模板**都换成 `supabase/templates/otp.html` 的内容，主题 `Your Badie sign-in code`。
6. Authentication → Sign In / Providers → Email：Email OTP length 设 6，过期时间 3600 秒。
7. Authentication → Rate Limits：发信上限先设每小时 30 封左右（开了自定义 SMTP 后的默认值），用户多了再调高。
8. 上线前用 Gmail、Outlook、iCloud、QQ 邮箱、163 各收一次验证码，看是否进垃圾箱（QQ 邮箱按发信 IP 限流，量大时可能延迟）。

## 3.5 防机器人与滥用

1. **人机验证（Turnstile，免费）**：Cloudflare → Turnstile → Add widget：Hostname 填 `badie.rsvp`，Widget mode 选 **Managed**。
   - Site Key 存为 Variable `TURNSTILE_SITE_KEY`，推一次 main 让网站带上验证框。
   - **网站部署后**再到 Supabase → Authentication → Attack Protection → Enable CAPTCHA protection，选 Turnstile，填 Secret Key。顺序反过来会让所有人登录失败。
   - iOS App 不用另外配置：登录时用看不见的网页视图打开 `https://badie.rsvp/captcha/`，用的是同一个 Site Key。打开 CAPTCHA 之前装的旧版 App 会发不出验证码，要更新。
2. Supabase → Authentication → Rate Limits：发验证码邮件每小时 30 封左右；每个 IP 每 5 分钟登录 / 注册请求 30 次、验证码校验 30 次（默认值即可）。
3. Cloudflare → badie.rsvp → Security → Bots：打开 **Bot Fight Mode**；AI Crawl Control 里拦截 AI 训练爬虫，放行搜索引擎和 AI 搜索（与 robots.txt 一致）。
4. 网站已经带上：内容安全策略（只允许自身脚本和 Turnstile）、禁止被嵌入 iframe、`/app/` 不进搜索引擎；数据库里所有写操作走带检查的函数，每人每天最多加 3 家球馆。

## 4. 登录相关网址

Authentication → URL Configuration：

- Site URL：`https://badie.rsvp`
- Redirect URLs（Google / Apple 登录完跳回来的地址，只放这几个）：
  - `https://badie.rsvp/signin/**`（网页；登录后回到原来想去的页面）
  - `badie://auth-callback`（iOS App）
  - `http://localhost:4321/**`（本地开发）

## 4.5 Google / Apple 登录

网页和 App 只在 Supabase 里开了对应登录方式后才显示按钮，所以可以一个一个来，没配好之前不会出错。**密钥都直接填进 Google / Apple / Supabase 的后台，不要发到聊天里，也不要提交到仓库。**

**Google（网页和 iOS 共用一个网页客户端）**

1. Google Cloud Console → 新建项目 `Badie` → Google Auth Platform：
   - Branding：名字 Badie、Logo、首页 `https://badie.rsvp`、隐私政策和用户协议的网址、授权域名 `badie.rsvp`。
   - Audience：External，然后 Publish。
   - Data Access（Scopes）：只要 `openid`、`userinfo.email`、`userinfo.profile`（多要敏感权限会触发 Google 审核）。
2. Clients → Create client → Web application：
   - Authorized redirect URIs：`https://yeffnjdpjejlplqryjfx.supabase.co/auth/v1/callback`
3. 复制 Client ID 和 Client secret，填到 Supabase → Authentication → Sign In / Providers → Google，打开 Enable。“Skip nonce check” 保持关闭。
   - iOS 不用另建客户端：App 在系统浏览器里走同一个网页登录（和 Safari 共用 Google 登录状态），不装 Google 的 SDK。
   - 没有自定义域名时，Google 的确认页上显示的是 `yeffnjdpjejlplqryjfx.supabase.co`；以后想显示 badie.rsvp，需要 Supabase 的自定义域名（付费功能）。

**Apple（iOS 原生 + 网页）**

1. Apple Developer → Certificates, Identifiers & Profiles → Identifiers：
   - App ID `com.badie.app`：勾上 **Sign in with Apple**（代码里已经带了这个 entitlement，Xcode 自动签名时会同步）。
   - 新建 Services ID `com.badie.web`（网页登录用）：勾上 Sign in with Apple → Configure：Primary App ID 选 `com.badie.app`，Domains 填 `yeffnjdpjejlplqryjfx.supabase.co`，Return URLs 填 `https://yeffnjdpjejlplqryjfx.supabase.co/auth/v1/callback`。
2. Keys → 新建 Key，勾 Sign in with Apple（关联 `com.badie.app`），下载 `.p8`（**只能下载一次**，存进密码管理器），记下 Key ID 和右上角的 Team ID。
3. Supabase → Authentication → Sign In / Providers → Apple：打开 Enable；
   - Client IDs：`com.badie.web,com.badie.app`（网页的 Services ID 放第一个）。
   - Secret Key：在自己电脑上运行 `node supabase/scripts/apple_client_secret.mjs <Team ID> <Key ID> com.badie.web <.p8 路径>`（私钥不离开本机），把输出粘进去。**这个密钥最长 6 个月就过期，Supabase 不会自动换**：脚本会打印到期日，在日历里设个提前一个月的提醒，到时重新运行填回去，否则网页的 Apple 登录会失效（iOS 原生登录不受影响）。
4. 注销时撤销 Apple 授权（Apple 要求，Supabase 不会代办）：Supabase → Edge Functions → Secrets 加三项：
   - `APPLE_TEAM_ID`、`APPLE_KEY_ID`，以及 `APPLE_PRIVATE_KEY`（粘 `.p8` 文件的全部内容）。
   - 函数 `apple-revoke` 由 “Supabase deploy” 自动部署。用户在 App 里注销时会再用 Apple 确认一次，用拿到的授权码撤销；在网页上注销的会提示他们去 Apple 账户设置里自己停用。
5. Apple 隐藏邮箱（用户选了“隐藏我的邮箱”时，地址是 `…@privaterelay.appleid.com`）：Certificates, Identifiers & Profiles → Services → **Sign in with Apple for Email Communication** → 注册 `badie.rsvp` 和 `send.badie.rsvp`（或者具体地址 `noreply@badie.rsvp`、`games@badie.rsvp`），并打开投递失败通知。不注册的话，发给这些用户的验证码和约球通知会被 Apple 退回。每个转发地址每天最多收 100 封。

账号合并：同一个邮箱先用验证码注册、后来用 Google 登录，会自动合成一个账号（Google 的邮箱是验证过的）。Apple 选了隐藏邮箱的是另一个账号，这是 Apple 的设计。

## 5. 第一次部署

把代码推到 `main`：

- “Supabase deploy”：先预览变更，再推迁移，然后用 psql 同步场馆目录（`seed.sql`）。注意 `supabase db push --include-seed` 只在第一次执行 seed，之后文件变了也只更新记账的 hash，所以同步要显式执行。
- “Web CI”：构建网站，第一次会自动创建 Cloudflare Pages 项目 `badie` 并部署。

## 6. 绑定域名

Workers & Pages → badie → Custom domains → Set up a domain：先加 `badie.rsvp`，再加 `www.badie.rsvp`。**先在这里加，不要先手动建 DNS 记录**（会出 522 错误）。然后 Rules → Redirect Rules 用模板 “Redirect from WWW to root” 把 www 301 到根域名。`.rsvp` 强制 HTTPS，Pages 自带证书，不用额外设置。

## 7. 把自己设为管理员

在网站上用自己的邮箱登录一次，然后在 Supabase → SQL Editor 运行：

```sql
insert into public.admin_users (user_id, role)
select id, 'owner' from auth.users where email = '你的邮箱';
```

## 8. 约球通知邮件

匹配到人、约成、取消、错过确认时会发邮件（网页没有推送，用户不在线时靠邮件）。数据库每分钟检查一次，Vault 里有 Resend 的 key 才发：

1. Resend → API Keys → Create，名字 `badie-notifications`，权限 Sending access，域名选 `badie.rsvp`。
2. Supabase → Integrations → Vault → Add new secret：Name 填 `resend_api_key`，Secret 粘 key。**不要在 SQL Editor 里写 key**（会留在查询历史里）。
3. 发件人是 `games@badie.rsvp`，Resend 验证过根域名就能用。免费额度每天 100 封；超了 Resend 会拒发，匹配本身不受影响。

通知和邮件用收件人的界面语言（资料里的 `locale`，网页/App 换语言时自动更新），时间按球馆当地时间。新增通知文字时，在迁移里给 `notification_texts` 补上 9 种语言的译文（测试会检查每种语言齐全、占位符一致）。

## 9. 上线检查

- 用一个**从没用过的邮箱**走一遍：收验证码 → 登录 → 填昵称 → 定级问卷 → 附近球馆 → 收藏。
- 开了 Google / Apple 后各登录一次（网页和 iOS 都试），再用 Apple 登录的测试账号在 App 里注销一次，确认能正常走完。
- 用两个邮箱各发一个同时段、同球馆的约球请求：应该马上配上、两边都收到邮件，都确认后出现在 My games。
- 网站各页面打开正常，刷新 `/courts/`、`/games/` 不报 404，旧地址 `/app/games/` 会跳到 `/games/`。
- “Supabase keep-alive” 每天自动运行，防止免费项目因 7 天无活动被暂停。

## 以后要补的

- **备份**：免费版没有自动备份。要做每日 `pg_dump` 到私有存储（如 Cloudflare R2），不能传成公开仓库的 Actions 产物。
- Apple 网页登录的 Secret Key 每 6 个月要重新生成一次（见 4.5 第 3 步），记得设提醒。
