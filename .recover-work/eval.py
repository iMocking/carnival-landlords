"""在「模拟损坏 -> 恢复」上评估 repair.py 的准确率（用完好文件做 ground truth）。"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repair  # noqa: E402

TARGETS = sys.argv[1:] or ["src/view/pages/lobby_view.gd", "src/view/main_view.gd"]

for path in TARGETS:
    original = open(path, "rb").read()
    back = repair.invert(repair.corrupt(original))
    holes = repair.scan_holes(back)
    for label, include_self in (("严格", False), ("含自身", True)):
        paths = repair.project_corpus_paths()
        if include_self:
            paths.append(os.path.abspath(path))
        corpus = repair.Corpus(paths)
        fixed, unsure = repair.repair(back, corpus)
        diff = [i for i in range(min(len(fixed), len(original))) if fixed[i] != original[i]]
        ok = len(holes) - len(diff)
        print(f"[{os.path.basename(path)}/{label}] 洞 {len(holes)}  未解析 {len(unsure)}  "
              f"错 {len(diff)}  准确率 {ok / max(1, len(holes)):.1%}")
        for i in diff[:12]:
            start = i
            while start > 0 and 0x80 <= original[start] <= 0xBF:
                start -= 1
            want = original[start:start + 4].decode("utf-8", "replace")[:1]
            got = fixed[start:start + 4].decode("utf-8", "replace")[:1]
            lo = max(0, start - 40)
            print(f"    off={i} 应为 {want!r} 实为 {got!r}  前文 …"
                  f"{original[lo:start].decode('utf-8', 'replace')[-22:]}")
