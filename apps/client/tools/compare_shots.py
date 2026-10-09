"""把「设计参考图」与「游戏截图」拼成一张上下对照图，便于逐页比对。

用法：
    python tools/compare_shots.py                 # 全部已配对的页面
    python tools/compare_shots.py 登录界面 对局牌桌  # 只拼指定页面（用设计稿目录名）

输出：res://.probe/compare/<页面>.png（上：设计稿；下：游戏截图，等宽缩放）

前置：
    python tools/design_ref.py        # 生成 .probe/design_ref/<页面>.png
    godot --path . --script res://tools/capture_shots.gd   # 生成 .probe/shots/*.png
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
REF_DIR = ROOT / ".probe" / "design_ref"
SHOT_DIR = ROOT / ".probe" / "shots"
OUT_DIR = ROOT / ".probe" / "compare"

## 设计稿目录名 -> 游戏截图文件名（capture_shots.gd 的 job 名）
PAIRS = {
    "游戏启动界面": "00_boot",
    "登录界面": "01_login",
    "狂欢斗地主游戏大厅": "02_lobby",
    "活动中心": "02b_activity",
    "商城": "02c_shop",
    "个人中心": "03_profile_hub",
    "我的战绩": "03_profile_history",
    "主题皮肤": "04_profile_skins",
    "我的成就": "05_profile_achievements",
    "消息中心": "05b_profile_messages",
    "系统设置": "05c_settings_basic",
    "对局牌桌": "06_game",
}

WIDTH = 900
GAP = 10
LABEL_H = 26


def load_scaled(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    height = max(1, round(image.height * WIDTH / image.width))
    return image.resize((WIDTH, height), Image.LANCZOS)


def compose(page: str, shot: str) -> Path | None:
    ref_path = REF_DIR / f"{page}.png"
    shot_path = SHOT_DIR / f"{shot}.png"
    if not ref_path.exists() or not shot_path.exists():
        print(f"skip {page}: ref={ref_path.exists()} shot={shot_path.exists()}")
        return None
    top = load_scaled(ref_path)
    bottom = load_scaled(shot_path)
    canvas = Image.new("RGB", (WIDTH, LABEL_H + top.height + GAP + LABEL_H + bottom.height), (24, 12, 12))
    draw = ImageDraw.Draw(canvas)
    draw.text((6, 6), f"设计稿 {page}", fill=(255, 220, 150))
    canvas.paste(top, (0, LABEL_H))
    y = LABEL_H + top.height + GAP
    draw.text((6, y + 6), f"游戏截图 {shot}", fill=(255, 220, 150))
    canvas.paste(bottom, (0, y + LABEL_H))
    out = OUT_DIR / f"{page}.png"
    canvas.save(out)
    return out


def main() -> int:
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for page, shot in PAIRS.items():
        if wanted and page not in wanted:
            continue
        out = compose(page, shot)
        if out is not None:
            print(f"{page} -> {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
