"""验证损坏模型在「括号 + 换行」这类组合上是否可靠（往返一致性）。"""
import sys
import os

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repair  # noqa: E402

samples = [
    "## 容器给出（安全区 + `SIDE_PADDING`），\n",
    "## 容器给出（安全区），\n## 因此一致。\n",
    "文本给出（安全区 + X），",
    "## 整页容器：左右内缩由 `AppPage` 的安全区容器给出（安全区 + `SIDE_PADDING`），\n## 因此一致。\n",
    "a（b）c\u3002\n",
]
for s in samples:
    raw = s.encode("utf-8")
    back = repair.invert(repair.corrupt(raw))
    print("原文:", s.replace("\n", "\\n"))
    print("  往返:", back.decode("utf-8", "replace").replace("\n", "\\n"))
    print("  一致:", back == raw, " 洞:", [p for p, _ in repair.scan_holes(back)])
