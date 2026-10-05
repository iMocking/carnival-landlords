class_name AudioSynth
extends RefCounted
## 程序化音频合成：所有音效 / 背景音乐都由代码算出 PCM，仓库里不放任何音频素材。
## 好处是零版权素材、零导入流程；代价是首次生成需要几十到几百毫秒（调用方按需惰性生成）。
##
## 采样率统一 22050Hz / 16bit 单声道 —— 对这类短音效与轻量 BGM 足够，内存占用也小。

const RATE := 22050

## 可用音效名
const SFX_NAMES := [
    "click", "select", "deal", "play", "pass", "warn",
    "bid", "bomb", "rocket", "win", "lose",
]

static func create(name: String) -> AudioStreamWAV:
    match name:
        "click":
            return _click()
        "select":
            return _select()
        "deal":
            return _deal()
        "play":
            return _play()
        "pass":
            return _pass()
        "warn":
            return _warn()
        "bid":
            return _bell()
        "bomb":
            return _bomb()
        "rocket":
            return _rocket()
        "win":
            return _arpeggio([523.25, 659.25, 783.99, 1046.50], 0.15, 7.0, 0.30)
        "lose":
            return _arpeggio([659.25, 523.25, 392.00], 0.20, 4.5, 0.26)
        _:
            return null

# ------------------------------------------------------------------ 工具

static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
    var bytes := PackedByteArray()
    bytes.resize(samples.size() * 2)
    for i in samples.size():
        bytes.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32000.0)))
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = RATE
    stream.stereo = false
    stream.data = bytes
    if loop:
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
        stream.loop_begin = 0
        stream.loop_end = samples.size()
    return stream

static func _buffer(seconds: float) -> PackedFloat32Array:
    var buf := PackedFloat32Array()
    buf.resize(maxi(1, int(RATE * seconds)))
    return buf

## 一阶低通，把白噪声揉成"木质 / 布料"质感（纸牌摩擦声的关键）
static func _low_pass(previous: float, input: float, k: float) -> float:
    return previous + (input - previous) * k

# ------------------------------------------------------------------ 音效

## 按钮 / 点击：极短的一下木质"嗒"
static func _click() -> AudioStreamWAV:
    var seconds := 0.075
    var buf := _buffer(seconds)
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var lp := 0.0
    for i in buf.size():
        var t := float(i) / RATE
        var env := exp(-t * 62.0)
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.45)
        var tone := sin(TAU * 1450.0 * t) * 0.45
        buf[i] = (lp * 0.6 + tone * 0.4) * env * 0.55
    return _wav(buf)

## 选牌：明亮的小叮，比 click 更"高"
static func _select() -> AudioStreamWAV:
    var seconds := 0.09
    var buf := _buffer(seconds)
    for i in buf.size():
        var t := float(i) / RATE
        var env := exp(-t * 52.0) * (1.0 - exp(-t * 900.0))
        buf[i] = (sin(TAU * 1760.0 * t) * 0.7 + sin(TAU * 2640.0 * t) * 0.25) * env * 0.42
    return _wav(buf)

## 发牌：四声连续的"唰"
static func _deal() -> AudioStreamWAV:
    var seconds := 0.62
    var buf := _buffer(seconds)
    var rng := RandomNumberGenerator.new()
    rng.seed = 11
    var starts := [0.0, 0.12, 0.24, 0.36]
    var lp := 0.0
    for i in buf.size():
        var t := float(i) / RATE
        var v := 0.0
        for st in starts:
            var lt := t - float(st)
            if lt < 0.0 or lt > 0.17:
                continue
            var env := sin(PI * (lt / 0.17))
            v += env * env
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.28)
        buf[i] = lp * v * 0.30
    return _wav(buf)

## 出牌：纸牌滑过绒布的一声"唰"
static func _play() -> AudioStreamWAV:
    var seconds := 0.24
    var buf := _buffer(seconds)
    var rng := RandomNumberGenerator.new()
    rng.seed = 23
    var lp := 0.0
    for i in buf.size():
        var t := float(i) / RATE
        var env := exp(-t * 15.0) * (1.0 - exp(-t * 260.0))
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.22)
        var air := sin(TAU * (760.0 - 2600.0 * t) * t) * 0.18
        buf[i] = (lp * 0.85 + air) * env * 0.42
    return _wav(buf)

## 不出：两下轻叩桌面
static func _pass() -> AudioStreamWAV:
    var seconds := 0.34
    var buf := _buffer(seconds)
    var rng := RandomNumberGenerator.new()
    rng.seed = 31
    var lp := 0.0
    for i in buf.size():
        var t := float(i) / RATE
        var v := 0.0
        for st in [0.0, 0.13]:
            var lt := t - float(st)
            if lt < 0.0 or lt > 0.16:
                continue
            v += exp(-lt * 26.0) * (1.0 - exp(-lt * 500.0))
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.10)
        buf[i] = (sin(TAU * 138.0 * t) * 0.55 + lp * 1.5) * v * 0.42
    return _wav(buf)

## 非法操作 / 不能出：两声低警示音
static func _warn() -> AudioStreamWAV:
    var seconds := 0.30
    var buf := _buffer(seconds)
    for i in buf.size():
        var t := float(i) / RATE
        var v := 0.0
        for st in [0.0, 0.15]:
            var lt := t - float(st)
            if lt < 0.0 or lt > 0.14:
                continue
            v += sin(TAU * 300.0 * lt) * exp(-lt * 18.0)
        buf[i] = v * 0.32
    return _wav(buf)

## 叫分：一声柔和的金铃
static func _bell() -> AudioStreamWAV:
    var seconds := 0.75
    var buf := _buffer(seconds)
    for i in buf.size():
        var t := float(i) / RATE
        var env := exp(-t * 3.4) * (1.0 - exp(-t * 320.0))
        buf[i] = (sin(TAU * 587.33 * t) * 0.6 + sin(TAU * 1174.66 * t) * 0.25
            + sin(TAU * 1761.0 * t) * 0.1) * env * 0.42
    return _wav(buf)

## 炸弹：低频轰鸣 + 噪声爆裂
static func _bomb() -> AudioStreamWAV:
    var seconds := 1.0
    var buf := _buffer(seconds)
    var rng := RandomNumberGenerator.new()
    rng.seed = 43
    var lp := 0.0
    for i in buf.size():
        var t := float(i) / RATE
        var env := exp(-t * 4.0) * (1.0 - exp(-t * 110.0))
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.10)
        var burst := rng.randf_range(-1.0, 1.0) * exp(-t * 9.0)
        var sub := sin(TAU * 52.0 * t) * exp(-t * 2.6)
        buf[i] = clampf((burst * 0.45 + lp * 2.2 + sub * 0.7) * env * 0.55, -1.0, 1.0)
    return _wav(buf)

## 王炸：升调呼啸 + 尾音爆炸
static func _rocket() -> AudioStreamWAV:
    var seconds := 1.35
    var buf := _buffer(seconds)
    var rng := RandomNumberGenerator.new()
    rng.seed = 57
    var phase := 0.0
    var lp := 0.0
    for i in buf.size():
        var t := float(i) / RATE
        var rise := clampf(t / 0.72, 0.0, 1.0)
        var freq := 190.0 + 1500.0 * rise * rise
        phase += TAU * freq / RATE
        var whistle_env := (1.0 - exp(-t * 26.0)) * (1.0 - rise) * 0.32
        var boom_env := 0.0
        if t > 0.72:
            boom_env = exp(-(t - 0.72) * 3.6)
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.12)
        var whistle := sin(phase) * whistle_env
        var boom := (lp * 2.4 + rng.randf_range(-1.0, 1.0) * 0.5) * boom_env * 0.5
        buf[i] = clampf((whistle + boom + sin(TAU * 48.0 * t) * boom_env * 0.6) * 0.8, -1.0, 1.0)
    return _wav(buf)

## 胜负小旋律：每个音一条"弹拨"包络
static func _arpeggio(notes: Array, step: float, decay: float, amp: float) -> AudioStreamWAV:
    var seconds := step * notes.size() + 0.7
    var buf := _buffer(seconds)
    for k in notes.size():
        var i0 := int(float(k) * step * RATE)
        var freq := float(notes[k])
        var count := int(0.9 * RATE)
        for j in count:
            var idx := i0 + j
            if idx >= buf.size():
                break
            var t := float(j) / RATE
            var env := exp(-t * decay) * (1.0 - exp(-t * 420.0))
            buf[idx] += (sin(TAU * freq * t) * 0.72 + sin(TAU * freq * 2.0 * t) * 0.2) * env * amp
    return _wav(buf)

# ------------------------------------------------------------------ 背景音乐

## 96BPM、4 小节、A 小调五声音阶的循环：低音 + 铺底和弦 + 弹拨旋律 + 反拍沙锤。
## 走"轻音乐/牌室"路线，音量压得比较低，长时间循环不吵。
static func music_loop() -> AudioStreamWAV:
    var bpm := 96.0
    var beat := 60.0 / bpm
    var bars := 4
    var beats_per_bar := 4
    var total := int(RATE * beat * beats_per_bar * bars)
    var buf := PackedFloat32Array()
    buf.resize(total)

    var chords := [
        {"root": 110.00, "notes": [220.00, 261.63, 329.63]},
        {"root": 87.31, "notes": [174.61, 220.00, 261.63]},
        {"root": 130.81, "notes": [261.63, 329.63, 392.00]},
        {"root": 98.00, "notes": [196.00, 246.94, 293.66]},
    ]
    var penta := [440.00, 523.25, 587.33, 659.25, 783.99]
    var melodies := [
        [[0.0, 0, 1.0], [1.0, 2, 1.0], [2.0, 1, 1.5], [3.5, 2, 0.5]],
        [[0.0, 3, 1.0], [1.0, 2, 1.0], [2.0, 0, 2.0]],
        [[0.0, 4, 1.0], [1.0, 3, 1.0], [2.0, 2, 1.0], [3.0, 1, 1.0]],
        [[0.0, 2, 1.5], [1.5, 1, 0.5], [2.0, 0, 2.0]],
    ]

    for bar in bars:
        var chord: Dictionary = chords[bar % chords.size()]
        var bar_start := float(bar) * beats_per_bar * beat
        _add_note(buf, bar_start, beat * 1.5, float(chord["root"]), 0.26, "bass")
        _add_note(buf, bar_start + beat * 2.0, beat * 1.5, float(chord["root"]), 0.22, "bass")
        for note in chord["notes"]:
            _add_note(buf, bar_start, beats_per_bar * beat * 0.96, float(note), 0.055, "pad")
        for step in melodies[bar % melodies.size()]:
            var at := float(step[0])
            var semitone: int = step[1]
            var length := float(step[2])
            _add_note(buf, bar_start + at * beat, length * beat, float(penta[semitone]), 0.14, "pluck")
        for b in beats_per_bar:
            _add_shaker(buf, bar_start + float(b) * beat + beat * 0.5, 0.045, 0.05)

    # 归一化到 -6dB 左右，并在首尾各做 30ms 淡入淡出，避免循环接缝"啪"一声
    var peak := 0.0001
    for v in buf:
        peak = maxf(peak, absf(v))
    var gain := 0.5 / peak
    var fade := int(RATE * 0.03)
    for i in buf.size():
        var v := buf[i] * gain
        if i < fade:
            v *= float(i) / float(fade)
        elif i > buf.size() - fade:
            v *= float(buf.size() - i) / float(fade)
        buf[i] = v
    return _wav(buf, true)

static func _add_note(buf: PackedFloat32Array, start: float, duration: float, freq: float, amp: float, kind: String) -> void:
    var i0 := int(start * RATE)
    var count := int(duration * RATE)
    var size := buf.size()
    for j in count:
        var idx := i0 + j
        if idx < 0 or idx >= size:
            continue
        var t := float(j) / RATE
        var env := 1.0
        var wave := sin(TAU * freq * t)
        match kind:
            "bass":
                env = minf(t * 26.0, 1.0) * exp(-t * 1.6)
                wave = wave * 0.9 + sin(TAU * freq * 2.0 * t) * 0.12
            "pad":
                var tail := clampf((duration - t) / 0.35, 0.0, 1.0)
                env = minf(t * 3.2, 1.0) * tail * 0.9
                wave = wave * 0.62 + sin(TAU * freq * 2.0 * t) * 0.24 + sin(TAU * freq * 3.0 * t) * 0.09
            _:
                env = exp(-t * 6.2) * (1.0 - exp(-t * 300.0))
                wave = wave * 0.76 + sin(TAU * freq * 2.0 * t) * 0.18
        buf[idx] += wave * env * amp

static func _add_shaker(buf: PackedFloat32Array, start: float, duration: float, amp: float) -> void:
    var i0 := int(start * RATE)
    var count := int(duration * RATE)
    var size := buf.size()
    var rng := RandomNumberGenerator.new()
    rng.seed = 1000 + i0
    var lp := 0.0
    for j in count:
        var idx := i0 + j
        if idx < 0 or idx >= size:
            continue
        var t := float(j) / RATE
        var env := exp(-t * 90.0)
        lp = _low_pass(lp, rng.randf_range(-1.0, 1.0), 0.6)
        buf[idx] += (rng.randf_range(-1.0, 1.0) - lp) * env * amp