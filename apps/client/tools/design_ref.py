"""把 design_update 的 pagx 稿变成「能看的参考图」。

导出稿把每个字的文字放在 `data-pagx-text` 上，`<span>` 里却是空的（字号 / 颜色 /
位置都在 span 上）。于是直接在浏览器里打开会看不到任何文字。这个脚本把文字按
**逐字符**塞回 span，再用无头 Chrome 截成 1080 宽的参考图，用来和游戏截图逐页比对。

用法：
    python tools/design_ref.py                 # 全部页面
    python tools/design_ref.py 登录界面 游戏启动界面
输出：res://.probe/design_ref/<页面>.png
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import lxml.html

ROOT = Path(__file__).resolve().parents[1]
DESIGN_DIR = ROOT / "design_update"
OUT_DIR = ROOT / ".probe" / "design_ref"
CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")


def inject_text(html_text: str) -> str:
    doc = lxml.html.fromstring(html_text)
    for holder in doc.xpath("//*[@data-pagx-text]"):
        text = holder.get("data-pagx-text") or ""
        spans = holder.xpath("./span") or holder.xpath(".//span")
        if not spans:
            continue
        for index, span in enumerate(spans):
            span.text = text[index] if index < len(text) else ""
    return lxml.html.tostring(doc, encoding="unicode", doctype="<!DOCTYPE html>")


def render(page: Path, out_png: Path) -> None:
    build = OUT_DIR / page.name
    if build.exists():
        shutil.rmtree(build)
    build.mkdir(parents=True)
    assets = page / "assets"
    if assets.exists():
        shutil.copytree(assets, build / "assets")
    (build / "index.html").write_text(inject_text((page / "index.html").read_text(encoding="utf-8")), encoding="utf-8")
    cmd = [
        str(CHROME),
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--window-size=1080,640",
        "--screenshot=" + str(out_png),
        (build / "index.html").resolve().as_uri(),
    ]
    result = subprocess.run(cmd, capture_output=True, timeout=120)
    if not out_png.exists():
        raise SystemExit(f"chrome failed for {page.name}: {result.stderr.decode('utf-8', 'ignore')[-500:]}")


def main() -> int:
    args = [a for a in sys.argv[1:]]
    pages = sorted(p for p in DESIGN_DIR.iterdir() if p.is_dir() and (p / "index.html").exists())
    if args:
        pages = [p for p in pages if p.name in args]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for page in pages:
        out_png = OUT_DIR / f"{page.name}.png"
        render(page, out_png)
        print(f"{page.name} -> {out_png.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
