"""统计真实损坏文件里的洞的形态：每个洞所在字符丢了几字节、已知前缀多长。"""
import os
import sys
from collections import Counter

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repair  # noqa: E402

FILES = ["history_view.gd", "skins_view.gd", "settings_view.gd",
         "achievements_view.gd", "messages_view.gd", "profile_view.gd"]

total = Counter()
grand = Counter()
for name in FILES:
    path = os.path.join("src", "view", "pages", name)
    buf = repair.invert(open(path, "rb").read())
    units = repair.parse_units(buf)
    # 用更宽的扫描：把每个「非 ASCII 起始的字符单元」都列出来
    i = 0
    n = len(buf)
    shapes = Counter()
    while i < n:
        need = repair.char_length(buf[i])
        if need and i + need <= n:
            tail = buf[i + 1:i + need]
            holes = sum(1 for b in tail if b == 0x3F)
            known = sum(1 for b in tail if 0x80 <= b <= 0xBF)
            if holes:
                shapes[(need, known, holes)] += 1
            i += need
            continue
        i += 1
    total[name] = sum(shapes.values())
    grand.update(shapes)
    detail = "  ".join(f"{k}:{v}" for k, v in sorted(shapes.items()))
    print(f"{name:<20} 洞 {sum(shapes.values()):<4} {detail}")
print("\n合计形态 (字符字节数, 已知续字节数, 洞数) -> 次数")
for k, v in sorted(grand.items(), key=lambda kv: -kv[1]):
    print(f"  {k}: {v}")
print(f"总计 {sum(grand.values())}")
