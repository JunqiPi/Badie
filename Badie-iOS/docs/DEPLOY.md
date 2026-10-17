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

1. 注册 Resend（免费：每月 3,000 封、每天 100 封）。
2. Domains → Add Domain，填 `badie.rsvp`（Resend 的 SPF/MX 放在 `send.badie.rsvp` 子域，不影响根域收信）；选 Cloudflare 自动配置，或按提示手动加记录（SPF、DKIM、MX），再加一条 DMARC：`_dmarc.badie.rsvp` TXT `v=DMARC1; p=none;`。等 Resend 显示 Verified。
3. API Keys → Create（Sending access），**直接粘到下一步，不用存进 GitHub**。
4. Supabase → Authentication → Emails → SMTP Settings：开启；Host `smtp.resend.com`，Port `465`，Username `resend`，Password 填 Resend API key；发件人 `noreply@badie.rsvp`，名称 `Badie`。
5. Authentication → Emails → Templates：**Magic Link 和 Confirm signup 两个模板**都换成 `supabase/templates/otp.html` 的内容，主题 `Your Badie sign-in code`。
6. Authentication → Sign In / Providers → Email：Email OTP length 设 6，过期时间 3600 秒。
7. Authentication → Rate Limits：发信上限调到每小时 30 封左右。

## 3.5 防机器人与滥用

1. **人机验证（Turnstile，免费）**：Cloudflare → Turnstile → Add widget：Hostname 填 `badie.rsvp`，Widget mode 选 **Managed**。
   - Site Key 存为 Variable `TURNSTILE_SITE_KEY`，推一次 main 让网站带上验证框。
   - **网站部署后**再到 Supabase → Authentication → Attack Protection → Enable CAPTCHA protection，选 Turnstile，填 Secret Key。顺序反过来会让所有人登录失败。
2. Supabase → Authentication → Rate Limits：发验证码邮件每小时 30 封左右；每个 IP 每 5 分钟登录 / 注册请求 30 次、验证码校验 30 次（默认值即可）。
3. Cloudflare → badie.rsvp → Security → Bots：打开 **Bot Fight Mode**；AI Crawl Control 里拦截 AI 训练爬虫，放行搜索引擎和 AI 搜索（与 robots.txt 一致）。
4. 网站已经带上：内容安全策略（只允许自身脚本和 Turnstile）、禁止被嵌入 iframe、`/app/` 不进搜索引擎；数据库里所有写操作走带检查的函数，每人每天最多加 3 家球馆。

## 4. 登录相关网址

Authentication → URL Configuration：

- Site URL：`https://badie.rsvp`
- Redirect URLs：`https://badie.rsvp/app/**`、`http://localhost:4321/**`（以后接 Google / Apple 登录用）

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

## 8. 上线检查

- 用一个**从没用过的邮箱**走一遍：收验证码 → 登录 → 填昵称 → 附近球馆 → 收藏。
- 网站各页面、`/app/` 打开正常，刷新 `/app/courts/` 不报 404。
- “Supabase keep-alive” 每天自动运行，防止免费项目因 7 天无活动被暂停。

## 以后要补的

- **备份**：免费版没有自动备份。要做每日 `pg_dump` 到私有存储（如 Cloudflare R2），不能传成公开仓库的 Actions 产物。
- Google / Apple 登录；Apple 的网页登录密钥每 6 个月要换一次。
