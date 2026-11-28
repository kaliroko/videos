#!/usr/bin/env python3
"""把新图标图裁成正方形图标源图（供 generate_icons.py 使用）。

新图 再次新的软件图标.jpg 本身就是 640×640 的方形暗紫人像，
所以这里只做缩放 + 一点点底部压暗，让它在小尺寸下更有层次。

用法
----
    python3 tool/haven_icon_source.py      # 产出 tool/icon_source.png
    python3 tool/generate_icons.py         # 产出 android 各密度图标
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / '再次新的软件图标.jpg'
TARGET = Path(__file__).resolve().parent / 'icon_source.png'
SIZE = 1024

# 底部压暗：图标下沿稍微沉一点，小尺寸下五官更清楚
BOTTOM_DIM = 0.28


def main() -> int:
    if not SOURCE.exists():
        raise SystemExit(f'找不到源图：{SOURCE}')

    src = Image.open(SOURCE).convert('RGB')
    w, h = src.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    crop = src.crop((left, top, left + side, top + side)).resize(
        (SIZE, SIZE), Image.LANCZOS
    )

    shade = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    px = shade.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        alpha = int(255 * BOTTOM_DIM * (t ** 2.2))
        for x in range(SIZE):
            px[x, y] = (13, 10, 16, alpha)
    crop = Image.alpha_composite(crop.convert('RGBA'), shade)

    crop.convert('RGB').save(TARGET, 'PNG', optimize=True)
    print(f'OK 图标源图：{TARGET.relative_to(ROOT)}  {crop.size[0]}x{crop.size[1]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
