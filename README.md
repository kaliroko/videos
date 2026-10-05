# 碎碎念

一款日记分享动态 App，带视频与聊天室。基于 Flutter + 液态玻璃 UI 构建。

主页面是一段会**自己写出来**的手写体标题，下面是一叠米色纸片般的动态卡片；
点右下角的「写」会弹出一张带弹簧物理的发布卡片。发动态**不需要注册**——
昵称可以随便填，也可以勾匿名。

## 功能

| 模块 | 说明 |
|---|---|
| **碎碎念**（首页） | 日记动态流。无需注册，昵称可自定义或匿名，**有主标题**，最多 9 张配图，心情标签，非匿名时可选**地区**，**4 个表情反应**（类似点赞），**可评论**，可删除自己发的 |
| **视频** | 上下滑动切换的竖屏视频流，多播放器预加载 + 进度记忆 |
| **聊天室** | 匿名公共聊天，MD3 界面 + 弹簧动画，支持图片、文件、表情、回复、撤回 |
| **运营控制** | 远程公告 / 远程停服，基于 Supabase Realtime + 60 秒轮询兜底 |

## 技术栈

- **Flutter** 3.38.9 / Dart 3.5+
- **Kotlin** 2.1.20 / AGP 8.9.1 / Gradle 8.11.1 / Java 17
- 液态玻璃 UI 库（本地路径引用 `vendor/liquid_glass_widgets`）
- **Provider** 状态管理
- **Supabase**（Realtime + Storage）作为云端后端
- CachedNetworkImage / Chewie / video_player

## 本地运行

```bash
flutter pub get
flutter run
```

## CI/CD

GitHub Actions 在推送 `main`/`master` 时自动构建 APK 并发布 Release。

- `.github/workflows/build.yml` —— arm64
- `.github/workflows/arm.yml` —— arm32

流程：`flutter analyze` →（有 `test/` 才跑测试）→ `flutter build apk --release --obfuscate` →
`apksigner verify` → 上传产物 → 建 Release。

> CI 只跑 `flutter pub get` 和 `flutter build apk`，**不依赖任何外网下载**（字体等资源都在仓库里）。

## 深色 / 浅色

跟系统走：`MaterialApp` 同时装了 `theme`（浅）和 `darkTheme`（深），
`themeMode: ThemeMode.system`，系统切换时 App 自动跟着变。

碎碎念和聊天室用的是自己那套「墨 · 朱 · 纸」调色板（`lib/theme/diary_palette.dart`），
它没有走标准的 `ThemeExtension`，而是「静态当前模式 + getter」：

- 成员名和调用点一个都不用改（这些颜色被 197 处引用，大量嵌在 `const` 构造里）
- `MaterialApp.builder` 里每帧调一次 `DiaryPalette.syncWith(brightness)` 同步模式
- 代价是它不是响应式的「每 Widget 取色」，全局同一时刻只有一个模式 —— 对本 App 够用

## 字体

界面用了两款开源中文字体，已随包打进 APK，运行时不会下载。详见 [`assets/fonts/README.md`](assets/fonts/README.md)。
其中毛笔手写体做了子集化裁剪（5.6 MB → 385 KB），维护脚本是 `tool/subset_fonts.py`。

## 日记模块的数据存在哪

`lib/repository/diary_repository.dart` 有两条路：

- **本机模式**：动态存在 `SharedPreferences`，图片复制进 App 私有目录。开箱即用，但只在这台手机上。
- **云端模式**：动态进 Supabase 的 `diary_posts` 表、评论进 `diary_comments` 表、
  表情反应进 `diary_reactions` 表，图片进 `diary_images` 桶，所有人可见。

App 启动时会探测一次云端，探测失败就安静退回本机模式，不影响使用。
要把云端打开，到 Supabase 后台执行一次 [`supabase_diary.sql`](supabase_diary.sql) 即可，不用改代码。

### 冷启动缓存

`lib/repository/diary_cache.dart` 会在每次拿到数据后把列表存一份到本地。
下次启动**先把缓存铺出来**，再联网刷新 —— 所以不会出现「打开 App 先空一片、
等几秒才出卡片」的情况。云端模式下这一步尤其重要，因为探测 Supabase 最长要 6 秒。

刷新失败时缓存会被保留，不会把用户已经看到的卡片清掉。

## 项目结构

```
lib/
├── main.dart                    # 入口：签名校验 → 缓存预读 → Supabase → runApp
├── permission_gate.dart         # 权限门禁（含「碎碎念」首页预览）
│
├── models/                      # diary_post / video_model / app_config
├── providers/                   # diary_provider / nav_bar_visibility
├── repository/                  # diary_repository（本机 + 云端）/ simple_api
├── theme/                       # app_theme（全局）/ diary_palette（墨·朱·纸）
│
├── screens/
│   ├── diary_screen.dart            # 碎碎念首页：手写体页头 + 卡片流
│   ├── diary_compose_sheet.dart     # 物理弹窗发布卡片
│   ├── diary_comments_sheet.dart    # 评论面板（同一套弹簧物理）
│   ├── swipe_video_screen.dart      # 上下滑动视频
│   ├── chat_screen.dart             # 聊天室（MD3 + 弹簧）
│   └── home_screen.dart             # 三个入口的骨架
│
├── widgets/
│   ├── handwriting_text.dart        # ★ 手写笔迹动画引擎
│   ├── spring_sheet.dart            # ★ 物理弹窗骨架
│   ├── diary_card.dart              # 纸片动态卡片
│   ├── ink_seal.dart                # 朱砂印章
│   └── remote_gate.dart             # 远程开关 UI
│
├── managers/                    # bootstrap / remote_config / analytics / app_update
└── security/                    # integrity_guard（原生签名校验桥接）

assets/fonts/                    # 两款开源中文字体 + OFL 授权
tool/subset_fonts.py             # 字体子集维护脚本（开发期用，不进 CI）
supabase_diary.sql               # 云端建表脚本
```
