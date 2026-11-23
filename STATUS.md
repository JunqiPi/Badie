# Badie 现状须知（2026-11-15）

新会话先读这一页，再按需要看 `CLAUDE.md` 和 `Badie-iOS/docs/` 里的文档。

## 版本

| | 状态 |
|---|---|
| 网站 https://badie.rsvp | 和 main 同步，推 main 后自动部署 |
| iPhone 1.0 | 已上架：https://apps.apple.com/app/id6825569793 （App ID `6825569793`，bundle `com.badie.app`） |
| iPhone 1.0.1 | Build `20261106.0636`，已提交过 |
| iPhone 1.0.2 | Build `20261108.2349`（main `29b144b`），**已上架**（2026-11-10 查到状态是 READY_FOR_DISTRIBUTION） |
| iPhone 1.0.3 | 苹果已批准（教练带课的球群、费用说明，Build `20261111.21`） |
| iPhone 1.0.4 | 已上线（全 App 少字改版，Build `20261111.2236`） |
| iPhone 1.0.6 | 2026-11-16 Build `20261116.1533`（main `5e9cf59`）已上传并挂到 1.0.6，10 种语言的更新说明已写入（审核信息、截图沿用上一版）。内容：注册必填常去球馆、发现页自动刷新、筛选里看附近的球群、球群多球馆、球馆库加 OSM、约球默认不限等级、关“显示我”前提醒。1.0.5 已上架 |
| iPhone 1.0.7 | 2026-11-20 Build `20261119.2245`（main `7ecedd9`，Xcode 27.1 / iOS 27 SDK）已挂上：访客报名、当晚排场 / 收款、比赛（赛制和参赛方式分开、打几轮、淘汰签表、瑞士轮、三四名、只收合规比分、中途退赛、计入胜率，见 `CLUB_NIGHT.md` 第二节开头）、别的城市的球馆能按名字搜到。10 种语言的更新说明已写入；审核备注换成了新的两段（`review_notes.json`）。等用户在 TestFlight 试过后提交。之前的 `20261119.1842`（iOS 26.5 SDK）、`20261119.1923`（旧的比赛逻辑）不要用。挂构建要指定 Build 号（`asc-build.yml` 的 build），刚上传完苹果还没列出来时它会等 |
| iPhone 1.0.5 | 2026-11-13 准备提交：附近的人（发现页刷卡：顶部选距离、附近的人头像排、照片为主的卡片；右滑发邀请，具体日期时间、单双打，双打答应后变公开局）、原首页并进球局、右上角进附近球馆（球馆详情有最近在这打过和常客）、等级卡片和打法分析（插画占位）、不用注册测级。Build `20261113.0517`（main `94d4274`，加了“我的”页卡片和编辑资料的编辑 / 预览）已挂上；更新说明、中文副标题“羽你一起进步”、商店截图（App Store screenshots 运行 `43371772036`，演示球友欣然/子轩用了用户给的照片）已写入。提交前复查（2026-11-13）又修了一轮，见下面“1.0.5 提交前复查”：新 Build `20261113.1632`（main `8870985`）已上传并挂到 1.0.5：在上一版的基础上，等级卡片改成一张可翻面的卡、打法换了新称呼、用上正式剪影。**用户 2026-11-13 已提交审核**。注意：挂构建的工作流在上传刚结束时跑会挂回旧构建（苹果还没列出新的），要等几分钟再跑，并看日志里“挂在版本上的构建”是不是新的 |
| 数据库 | Supabase 项目 `yeffnjdpjejlplqryjfx`，推 main 后自动跑迁移（最新 `20261217000000_nearby_review_fixes.sql`） |

- 1.0.2 的 10 种语言更新说明、推广文本在 `Badie-iOS/docs/STORE_LISTING.md`。给用户时**直接贴内容**，不要只给路径。
- 审核演示账号 `review@badie.rsvp`，**不能注销**。演示模式：设置 → 管理员 → 进入演示模式（只有管理员能看到）。
- 打赏：美国区链到 Ko-fi（https://ko-fi.com/badie ），欧盟 27 国不显示，其他地区用苹果内购（`com.badie.app.tip.small/medium/large`）。提交时 Notes 要写明打赏不解锁功能、美国区用 Ko-fi（guideline 3.1.1）。

## 安卓版（2026-11-15 开始做，还没发过版）

需求是 `Badie-Android/docs/REQUIREMENTS.md`（按 iPhone 1.0.5 逐项盘点，用户已定：Kotlin + Compose、最低 Android 8.0、地图用 Google、打赏只放 Ko-fi、做 Apple 登录、演示模式只给管理员）。工程在 `Badie-Android/`，2026-11-15 推到 main（不上架，只是代码进了主干）。

**做法**（后面照着来）

- 一个文件对一个文件地搬 iPhone 的代码，名字尽量不变，测试用例也照搬。文字多的表（等级标准、问卷）用脚本从 Swift 转，不手抄。
- 界面文字只有 iPhone 的 `Localizable.xcstrings` 一份：构建时转成 10 种语言的 `strings.xml`（`app/build.gradle.kts` 里的 `generateStrings`），代码里写 `tr("简体中文原文", 参数)`，参数的位置写 `%@` 或 `%lld`。测试会查每个原文都在文字表里。
- 图标：iPhone 的系统图标名对应到 Material Symbols，在 `scripts/icons.json` 里加一行，跑 `python3 scripts/gen_icons.py <解开的 @material-symbols/svg-700 包里的 rounded 目录>`，代码里写 `Sym.boltFill`。
- 跑：`cd Badie-Android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`。Android CI 跑同样三步，并把调试包（`badie-debug-apk`）和界面截图（`screenshots`）传成产物。
- 没有模拟器也能看界面：`src/test/.../screens/ScreenshotTest.kt` 把页面渲染成图，在 `app/build/outputs/roborazzi/`。搬一个页面加一张，对着 iPhone 的截图看。

**端到端测试（模拟器，2026-11-16）**：没有安卓手机，发版前靠它确认 App 真的能用。

- CI：`.github/workflows/android-e2e.yml`（改了 `Badie-Android/`、`supabase/` 就跑，也能手动跑，约 20 分钟）。起本机的 Supabase 和推送服务，调试包用 `-Pbadie.supabaseUrl=http://10.0.2.2:54321 -Pbadie.supabaseKey=…` 连它（不传就连正式后端，正式包不能换），在 Android 14（Google APIs，带 Play 服务）的模拟器上跑。没通过时把截图、录屏、界面结构和 logcat 传成产物 `android-e2e-debug` / `android-e2e-minified`。
- 压缩包也跑一遍（2026-11-16）：同一套测试分两组并行，`debug` 和 `minified`。`minified` 加 `-Pbadie.minify=true`：调试包照正式包一样用 R8 压缩、混淆、去资源（同样的 `proguard-rules.pro`，关掉可调试，R8 才按正式模式优化），照样连本机 Supabase。测试 APK 直接调 App 里的库（Compose、Kotlin、OkHttp 等），这些整个留下，规则在 `app/e2e-keep.pro`（构建完 `e2e/check-test-refs.py` 先查测试调到的类和方法压缩后都还在，缺了就加到这里），只有这一组用，正式包不用；App 自己的代码照常压缩。没通过时产物里有 `mapping.txt`，混淆过的堆栈用 R8 的 retrace 还原。改 `proguard-rules.pro` 后看这一组。第一次跑（2026-11-16）全部通过：压缩没有把 App 弄坏，正式包的规则不用改。真的收推送那几项因为没配 `FCM_SERVICE_ACCOUNT` 两组都跳过了，压缩包收推送（`FirebaseMessagingService`）还没验过。
- 调试那一组的 `push-registration` 跑过一次没通过（退出登录后停在发现页，没回欢迎页），同样的代码再跑就过了，原因没查；再出现时看录屏。
- 网站上在发的安装包（`live-apk` 那一组）：下载 `badie.rsvp/android/badie.apk`、对 `version.json` 的 SHA-256，装到模拟器上打开，要看到欢迎页的三个登录按钮、点“邮箱登录 / 注册”进到邮箱那一页、不崩（`e2e/live-apk.sh`，不登录）。截图和 logcat 在产物 `android-live-apk`。
- 测试在 `app/src/androidTest/.../e2e/`（Compose 测试 + UiAutomator 点系统的权限框和通知栏），按界面上的字找（字用 App 的文字表取，跟模拟器的语言走）。“另一个人”由测试直接调本机 Supabase（`Harness.kt`）。`e2e/run.sh` 一段段跑（每段新的进程、清掉数据），段和段之间可以杀进程、替别人发消息。
- 覆盖：邮箱注册（验证码从本机收件箱取）→ 填资料 → 主界面、退出、密码登录、冷启动直接进主界面；私信和球局群聊不刷新就收到（会话列表、角标、打开的聊天），回复对方收得到；收到好友申请时“消息”角标和铃铛；别人发来的邀请出现在球局页；别人用房间码进房间，房间页自己更新；快速匹配两人都确认后球局页出现球局；通知中心点好友申请打开资料卡并通过；球局页下拉刷新；允许通知后登记推送、数据库叫推送服务、退出时删登记。
- 真的收推送（在后台、被杀掉后收到、点通知进聊天、开着那个聊天不弹）要在 GitHub Secrets 里加 `FCM_SERVICE_ACCOUNT`（和 Supabase 里那份一样）；没有时这几项跳过，日志里会写。
- 刚成为球友、还没聊过的人不在会话列表里（iPhone 也这样，服务器其实返回了，见 `MessagesView.swift` 里用不到的“已是球友”）。

**做完的**

1. 工程和 CI；App 图标；系统设置里的 App 语言（10 种）。
2. 设计系统的基础：颜色、字号、间距、贴纸卡片、按钮、图标按钮、角标、页头、提示条、空状态、横幅、输入框、密码框、验证码格子、头像、选择胶囊、分段选择、“?”规则说明、进度条（`design/`）。
3. 骨架：启动页、四个标签各一条导航栈、悬浮标签栏、“+”菜单（`shell/`）。（各页面后来都搬完了，见第 8 条起。）
4. 后端客户端：登录、调接口、读写表、照片、换令牌、约 100 个错误码的文案、密码规则、登录状态加密存本机（`remote/`）。
5. 模型：等级和 27 档、等级标准、性别、认证、距离、定级问卷（14 题、算分、打法）、用户（综合等级、靠谱徽章）、口碑、赛后评价（`models/`）。问卷的测试用例和 iPhone、网页一样。2026-11-16 其余模型也搬完了：球馆（价格、营业时间、来源、确认）、国家和手机号、时间段和日期文字、球局和费用、赛果和排行榜、约球请求、房间、球群、约人的时间窗口、挑战、消息、好友和通知、爽约、高水平认证；iPhone 打包的球馆目录不搬（安卓从服务器读）。日期按 `DateText`（安卓用 ICU 按模板排，测试里是简体中文的写法），按日历算的函数都带时区参数。
6. 账号（`backend/Backend.kt`，对应 iPhone 的 `MockBackend+Remote.swift`）：登录后读资料、第一次登录建资料、本机缓存（离线先用缓存进主界面）、登录失效退回登录页、补选性别。
7. **登录和注册**（`features/onboarding/`，2026-11-15）：欢迎页、邮箱 + 密码登录和注册、验证码登录、忘记密码、6 位验证码、人机验证、称呼和头像（颜色加表情）、定级问卷和结果卡、最后一步（常打、在附近的人里显示我）、以前没选性别的人补选。流程逻辑在 `OnboardingModel.kt`，有测试。
8. **全部功能页面**（2026-11-16，六块分头搬完再合起来）：发现页（附近的人、按天的卡片、筛选、约人和回邀请）、快速匹配（设置、找人、确认、结束）；球局（球局页、签到、AA、赛果、互评、再约一次、开赛前本地提醒）、房间（开局、大厅、房间码、公开球局）；球友、球友资料、举报、爽约记录和申诉、私信和群聊、通知中心、球群（找、报名、候补、名单、建群）；球馆（附近、球馆页、选球馆、添加、附近范围）；排行榜、挑战；“我的”、编辑资料（照片头像和卡片背景、裁剪）、设置全部、空闲时间、等级对照表、重新定级、高水平认证、帮助和反馈、等级卡片（生成图片、分享、存相册）。各块的服务器调用在 `backend/*Api.kt`。
9. 各块已经接起来（2026-11-16）：位置和附近范围只有一份（`LocationManager`），球局页有约球请求、球群、本周排行、同馆常客，球馆页列出球群，“我的”有球友数、挑战、加球友链接，发现页的铃铛有角标，日期跟着界面语言。
10. 测试 467 个，本机过；截图 111 张。
11. **推送**（2026-11-16，Firebase Cloud Messaging，`push/`）：允许了通知就要令牌，登录后、每次启动报给服务器（`register_push`，kind 是 `fcm`），退出登录和注销前先注销；发出约球请求后问一次通知权限；聊天显示成带头像的会话通知，同一会话归在一条；在前台时正开着的会话不弹，并马上拉新消息；点通知（包括本地提醒）打开对应页面，冷启动时等主界面出来再跳。Firebase 配置在 `res/values/firebase.xml`（`google-services.json` 不进仓库）。还没在真机上收过推送。截图里中文的粗体不明显，是测试环境的字体只有一种粗细，真机上要再看。
12. **跟上 main 上后来的改动**（2026-11-16）：注册时“列表里没有我的球馆”；关“在同馆常客里显示我”前先确认；露天场地（读 `venues.kind`，球馆页显示“露天场地”，自动选常去球馆先选室内）；球馆搜索用 `search_venues`；发现页附近的人每分钟刷新、回到 App 时刷新；球群多球馆（1–5 个，主球馆在前）、每周场次选球馆、球群页和场次写实际球馆、发现页筛选里的“显示：球友 / 球群”（附近的球群，近的在前）。
13. **上架准备**（2026-11-16，详细步骤见 `Badie-Android/docs/RELEASE.md`）：
    - 正式包：R8 压缩混淆加去资源（规则 `app/proguard-rules.pro`），只连正式 Supabase。versionName 在 `app/build.gradle.kts` 手改；versionCode 用发版工作流的运行序号，自动加 1。
    - 签名：一把密钥，网站下载的 APK 和给 Play 的 AAB 都用它签。发版工作流第一次运行时自己生成，存在生产 Supabase 的 Vault（`android_signing_keystore`、`android_signing_password`）；GitHub Secrets 里有 `ANDROID_UPLOAD_*` 四个时优先用那四个。以后上 Play 要把这把密钥当应用签名密钥传上去（PEPK），不能让 Google 生成，不然网站版的人没法从 Play 更新。备份、导出、指纹都在 RELEASE.md。
    - 工作流 **Android release**（只能手动跑）：测试、lint、取密钥、打 AAB 和通用 APK、验签名（APK 超过 25 MiB 就停）。在 main 上跑时发 GitHub Release `android-v<版本>-<versionCode>`（`badie.apk`、`android-version.json`），再触发 Web CI 重新部署；运行摘要里有证书的 SHA-1、SHA-256。产物 `badie-release-aab`、`badie-release-apk`。**还没真正跑过**（2026-11-16 写好，等用户看过再跑第一次）。
    - Google 登录：系统的凭据管理器，令牌签给网页客户端（Supabase 已认）。Apple 登录：浏览器标签页里走 Supabase 的网页授权（PKCE），跳回 `com.badie.app://auth/callback`。按钮的位置、文字、“Apple 没开时不显示 Google”和 iPhone 一样。
    - 网页链接进 App（App Links）：路径和 iPhone 一样，加球友链接、等级页也接了。网站的 `assetlinks.json` 等第一次发版后拿到运行摘要里的 SHA-256，用 `Badie-Android/scripts/assetlinks.py` 生成。
14. **从网站直接下载**（2026-11-16，不等 Play）：网站构建前（`web.yml`）下载最新的安卓 Release 放到 `/android/badie.apk`、`/android/version.json`（`_headers` 设成安装包、附件下载）；`astro.config.ts` 读到才显示下载（`src/app/androidApp.ts`），没有时一切照旧（添加到主屏幕）。安卓手机上首页、关于页的按钮是“下载安卓 App”，点了下载并弹出三步安装说明，“添加到主屏幕”退成下面一行小字；登录后的提示也换成下载 App；电脑上 App Store 旁边多一个“下载安卓 App”去 `/android/`。`/android/` 页面 10 种语言，有版本、大小、SHA-256、安装步骤。App 里（`shell/SideloadUpdates.kt`）：从网站装的正式包每天最多查一次 `version.json`，有新版本在标签栏上面提示，点“下载”用浏览器打开安装包；从 Play 装的和调试包不查。新加的两句文字（“Badie %@ 可以更新了”“下载”）在 xcstrings 里标成手动添加，iPhone 不用。
15. **1.0.6：不再直接读 `venues` 表**（2026-11-16，为服务器的“防整表拿走”）：按 id 读球馆的 5 处（`VenueApi` 的球馆页和查重、`RankingsApi`、`ProfileApi` 常去球馆的名字、`MatchApi`）都改调 `venues_by_ids`（`VenueApi.kt` 的 `venueRowsByIds` / `venuesByIds`，一次 100 家、多了分批，整行用 `venueFromRow` 只读认识的列）；`Backend.searchVenues` 只用 `search_venues`（带位置）。端到端测试冷启动后在“我的”卡片上等常去球馆的名字（走 `venues_by_ids`）。versionName `1.0.6`，还没发版。

**搬的时候没法做、先简化的**（等对应的东西齐了再补）

- 地图（球馆页小地图、附近球馆地图、添加球馆时拖图钉、地点联想）：等 Google Cloud 的 key。现在用地址文字、距离和“导航”跳地图 App。
- 应用内评价（Google Play 的评价窗口）、二维码：要加依赖。规则（120 天一次）已经做了，只是不弹。
- 球局提醒是本机闹钟，手机重启后会丢；加到日历时带不了坐标和提前 2 小时的闹钟（安卓的日历接口不支持）。
- 导航用系统的“选择 App”，不像 iPhone 列出几个地图 App。
- 打赏（Ko-fi）按手机卡或设备的地区判断是否显示（安卓看不到商店地区）。
- 注销账号不做 Apple 撤销：安卓的 Apple 登录走网页授权，授权码在 Supabase 那里，App 拿不到（要改服务器）。
- Apple 登录拿不到第一次授权时给的名字，昵称不预先填。
- 等级页链接对没定级的人只打开编辑资料，不直接开始测。

**登录注册里还没做的**（都记在这里，后面对应的那一步补上）

- 安卓的人机验证靠网站的 `/captcha/` 页面往回传令牌（`web/src/pages/captcha.astro` 里 `BadieCaptcha.postMessage` 那一行，2026-11-15 随 main 上线）。还没在真机上登录过，第一次装到手机上要先验这一步。
- Apple、Google 登录：代码已做（2026-11-16），等用户做完下面“上架要用户做的”第 6、7 步才能用。
- 照片头像（选图、裁剪、上传）。
- 最后一步里的空闲时间。
- 结果卡里的六维雷达图、“看对照表”、“分享等级卡片”。

**注册已跟上 iPhone 1.0.6**（main `b5772c9` 的改动，2026-11-16）：最后一步的常去球馆必选（开了定位就先选上离你最近的一家，最多 3 家），注册后默认在附近的人里显示，不再有那个开关。球馆从服务器读（`venues_near`，按名字搜用 `search_venues`，按 id 用 `venues_by_ids`；1.0.6 起不直接读 `venues` 表），不像 iPhone 那样把球馆目录打包进 App；定位用系统自带的，不靠 Google 服务。还没做：找不到球馆时自己添加（要等地图）、老用户自动补常去球馆（服务器已经替老用户补过一家）。

**和 iPhone 不一样的地方**

- 推送：在设置里点“球局提醒”允许通知后，安卓马上登记推送；iPhone 要等下次打开 App 才登记（iPhone 也该改，等用户定）。
- 推送：注销账号前安卓先注销推送登记（iPhone 靠服务器删账号时一起删）；Android 13 以前的系统不问通知权限（默认就能发）；聊天通知没有登记成系统的“对话”（没做快捷方式），Android 11 起不进通知栏最上面的“对话”区。
- 球馆搜索：`search_venues` 只搜名字、别名、城市，不认街道地址（iPhone 搜本机的球馆，认地址）。1.0.6 起去掉了“没搜到再直接查表”：注册、挑战、房间、球群选球馆的搜索框的提示改成文字表里已有的“搜索球馆”（网站写“Search courts by name”，文字表里没有，按 PORTING 不加新句子）；“搜索球馆”和快速匹配选球馆（`features/venues/VenuePicker.kt`）还把附近、常去的球馆在本机按地址比，所以留着 iPhone 的“球馆名、简称（如 LABC）或地址”。
- 发现页看球友还是球群记在本机（`SharedPreferences`），和 iPhone 的 `@AppStorage` 一样换手机不带过去。
- 注册最后一步选的“常打”（单打 / 双打）：iPhone 连正式后端时没有存（`OnboardingFlow.finish()` 的正式后端那一路没传 `preferredMode`），安卓存了。要不要把 iPhone 也改掉，等用户定。

**接下来的顺序**

1. 用户看过后跑第一次 **Android release**（main），网站出现 `/android/`；装到手机上验推送（要 Supabase 填好 `FCM_SERVICE_ACCOUNT`）、Google 和 Apple 登录、网页链接、人机验证、更新提示。
2. 用运行摘要里的指纹建 Google 登录的安卓客户端（SHA-1）、加 `assetlinks.json`（SHA-256）；备份 Vault 里的密钥。
3. 开发者验证（Android developer verification）：2026-09-30 起巴西、印尼、新加坡、泰国的手机只能装登记过的 App（网站下载的也算），2027 年全球。要在 Android Developer Console 登记 `com.badie.app` 和证书。
4. 地图（要 Google Cloud 的 key）。
5. 演示模式、商店截图和文案、封闭测试、上 Play（应用签名用同一把密钥）。

**要用户准备的**（到那一步再弄，不急）

- **上架要用户做的**（按顺序，每一步点哪里见 `Badie-Android/docs/RELEASE.md` 的“用户要做的”）：
  1. 推 main 以后 Actions → Android release → Run workflow（main）。签名密钥自动生成，不用手动做。
  2. 备份 Vault 里的密钥（一条 SQL，存进密码管理器）。
  3. Google Cloud → Google Auth Platform → Clients → 建 Android 客户端：包名 `com.badie.app`，SHA-1 填运行摘要里的。
  4. Supabase → Authentication → URL Configuration → Redirect URLs 加 `com.badie.app://auth/callback`。
  5. 把运行摘要里的 SHA-256 给助手（或自己跑 `Badie-Android/scripts/assetlinks.py`），生成网站的 `assetlinks.json`，推 main。
  6. Android Developer Console 做开发者验证、登记包名和证书。
  7. 以后上 Play：应用签名选“从 Java KeyStore 导出并上传密钥”，用同一把。
- 球馆那一步之前：Google Cloud 账号（绑卡），开地图和 Places 的 key。
- 上架：Google Play 开发者账号；个人账号要 12 个测试者连续测 14 天。

**这个云端开发环境的坑**

- 没有 Android SDK，要自己装：下载 `commandlinetools-linux`，`sdkmanager "platforms;android-37.0" "build-tools;36.0.0" "platform-tools"`，在 `Badie-Android/local.properties` 写 `sdk.dir=`（这个文件不进仓库）。
- Maven Central 在这里被限流（一多半请求回 429）：第一次构建要反复跑十几遍才能把依赖下全，下全以后就快了。加新依赖时也会这样。CI 上没有这个问题。
- 读 CI 的日志很费 token：编译错误尽量在本机跑出来。

## 怎么发版

1. 改动先推开发分支，等 CI 全绿（iOS、Web、Supabase）。开发分支的 iOS CI 不截图，约 15 分钟。
2. 用户说“推到 main”才推 main：先确认 main 没有别人新推的提交（有就先合进开发分支），再 `git push origin <sha>:main`。推 main 会自动部署数据库（Supabase deploy）和网站。
3. 上传 TestFlight 要先问用户：`gh workflow run testflight.yml --ref main`，build 号是 UTC 时间（如 `20261108.2349`）。iOS 的工作流都在 `xcode-27` 镜像上、写死 Xcode 27.1（2026-11-19 苹果要求 iOS 27 的 SDK；默认的 `macos-26` 只有 Xcode 26）。
4. 只改文档时，提交信息里加 `[skip ci]`，不跑 CI。

## 最近做的功能（1.0.2）

- **首页按天看人**：首页最上面是日期，点一天全屏看这天附近在找人、我能约的人。
  - 右滑和点爱心一样：直接约。单打发邀请，对方确认就成局；双打替我开一个公开的双打局并邀请对方。约在筛选里选的球馆，没选就约离我最近的那家。
  - 筛选：项目、球馆、等级、时间、对方性别、只看没爽约过的（记在本机）。没有距离筛选，距离只在设置的“附近范围”里。
  - 卡片 30 秒自动刷新。日期上的人数和卡片用同一套条件（`pool_by_day` / `day_candidates`）。
  - **限制**：同一天最多同时等 3 个人回复（单打、双打合计，`too_many_invites`）；时间重叠的邀请也能发，谁先接受就和谁打，其余重叠的自动撤回并通知对方；同一个人一天只能约一次双打，自己每天最多 20 次；跳过是按请求记的，对方改了请求或重发会再出现。
- **卡片背景**：头像和卡片背景照片分开（头像 320×320，背景 600×800），或选 8 种颜色（没选的按用户 ID 给默认色，iOS 和网站同一个算法）。可以全屏预览“我的卡片”。
- **结束球局**：填两边各赢了几局（可填每局比分自动数），或“没计分，就是练球”“记不清了”。两队都填了、而且一致才算局数；只有一方填的按 1 局算。平局单独记，不上排行榜。胜率按局算（`win_rate.rounds / round_wins`），老字段 `games / wins` 留给 1.0.1。
- **App 里换语言**：设置 → App 语言，马上生效；和 iOS 系统设置里给 Badie 选的语言是同一个值。
- **下拉刷新**：所有列表页下拉都刷新全部内容。

## 教练带课的球群（2026-11-10 推到 main）

网站和数据库已经上线；iPhone 在 1.0.3 里。

- `Badie-iOS/docs/COACHING.md` 的小版本；完整方案在 `COACHING_LATER.md`，先不做：
  - 建群和编辑时可以勾“教练带课”：每场 1–40 人（普通群还是 4–40），水平范围只作提示，谁都能加入或申请。
  - 收费备注 120 字，教练写价格和自己的收款方式，Badie 不经手钱。iPhone 上现在也能填、能看到。
  - 看效果：SQL 编辑器里跑 `select * from public.coached_group_stats();`。
  - 旧版 App 照常能用（不传 `p_coached`）。上线后 `STORY.md` 的功能表加一行“教练可以用球群带课”。

## 商店截图和商店文字（2026-11-10 重做，已推 main）

- 文案和版式都换了：9 张、海报式，细节见 `Badie-iOS/docs/APP_STORE.md` 第 0 步的“截图”和 `VOICE.md` 的“商店截图上的标题”。
- 最新一套成品：Actions → App Store screenshots 第 13 次运行的产物（30 天后过期，过期了重跑）。**已经传到 App Store Connect 的 1.0.3 上**（用 Upload App Store screenshots 工作流）。
- 新加了演示页面 `playerNoShow`（资料页显示“近 180 天爽约 1 次”），“按天看人”的演示卡片改成柠檬色。
- 更新说明和描述放在 `Badie-iOS/scripts/store_text.json`，用 Actions → Update App Store text 写进 App Store Connect（1.0.3 已写）。
- 界面文字过了一遍（简体、英文逐句读，其余语言只用规则扫）：简体和繁体的“履约”都改成了“到场”。iPhone 上简体是源语言，改动写在 xcstrings 的 zh-Hans 里，代码里的 key 没动。繁体界面还在用“水平”，商店页用“程度”，要不要统一等用户定。

## 1.0.5 提交前复查（2026-11-13）

本机起完整数据库，300–3000 个随机用户并发做 1.0.5 的所有动作，再查数据对不对；iPhone 和网站逐文件读了一遍。修了：

- **等级下限**：女生在不限性别的局里等级减 1.5，rating 不到 2 的算出 0 或负数。两位 1 级女生约双打答应时报错，她们也开不了不限性别的局、加不进公开局。现在换算后的等级限制在 1–9（`audience_level`）。
- **同一时间约了几个人**：一个成局后，我提出的、时间重叠的其他邀请自动撤回并通知对方（`withdraw_invites_for`）。等我回复的不动。
- **签到定下的时间不记爽约**：没定时间的球局，一个人签到就把时间定成现在（`games.time_by_check_in`），对方没答应过这个时间，这样的局 `judged_no_show` 不算。
- **附近的人、球馆页的人提速**：结果不变。3 万用户（一个城市 5400 人）时 `nearby_players` 4.4 秒 → 0.65 秒，`venue_people` 2.3 秒 → 0.06 秒。
- **iPhone**：发邀请的人打开自己的邀请，标题是“你约了 X”（以前写成“X 想换个时间”）；已经允许定位、位置还没回来时转圈等，不再提示“开启定位”，也不按默认城市找人。
- **网站**：日语、韩语等 8 种语言的静态页上切换语言有反应了（`pathInLanguage`）。

没修、留到 1.0.6 的：

- 附近的人加载失败时显示“附近暂时没有人”（iPhone 和网站都是）；一次只拉 30 张，刷完就说看完了，要下拉或重进才有下一批。
- 网站约 TA 的半屏出任何错都会关掉，选好的时间要重填。
- 两个人同时答应同一个人的同时间邀请（毫秒级）仍可能撞车；签到定时间不查撞车。
- 换城市后发现页第一张卡可能还是旧城市的。
- 时区是 :45 偏移的球馆（尼泊尔等）发不出邀请；目前球馆库里没有这样的球馆。
- 线上的 AASA 已带 `/levels/*`，1.0.4 及更早版本点等级卡片链接会进通知页，1.0.5 上架后自然好。

## 等级卡片改版、网站减字（2026-11-13，已推 main）

- **等级卡片**：一张 4:5 的卡（1080×1350），正面 / 背面点一下翻面，分享的是正在看的那一面；所有打法统一用黑、米白、柠檬绿，不再有彩色海报底和“限时动态”尺寸。有头像的人可以印上头像（可关）。iPhone 在 `LevelCardViews.swift`，网站在 `web/src/app/levelCard.ts`。CI 只截了正面，背面没有截图验证过。
- **打法新称呼**（用户定的）：杀球重炮手、网前魔术师、铁壁、弹簧腿、小马达、战术师、六边形战士、新星。代码里的名字（cannon / quick / engine / captain 等）没变。“弹簧腿”下面那句还是原来“快枪手”的“中场越快越舒服。”，等用户定新的。
- **剪影**：8 张，用户用 GPT 生成，按人物裁好、统一成 `#17140F`。网站在 `web/public/cards/<打法>.png`，iPhone 在 `Assets.xcassets/Play-<打法>`。后三张（战术师、六边形战士、新星）是按发图顺序配的，用户还没确认。
- **网站减字**：对照了 EF SET、USA Pickleball、UTR、DUPR 等的等级页（开头 26–40 词到正题，索引页每级不超过约 30 词，细节放分级页或折叠）。等级表开头改成一句，男女等级的说明改成页底一句，分项标准折叠；关于页去掉重复的一段、常见问题折叠；快速匹配、发起球局、等级认证去掉重复的说明。
- **顶栏“测等级”**（main `fe5ab75`，已上线）：没登录时顶栏有“测等级”，直接进问卷；等级表和问卷不再算在“我”下面。其他语言的静态页面构建时会把站内地址（连传给顶栏的 path）都加上语言前缀，顶栏判断在哪个 tab 之前要先去掉（`withoutLanguagePrefix`）。
- **更新说明**：`store_text.json` 里的打法名字已换成新称呼，但还没同步到 App Store Connect（要跑 Update App Store text，先问用户）。

## 网站测级结果页重做（2026-11-13，已推 main `cc344db`）

- **卡片叠字修了**（网站）：正面的打法说明换成两行时，第二行会压到底边的 `BADIE.RSVP/LEVELS`（杀球重炮手这种说明长的会碰到）。`levelCard.ts` 里把打法那一组往上挪了，落款往下挪了 4。
- **结果页上面两块重做**（`web/src/app/QuizResult.tsx`，样式在 `global.css` 的“测级结果页”一段），没有新增文字：
  - 等级：羽毛球标志的底纹、大一号的星形、周围六个小贴纸（两只羽毛球、四个彩色小块，窄屏不显示）、1–9 级的刻度（圆点停在 −、平、+ 的准确位置）。
  - 打法：上半块和卡片的人物区一样（米白底、英文大字、剪影），打法名字压在上面；最强一拍、最佳搭档是两个白色小贴纸；雷达图加了顶点和轴线。
  - 动效：数字从 1 数到结果，星形盖章一样弹出，小贴纸弹开，圆点从 1 级滑过去，剪影升上来，雷达图从中心长出来。系统关了动效的人看到静止的最终画面。
- 验证：本机预览走完问卷看过电脑、手机（390、320 宽）和深色；上线后在 badie.rsvp 又走了一遍。Web CI（含端到端）通过。
- **iPhone 没改**：
  - 卡片（`LevelCardViews.swift`）两行说明的第二行离落款只有一两个点，没叠上但很挤。对应网站的改法是打法名字的基线 393.33 → 390.67、说明的基线 410.67 → 406.67、落款 436 → 436.67。
  - 结果页（`SkillAssessmentViews.swift` 的 `AssessmentResultCard`）还是原来的一张柠檬绿卡片，结构和网站不一样（没有星形，打法和雷达图在同一张卡里）。要照网站这版做，得看着截图调；做这次改动的会话读不到 CI 的截图，所以没动。
- 这台 Windows 电脑上 `astro check` 会报 8 个和大小写有关的错（`Levels.tsx` 和 `levels.ts` 在不分大小写的盘上被当成同一个文件），本机起预览也要临时把 `./Levels` 的引用写成 `./Levels.tsx`；CI 上没有这个问题。本机的 Node 是 22.14，Astro 要 22.22 以上，可以用 `npx -p node@22.22.0` 取一个新的来跑。

## 让注册的人都出现在发现页（2026-11-15）

线上 28 人里只有 2 人出现在“附近的人”：要同时打开“显示我”、定过级、有常去球馆（我们不存位置，常去球馆就是“在哪一带”），24 人没有常去球馆。用户定的：
- **注册时常去球馆必填**，知道位置时自动选上最近的一家（能换）；注册后自动显示在附近的人里（开关只在设置里）。网站 `Onboarding.tsx` + `usualCourt.ts`，iPhone `OnboardingFlow.swift`（1.0.6）
- **跳过问卷的按 3 级算**，也进附近的人、能被约（`has_level` 对有资料的人都为真，迁移 `20261218000000_everyone_in_discover.sql`）
- **约球默认不限等级**：快速匹配默认“不限”，开局默认 1–9，双打邀请答应后的公开局 1–9
- **补常去球馆**：迁移按最近的约球请求 / 房间 / 球局 / 球群补一家（线上能补 11 人）；网站发现页和 iPhone 拿到真实定位时，一家都没有的自动收藏最近的一家（每个账号一次，自己删了不再补）；剩下 13 人没有任何记录，用户发邮件问了球馆后手动写进 `favorite_venues`；库里没有的 5 家（英国 3、曼谷、Shah Alam）放在 `Resources/curated-added.json`
- **注册时要是搜不到自己的球馆**，可以点“列表里没有我的球馆”先继续（以后在球馆页再选）
- **设置里关“在同馆常客里显示我”先确认**：“我们只用你的常去球馆，让附近的球友找到你、约你打球。关掉后，别人就约不了你了。”（关掉后 `invite_allowed` 确实不让别人约）
- 安卓的注册页、设置已跟上（2026-11-16）：常去球馆必选、默认显示、“列表里没有我的球馆”、关掉“显示我”时的确认

## 全世界的球馆：OpenStreetMap（2026-11-16）

- `supabase/scripts/build_osm_venues.py` 从 QLever（qlever.dev，OSM 全球数据，overpass-api.de 在这台机器上连不上）拉所有 `sport=badminton`（约 1.36 万个，中国大陆占 4482 个）。用户定的：**除了商店都收**；另外也不收标了不对外开放的（305 个）和军事区里的，中国大陆、朝鲜不收
- 有名字的用自己的名字；没名字但在有名字的体育馆里的用那栋楼；没名字的露天场地叫“所在公园 / 学校 / 小区 · 羽毛球场”（按当地语言），50 米内同一处的几块并成一个、记下场地数。和 App 里已有的球馆 150 米内或 1 公里内同名的跳过。结果 7301 家，其中露天 4421 家（`venues.kind = 'outdoor'`，迁移 `20261219000000_outdoor_courts.sql`），球馆库一共 11053 家
- 放 `supabase/data/osm-venues.json`：只进数据库，不打包进 App、不生成网站静态页；状态“待确认”，署名 © OpenStreetMap contributors（ODbL，这份文件在公开仓库里，满足共享要求）。id 用 OSM 编号（`v-fr-osm-w140992546`），重跑不会换 id；OSM 那边删了的会按种子规则隐藏进审核
- 露天场地太多会把球馆挤掉：`venues_near` 把室内的排前面；注册时自动选常去球馆，网站和 iPhone 都先选室内的（iPhone 1.0.6 起读 `kind`，详情页显示“露天场地”）
- **换一种语言也能搜到**：OSM 里各种语言的名字（`name:en`、`name:th`、`alt_name`……）都放进别名；自动起名的场地加英文别名 “Badminton court”。网站的球馆搜索改用 `search_venues`（迁移 `20261220000000_search_venues.sql`）：名字、别名、城市都搜，不分大小写和重音、忽略空格，离你近的在前（以前只按名字搜、不认别名、随便取 8 个）。iPhone 搜的是本机已有的球馆（附近的 + App 自带目录），本来就认别名、拼音；搜不到还能用 Apple 地图。城市名只有英文（“首尔”搜不到，“Seoul”可以）
- 更新：装 `reverse_geocoder==1.5.1 timezonefinder==6.5.9`，跑这个脚本再跑 `build_venue_seed.py`
- 噪音还有一些（小区、学校里的场地外人进不去，偶尔把整个体育场算进来），靠球友确认 / 举报

## 一个球群几个球馆、发现页找球群（2026-11-16，网站和数据库，没推 main）

- 迁移 `20261221000000_group_venues.sql`，测试 `supabase/tests/group_venues.test.sql`：
  - 新表 `group_venues` 存球群全部球馆（1–5 个，position 0 是主球馆）；`play_groups.venue_id` 一直等于主球馆，旧版 App 只认它，照常能用
  - 每周场次可以选在哪个球馆（`group_schedules.venue_id`，空 = 主球馆）；生成场次时把球馆写进 `group_sessions.venue_id`，以后换主球馆、删球馆，已经生成的场次不会悄悄换地方。删掉的球馆上的场次回到主球馆（报名不丢）；某一场换球馆和改时间一样：原来的取消（通知报了名的人），按新的生成
  - `create_group` / `update_group` 多一个 `p_venues`（按顺序，第一个是主球馆；编辑时 null = 不变），场次 jsonb 可带 `"venue"`。旧版 App 编辑时不带 `"venue"`，沿用原来的球馆
  - `group_summary` 多 `venues`，每周场次多 `venue`；`group_page` 每一场多 `venue`；`my_groups` 的场次写实际球馆；取消、递补的通知也写实际球馆
  - `groups_near`：任何一个球馆在范围内都算，多 `distance_m`（到最近的球馆），近的在前
- 网站：建群、编辑可以加到 5 个球馆，多于一个时每周场次能选球馆；球群页和卡片列出所有球馆；发现页的筛选里多了“显示：球友 / 球群”（记在浏览器里，选了球群时筛选按钮上有角标、条件栏里有“球群 ✕”），球群按附近范围列出。iPhone 一样放在筛选里（1.0.6）；发现页顶部和以前一样
- iPhone 一样（1.0.6）；安卓也跟上了（2026-11-16）

## 我们整理的球馆、网站球馆目录、防整表拿走（2026-11-16）

- **我们整理的球馆表**（CSV：名字、地址，约 1.9 万行）：`supabase/scripts/build_imported_venues.py`。不收“could not be confirmed”的、OSM 编号命名的（“Badminton pitch in X #123”，归 OSM 那边）、库里同名同城的
  - 坐标：先用 QLever 一次 500 个名字到 OSM 里找同名的地方，核对它所在的市 / 区 / 省、邮编在地址里；找不到的再用 Nominatim（每秒 1 次、单线程，从发出算起；每条最多 3 次；只查到城市的标“位置大概”，名字又只是“羽毛球场”的不收）。Nominatim 会模糊匹配（邮编命中别国、“Sub-District”成了监狱），所以查到的地方必须在地址写的城市里
  - **这批数据不进公开仓库**（防止被一次拿走）：结果写在 `--cache` 目录，直接写进线上数据库；`source = curated`、`status = unconfirmed`，id 是 `v-国家-b` 加 10 位十六进制。`build_venue_seed.py` 同步时不隐藏这种 id。网站构建前用 `supabase/scripts/export_collected_venues.sql` 从线上库只读导出（`web.yml`，用已有的 Supabase 密钥）
  - **线上库现有 3,152 家**（71 个国家）：位置准的 2,807 家（1,167 家坐标来自 Overture Maps，其余来自 OSM），位置大概的 345 家（只知道城市，网站和 App 附近列表不显示）。先写了 1,618 家，后来加了“门牌查不到就查街道”和 Overture（`overture_places.py`，`--overture`）又补了 1,534 家；和库里已有的同一家（60 米内或 1 公里内同名）不再写
  - **日本（2026-11-19，我们收集的公共体育馆表，1,618 行）**：写进线上库 1,572 家（19 家同名同城、25 家和已有的同一家，没写）；位置准的 1,429 家：OSM 按名字 481、国土地理院 895、Overture 32，其余按地址；位置大概的 143 家；46 家带 OSM 的英文名做别名。日本现在一共 1,665 家（以前 93 家）
    - 都道府县（位置准）：東京都 194、富山 69、大阪府 67、神奈川 49、石川 47、愛知 45、兵庫 44、鹿児島 42、新潟 39、岩手 35、福岡 35、埼玉 33；主要城市：東京 23 区 139、大阪市 26、横浜市 21、名古屋市 20、京都市 17、札幌市 15、神戸市 14、福岡市 11、千葉市 8、さいたま市 8、川崎市 7
    - 表里的地址都道府県 + 市区町村写了两遍、有的夹着“〒邮编”，先整理成“门牌, 市区町村, 都道府县, JP, 都道府县”再导入（转换脚本没进仓库，很短：去掉邮编，找“市区町村”后面紧跟着的重复）
    - 日本的门牌 OSM 几乎没有：`--gsi` 用国土地理院的住所検索（`msearch.gsi.go.jp`，每秒 1 次，查得到番地；查到的地址要在同一个市区町村里并带番地号码），署名“出典：国土地理院”。中日韩地名按包含关系核对，门牌、城市、省用表里自己写的
    - **日本的体育馆（OSM，`build_osm_gyms.py JP` → `supabase/data/osm-gyms-JP.json`，走种子同步）1,253 家**：OSM 里日本的体育馆很少标 sport=badminton，之前東京体育館都没有。按名字收（体育館 / アリーナ / スポーツセンター…），不收武道館、学校、园区里的楼、单位自用、只叫“体育館”的；英文名、alt_name 做别名（“Tokyo Metropolitan Gymnasium”能搜到）。重跑时用 `--exclude` 给线上库导出的我们整理的球馆，免得重复。日本现在一共 2,918 家
- **各国的体育馆（OSM，2026-11-19）**：`supabase/scripts/build_osm_gyms.py <国家…>` → `supabase/data/osm-gyms-<国家>.json`，走种子同步（推 main 就进库）。每个国家一套当地叫法（names）、不收的词（skip：学校、武道館、泳池、冰场、篮球场、单位自用……）、通称（generic）、行政区划级别，见脚本里的 COUNTRIES；`--count` 只数不写。查询结果按名字缓存，改了规则要清掉 `--cache` 目录
  - 现有 14,526 家（2026-11-20）：法国 4,619、德国 4,372、日本 1,388、美国 1,280、菲律宾 822、英国 615、印尼 285、澳大利亚 238、加拿大 233、韩国 174、印度 162、越南 111、台湾 93、马来西亚 75、泰国 38、香港 21
  - 学校、大学的体育馆也收（1,430 家，`kind = school`）：不少晚上、周末开放给俱乐部和社区。`venues_near` 里室内公共场馆在前、学校其次、露天最后（迁移 `20261230000000_school_gyms_last.sql`）。名字只是“体育館”这种通称的（多半是学校里没起名的）还是不收：认不出是哪一家；要收得用所在学校的名字起名（“某某小学 · 体育館”），日本一国就可能上万所
  - 德国、法国的 Sporthalle / Gymnase 以学校、俱乐部的为主（羽毛球在那边主要是俱乐部活动）。国家页球馆超过 500 家时地图每个地区一个点，德国页压缩后约 180 KB；网站一共约 12,100 个文件
  - 韩国 OSM 里体育馆少，要补全得用韩国政府的公共数据（全国体育设施标准数据）或我们自己收集的表
  - 写法：本地生成每批 150 家的 SQL（带 md5 校验、文字先统一成 NFC、id 原样带上），用 Supabase 连接逐批执行；加密后推仓库让数据库下载的办法被安全检查拦了。名字匹配别太松：只看共同词会把“Badminton Power”配给花店“Flower Power”
  - Overture 署名：坐标来自它的，`attribution` 是“Coordinates © Overture Maps Foundation (CDLA Permissive 2.0); address © OpenStreetMap contributors”，导出时带上，网站页脚按它署名。网络要放行 `overturemaps-us-west-2.s3.us-west-2.amazonaws.com`，装 `pyarrow==21.0.0`
  - 下次导入同类数据：先批量匹配，再一条条查剩下的；装 `timezonefinder==6.5.9`
- **网站球馆目录**：所有目录（含 `supabase/data` 和上面导出的）都列出来。只有 App 自带的球馆有自己的页面（Cloudflare Pages 一次最多 2 万个文件，现在约 9,500 个）；其余的在列表里，点开是 Google 地图。少于 3 家的城市不单独成页，按省 / 州分组列在国家页上。目录页：球馆最多的 8 个国家大卡片，其余按大洲（时区归大洲，`data-region` 用联合国编码翻译）
- **防整表拿走**：迁移 `20261224000000_venue_api_guard.sql`（测试 `venue_api_guard.test.sql`）写好了 `check_request`（不让 `anon` / `authenticated` 直接 GET `/venues`），**还没启用**：安卓 1.0.5（`android-v1.0.5-1` 已发布）有 5 处直接 `GET /venues?id=in.(…)`（`VenueApi`、`RankingsApi`、`ProfileApi`、`MatchApi`，`Backend` 搜索没搜到时按地址查表），接口这一层分不出按 id 查和整表翻页。**安卓 1.0.6 已改完**（按 id 用 `venues_by_ids`，搜索只用 `search_venues`，不再直接读表），还没发版。发 1.0.6 以后，网站装的旧包会在标签栏上面提示更新；装 1.0.5 的人都更新了（或者不再管旧包）再启用：加迁移 `alter role authenticator set pgrst.db_pre_request = 'public.check_request'; notify pgrst, 'reload config';`。按位置（`venues_near`，100 公里、200 家）、搜索（`search_venues`，50 家）、按 id（`venue_brief`）照常；网站邀请里已改用 `venue_brief`。**启用前先改** `.github/workflows/supabase-keepalive.yml`：它用公开 key 直接 `GET /rest/v1/venues?select=id&limit=1` 数球馆，启用后会失败（可以改调 `rpc/search_venues` 或 `rpc/venues_near`）。Cloudflare 上用户加了限速：`/courts/` 页同一 IP 10 秒超过 30 次拦 10 秒（认证过的搜索引擎不受限）
- **iPhone 1.0.6**：选球馆时本机搜到不到 5 家，再用 `search_venues` 补，远处城市的球馆也能按名字搜到。安卓还没有选球馆的界面

## 美国都会区的价格页（2026-11-16，网站，分支 `claude/metro-prices`，没推 main）

- 为什么：美国的球馆散在郊区小城里，大多数城市页不够 3 家、不让收录，搜 “badminton Los Angeles” 的人没有一页可看。
- `/courts/us/metro/<名字>/`（中文 `/zh/…`）：一个都会区里打羽毛球的地方，分“羽毛球馆”和“社区活动中心和学校体育馆”两张表，按散客价从低到高，列散客每人、包场每小时、场地数、开放时段。现在 16 个：洛杉矶、湾区、纽约、芝加哥、西雅图、华盛顿、圣地亚哥、达拉斯、休斯敦、奥斯汀、新泽西中部、波士顿、哥伦布、费城、匹兹堡、亚特兰大。
- 名单和半径在 `web/src/lib/metros.ts`（中心点 + 半径）。只收有自己页面的球馆（App 自带、对照官网核对过的）；够 4 家、其中 3 家有价格才成页，名单里其余的（丹佛、波特兰等）数据补上来以后自己出现。
- 入口：美国的国家页（“各都会区的散客价”）、都会区里的城市页和球馆页各有一个链接。页面进站点地图，带 ItemList 和面包屑的结构化数据。
- 其他国家没有价格数据，先不做。

## 球群的访客报名（iPhone 1.0.7，2026-11-18；数据库和网站在 main `989bc7b` 已上线，走查后的修补在分支 `claude/guest-signup-fixes`，没推 main）

需求在 `Badie-iOS/docs/GUEST_SIGNUP.md`（“要用户定的”都按建议定了），设计稿（用户已同意）是 https://claude.ai/artifact/NQRCGsWTAMYgsyhxnnkirw 的 1.0.7 那一行。组织者把链接发到原来的群里，没装 App 的人在网页上填名字就能报名或候补。

- 数据库：迁移 `20261225000000_guest_signup.sql`，测试 `supabase/tests/guest_signup.test.sql`
  - 访客也是 `session_signups` 的一行（`user_id` 空，有 `guest_name`、`guest_email`、`guest_locale`、`guest_token_hash`），主键改成 `id`、`(session_id, user_id)` 唯一。名额、候补、递补只有一份逻辑
  - `play_groups` 多 `guests_allowed`、`guest_limit`（空 = 每场名额的一半）、`guest_code`（报名链接 `badie.rsvp/g/<码>/`，8 位，和群号分开，可以重置）。关掉后链接打不开，已经报上的访客保留
  - 访客上限把候补里的访客也算上，所以递补时排第一的直接补，不用跳过谁
  - 新函数：`guest_group_page`（不登录；报名的人只给名字，注册用户给昵称，不给 id、头像、邮箱）、`guest_sign_up`（只有服务端密钥能调）、`guest_set_email`、`guest_cancel`（凭证）、`set_guest_signup`、`reset_guest_link`、`remove_guest`（组织者）
  - `promote_waitlist`、`cancel_session`、`disband_group` 认访客：留了邮箱的发邮件（沿用通知的译文，语言按报名时的网页）。报名或补填邮箱时发一封带取消链接的确认邮件（库里只存凭证的哈希，只有这时有明文）。场次结束一天后清掉访客邮箱
  - `group_page` 的 `players` 里也有访客（`guest: true`、`signed_up_at`，id 是那一行报名的 id）：旧版 App 照样解得开，人数照算（点访客会打开一个找不到的资料页）。组织者多看到 `guests_allowed`、`guest_limit`、`guest_code`
  - 防乱填：Turnstile（无感模式）；每个 IP 每小时 10 次（`guest_signup_ips`，存 IP 的哈希，一小时后删）；名字 2–20 字、不能留电话和链接、过不当词；同一场有同名的，网页上先问一句
- 服务器函数 `guest-signup`：先向 Cloudflare 核对 Turnstile，再用服务端密钥调 `guest_sign_up`，带上 IP。已加进 `supabase-deploy.yml`，`config.toml` 里不验 JWT
- 网站：`/g/<码>/` 报名页（9 种语言；场次展开看名单、填名字、可选邮箱，报了以后显示“候补第几位”、补填邮箱、取消；确认邮件里的取消链接 `?cancel=`）；已登录的人打开时让他去球群页报名。编辑球群里多“访客报名”（开关、每场上限、复制和重置链接）；球群页名单里访客标“访客”，组织者可以移出，可以复制报名链接
- iPhone 1.0.7：编辑球群里的“访客报名”（同上）、球群页“复制报名链接”、场次名单里的“访客”和组织者的“移出这一场”
- 比需求简单的地方：不另设 `guest_id`（用报名那一行的 id）
- **走查后的修补**（迁移 `20261226000000_guest_signup_fixes.sql`，测试 `guest_signup_fixes.test.sql`，和 iPhone 1.0.7 一起上；逐条见 `GUEST_SIGNUP.md` 最后一节）：
  - 网页上注册后在球群页报名，带上这台设备的访客凭证，那一行改成自己的（不占两个位子）；App 里组织者看到和成员同名的访客标“同名”
  - 组织者移出访客，留了邮箱的收到邮件；递补、改时间的邮件带取消链接（发信时换新凭证 `guest_mail_token_hash`，设备上的凭证照样能用）
  - 开场前 24 小时内有人退出、候补没人：组织者收到“有空位”（推送 + 通知）
  - 访客开场前 2 小时内退出也记临时取消；组织者在名单下面看到“临时退出”（`group_page` 每场多 `late_cancels`，只有组织者有）
  - 报名页：“换了手机就找 {组织者} 取消”；结束的场次多留 1 天、写“已结束”
  - 隐私设置“报名链接上只显示我的首字母”（`profiles.public_initials`，网站和 iPhone）
  - 改每周场次的时间、名额、费用、球馆：同一个星期几的改在原来那一场上，报名保留，报了名的人收到“场次有变”（以前是取消再重新报）。换星期几、删掉的照旧取消
  - 同一场同名的访客，后报的记成 “Tony 2”
  - 清访客邮箱改成函数 `forget_guest_emails()`（收款迁移已经改了它：开了收款的留到付清或 7 天）
- **还没做**：安卓（同样四样加上面的修补，照 iPhone 搬，不在这次范围）；邮件只有纯文字；旧版 App 点访客会打开找不到的资料页（旧版改不了，新版不能点）；同一个访客收到几封带链接的邮件时，只有最新一封的取消链接有效
- **上线前用户要做**：Supabase → Edge Functions → Secrets 加 `TURNSTILE_SECRET_KEY`（Cloudflare → Turnstile 里网站那个组件的 Secret Key，和登录用的是同一个）。没配时函数不核对人机验证，每次报名在函数日志里写一条警告。发件人沿用约球邮件的 `games@badie.rsvp`，不用另配

## 球群当晚的排场、比赛和收款（iPhone 1.0.7，2026-11-19，分支 `claude/club-night`，没推 main）

需求、接口、做完的和比需求简单的地方都在 `Badie-iOS/docs/CLUB_NIGHT.md`；设计稿是 https://claude.ai/artifact/NQRCGsWTAMYgsyhxnnkirw 的“1.0.8 当晚与比赛”那一行（按用户定的改放 1.0.7）。和访客报名一起在 1.0.7 里，目标 2026-12-05 提交审核。已合并 `claude/guest-signup-fixes`。

- 数据库：迁移 `20261228000000_club_night.sql`，测试 `club_night.test.sql`、`matches.test.sql`
  - 排场：到场、已付记在 `session_signups` 上（现场加的人也是一行访客报名）；`club_nights`、`night_games`。排人只在 `night_pick`：场数少的先、等得久的先，晚到和休息回来的从在场最少的场数算起，尽量不重复搭档和同一组人，可按实力分队；同一片场地按两次只算一次（`court_changed`），10 秒撤销，减场地时打完再收，在打比赛时空出来的场地给比赛
  - 比赛：`matches`、`match_players`、`match_games`；四种赛制，对阵开始时排好，哪片场地空了上下一场；球员自己输一次、先存的算，组织者改要带版本；积分榜按胜率、净胜分、总得分、两人之间胜负，三人以上写并列
  - 收款：`group_sessions.fee`（默认同一个每周场次上次的数）、`payment_handles`；要付的是标了到场的人（没用排场就是报上名的），收钱的人自己不用付；“我付了”记 `paid_self`；提醒 12 小时一次、结束 7 天内，访客邮件带 `badie.rsvp/pay/<凭证>/`；`forget_guest_emails()` 改成开了收款的留到付清或 7 天
  - 帮手：每晚（每场比赛）最多 3 个，结束 3 小时后失效，不能收款、结束、删除
  - “轮到你了”只推送：新表 `live_pushes`，`send-push` 带 `collapse`（同一晚互相替换）。比赛的通知是新类型 `match`，旧版 App 显示成系统通知
  - 公开看板 `live_board`（排场结束后 24 小时、比赛 7 天，只有名字）；球员的 `my_tonight`；球群页的 `group_tonight`（没改 `group_page`，旧版 App 不受影响）
- 网站：`/night/<场次>/`、`/matches/…`、`/live/<码>/`、`/pay/<凭证>/`，球群页的按钮、球局页“今晚”卡、“+”菜单“比赛 · 循环赛”（英文 Match · round robin）、设置里的收款方式；二维码用 `qrcode-generator` 2.0.4。端到端测试 `night.e2e.mjs`。隐私政策加了收款方式和访客邮箱的保留时间
- iPhone 1.0.7（版本号已改）：同样几样，看板用 App 里的 Safari 打开；`/app/matches/<id>/` 的通知打开比赛页
- **还没做**：安卓（同样几样，照 iPhone 搬，这次没动 `Badie-Android/`）；比需求简单的地方见 `CLUB_NIGHT.md`
- **上线前用户要做**：没有新的密钥。提交审核时 Notes 写一句“收款只是给出 Venmo / Cash App / PayPal 链接，钱不经过 App，是线下场地费，不走内购”（和打赏的说明分开）

## 球群的价格和收款记录（2026-11-23 推到 main：数据库、网站上线；iPhone 在 1.0.8）

用户试用当晚收款后说：看不到以前的场次和谁付了钱，付款按钮看不出能点，教练用不够。这是“第一步”（不碰钱）；第二步教练开 Stripe、报名就付钱，等这一步上线后再做。细节见 `CLUB_NIGHT.md` 的“价格和收款记录”。

- 数据库：迁移 `20261231000000_group_ledger.sql`，测试 `group_ledger.test.sql`（本机全部 48 个测试文件通过）
- 网站：建群填每人价格（0 = 免费）、球群页 / 访客报名页 / 每一场写价格、“你还没付”卡（球群页和球局页）、组织者的收款记录 `/groups/<id>/payments/`（还欠着、开过的场次、导出 CSV）和某一场 `/groups/<id>/payments/<场次>/`。`night.e2e.mjs` 加了这几步，本机通过
- iPhone：同样几样（`Features/Night/LedgerViews.swift`、编辑球群的价格、当晚页的 `payOnly`），CI 编译和测试通过。用户定了放 **1.0.8**（版本号还没改，1.0.7 提交后再改）
- 设计稿：https://claude.ai/artifact/NQRCGsWTAMYgsyhxnnkirw 的“1.0.8 价格和收款记录”那一行（7 张，按流程排）
- 安卓（2026-11-23，开发分支）：收款这一套搬完了——编辑球群的价格、球群页和场次的价格、“你还没付”卡（球群页、球局页）和付款半屏、组织者的收款记录（导出 CSV，走 FileProvider 的 `exports/`）、某一场的收款、“我的 → 收款方式”。代码在 `features/groups/PaymentScreens.kt`、`backend/PaymentsApi.kt`、`models/Payments.kt`；单元测试 `PaymentsTest`、截图 `PaymentsScreenshotTest`。1.0.7 的排场、比赛、访客报名安卓还没有
- **还没做**：金额只有美元
- 本机跑安卓构建时 Maven 中央仓库会限流（429）：给 gradlew 加 `-I <初始化脚本>`，脚本里把 `https://maven-central.storage-download.googleapis.com/maven2/` 放到 pluginManagement 和 dependencyResolutionManagement 的仓库最前面（不要改全局配置）

## 搜索：对准的词和落地页（2026-11-19，网站，已推 main）

- 主要对准两个词：**badminton partner / group app**、**badminton tournament maker**。“badminton courts” 这种通用词结果是场地尺寸文章和 Google 地图，不作为目标；球馆目录对准“城市 + badminton courts”。
- 三个只有英文的静态页（`Base` 布局，内容在 HTML 里，带 JSON-LD 和常见问题）：`/badminton-partner-app/`、`/badminton-group-app/`、`/badminton-tournament-maker/`。页脚、首页的静态内容、三页之间互相链接；首页标题改成 “Badie — free badminton partner app and court finder”。
- **排表工具**（`src/app/TournamentMaker.tsx`，排法在 `src/lib/tournament.ts`，测试 `tests/tournament.test.ts`）：不登录，填名字、选参赛方式（单打、固定搭档、轮换搭档）和赛制（循环、小组赛 + 淘汰赛、瑞士轮、单淘汰，可选三四名），排出对阵，能打印、复制链接（设置在 `#` 后面）。排法照搬服务器（`20261229000000_match_formats.sql` 的 `match_plan`、`match_preview`、`match_schedule_rr`、`match_swiss_round` 第 1 轮、`bracket_order`、`match_bracket`，和 `match_schedule_rotating`）；瑞士轮第 2 轮起、淘汰赛第 2 轮起要看比分，只写出有哪几轮。没有等级：名单顺序就是种子顺序，固定搭档按名单两两一队。“Run it live in Badie” 把名单和设置存进 sessionStorage（`badie.maker`，一小时内有效），新建比赛页（`Match.tsx` 的 `NewMatch`）读一次就删。服务器对名字要求 2–20 个字，排表这边截到 20 个字，1 个字的名字到新建比赛时才会报错。**比赛的规则再改时，这里要跟着改**（小组赛出线的同组错开这一步没搬，因为排表页不排淘汰赛的对阵）。
- 球馆目录：州 / 省统一成缩写（US、CA、AU），同一国家同名、25 公里以内的城市并成一个（以前 “Chicago, IL” 和 “Chicago, Illinois”、曼彻斯特的 6 个区各成一页）。被并掉的城市页地址没有做跳转。
- **11 月 8 日的断崖（2026-11-20 查清）**：10 月 24 日到 11 月 7 日每天 2,000–4,500 次曝光、20–70 次点击（大多是英国的球馆页，“badminton court near me” 平均第 8 位），11 月 8 日起每天约 10 次。没有人工处罚，抓取正常（Host status 没问题、99% 返回 200）；Google 只在 10 月 21–23 日抓了一大轮，之后把站点地图里的页面几乎都拿出了索引（只剩 3 个，1,738 个“Crawled - currently not indexed”）。判断是新域名、没有外链、上线就有约 3,900 个模板球馆页，Google 试了两周后整站不收。已做：中文版球馆页 noindex、不进站点地图、不和英文版互相标 hreflang（`static-i18n.ts` 的 `isVenuePath`）。还要做：英文球馆页加别处没有的内容（球群、最近约球、价格和时间），城市页做主要入口，站外链接。
- **只收录核对过的**（2026-11-20）：`web/src/lib/venues.ts` 的 `FOCUS_COUNTRIES`（美、英、韩、日）里，对照官网核对过价格或开放时间的球馆页、有这种球馆的城市页、四国的国家页才收录、进站点地图；其余 noindex，球馆目录的中文版全部不收录。核对结果在 `Badie-iOS/data/verified-venues.json`（按球馆 id，带来源链接、核对日期；`badminton: false` 表示官网写明不对外），只给网站用：App 目录的价格只能是整数（`VenueCatalog.swift`），测试 `web/tests/catalog.test.ts` 会查。英国第一批 141 家（10 个大城市）核对出 61 家，另 2 家不对外；Everyone Active、多个市政府和大学的网站挡自动访问，没核对。核对时 WebFetch 走不了会话网络，用 curl 读官网（默认 UA，不绕过拦截）；环境 “Badie Android” 的网络在 2026-11-20 改成了不限。2026-11-20 全部核对完：英国 1,359 家（Everyone Active 127 家、leisurecentre.com 33 家挡自动访问没查）里 566 家能收录；日本 58 家里 45 家（场地价只留一个单位正好一片场地的）；韩国开放数据只有名字和区，大城市 296 家从头核对，57 家有官网地址和价格或时间、查到精确位置（`Badie-iOS/data/catalogs/verified-KR.json`，`Badie-iOS/scripts/build_verified_kr.py` 生成：Nominatim 单线程 1.1 秒一次、只收落到建筑上的，查不到再用 Overture Maps 按名字找）。韩国、日本的球馆目录有韩文、日文版（/ko/、/ja/，收录，和英文互标 hreflang），开放时间有当地语言版（`playTimesLocal`）。站点地图 1,944 个网址。核对时 WebFetch 走不了网络，用 `curl` 读官网；每批 40 家一个 agent，英国一共用了约 500 万 token。
- 用户要做：Search Console 看收录（Pages 报告）、对新页面请求编入索引；Bing Webmaster Tools 导入；Cloudflare 打开 Crawler Hints；争取进 “best badminton apps” 类文章、AlternativeTo、Product Hunt。

## 已知、没修的

1. 在找人的人对能约 TA 的人都可见，改了定位的人也能看到（这是按天看人的设计；不想被看到可以在设置里关）。
2. 管理员撤下的照片文件要等本人下次传照片或注销才真正删掉（地址随机，App 里已经看不到）。
3. 卡片显示对方的整个空闲时段，右滑约的是开头 2 小时（约完的提示里写清楚）。
4. 演示模式里右滑只弹提示，不真的约。
5. 网站卡片页搜索范围固定 30 km（已修：现在可选 10/30/50/100 km），iPhone 用设置里的“附近范围”。
6. 开了一个双打局、同一时间又约成单打，双打局不会自动关。
7. 少数不常见的服务器错误会显示“出了点问题，请重试”。
8. **刚加的好友没聊过天时，消息列表里不显示这个人**（iPhone 和安卓都这样）：服务器给了这个会话，App 没列出来，iPhone 写好的“已经是好友了”预览也从没显示过。看着是 iPhone 那边的毛病，安卓照搬了，两边一起修（2026-11-16 安卓模拟器测试时发现）。

## 用户那边的待办

- 访客报名上线前：Supabase → Edge Functions → Secrets 加 `TURNSTILE_SECRET_KEY`（见上面“球群的访客报名”）。
- Cloudflare 打开 Web Analytics（网站已经接好代码）。
- 删掉不用的环境变量 `SUPABASE_READONLY_DB_URL`。
