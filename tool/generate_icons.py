#!/usr/bin/env python3
"""从 tool/icon_source.png 生成 Android 各密度的应用图标。

要解决的问题
------------
源图是**竖版**（593×800），而应用图标必须是**正方形**。直接把竖图塞进方框
只有两条路：裁掉上下（丢内容）或者左右留白条（难看）。

这里走第三条：**把图完整缩放后居中放在白底上**。
这张源图自己的底色就是白的，所以留出来的边和白底天然融为一体，看不出是补的，
而且一点都不裁。

（试过「把边缘像素横向拉伸填满」，但这张图的画框本身贴着左右边缘，
 一拉伸就把深色边框拉成两条竖带，反而难看，所以改成白底居中。）

各系统怎么用
------------
* Android 8+ 走自适应图标（`mipmap-anydpi-v26/ic_launcher.xml`）：
  `ic_launcher_background` 是整张满铺的方图，圆角由**启动器遮罩**切出来；
  `ic_launcher_foreground` 留全透明（图形已经画在背景层里了）。
* Android 7 及以下没有遮罩，用的是 `ic_launcher.png`，
  所以圆角是**直接烘焙进 PNG** 的 —— 这样老系统上也是圆角图标。

用法
----
    pip install pillow
    python3 tool/generate_icons.py

换图
----
把自己的图覆盖成 `tool/icon_source.png`，重跑这个脚本即可。
不用管长宽比，竖图横图方图都行。
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print('缺少依赖，请先执行：pip install pillow', file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
SOURCE = Path(__file__).resolve().parent / 'icon_source.png'

# 启动器图标（老系统用，圆角烘焙在 PNG 里）
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

# 自适应图标的 108dp 画布
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

# 圆角半径占边长的比例。Android 老图标的常见做法在 20%~25% 之间
CORNER_RATIO = 0.22

# 超采样倍数：先画大图再缩，圆角边缘才不会有锯齿
SS = 4

# 自适应图标前景占画布的比例。
# 规范上 108dp 画布里中央 72dp 是「保证可见」，但图形只占 72/108 会显得偏小；
# 这张图四周本来就有留白，所以放到 0.90 —— 图形主体仍落在安全区内，
# 万一被裁也只裁到留白。
SAFE_ZONE = 0.90


def compose_square(src: Image.Image, size: int, inner_ratio: float = 1.0,
                   bg=(255, 255, 255)) -> Image.Image:
    """把任意长宽比的图居中放进正方形白底。

    inner_ratio 控制图最多占画布的多大比例（1.0 = 顶满）。自适应图标要留
    安全区，所以传 72/108。
    """
    w, h = src.size
    box = size * inner_ratio
    scale = box / max(w, h)
    new_w, new_h = max(1, round(w * scale)), max(1, round(h * scale))
    fitted = src.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new('RGB', (size, size), bg)
    canvas.paste(fitted, ((size - new_w) // 2, (size - new_h) // 2))
    return canvas


def rounded(img: Image.Image, radius_ratio: float) -> Image.Image:
    """加上圆角，四角之外透明。超采样后缩回来，边缘才平滑。"""
    w, h = img.size
    big = img.resize((w * SS, h * SS), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (w * SS, h * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, w * SS - 1, h * SS - 1),
        radius=int(w * SS * radius_ratio),
        fill=255,
    )
    big.putalpha(mask)
    return big.resize((w, h), Image.LANCZOS)


def save(img: Image.Image, density: str, name: str) -> Path:
    d = RES / f'mipmap-{density}'
    d.mkdir(parents=True, exist_ok=True)
    path = d / name
    img.save(path, 'PNG', optimize=True)
    return path


def main() -> int:
    if not SOURCE.exists():
        print(f'找不到源图：{SOURCE}', file=sys.stderr)
        return 1

    src = Image.open(SOURCE).convert('RGB')
    print(f'源图 {src.size[0]}×{src.size[1]}  ({SOURCE.name})')

    # 自适应图标按最大密度做一张，再逐级缩，避免每次都从源图重采样
    biggest = max(ADAPTIVE.values())
    master = compose_square(src, biggest)                      # 顶满，给老图标用
    safe_master = compose_square(src, biggest, SAFE_ZONE)     # 缩进安全区，给自适应前景用

    print('\n生成启动器图标（圆角已烘焙进 PNG）:')
    for density, size in LEGACY.items():
        icon = rounded(master.resize((size, size), Image.LANCZOS), CORNER_RATIO)
        p = save(icon, density, 'ic_launcher.png')
        print(f'  {density:8s} {size:>3}px  圆角 {CORNER_RATIO:.0%}  {p.stat().st_size/1024:6.1f} KB')

    print('\n生成自适应图标背景（纯白，圆角由启动器遮罩切）:')
    for density, size in ADAPTIVE.items():
        bg = Image.new('RGB', (size, size), (255, 255, 255))
        p = save(bg, density, 'ic_launcher_background.png')
        print(f'  {density:8s} {size:>3}px  {p.stat().st_size/1024:6.1f} KB')

    print(f'\n生成自适应图标前景（图缩进 {SAFE_ZONE:.0%} 安全区，四周透明）:')
    for density, size in ADAPTIVE.items():
        small = safe_master.resize((size, size), Image.LANCZOS).convert('RGBA')
        # 白底转透明：安全区之外露出的应是背景层
        px = small.load()
        edge = int(size * (1 - SAFE_ZONE) / 2)
        for y in range(size):
            for x in range(size):
                if x < edge or x >= size - edge or y < edge or y >= size - edge:
                    px[x, y] = (0, 0, 0, 0)
        p = save(small, density, 'ic_launcher_foreground.png')
        print(f'  {density:8s} {size:>3}px  {p.stat().st_size/1024:6.1f} KB')

    print('\n✅ 完成。清单：')
    for density in LEGACY:
        d = RES / f'mipmap-{density}'
        names = sorted(x.name for x in d.glob('ic_launcher*.png'))
        print(f'  mipmap-{density:8s} {names}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
