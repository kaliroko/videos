#!/usr/bin/env python3
"""从 tool/icon_source.png 生成 Android 各密度的应用图标（正方形 + 四边圆角）。

要解决的问题
------------
1. 源图是**竖版**（593×800），而应用图标必须是**正方形**。直接把竖图塞进方框
   只有两条路：裁掉上下（丢内容）或者左右留白条（难看）。
   这里走第三条：**把图完整缩放后居中放在白底上**。这张源图自己的底色就是白的，
   所以留出来的边和白底天然融为一体，看不出是补的，而且一点都不裁。

   （试过「把边缘像素横向拉伸填满」，但这张图的画框本身贴着左右边缘，
    一拉伸就把深色边框拉成两条竖带，反而难看，所以改成白底居中。）

2. 形状要**正方形 + 四边圆角**。这一点决定了**不能用自适应图标**：
   自适应图标（`mipmap-anydpi-v26/ic_launcher.xml`）的形状由**启动器遮罩**
   决定，各家启动器不一样，很多会直接切成圆形 —— 我们控制不了，只能被切。
   所以这里改为**把圆角直接烘焙进 PNG**，让系统原样显示。

   代价：没有自适应图标时，部分启动器（如 Pixel）会给老式图标垫一层背景，
   图标看起来会比自适应图标略小一点。

   想要自适应图标的话，把下面的 GENERATE_ADAPTIVE_ICON 改成 True 再跑一次，
   脚本会把图层和 mipmap-anydpi-v26/ic_launcher.xml 一起写出来。

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

# ── 形状参数 ──────────────────────────────────────────────────────────
# 圆角半径占边长的比例。
# 0.22 太圆（接近 squircle），0.16 更像「正方形 + 四边圆角」。
CORNER_RATIO = 0.16

# ── 是否生成自适应图标 ────────────────────────────────────────────────
# ★ 默认 False：形状由启动器遮罩决定，控制不了，很多启动器会切成圆形。
#   想要正方形圆角，就只能关掉它、把圆角烘焙进 PNG。
GENERATE_ADAPTIVE_ICON = False

# 启动器图标（形状烘焙在 PNG 里）
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

# 自适应图标的 108dp 画布
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

# 自适应图标前景占画布的比例。规范上 108dp 里中央 72dp 保证可见，
# 但图只占 72/108 会显得偏小；源图四周本来就有留白，所以放到 0.90。
SAFE_ZONE = 0.90

# 超采样倍数：先画大图再缩，圆角边缘才不会有锯齿
SS = 4

ADAPTIVE_XML = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!-- 由 tool/generate_icons.py 生成。形状由启动器遮罩决定，不受我们控制。 -->\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n'
)


def compose_square(src: Image.Image, size: int, inner_ratio: float = 1.0,
                   bg=(255, 255, 255)) -> Image.Image:
    """把任意长宽比的图居中放进正方形白底。

    inner_ratio 控制图最多占画布的多大比例（1.0 = 顶满）。
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


def drop_unused(name: str) -> int:
    """删掉某个已不再需要的 mipmap 资源"""
    removed = 0
    for d in RES.glob('mipmap-*'):
        p = d / name
        if p.exists():
            p.unlink()
            removed += 1
    return removed


def main() -> int:
    if not SOURCE.exists():
        print(f'找不到源图：{SOURCE}', file=sys.stderr)
        return 1

    src = Image.open(SOURCE).convert('RGB')
    print(f'源图 {src.size[0]}×{src.size[1]}  ({SOURCE.name})')
    print(f'形状：正方形 + 四边圆角（半径 {CORNER_RATIO:.0%}）')

    master = compose_square(src, max(LEGACY.values()))

    print('\n生成启动器图标（圆角已烘焙进 PNG，系统原样显示）:')
    for density, size in LEGACY.items():
        icon = rounded(master.resize((size, size), Image.LANCZOS), CORNER_RATIO)
        p = save(icon, density, 'ic_launcher.png')
        print(f'  {density:8s} {size:>3}px  圆角 {size * CORNER_RATIO:4.1f}px  '
              f'{p.stat().st_size/1024:6.1f} KB')

    xml_path = RES / 'mipmap-anydpi-v26' / 'ic_launcher.xml'

    if GENERATE_ADAPTIVE_ICON:
        print('\n生成自适应图标背景（纯白，圆角由启动器遮罩切）:')
        for density, size in ADAPTIVE.items():
            p = save(Image.new('RGB', (size, size), (255, 255, 255)),
                     density, 'ic_launcher_background.png')
            print(f'  {density:8s} {size:>3}px  {p.stat().st_size/1024:6.1f} KB')

        print(f'\n生成自适应图标前景（图缩进 {SAFE_ZONE:.0%}，四周透明）:')
        safe_master = compose_square(src, max(ADAPTIVE.values()), SAFE_ZONE)
        for density, size in ADAPTIVE.items():
            fg = safe_master.resize((size, size), Image.LANCZOS).convert('RGBA')
            px = fg.load()
            edge = int(size * (1 - SAFE_ZONE) / 2)
            for y in range(size):
                for x in range(size):
                    if x < edge or x >= size - edge or y < edge or y >= size - edge:
                        px[x, y] = (0, 0, 0, 0)
            p = save(fg, density, 'ic_launcher_foreground.png')
            print(f'  {density:8s} {size:>3}px  {p.stat().st_size/1024:6.1f} KB')

        xml_path.parent.mkdir(parents=True, exist_ok=True)
        xml_path.write_text(ADAPTIVE_XML, encoding='utf-8')
        print(f'\n✅ 已写出 {xml_path.relative_to(ROOT)}')
    else:
        # 关掉自适应图标时把它的图层和 XML 一并清掉，避免留一堆没用的资源
        n = drop_unused('ic_launcher_background.png')
        n += drop_unused('ic_launcher_foreground.png')
        if xml_path.exists():
            xml_path.unlink()
            n += 1
        if n:
            print(f'\n🧹 清掉 {n} 个不再需要的自适应图标资源'
                  '\n   （背景/前景 PNG + anydpi-v26/ic_launcher.xml）')
        print('\nℹ️  未生成自适应图标：它的形状由启动器遮罩决定，'
              '\n   会是圆形或大圆角方形，拿不到「正方形 + 四边圆角」。'
              '\n   想换回去就把 GENERATE_ADAPTIVE_ICON 改成 True 再跑。')

    print('\n✅ 完成。清单：')
    for density in LEGACY:
        names = sorted(x.name for x in (RES / f'mipmap-{density}').glob('ic_launcher*'))
        print(f'  mipmap-{density:8s} {names}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
