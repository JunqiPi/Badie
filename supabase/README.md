# Badie 后端（Supabase）

设计见 [Badie-iOS/docs/BACKEND.md](../Badie-iOS/docs/BACKEND.md)。这里只放数据库迁移、SQL 函数、权限规则和测试。

```bash
npx supabase@2 db start     # 本地启动数据库（需要 Docker），自动执行 migrations/
npx supabase@2 test db      # 运行 tests/ 里的 pgTAP 测试
npx supabase@2 db lint -s public
npx supabase@2 db reset     # 改了迁移后重建本地数据库
```

- `seed.sql` 是 App 内置场馆目录（`Badie-iOS/Badie/Resources/*.json`）生成的，改了目录要运行 `python3 supabase/scripts/build_venue_seed.py`（CI 会检查）。生产库首次导入也用它。
- 客户端不直接写表：球馆的添加、确认、举报都走 `add_venue`、`confirm_venue`、`report_venue`，规则与 iOS 模拟后端一致。
- 密钥（Apple/Google 登录、APNs）只放在 Supabase 后台和 GitHub Secrets，`config.toml` 里用 `env(...)` 引用，绝不提交。
