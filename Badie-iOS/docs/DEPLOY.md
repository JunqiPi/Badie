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
| `VAPID_PUBLIC_KEY` | Variables | `node supabase/scripts/vapid_keys.mjs` 生成的浏览器推送公钥（可以公开，见 8.5） |

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
   - 如果生成时要选权限（scoped token），只选 badie 这个项目，并给：Project Settings、API Keys、API Key Secrets 读，**Edge Functions 读写**（部署服务器函数要用）。
   - 部署时报 `Missing required permission(s): edge_functions_write`，说明这把 token 没有 Edge Functions 读写：按上面重新生成一把，替换 GitHub 里的 Secret，再到 Actions → Supabase deploy → Run workflow。
6. Variables 里加 `SUPABASE_PROJECT_REF`、`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。

## 3. 登录方式和验证码邮件（必须做，否则注册收不到确认码）

Supabase 自带的邮件只发给项目成员、每小时 2 封，而且 2026-06 之后的免费新项目不能改模板（默认模板里没有验证码）。所以要配自己的发信服务：

登录方式：邮箱 + 密码（主要），Google / Apple（见 4.5），邮件验证码作为备用（没设过密码、或不想用密码的人）。

1. 注册 Resend，先用免费版（每月 3,000 封、**每天 100 封，注册确认码、重设密码、验证码登录和约球邮件共用**）。用密码、Google、Apple 登录都不发邮件；只有注册时发一封确认码、忘记密码时发一封重设码、有人选验证码登录时发一封；约球提醒主要靠推送，约球邮件要用户自己在设置里打开（默认关）。所以免费版应该能撑很久（每天新注册 100 人以内）。超了会自动换 Mailjet 发（见 3.1，再多 200 封）。在 Resend 后台看每天发了多少，两家经常都用满时再升级 Pro（$20/月，每月 5 万封）。
   - 为什么选 Resend（2026-10 调研）：两条发信路径（验证码 SMTP、通知的批量 API）都已经在用；不用审核、当天能发；5 万～10 万封每月的价格在免审核的服务里最低。风险是违规（退信超过 4%、投诉超过 0.08%）会被直接停号，所以注册时邮箱填错的要少。
   - 备用：Postmark（独立送达测试排第二、用户口碑最好，但 5 万封以上贵约 3 倍）。建议先注册好放着（人工审核，一般 24 小时内），出问题时 Supabase 的 SMTP 改成 `smtp.postmarkapp.com`、端口 587，几分钟就能切。
   - 以后每月超过 10 万封再考虑 Amazon SES（每 10 万封约 $10，但要申请生产权限，常被拒）。Cloudflare 的发信服务还在测试版、没有批量接口，暂不考虑。
2. Domains → Add Domain，填 `badie.rsvp`（Resend 的 SPF/MX 放在 `send.badie.rsvp` 子域，不影响根域收信）；选 Cloudflare 自动配置，或按提示手动加记录（SPF、DKIM、MX，全部设成 DNS only），再加：
   - DMARC：`_dmarc.badie.rsvp` 只能有一条 TXT（有两条等于没有）。用 Cloudflare 的 DMARC Management（免费）加的那条：`v=DMARC1; p=none; rua=mailto:…@dmarc-reports.cloudflare.net`，报告在 Cloudflare 面板里看，不会往邮箱里塞 XML。想同时发到邮箱，就在同一条的 rua 后面加 `,mailto:support@badie.rsvp`，别新建第二条。2～4 周报告干净后改成 `p=quarantine`。
   - SPF：Resend 的 SPF 在 `send.badie.rsvp` 上（加域名时自动配好，不用动根域）。根域 `badie.rsvp` 的 SPF 用第 6.5 节 Cloudflare Email Routing 自动加的那条即可。
   - 等 Resend 显示 Verified。
3. API Keys → Create（Sending access），**直接粘到下一步，不用存进 GitHub**。
4. Supabase → Authentication → Emails → SMTP Settings：开启；Host `smtp.resend.com`，Port `465`，Username `resend`，Password 填 Resend API key；发件人 `noreply@badie.rsvp`，名称 `Badie`。
5. Authentication → Emails → Templates：
   - **Magic Link 和 Confirm signup** 换成 `supabase/templates/otp.html` 的内容，主题 `Your Badie sign-in code`。
   - **Reset Password** 换成 `supabase/templates/recovery.html` 的内容，主题 `Reset your Badie password`（邮件里是 6 位码，在网页 / App 里输入，不用点链接）。
6. Authentication → Sign In / Providers → Email：
   - **Confirm email 保持打开**（默认）：注册要输入邮件里的确认码，别人不能拿你的邮箱注册。
   - Minimum password length 设 **8**；Password requirements 选 **No required characters**（不强制大小写、符号，按 NIST 的建议；网页和 App 会另外查这个密码是否在泄露的密码库里，免费版没有 Supabase 自带的那项检查）。
   - Email OTP length 设 6，过期时间 3600 秒。
   - Secure password change 保持关闭（已登录的人在设置里直接改密码；忘记密码走邮件里的码）。
7. Authentication → Rate Limits：发信上限先设每小时 30 封左右（开了自定义 SMTP 后的默认值），用户多了再调高。
8. 上线前用 Gmail、Outlook、iCloud、QQ 邮箱、163 各收一次验证码，看是否进垃圾箱（QQ 邮箱按发信 IP 限流，量大时可能延迟）。

## 3.1 发信备份：Resend 额度用完自动换 Mailjet（免费）

登录验证码和约球邮件都由服务器函数 `send-email` 发：先用 Resend（每天 100 封）；被拒（额度用完、出错、超时）就换 Mailjet（每天 200 封、每月 6,000 封）。合起来每天约 300 封，两家经常都用满了再升级 Resend Pro。

- Mailjet 超过每天 200 封不会报错，而是排到第二天发（验证码就没用了），所以它只能放在后面当备份。
- Mailjet 免费版的邮件底部可能带 Mailjet 标识；有用户反映新账号被突然暂停审核（多见于退信多的账号），所以只当备份，不当主力。

1. Mailjet → Account settings → **Senders & Domains → Add domain** → 填 `badie.rsvp`。按提示到 Cloudflare DNS 加一条验证用的 TXT 记录，回 Mailjet 点 Check now。
2. 同一页点 **Authenticate this domain (SPF/DKIM)**，把它给的记录加到 Cloudflare（全部 DNS only）：
   - DKIM：照抄它给的主机名和值。
   - SPF：根域只能有一条 SPF。**不要新建**，编辑 6.5 里 Email Routing 加的那条，改成 `v=spf1 include:_spf.mx.cloudflare.net include:spf.mailjet.com ~all`。
   - 等 SPF 和 DKIM 都变绿。
3. Mailjet → Account settings → **API Key Management**：复制 API Key 和 Secret Key（直接粘到第 5 步，不要发到聊天里）。
4. Resend → API Keys → Create：名字 `badie-functions`，权限 Sending access，域名 `badie.rsvp`。
5. Supabase → Edge Functions → Secrets，加三条：`RESEND_API_KEY`、`MAILJET_API_KEY`、`MAILJET_SECRET_KEY`。
6. 确认 “Supabase deploy” 已经部署了 `send-email`（Edge Functions 列表里能看到它）。
7. Supabase → Authentication → **Hooks** → Add hook → **Send Email hook**：类型选 HTTPS，URL 填 `https://yeffnjdpjejlplqryjfx.supabase.co/functions/v1/send-email`，点 **Generate secret**，复制这串 `v1,whsec_…`，点 Create；马上到 Edge Functions → Secrets 加 `SEND_EMAIL_HOOK_SECRET` 填这串。
8. 用一个没注册过的邮箱注册一次，能收到验证码就好。哪家发不出去会记在 Edge Functions → send-email → Logs 里。

开了 Hook 后，第 3 节的 SMTP 就不用了，但别删：Hook 出问题时在 Authentication → Hooks 里把它关掉，就自动回到 SMTP（只用 Resend）。

## 3.5 防机器人与滥用

1. **人机验证（Turnstile，免费）**：Cloudflare → Turnstile → Add widget：Hostname 填 `badie.rsvp`，Widget mode 选 **Managed**。
   - Site Key 存为 Variable `TURNSTILE_SITE_KEY`，推一次 main 让网站带上验证框。
   - **网站部署后**再到 Supabase → Authentication → Attack Protection → Enable CAPTCHA protection，选 Turnstile，填 Secret Key。顺序反过来会让所有人登录失败。
   - iOS App 不用另外配置：登录时用看不见的网页视图打开 `https://badie.rsvp/captcha/`，用的是同一个 Site Key。打开 CAPTCHA 之前装的旧版 App 会发不出验证码，要更新。
2. Supabase → Authentication → Rate Limits：发验证码邮件每小时 30 封左右；每个 IP 每 5 分钟登录 / 注册请求 30 次（也挡住撞库、猜密码）、验证码校验 30 次（默认值即可）。密码登录、注册、重设密码同样要过 Turnstile。
3. Cloudflare → badie.rsvp → Security → Bots：打开 **Bot Fight Mode**；AI Crawl Control 里拦截 AI 训练爬虫，放行搜索引擎和 AI 搜索（与 robots.txt 一致）。
4. 网站已经带上：内容安全策略（只允许自身脚本和 Turnstile）、禁止被嵌入 iframe、`/app/` 不进搜索引擎；数据库里所有写操作走带检查的函数，每人每天最多加 3 家球馆。

## 4. 登录相关网址

Authentication → URL Configuration：

- Site URL：`https://badie.rsvp`
- Redirect URLs（Google / Apple 登录完跳回来的地址，只放这几个）：
  - `https://badie.rsvp/signin/**`（网页；登录后回到原来想去的页面）
  - `badie://auth-callback`（iOS App）
  - `http://localhost:4321/**`（本地开发）

不改的话，Google 登录完会跳到 `http://localhost:3000/?code=…`（Supabase 默认的 Site URL）。

## 4.5 Google / Apple 登录

网页和 App 只在 Supabase 里开了对应登录方式后才显示按钮，所以可以一个一个来，没配好之前不会出错。**密钥都直接填进 Google / Apple / Supabase 的后台，不要发到聊天里，也不要提交到仓库。**

**Google（网页和 iOS 共用一个网页客户端，免费）**

先把代码推到 main（按钮的代码要在线上），再按顺序做：

1. 打开 console.cloud.google.com → 顶部项目选择 → New Project，名字 `Badie` → Create，切换到这个项目。
2. 左侧菜单 Google Auth Platform → Get started：
   - App name `Badie`，User support email 选你的邮箱 → Next；
   - Audience 选 **External** → Next；
   - Contact information 填你的邮箱 → Next → 勾选同意 → Create。
3. Branding（品牌）：
   - App home page `https://badie.rsvp`
   - Privacy policy `https://badie.rsvp/privacy/`、Terms of service `https://badie.rsvp/terms/`（这两页随代码一起上线）
   - Authorized domains：加 `badie.rsvp` 和 `yeffnjdpjejlplqryjfx.supabase.co`
   - Logo 先不传：传了 Google 要做品牌审核（几个工作日），不传也能用。
4. Data Access → Add or remove scopes：只勾 `openid`、`.../auth/userinfo.email`、`.../auth/userinfo.profile` → Update → Save。只要这三个基本权限就不需要 Google 审核。
5. Audience → Publishing status 点 **Publish app** → Confirm（还在 Testing 时只有测试名单里的人能登录）。
6. Clients → Create client：
   - Application type **Web application**，名字 `Badie web`
   - Authorized redirect URIs 加 `https://yeffnjdpjejlplqryjfx.supabase.co/auth/v1/callback`
   - Create，弹窗里复制 Client ID 和 Client secret（secret 之后看不到原文，可以重新生成）。
7. Supabase → Authentication → Sign In / Providers → Google：打开 Enable，粘 Client ID（Client IDs 一栏）和 Client Secret，“Skip nonce check” 保持关闭 → Save。
8. 确认第 4 节的 Redirect URLs 已经填好（`https://badie.rsvp/signin/**`、`badie://auth-callback`）。
9. 打开 `https://badie.rsvp/signin/`，应该出现“Continue with Google”，用自己的 Google 账号登录一次试试。

说明：
- iOS 不用另建客户端：App 在系统浏览器里走同一个网页登录（和 Safari 共用 Google 登录状态），不装 Google 的 SDK。
- App 里只有 Apple 也开了才显示 Google（App Store 审核规则 4.8：有第三方登录就必须同时提供能隐藏邮箱的登录）。只开 Google 时，网页有 Google 按钮，App 里没有。
- 没有自定义域名时，Google 的确认页上显示的是 `yeffnjdpjejlplqryjfx.supabase.co`；以后想显示 badie.rsvp，需要 Supabase 的自定义域名（付费功能）。

**Apple（iOS 原生 + 网页）**

需要 Apple Developer Program（每年 $99；把 App 上架 App Store、用 TestFlight 本来就要这个账号，Apple 登录本身不另收费）。上架前再配就行。

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

## 6.5 联系邮箱 support@badie.rsvp

隐私政策和用户协议里写的联系邮箱是 `support@badie.rsvp`，用 Cloudflare 免费转发到你自己的邮箱（你的邮箱不会出现在网站上）：

1. Cloudflare 账户首页（不是 badie.rsvp 的域名页）左边栏 → Compute → Email Service → Email Routing → **Onboard Domain** → 选 `badie.rsvp` → Done（会自动加 MX 和 SPF 记录）。没做这一步之前看不到 Routing Rules。
2. Destination Addresses 加你的邮箱，去邮箱里点 Verify email address。
3. 选 `badie.rsvp` → **Routing Rules** → Create routing rule：Email pattern `support`，Action 选 Send to an email → 你的邮箱 → Save。用别的邮箱给 support@ 发一封试试（同一个邮箱自己发给自己可能看不到）。
4. Cloudflare 会自动给根域加一条 SPF（`v=spf1 include:_spf.mx.cloudflare.net ~all`），照它的提示添加即可；Resend 的 SPF 在 `send.badie.rsvp` 上，互不影响。根域只能有一条 SPF，以后别再手动加第二条。

## 7. 把自己设为管理员

在网站上用自己的邮箱登录一次，然后在 Supabase → SQL Editor 运行：

```sql
insert into public.admin_users (user_id, role)
select id, 'owner' from auth.users where email = '你的邮箱';
```

## 8. 约球邮件（用户自己打开，默认关）

约球提醒主要靠推送（见 8.5）。在「设置」里打开了「约球消息也发邮件」的人，匹配到人、约成、取消、错过确认时还会收到邮件，开着推送也照发。数据库每分钟检查一次，交给 `send-email` 函数发（和登录验证码一样，Resend 不行就换 Mailjet）。要配齐两样才发：

1. 3.1 里的发信服务密钥（`RESEND_API_KEY`，有 Mailjet 的话再加两条）。
2. 8.5 第 1 步的暗号和地址（Vault 里的 `push_secret`、`project_url`，Edge Functions 的 `PUSH_SECRET`），和推送共用。

发件人是 `games@badie.rsvp`，两家验证过根域名就能用。两家都发不出去时这一批邮件就不发了，匹配本身不受影响。Vault 里以前的 `resend_api_key` 已经不用，可以删掉。**任何 key 都不要在 SQL Editor 里写**（会留在查询历史里）。

通知和邮件用收件人的界面语言（资料里的 `locale`，网页/App 换语言时自动更新），时间按球馆当地时间。新增通知文字时，在迁移里给 `notification_texts` 补上 9 种语言的译文（测试会检查每种语言齐全、占位符一致）。

## 8.5 推送通知（免费，主要的提醒方式）

新通知马上推送到 App 和浏览器。下面没配齐之前不会推送，也不会出错；用户仍能在 App 的通知列表里看到。浏览器收不到推送（拒绝过或不支持）、又没开邮件的人，约球页会提示去设置里打开约球邮件。

1. **暗号和地址**（让数据库叫推送服务）：在自己电脑上运行 `openssl rand -hex 32` 生成一串随机字符。
   - Supabase → Integrations → Vault → Add new secret：`push_secret` 填这串字符；再加一条 `project_url` 填 `https://yeffnjdpjejlplqryjfx.supabase.co`。
   - Supabase → Edge Functions → Secrets：`PUSH_SECRET` 填同一串字符。
2. **iPhone App（Apple 推送）**：
   - Apple Developer → Identifiers → `com.badie.app`：勾上 **Push Notifications**（代码里已经带了这个 entitlement）。
   - 推送要用 Apple 的密钥：4.5 里建的那把 Key 如果也勾了 Apple Push Notifications service (APNs)，就不用再填；否则新建一把只勾 APNs 的 Key，把 Key ID 和 `.p8` 内容填到 Edge Functions → Secrets 的 `APNS_KEY_ID`、`APNS_PRIVATE_KEY`（`APPLE_TEAM_ID` 共用）。
   - 用户第一次发出约球请求时，App 会问能不能发通知。
3. **浏览器（Web Push）**：在自己电脑上运行 `node supabase/scripts/vapid_keys.mjs`：
   - 公钥 `VAPID_PUBLIC_KEY`：填到 GitHub → Variables（网站构建用），也填到 Edge Functions → Secrets。
   - 私钥 `VAPID_PRIVATE_KEY`：只填到 Edge Functions → Secrets。
   - 推一次 main 后，网页的「设置」里会出现「这台设备的通知」开关，发出约球请求后也会提示打开。iPhone 上的浏览器要先把 Badie 添加到主屏幕才能收推送（苹果的限制）。
4. 推送服务 `send-push`（和发信的 `send-email`）由 “Supabase deploy” 自动部署。

## 9. 上线检查

- 用一个**从没用过的邮箱**走一遍：邮箱 + 密码注册 → 收确认码 → 填昵称 → 定级问卷 → 附近球馆 → 收藏。退出后用密码登录（不应再收到邮件），再试一次“忘记密码？”。
- iPhone 上注册时，键盘上方应该出现“使用强密码”；之后登录时钥匙串用面容 ID 自动填入密码。
- 开了 Google / Apple 后各登录一次（网页和 iOS 都试），再用 Apple 登录的测试账号在 App 里注销一次，确认能正常走完。
- 配好推送后：电脑浏览器和 TestFlight 版 App 各打开一次通知，用另一个账号约同一时段同一球馆，两边应该马上收到推送；没打开约球邮件的账号**收不到邮件**。
- 其中一个账号在设置里打开「约球消息也发邮件」，再约一次：这个账号除了推送还会收到邮件，都确认后出现在 My games。
- 网站各页面打开正常，刷新 `/courts/`、`/games/` 不报 404，旧地址 `/app/games/` 会跳到 `/games/`。
- “Supabase keep-alive” 每天自动运行，防止免费项目因 7 天无活动被暂停。

## 以后要补的

- **备份**：免费版没有自动备份。要做每日 `pg_dump` 到私有存储（如 Cloudflare R2），不能传成公开仓库的 Actions 产物。
- Apple 网页登录的 Secret Key 每 6 个月要重新生成一次（见 4.5 第 3 步），记得设提醒。
