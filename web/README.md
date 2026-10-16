# Badie 网站

Astro 静态站：公开的球馆页（给搜索引擎和 AI 搜索读的纯 HTML）。以后登录后的应用挂在 `/app/` 下。

```bash
npm ci
npm run dev      # http://localhost:4321
npm run check    # 类型检查
npm run build    # 输出到 dist/；SITE_URL 决定 canonical 和 sitemap 的域名
```

- 球馆数据读 `../Badie-iOS/Badie/Resources` 里和 App 共用的目录（不含只有大概位置的韩国数据）。
- 只有名字和地址的球馆页、不到 3 家的城市页带 `noindex`，也不进 sitemap。
- 样式变量和 iOS `Theme.swift` 一致，深色模式跟随系统。
- 布局按网页习惯，不照搬手机版：城市页是“列表 + 地图”，球馆页是两栏（右侧固定的“到这里去”卡片），首页用 bento 数字块。
- `sticker`（描边 + 硬投影）只给能点的卡片和按钮；静态色块用 `tile`（只有描边），保持“能点”的信号可靠。
