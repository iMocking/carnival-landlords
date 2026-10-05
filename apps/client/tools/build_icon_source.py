"""从《狂欢斗地主》设计图里提取地主形象头像，生成 res://icon.svg。

    python tools/build_icon_source.py        # 在仓库根目录执行，覆盖 res://icon.svg
    godot --path . --script res://tools/build_icon.gd   # 再由 icon.svg 生成 icon.ico

设计图上没有单独的图标素材，桌面图标用「狂欢大侠」的头像（desgin/《狂欢斗地主》个人中心.jpeg
里的圆形头像）—— 它是设计稿里最干净、分辨率最高的地主形象头像。

需要说明的两点：

* 设计稿头像右下角叠着一个「换头像」的界面角标，它不是角色的一部分。这里用同半径的
  角度插值把它抹掉（那一圈背后是平滑的暗色内底，插值无缝）。
* 头像本身是位图。Godot 4.7 的 ThorVG 光栅化器支持 <image> 内嵌 data URI，所以直接把
  头像以 base64 PNG 嵌进 icon.svg —— 不必新增位图素材，`application/config/icon` 仍然
  指向 res://icon.svg，tools/build_icon.gd 与 tests/branding_test.gd 都不用改。

只依赖 Pillow（numpy 随 Pillow 一起装）。
"""
from __future__ import annotations

import base64
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "desgin" / "《狂欢斗地主》个人中心.jpeg"
OUT = ROOT / "icon.svg"

# 设计稿头像的几何量（在 SRC 的像素坐标下量得）
CX, CY = 453.0, 569.0        # 金环内圈圆心
R_INNER = 202.0              # 金环内圈半径
R_CROP = 194.0               # 实际裁剪半径：比内圈小一圈，避免把金环像素带进来
BADGE = (566, 683, 654, 776)  # 「换头像」角标 x0,y0,x1,y1
EMBED = 192                  # 内嵌 PNG 边长：256px 图标里头像只占 188px，192 足够

# 底色（红金圆角底）
PLATE_TOP = "#f5674e"
PLATE_MID = "#de332f"
PLATE_BOTTOM = "#9c1418"


def _sample(a: np.ndarray, px: np.ndarray, py: np.ndarray) -> np.ndarray:
    """双线性采样，越界钳到边缘。"""
    h, w = a.shape[:2]
    px = np.clip(px, 0, w - 1.001)
    py = np.clip(py, 0, h - 1.001)
    x0 = np.floor(px).astype(int)
    y0 = np.floor(py).astype(int)
    fx = (px - x0)[..., None]
    fy = (py - y0)[..., None]
    c00 = a[y0, x0]
    c10 = a[y0, x0 + 1]
    c01 = a[y0 + 1, x0]
    c11 = a[y0 + 1, x0 + 1]
    return c00 * (1 - fx) * (1 - fy) + c10 * fx * (1 - fy) + c01 * (1 - fx) * fy + c11 * fx * fy


def erase_badge(a: np.ndarray) -> np.ndarray:
    """把「换头像」角标用同半径的角度插值补掉。"""
    pad = 6
    bx0, by0, bx1, by1 = BADGE[0] - pad, BADGE[1] - pad, BADGE[2] + pad, BADGE[3] + pad
    yy, xx = np.mgrid[by0:by1 + 1, bx0:bx1 + 1]
    rr = np.hypot(xx - CX, yy - CY)
    th = np.arctan2(yy - CY, xx - CX)
    mask = rr < (R_CROP + 26)          # 只处理可能被裁进圆内的部分

    n_ang = 1440
    ang = np.linspace(-np.pi, np.pi, n_ang, endpoint=False)
    radius = np.arange(0.5, R_CROP + 28, 0.5)
    cols = CX + radius[:, None] * np.cos(ang)[None, :]
    rows = CY + radius[:, None] * np.sin(ang)[None, :]
    ring = _sample(a, cols, rows)      # (R, n_ang, 3)

    covered = ((cols >= bx0) & (cols <= bx1) & (rows >= by0) & (rows <= by1))
    filled = ring.copy()
    for i in range(ring.shape[0]):
        m = covered[i]
        if not m.any() or m.all():
            continue
        idx = np.nonzero(~m)[0]
        for ch in range(3):
            # period=n_ang 让插值跨越 ±180° 的接缝也是连续的
            filled[i][m, ch] = np.interp(np.arange(n_ang), idx, ring[i, idx, ch], period=n_ang)[m]

    ai = np.clip(((th + np.pi) / (2 * np.pi) * n_ang).astype(int), 0, n_ang - 1)
    ri = np.clip((rr / 0.5).astype(int) - 1, 0, len(radius) - 1)
    sub = a[by0:by1 + 1, bx0:bx1 + 1]
    sub[mask] = filled[ri, ai][mask]
    a[by0:by1 + 1, bx0:bx1 + 1] = sub
    return a


def lift_shadows(img: Image.Image) -> Image.Image:
    """抬暗部 + 暖色偏移：设计稿头像的内底偏黑，缩到 16~32px 会糊成一团深褐。"""
    px = np.asarray(img).astype(np.float64)
    rgb = np.power(px[..., :3] / 255.0, 0.72)
    rgb[..., 0] = np.clip(rgb[..., 0] * 1.06, 0, 1)
    rgb[..., 2] = np.clip(rgb[..., 2] * 0.94, 0, 1)
    px[..., :3] = rgb * 255.0
    return Image.fromarray(px.astype(np.uint8), "RGBA")


def extract_avatar() -> Image.Image:
    """裁出圆形头像（带抗锯齿的 alpha）。"""
    im = Image.open(SRC).convert("RGB")
    a = erase_badge(np.asarray(im).astype(np.float64))

    size = int(R_CROP * 2)
    left, top = int(round(CX - R_CROP)), int(round(CY - R_CROP))
    square = Image.fromarray(a.astype(np.uint8)).crop((left, top, left + size, top + size))

    ss = 4                              # 4x 超采样圆边
    alpha = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(alpha).ellipse([ss * 0.5, ss * 0.5, size * ss - ss * 0.5, size * ss - ss * 0.5], fill=255)
    alpha = alpha.resize((size, size), Image.LANCZOS)

    out = square.convert("RGBA")
    out.putalpha(alpha)
    return lift_shadows(out.resize((EMBED, EMBED), Image.LANCZOS))


SVG = '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="128" height="128" viewBox="0 0 128 128">
  <!--
    桌面图标：红金圆角底 + 双层金边，中间是《狂欢斗地主》设计图里地主形象
    「狂欢大侠」的圆形头像，外加一圈金环。
    头像取自 desgin/《狂欢斗地主》个人中心.jpeg（右下角的「换头像」UI 角标已抹掉），
    以 base64 PNG 内嵌 —— Godot 的 ThorVG 支持 <image> 的 data URI，所以本文件
    依旧是唯一的图标源：tools/build_icon.gd 直接把它光栅化成 icon.ico。
    重新生成：python tools/build_icon_source.py
  -->
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{plate_top}"/>
      <stop offset="0.45" stop-color="{plate_mid}"/>
      <stop offset="1" stop-color="{plate_bottom}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.22" r="0.78">
      <stop offset="0" stop-color="#ffc09a" stop-opacity="0.5"/>
      <stop offset="1" stop-color="#ffc09a" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0.62" stop-color="#ff7a30" stop-opacity="0"/>
      <stop offset="0.82" stop-color="#ff7433" stop-opacity="0.34"/>
      <stop offset="1" stop-color="#ff7433" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff3c4"/>
      <stop offset="0.45" stop-color="#ffd257"/>
      <stop offset="1" stop-color="#bd7d1c"/>
    </linearGradient>
    <linearGradient id="goldRing" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#fff6d2"/>
      <stop offset="0.35" stop-color="#ffd257"/>
      <stop offset="0.62" stop-color="#e0a02c"/>
      <stop offset="1" stop-color="#a96a12"/>
    </linearGradient>
    <linearGradient id="card" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fffdf6"/>
      <stop offset="1" stop-color="#efe6d2"/>
    </linearGradient>
  </defs>

  <!-- 底板：红金圆角方 + 双层金边 -->
  <rect x="4" y="4" width="120" height="120" rx="27" fill="url(#bg)"/>
  <rect x="4" y="4" width="120" height="120" rx="27" fill="url(#glow)"/>
  <rect x="4" y="4" width="120" height="120" rx="27" fill="none" stroke="#5a1206" stroke-width="8"/>
  <rect x="8" y="8" width="112" height="112" rx="23" fill="none" stroke="url(#gold)" stroke-width="5"/>
  <rect x="16" y="16" width="96" height="96" rx="16" fill="none" stroke="#fff3c4" stroke-opacity="0.22" stroke-width="2"/>

  <!-- 头像：设计图里的地主形象，外圈一层暖光让暗底不至于糊成褐色 -->
  <circle cx="64" cy="63" r="46" fill="url(#halo)"/>
  <image x="24" y="23" width="80" height="80" xlink:href="data:image/png;base64,{b64}"/>
  <circle cx="64" cy="63" r="42.6" fill="none" stroke="#3f0d08" stroke-width="2.6"/>
  <circle cx="64" cy="63" r="40" fill="none" stroke="url(#goldRing)" stroke-width="5.4"/>
  <circle cx="64" cy="63" r="36.2" fill="none" stroke="#fff3c4" stroke-opacity="0.28" stroke-width="1.2"/>

  <!-- 右下角：白牌红桃，一眼认出是斗地主 -->
  <g transform="rotate(14 100 104)">
    <rect x="93" y="95" width="15" height="21" rx="3.5" fill="#3d0509" opacity="0.35" transform="translate(1.6 1.6)"/>
    <rect x="93" y="95" width="15" height="21" rx="3.5" fill="url(#card)" stroke="#b9a98a" stroke-width="1.2"/>
    <path d="M23.6,0c-3.4,0-6.3,2.7-7.6,5.6C14.7,2.7,11.8,0,8.4,0C3.8,0,0,3.8,0,8.4c0,9.4,9.5,11.9,16,21.2 c6.1-9.3,16-12.1,16-21.2C32,3.8,28.2,0,23.6,0z"
          fill="#cc2b28" transform="translate(94.3 97.2) scale(0.20)"/>
  </g>
</svg>
'''


def main() -> int:
    if not SRC.exists():
        print(f"missing design source: {SRC}", file=sys.stderr)
        return 1
    avatar = extract_avatar()

    buf = io.BytesIO()
    avatar.save(buf, "PNG", optimize=True)
    png = buf.getvalue()
    b64 = base64.b64encode(png).decode("ascii")

    OUT.write_text(
        SVG.format(plate_top=PLATE_TOP, plate_mid=PLATE_MID, plate_bottom=PLATE_BOTTOM, b64=b64),
        encoding="utf-8",
        newline="\n",          # 与 .gitattributes 的 eol=lf 保持一致
    )
    print(f"avatar {EMBED}x{EMBED} png={len(png)}B -> {OUT.relative_to(ROOT)} ({OUT.stat().st_size}B)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
