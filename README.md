# 玻璃哔哩 (BiliGlass)

B站风格液态玻璃视频播放应用，基于 [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) 实现。

## 技术栈

- **Flutter** 3.16+ / Dart 3.2+
- **Kotlin** 2.1.20 / AGP 8.6.1 / Gradle 8.10 / Java 17
- 液态玻璃 UI 库（本地路径引用 `../liquid_glass_widgets`）
- Provider 状态管理
- CachedNetworkImage + Chewie 播放器

## 本地运行

```bash
flutter pub get
flutter run
```

## CI/CD

GitHub Actions 在推送 `main`/`master` 时自动构建 APK 并发布 Release。

构建配置：
- Flutter 3.38.9 / Java 17 (Temurin)
- R8 代码压缩 + 资源收缩（不启用代码混淆，避免 Play Core 依赖问题）
- APK target: android-arm64

## API 接入

当前使用模拟数据。在 `lib/providers/video_provider.dart` 的 `fetchVideos()` 方法中替换为真实 API：

```dart
final response = await http.get(Uri.parse('YOUR_API_URL'));
final data = jsonDecode(response.body) as List;
_videos = data.map((e) => VideoItem.fromJson(e)).toList();
```

## 项目结构

```
lib/
├── main.dart                 # 入口
├── screens/
│   └── home_screen.dart      # 首页（B站布局）
├── providers/
│   └── video_provider.dart   # 视频数据 Provider
├── models/
│   └── video_model.dart      # VideoItem 模型
├── widgets/
│   └── video_card.dart       # 视频卡片组件
├── utils/
│   └── format_utils.dart     # 格式化工具
└── theme/
    └── app_theme.dart        # 主题配置
```
# videos
# videos
