# Her Haven · 私密乌托邦

一款面向女性的私密空间 App：**私语日记 + 自慰时刻 + 影像 + 同频 + 健康科普 + 呼吸**。
视觉 1:1 移植自前端原型 `index.html`：同一张背景图、同一套暗玻璃玫瑰配色、
同一款思源宋体、同一组动效语言；原有「碎碎念」动态墙、视频流、聊天室全部并入新模块。

## 这个 App 长什么样

- **底**：网页原图 `1.png`（原样打包，未重新编码）+ `brightness(0.65)` + 底部渐变遮罩。
  也就是网页的 `#globalAnimeBg + #bgOverlay`，在 Flutter 里用
  `ColorFiltered + DecoratedBox(gradient)` 逐行对应。
- **玻璃**：`rgba(22,17,26,.6) + blur(20px) + 12px 圆角 + 1px rgba(255,255,255,.08)`
  → `GlassCard`（ClipRRect → BackdropFilter → 半透明容器）。
- **玫瑰 / 薰衣草**：`#D17997` / `#8E7BB5`，深浅两套 token 都在
  `lib/theme/haven.dart`，旧界面通过 `DiaryPalette` 全部转发过去。
- **字体**：Noto Serif SC 300/400（打包进 APK 的子集）+ 系统无衬线。
- **动效**：网页的 fadeUp / 弹幕 / 呼吸缩放 / toast 全部保留，
  并在原 App 的弹簧物理语言里重新实现（没有一条补间曲线）。

## 模块

| 标签 | 内容 | 数据 |
|---|---|---|
| **首页** | hero 主视觉（可换一张的动漫图）、**聊天室卡片（在计时器上方）**、计时器、同频入口、四宫格、SAPPHIC WISDOM | — |
| **私语** | 网页「私语日记」表单（日期 / 情绪 / 身体反应 / 注意力 / 想说的话，收进一张弹簧抽屉）**+ 碎碎念动态墙**，合并成一条时间线 | 私密条目仅本机；碎碎念走原仓库逻辑（本机或 Supabase） |
| **自慰时刻** | 页面上只留三格统计 + 「记录一次」按钮 + 写过的记录；完整表单（计时 / 时长 / 状态 / 详细记录 / 三段文字 / 疼痛提醒）收进弹簧抽屉 | 仅本机 |
| **影像** | 原有上下滑动视频流（多播放器预加载、进度记忆）；进入即**沉浸式全屏**，左上角浮出退出按钮 | 原逻辑不变 |
| **同频** | 网页的 MATCH 仪式、双人头像、共频计时 + **连接后的「双人共振」**（共享计时 / 合拍度 / 节奏 / 她的回应 / 事后余韵 / 随时可以停） | 同频与共振都是本地演示；聊天室已移到首页卡片 |
| **健康科普** | 六条折叠科普 | — |
| **呼吸放松** | 4-4-6 呼吸圆，吸气放大 / 屏息 / 呼气回缩 | — |

> 网页里的「隐私中心 / 启动锁屏」按需求去掉了：不做锁屏、不做通知模糊/截图遮罩；欢迎页也不再拦 18+ 确认。
> 「共振」只写到暗示与节奏，不描写具体动作；开始前有双方自愿提示，任何时候都可以停。
> 私密数据仍然只写本机，页面上也照旧标着「仅本机」。

## 和原 App 的关系

- 原来的三个模块原样保留：**碎碎念动态**（发帖 / 图 / 匿名 / 评论 / 表情 / 删除）、
  **视频流**、**聊天室**（Realtime / 图片 / 文件 / 表情 / 回复 / 撤回）。
- 原来的底部液态玻璃栏换成网页的顶部标签栏，导航语言与原型一致。
- 原来的毛笔手写体、朱砂色、米色纸全部退役；`DiaryPalette` 保留为转发层，
  197 个旧调用点一行没改就整体换肤。
- 停服页 / 公告 / 更新弹窗 / 引导页 / 欢迎页都跟着 Haven 主题走。

## 目录

```
lib/
  theme/
    haven.dart          # 设计令牌唯一真值（颜色 / 字体 / 字号 / 圆角 / 渐变）
    app_theme.dart      # Haven → Material 3 主题（深色为准）
    diary_palette.dart  # 旧配色门面，全部转发到 HavenColors
    springs.dart        # 全 App 弹簧参数
  widgets/
    haven_widgets.dart  # 网页组件的 1:1 译本（按钮/chip/表单/toast/弹幕/背景/动漫图）
    glass_card.dart     # 玻璃卡
  screens/haven/
    haven_shell.dart    # 顶部品牌 + 标签栏 + 七模块
    haven_home.dart     # 首页
    haven_diary.dart    # 私语（私密日记 + 碎碎念，融合时间线）
    haven_moment.dart   # 身体时刻
    haven_sync.dart     # 同频空间
    haven_learn.dart    # 健康科普
    haven_breathe.dart  # 呼吸放松
  repository/haven_store.dart  # 私密日记 / 身体时刻的本机存储
  models/haven_models.dart
assets/
  images/haven_bg.png   # 网页 1.png 原图
  images/moe_fallback.jpg
  fonts/                # 思源宋体子集（见 assets/fonts/README.md）
```

## 字体（已内置）

`assets/fonts/NotoSerifSC-Light.ttf` 已经放进仓库，是按源码用字裁剪过的
官方思源宋体子集（约 577 KB），直接 `flutter pub get` 就能构建。

想换成自己下载的版本：**覆盖同名文件**即可，不用改代码。
下载地址：

- <https://fonts.google.com/noto/specimen/Noto+Serif+SC>
- <https://fonts.google.com/download?family=Noto%20Serif%20SC>（zip 里的 static/NotoSerifSC-Light.ttf）
- 可变字体直链：<https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf>

重新裁剪：`python3 tool/fetch_serif_font.py`。详见 [`assets/fonts/README.md`](assets/fonts/README.md)。

## 本地运行

```bash
flutter pub get
flutter run
```

## 图标

新图标源图是 `再次新的软件图标.jpg`，处理链：

```bash
python3 tool/haven_icon_source.py   # 竖图 → 1024 方形源图（顶对齐裁切 + 玫瑰暗角）
python3 tool/generate_icons.py      # 出 Android 各密度 PNG（圆角烘焙在 PNG 里）
```

启动闪屏背景色与网页底色一致（`#0D0A10`）。

## 数据存在哪

- **私密日记 / 身体时刻**：`SharedPreferences` 里的 JSON，各留最近 200 条，只在本机。
  （不是 SQLCipher 加密；页面文案也不声称加密。）
- **碎碎念**：`lib/repository/diary_repository.dart` 两条路 —— 本机 SharedPreferences
  或 Supabase（`supabase_diary.sql`），启动时探测，探测失败静默退回本机。
- **聊天室**：Supabase Realtime + Storage，原逻辑不变。

## CI/CD

GitHub Actions 在推送 `main`/`master` 时构建 APK 并发布 Release：

- `.github/workflows/build.yml` —— arm64
- `.github/workflows/arm.yml` —— arm32

流程：`flutter analyze` →（有 `test/` 才跑测试）→ `flutter build apk --release --obfuscate`
→ `apksigner verify` → 上传产物 → 建 Release。

> ⚠️ CI 也需要字体文件在仓库里；如果暂时不想提交字体，请先在
> `pubspec.yaml` 里去掉 `fonts:` 段落，或改用可变字体单文件方案。

## 字体与授权

- Noto Serif SC —— SIL Open Font License 1.1，版权与许可见 `assets/fonts/OFL-NotoSerifSC.txt`
- 背景图 `1.png`、动漫图分别来自原型与远端随机图接口 `t.alcy.cc`，
  正式发布前请替换为你有权使用的素材。
