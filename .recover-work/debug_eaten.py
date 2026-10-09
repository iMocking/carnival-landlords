"""临时调试：看某个洞的 eaten_options 到底算出了什么。"""
import re
import sys
import os

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repair  # noqa: E402

name = sys.argv[1]
needle = sys.argv[2]
buf = repair.invert(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "damaged", name), "rb").read())
for unit in repair.parse_units(buf):
    off, ln, ln_no, kind, payload = unit
    if kind != "hole":
        continue
    line_lo = buf.rfind(b"\n", 0, off) + 1
    line_hi = buf.find(b"\n", off)
    if line_hi < 0:
        line_hi = len(buf)
    before = buf[line_lo:off].decode("utf-8", "replace")
    if needle not in before:
        continue
    after = buf[off + ln:line_hi].decode("utf-8", "replace")
    print("offset", off, "len", ln, "payload", payload.hex())
    print("  before tail:", repr(before[-40:]))
    print("  after      :", repr(after[:90]))
    print("  quote_open(before) =", repair._quote_open(before))
    print("  quotes in after    =", len(re.findall(r'(?<!\\)"', after)))
    print("  format regex match =", bool(re.match(r"^[sdifxXo]", after)))
    print("  eaten_options      =", repair.eaten_options(buf, off, ln))
