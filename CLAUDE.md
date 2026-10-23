# Badie

免费的羽毛球找搭子 App：网站 https://badie.rsvp（Astro + React，`web/`）、iPhone App（SwiftUI，`Badie-iOS/`）、后端 Supabase（`supabase/`）。

## 和用户合作

- **用中文回复**。话要短，给推荐，不要列一长串选项。
- **说“推到 main”才推 main**，平时只推自己的开发分支。不开 PR，除非用户要。
- **对外的动作先问**：上传 TestFlight、动用户的 Apple / Google / Supabase 账号、发帖。
- **密钥不进聊天、不进仓库**：让用户自己填到 GitHub Secrets、Supabase 或 Vault。仓库是公开的：CI 里不打印密钥，也不打印签名证书名（里面有真名）；数据库备份不能传成 Actions 产物；前端不放 `sb_secret_` 开头的密钥。
- **不在任何地方写用户的私人邮箱**。仓库里不写模型名。
- **依赖版本写死**，用发布满两周的版本。
- **不爬商业平台**，不绕过反爬。
- **用户对调研的要求**：分辨营销和事实；不能只看官方说法，更要看真实用户的反馈（比如社交媒体）。科研论文例外，有论文支持可以加分。也不要过于悲观：没有论文，但产品被广泛认可，也算合理。

## 产品和文案

- **App 里少写解释**：一屏一句话。为什么做、怎么用这类说明放在网站的关于页和商店页。
- 对外口径以 `Badie-iOS/docs/STORY.md` 为准，只说做到了的事。
- 文字风格（10 种语言）按 `Badie-iOS/docs/VOICE.md`：平实、克制、具体，不用感叹号和表情。
- 宣传交接说明在 `Badie-iOS/docs/MARKETING_BRIEF.md`。
- 部署、密钥和第三方设置见 `Badie-iOS/docs/DEPLOY.md`，上架流程见 `Badie-iOS/docs/APP_STORE.md`。

## 开发

- **网站**（在 `web/` 下运行）：
  - 改完先跑 `npm test` 和 `npx astro check`。
  - 界面文字的英文原文就是 key，9 种语言的译文在 `src/app/locales/*.json`。测试会检查每种语言都齐。
  - 中文版静态页面（`/zh/…`）在构建时翻译，见 `src/lib/static-i18n.ts`。
- **端到端测试**（`web/tests/*.e2e.mjs`）：需要本机的 Supabase（`supabase start`），网站要按本机 Supabase 的地址构建。
- **iOS**：只能在 CI（GitHub Actions 的 macOS）上编译和测试。xcstrings 的格式是 `json.dumps(d, ensure_ascii=False, indent=2, separators=(",", " : "))`，key 排序。
- **数据库**：迁移放在 `supabase/migrations/`，pgTAP 测试放在 `supabase/tests/`。

## 省 token

- 只读需要的几行，命令尽量合并成一次。
- 能用数字检查的就不截图。
- 搜索时排除 `node_modules` 和 `dist`。
- 等 CI 用一个后台脚本，不要一次次手动查。
- 一个话题做完就开新会话。
