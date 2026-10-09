"""把 design_update/<页面>/index.html（pagx 导出稿）转成可读的版面规格。

用法：
    python tools/design_spec.py                    # 全部页面
    python tools/design_spec.py 游戏启动界面         # 指定页面
    python tools/design_spec.py --json out.json    # 同时导出结构化 JSON

设计稿是「绝对定位 + 内联样式」的扁平导出：每个视觉节点靠 `transform: translate(x,y)`
定位在父节点坐标系里，尺寸写在 CSS 类里。脚本把这两件事合成**画布绝对坐标**，
并按缩进打印，于是"谁在谁上面、离左边多远、多大、什么颜色、什么字"一目了然。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import lxml.html

ROOT = Path(__file__).resolve().parents[1]
DESIGN_DIR = ROOT / "design_update"

STYLE_BLOCK = re.compile(r"<style[^>]*>(.*?)</style>", re.S)
TRANSLATE = re.compile(r"translate\(\s*(-?[\d.]+)px\s*,\s*(-?[\d.]+)px\s*\)")
ROTATE = re.compile(r"rotate\(\s*(-?[\d.]+)deg\s*\)")


def load_css(html_text: str) -> dict[str, dict[str, str]]:
    """手工扫描花括号解析 CSS。

    不能用 `([^{}]+)\\{([^{}]*)\\}` 这种正则：在几十万字符的稿子上，
    `[^{}]+` 每遇到一个非 `{` 的字符都要回溯一次，实测直接把脚本挂死。
    """
    rules: dict[str, dict[str, str]] = {}
    for block in STYLE_BLOCK.findall(html_text):
        cursor = 0
        while True:
            open_i = block.find("{", cursor)
            if open_i < 0:
                break
            close_i = block.find("}", open_i)
            if close_i < 0:
                break
            selectors = block[cursor:open_i].strip()
            body = block[open_i + 1 : close_i]
            cursor = close_i + 1
            if not selectors or selectors.startswith("@"):
                continue
            props: dict[str, str] = {}
            for chunk in body.split(";"):
                if ":" in chunk:
                    key, value = chunk.split(":", 1)
                    props[key.strip()] = value.strip()
            for selector in selectors.split(","):
                selector = selector.strip().lstrip(".")
                if selector:
                    rules[selector] = props
    return rules


def px(value: str | None) -> float | None:
    if not value:
        return None
    match = re.match(r"^(-?[\d.]+)px$", value.strip())
    return float(match.group(1)) if match else None


def props_of(el, css: dict[str, dict[str, str]]) -> dict[str, str]:
    merged: dict[str, str] = {}
    for cls in (el.get("class") or "").split():
        merged.update(css.get(cls, {}))
    for decl in (el.get("style") or "").split(";"):
        if ":" in decl:
            key, value = decl.split(":", 1)
            merged[key.strip()] = value.strip()
    return merged


def rect_of(props: dict[str, str], parent: tuple[float, float]) -> tuple[float, float, float, float]:
    """返回画布绝对坐标 (x, y, w, h)。"""
    ox, oy = parent
    transform = props.get("transform", "")
    shift = TRANSLATE.search(transform)
    if shift:
        ox += float(shift.group(1))
        oy += float(shift.group(2))
    elif props.get("position") == "absolute":
        ox += px(props.get("left")) or 0.0
        oy += px(props.get("top")) or 0.0
    w = px(props.get("width"))
    h = px(props.get("height"))
    return ox, oy, w if w is not None else -1.0, h if h is not None else -1.0


def paint_of(props: dict[str, str]) -> str:
    bits: list[str] = []
    when = props.get("background") or props.get("background-color")
    if when and when not in ("none", "transparent"):
        bits.append(when)
    if props.get("border"):
        bits.append("border=" + props["border"])
    for side in ("top", "right", "bottom", "left"):
        key = f"border-{side}"
        if props.get(key):
            bits.append(f"{key}={props[key]}")
    if props.get("border-radius"):
        bits.append("r=" + props["border-radius"])
    if props.get("box-shadow"):
        bits.append("shadow=" + props["box-shadow"])
    if props.get("filter"):
        bits.append("filter=" + props["filter"])
    if props.get("clip-path"):
        bits.append("clip=" + props["clip-path"])
    if props.get("opacity"):
        bits.append("opacity=" + props["opacity"])
    return " | ".join(bits)


def text_of(el) -> str:
    """只取**直接**挂在当前节点上的文本（pagx 的每个文本块都是一个独立 div）。"""
    parts: list[str] = []
    holders = [el] if el.get("data-pagx-text") else []
    holders += el.xpath("./*[@data-pagx-text]")
    for holder in holders:
        raw = holder.get("data-pagx-text") or ""
        spans = holder.xpath(".//span")
        styles = []
        for span in spans:
            props = {}
            for decl in (span.get("style") or "").split(";"):
                if ":" in decl:
                    key, value = decl.split(":", 1)
                    props[key.strip()] = value.strip()
            styles.append(
                "{}px {} {}".format(
                    re.sub(r"px$", "", props.get("font-size", "?")),
                    props.get("color", "?"),
                    props.get("font-family", "?").strip("'"),
                )
            )
        unique = sorted(set(styles))
        parts.append(f'"{raw}" [{"; ".join(unique)}]')
    return "  //  ".join(parts)


def walk(el, css, parent_xy, depth, out, canvas_w, canvas_h):
    props = props_of(el, css)
    if depth == 0:
        x, y, w, h = 0.0, 0.0, canvas_w, canvas_h
    else:
        x, y, w, h = rect_of(props, parent_xy)
    named = el.get("data-name")
    text = text_of(el)
    paint = paint_of(props)
    rot = ROTATE.search(props.get("transform", ""))
    interesting = bool(named) or bool(text) or bool(paint)
    if interesting:
        label = named or el.get("id") or "div"
        size = f"{w:.0f}x{h:.0f}" if w >= 0 and h >= 0 else "auto"
        line = "  " * depth + f"[{x:7.1f},{y:6.1f}] {size:>9}  {label}"
        if rot:
            line += f"  rotate({float(rot.group(1)):g}deg)"
        if paint:
            line += f"\n{'  ' * depth}      {paint}"
        if text:
            line += f"\n{'  ' * depth}      {text}"
        if el.get("data-node-type"):
            line += f"  (type={el.get('data-node-type')})"
        out.append(line)
    for child in el:
        if not isinstance(child.tag, str):
            continue
        walk(child, css, (x, y), depth + 1 if interesting else depth, out, canvas_w, canvas_h)


def extract(page_dir: Path) -> str:
    html_text = page_dir.joinpath("index.html").read_text(encoding="utf-8")
    doc = lxml.html.fromstring(html_text)
    css = load_css(html_text)
    viewport = doc.xpath("//*[@data-pagx-viewport]")
    canvas_w, canvas_h = 1080.0, 640.0
    if viewport:
        style = viewport[0].get("style") or ""
        w = re.search(r"width:(\d+)px", style)
        h = re.search(r"height:(\d+)px", style)
        if w:
            canvas_w = float(w.group(1))
        if h:
            canvas_h = float(h.group(1))
    out: list[str] = [f"### {page_dir.name}  ({canvas_w:.0f}x{canvas_h:.0f})"]
    bodies = doc.xpath("//body")
    for body in bodies:
        for child in body:
            if not isinstance(child.tag, str):
                continue
            walk(child, css, (0.0, 0.0), 0, out, canvas_w, canvas_h)
    return "\n".join(out)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    json_path = None
    if "--json" in sys.argv:
        json_path = sys.argv[sys.argv.index("--json") + 1]
    pages = sorted(p for p in DESIGN_DIR.iterdir() if p.is_dir() and p.joinpath("index.html").exists())
    if args:
        pages = [p for p in pages if p.name in args]
    report = [extract(p) for p in pages]
    text = "\n\n".join(report)
    out_path = ROOT / ".probe" / "design_spec.txt"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8")
    print(f"wrote {out_path} ({len(text)} chars, {len(pages)} pages)")
    if json_path:
        Path(json_path).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
