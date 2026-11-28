#!/usr/bin/env python3
"""把新图标图裁成正方形图标源图（供 generate_icons.py 使用）。

"新软件图标.png" 的图标本体是一个圆角方块，四周有一圈白边，
右下角还有 AI 生成水印。这里：

1. 自动扫描图标本体的边界（只取中间的行/列，避开右下角水印）；
2. 向内收 2px，避开边缘抗锯齿白线；
3. 取正方形、缩放到 1024；
4. 白边、四角和水印交给 generate_icons.py 的圆角遮罩去掉
   （遮罩半径 0.215，比图标圆角略大，正好切掉外圈）。

用法
----
    python3 tool/haven_icon_source.py      # 产出 tool/icon_source.png
    python3 tool/generate_icons.py         # 产出 android 各密度图标
"""

from __future__ import annotations

from pathlib import Path
from statistics import median

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / '新软件图标.png'
TARGET = Path(__file__).resolve().parent / 'icon_source.png'
SIZE = 1024

# 白边判定阈值：三个通道都 >= 这个值才算「白」
WHITE = 242
# 向内收，避开边缘抗锯齿
INSET = 2


def detect_box(src: Image.Image) -> tuple[int, int, int, int]:
    """只扫中间的行/列，避开右下角的水印。"""
    w, h = src.size
    px = src.load()

    def non_white(x: int, y: int) -> bool:
        r, g, b = px[x, y]
        return not (r >= WHITE and g >= WHITE and b >= WHITE)

    xs0: list[int] = []
    xs1: list[int] = []
    ys0: list[int] = []
    ys1: list[int] = []

    y_step = max(1, h // 40)
    for y in range(int(h * 0.32), int(h * 0.68), y_step):
        xs = [x for x in range(w) if non_white(x, y)]
        if xs:
            xs0.append(min(xs))
            xs1.append(max(xs))

    x_step = max(1, w // 40)
    for x in range(int(w * 0.32), int(w * 0.68), x_step):
        ys = [y for y in range(h) if non_white(x, y)]
        if ys:
            ys0.append(min(ys))
            ys1.append(max(ys))

    if not xs0 or not ys0:
        return (0, 0, w - 1, h - 1)
    return (
        int(median(xs0)),
        int(median(ys0)),
        int(median(xs1)),
        int(median(ys1)),
    )


def main() -> int:
    if not SOURCE.exists():
        raise SystemExit(f'找不到源图：{SOURCE}')

    src = Image.open(SOURCE).convert('RGB')
    x0, y0, x1, y1 = detect_box(src)

    left = x0 + INSET
    top = y0 + INSET
    right = x1 - INSET
    bottom = y1 - INSET

    side = min(right - left, bottom - top)
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    box = (
        cx - side // 2,
        cy - side // 2,
        cx - side // 2 + side,
        cy - side // 2 + side,
    )

    crop = src.crop(box).resize((SIZE, SIZE), Image.LANCZOS)
    crop.save(TARGET, 'PNG', optimize=True)
    print(f'OK 图标源图：{TARGET.relative_to(ROOT)}  {crop.size[0]}x{crop.size[1]}  '
          f'检测边界 {(x0, y0, x1, y1)}  裁剪区 {box}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
