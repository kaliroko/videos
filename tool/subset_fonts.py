#!/usr/bin/env python3
"""重新生成 assets/fonts 里的字体子集。

背景
----
「碎碎念」模块用了两款开源中文字体：

  * MaShanZheng（毛笔手写体）—— 只负责装饰性文字：页头大字、循环书写的那句话、
    卡片日期、发布卡片标题、FAB 上的「写」。这些文案全是写死在源码里的，
    所以可以把字体裁到只剩用得到的字，体积从 5.6 MB 降到约 380 KB。
  * ZCOOLKuaiLe（圆润可爱体）—— 负责昵称、印章、标签、按钮。
    昵称是**用户输入**，什么字都可能出现，所以这款字体**不裁剪**，保留完整字库。

什么时候需要重跑
----------------
只要你新增了用 `DiaryPalette.brush` 渲染的中文文案，就要重跑一次，
否则新字会回退到系统字体（不会变成豆腐块，但字形会不一致）。

用法
----
    pip install fonttools
    python3 tool/subset_fonts.py

校验
----
脚本最后会把源码里所有字符串字面量的非 ASCII 字符拿出来，
逐个检查是否在对应字体里有字形；有缺口就以非 0 退出，便于接进 CI。
"""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

try:
    from fontTools.ttLib import TTFont
    from fontTools import subset
except ImportError:  # pragma: no cover
    print('缺少依赖，请先执行：pip install fonttools', file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / 'assets' / 'fonts'

# 手写体只服务这些文件；扫描它们的所有字符即可
BRUSH_SOURCES = [
    'lib/theme/diary_palette.dart',
    'lib/models/diary_post.dart',
    'lib/providers/diary_provider.dart',
    'lib/repository/diary_repository.dart',
    'lib/screens/diary_screen.dart',
    'lib/screens/diary_compose_sheet.dart',
    'lib/widgets/diary_card.dart',
    'lib/widgets/diary_image_viewer.dart',
    'lib/widgets/handwriting_text.dart',
    'lib/widgets/ink_seal.dart',
    # 权限页那张「首页预览」用的也是手写体大字，所以也要扫
    'lib/permission_gate.dart',
]

BRUSH_FONT = 'MaShanZheng-Regular.ttf'
ROUND_FONT = 'ZCOOLKuaiLe-Regular.ttf'

UPSTREAM = {
    BRUSH_FONT: 'https://raw.githubusercontent.com/google/fonts/main/ofl/mashanzheng/MaShanZheng-Regular.ttf',
    ROUND_FONT: 'https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf',
}

# 补一些文案里可能用到、但源码未必出现的符号
EXTRA = '，。！？、：；「」『』（）《》…—～“”‘’'

STRING_LITERAL = re.compile(r"'((?:[^'\\\n]|\\.)*)'")


def ensure_original(name: str) -> Path:
    """拿到未裁剪的原始字体。

    已经裁剪过的文件字形数会明显偏少，这种情况重新下载一份原件。
    """
    path = FONT_DIR / name
    if path.exists():
        glyphs = len(TTFont(path).getBestCmap())
        if glyphs > 3000:
            return path
        print(f'  {name} 已是裁剪版本（{glyphs} 字形），重新下载原件…')
    else:
        print(f'  {name} 不存在，下载原件…')

    tmp = FONT_DIR / f'.{name}.orig'
    with urllib.request.urlopen(UPSTREAM[name], timeout=180) as resp:
        tmp.write_bytes(resp.read())
    return tmp


def collect_chars() -> set[str]:
    chars: set[str] = set()
    for rel in BRUSH_SOURCES:
        path = ROOT / rel
        if not path.exists():
            print(f'  ⚠️ 找不到 {rel}，跳过', file=sys.stderr)
            continue
        chars |= set(path.read_text(encoding='utf-8'))
    chars = {c for c in chars if c.isprintable() or c == ' '}
    chars |= {chr(i) for i in range(0x20, 0x7F)}
    chars |= set(EXTRA)
    return chars


def rebuild_brush(chars: set[str]) -> None:
    source = ensure_original(BRUSH_FONT)
    keep = FONT_DIR / '.keep.txt'
    keep.write_text(''.join(sorted(chars)), encoding='utf-8')

    target = FONT_DIR / BRUSH_FONT
    subset.main([
        str(source),
        f'--text-file={keep}',
        f'--output-file={target}',
        '--layout-features=*',
        '--no-hinting',
        '--desubroutinize',
        '--drop-tables+=DSIG',
        '--name-IDs=*',
        '--recalc-bounds',
    ])
    keep.unlink(missing_ok=True)
    if source != target and source.name.startswith('.'):
        source.unlink(missing_ok=True)

    size_kb = target.stat().st_size / 1024
    print(f'  {BRUSH_FONT}: {len(chars)} 个字符 → {size_kb:.1f} KB')


def verify() -> int:
    """界面文案里的每个非 ASCII 字符都要有字形。

    只检查会渲染到屏幕上的字符串：注释和 debugPrint 日志（里面有 ✅ ❌ 这类 emoji）
    不参与渲染，跳过它们，否则会误报。
    """
    brush = set(TTFont(FONT_DIR / BRUSH_FONT).getBestCmap())
    round_ = set(TTFont(FONT_DIR / ROUND_FONT).getBestCmap())

    problems = 0
    for rel in BRUSH_SOURCES:
        path = ROOT / rel
        if not path.exists():
            continue
        for lineno, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith('//'):
                continue  # 注释不参与渲染
            if 'debugPrint(' in line or 'log(' in line:
                continue  # 日志不参与渲染
            for match in STRING_LITERAL.finditer(line):
                for ch in match.group(1):
                    if ord(ch) < 0x80:
                        continue
                    if ord(ch) not in brush and ord(ch) not in round_:
                        print(f'  ❌ {rel}:{lineno} 缺字形: {ch!r}', file=sys.stderr)
                        problems += 1

    if problems:
        print(f'\n发现 {problems} 处字形缺口', file=sys.stderr)
        return 1
    print('  ✅ 所有界面文案都有字形覆盖')
    return 0


def main() -> int:
    print('收集手写体需要的字符…')
    chars = collect_chars()
    print(f'  {len(chars)} 个字符')

    print('重建字体…')
    rebuild_brush(chars)
    round_path = FONT_DIR / ROUND_FONT
    if round_path.exists():
        glyphs = len(TTFont(round_path).getBestCmap())
        print(f'  {ROUND_FONT}: 保留完整字库（{glyphs} 字形），不裁剪')

    print('校验…')
    return verify()


if __name__ == '__main__':
    raise SystemExit(main())
