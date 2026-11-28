#!/usr/bin/env python3
"""下载 Noto Serif SC，并按源码里真正出现的字做子集裁剪。

为什么需要这一步
----------------
网页的标题字体是 "Noto Serif SC"（思源宋体），300 / 400 两个字重。
完整字体 20MB+，全量打进 APK 不现实；界面上的固定文案是有限的，
所以按 lib/**/*.dart 里出现过的字符裁一遍即可（一般 1MB 上下）。

★ 这是一次性的维护脚本，不是构建步骤。
★ 用户输入的文字（昵称、日记正文）不使用衬线体；
  即使某个字不在子集里，Flutter 也只会回退到系统字体，不会出现豆腐块。
★ 如果你已经手动下载了官方字体，也可以直接把
  NotoSerifSC-Light.ttf / NotoSerifSC-Regular.ttf 放进 assets/fonts/，
  不跑这个脚本。

用法
----
    python3 tool/fetch_serif_font.py
"""

from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = Path(__file__).resolve().parent / '.cache'
OUT = ROOT / 'assets' / 'fonts'

VAR_URL = ('https://raw.githubusercontent.com/google/fonts/main/ofl/'
           'notoserifsc/NotoSerifSC%5Bwght%5D.ttf')
OFL_URL = ('https://raw.githubusercontent.com/google/fonts/main/ofl/'
           'notoserifsc/OFL.txt')

# 出两档字重，和网页的 font-weight: 300 / 400 对齐
WEIGHTS = {300: 'NotoSerifSC-Light.ttf', 400: 'NotoSerifSC-Regular.ttf'}

# 固定补充：ASCII、数字、常用中英文标点 —— 日期、计时、英文眉题都要用。
# 反引号用 chr(96) 拼进去，免得和脚本自身的引号打架。
EXTRA = (
    ' !"#$%&' + "'" + '()*+,-./0123456789:;<=>?@'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_' + chr(96) +
    'abcdefghijklmnopqrstuvwxyz{|}~'
    '，。、；：？！“”‘’（）《》〈〉【】「」『』—…·～￥％＋－×÷＝'
    '✓←→↑↓❤♥'
)


def collect_chars() -> set[str]:
    chars: set[str] = set(EXTRA)
    for path in (ROOT / 'lib').rglob('*.dart'):
        text = path.read_text(encoding='utf-8', errors='ignore')
        chars.update(text)
    return {c for c in chars if ord(c) >= 0x20}


def download(url: str, target: Path) -> Path:
    if target.exists() and target.stat().st_size > 0:
        print(f'· 命中缓存 {target.name} ({target.stat().st_size/1024/1024:.1f} MB)')
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f'· 下载 {url}')
    with urllib.request.urlopen(url, timeout=180) as resp:
        data = resp.read()
    target.write_bytes(data)
    print(f'  完成 {target.stat().st_size/1024/1024:.1f} MB')
    return target


def main() -> int:
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont
    except ImportError:
        print('缺少依赖，请先执行：pip install fonttools', file=sys.stderr)
        return 2

    chars = collect_chars()
    codes = sorted({ord(c) for c in chars})
    print(f'· 源码中出现的字符 {len(chars)} 个（去重后 {len(codes)} 个码位）')

    src = download(VAR_URL, CACHE / 'NotoSerifSC[wght].ttf')
    OUT.mkdir(parents=True, exist_ok=True)

    for weight, filename in WEIGHTS.items():
        font = TTFont(src)
        try:
            instantiateVariableFont(font, {'wght': weight}, inplace=True)
        except Exception as exc:  # 已经是静态字体时直接跳过
            print(f'  ! 实例化 wght={weight} 失败（可能不是可变字体）：{exc}')

        options = subset.Options()
        options.layout_features = ['*']
        options.name_IDs = ['*']
        options.notdef_outline = True
        options.hinting = False
        options.desubroutinize = False

        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes=codes)
        subsetter.subset(font)

        target = OUT / filename
        font.save(target)
        print(f'OK {filename}  {target.stat().st_size/1024:.0f} KB  (wght {weight})')

        cmap = font.getBestCmap()
        missing = sorted({c for c in chars if ord(c) not in cmap and not c.isspace()})
        if missing:
            print(f'缺字 {len(missing)} 个：{"".join(missing[:40])}')
        else:
            print('   字形覆盖完整')

    ofl = OUT / 'OFL-NotoSerifSC.txt'
    if not ofl.exists():
        try:
            download(OFL_URL, ofl)
        except Exception as exc:
            print(f'OFL 许可下载失败：{exc}')
    print('\n完成。重新 flutter pub get / 构建后字体才会进 APK。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
