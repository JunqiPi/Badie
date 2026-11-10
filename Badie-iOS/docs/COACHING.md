# 教练：先用球群带课（小版本）

> 2026-11-10 写。给工程 agent 和宣传 agent。
> 用户定的方向：先做这个小版本，不碰钱、不建新表，看教练能不能带来约球的人。完整方案（收款、课时包、少儿档案等）在 `COACHING_LATER.md`，达到第 5 节的条件再做。
> 进度：第 3 节的数据库、网站、iPhone 已经做了（迁移 `20261209000000_coached_groups.sql`），先带用户认识的一个教练试。教练简介和列表筛选等教练多了再做。
> 证据分三档：**[官方]** 平台或球馆自己的页面；**[用户]** 真实用户的评价；**[推断]** 我们自己的判断，要验证。

## 1. 为什么只做小的

- **找教练当种子有依据**：Hinz 等 2011（《Journal of Marketing》）：先找人脉广的人，推荐数比随机找多一半以上。同一篇也说，这些人只是认识的人多，说服力并不更强。论文支持的是“去找教练”，没有说要给教练做一套系统。
- **教练没有换工具的理由** **[推断]**：微信接龙加 Zelle 能凑合，Zelle 不收费，刷卡要 2.9% + 30¢。
- **我们独有的是帮教练找新学员，刚上线时还给不出学员** **[推断]**。TeachMe.To 抽成 20%（二手数字）教练仍然来，图的是学员，不是工具。
- **独立教练可能比想象的少** **[官方]**：Canada Elite Badminton 要求外来教练先获批准；George Brown、BA Active 只许本馆教练；Langley 一家社区场地禁止私教。馆内教练用球馆的系统。
- **缺的证据**：没搜到羽毛球教练亲口说自己用什么工具。所以第 2 节先去问。

## 2. 先问 5 个教练（宣传 agent，不用写代码）

发帖、私信按 `MARKETING_BRIEF.md` 的规矩先给用户看。要问清楚四件事：

1. 现在怎么排课、怎么收钱，最烦的是哪一步。
2. 在哪里上课，球馆让不让自己带学员。
3. 学员下课以后找不找人练球，怎么找。
4. 给一个链接，学员点开就能报名每周的课，愿不愿意发到自己的学员群里。

第 4 条多数人说不愿意，就不用再往下加功能。现在只有一个教练，先问这一位。

## 3. 做什么

都在现有球群上改。Badie 不经手钱。

| 改动 | 现在 | 改成 |
|---|---|---|
| 球群加“教练带课”标记 | 没有（房间有“可指导”标签） | 已做。建群和编辑时可以勾，球群卡片和球群页带“教练带课”标签 |
| 每场人数 | 4–40 | 已做。教练带课的群 1–40（私教、小班都能开）；普通群不变 |
| 收费备注 | 40 字 | 已做。120 字，教练写价格和自己的收款方式。纯文字，不做成可点的链接。iPhone 上原来不能填、也不显示，现在都有了 |
| 水平范围 | 超出范围进不去 | 已做。教练带课的群只作提示，谁都能加入或申请；要筛人就用现有的“需要审批” |
| 看效果 | 没有 | 已做，见第 4 节 |
| 教练简介 | 资料里没有 | **先不做**。只有一个教练时，球群的 120 字介绍够用。教练多了再在资料里加 |
| 找得到 | 球群列表没有筛选 | **先不做**。只有一个教练的群，筛选没有意义；标签已经有了 |

不用改的：邀请链接（`badie.rsvp/join/?code=…`，已经能点）、报名、候补、递补、组织者取消某一场、群聊。

### 边界

- **教练不占名额**：教练是群主，不报名；人数指学员。
- **不核验**：标记和简介都是自己填的，界面上照实写“自己填写”。举报、拉黑、内容过滤沿用现有的。
- **钱的事不归我们**：收费、退款、请假补课由教练和学员自己商量。不做评价、点名、课时包。
- **未成年人**：用户协议是 13 岁以上，不做孩子档案。少儿课由家长用自己的账号报名。
- **缺席**：球群场次现在不记爽约，教练带课的群也一样。
- **苹果审核**：App 里没有付款，不涉及内购规则。

### 实现提示

- 迁移 `20261209000000_coached_groups.sql`：`play_groups.coached`；`group_schedules` 的人数和备注长度约束；`create_group`、`update_group` 多一个 `p_coached`；`join_group` 对教练带课的群跳过 `level_out_of_range`。测试在 `supabase/tests/coached_groups.test.sql`。
- **旧版 App 照常能用**：建群不传 `p_coached` 就是普通群；编辑不传就保持原样，不会把标记弄丢。
- 网站 `NewGroup.tsx`、`Group.tsx`、`Groups.tsx`，iPhone `Features/Groups/GroupViews.swift`、`Models/PlayGroup.swift`。
- 上线后 `STORY.md` 的功能表加一行“教练可以用球群带课”。价格口径不变：全部免费。

## 4. 看什么数字

不用新表，现有数据就能算。在 Supabase 的 SQL 编辑器里跑 `select * from public.coached_group_stats();`（App 里调不到），每个教练带课的群一行：

- `students`：学员数，不算教练和等审批的人。
- `new_users`：**教练带来的新用户**，加群前 24 小时内才注册的人。
- `new_users_who_played`：**这些人里有多少去约了球**，加群后 14 天内发过约球请求、进过球局或房间。

第二、三个数字就是这件事值不值得做下去的答案。

## 5. 什么时候做完整方案

同时满足三条，再打开 `COACHING_LATER.md`（门槛是 **[推断]**，用户可以调）：

1. 至少 5 个教练，每人带来 10 个以上新用户。
2. 这些新用户里三成以上在 14 天内约过球。
3. 教练主动提出要在 App 里收款。

到那时也分两步：先让教练在收费备注里贴自己的 Stripe 付款链接（不用写代码），还不够用再接 Stripe Connect。

## 来源

- Hinz 等 2011：https://ama.org/2019/01/16/seeding-strategies-for-viral-marketing-an-empirical-comparison
- 球馆对外来教练的规定：https://elitebadminton.ca/court-rental/ ，https://sites.google.com/site/gbcbaddy/club-information/rules-regulations ，https://www.bactivebadminton.com/court-rentals ，https://www.active.com/langley-bc/racquet-sports/badminton-classes/badminton-court-rental-court-2-2027-110884590
- TeachMe.To 的教练和学员评价：https://ie.trustpilot.com/review/teachme.to?page=2
- 刷卡手续费：https://stripe.com/pricing
