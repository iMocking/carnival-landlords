class_name AudioDirector
extends Node
## 音频总控（视图层服务）：真实斗地主 BGM / 音效 / 真人语音 + 程序化合成兜底 + TTS 播报。
##
## * 音源见 assets/audio/Sound/，逻辑名到文件的映射集中在 AudioLibrary；
##   文件缺失时自动回退到 AudioSynth 程序化合成，不会出现哑事件。
## * 出牌播报优先用原版真人语音（单张 / 对子 / 三张 / 顺子 / 飞机 / 炸弹等），
##   TTS 只作为兜底；个人中心的播报开关同时控制真人语音与 TTS。
## * 无头运行（CI / 自动化测试）整体静默，不会留下悬空 playback。
## * 全局通过静态方法访问，没有实例时静默跳过，调用方不用判空。

const SFX_VOICES := 8
const SFX_DB := -4.0
const MUSIC_DB := -9.0
const VOICE_DB := -1.0
const CLICK_GUARD_MSEC := 50

static var _instance: AudioDirector = null

static func play_click() -> void:
    if _instance != null:
        _instance._play_click()

static func play(sound: String, volume_db: float = 0.0) -> void:
    if _instance != null:
        _instance._play_named(sound, volume_db)

static func play_effect(relative: String, volume_db: float = 0.0) -> void:
    if _instance != null:
        _instance._play_effect(relative, volume_db)

static func play_pattern(seat: int, kind: int, main_rank: int, length: int = 1, label: String = "") -> void:
    if _instance != null:
        _instance._play_pattern(seat, kind, main_rank, length, label)

static func play_bid(seat: int, score: int) -> void:
    if _instance != null:
        _instance._play_bid(seat, score)

static func play_pass(seat: int) -> void:
    if _instance != null:
        _instance._play_pass(seat)

static func play_alarm(seat: int, count: int) -> void:
    if _instance != null:
        _instance._play_alarm(seat, count)

## TTS 播报（兜底；原版真人语音缺失时才会用到）
static func announce(text: String) -> void:
    if _instance != null:
        _instance.speak(text)

static func set_music_enabled(enabled: bool) -> void:
    if _instance != null:
        _instance._music_on = enabled
        _instance._sync_music()

## 系统设置 →「震动反馈」：在关键操作上给一次短震动。
##
## 只用 `Input.vibrate_handheld()`（Android / iOS 支持，桌面直接是空操作），
## 时长取 40~70ms —— 再长会显得笨重，再短在手机上几乎感觉不到。
## 由 `vibrate_enabled` 开关控制；无头运行静默。
static func vibrate(duration_ms: int = 45) -> void:
    if _instance == null:
        return
    if _instance._silent or not _instance._vibrate_on:
        return
    if OS.has_feature("headless"):
        return
    Input.vibrate_handheld(clampi(duration_ms, 20, 200))

## 设置面板打开时同步各开关（避免每处调用都去问 ViewModel）
static func apply_settings(snapshot: Dictionary) -> void:
    if _instance == null:
        return
    _instance._vibrate_on = bool(snapshot.get("vibrate_enabled", true))

## 背景音乐：lobby / game / alert / result_win / result_lose
static func set_music(track: String) -> void:
    if _instance != null:
        _instance.set_music_track(track, not track.begins_with("result"))

static func play_result(won: bool) -> void:
    if _instance != null:
        _instance.set_music_track("result_win" if won else "result_lose", false)

var _music: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _cursor := 0
var _music_on := true
var _sfx_on := true
var _tts_on := true
var _vibrate_on := true
var _voice_on := true
var _tts_voice := ""
var _tts_ready := false
var _music_started := false
var _music_track := ""
var _last_click_msec := 0
var _silent := false

func _ready() -> void:
    _instance = self
    _silent = DisplayServer.get_name() == "headless"
    _music = AudioStreamPlayer.new()
    _music.name = "Music"
    _music.volume_db = MUSIC_DB
    add_child(_music)
    for i in SFX_VOICES:
        var player := AudioStreamPlayer.new()
        player.name = "Sfx%d" % i
        player.volume_db = SFX_DB
        add_child(player)
        _players.append(player)
    _probe_tts()

func _exit_tree() -> void:
    # 退出前主动断掉流引用：否则 AudioStream 与 playback 会在引擎关音频服务后残留
    if _music != null:
        _music.stop()
        _music.stream = null
    for player in _players:
        player.stop()
        player.stream = null
    _cache.clear()
    if _tts_ready:
        DisplayServer.tts_stop()
    if _instance == self:
        _instance = null

func setup(app: AppViewModel) -> void:
    app.profile_changed.connect(_apply_settings)
    _apply_settings(app.profile_snapshot())
    call_deferred("_start_music")

# ------------------------------------------------------------------ 播放

func _play_click() -> void:
    var now := Time.get_ticks_msec()
    if now - _last_click_msec < CLICK_GUARD_MSEC:
        return
    _last_click_msec = now
    _play_named("click", -2.0)

func _play_named(sound: String, volume_db: float = 0.0) -> void:
    if sound == "win" or sound == "lose":
        set_music_track("result_win" if sound == "win" else "result_lose", false)
        return
    if sound == "deal":
        _play_deal(volume_db)
        return
    if _silent or not _sfx_on:
        return
    _play_stream(_stream(sound), volume_db)

## 原版发牌是两段：先 Special_Dispatch 派牌，0.35s 后 DealFold 落手
func _play_deal(volume_db: float = 0.0) -> void:
    if _silent or not _sfx_on:
        return
    _play_effect(AudioLibrary.sfx_rel("deal"), volume_db)
    if is_inside_tree():
        get_tree().create_timer(0.35).timeout.connect(func() -> void:
            _play_effect(AudioLibrary.sfx_rel("deal_fold"), volume_db - 1.0))

func _play_effect(relative: String, volume_db: float = 0.0) -> void:
    if _silent or not _sfx_on or relative.is_empty():
        return
    _play_stream(_load_audio(AudioLibrary.path(relative)), volume_db)

func _play_voice(relative: String, volume_db: float = 0.0) -> void:
    if _silent or not _voice_on or relative.is_empty():
        return
    _play_stream(_load_audio(AudioLibrary.path(relative)), VOICE_DB + volume_db)

func _play_pattern(seat: int, kind: int, main_rank: int, length: int = 1, label: String = "") -> void:
    if kind == CardPattern.Kind.INVALID:
        return
    var effect := AudioLibrary.pattern_effect_rel(kind)
    if effect != "":
        _play_effect(effect)
    if _silent or not _voice_on:
        return
    var voice := AudioLibrary.pattern_voice_rel(AudioLibrary.gender_of_seat(seat), kind, main_rank, length)
    if voice != "":
        _play_voice(voice)
    elif not label.is_empty():
        speak(label)  # 真人语音文件缺失时才用 TTS 兜底

func _play_bid(seat: int, score: int) -> void:
    if _silent or not _voice_on:
        return
    var voice := AudioLibrary.bid_voice_rel(AudioLibrary.gender_of_seat(seat), score)
    if voice != "":
        _play_voice(voice)

func _play_pass(seat: int) -> void:
    if _silent or not _voice_on:
        return
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var voice := AudioLibrary.pass_voice_rel(AudioLibrary.gender_of_seat(seat), rng.randi_range(1, 4))
    if voice != "":
        _play_voice(voice)

func _play_alarm(seat: int, count: int) -> void:
    if _silent or not _voice_on:
        return
    var voice := AudioLibrary.alarm_voice_rel(AudioLibrary.gender_of_seat(seat), count)
    if voice != "":
        _play_voice(voice, -1.0)
    var alert := AudioLibrary.sfx_rel("alert")
    if alert != "":
        _play_effect(alert, 0.0)

## TTS 播报：念牌型名，原版真人语音缺失时的兜底
func speak(text: String) -> void:
    var line := text.strip_edges()
    if line.is_empty():
        return
    if _silent or not _tts_on:
        return
    if _tts_ready:
        DisplayServer.tts_speak(line, _tts_voice, 92, 1.05, 1.10, 0, true)
    else:
        _play_named("bid", -2.0)

# ------------------------------------------------------------------ 音乐

func set_music_track(track: String, loop: bool = true) -> void:
    if _music == null:
        return
    if _silent:
        _music_track = track
        return
    if _music_track == track and loop and _music.stream != null:
        _sync_music()
        return
    _music_track = track
    var rel := AudioLibrary.music_rel(track)
    var stream: AudioStream = null
    if rel != "":
        stream = _load_audio(AudioLibrary.path(rel))
    if stream is AudioStreamMP3:
        (stream as AudioStreamMP3).loop = loop
    if stream == null and (track == "lobby" or track == "game" or track == "alert"):
        stream = AudioSynth.music_loop()
    _music.stream = stream
    _music.volume_db = MUSIC_DB
    _sync_music()

func stop_music() -> void:
    if _music != null:
        _music.stop()

func music_track() -> String:
    return _music_track

func _start_music() -> void:
    if _music_started:
        return
    _music_started = true
    if _silent:
        return
    if _music_track.is_empty():
        set_music_track("lobby")
    else:
        _sync_music()

func _sync_music() -> void:
    if _music == null:
        return
    if _music.stream == null:
        _music.stop()
        return
    if not _music_on or not _music_started or _silent:
        _music.stop()
        return
    if not _music.playing:
        _music.play()

# ------------------------------------------------------------------ 内部

func _stream(sound: String) -> AudioStream:
    if _cache.has(sound):
        return _cache[sound]
    var stream: AudioStream = null
    var rel := AudioLibrary.sfx_rel(sound)
    if rel != "":
        stream = _load_audio(AudioLibrary.path(rel))
    if stream == null:
        stream = AudioSynth.create(sound)
    _cache[sound] = stream
    return stream

func _load_audio(path: String) -> AudioStream:
    if path.is_empty() or not ResourceLoader.exists(path):
        return null
    return load(path) as AudioStream

func _play_stream(stream: AudioStream, volume_db: float) -> void:
    if _silent or stream == null:
        return
    var player := _next_player()
    if player == null:
        return
    player.stream = stream
    player.volume_db = SFX_DB + volume_db
    player.play()

func _next_player() -> AudioStreamPlayer:
    if _players.is_empty():
        return null
    for player in _players:
        if not player.playing:
            return player
    _cursor = (_cursor + 1) % _players.size()
    return _players[_cursor]

func _probe_tts() -> void:
    if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
        return
    var fallback := ""
    for voice in DisplayServer.tts_get_voices():
        var entry: Dictionary = voice
        var id := str(entry.get("id", ""))
        if str(entry.get("language", "")).begins_with("zh"):
            _tts_voice = id
            _tts_ready = true
            return
        if fallback.is_empty():
            fallback = id
    if not fallback.is_empty():
        _tts_voice = fallback
        _tts_ready = true

func _apply_settings(snapshot: Dictionary) -> void:
    if snapshot.is_empty() or not bool(snapshot.get("has_profile", false)):
        return
    _music_on = bool(snapshot.get("music_enabled", true))
    _sfx_on = bool(snapshot.get("sfx_enabled", true))
    _tts_on = bool(snapshot.get("tts_enabled", true))
    _vibrate_on = bool(snapshot.get("vibrate_enabled", true))
    _voice_on = _tts_on
    if not _tts_on and _tts_ready:
        DisplayServer.tts_stop()
    _sync_music()
