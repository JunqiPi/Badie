# Google Play 上架材料（安卓版）

> 2026-11-16 写。商店文字按 `Badie-iOS/docs/STORY.md`（只说做到了的）和 `VOICE.md`（平实、不用感叹号和表情）。
> 文案从 iPhone 的 `Badie-iOS/docs/STORE_LISTING.md` 改过来，改动只有：去掉二维码（安卓第一版没有，换成加球友链接）；中文描述第一句点明“羽毛球 / 羽球”（Play 没有关键词栏，搜索看名称和说明）。没有提 Apple 地图、手表、小组件这类 iPhone 才有的东西，也没提地图。
> 字数用 Python 的 `len()` 数（按字符）。Play 的限制：名称 30、简短说明 80、完整说明 4000、版本说明 500。
> 对照过 Spond、Strava 现在挂在 Play 上的说明：简短说明是一句平实的话，完整说明是一段话加一串“•”短句，和 iPhone 的写法一致，所以没有改结构。

## 0. 提交前要先办的事

1. **隐私政策要补安卓**（`https://badie.rsvp/privacy/`）：现在的“Service providers”只写了 Apple 推送和浏览器推送，要加上 **Google 的 Firebase Cloud Messaging（安卓推送）**；“Visit counts”那条写着“The iPhone app doesn’t use it”，改成“The apps don’t use it”。以后接了 Google 地图，再加 Google Maps / Places。数据安全表要和隐私政策对得上，Play 会对。
2. **删除账号的网页**：Play 要一个不用装 App 也能申请删除的网址，页面上要能看到 Badie 的名字和删除的步骤（或邮箱）。现在最接近的是 `https://badie.rsvp/contact/`（“Delete your account”一条 + 邮箱），但这一条是页面脚本渲染的，静态 HTML 里只有邮箱。建议在网站加一个简单的 `/delete-account/` 页（写清“登录后在 Settings → Delete account；或发邮件到 support@badie.rsvp，30 天内删除”），再把网址填进 Play。
3. **Ko-fi 打赏入口**：Play 的付款政策只给“免税的慈善捐款”开了口子，给开发者的打赏没有明说可以链到站外付款。建议安卓第一版**先不显示**“支持 Badie”，上架稳定后再对政策原文定（`REQUIREMENTS.md` 第 12 节第 1 条）。现在代码按手机卡地区显示，要改代码（这份文档没动代码）。
4. **审核账号**：见第 6 节。
5. **登录方式**：现在安卓只有邮箱（密码 / 验证码）。iPhone 上用 Apple 或 Google 登录的人，在安卓上只能用验证码登录（Apple 隐藏邮箱也能收到码）。版本说明里写了“用同一个账号登录”，上架前 Google / Apple 登录最好做完；没做完就保持现在的写法，问题不大。

## 1. 商店页文案和第一版的版本说明（10 种语言）

- 默认语言选 English (United States)，其余 9 种在“管理翻译 → 添加自己的翻译”里加。语言代码：`en-US`、`zh-CN`、`zh-TW`、`ja-JP`、`ko-KR`、`id`、`ms`、`th`、`vi`、`hi-IN`（Play 里马来语可能显示为 `ms` 或 `ms-MY`，以 Console 为准）。
- **版本说明**可以一次贴进去：Play 的版本说明框认 `<en-US>…</en-US>` 这种标签，把下面 10 段带标签的连起来贴进一个框就行。
- **中文名称**：iPhone 上中文名是“轻羽 / 輕羽”，但安卓装好后桌面上显示的是 `Badie`（`android:label` 没有分语言）。所以 Play 的中文名称写成“轻羽 Badie：…”，让两边都对得上。要不要把安卓桌面名也改成按语言显示“轻羽”，见文末的问题。
- 繁体：台湾说“羽球”、香港说“羽毛球”，名称里放“羽毛球”，简短说明和描述第一句用“羽球”，结尾一句有“羽毛球”。

### English (U.S.)（`en-US`）

- 应用名称（22/30）：`Badie: Badminton Buddy`
- 简短说明（70/80）：

  ```
  Tell Badie when you're free. It finds badminton players at your level.
  ```

- 完整说明（1316/4000）：

```
Too shy to ask strangers at the court for a game? Badie finds players for you.

Tell Badie when you're free and which courts you can get to, and it finds players at your level. If your usual partner can't make it tonight, find someone who's free at the same time. If you've just moved, see the courts nearby and join a group that plays every week.

• See who's free: tap a day and swipe through nearby players at your level who want a game that day. Swipe right to invite.
• Players who show up: no-shows and late cancellations are tracked, and both sides confirm results.
• Levels that stay accurate: a 2-minute quiz places you on a 1–9 scale, and players you meet help calibrate it. Men's and women's levels are rated separately.
• Last-minute games: booked a court but short on players? Post it and nearby players can join.
• Any event: singles, doubles, men's, women's or mixed doubles.
• Weekly groups: same time and court every week, with sign-ups and a waitlist.
• Add friends by nickname#1234 or send them your friend link.
• Weekly and court leaderboards, challenges and win rate.
• Private by default: players see your nickname and level, not your contact details. Your location is only used to find courts nearby and is never stored.

Badie is free. We want more people around the world playing badminton.
```

- 第一版的版本说明（262/500）：

```
<en-US>
Badie is now on Android.

Tell Badie when you're free and which courts you can get to, and it finds badminton players at your level. If you already use Badie on the website or iPhone, sign in with the same account. Your games, friends and messages are all there.
</en-US>
```

### 简体中文（`zh-CN`）

- 应用名称（15/30）：`轻羽 Badie：找羽毛球搭子`
- 简短说明（27/80）：

  ```
  说一声你哪天有空，Badie 按实力帮你找羽毛球搭子。
  ```

- 完整说明（476/4000）：

```
不好意思在球馆里找陌生人打羽毛球？Badie 帮你找。

告诉 Badie 你哪天有空、能去哪几家球馆，它会帮你找实力差不多的人。固定搭子今晚来不了，就找个同一时间有空的；刚搬到新城市，先看看附近有哪些球馆，再加入一个每周固定打的球群。

• 看哪天谁有空：点一天，附近实力对得上、那天也想打的人一张张翻，右滑就约。
• 实力对得上：2 分钟做完定级问卷，从 1 到 9 级。打过几场后，球友的评价会帮你校准等级。男女分开定级。
• 不怕被放鸽子：爽约和临时取消都会记下来，180 天内爽约三次就不能再约球。比分要双方都确认才算。
• 场地缺人：订了场还差一两个人，发个球局，附近的人可以直接加入。
• 单打、双打、男双、女双、混双都能约。
• 每周球群：固定时间、固定球馆，报满了自动排候补。
• 加球友：搜“昵称#编号”，或者把你的加球友链接发给对方。
• 想比一比的话，有周榜、球馆排行、挑战和胜率。
• 别人只看得到你的昵称和实力，看不到联系方式。位置只用来找附近的球馆，不会保存。

Badie 完全免费。我们想让世界各地有更多人打上羽毛球。
```

- 第一版的版本说明（92/500）：

```
<zh-CN>
Badie 有安卓版了。

告诉 Badie 你哪天有空、能去哪几家球馆，它按实力帮你找球友。已经在网站或 iPhone 上用 Badie 的，用同一个账号登录，球局、球友和消息都在。
</zh-CN>
```

### 繁體中文（`zh-TW`）

- 应用名称（15/30）：`輕羽 Badie：找羽毛球球友`
- 简短说明（26/80）：

  ```
  說一聲你哪天有空，Badie 依實力幫你找羽球球友。
  ```

- 完整说明（475/4000）：

```
不好意思在球館裡找陌生人打羽球？Badie 幫你找。

告訴 Badie 你哪天有空、能去哪幾間球館，它會幫你找實力差不多的人。固定球友今晚來不了，就找個同一時間有空的；剛搬到新城市，先看看附近有哪些球館，再加入一個每週固定打的球群。

• 看哪天誰有空：點一天，附近實力對得上、那天也想打的人一張張翻，右滑就約。
• 實力對得上：2 分鐘做完分級問卷，從 1 到 9 級。打過幾場後，球友的評價會幫你校準等級。男女分開分級。
• 不怕被放鴿子：爽約和臨時取消都會記下來，180 天內爽約三次就不能再約球。比賽結果要雙方都確認才算。
• 場地缺人：訂了場還差一兩個人，發個球局，附近的人可以直接加入。
• 單打、雙打、男雙、女雙、混雙都能約。
• 每週球群：固定時間、固定球館，額滿後自動候補。
• 加球友：搜「暱稱#編號」，或把你的加球友連結傳給對方。
• 想比一比的話，有週榜、球館排行、挑戰和勝率。
• 別人只看得到你的暱稱和實力，看不到聯絡方式。位置只用來找附近的球館，不會保存。

Badie 完全免費。我們想讓世界各地有更多人打上羽毛球。
```

- 第一版的版本说明（99/500）：

```
<zh-TW>
Badie 有 Android 版了。

告訴 Badie 你哪天有空、能去哪幾間球館，它依實力幫你找球友。已經在網站或 iPhone 上用 Badie 的，用同一個帳號登入，球局、球友和訊息都在。
</zh-TW>
```

### 日本語（`ja-JP`）

- 应用名称（16/30）：`Badie：バドミントン仲間探し`
- 简短说明（39/80）：

  ```
  空いている日を伝えると、Badie がレベルの近いバドミントン仲間を探します。
  ```

- 完整说明（710/4000）：

```
知らない人に「一緒に打ちませんか」と声をかけるのは気が引けるものです。Badie が代わりに探します。

空いている日時と行ける体育館を伝えると、レベルの近い相手を探します。いつものペアが来られない夜は同じ時間に空いている人を、引っ越したばかりなら近くの体育館と毎週の定期グループを見つけられます。

• 空いている人を見る：日付を選ぶと、その日に相手を探している、レベルの近い近くの人が 1 人ずつ表示されます。右にスワイプすると誘えます。
• レベルが合う：2 分の質問で 1〜9 のレベルを判定します。一緒に打った人の評価で、だんだん正確になります。男女は別々に判定します。
• ドタキャンされにくい：ドタキャンと直前のキャンセルは記録され、180 日以内に 3 回ドタキャンすると試合に参加できなくなります。試合結果は両チームが確認したものだけ反映されます。
• あと一人足りないとき：コートを取ったのに人数が足りなければ募集を出せます。近くの人がそのまま参加できます。
• シングルス、ダブルス、男子・女子ダブルス、ミックスダブルス、どれでも探せます。
• 毎週の定期グループ：同じ曜日、同じ体育館。定員を超えると自動でキャンセル待ちになります。
• 友達追加：「ニックネーム#番号」で検索するか、友達追加リンクを送ります。
• 週間ランキング、体育館ランキング、挑戦、勝率もあります。
• 相手に見えるのはニックネームとレベルだけで、連絡先は見えません。位置情報は近くの体育館を探すときにだけ使い、保存しません。

Badie は無料です。世界中でもっと多くの人にバドミントンを楽しんでほしいと思っています。
```

- 第一版的版本说明（137/500）：

```
<ja-JP>
Badie が Android で使えるようになりました。

空いている日と行ける体育館を伝えると、レベルの近い相手を探します。ウェブ版や iPhone で Badie を使っている方は、同じアカウントでログインしてください。試合、友達、メッセージはそのまま引き継がれます。
</ja-JP>
```

### 한국어（`ko-KR`）

- 应用名称（18/30）：`Badie: 배드민턴 파트너 찾기`
- 简短说明（45/80）：

  ```
  시간 되는 날을 알려 주면 Badie가 실력이 비슷한 배드민턴 상대를 찾아 줘요.
  ```

- 完整说明（767/4000）：

```
체육관에서 처음 보는 사람에게 같이 치자고 하기 어렵죠. Badie가 대신 찾아 드려요.

시간 되는 날과 갈 수 있는 체육관을 알려 주면 실력이 비슷한 사람을 찾아 줘요. 늘 같이 치던 파트너가 오늘 못 오면 같은 시간에 비는 사람을, 이사 온 지 얼마 안 됐다면 근처 체육관과 매주 모이는 모임을 찾을 수 있어요.

• 그날 시간 되는 사람 보기: 날짜를 누르면 그날 상대를 찾고 있는, 실력이 비슷한 근처 사람이 한 명씩 나와요. 오른쪽으로 밀면 초대해요.
• 실력이 맞아요: 2분짜리 질문으로 1~9 레벨을 정해요. 같이 쳐 본 사람들의 평가로 점점 정확해져요. 남녀 레벨은 따로 매겨요.
• 노쇼 걱정이 적어요: 노쇼와 직전 취소는 기록되고, 180일 안에 노쇼가 세 번이면 더 이상 게임에 참여할 수 없어요. 경기 결과는 양쪽이 모두 확인해야 반영돼요.
• 한 명이 모자랄 때: 코트는 잡았는데 사람이 모자라면 모집 글을 올리세요. 근처 사람이 바로 들어올 수 있어요.
• 단식, 복식, 남복, 여복, 혼복 모두 찾을 수 있어요.
• 정기 모임: 매주 같은 시간, 같은 체육관이에요. 정원이 차면 자동으로 대기 순번에 들어가요.
• 친구 추가: '닉네임#번호'로 검색하거나 친구 추가 링크를 보내면 돼요.
• 주간 랭킹, 체육관 랭킹, 도전, 승률도 있어요.
• 상대에게는 닉네임과 레벨만 보이고 연락처는 보이지 않아요. 위치는 근처 체육관을 찾을 때만 쓰고 저장하지 않아요.

Badie는 무료예요. 세계 곳곳에서 더 많은 사람이 배드민턴을 즐기면 좋겠어요.
```

- 第一版的版本说明（141/500）：

```
<ko-KR>
이제 Android에서도 Badie를 쓸 수 있어요.

시간 되는 날과 갈 수 있는 체육관을 알려 주면 실력이 비슷한 사람을 찾아 줘요. 웹이나 iPhone에서 Badie를 쓰고 있다면 같은 계정으로 로그인하세요. 게임, 친구, 메시지가 그대로 있어요.
</ko-KR>
```

### Bahasa Indonesia（`id`）

- 应用名称（27/30）：`Badie: Cari Teman Badminton`
- 简短说明（72/80）：

  ```
  Beri tahu kapan kamu kosong, Badie carikan lawan badminton yang selevel.
  ```

- 完整说明（1582/4000）：

```
Sungkan mengajak orang yang belum dikenal untuk main di GOR? Badie yang mencarikan.

Beri tahu kapan kamu kosong dan GOR mana saja yang bisa kamu datangi, Badie akan mencarikan pemain yang levelnya mirip. Pasangan mainmu berhalangan malam ini? Cari orang lain yang kosong di jam yang sama. Baru pindah kota? Lihat GOR terdekat dan bergabung dengan grup yang main setiap minggu.

• Lihat siapa yang kosong: ketuk satu hari, lalu geser kartu pemain di sekitarmu yang selevel dan sedang mencari lawan hari itu. Geser ke kanan untuk mengajak.
• Level yang pas: kuis 2 menit menempatkanmu di level 1–9, lalu penilaian dari pemain yang pernah main denganmu membuatnya makin akurat. Level putra dan putri dihitung terpisah.
• Lebih sedikit yang mangkir: ketidakhadiran dan pembatalan mendadak dicatat. Tiga kali tidak hadir dalam 180 hari, kamu tidak bisa ikut main lagi. Hasil pertandingan baru dihitung setelah dikonfirmasi kedua tim.
• Kurang orang: sudah pesan lapangan tapi kurang satu atau dua pemain? Umumkan, pemain di sekitar bisa langsung bergabung.
• Tunggal, ganda, ganda putra, ganda putri, dan ganda campuran.
• Grup mingguan: jam dan GOR yang sama setiap minggu. Kalau sudah penuh, kamu otomatis masuk daftar tunggu.
• Tambah teman: cari "nama#nomor", atau kirim link temanmu.
• Ada peringkat mingguan, peringkat GOR, tantangan, dan persentase menang.
• Orang lain hanya melihat nama panggilan dan levelmu, bukan kontakmu. Lokasi hanya dipakai untuk mencari GOR terdekat dan tidak disimpan.

Badie gratis. Kami ingin lebih banyak orang di seluruh dunia bermain bulu tangkis.
```

- 第一版的版本说明（267/500）：

```
<id>
Badie sekarang ada di Android.

Beri tahu kapan kamu kosong dan GOR mana saja yang bisa kamu datangi, Badie akan mencarikan pemain yang levelnya mirip. Kalau sudah memakai Badie di web atau iPhone, masuk dengan akun yang sama. Permainan, teman, dan pesanmu tetap ada.
</id>
```

### Bahasa Melayu（`ms`）

- 应用名称（27/30）：`Badie: Cari Rakan Badminton`
- 简短说明（71/80）：

  ```
  Beritahu bila anda lapang, Badie carikan pemain badminton yang setahap.
  ```

- 完整说明（1709/4000）：

```
Segan mengajak orang yang tidak dikenali untuk bermain di gelanggang? Biar Badie yang carikan.

Beritahu bila anda lapang dan gelanggang mana yang boleh anda pergi, Badie akan carikan pemain yang tahapnya hampir sama. Pasangan biasa anda tidak dapat datang malam ini? Cari orang lain yang lapang pada masa yang sama. Baru berpindah ke bandar baharu? Lihat gelanggang berdekatan dan sertai kumpulan yang bermain setiap minggu.

• Lihat siapa yang lapang: ketik satu hari, kemudian leret kad pemain berdekatan yang setahap dan sedang mencari permainan pada hari itu. Leret ke kanan untuk mengajak.
• Tahap yang sesuai: kuiz 2 minit meletakkan anda pada tahap 1–9, dan penilaian daripada pemain yang pernah bermain dengan anda menjadikannya semakin tepat. Tahap lelaki dan wanita dikira berasingan.
• Kurang yang tidak hadir: ketidakhadiran dan pembatalan saat akhir direkodkan. Tiga kali tidak hadir dalam 180 hari, anda tidak boleh menyertai permainan lagi. Keputusan perlawanan hanya dikira selepas disahkan oleh kedua-dua pasukan.
• Tidak cukup orang: sudah tempah court tetapi kurang seorang dua? Siarkan, pemain berdekatan boleh terus menyertai.
• Perseorangan, beregu, beregu lelaki, beregu wanita dan beregu campuran.
• Kumpulan mingguan: masa dan gelanggang yang sama setiap minggu. Jika penuh, anda terus masuk senarai menunggu.
• Tambah rakan: cari "nama#nombor", atau hantar pautan rakan anda.
• Ada carta mingguan, carta gelanggang, cabaran dan kadar menang.
• Orang lain hanya nampak nama panggilan dan tahap anda, bukan maklumat hubungan. Lokasi hanya digunakan untuk mencari gelanggang berdekatan dan tidak disimpan.

Badie percuma. Kami mahu lebih ramai orang di seluruh dunia bermain badminton.
```

- 第一版的版本说明（273/500）：

```
<ms>
Badie kini ada di Android.

Beritahu bila anda lapang dan gelanggang mana yang boleh anda pergi, Badie akan carikan pemain yang setahap. Jika anda sudah menggunakan Badie di laman web atau iPhone, log masuk dengan akaun yang sama. Permainan, rakan dan mesej anda tetap ada.
</ms>
```

### ไทย（`th`）

- 应用名称（20/30）：`Badie: หาเพื่อนตีแบด`
- 简短说明（54/80）：

  ```
  บอกว่าว่างวันไหน แล้ว Badie จะหาคนตีแบดฝีมือใกล้กันให้
  ```

- 完整说明（1134/4000）：

```
ไม่กล้าชวนคนที่ไม่รู้จักมาตีด้วยกันที่สนามใช่ไหม Badie หาให้

บอก Badie ว่าว่างวันไหน ไปสนามไหนได้บ้าง แล้ว Badie จะหาคนฝีมือใกล้กันให้ คู่ตีประจำมาไม่ได้คืนนี้ก็หาคนที่ว่างเวลาเดียวกัน เพิ่งย้ายมาเมืองใหม่ก็ดูสนามใกล้ ๆ แล้วเข้าก๊วนที่ตีกันทุกสัปดาห์

• ดูว่าใครว่าง: แตะวันที่ แล้วปัดดูคนแถวนั้นที่ฝีมือใกล้กันและกำลังหาคนตีในวันนั้น ปัดขวาเพื่อชวน
• ฝีมือตรงกัน: ทำแบบสอบถาม 2 นาทีเพื่อจัดระดับ 1–9 แล้วคะแนนจากคนที่เคยตีด้วยจะช่วยให้แม่นขึ้นเรื่อย ๆ ระดับชายและหญิงคิดแยกกัน
• ลดการเบี้ยวนัด: การเบี้ยวนัดและการยกเลิกกะทันหันจะถูกบันทึก ถ้าเบี้ยวนัด 3 ครั้งใน 180 วันจะเข้าร่วมเกมไม่ได้อีก ผลการแข่งขันนับเมื่อทั้งสองฝ่ายยืนยันแล้วเท่านั้น
• คนไม่ครบ: จองคอร์ทแล้วแต่ยังขาดหนึ่งสองคน ประกาศหาได้ คนแถวนั้นเข้าร่วมได้ทันที
• ตีเดี่ยว ตีคู่ คู่ชาย คู่หญิง และคู่ผสม
• ก๊วนประจำสัปดาห์: เวลาเดิม สนามเดิมทุกสัปดาห์ ถ้าเต็มจะต่อคิวสำรองให้อัตโนมัติ
• เพิ่มเพื่อน: ค้นหา "ชื่อเล่น#หมายเลข" หรือส่งลิงก์เพิ่มเพื่อนของคุณ
• มีอันดับประจำสัปดาห์ อันดับประจำสนาม การท้าแข่ง และอัตราชนะ
• คนอื่นเห็นแค่ชื่อเล่นกับระดับของคุณ ไม่เห็นช่องทางติดต่อ ตำแหน่งใช้แค่หาสนามใกล้ ๆ และไม่ถูกเก็บไว้

Badie ใช้ฟรี เราอยากให้คนทั่วโลกได้ตีแบดกันมากขึ้น
```

- 第一版的版本说明（199/500）：

```
<th>
Badie ใช้บน Android ได้แล้ว

บอก Badie ว่าว่างวันไหน ไปสนามไหนได้บ้าง แล้ว Badie จะหาคนฝีมือใกล้กันให้ ถ้าใช้ Badie บนเว็บหรือ iPhone อยู่แล้ว เข้าสู่ระบบด้วยบัญชีเดิม เกม เพื่อน และข้อความยังอยู่ครบ
</th>
```

### Tiếng Việt（`vi`）

- 应用名称（28/30）：`Badie: Tìm bạn đánh cầu lông`
- 简短说明（71/80）：

  ```
  Cho biết bạn rảnh hôm nào, Badie tìm người đánh cầu lông cùng trình độ.
  ```

- 完整说明（1400/4000）：

```
Ngại rủ người chưa quen đánh cùng ở sân? Để Badie tìm giúp.

Cho Badie biết bạn rảnh hôm nào, đến được những sân nào, Badie sẽ tìm người có trình độ gần với bạn. Bạn đánh quen tối nay bận thì tìm người rảnh cùng giờ. Mới chuyển đến thành phố mới thì xem các sân gần đây và vào một nhóm đánh cố định hằng tuần.

• Xem ai rảnh: chạm vào một ngày rồi lướt qua những người ở gần, cùng trình độ, đang tìm người đánh hôm đó. Vuốt phải để rủ.
• Đúng trình độ: bài trắc nghiệm 2 phút xếp bạn vào mức 1–9, sau đó đánh giá của những người từng đánh cùng sẽ giúp mức này ngày càng chính xác. Trình độ nam và nữ được tính riêng.
• Bớt bùng kèo: bùng kèo và hủy sát giờ đều được ghi lại. Bùng kèo 3 lần trong 180 ngày sẽ không được tham gia trận nữa. Kết quả trận chỉ được tính khi cả hai bên xác nhận.
• Thiếu người: đặt sân rồi mà còn thiếu một hai người thì đăng lên, người ở gần có thể vào ngay.
• Đánh đơn, đánh đôi, đôi nam, đôi nữ và đôi nam nữ.
• Nhóm cố định hằng tuần: cùng giờ, cùng sân mỗi tuần. Đủ người thì bạn tự động vào danh sách chờ.
• Kết bạn: tìm "biệt danh#số", hoặc gửi link kết bạn của bạn.
• Có bảng xếp hạng tuần, xếp hạng theo sân, thách đấu và tỉ lệ thắng.
• Người khác chỉ thấy biệt danh và trình độ của bạn, không thấy thông tin liên lạc. Vị trí chỉ dùng để tìm sân gần đây và không được lưu lại.

Badie miễn phí. Chúng tôi muốn ngày càng nhiều người trên khắp thế giới chơi cầu lông.
```

- 第一版的版本说明（249/500）：

```
<vi>
Badie đã có trên Android.

Cho Badie biết bạn rảnh hôm nào, đến được những sân nào, Badie sẽ tìm người có trình độ gần với bạn. Nếu bạn đã dùng Badie trên web hoặc iPhone, hãy đăng nhập bằng tài khoản cũ. Trận đấu, bạn bè và tin nhắn vẫn còn nguyên.
</vi>
```

### हिन्दी（`hi-IN`）

- 应用名称（29/30）：`Badie: बैडमिंटन पार्टनर खोजें`
- 简短说明（69/80）：

  ```
  बताइए आप कब फ़्री हैं, Badie आपके लेवल के बैडमिंटन खिलाड़ी ढूँढ देगा।
  ```

- 完整说明（1492/4000）：

```
कोर्ट पर अनजान लोगों से साथ खेलने के लिए पूछने में झिझक होती है? Badie आपके लिए ढूँढ देगा।

बताइए आप किस दिन फ़्री हैं और किन कोर्ट तक जा सकते हैं, Badie आपके जैसे लेवल वाले खिलाड़ी ढूँढेगा। आपका रोज़ का पार्टनर आज नहीं आ सकता, तो उसी समय फ़्री किसी और के साथ खेलिए। नए शहर में आए हैं, तो पास के कोर्ट देखिए और हर हफ़्ते खेलने वाले ग्रुप से जुड़िए।

• देखें कौन फ़्री है: कोई दिन चुनिए और पास के उन खिलाड़ियों के कार्ड देखिए जो आपके लेवल के हैं और उस दिन खेलना चाहते हैं। बुलाने के लिए दाईं ओर स्वाइप कीजिए।
• सही लेवल: 2 मिनट की प्रश्नावली आपको 1–9 के लेवल पर रखती है, फिर साथ खेले लोगों की रेटिंग से यह और सटीक होता जाता है। पुरुष और महिला लेवल अलग गिने जाते हैं।
• कम नो-शो: नो-शो और आख़िरी समय पर कैंसल करना दर्ज होता है। 180 दिनों में 3 बार नो-शो हुआ तो आप आगे गेम में शामिल नहीं हो पाएँगे। मैच का नतीजा तभी गिना जाता है जब दोनों टीमें पुष्टि करें।
• खिलाड़ी कम हैं: कोर्ट बुक है पर एक-दो लोग कम हैं, तो गेम पोस्ट कीजिए, पास के खिलाड़ी सीधे जुड़ सकते हैं।
• सिंगल्स, डबल्स, मेन्स डबल्स, विमेन्स डबल्स और मिक्स्ड डबल्स।
• हर हफ़्ते का ग्रुप: हर हफ़्ते वही समय, वही कोर्ट। जगह भर जाए तो आप अपने-आप वेटलिस्ट में आ जाते हैं।
• दोस्त जोड़ें: "निकनेम#नंबर" से खोजिए, या अपना दोस्त लिंक भेजिए।
• हफ़्ते की रैंकिंग, कोर्ट की रैंकिंग, चैलेंज और जीत का प्रतिशत भी है।
• दूसरों को सिर्फ़ आपका निकनेम और लेवल दिखता है, संपर्क जानकारी नहीं। लोकेशन सिर्फ़ पास के कोर्ट ढूँढने में इस्तेमाल होती है और सेव नहीं होती।

Badie मुफ़्त है। हम चाहते हैं कि दुनिया भर में ज़्यादा से ज़्यादा लोग बैडमिंटन खेलें।
```

- 第一版的版本说明（250/500）：

```
<hi-IN>
Badie अब Android पर भी है।

बताइए आप किस दिन फ़्री हैं और किन कोर्ट तक जा सकते हैं, Badie आपके जैसे लेवल वाले खिलाड़ी ढूँढेगा। अगर आप वेबसाइट या iPhone पर Badie इस्तेमाल करते हैं, तो उसी अकाउंट से साइन इन कीजिए। आपके गेम, दोस्त और मैसेज वहीं मिलेंगे।
</hi-IN>
```

## 2. 数据安全表（Play Console → 应用内容 → 数据安全）

依据：`supabase/migrations` 里存的表、隐私政策、安卓的 `AndroidManifest.xml` 和合并后的清单（2026-11-16 的调试包）。

**总的问题**

| 问题 | 答 | 说明 |
|---|---|---|
| 是否收集或分享表里列的用户数据 | 是 | |
| 所有数据传输时都加密 | 是 | 正式包只走 HTTPS（`network_security_config.xml` 不允许明文），Supabase、Firebase 都是 TLS |
| 用户怎么创建账号 | 选“用户名、密码和其他身份验证方式”一类的选项 | 邮箱 + 密码，或邮箱验证码。以后加了 Google / Apple 登录，再勾 OAuth。选项的原文以 Console 为准 |
| 删除账号的网址 | 见第 0 节第 2 条 | App 里：我的 → 设置 → 注销账号并删除数据（英文界面是 Me → Settings → Delete account and data） |
| 能否只删部分数据、不删账号 | 否 | 照片可以换掉，但大部分数据只随账号一起删 |
| 是否做过独立的安全审核 | 否 | |

**哪些不算“分享”**：Supabase（数据库、登录、存储）、Resend 等发信服务、Firebase（推送）、Cloudflare（人机验证）都是替我们处理数据的服务商，按 Play 的定义不算分享。别的球友看到你的昵称、照片、等级，是你自己在 App 里发布的、App 本身的功能，也不算分享。所以下面每一项的“分享”都填**否**。

**收集的数据**（都选：不分享、用途见表；“临时处理”只有位置选是）

| Play 的类别 → 类型 | 必需 / 可选 | 用途 | 实际是什么 |
|---|---|---|---|
| 位置 → 大致位置 | 可选 | App 功能 | 找附近的球馆和球友时，坐标随那次查询发到服务器，不保存。**临时处理：是** |
| 位置 → 精确位置 | 可选 | App 功能 | 同上。App 申请了精确定位（`ACCESS_FINE_LOCATION`），用户给了就会发精确坐标，所以也要勾。**临时处理：是** |
| 个人信息 → 电子邮件地址 | 必需 | App 功能、账号管理 | 登录邮箱；约球邮件、验证码 |
| 个人信息 → 姓名 | 可选 | App 功能 | 申请高水平认证时填的比赛里的名字（以后有 Google / Apple 登录，还有它们给的名字） |
| 个人信息 → 用户 ID | 必需 | App 功能、账号管理 | 账号 ID、“昵称#编号” |
| 个人信息 → 其他信息 | 必需 | App 功能 | 性别（男女等级分开算）、国家或地区、App 语言 |
| 照片和视频 → 照片 | 可选 | App 功能 | 头像、卡片背景照片 |
| 消息 → 其他应用内消息 | 可选 | App 功能 | 私信、球局群聊、球群群聊；帮助与反馈里写的话 |
| 应用活动 → 其他用户生成的内容 | 必需 | App 功能 | 昵称、定级问卷的答案、评价、添加的球馆、球群名和说明、举报内容 |
| 应用活动 → 其他操作 | 必需 | App 功能 | 约球请求、球局、签到、赛果、AA 标记、球友、挑战、屏蔽、空闲时间、常去球馆 |
| 应用信息和性能 → 诊断信息 | 可选 | App 功能 | 只在发反馈时附带 App 版本、系统版本、机型、语言（发之前用户看得到） |
| 设备或其他 ID → 设备或其他 ID | 可选 | App 功能 | 允许通知后的推送令牌（FCM 令牌，Firebase 会用到它的安装 ID） |

**不勾的**：财务信息（没有内购；Ko-fi 的付款在 Ko-fi 网站上，我们收不到）、健康和健身、联系人、日历（只是打开系统的“新建日程”页，不读日历）、音频、文件、网页浏览记录、已安装的应用、搜索记录（搜人时只记次数用来限速，不存搜的字）、广告 ID（合并后的清单里没有 `AD_ID` 权限）、崩溃日志（没有崩溃上报）。

**Play 页面上会显示的几句**：数据传输时加密；可以申请删除数据。没有分享给第三方。

## 3. 内容分级（IARC 问卷）

- 邮箱填支持邮箱（第 7 节）。类别建议选“社交网络、论坛、博客和用户生成内容分享”这一类（有私信、群聊、头像照片、资料）。拿不准就选“其他应用类型”，后面关于互动的问题照样会问，答案一样。
- 暴力、血腥、性内容、裸露、粗口、毒品 / 酒精 / 烟草、赌博、恐怖：**都答否**（App 自己的内容里没有；用户写的不当词服务器会过滤）。
- 用户之间能不能互动、交换内容（聊天、发照片）：**是**。
- 有没有用户生成的内容：**是**。有没有审核：**是**——服务器过滤不当词，可以举报和屏蔽，管理员 24 小时内处理举报（和 iPhone 提交时写的一致）。
- 是否把用户的位置分享给其他用户：**否**（别人看不到你的位置；看得到的是你选的球馆和常去球馆）。如果问卷里的说法包括“球馆、场地”，再按原文斟酌。
- 是否能买数字商品 / 内购：**否**。
- 是否能不受限制地上网（内置浏览器）：**否**（外部链接用系统浏览器打开）。
- 结果大概是低年龄分级加“用户互动”的标注，以问卷算出来的为准。分级和下一节的“目标受众”是两回事。

## 4. 目标受众和内容

- 网站用户协议：**至少 13 岁，18 岁以下要监护人同意**；隐私政策写了不面向 13 岁以下。iPhone 的年龄分级也定在 13+。
- 目标年龄组：勾 **13–15、16–17、18 岁以上**，不勾 12 岁及以下（勾了就要守“家庭”政策）。
- “应用是否会无意中吸引儿童”：**否**（运动约球、陌生人约见面，画风也不是儿童向）。
- 如果想省事、少被追问未成年人的事，也可以只勾 18 岁以上，但会和协议的 13 岁对不上。建议按协议勾。
- Console 里如果出现年龄验证（Age Signals）一类的新问题，照实填，拿不准先停下来问。

## 5. 广告、政府、金融、健康等声明

| 项目 | 答 |
|---|---|
| 广告 | 否（没有广告 SDK） |
| 广告 ID | 否（不用广告 ID） |
| 政府应用 | 否 |
| 金融功能 | 不提供任何金融功能（教练球群的“收费备注”只是文字，钱当面给；Ko-fi 第一版建议不显示） |
| 健康应用 | 否 / 没有健康功能 |
| 新闻应用 | 否 |
| 照片和视频权限 | 不用申报：用的是系统照片选择器，没有申请读相册的权限 |
| 后台位置 | 不用申报：只在用 App 时取位置 |

## 6. 应用访问权限（给审核员的账号）

审核员要能登录，不然会被拒。

1. 建一个**专门给 Play 审核用的账号**，不和 iPhone 的审核账号混用（iPhone 那个不能注销，Play 审核员可能会试注销）。邮箱用你自己域名下的一个转发地址（Cloudflare Email Routing 加一个），密码用密码管理器随机生成。**不要把账号密码发到聊天里，也不要写进仓库。**
2. 用它在 badie.rsvp 注册，填昵称、做定级、选常去球馆；和你的主账号互加球友、聊一句、约成并打完一场，让审核员看得到真实内容。
3. Console → 应用内容 → 应用访问权限 → “部分或全部功能受限” → 添加说明：名称 `Reviewer account`，填邮箱和密码，在“其他信息”框里贴下面这段（英文）：

```
Badie helps badminton players find partners at their level and courts nearby. It is free and has no ads.

Sign in: continue from the welcome screen to the email step. If it says "Sign up for Badie", tap "Have an account? Sign in". Then enter the email and password above.
The account already has a level, home courts, a friend and a finished game, so you can see real content.

Quick Match (the + button in the middle of the tab bar > Quick Match) needs a second real player, so a new request may stay in "searching" during review. The past game, chat, leaderboard and player profiles show what a confirmed game looks like.

User-generated content: offensive words are filtered on the server. To report or block, open any player profile and tap Report or Block. Reports are reviewed within 24 hours.

Account deletion: Me tab > Settings > Delete account and data. Please don't delete this review account. If you want to test deletion, create a new account with any email address (sign-up sends a 6-digit code).

Location is only used to show courts and players nearby and is not stored.
```

- 登录时有一道隐藏的人机验证（Cloudflare），一般不用点。第一次在真机上登录前先自己走一遍，确认上面写的按钮名和步骤和安卓一致。
- Supabase 免费项目 7 天没活动会暂停，已有每天的保活任务，审核期间不用管。

## 7. 其他 Console 栏目

| 栏目 | 填什么 |
|---|---|
| 应用 / 游戏 | 应用 |
| 免费 / 付费 | 免费（选了免费以后不能改成付费） |
| 类别 | 体育（Sports） |
| 标签 | 在 Console 给的列表里选，最多 5 个，选和羽毛球、运动、找人一起玩相关的。列表里有哪些以 Console 为准 |
| 联系邮箱 | 网站上公开的支持邮箱：support@badie.rsvp |
| 网站 | https://badie.rsvp |
| 电话 | 不填（选填） |
| 隐私政策 | https://badie.rsvp/privacy/ （先按第 0 节补好安卓） |
| 国家和地区 | 全部能选的（Play 本来就不在中国大陆） |
| 应用签名 | 用 Play 应用签名；上传密钥你自己生成、自己保管，不进仓库 |

## 8. 图片素材

| 素材 | 要求 | 用什么 |
|---|---|---|
| 应用图标 | 512 × 512，32 位 PNG（带透明通道），不超过 1 MB；Play 会自己裁圆角，不要自己加圆角和阴影 | 用 iPhone 那张 1024 的图标缩到 512 |
| 置顶大图（Feature graphic） | 1024 × 500，JPEG 或 24 位 PNG（不带透明通道） | 柠檬色底，logo 加一句定位（“i 人也能约到球” / “Find a game without asking”），字少、居中，不放价格和“免费” |
| 手机截图 | 2–8 张，JPEG 或 24 位 PNG；长边不超过短边的 2 倍，边长 320–3840。想进 Play 的推荐位，至少 4 张、竖屏 9:16、不小于 1080 × 1920 | 1080 × 1920，每种语言 8 张 |

截图照 iPhone 那套海报式的 9 张来，标题直接用 `Badie-iOS/scripts/store_captions.json` 里的，去掉一张：

1. 发现页（定位句：“i 人也能约到球”）
2. 快速匹配：选时间和球馆（“选时间，选球馆”）
3. 匹配到的对手（“实力相近的对手”）
4. 按天看人的卡片（“明天谁有空”）
5. 定级结果（“2 分钟测出几级”）
6. 别人资料上的爽约次数（“爽约次数看得到”）
7. 公开球局 / 房间（“订了场，差一人”）
8. 球群（“每周固定局”）

- **不放第 9 张“免费，没有广告”**：Play 的商店页规范把“表示价格和促销信息的图片或文字”列为常见违规，免费只在完整说明的结尾说。
- **画面要是安卓的界面**，不能用 iPhone 的截图或 iPhone 的外框（Play 要求截图反映 App 实际的样子）。第 1 张如果要放整部手机，用不带品牌的通用手机外框。
- 安卓现在还没有演示模式（`STATUS.md`“接下来的顺序”第 4 步），截图要等它做好，或者用 Roborazzi 的截图测试配上演示数据来出图。
- 平板截图不用传（App 只做了竖屏手机）。

## 9. 封闭测试（个人开发者账号必须先做）

Play 的规定（2026-11-16 查过帮助中心原文）：2023-11-13 之后注册的个人账号，申请正式发布时，封闭测试里要**至少有 12 个测试者已加入，并且在之前 14 天里一直没退出**。中途退出的不算；退出后再加入，要重新连续算 14 天。

步骤：

1. **先把第 0、2–8 节填完**：商店页、隐私政策、应用访问权限、广告、内容分级、目标受众、数据安全这些不填完，测试版发不出去。
2. Console → 测试 → **封闭测试** → 用默认的那条测试轨道（Closed testing - Alpha）或新建一条 → 选国家和地区（选测试者所在的地方）。
3. **测试者**：建一个 Google 群组（groups.google.com，测试者用自己的 Google 账号加入）或在 Console 里建邮件列表（填测试者 Google Play 用的 Gmail 地址）。群组好处是你不用一个个收邮箱，人自己进。建议多找几个人（15–20 个），有人中途退出也够 12 个。
4. **创建版本**：上传签好名的 AAB，填版本说明（可以先用第 1 节的），提交审核。第一次审核可能要几天。
5. 审核过了以后，测试页面上有**加入测试的链接**（网页链接和安卓上的链接），发给测试者。
6. **测试者要做的**：用加了群组 / 在名单里的那个 Google 账号打开链接 → 点“成为测试者” → 从 Play 安装 Badie → **14 天内不要退出测试、不要卸载**，隔几天打开用一用（注册、约一次球、发条消息），有问题在 App 的“帮助与反馈”里写。
7. 你在 Console 的封闭测试页看人数；满 12 人、连续 14 天后，到**信息中心 → 申请正式版**。要回答三组问题：封闭测试的情况（招人难不难、测试者用了哪些功能、收到什么反馈）、App 的情况（给谁用、有什么价值、第一年大概多少安装）、上线准备（根据测试改了什么、怎么判断可以上线）。把每次根据反馈改的东西随手记下来，到时候好填。
8. Google 说一般 7 天内回复。如果说测试参与度不够，会让你继续测一段再申请。

要在 Console 里再确认的：

- 你自己的账号算不算 12 个人之一（帮助中心没写，建议不算，按 12 个别人找）。
- 测试者需不需要真的打开过 App（规定只写“加入并且没退出”，但有开发者说参与度低会被拒，所以让大家真的用一用）。

## 10. 要你定的

1. **Ko-fi**：安卓第一版先不显示“支持 Badie”（建议），还是对完政策再定。
2. **删除账号的网页**：加一个 `/delete-account/` 小页（建议），还是先填 `https://badie.rsvp/contact/`。
3. **中文名称**：Play 上写“轻羽 Badie：找羽毛球搭子 / 輕羽 Badie：找羽毛球球友”；安卓桌面名要不要也按语言显示“轻羽 / 輕羽”（和 iPhone 一样），要改代码。
4. **目标年龄**：按协议勾 13 岁以上（建议），还是只勾 18 岁以上。
5. **Google / Apple 登录**：上架前做完（建议），还是第一版只有邮箱。
