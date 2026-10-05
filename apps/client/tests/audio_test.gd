extends SceneTree
## 音频系统测试：
##   1) 11 个音效 + 背景音乐都由代码合成，波形非静音、不削顶、长度合理；
##   2) 音乐是 10 秒可循环的 WAV；
##   3) 声音开关随存档持久化；
##   4) AudioDirector 在无头环境（无音频设备、无 TTS）下调用不报错。
##   godot --headless --path . --script res://tests/audio_test.gd

var _checks := 0
var _failures := 0

func _initialize() -> void:
    _test_sfx()
    _test_music()
    _test_settings()
    _test_director_safe()
    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("AUDIO PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _stats(stream: AudioStreamWAV) -> Dictionary:
    var bytes := stream.data
    var count := bytes.size() / 2
    var peak := 0.0
    var energy := 0.0
    for i in count:
        var v := float(bytes.decode_s16(i * 2)) / 32768.0
        peak = maxf(peak, absf(v))
        energy += v * v
    return {
        "peak": peak,
        "rms": sqrt(energy / maxf(1.0, float(count))),
        "seconds": float(count) / float(stream.mix_rate),
    }

func _test_sfx() -> void:
    _check(AudioSynth.SFX_NAMES.size() >= 10, "音效数量不少于 10 个")
    for name in AudioSynth.SFX_NAMES:
        var stream := AudioSynth.create(name)
        _check(stream != null, "音效可合成：%s" % name)
        if stream == null:
            continue
        var info := _stats(stream)
        _check(float(info["seconds"]) > 0.03 and float(info["seconds"]) < 2.0,
            "%s 时长合理（%.2fs）" % [name, float(info["seconds"])])
        _check(float(info["peak"]) > 0.05, "%s 不是静音（peak=%.2f）" % [name, float(info["peak"])])
        _check(float(info["peak"]) <= 1.0, "%s 不削顶（peak=%.2f）" % [name, float(info["peak"])])
        _check(float(info["rms"]) > 0.008, "%s 有足够能量（rms=%.3f）" % [name, float(info["rms"])])
    _check(AudioSynth.create("不存在的音效") == null, "未知音效返回 null")

func _test_music() -> void:
    var music := AudioSynth.music_loop()
    _check(music != null, "背景音乐可合成")
    if music == null:
        return
    var info := _stats(music)
    _check(float(info["seconds"]) >= 8.0, "BGM 至少 8 秒（%.1fs）" % float(info["seconds"]))
    _check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGM 设为循环播放")
    _check(music.loop_end == music.data.size() / 2, "循环覆盖整段")
    _check(float(info["rms"]) > 0.01, "BGM 有足够能量（rms=%.3f）" % float(info["rms"]))
    _check(float(info["peak"]) <= 1.0, "BGM 不削顶（peak=%.2f）" % float(info["peak"]))

func _test_settings() -> void:
    var profile := PlayerProfile.create("音频测试")
    _check(profile.music_enabled and profile.sfx_enabled and profile.tts_enabled, "声音开关默认全开")
    _check(profile.toggle_audio("music") == false, "toggle 音乐返回新值 false")
    _check(profile.toggle_audio("sfx") == false, "toggle 音效返回新值 false")
    _check(profile.toggle_audio("tts") == false, "toggle 播报返回新值 false")
    _check(profile.toggle_audio("tts") == true, "再切一次播报恢复 true")
    var reloaded := PlayerProfile.from_dict(profile.to_dict())
    _check(not reloaded.music_enabled and not reloaded.sfx_enabled and reloaded.tts_enabled, "声音开关可正确读档")
    _check(profile.to_dict().has("music_enabled"), "存档字典带 music_enabled")

func _test_director_safe() -> void:
    # 没有实例时静态调用必须是安全的空操作
    AudioDirector.play_click()
    AudioDirector.play("bomb")
    AudioDirector.announce("顺子")
    AudioDirector.set_music_enabled(false)
    _check(true, "无实例时静态音频接口不报错")

    var director := AudioDirector.new()
    root.add_child(director)
    AudioDirector.play("click")
    AudioDirector.announce("三带一")
    var snapshot := {"has_profile": true, "music_enabled": false, "sfx_enabled": false, "tts_enabled": false}
    director._apply_settings(snapshot)
    AudioDirector.play("win")
    _check(true, "有实例时播放接口不报错（无头下静默）")
    director.queue_free()