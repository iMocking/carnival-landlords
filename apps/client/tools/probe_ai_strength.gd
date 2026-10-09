extends SceneTree
## 临时探针：**角色受控**地比较两档强度（用完即删）。
##
## 座位 0 的身份每局随机，60 局的胜负噪声比档位差异还大（实测同一配置两次能差 10 个点），
## 所以这里固定角色：A 当地主、两农民用 B 打 N 局，再反过来打 N 局，
## 比较**地主胜率** —— 地主优势是同一份，差值就归给档位差异。
##   godot --headless --path . --script res://tools/probe_ai_strength.gd

const GAMES := 200
const PAIRS := [
    [0, 1],   # 简单 vs 困难
    [1, 2],   # 困难 vs 高级
    [2, 3],   # 高级 vs 地狱
    [0, 2],   # 简单 vs 高级
    [1, 3],   # 困难 vs 地狱
]

func _initialize() -> void:
    for pair in PAIRS:
        var a := int(pair[0])
        var b := int(pair[1])
        var rate_a := _landlord_win_rate(a, b)
        var rate_b := _landlord_win_rate(b, a)
        print("%s 当地主 %.0f%%  |  %s 当地主 %.0f%%  ->  %s" % [
            AiBrain.level_label(a), rate_a * 100.0,
            AiBrain.level_label(b), rate_b * 100.0,
            "前者更强" if rate_a > rate_b else ("后者更强" if rate_b > rate_a else "持平")])
    quit(0)

## 地主固定为 0 号位（叫分也统一：0 号叫 3、其余不叫），两农民用 `farmer_level`。
##
## 为什么必须固定：地主是**叫分**决定的，而各档叫分偏好不同——不固定的话，
## 比较的其实是"哪一档更爱叫地主"，不是牌力（第一版探针就栽在这里：
## 简单档叫分带随机抖动，结果它反而"更强"）。
func _landlord_win_rate(landlord_level: int, farmer_level: int) -> float:
    var landlord_wins := 0
    var settled := 0
    for i in GAMES:
        var engine := GameEngine.new()
        var box := {"summary": {}}
        engine.game_finished.connect(func(result: Dictionary) -> void: box["summary"] = result)
        engine.restart_requested.connect(func() -> void: engine.start_new_game())
        engine.start_new_game()
        var levels := [landlord_level, farmer_level, farmer_level]
        var guard := 0
        while engine.phase != GameEngine.Phase.SETTLE and guard < 4000:
            guard += 1
            if engine.phase == GameEngine.Phase.BIDDING:
                var bid_seat: int = engine.current_seat
                engine.submit_bid(bid_seat, 3 if bid_seat == 0 else 0)
            elif engine.phase == GameEngine.Phase.PLAYING:
                var seat: int = engine.current_seat
                var move := AiBrain.choose_play(engine, seat, levels[seat])
                var played := false
                if not move.is_empty():
                    played = engine.play_cards(seat, move)
                if not played and engine.phase == GameEngine.Phase.PLAYING \
                        and engine.current_seat == seat:
                    if not engine.pass_turn(seat):
                        var hand: Array = engine.players[seat].hand
                        if hand.is_empty():
                            break
                        engine.play_cards(seat, [hand[hand.size() - 1]])
            else:
                break
        var summary: Dictionary = box["summary"]
        if summary.is_empty():
            continue
        settled += 1
        if bool(summary.get("landlord_won", false)):
            landlord_wins += 1
    return float(landlord_wins) / float(maxi(1, settled))
