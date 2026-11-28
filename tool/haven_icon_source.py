#!/usr/bin/env python3
"""把竖版人像裁成正方形图标源图（供 generate_icons.py 使用）。

为什么要在前面加这一步
----------------------
generate_icons.py 的策略是「整图缩放后居中放在底上」。换成新的竖版人像
（408x502）之后，整图塞进方框会在左右留白，小尺寸下人物只有指甲盖大。
这里先做一个**顶对齐的方形裁切**，让人物面部占满画布，再交给下游脚本
去烘圆角和出各密度。

用法
----
    python3 tool/haven_icon_source.py      # 产出 tool/icon_source.png
    python3 tool/generate_icons.py         # 产出 android 各密度图标
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / '软件新图片图标.png'
TARGET = Path(__file__).resolve().parent / 'icon_source.png'
SIZE = 1024

# 底部压暗的强度：图标下沿稍微沉一点，上方脸更亮，小尺寸下也不会糊成一片
BOTTOM_DIM = 0.42
# 玫瑰色暗角：和 App 整体「暗玻璃 + 玫瑰」的语气对齐
VIGNETTE = 0.34


def main() -> int:
    if not SOURCE.exists():
        raise SystemExit(f'找不到源图：{SOURCE}')

    src = Image.open(SOURCE).convert('RGB')
    w, h = src.size

    # 顶对齐方形裁切：宽度就是边长，从顶边往下取
    side = min(w, h)
    left = (w - side) // 2
    box = (left, 0, left + side, side)
    crop = src.crop(box).resize((SIZE, SIZE), Image.LANCZOS)

    # 渐变层：上方透明、下方压暗
    shade = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    px = shade.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        alpha = int(255 * BOTTOM_DIM * (t ** 1.7))
        for x in range(SIZE):
            px[x, y] = (13, 10, 16, alpha)
    crop = Image.alpha_composite(crop.convert('RGBA'), shade)

    # 玫瑰暗角：径向遮罩，四周泛一点玫瑰
    glow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse(
        (-SIZE * 0.35, -SIZE * 0.45, SIZE * 1.35, SIZE * 1.35),
        fill=(209, 121, 151, 0),
    )
    # 用逐像素计算代替蒙版：边缘更柔和
    gpx = glow.load()
    cx, cy = SIZE / 2, SIZE / 2
    max_d = (2 ** 0.5) * SIZE / 2
    for y in range(SIZE):
        for x in range(SIZE):
            d = (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / max_d
            a = int(255 * VIGNETTE * max(0.0, d - 0.28) / 0.72)
            gpx[x, y] = (209, 121, 151, a)
    # 只是一层很淡的玫瑰，别把画压死
    crop = Image.alpha_composite(crop, glow)

    crop.convert('RGB').save(TARGET, 'PNG', optimize=True)
    print(f'✅ 图标源图已写出：{TARGET.relative_to(ROOT)}  {crop.size[0]}×{crop.size[1]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
