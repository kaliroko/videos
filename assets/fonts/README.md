# assets/fonts

Her Haven 的衬线字体：**Noto Serif SC（思源宋体，SIL OFL 1.1）**，
对应网页原型的 font-family: "Noto Serif SC", "Songti SC", serif。

字体直接打进 APK，运行时不会下载任何字体，也没有用 google_fonts 之类的联网包。

## 当前仓库里已有的文件

| 文件 | 说明 |
|---|---|
| `NotoSerifSC-Light.ttf` | 官方可变字体按源码用字裁出来的子集，约 577 KB，已声明在 pubspec.yaml |
| `OFL-NotoSerifSC.txt` | 许可全文 |

`pubspec.yaml` 只声明了 Light 一档 —— 少一个文件，就少一处「构建时找不到资源」的风险。
如果你想要网页里 400 字重的标题，可以再放一个 `NotoSerifSC-Regular.ttf`，
然后在 pubspec 的 fonts 里补一条 weight: 400。

## 想换成你自己下载的字体？

直接**覆盖同名文件** `assets/fonts/NotoSerifSC-Light.ttf` 即可，代码不用改。

下载地址：

1. Google Fonts 官方页面
   <https://fonts.google.com/noto/specimen/Noto+Serif+SC>
2. 直接下载家族 zip（解压后取 static/NotoSerifSC-Light.ttf）
   <https://fonts.google.com/download?family=Noto%20Serif%20SC>
3. 可变字体直链（完整 25 MB）
   <https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf>
   国内镜像：<https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf>
   （jsDelivr 单文件有 20 MB 上限，会被拒；用 raw.githubusercontent 那条）
4. 思源宋体官方发布
   <https://github.com/notofonts/noto-cjk/releases>
5. 许可全文
   <https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/OFL.txt>

## 自己重新裁剪（可选）

```bash
pip install fonttools
python3 tool/fetch_serif_font.py
```

脚本会下载官方可变字体、按 lib/**/*.dart 里出现过的字符裁剪，
输出 Light（和可选的 Regular）并校验字形覆盖。

## 为什么正文不用衬线体

用户输入的文字（昵称、私密日记正文、聊天内容）一律走系统无衬线体；
衬线子集只含界面固定文案里的字，拿去渲染用户输入会缺字回退，
一行字里混两种字体反而更难看。

## 旧版字体

MaShanZheng-Regular.ttf、ZCOOLKuaiLe-Regular.ttf 是上一版「米色纸 + 毛笔字」用的，
已经不在 pubspec 的 fonts 里，不会进 APK，可连同 tool/subset_fonts.py 一起删掉。
