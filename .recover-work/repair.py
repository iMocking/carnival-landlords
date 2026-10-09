"""乱码文件的字节级恢复工具。

背景：这 6 个 .gd 原本是 UTF-8，被 PowerShell 5.1 的 `Get-Content -Raw`（按系统 ANSI/GBK
解码）读成字符串后，又以 UTF-8 写回 —— 于是文件里存的是「GBK 解码结果的 UTF-8 编码」。

逆过程：读 UTF-8 -> 按 GBK 编码 -> 得到**原始字节**，只有一处损失：GBK 解码遇到非法双字节
序列时会吞掉前导字节并吐一个 '?'，编码回来就是 0x3F。

已验证的不变量：被吞掉的字节一定落在某个多字节字符的**最后一个字节**上
（只有「后面紧跟一个 < 0x40 的 ASCII 字节」才构成非法序列，而字符中间的字节后面跟的
都是 >= 0x80 的续字节）。因此：
  * 洞所在字符的前面所有字节都已知；
  * 候选 = 语料里所有以该前缀开头的字符；
  * 用「上下文 n-gram 在语料里的出现次数」给候选打分（含该文件自身的完好部分）。

用法：
  selftest <intact.gd>                 模拟损坏 -> 恢复 -> 与原文件逐字节比对
  fix <damaged.gd> <out.gd>            修复并输出，报告低置信度的洞
  fixall <outdir> <a.gd> <b.gd> ...    批量修复
"""
import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"D:\code\godot\carnival-landlords\apps\client"
BAD_CHARS = {"\ufffd", "?"}
## 被这次事故写坏的文件：**绝不能进语料** —— 它们是 GBK 乱码，
## 混进去会让 n-gram 全是垃圾。
DAMAGED = {
    "history_view.gd", "skins_view.gd", "settings_view.gd",
    "achievements_view.gd", "messages_view.gd", "profile_view.gd",
}

# ---------------------------------------------------------------- CP936 精确表

## Python 自带的 'gbk' 编解码表与 .NET 的 CP936 **并不一致**（PUA 区尤其明显：
## 真实文件里出现的 U+E224 用 Python 的 gbk 根本编不回去）。所以这里直接读一份
## 由 .NET 生成的对照表（`tools` 里生成的 cp936.tsv：码点 -> 双字节）。
_TABLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cp936.tsv")
DEC = {}    # bytes -> char（可能是 1 字节或 2 字节）
ENC = {}    # char -> bytes
with open(_TABLE, "r", encoding="utf-8") as _fh:
    for _line in _fh:
        _line = _line.rstrip("\n")
        if not _line:
            continue
        _cp, _hex = _line.split("\t")
        _ch = chr(int(_cp, 16))
        _raw = bytes.fromhex(_hex)
        DEC.setdefault(_raw, _ch)
        ENC.setdefault(_ch, _raw)


# ---------------------------------------------------------------- 损坏模型


def gbk_decode_like_dotnet(raw: bytes) -> str:
    """精确复刻 .NET CP936 的解码（对 4.7.2 与本机 .NET 逐案例实测）。

    规则：
      * b < 0x80        -> ASCII，吃 1 字节；
      * b == 0x80/0xFF  -> 单字节映射（€ / U+F8F5），吃 1 字节；
      * 后面还有字节：
          - 后继在 0x40..0xFE（0x7F 除外）-> 合法双字节，吃 2 字节；
          - 否则 -> 出 '?'，**并把后继那一个字节也一起吃掉**（吃 2 字节）；
      * 前导字节落在缓冲区末尾 -> '?'，吃 1 字节。

    所以每个 '?' 都精确对应「被吞掉的 2 个字节」：一个汉字末字节 + 一个 < 0x40 的
    ASCII 字节 —— 新行 / 引号 / 逗号 / 右括号就是这么丢的（实测 `E3 80 82 0A` -> 9286 003f，
    新行确实被吃掉了）。
    """
    out = []
    i = 0
    n = len(raw)
    while i < n:
        b = raw[i]
        if b < 0x80:
            out.append(chr(b))
            i += 1
            continue
        one = DEC.get(raw[i:i + 1])
        if one is not None:
            out.append(one)
            i += 1
            continue
        if i + 1 < n:
            ch = DEC.get(raw[i:i + 2])
            if ch is not None:
                out.append(ch)
                i += 2
                continue
            out.append("?")
            i += 2
            continue
        out.append("?")
        i += 1
    return "".join(out)


def corrupt(raw: bytes) -> bytes:
    return gbk_decode_like_dotnet(raw).encode("utf-8")


def invert(damaged: bytes) -> bytes:
    """逆变换：UTF-8 解码后按 CP936 表逐字符编回原始字节。"""
    text = damaged.decode("utf-8")
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if cp < 0x80:
            out.append(cp)
            continue
        pair = ENC.get(ch)
        if pair is None:
            raise ValueError(f"字符 U+{cp:04X} 不在 CP936 表中，无法还原")
        out += pair
    return bytes(out)


# ---------------------------------------------------------------- 洞扫描


def char_length(b: int) -> int:
    if 0xC2 <= b <= 0xDF:
        return 2
    if 0xE0 <= b <= 0xEF:
        return 3
    if 0xF0 <= b <= 0xF4:
        return 4
    return 0


def scan_holes(buf: bytes):
    """返回 [(hole_offset, known_prefix_bytes)]；每个洞都是其字符的最后一个字节。"""
    holes = []
    i = 0
    n = len(buf)
    while i < n:
        need = char_length(buf[i])
        if need and i + need <= n:
            known = [buf[i]]
            hole = None
            broken = False
            for k in range(i + 1, i + need):
                c = buf[k]
                if 0x80 <= c <= 0xBF:
                    known.append(c)
                elif c == 0x3F and hole is None:
                    hole = k
                else:
                    broken = True
                    break
            if not broken:
                if hole is not None:
                    holes.append((hole, bytes(known)))
                i += need
                continue
        i += 1
    return holes


def line_of(buf: bytes, index: int) -> int:
    return buf.count(b"\n", 0, index) + 1


# ---------------------------------------------------------------- 语料


class Corpus:
    """n-gram 语料：所有**完好**字符的相邻二元组 / 三元组计数 + 前缀索引。"""

    def __init__(self, paths):
        self.by_prefix = {}
        self.texts = []
        for p in paths:
            try:
                with open(p, "rb") as fh:
                    raw = fh.read()
            except OSError:
                continue
            text = raw.decode("utf-8", errors="replace")
            self.texts.append(text)
            for ch in text:
                enc = ch.encode("utf-8")
                for cut in range(1, len(enc)):
                    self.by_prefix.setdefault(enc[:cut], set()).add(ch)
        self.size = sum(len(t) for t in self.texts)

    def add_text(self, text: str) -> None:
        """把一段文本并入语料（第二遍用：把已修好的自身文本也当作证据，
        等价于自测里「语料含该文件自身」那一档，实测准确率从 95.6% 提到 97.1%）。"""
        self.texts.append(text)
        for ch in text:
            enc = ch.encode("utf-8")
            for cut in range(1, len(enc)):
                self.by_prefix.setdefault(enc[:cut], set()).add(ch)

    def candidates(self, prefix: bytes):
        return sorted(ch for ch in self.by_prefix.get(prefix, ())
                      if ch.encode("utf-8").startswith(prefix))


def project_corpus_paths(exclude_names=True):
    patterns = ["src/**/*.gd", "tests/**/*.gd", "tools/**/*.gd", "*.tscn", "src/**/*.tscn",
                "*.cfg", "*.md", "*.json", "docs/**/*.md"]
    paths = []
    for pat in patterns:
        paths.extend(glob.glob(os.path.join(ROOT, pat), recursive=True))
    if exclude_names:
        paths = [p for p in paths if os.path.basename(p) not in DAMAGED]
    return sorted(set(paths))


# ---------------------------------------------------------------- 修复（按行 Viterbi）

## 被吞掉的那个字节一定 < 0x40（或 0x7F）—— 实测 .NET 只在这种情况下判非法。
## 这里列出 GDScript 源码里真正可能出现的那些：新行最多，其次是引号 / 逗号 / 右括号。
EATEN_CANDIDATES = [
    "\n", "\t", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+",
    ",", "-", ".", "/", ":", ";", "<", "=", ">", "?",
] + [str(d) for d in range(10)]

## 洞后面紧跟这些，就说明被吞的那个字节**一定是新行**（否则后面的代码会被吞进注释里）。
## 但必须再配一条「后面那段以 ASCII 为主」的判据：否则注释里正常的散文
## （例如「底 rgba(...)、描边 #C68A43」里的 `rgba(`）会被误判成代码而被切成新行，
## 那一段就真的变成代码了 —— 直接解析错误。误判方向不对称：
## 少切一刀只是两行注释并成一行；多切一刀会把散文变成代码，必须避免。
CODE_TRIGGERS = re.compile(
    r"^\s*(?:func\b|static\b|var\b|const\b|class\b|extends\b|signal\b|enum\b|@|if\b|"
    r"for\b|while\b|match\b|return\b|await\b|assert\b|pass\b|break\b|continue\b|"
    r"[A-Za-z_][A-Za-z0-9_]*\s*[.(=\[]|_?[a-z_][a-z0-9_]*\()")
COMMENT_TRIGGER = re.compile(r"^\s*#{1,3} ")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def _quote_open(text: str) -> bool:
    """该行到洞为止是否停在未闭合的字符串字面量里（未转义引号数为奇数）。"""
    return len(re.findall(r'(?<!\\)"', text)) % 2 == 1


def _in_comment(text: str) -> bool:
    """洞是否落在注释里：逐字符走一遍，字符串外的 `#` 之后都算注释。

    这一条必须有：中文注释里常带成对引号（例如「键 = "皮肤 id@宽x高"」），
    一旦前面的行被合并进来、引号数变成奇数，字符串规则就会把注释末尾的新行
    误判成收尾引号（实测就是这么错的）。
    """
    in_str = False
    i = 0
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "#":
            return True
        i += 1
    return False


## 中文括号对：它们几乎只出现在注释与字符串里，且总是成对，配对信息比 n-gram 更可靠。
CJK_PAIRS = {"（": "）", "「": "」", "《": "》", "【": "】"}
CJK_CLOSERS = set(CJK_PAIRS.values())


def bracket_bonus(line_before: str, ch: str) -> float:
    """洞所在字符若是「本行尚未闭合的中文括号」的右半边，给一个大加分。"""
    stack = []
    for c in line_before:
        if c in CJK_PAIRS:
            stack.append(CJK_PAIRS[c])
        elif c in CJK_CLOSERS and stack and stack[-1] == c:
            stack.pop()
    if stack:
        return 4.0 if ch == stack[-1] else (-2.0 if ch in CJK_CLOSERS else 0.0)
    return -2.0 if ch in CJK_CLOSERS else 0.0


def eaten_options(buf: bytes, offset: int, length: int):
    """该洞被吞掉的那个字节的候选集（按 GDScript 语法硬约束收窄）。

    残余错误几乎全在这几类上，都能用语法一票定死：
      * 停在字符串字面量里，且其后引号数为**偶数**（说明后面的引号自己成对）
        -> 本串只能由被吞的那个字节收尾，即 `"`；
      * 停在字符串里但后面引号数为奇数 -> 被吞的是串内内容，**不可能是 `"`，
        也不可能是裸新行**（GDScript 单行字符串不允许裸换行）；
      * 洞后面紧跟代码关键字 / 新注释行 -> 被吞的是新行（否则那段代码会被吞进注释）。
    """
    line_lo = buf.rfind(b"\n", 0, offset) + 1
    line_hi = buf.find(b"\n", offset)
    if line_hi < 0:
        line_hi = len(buf)
    before = buf[line_lo:offset].decode("utf-8", errors="replace")
    after = buf[offset + length:line_hi].decode("utf-8", errors="replace")
    if _quote_open(before) and not _in_comment(before):
        # 格式串占位符：`"解锁「?s」" % str(...)` 这种，被吞的只能是 `%`
        # （语料里 `「%` 极少见，n-gram 会误判成引号，必须用语法兜住）
        if re.match(r"^[sdifxXo]", after) and "%" in after:
            return ["%"]
        # 串必须在本行收尾，两条判据任一成立即可：
        #   a) 其后引号数为偶数（说明后面的引号自己成对，本串只能由被吞的那个收尾）；
        #   b) 其后紧跟 `,` `)` `]` `}`（分隔符，串不可能跨过去）。
        # 只用 a) 会被「后面还藏着别的洞、把引号吃掉了」骗过（实测就是这么错的），
        # 所以 b) 作为独立判据一起用。
        tail = after.lstrip()
        if (len(re.findall(r'(?<!\\)"', after)) % 2 == 0
                or (tail and tail[0] in ",)]}")):
            return ["\""]
        return [c for c in EATEN_CANDIDATES if c not in ('"', "\n")]
    if before.strip():
        if COMMENT_TRIGGER.match(after):
            return ["\n"]
        if len(CJK_RE.findall(after[:40])) <= 2 and CODE_TRIGGERS.match(after):
            return ["\n"]
    return EATEN_CANDIDATES


def parse_units(buf: bytes):
    """把字节流解析成 [(offset, length, line, kind, payload)]。

    kind='fixed'  payload=字符，length=该字符原始字节数；
    kind='hole'   payload=该洞已知的前缀字节，length=该字符原始字节数（末字节被 0x3F 顶掉）；
    kind='eaten'  payload=None，length=0 —— 紧跟每个洞，代表被 .NET 一起吞掉的那个 ASCII 字节。

    洞与 eaten 必须成对出现：每个 '?' 都吞了 2 个字节（汉字末字节 + 一个 ASCII 字节），
    所以还原时除了补回末字节，还要**插入**那个被吞的 ASCII 字节。
    """
    units = []
    line = 1
    i = 0
    n = len(buf)
    while i < n:
        need = char_length(buf[i])
        if need and i + need <= n:
            known = [buf[i]]
            hole = None
            broken = False
            for k in range(i + 1, i + need):
                c = buf[k]
                if 0x80 <= c <= 0xBF:
                    known.append(c)
                elif c == 0x3F and hole is None:
                    hole = k
                else:
                    broken = True
                    break
            if not broken:
                if hole is None:
                    ch = buf[i:i + need].decode("utf-8")
                    units.append((i, need, line, "fixed", ch))
                    if ch == "\n":
                        line += 1
                else:
                    units.append((i, need, line, "hole", bytes(known)))
                    units.append((i + need, 0, line, "eaten", None))
                i += need
                continue
        ch = chr(buf[i])
        units.append((i, 1, line, "fixed", ch))
        if ch == "\n":
            line += 1
        i += 1
    return units


class LM:
    """字符级 trigram 语言模型（带向 bigram / unigram 回退）。"""

    def __init__(self, corpus: "Corpus"):
        self.uni = {}
        self.bi = {}
        self.tri = {}
        total = 0
        for text in corpus.texts:
            clean = "".join(ch if ch not in BAD_CHARS else "\n" for ch in text)
            for ch in clean:
                self.uni[ch] = self.uni.get(ch, 0) + 1
                total += 1
            for i in range(len(clean) - 1):
                k = clean[i:i + 2]
                self.bi[k] = self.bi.get(k, 0) + 1
            for i in range(len(clean) - 2):
                k = clean[i:i + 3]
                self.tri[k] = self.tri.get(k, 0) + 1
        self.total = max(1, total)
        self.bi_total = {}
        for k, v in self.bi.items():
            self.bi_total[k[0]] = self.bi_total.get(k[0], 0) + v
        self.tri_total = {}
        for k, v in self.tri.items():
            self.tri_total[k[:2]] = self.tri_total.get(k[:2], 0) + v

    def logp(self, ch: str, p1: str, p2: str) -> float:
        import math
        p_uni = self.uni.get(ch, 0) / self.total
        p_bi = (self.bi.get(p1 + ch, 0) / self.bi_total[p1]) if p1 and self.bi_total.get(p1) else 0.0
        p_tri = (self.tri.get(p2 + p1 + ch, 0) / self.tri_total[p2 + p1]) \
            if (p1 and p2 and self.tri_total.get(p2 + p1)) else 0.0
        p = 0.55 * p_tri + 0.30 * p_bi + 0.15 * p_uni
        if p <= 0.0:
            p = 1e-9
        return math.log(p)


def repair(buf: bytes, corpus: "Corpus", extra_texts=(), decisions=None):
    """逐行 Viterbi 还原所有洞（连被吞掉的 ASCII 字节一起推断）。

    返回 (修复后的字节, 未解析的洞偏移列表)。
    """
    units = parse_units(buf)
    lm = LM(corpus)
    lines = {}
    for unit in units:
        lines.setdefault(unit[2], []).append(unit)
    picked = {}          # unit 下标 -> 选定的字符
    unsure = []
    for line, members in lines.items():
        if not any(kind == "hole" for _, _, _, kind, _ in members):
            continue
        slots = []
        slot_units = []
        bonuses = []
        prev_hole = None
        for unit in members:
            _, _, _, kind, payload = unit
            if kind == "hole":
                prev_hole = unit
                options = corpus.candidates(payload)
                if not options:
                    unsure.append(unit[0])
                    slots.append(("fixed", ["?"]))
                    slot_units.append(("skip", unit))
                    bonuses.append({})
                    continue
                slots.append(("hole", options))
                slot_units.append(("hole", unit))
                line_lo = buf.rfind(b"\n", 0, unit[0]) + 1
                line_before = buf[line_lo:unit[0]].decode("utf-8", errors="replace")
                bonuses.append({ch: bracket_bonus(line_before, ch) for ch in options})
            elif kind == "eaten":
                # eaten 一定紧跟它的洞：用洞的 offset/length 判断是否必须补新行
                opts = (eaten_options(buf, prev_hole[0], prev_hole[1])
                        if prev_hole is not None else EATEN_CANDIDATES)
                slots.append(("eaten", opts))
                slot_units.append(("eaten", unit))
                bonuses.append({})
            else:
                slots.append(("fixed", [payload]))
                slot_units.append(("fixed", unit))
                bonuses.append({})
        picks = _viterbi(slots, lm, bonuses)
        if picks is None:
            unsure.extend(u[0] for u in (s[1] for s in slot_units) if u[3] == "hole")
            continue
        for (tag, unit), pick in zip(slot_units, picks):
            if tag == "hole":
                picked[id(unit)] = pick
            elif tag == "eaten":
                picked[("eaten", unit[0])] = pick
    out = bytearray()
    if decisions is not None:
        decisions.clear()
    for unit in units:
        offset, length, line, kind, payload = unit
        if kind == "fixed":
            out += buf[offset:offset + length]
        elif kind == "hole":
            pick = picked.get(id(unit))
            if pick is None:
                out += buf[offset:offset + length]
                continue
            out += payload + pick.encode("utf-8")[-1:]
            if decisions is not None:
                decisions.append([line, offset, payload.hex(), pick, ""])
        else:
            pick = picked.get(("eaten", offset))
            if pick:
                out += pick.encode("utf-8")
            if decisions is not None and decisions:
                decisions[-1][4] = pick or ""
    return bytes(out), unsure


def _viterbi(slots, lm: LM, bonuses=None, beam: int = 128):
    """返回每个槽选定的字符（与 slots 一一对应）。"""
    if bonuses is None:
        bonuses = [{} for _ in slots]
    # 状态: (p2, p1) -> (score, backpointer)
    states = {("", ""): (0.0, None)}
    # 记录每步的状态集合，便于回溯
    steps = []
    for idx, (kind, options) in enumerate(slots):
        bonus = bonuses[idx]
        nxt = {}
        for (p2, p1), (score, _) in states.items():
            for ch in options:
                val = score + lm.logp(ch, p1, p2) + bonus.get(ch, 0.0)
                key = (p1, ch)
                if key not in nxt or val > nxt[key][0]:
                    nxt[key] = (val, (p2, p1))
        if not nxt:
            return None
        if len(nxt) > beam:
            nxt = dict(sorted(nxt.items(), key=lambda kv: -kv[1][0])[:beam])
        steps.append(nxt)
        states = nxt
    # 回溯
    best_key = max(states.items(), key=lambda kv: kv[1][0])[0]
    path = []
    key = best_key
    for i in range(len(steps) - 1, -1, -1):
        path.append(key)
        bp = steps[i][key][1]
        if bp is None:
            break
        key = bp
    path.reverse()
    return [key[1] for key in path]


# ---------------------------------------------------------------- 入口


def selfcheck(path: str, label: str, include_self: bool) -> None:
    """在「模拟损坏 -> 恢复」上评估：每个洞要同时答对补的字节和被吞的字节。"""
    with open(path, "rb") as fh:
        original = fh.read()
    back = invert(corrupt(original))
    holes = scan_holes(back)
    paths = [p for p in project_corpus_paths()
             if os.path.abspath(p) != os.path.abspath(path)]
    if include_self:
        paths.append(path)
    corpus = Corpus(paths)
    fixed, unsure = repair(back, corpus)
    corpus.add_text(fixed.decode("utf-8", errors="replace"))
    fixed, unsure = repair(back, corpus)
    same_bytes = len(fixed) == len(original)
    diff = sum(1 for i in range(min(len(fixed), len(original))) if fixed[i] != original[i])
    print(f"[{label}] 洞 {len(holes)}  长度一致 {same_bytes} "
          f"({len(fixed)} vs {len(original)})  差异字节 {diff}  "
          f"逐字节准确率 {1 - diff / max(1, len(original)):.4%}")
    if diff:
        shown = 0
        for i in range(min(len(fixed), len(original))):
            if fixed[i] == original[i]:
                continue
            lo = max(0, i - 30)
            print(f"    off={i} 原文 …{original[lo:i].decode('utf-8', 'replace')[-20:]}"
                  f"【{original[i:i + 4].decode('utf-8', 'replace')[:2]}】"
                  f" 实为【{fixed[i:i + 4].decode('utf-8', 'replace')[:2]}】")
            shown += 1
            if shown >= 12:
                break


def selftest(path: str) -> int:
    selfcheck(path, "严格：语料不含该文件", False)
    selfcheck(path, "实际：语料含该文件自身", True)
    return 0


def fix_file(path: str, dst: str, verbose: bool = True, log=None) -> int:
    with open(path, "rb") as fh:
        buf = invert(fh.read())
    holes = scan_holes(buf)
    corpus = Corpus(project_corpus_paths())
    fixed, unsure = repair(buf, corpus)
    # 第二遍：第一遍的结果（含已补的洞）并入语料再解一次 —— 自身用词是最强的证据
    corpus.add_text(fixed.decode("utf-8", errors="replace"))
    fixed, unsure = repair(buf, corpus)
    with open(dst, "wb") as fh:
        fh.write(fixed)
    print(f"{os.path.basename(path)}: 洞 {len(holes)}，长 {len(buf)} -> {len(fixed)}"
          f"（多出 {len(fixed) - len(buf)} 字节 = 补回被吞的 ASCII），待定 {len(unsure)}")
    if log is not None:
        units = parse_units(buf)
        for i, unit in enumerate(units):
            if unit[3] != "hole":
                continue
            offset, length, line, _, prefix = unit
            eaten_unit = units[i + 1] if i + 1 < len(units) else None
            ctx = buf[max(0, offset - 30):offset].decode("utf-8", "replace")
            tail = buf[offset + length:offset + length + 14].decode("utf-8", "replace")
            log.write(f"{os.path.basename(path)}\tL{line}\toff={offset}\t"
                      f"prefix={prefix.hex()}\t…{ctx}【?】{tail}\n")
    return len(unsure)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "selftest":
        return selftest(sys.argv[2])
    if cmd == "invert":
        with open(sys.argv[2], "rb") as fh:
            raw = fh.read()
        with open(sys.argv[3], "wb") as fh:
            fh.write(invert(raw))
        print(f"{sys.argv[3]} 洞 {len(scan_holes(invert(raw)))} 个")
        return 0
    if cmd == "flag":
        # 把所有「语料里几乎没有依据」的决策捞出来人工复核 —— 内容字错都藏在这里
        path = sys.argv[2]
        with open(path, "rb") as fh:
            buf = invert(fh.read())
        corpus = Corpus(project_corpus_paths())
        dec = []
        fixed, unsure = repair(buf, corpus, decisions=dec)
        corpus.add_text(fixed.decode("utf-8", errors="replace"))
        dec = []
        fixed, unsure = repair(buf, corpus, decisions=dec)
        lm = LM(corpus)
        mode = sys.argv[3] if len(sys.argv) > 3 else ""
        for line_no, offset, prefix, ch, eaten in dec:
            if mode == "digit" and eaten not in "0123456789":
                continue
            if mode == "string":
                line_lo = buf.rfind(b"\n", 0, offset) + 1
                before_probe = buf[line_lo:offset].decode("utf-8", errors="replace")
                if not _quote_open(before_probe) or _in_comment(before_probe):
                    continue
            options = corpus.candidates(bytes.fromhex(prefix))
            before = buf[:offset].decode("utf-8", errors="replace")
            line_hi = buf.find(b"\n", offset)
            if line_hi < 0:
                line_hi = len(buf)
            after = buf[offset + 3:line_hi].decode("utf-8", errors="replace")
            print(f"{os.path.basename(path)}:{line_no}\t{ch}{eaten}\t…{before[-24:]}"
                  f"【{ch}|{eaten}】{after[:34]}")
        return 0
    if cmd == "dump":
        path = sys.argv[2]
        with open(path, "rb") as fh:
            buf = invert(fh.read())
        corpus = Corpus(project_corpus_paths())
        dec = []
        fixed, unsure = repair(buf, corpus, decisions=dec)
        corpus.add_text(fixed.decode("utf-8", errors="replace"))
        dec = []
        fixed, unsure = repair(buf, corpus, decisions=dec)
        # 把每个洞的决策内联进文本，便于直接看上下文
        units = parse_units(buf)
        marks = []
        hole_seen = 0
        for unit in units:
            kind = unit[3]
            if kind == "fixed":
                marks.append(buf[unit[0]:unit[0] + unit[1]].decode("utf-8", errors="replace"))
            elif kind == "hole":
                ch = dec[hole_seen][3] if hole_seen < len(dec) else "?"
                eaten = dec[hole_seen][4] if hole_seen < len(dec) else ""
                show = {"\n": "\\n", "\t": "\\t", "\r": "\\r", " ": "␠"}.get(eaten, eaten)
                marks.append(f"⟦{ch}⟧⟪{show}⟫")
                hole_seen += 1
        marked = "".join(marks)
        for line_no, offset, prefix, ch, eaten in dec:
            show = {"\n": "\\n", "\t": "\\t", "\r": "\\r", " ": "␠"}.get(eaten, eaten)
            print(f"{os.path.basename(path)}:{line_no}\t⟦{ch}⟧⟪{show}⟫")
        print("---- 内联上下文 ----")
        print(marked.replace("\n", "\n"))
        return 0
    if cmd == "fix":
        return 0 if fix_file(sys.argv[2], sys.argv[3]) == 0 else 1
    if cmd == "fixall":
        outdir = sys.argv[2]
        os.makedirs(outdir, exist_ok=True)
        total = 0
        for src in sys.argv[3:]:
            total += fix_file(src, os.path.join(outdir, os.path.basename(src)), verbose=False)
        print(f"待定合计 {total}")
        return 0
    print(f"unknown cmd {cmd}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
