"""扫描修复后的文件里仍可能「两行并成一行」的可疑点（补漏用）。

合并行的特征：注释中间突然出现一段代码、或中文行里突兀地出现 4 个以上空格接标识符。
"""
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"D:\code\godot\carnival-landlords\apps\client"
FILES = ["history_view.gd", "skins_view.gd", "settings_view.gd",
         "achievements_view.gd", "messages_view.gd", "profile_view.gd"]

## 注释里出现「代码样」片段
CODE_IN_COMMENT = re.compile(r"(?:\S\s{2,}|[，。）」]\s*)(?:return|var |func |_?[a-z_][a-z0-9_]*\.[a-z_]+\(|"
                             r"[A-Za-z_][A-Za-z0-9_]*\.(?:new|create)\(|row\.|dot\.|app\.)")
## 行首不是注释 / 缩进，却以中文散文开头（典型的被注释吞掉后又漏出来）
ORPHAN = re.compile(r"^\s{1,}\S")


def strip_strings(line: str) -> str:
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', line)


total = 0
for name in FILES:
    path = os.path.join(ROOT, "src", "view", "pages", name)
    for i, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        bare = strip_strings(line)
        stripped = bare.lstrip()
        if stripped.startswith("#"):
            # 注释行里混进代码样片段
            m = CODE_IN_COMMENT.search(stripped)
            if m:
                total += 1
                print(f"{name}:{i}  [注释内疑似代码] {line.strip()[:110]}")
        else:
            # 非注释行：以中文散文开头、且看不出语句结构
            if re.match(r"^[\s]*[\u4e00-\u9fff]", bare) and not re.search(r"[=(\[]", bare):
                total += 1
                print(f"{name}:{i}  [疑似散文行] {line.strip()[:110]}")
print(f"\n可疑点合计 {total}")
