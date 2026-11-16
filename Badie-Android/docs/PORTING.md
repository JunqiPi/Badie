# 从 iPhone 搬到安卓：做法

给接着搬功能的人（和助手）看。先读 `STATUS.md` 的“安卓版”和 `CLAUDE.md`，需求在 `docs/REQUIREMENTS.md`。

## 总原则

- **功能、规则、文案和 iPhone 完全一致。** 照着 iPhone 的源文件一个一个搬，名字尽量不变；iPhone 的测试用例也照搬。
- iPhone 代码和需求文档不一致时，以 iPhone 代码为准。
- iPhone 上没有的功能不加；iPhone 上的小毛病先照搬，记下来交给用户定。

## 文字

- 界面上的字只有一份：iPhone 的 `Badie-iOS/Badie/Localizable.xcstrings`（key 就是简体中文原文）。构建时转成 10 种语言的 `strings.xml`。
- 代码里写 `tr("原文", 参数…)`：界面里用 `com.badie.app.l10n.tr`（Composable），管理器、模型里用 `com.badie.app.l10n.L10n.tr`。
- Swift 的 `String(localized: "第 \(n) 题")` 在文字表里是 `第 %lld 题`：文字参数写 `%@`，整数写 `%lld`。**先在 xcstrings 里查到准确的 key 再写。**
- 不要自己编新句子，也不要改 xcstrings。`CatalogTest` 会查每个 `tr("…")` 都在文字表里。真缺一句，写进报告。
- 列举用 `ListText.and(…)`；距离用 `DistanceFormatter`；日期时间用 `models/TimeSlot.kt` 里的 `DateText`。

## 图标

iPhone 用到的系统图标都已经对应好了：`Sym.名字`，名字是系统图标名去掉点、改成驼峰（`bolt.fill` → `Sym.boltFill`，`person.3.fill` → `Sym.person3Fill`）。画图标用 `Symbol(Sym.xxx, size = iPhone 的字号)`。真缺了：在 `scripts/icons.json` 加一行，跑 `scripts/gen_icons.py`。

## 结构

- `shell/`：启动、四个标签、导航（`Router`、`Route`）、全局弹层、`AppEnvironment`（各管理器）、下拉刷新 `RefreshEverything`。
- `design/`：设计系统（`AppTheme`、`sticker`、`card`、`BrutalButton`、`IconButton`、`ScreenHeader`、`LargeTitleHeader`、`SectionTitle`、`StatTile`、`InfoRow`、`MenuRow`、`ToastView`、`EmptyStateView`、`NoticeBanner`、`LoadingDots`、`ProgressBar`、输入框、`AvatarView`、`AvatarStack`、`LevelBadge`、`TagPill`、`ReliableBadge`、`NewPlayerBadge`、`PraiseTagsView`、`VerifiedBadge`、`RatingPicker`、`NicknameText`、`ChoiceChip`、`SegmentedSticker`、`GenderPicker`、`RulesButton`、`SheetScaffold`、`TicketShape`、`DashedDivider`、`StarburstBadge`、`CoverCard`、`CardCover`、`RoundActionLabel`、`NoShowPill`、`PersonBubble`、`markedText`、`LegalLinksRow`）。和 iPhone 的 `DesignSystem/` 对应。
- `models/`：数据和规则，对应 iPhone 的 `Models/`。
- `remote/`：`SupabaseClient`（`rpc`、`call`、`select`、`insert`、`update`、`delete`、`upload`…）、`RemoteError`（错误码对应的提示）、`json(...)` 拼参数。
- `backend/`：`Backend`（账号、资料、常去球馆、照片、推送登记）、`PhotoStore`（别人的头像、卡片背景，按需下载）。
- `push/`：推送（Firebase Cloud Messaging）。`PushRegistry`（令牌、问通知权限、链接 → 页面）、`NotificationRouter`（点通知打开页面、前台不重复弹）、`PushNotifications.kt`（解析推送、显示通知、收推送的 Service）。对应 iPhone 的 `Services/PushRegistry.swift`、`NotificationRouter.swift` 和通知扩展。Firebase 的配置在 `res/values/firebase.xml`，不用 Google Services 插件。本地提醒点开也走 `NotificationRouter`。
- `features/<功能>/`：页面和这一块的管理器。

## 页面和管理器怎么接

- 每个页面、每个管理器都已经占好位置（`features/*/…Screens.kt`、`…Manager.kt`），`shell/MainTabView.kt` 和 `AppEnvironment` 已经接好。**入口的名字和参数不要改**，里面随便改。
- 管理器：构造参数是 `ManagerContext`（`scope`、`backend`、`appState`、`android`），占位里已有的成员（`refresh()`、角标数这类）名字不变。界面在 `LocalEnv.current` 里拿 `appState`、`router` 和各管理器。
- 跳到别的功能：用 `router.open(Route.xxx)` / `router.show(...)`；看球友资料用 `appState.showPlayer(id)`。不要直接调别的功能的界面；几个跨功能的弹层已经占好：`ChallengeComposerSheet`（rankings）、`InviteComposeSheet`（home）、`LevelCardSheet`（profile）、`PlayerProfileSheet`（social）。
- 调服务器：参数、返回的字段对照 iPhone 的 `Services/Backend/MockBackend+Remote*.swift` 和 `supabase/migrations/` 里那个函数最后一次的定义。解码用 `@Serializable` 类（字段 camelCase，`RemoteJSON` 自动对应 snake_case）。
- 提示条：`appState.showToast(...)`、出错 `appState.showError(error)`。

## 测试和截图

- 单元测试放 `app/src/test/kotlin/com/badie/app/…`。调服务器的用 `remote/FakeServer`（按“方法 路径”回假数据），后端用 `TestSupport.backend(server, session)`。
- 截图测试：每个功能自己建一个 `screens/<功能>ScreenshotTest.kt`，照 `ScreenshotTest.kt` 的写法出图（`@RunWith(RobolectricTestRunner::class)`、`@GraphicsMode(NATIVE)`、`captureRoboImage`）。每个主要页面至少一张，有数据的页面用假数据。
- 跑：在 `Badie-Android/` 下 `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug --console=plain --offline`。依赖都在本机缓存里，**不要加依赖**（这里 Maven Central 限流，加了就下不来）。lint 不能有 error。

## 暂时做不了的（写进报告，不要硬做）

- 地图显示和 Google 地点搜索（要用户开 Google Cloud 的 key）：先用地址文字、距离和“导航”跳到地图 App。
- Play 的应用内评价（要加依赖）、二维码（要加依赖）。Google / Apple 登录已经做了（2026-11-16），打包、签名、上架前的设置见 `docs/RELEASE.md`。
- 推送已经能做（2026-11-16 接好 Firebase）：新的推送类型只要服务器发，App 这边按 `link` 跳转，不用改。
- 演示模式：最后统一做。
