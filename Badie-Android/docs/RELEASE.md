# 安卓版：打包、签名、上架前的设置

给发版的人看。功能和进度在 `STATUS.md` 的“安卓版”，需求在 `docs/REQUIREMENTS.md`。

## 版本号

- **versionName**（给人看的，比如 `1.0.5`）：写在 `app/build.gradle.kts` 的 `defaultConfig` 里，发版前手动改，和 iPhone 对齐。
- **versionCode**（Play 用来比新旧，每次上传都要更大）：不用手改。发版工作流把它的**运行序号**传进来（`BADIE_VERSION_CODE`），每跑一次加 1，不会重复。本机构建是 1。
  - 为什么不写在构建文件里：忘了改就传不上去，还得再提交一次；运行序号是自动的。
  - 同一次运行点“重新运行”序号不变：要是那个包已经传过 Play，会被拒（重复的 versionCode），重新点 Run workflow 跑一个新的就行。
  - 以后要是改了工作流的文件名，序号会从 1 重新数，到时在 `android-release.yml` 里给序号加一个固定数（比如 `run_number + 1000`）。

## 签名

只有**一把密钥**，发版工作流自己生成、自己保管，不用人手动做：

- 网站上给人直接下载的 APK 用它签名；给 Play 的 AAB 也用它签。
- 放在**生产 Supabase 的 Vault** 里：`android_signing_keystore`（PKCS12 密钥库的 base64）和 `android_signing_password`（密钥库和密钥是同一个密码）。别名是 `upload`，证书名 `CN=Badie`，RSA 4096，有效期 10000 天。
- 第一次跑发版工作流时 Vault 里还没有：`scripts/vault-signing-key.sh` 用 `keytool` 生成一把、随机密码（`openssl rand`），在一个事务里两条一起存进 Vault，再读出来用。以后每次都读同一把。两次运行撞在一起时，后存的会因为名字重复失败，再读一次就是先存的那把（工作流本身也排队，不并行）。
- 连数据库用的是 `supabase-deploy.yml` 那套：Secrets 里的 `SUPABASE_ACCESS_TOKEN`、`SUPABASE_DB_PASSWORD` 和变量 `SUPABASE_PROJECT_REF`，`supabase link` 后用 `supabase/.temp/pooler-url` 连。
- 想换成自己保管的密钥：在 GitHub Secrets 加 `ANDROID_UPLOAD_KEYSTORE_BASE64`、`ANDROID_UPLOAD_STORE_PASSWORD`、`ANDROID_UPLOAD_KEY_ALIAS`、`ANDROID_UPLOAD_KEY_PASSWORD` 四个，工作流就优先用它们。**但换了密钥，已经装了网站版的人就没法直接更新了**（安卓只认同一把密钥签的新版本），所以除非密钥泄露，不要换。
- 不打印、不进仓库：密码和密钥库在用之前先 `::add-mask::`；psql 和 keytool 都从环境变量读，不放在命令行参数里；密钥库只写到 `$RUNNER_TEMP`，打完包就删。产物和 Release 里只有安装包。
- 构建时从环境变量读（`app/build.gradle.kts`）：`BADIE_UPLOAD_KEYSTORE`（文件路径）、`BADIE_UPLOAD_STORE_PASSWORD`、`BADIE_UPLOAD_KEY_ALIAS`、`BADIE_UPLOAD_KEY_PASSWORD`。四个都有才签名，否则打出来的正式包不签名（本机检查用）。

**这把密钥丢不得**：Vault 里的两条被删了或者 Supabase 项目没了，网站版的用户就收不到更新（只能卸载重装，重新登录；账号和数据在服务器上，不会丢）。所以第一次发版以后，用户在自己电脑上留一份备份（见下面“备份密钥”）。

**证书指纹**：每次运行的摘要（Actions → 这次运行 → Summary）里有签名证书的 SHA-1 和 SHA-256（公开的值，可以发到聊天里）。Google 登录的安卓客户端用 SHA-1，`assetlinks.json` 用 SHA-256。

### 备份密钥（第一次发版以后做一次）

Supabase → SQL Editor 运行：

```sql
select name, decrypted_secret from vault.decrypted_secrets
where name in ('android_signing_keystore', 'android_signing_password');
```

把两行的值存进密码管理器。要用密钥库文件时，复制 `android_signing_keystore` 那一长串，在 Mac 的终端运行 `pbpaste | base64 -D > badie-signing.p12`（Linux 用 `base64 -d`）。

### 以后上 Google Play：用这把密钥当“应用签名密钥”

网站版和 Play 版必须是同一把密钥签的，不然装了网站版的人没法从 Play 更新（反过来也一样）。所以**不要**选 Play 默认的“由 Google 生成密钥”：

1. Play 管理中心 → 这个 App → 测试和发布 → 设置 → 应用完整性 → 应用签名（第一次创建版本时也会问）→ 选“更改应用签名密钥” → “从 Java KeyStore 导出并上传密钥”（Export and upload a key from Java keystore）。
2. 按那一页下载 `pepk.jar` 和加密公钥（`encryption_public_key.pem`），用上面备份的 `badie-signing.p12` 运行：
   ```
   java -jar pepk.jar --keystore=badie-signing.p12 --alias=upload --output=badie-signing.zip --include-cert --rsa-aes-encryption --encryption-key-path=encryption_public_key.pem
   ```
   问两次密码，都填 `android_signing_password` 的值。把 `badie-signing.zip` 传上去。
3. 上传密钥：最简单是同一把（这个工作流打的 AAB 已经用它签好了，直接传）。Google 建议另用一把上传密钥；那样工作流就要管两把密钥（APK 还得用应用签名密钥签），等真要分开时再改。
4. 做完以后 Play 上显示的“应用签名密钥证书”指纹应该和运行摘要里的一样，Google 登录和 `assetlinks.json` 都不用再改。

## 正式包里有什么不一样

- R8 压缩和混淆、去掉没用的资源。规则在 `app/proguard-rules.pro`（人机验证的 `BadieCaptcha.postMessage`、kotlinx.serialization、凭据管理器）。混淆后的崩溃堆栈靠映射表还原：映射表在 AAB 里，Play 会自己读。
- 连的是正式的 Supabase（`remote/SupabaseClient.kt` 的 `SupabaseConfig`，只有这一个地址）。安卓这边没有调试用的后端开关，也没有允许明文 HTTP 的网络配置，正式包里不会带进去。
- 本机检查正式包：`./gradlew :app:bundleRelease --max-workers=1`（不签名）。想试签名，用 `keytool` 在临时目录生成一把一次性的密钥，设上面四个环境变量再打；那把密钥用完就删，不要提交。

## 网站直接下载（现在就能用，不等 Play）

**发一版**：代码推到 main 以后，GitHub → Actions → **Android release** → Run workflow（分支 main）。工作流会：

1. 跑单元测试和正式包的 lint。
2. 从 Supabase Vault 取签名密钥（第一次自动生成并存进去）。
3. 打 AAB 和通用 APK，用 `apksigner` 验签名（日志里只写“通过”），APK 超过 25 MiB（Cloudflare Pages 单个文件的上限）就停下。
4. 发 GitHub Release `android-v<versionName>-<versionCode>`，附 `badie.apk` 和 `android-version.json`（`versionCode`、`versionName`、`url`、`sha256`、`minSdk`、`size`）。只有安卓的发布时标成“最新”。
5. 触发 Web CI 在 main 上重新部署：网站构建前下载最新的安卓发布放到 `/android/`，于是 `https://badie.rsvp/android/badie.apk`、`/android/version.json` 换成新的，首页、关于页在安卓手机上显示“下载安卓 App”，`/android/` 页面有版本、大小、SHA-256 和安装步骤。
6. 运行摘要里写版本、APK 大小和 SHA-256、证书指纹。AAB 在产物 `badie-release-aab` 里，APK 也在产物 `badie-release-apk` 里。

在开发分支上运行只打包、不发布（APK 只在产物里）。

**怎么确认**：
- `curl -sI https://badie.rsvp/android/badie.apk` 返回 200，`content-type: application/vnd.android.package-archive`。
- `curl -s https://badie.rsvp/android/version.json` 的 `versionCode` 是这次运行的序号，`sha256` 和运行摘要里的一样。
- 安卓手机上打开 badie.rsvp：首页有“下载安卓 App”，下载、允许浏览器安装应用、安装、登录。

**更新提示**：从网站装的正式包每天最多查一次 `version.json`（`shell/SideloadUpdates.kt`），`versionCode` 比自己大、手机系统够新就在标签栏上面提示“Badie 1.0.6 可以更新了”，点“下载”用浏览器下载新的安装包，装在旧版上（同一把密钥，登录状态不丢）。关掉以后这一版不再提，有更新的版本再提。从 Play 装的（安装来源是 `com.android.vending`）和调试包不查。

**要注意**：
- Google 的“开发者验证”（Android developer verification）：从 2026 年 9 月 30 日起，巴西、印尼、新加坡、泰国的认证安卓手机只能装和更新已验证开发者登记过的 App，网站下载的也算（不登记只能走开发者模式加等 24 小时的“高级流程”）；2027 年起推广到全球。要在 Android Developer Console（或 Play 管理中心）完成身份验证，并登记包名 `com.badie.app` 和这把密钥的证书。没登记时，这几个国家的用户会装不上。
- 第一次装时 Play 保护机制可能提示“未知应用”或要求扫描，这是给所有不经过 Play 的 App 的，照提示继续就行。

## 用户要做的（按顺序）

1. **第一次发版**：推 main 以后 Actions → **Android release** → Run workflow（main）。签名密钥自动生成，不用手动做任何事。
2. **备份密钥**：见上面“备份密钥”，存进密码管理器。
3. **Google 登录**：console.cloud.google.com（选 `Badie` 项目）→ Google Auth Platform → Clients → Create client → Application type **Android**，名字 `Badie Android`，Package name `com.badie.app`，SHA-1 填运行摘要里的 SHA-1 → Create。
   - 不用改 Supabase：App 拿到的身份令牌签给的是网页客户端（`302163183222-r66s…`，已经在 Supabase 的 Google 设置里）。安卓客户端只是让 Google 认这个包。
   - 以后上 Play 也用同一把密钥（见上面），不用再建第二个客户端。
4. **Apple 登录**：Supabase → Authentication → URL Configuration → Redirect URLs → Add URL：`com.badie.app://auth/callback` → Save。Apple 那边不用动（用的是网站的服务 ID `com.badie.web`）。
5. **网页链接进 App**：把运行摘要里的 SHA-256 发给我，或者自己在仓库根目录运行
   ```
   python3 Badie-Android/scripts/assetlinks.py <运行摘要里的 SHA-256>
   ```
   生成 `web/public/.well-known/assetlinks.json`，推 main，网站部署后打开 `https://badie.rsvp/.well-known/assetlinks.json` 能看到内容就好。
   Google 的检查工具：`https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://badie.rsvp&relation=delegate_permission/common.handle_all_urls`。
6. **开发者验证**：在 Android Developer Console 验证身份、登记 `com.badie.app` 和证书（见上面“要注意”）。
7. **装到手机上验**：从 `https://badie.rsvp/android/` 下载安装，见下一节。
8. **以后上 Play**：play.google.com/console → 创建应用（名称 `Badie`、免费）→ 应用签名用“从 Java KeyStore 导出并上传密钥”（见上面）→ 内部测试 → 上传 `badie-release-aab` 里的 `app-release.aab`。

## 只能装到手机上以后验的

- **Google 登录**：要第 3 步的安卓客户端（包名 + 证书的 SHA-1）建好才能用；没建好时点按钮会提示“登录没有完成…”。
- **Apple 登录**：浏览器标签页里登录 Apple，跳回 App 后进入 App（新用户去填资料）。中途关掉标签页应该什么都不提示。要第 4 步加好回调地址；没加的话会跳到网站首页，不回 App。
- **网页链接**：第 5 步以后，在手机上点一个 `https://badie.rsvp/games/…` 链接，应该直接进 App。电脑上可以用 `adb shell pm get-app-links com.badie.app` 看 `badie.rsvp` 是不是 `verified`；装了以后改的 assetlinks.json，用 `adb shell pm verify-app-links --re-verify com.badie.app` 重新验。
- **混淆后的包整体能跑**：登录（人机验证）、发现页、球局、私信、推送都点一遍。
- **更新提示**：装一个旧的 versionCode，等网站上有更新的版本后打开 App，标签栏上面应该出现“Badie … 可以更新了”。R8 规则出问题时，通常是某个接口解析失败或者人机验证一直转圈。

## 和 iPhone 不一样的地方

- Apple 登录走网页授权（Supabase 的 PKCE），不是系统弹窗；拿不到 Apple 第一次授权时给的名字，昵称不会预先填好。
- 注销账号时不撤销 Apple 授权：网页授权拿到的一次性授权码在 Supabase 那里，App 拿不到；`apple-revoke` 也还只认 iPhone 的客户端。要做的话得改服务器（见 REQUIREMENTS 8.3 第 4 条）。
- 进程在浏览器标签页里被系统杀掉（内存很紧）时，跳回 App 不会接着登录，要再点一次。
- 等级页的链接（`/levels/…`）对没定级的人只打开编辑资料，不像 iPhone 那样直接开始测。
