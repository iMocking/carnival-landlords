"""量一下各页面截图里，内容左右两侧的留白是否对称。

做法：在若干条水平扫描线上，找最左 / 最右那个"与背景差异明显"的像素列。
背景是暗红渐变，内容元素（面板、卡片、文字）都比它亮或比它暗很多，
因此用"与同一行背景中位色的差值"来判定内容边界。
"""
import sys
from pathlib import Path

from PIL import Image

SHOTS = Path(r"D:\code\github\waiting-for-landlord\.probe\shots")


def row_bounds(img: Image.Image, y: int, thresh: int = 26) -> tuple[int, int] | None:
    px = img.load()
    width = img.size[0]
    row = [px[x, y] for x in range(width)]
    # 以整行的中位色近似"背景"
    lum = sorted(0.299 * r + 0.587 * g + 0.114 * b for r, g, b in row)
    base = lum[len(lum) // 2]
    cols = [
        x
        for x in range(width)
        if abs((0.299 * row[x][0] + 0.587 * row[x][1] + 0.114 * row[x][2]) - base) > thresh
    ]
    if not cols:
        return None
    return cols[0], cols[-1]


def report(name: str) -> None:
    path = SHOTS / f"{name}.png"
    if not path.exists():
        print(f"{name:26s} (missing)")
        return
    img = Image.open(path).convert("RGB")
    w, h = img.size
    lefts, rights = [], []
    for frac in (0.16, 0.28, 0.42, 0.55, 0.68, 0.82):
        found = row_bounds(img, int(h * frac))
        if found:
            lefts.append(found[0])
            rights.append(w - 1 - found[1])
    if not lefts:
        print(f"{name:26s} no content detected")
        return
    print(
        f"{name:26s} {w}x{h}  left={min(lefts):3d}..{max(lefts):3d}  "
        f"right={min(rights):3d}..{max(rights):3d}  delta={min(lefts) - min(rights):+d}"
    )


for shot in sys.argv[1:]:
    report(shot)
