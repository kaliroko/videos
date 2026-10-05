# assets/fonts

「碎碎念」日记模块用的两款字体。两款都是 SIL Open Font License 1.1，可随 App 一起分发。

**字体是直接打进 APK 的**：文件就在这个目录里，`pubspec.yaml` 用 `fonts:` 声明，
Flutter 构建时打包进去。**运行时不会下载任何字体**，也没有引入 `google_fonts` 之类的联网包。

| 文件 | 字体 | 体积 | 用途 |
|---|---|---|---|
| `MaShanZheng-Regular.ttf` | Ma Shan Zheng 马善政毛笔楷书 | ~385 KB | **仅装饰文字**：页头大字、循环书写的那句话、卡片日期、发布卡片标题、FAB 上的「写」、权限页的首页预览 |
| `ZCOOLKuaiLe-Regular.ttf` | ZCOOL KuaiLe 站酷快乐体 | ~1.5 MB | 昵称、印章、心情标签、按钮、提示文案 |

## 为什么一个裁剪、一个不裁剪

**毛笔体裁到只剩用得到的字。** 它渲染的文案全部写死在源码里（不会出现用户输入），
所以可以把 7015 字形裁到 630 个，**5.6 MB → 385 KB**。

**圆体保留完整字库。** 卡片上的昵称和印章首字是**用户自己输入的**，什么字都可能出现，
裁掉就会出现字形不一致（Flutter 会回退到系统字体，不会变豆腐块，但两种字体混排很丑），
所以这 1.5 MB 不能省。

## 加了新的手写体文案怎么办

`tool/subset_fonts.py` 是**开发期维护脚本，不是构建步骤**，平时完全不需要跑它。

只有当你在源码里新增了用 `DiaryPalette.brush` 渲染的中文时，才需要重跑一次：

```bash
pip install fonttools
python3 tool/subset_fonts.py
```

它会下载一次原始字体、按当前源码重新裁剪毛笔体、并逐个校验界面文案的字形覆盖
（有缺口就非 0 退出）。跑完把新的 `.ttf` 提交即可。

> ⚠️ **不要把它加进 CI**：那会让构建依赖外网下载。CI 只该跑 `flutter pub get` + `flutter build apk`。

> 不想维护子集也行：把上面那个 URL 的原始字体直接覆盖进来（约 5.6 MB）就永远不会缺字，
> 代价是 APK 大约多 5.2 MB。

## 已知的一处妥协

评论面板标题「评论」用的是**圆体**，不是毛笔体 —— 毛笔体子集里没有「评」「论」这两个字
（裁剪时扫描的源文件里没出现过）。硬用毛笔体会回退成系统字体，一行字看起来很花。

想统一成毛笔体：跑一次 `tool/subset_fonts.py` 重新裁剪（它现在会扫到
`lib/screens/diary_comments_sheet.dart`，把这两个字带进子集），
然后把该文件里 `SpringSheetHeader` 的 `titleStyle` 参数删掉 —— 默认就是毛笔体。

## 授权

- `OFL-MaShanZheng.txt` —— Ma Shan Zheng 的 SIL OFL 1.1 全文
- `OFL-ZCOOLKuaiLe.txt` —— ZCOOL KuaiLe 的 SIL OFL 1.1 全文

OFL 允许嵌入、打包、商用，要求保留版权声明与许可文本（即上面两个文件），
且不得单独售卖字体本身。
