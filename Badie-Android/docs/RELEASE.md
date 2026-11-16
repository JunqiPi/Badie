# 安卓版：打包、签名、上架前的设置

给发版的人看。功能和进度在 `STATUS.md` 的“安卓版”，需求在 `docs/REQUIREMENTS.md`。

## 版本号

- **versionName**（给人看的，比如 `1.0.5`）：写在 `app/build.gradle.kts` 的 `defaultConfig` 里，发版前手动改，和 iPhone 对齐。
- **versionCode**（Play 用来比新旧，每次上传都要更大）：不用手改。发版工作流把它的**运行序号**传进来（`BADIE_VERSION_CODE`），每跑一次加 1，不会重复。本机构建是 1。
  - 为什么不写在构建文件里：忘了改就传不上去，还得再提交一次；运行序号是自动的。
  - 同一次运行点“重新运行”序号不变：要是那个包已经传过 Play，会被拒（重复的 versionCode），重新点 Run workflow 跑一个新的就行。
  - 以后要是改了工作流的文件名，序号会从 1 重新数，到时在 `android-release.yml` 里给序号加一个固定数（比如 `run_number + 1000`）。

## 签名

用 **Play 应用签名**：我们只管“上传密钥”（upload key），给用户装的包由 Google 用它保管的“应用签名密钥”重新签。上传密钥丢了可以在 Play 管理中心申请重置，应用签名密钥不会丢。

- 上传密钥库（`.jks`）和密码只放在用户自己的密码管理器和 GitHub Secrets 里，不进仓库（`.gitignore` 已经挡了 `*.jks`、`*.keystore`），不发到聊天里。
- 构建时从环境变量读（`app/build.gradle.kts`）：`BADIE_UPLOAD_KEYSTORE`（文件路径）、`BADIE_UPLOAD_STORE_PASSWORD`、`BADIE_UPLOAD_KEY_ALIAS`、`BADIE_UPLOAD_KEY_PASSWORD`。四个都有才签名，否则打出来的正式包不签名（本机检查用）。
- 工作流 `.github/workflows/android-release.yml`（只能手动运行）：先跑单元测试和 lint，再把 GitHub Secrets 里的 base64 解成临时文件、打签名的 AAB、确认签上了、删掉临时文件，把 AAB 和混淆映射表（`mapping.txt`）作为产物 `badie-release-aab` 上传（保留 30 天）。日志里不打印密钥和证书信息。

## 正式包里有什么不一样

- R8 压缩和混淆、去掉没用的资源。规则在 `app/proguard-rules.pro`（人机验证的 `BadieCaptcha.postMessage`、kotlinx.serialization、凭据管理器）。混淆后的崩溃堆栈靠映射表还原：映射表在 AAB 里，Play 会自己读。
- 连的是正式的 Supabase（`remote/SupabaseClient.kt` 的 `SupabaseConfig`，只有这一个地址）。安卓这边没有调试用的后端开关，也没有允许明文 HTTP 的网络配置，正式包里不会带进去。
- 本机检查正式包：`./gradlew :app:bundleRelease --max-workers=1`（不签名）。想试签名，用 `keytool` 在临时目录生成一把一次性的密钥，设上面四个环境变量再打；那把密钥用完就删，不要提交。

## 用户要做的（按顺序）

1. **生成上传密钥**（在自己电脑上，装了 Java 就有 `keytool`）：
   ```
   keytool -genkeypair -v -keystore badie-upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Badie"
   ```
   按提示设密码（现在的 keytool 只问一次，密钥密码和密钥库密码是同一个）。`CN=Badie` 是证书上的名字，别填真名（证书会跟着包公开）。把 `badie-upload.jks` 和密码存进密码管理器。
2. **加 GitHub Secrets**：GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret，加四条：
   - `ANDROID_UPLOAD_KEYSTORE_BASE64`：Mac 上 `base64 -i badie-upload.jks | pbcopy` 后粘贴（Linux 用 `base64 -w0 badie-upload.jks`）
   - `ANDROID_UPLOAD_STORE_PASSWORD`、`ANDROID_UPLOAD_KEY_PASSWORD`：都填上一步设的密码
   - `ANDROID_UPLOAD_KEY_ALIAS`：`upload`
3. **在 Play 管理中心建 App**：play.google.com/console → 创建应用 → 名称 `Badie`、默认语言、类型“应用”、“免费” → 创建。
4. **打包**：代码推到 main 以后（工作流要在 main 上才会出现在列表里），GitHub → Actions → **Android release** → Run workflow（分支 main）。跑完在这次运行的页面下载 `badie-release-aab`，解压出 `app-release.aab`。
5. **第一次上传**：Play 管理中心 → 测试和发布 → 测试 → 内部测试 → 创建新版本 → 应用签名选 Google 生成的密钥（默认）→ 上传 `app-release.aab` → 保存。
6. **记下两组指纹**：测试和发布 → 设置 → 应用完整性 → 应用签名（找不到就在顶部搜索框搜“应用签名”）→ 复制“应用签名密钥证书”的 **SHA-1** 和 **SHA-256**（同一页下面还有“上传密钥证书”的，也记下）。指纹是公开的，可以发到聊天里。
7. **Google 登录**：console.cloud.google.com（选 `Badie` 项目）→ Google Auth Platform → Clients → Create client → Application type **Android**，名字 `Badie Android`，Package name `com.badie.app`，SHA-1 填第 6 步的**应用签名密钥** SHA-1 → Create。
   - 想让自己签的包（不经过 Play 装的）也能用 Google 登录，再建一个，SHA-1 填上传密钥的。
   - 不用改 Supabase：App 拿到的身份令牌签给的是网页客户端（`302163183222-r66s…`，已经在 Supabase 的 Google 设置里）。安卓客户端只是让 Google 认这个包。
8. **Apple 登录**：Supabase → Authentication → URL Configuration → Redirect URLs → Add URL：`com.badie.app://auth/callback` → Save。Apple 那边不用动（用的是网站的服务 ID `com.badie.web`）。
9. **网页链接进 App**：把第 6 步的应用签名 SHA-256 发给我，或者自己在仓库根目录运行
   ```
   python3 Badie-Android/scripts/assetlinks.py <应用签名的 SHA-256>
   ```
   生成 `web/public/.well-known/assetlinks.json`，推 main，网站部署后打开 `https://badie.rsvp/.well-known/assetlinks.json` 能看到内容就好。
   Google 的检查工具：`https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://badie.rsvp&relation=delegate_permission/common.handle_all_urls`。
10. **装到手机上验**（从内部测试的链接装，这样是 Google 签的包）：见下一节。

## 只能在上传以后验的

- **Google 登录**：要第 7 步的安卓客户端（包名 + 应用签名的 SHA-1）建好才能用；没建好时点按钮会提示“登录没有完成…”。
- **Apple 登录**：浏览器标签页里登录 Apple，跳回 App 后进入 App（新用户去填资料）。中途关掉标签页应该什么都不提示。要第 8 步加好回调地址；没加的话会跳到网站首页，不回 App。
- **网页链接**：第 9 步以后，在手机上点一个 `https://badie.rsvp/games/…` 链接，应该直接进 App。电脑上可以用 `adb shell pm get-app-links com.badie.app` 看 `badie.rsvp` 是不是 `verified`；装了以后改的 assetlinks.json，用 `adb shell pm verify-app-links --re-verify com.badie.app` 重新验。
- **混淆后的包整体能跑**：登录（人机验证）、发现页、球局、私信、推送都点一遍。R8 规则出问题时，通常是某个接口解析失败或者人机验证一直转圈。

## 和 iPhone 不一样的地方

- Apple 登录走网页授权（Supabase 的 PKCE），不是系统弹窗；拿不到 Apple 第一次授权时给的名字，昵称不会预先填好。
- 注销账号时不撤销 Apple 授权：网页授权拿到的一次性授权码在 Supabase 那里，App 拿不到；`apple-revoke` 也还只认 iPhone 的客户端。要做的话得改服务器（见 REQUIREMENTS 8.3 第 4 条）。
- 进程在浏览器标签页里被系统杀掉（内存很紧）时，跳回 App 不会接着登录，要再点一次。
- 等级页的链接（`/levels/…`）对没定级的人只打开编辑资料，不像 iPhone 那样直接开始测。
