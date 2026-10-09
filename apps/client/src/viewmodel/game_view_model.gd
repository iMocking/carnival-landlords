class_name GameViewModel
extends RefCounted
## MVVM 的 ViewModel 层（对局牌的**呈现**方）。
##
## C0 之后的职责划分（开发计划 D-16）：
##   * 本类负责**节奏与呈现**：AI 思考延迟、准备等待、音频播报信号、
##     把权威状态折成视图字典；
##   * **裁决**（谁能行动、这一手能不能出、AI 出什么、结算怎么算）在
##     `GameSessionContract` 之后 —— 离线是 `OfflineGameSession`（本地权威），
##     联机将换成由 WS 事件驱动的实现。
##
## 这样划分的目的是：**联机对局只替换裁决那一半**，界面与节奏一行都不用改。
## 视图层不持有任何模型对象。

signal hand_changed(cards: Array)
signal seats_changed(seats: Array)
signal table_changed(table: Dictionary)
signal phase_changed(data: Dictionary)
signal status_changed(text: String)
signal result_changed(summary: Dictionary)
signal toast(text: String)
## 结算面板点「准备」后进入等待态；新一局开始时再回到 false
signal ready_state_changed(waiting: bool)

## 新一局**先发牌、再叫分**：这个信号是发牌环节的起点，载荷里带齐视图需要的一切
## （发几张、什么节奏、我的牌长什么样），视图不需要再问第二个接口。
##
## 发牌时长由本类给出（见 `_deal_plan()`），视图照它排动画、本类照它排"发牌结束"，
## 于是"牌还在空中"与"叫分面板已经弹出来"这两件事不可能同时发生。
signal deal_started(plan: Dictionary)

## 音频播报事件：叫分 / 不出 / 报警（手牌剩 1~2 张）；View 层 AudioDirector 负责播放
signal bid_announced(seat: int, score: int)
signal pass_announced(seat: int)
signal alarm_announced(seat: int, count: int)

## 人类玩家座位号。
## 数值必须与 `GameSessionContract.HUMAN_SEAT` 一致 ——
## 两处刻意各留一份常量而不是互相引用：GDScript 的 `const` 不能引用其它类的常量
## （会报"不是常量表达式"），而让服务层反过来读 ViewModel 又是分层倒挂。
## 一致性由 `game_session_test` 断言守住。
const HUMAN_SEAT := 0
const AI_DELAY := 0.85
## 「准备」后模拟其他玩家准备的等待时长
const READY_DELAY := 1.1

# ---------------------------------------------------------------- 发牌环节
#
# 一局开始不再是"啪一下三家都有牌了"，而是先亮一段发牌动画，动画走完才开放叫分。
# 这段节奏放在 ViewModel（呈现层）而不是引擎里，理由是**引擎不该知道屏幕上有几帧**：
#   * 引擎的 `start_new_game()` 仍然是一次性把牌发完（裁决），
#     所以 `rules_smoke_test` / `mode_flow_test` 这些直接驱动引擎的测试不受影响；
#   * 本类在发牌期间把引擎信号**按住不发**（`_dealing`），屏幕上就只有牌在飞；
#   * 时长到了再把叫分界面整体推上来。
#
# 下面的两个常量是这段节奏的**唯一**来源：`_deal_plan()` 把它们连同总时长一起交给视图。
# 唯一能盖过它们的是**发牌音效的时长**（见 `deal_min_seconds`）——
# 牌发完了音效还在响，观感上就是音效被硬生生掐断。

## 单张牌从牌堆飞到座位的时长（秒）
const DEAL_CARD_FLIGHT := 0.26
## 相邻两张牌的发牌间隔（秒）
const DEAL_CARD_STAGGER := 0.03
## 最后一张落地后再留一点余量才开放叫分：动画的最后一帧与真手牌因此是"压着"交接的，
## 不会出现"牌还没停稳，叫分面板已经盖上来"。
const DEAL_TAIL := 0.12

# ---------------------------------------------------------------- 玩法与计分
# 实现在服务层（`OfflineGameSession`），这里只做转发以保持既有调用点（含单测）不变。

## 一局结束后各座位的金币增减（地主 ±2×底注×倍数，农民各 ∓1×，三家之和恒为 0）
static func seat_deltas(landlord_seat: int, landlord_won: bool, multiplier: int,
        seat_count: int, stake: int) -> Dictionary:
    return OfflineGameSession.seat_deltas(landlord_seat, landlord_won, multiplier, seat_count, stake)

## 按累计分排名：返回「下标 = 座位，值 = 名次（1 起）」
static func rank_seats(scores: Array) -> Array:
    return OfflineGameSession.rank_seats(scores)

var engine: GameEngine
## 对局服务：**权威状态与规则裁决**的唯一入口
var session: GameSessionContract
var mode: Dictionary = GameMode.default_mode()
var tournament_scores: Array = []
var tournament_round: int = 0
var human_name: String = "我"
## 系统设置下发的对局偏好（由 `MainView` 在开局前写入）
## * `card_speed_scale`：AI 思考时长系数（牌速调节）
## * `hint_level`：提示强度档位（0 基础 / 1 标准 / 2 智能）
## * `ai_level`：机器人强度档位（`AiBrain.Level`：简单 / 困难 / 高级 / 地狱）
## * `auto_hint`：快捷提示 —— 轮到我先手时自动给一次提示
## * `auto_sort_hand`：出牌后自动把剩余手牌按点数排好（直接透传给引擎）
var card_speed_scale: float = 1.0
var hint_level: int = 1
## -1 表示"还没从设置里灌过"：这一档的默认值与合法性由对局服务（裁决侧）自己兜。
## ViewModel 刻意不引用 `AiBrain` —— 档位校验属于裁决侧的事，
## 越界那就是边界又漏回来了（`game_session_test` 有结构断言守着）。
var ai_level: int = -1
var auto_hint: bool = false
var auto_sort_hand: bool = false
## 发牌动画的**时长下限**（秒），由视图在开局前灌入（见 `MainView._bind_scene()`）。
##
## 为什么是"下限"而不是直接定长：发牌音效有多长，牌就该飞多久，
## 而"音效多长"属于音频层 —— 这里不去翻音频资源，只接受一个秒数。
## 0 表示不作要求（无头测试 / 音频缺失），退回 `DEAL_*` 常量算出的默认节奏。
var deal_min_seconds: float = 0.0

var _selected: Array = []
var _hints: Array = []
var _hint_index: int = -1
var _seat_plays: Dictionary = {}
var _seat_badges: Dictionary = {}
var _ai_serial: int = 0
var _restart_serial: int = 0
var _disposed: bool = false
var _ready_pending: bool = false
## 打开「退出对局」确认弹窗时暂停对局：AI 不再行动，玩家也点不动牌
var _paused: bool = false
## 发牌动画进行中：引擎信号被按住，AI 与玩家都还没轮到
var _dealing: bool = false
## 发牌计时器的代际号：重开一局 / 退出页面会让上一局的计时器作废
var _deal_serial: int = 0
## 视图用来识别「新的一手牌 / 新的一局」：只靠 last_play 无法区分连续两手相同的牌
var _play_seq: int = 0
var _round_seq: int = 0
## 电脑玩家的"金币"展示值（座位 -> 数额）。纯展示：概念设计图的对手信息条上有金币，
## 而本机 AI 没有真实钱包。按座位从名字散列推出来，同一局内稳定，不会每帧跳动。
var _seat_gold: Dictionary = {}

func _init() -> void:
    # 默认用离线对局服务；联机实现落地后由外部注入替换
    session = OfflineGameSession.new()
    engine = session.engine()
    engine.hand_changed.connect(_on_hand_changed)
    engine.bid_turn.connect(_on_bid_turn)
    engine.bid_made.connect(_on_bid_made)
    engine.landlord_decided.connect(_on_landlord_decided)
    engine.turn_started.connect(_on_turn_started)
    engine.cards_played.connect(_on_cards_played)
    engine.turn_passed.connect(_on_turn_passed)
    engine.table_cleared.connect(_on_table_cleared)
    engine.game_finished.connect(_on_game_finished)
    engine.restart_requested.connect(_on_restart_requested)
    engine.action_rejected.connect(_on_action_rejected)

## 注入对局服务（联机实现落地后使用）。会重新绑定状态对象的信号。
func install_session(next_session: GameSessionContract) -> void:
    if next_session == null or next_session.engine() == null:
        return
    _disposed = true          # 让旧实现排队中的定时器全部失效
    _ai_serial += 1
    _restart_serial += 1
    _deal_serial += 1
    _dealing = false
    session = next_session
    engine = session.engine()
    engine.hand_changed.connect(_on_hand_changed)
    engine.bid_turn.connect(_on_bid_turn)
    engine.bid_made.connect(_on_bid_made)
    engine.landlord_decided.connect(_on_landlord_decided)
    engine.turn_started.connect(_on_turn_started)
    engine.cards_played.connect(_on_cards_played)
    engine.turn_passed.connect(_on_turn_passed)
    engine.table_cleared.connect(_on_table_cleared)
    engine.game_finished.connect(_on_game_finished)
    engine.restart_requested.connect(_on_restart_requested)
    engine.action_rejected.connect(_on_action_rejected)
    _disposed = false

# ---------------------------------------------------------------- 视图意图接口

## 页面销毁时调用：让所有排队中的定时器失效，避免「退出对局后仍在后台跑 AI」。
func shutdown() -> void:
    _disposed = true
    _ready_pending = false
    _paused = false
    _dealing = false
    _ai_serial += 1
    _restart_serial += 1
    _deal_serial += 1

func start() -> void:
    _paused = false
    _round_seq += 1
    _play_seq = 0
    tournament_scores.clear()
    tournament_round = 0
    _begin_round()

func restart() -> void:
    _paused = false
    _round_seq += 1
    _play_seq = 0
    _reset_round_state()
    _begin_round()

## 开一局：**先发牌、再叫分**。
##
## 顺序上有个要点：`session.begin()` 是裁决（洗牌 + 发牌 + 定谁先叫），必须最先跑完，
## 否则视图既拿不到牌、也就没法把牌"发"到正确的位置上。但它的信号在这一帧里是**静默**的
## （`_dealing` 会挡掉手牌 / 座位 / 阶段的下发与 AI 计时器），于是屏幕上只有发牌动画。
## 时长一到，`_finish_dealing()` 再把叫分界面整体推上去。
func _begin_round() -> void:
    _dealing = true
    _emit_status()                       # 此时引擎还没开工，视图只有一句「发牌中…」
    session.begin(mode, human_name, auto_sort_hand)
    _emit_table()                        # 台面中央那三张牌就是刚抽出来的牌堆
    var plan := _deal_plan()             # 牌已发完，这里才读得到"我的牌"
    _schedule_deal_end(plan)
    deal_started.emit(plan)

## 发牌动画的规模与节奏。
##
## 它是这一段演出的**唯一**时间来源：本类照它排"发牌结束"的定时器，视图照它排每张牌的
## 飞行与间隔。两边各写一份常量迟早会漂移 —— 表现就是"牌还在空中，叫分面板已经弹出来"。
##
## 时长 = `max(DEAL_* 算出的默认节奏, deal_min_seconds)`。后者是发牌音效的长度
## （实测 `Special_Dispatch` 有 3.87s，而默认节奏只有 1.88s —— 牌发完了音效还在响）。
## 补足差额时**只拉长逐张间隔**，单张飞行时长不动：牌速观感不变，只是发牌节奏变疏，
## 反而更像真人一张张派牌。「牌速」档位不参与这里 —— 它是 AI 思考时长的档位，
## 而发牌的节奏该由发牌音效决定。
func _deal_plan() -> Dictionary:
    var per_seat := GameEngine.HAND_SIZE
    var seats := GameEngine.SEAT_COUNT
    var span := maxf(float(per_seat * seats - 1), 1.0)
    var flight := DEAL_CARD_FLIGHT
    var tail := DEAL_TAIL
    var stagger := DEAL_CARD_STAGGER
    var duration := flight + stagger * span + tail
    var floor_seconds := maxf(deal_min_seconds, 0.0)
    if floor_seconds > duration:
        stagger = maxf(0.001, (floor_seconds - flight - tail) / span)
        duration = flight + stagger * span + tail
    return {
        "round_seq": _round_seq,
        "per_seat": per_seat,
        "seat_count": seats,
        "human_cards": _human_card_dicts(),
        "flight": flight,
        "stagger": stagger,
        "duration": duration,
    }

## 排队"发牌结束"。用独立代际号而不是复用 `_ai_serial`：发牌结束要放的
## 是叫分界面与 AI 叫分计时器，和 AI 思考的排队是两件事，混用会互相取消。
func _schedule_deal_end(plan: Dictionary) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        _finish_dealing()
        return
    _deal_serial += 1
    var serial := _deal_serial
    var round_seq := int(plan.get("round_seq", _round_seq))
    tree.create_timer(maxf(float(plan.get("duration", 0.0)), 0.01)).timeout.connect(func() -> void:
        if _disposed or serial != _deal_serial or round_seq != _round_seq:
            return
        _finish_dealing())

## 发牌结束：把按住的状态一次性放开 —— 手牌、座位张数、叫分面板、AI 计时器同时上线。
func _finish_dealing() -> void:
    if not _dealing:
        return
    _dealing = false
    _emit_all()
    _maybe_schedule_ai()

## 发牌动画是否正在进行（视图用它决定要不要压住台面提示）。
func is_dealing() -> bool:
    return _dealing

## 系统设置：把对局偏好灌进来（牌桌开局前调用一次；对局中途改也会立刻生效）
func apply_preferences(settings: Dictionary) -> void:
    card_speed_scale = float(settings.get("card_speed_scale", 1.0))
    hint_level = int(settings.get("hint_level", 1))
    auto_hint = bool(settings.get("auto_hint", false))
    auto_sort_hand = bool(settings.get("auto_sort_hand", false))
    if engine != null:
        engine.auto_sort_hand = auto_sort_hand
    # 机器人强度只**转发**，不在这里校验：那是裁决侧的活（对局服务自己钳制档位）
    if settings.has("ai_level"):
        ai_level = int(settings["ai_level"])
        if session != null:
            session.set_ai_level(ai_level)

## 暂停 / 恢复对局（退出确认弹窗打开期间调用）。
## 恢复时重新排一次 AI 计时器，避免暂停瞬间正好把 AI 的回合吞掉。
func set_paused(paused: bool) -> void:
    if _paused == paused:
        return
    _paused = paused
    if not _paused:
        _maybe_schedule_ai()

func is_paused() -> bool:
    return _paused

## 结算面板「准备」：等一小会儿模拟其他玩家准备，然后开下一局（比赛场打满则开新一届）。
## 期间视图显示「等待其他玩家准备…」；离开大厅时 shutdown() 会让这个定时器失效，不会在后台偷偷开局。
func request_ready() -> void:
    if _ready_pending or engine.phase != GameEngine.Phase.SETTLE:
        return
    _ready_pending = true
    ready_state_changed.emit(true)
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        _ready_pending = false
        ready_state_changed.emit(false)
        return
    _ai_serial += 1
    var serial := _ai_serial
    tree.create_timer(READY_DELAY).timeout.connect(func() -> void:
        if _disposed or serial != _ai_serial:
            return
        _ready_pending = false
        ready_state_changed.emit(false)
        _start_next_round())

func _start_next_round() -> void:
    if GameMode.rounds_of(mode) > 1 and tournament_finished():
        start()
    else:
        restart()

## 当前玩法是否已经打完全部局数（比赛场用）
func tournament_finished() -> bool:
    return tournament_round >= GameMode.rounds_of(mode)

func toggle_card(card_id: String) -> void:
    set_card_selected(card_id, not _selected.has(card_id))

## 滑动连选：视图给出「这张牌应该是选中还是取消」，而不是 toggle，
## 这样同一次拖动里重复经过同一张牌也不会来回翻。
func set_card_selected(card_id: String, selected: bool) -> void:
    if not _can_human_act():
        return
    if selected == _selected.has(card_id):
        return
    if selected:
        _selected.append(card_id)
    else:
        _selected.erase(card_id)
    _hints.clear()
    _hint_index = -1
    _emit_hand()
    _emit_table()

func play_selected() -> void:
    if not _can_human_act():
        return
    if _selected.is_empty():
        toast.emit("请先选择要出的牌")
        return
    # 出牌是否被接受由对局服务裁决（牌型不合法 / 打不过上家都返回 false）
    if session.human_play(_selected):
        _selected.clear()
        _hints.clear()
        _hint_index = -1
    _emit_hand()
    _emit_table()

func request_pass() -> void:
    if not _can_human_pass():
        return
    if session.human_pass():
        _selected.clear()
        _hints.clear()
        _hint_index = -1

func request_hint() -> void:
    if not _can_human_act():
        return
    if _hints.is_empty():
        var hand: Array = engine.players[HUMAN_SEAT].hand
        _hints = session.hints_for(hand, engine.last_pattern, engine.wild_rank)
        _hint_index = -1
    if _hints.is_empty():
        _selected.clear()
        toast.emit("没有能出的牌")
        _emit_hand()
        _emit_table()
        return
    _hint_index = (_hint_index + 1) % _hints.size()
    # 「提示强度 = 智能」时优先能一把走完的组合；由服务决定，界面只负责选中
    var pattern := session.pick_hint(_hints, _hint_index, hand_of_human(), hint_level >= 2)
    if pattern == null:
        return
    _selected = pattern.card_ids()
    _emit_hand()
    _emit_table()

func hand_of_human() -> Array:
    if engine == null or engine.players.size() <= HUMAN_SEAT:
        return []
    return engine.players[HUMAN_SEAT].hand

func request_bid(score: int) -> void:
    # 发牌还没完就不该有人叫分：引擎此刻已经进 BIDDING（发牌是它一次性做完的），
    # 单看引擎状态拦不住"叫分抢在发牌动画前面"这件事，得由这里挡。
    if _paused or _dealing:
        return
    session.human_bid(score)

# ---------------------------------------------------------------- 模型 -> 视图

func _on_hand_changed(_seat: int) -> void:
    _emit_hand()

func _on_bid_turn(_seat: int) -> void:
    _emit_all()
    _maybe_schedule_ai()

func _on_bid_made(seat: int, score: int) -> void:
    _seat_badges[seat] = "不叫" if score <= 0 else "%d 分" % score
    _emit_seats()
    _emit_table()
    bid_announced.emit(seat, score)

func _on_landlord_decided(_seat: int) -> void:
    _seat_badges.clear()
    _emit_all()

func _on_turn_started(_seat: int, _must_beat: bool) -> void:
    _hints.clear()
    _hint_index = -1
    _selected.clear()
    _emit_all()
    _maybe_schedule_ai()
    # 「快捷提示」：轮到我**先手**时自动给一次提示，省去每次手动点「提示」。
    # 只在自己能自由出牌（不是跟牌）时触发，否则会替玩家做判断。
    if auto_hint and _seat == HUMAN_SEAT and not _must_beat and _can_human_act():
        request_hint()

func _on_cards_played(seat: int, cards: Array, _pattern: CardPattern) -> void:
    _play_seq += 1
    _seat_plays[seat] = CardPresenter.card_dicts(cards, [], engine.wild_rank)
    _seat_badges.erase(seat)
    _emit_table()
    var remaining: int = engine.players[seat].hand.size()
    if remaining == 1 or remaining == 2:
        alarm_announced.emit(seat, remaining)

func _on_turn_passed(seat: int) -> void:
    _seat_badges[seat] = "不出"
    _seat_plays.erase(seat)
    _emit_table()
    pass_announced.emit(seat)

func _on_table_cleared(_seat: int) -> void:
    _seat_plays.clear()
    _seat_badges.clear()
    _emit_table()
    _emit_seats()

func _on_game_finished(summary: Dictionary) -> void:
    _ai_serial += 1
    _record_round(summary)
    _emit_all()
    result_changed.emit(_enrich_result(summary))

## 比赛场：把本局三家的金币增减累加到积分榜，并推进局数。单局玩法直接跳过。
func _record_round(summary: Dictionary) -> void:
    if GameMode.rounds_of(mode) <= 1:
        return
    if tournament_scores.is_empty():
        tournament_scores.resize(GameEngine.SEAT_COUNT)
        tournament_scores.fill(0)
    var deltas := seat_deltas(
        int(summary.get("landlord_seat", -1)),
        bool(summary.get("landlord_won", false)),
        int(summary.get("multiplier", 1)),
        GameEngine.SEAT_COUNT,
        GameMode.stake_of(mode))
    for seat in deltas.keys():
        tournament_scores[seat] = int(tournament_scores[seat]) + int(deltas[seat])
    tournament_round += 1

## 把「对局结果」翻译成「本机玩家视角的结果」，视图与档案层都不需要再判断座位。
func _enrich_result(summary: Dictionary) -> Dictionary:
    var enriched := summary.duplicate()
    var stake := GameMode.stake_of(mode)
    var multiplier := maxi(int(summary.get("multiplier", 1)), 1)
    var landlord_seat := int(summary.get("landlord_seat", -1))
    var landlord_won := bool(summary.get("landlord_won", false))
    var my_is_landlord := landlord_seat == HUMAN_SEAT
    var my_won := landlord_won == my_is_landlord
    # 与 PlayerProfile.apply_result 完全同一套算式：地主 2 倍、农民 1 倍
    var unit := stake * multiplier
    enriched["my_is_landlord"] = my_is_landlord
    enriched["my_role"] = "地主" if my_is_landlord else "农民"
    enriched["my_won"] = my_won
    enriched["gold_delta"] = (unit * 2 if my_is_landlord else unit) * (1 if my_won else -1)
    enriched["stake"] = stake
    enriched["mode_id"] = GameMode.id_of(mode)
    enriched["mode_name"] = str(mode.get("name", ""))
    var opponents := []
    for player in engine.players:
        if player.seat != HUMAN_SEAT:
            opponents.append(player.name)
    enriched["opponents"] = opponents

    var rounds := GameMode.rounds_of(mode)
    if rounds > 1:
        var finished := tournament_finished()
        var ranks := rank_seats(tournament_scores)
        var my_rank: int = int(ranks[HUMAN_SEAT]) if HUMAN_SEAT < ranks.size() else 1
        enriched["tournament"] = {
            "round": tournament_round,
            "rounds": rounds,
            "finished": finished,
            "scores": tournament_scores.duplicate(),
            "my_rank": my_rank,
            "entry_fee": int(mode.get("entry_fee", 0)),
            "reward_diamonds": GameMode.prize_for(mode, my_rank) if finished else 0,
        }
    return enriched

func _on_action_rejected(seat: int, reason: String) -> void:
    if seat == HUMAN_SEAT:
        toast.emit(reason)

func _on_restart_requested() -> void:
    _ai_serial += 1
    toast.emit("三家都不叫，重新发牌")
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    _restart_serial += 1
    var serial := _restart_serial
    tree.create_timer(1.2).timeout.connect(func() -> void:
        if _disposed or serial != _restart_serial:
            return
        _reset_round_state()
        # 重新发牌走与 start / restart 完全相同的一条路径：同样有发牌动画，同样最后才叫分
        _begin_round())

# ---------------------------------------------------------------- 电脑玩家

func _maybe_schedule_ai() -> void:
    if _paused:
        return
    # 发牌期间不许 AI 抢跑：引擎已经进了 BIDDING，不挡的话电脑会在牌还在飞的时候就叫分
    if _dealing:
        return
    if engine.phase == GameEngine.Phase.BIDDING and engine.current_seat != HUMAN_SEAT:
        _schedule_ai(_ai_bid)
    elif engine.phase == GameEngine.Phase.PLAYING and engine.current_seat != HUMAN_SEAT:
        _schedule_ai(_ai_play)

func _schedule_ai(action: Callable) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    _ai_serial += 1
    var serial := _ai_serial
    # 「牌速调节」：档位系数乘在 AI 思考时长上。这是**唯一的**速度来源，
    # 因此改档位能立刻影响出牌节奏，而不必在每个调用点各乘一次。
    var delay := maxf(0.05, AI_DELAY * card_speed_scale)
    tree.create_timer(delay).timeout.connect(func() -> void:
        if _disposed or serial != _ai_serial:
            return
        action.call())

func _ai_bid() -> void:
    if _paused:
        return
    if engine.phase != GameEngine.Phase.BIDDING:
        return
    var seat := engine.current_seat
    if seat == HUMAN_SEAT:
        return
    # 叫多少、以及提交，都由对局服务裁决
    session.ai_bid(seat)

func _ai_play() -> void:
    if _paused:
        return
    if engine.phase != GameEngine.Phase.PLAYING:
        return
    var seat := engine.current_seat
    if seat == HUMAN_SEAT:
        return
    # 出牌 / 不出 / 兜底打最小一张，整套裁决都在对局服务里
    var outcome := session.ai_take_turn(seat)
    if str(outcome.get("action", "none")) == "none":
        return

# ---------------------------------------------------------------- 快照发射

func _emit_all() -> void:
    _emit_hand()
    _emit_seats()
    _emit_table()
    _emit_phase()
    _emit_status()

func _emit_hand() -> void:
    # 发牌期间不发手牌：屏幕上该出现的是一张张飞过去的牌，而不是"凭空摆好的一手牌"
    if _dealing:
        return
    hand_changed.emit(_human_card_dicts())

## 我的手牌（含选中标记）的呈现数据。
##
## 发牌动画要"把我的牌按落位顺序发出去"，用的就是这一份 —— 与 `hand_changed` 完全同源，
## 所以牌飞到位之后换成真正的手牌时，牌面与位置都不会跳一下。
func _human_card_dicts() -> Array:
    if engine == null or engine.players.is_empty():
        return []
    var hand: Array = engine.players[HUMAN_SEAT].hand.duplicate()
    hand.sort_custom(func(a: Card, b: Card) -> bool:
        if a.rank != b.rank:
            return a.rank > b.rank
        return a.suit < b.suit)
    return CardPresenter.card_dicts(hand, _selected, engine.wild_rank)

func _emit_seats() -> void:
    # 两家的牌背与张数同样等发牌结束再上：发牌中途显示"剩 17 张"没有意义
    if _dealing:
        return
    var seats := []
    for player in engine.players:
        if player.is_ai and not _seat_gold.has(player.seat):
            _seat_gold[player.seat] = _fake_gold(player.name)
        var entry := {
            "seat": player.seat,
            "name": player.name,
            "hand_count": player.hand.size(),
            "is_landlord": player.role == PlayerState.Role.LANDLORD,
            "role_text": "地主" if player.role == PlayerState.Role.LANDLORD else "农民",
            "is_active": engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == player.seat,
            "is_bidding": engine.phase == GameEngine.Phase.BIDDING and engine.current_seat == player.seat,
            "badge": str(_seat_badges.get(player.seat, "")),
            "is_ai": player.is_ai,
        }
        if _seat_gold.has(player.seat):
            entry["gold"] = int(_seat_gold[player.seat])
        seats.append(entry)
    seats_changed.emit(seats)

## 电脑玩家的展示金币：从名字散列出 7 位数，四舍五入到百位，读起来像真实余额
static func _fake_gold(player_name: String) -> int:
    var seed := absi(player_name.hash())
    var base := 80000 + seed % 9400000
    return int(round(float(base) / 100.0)) * 100

func _emit_table() -> void:
    var plays := []
    for i in GameEngine.SEAT_COUNT:
        var entry := {
            "cards": _seat_plays.get(i, []),
            "badge": str(_seat_badges.get(i, "")),
        }
        plays.append(entry)
    var bottom: Array = []
    if engine.landlord_seat >= 0:
        bottom = CardPresenter.card_dicts(engine.bottom_cards, [], engine.wild_rank)
    else:
        bottom = CardPresenter.back_dicts(GameEngine.BOTTOM_SIZE, "bottom")
    var table := {
        "bottom_cards": bottom,
        "landlord_seat": engine.landlord_seat,
        "multiplier": engine.multiplier,
        "current_seat": engine.current_seat,
        "last_play_seat": engine.last_play_seat,
        "can_play": _can_human_act(),
        "can_pass": _can_human_pass(),
        "selected_count": _selected.size(),
        "phase": engine.phase,
        "plays": plays,
        # 玩法信息：牌桌标题与癞子提示都从这里取
        "mode_id": GameMode.id_of(mode),
        "mode_name": str(mode.get("name", "")),
        "stake": GameMode.stake_of(mode),
        "hot": GameMode.is_hot(mode),
        "wild_rank": engine.wild_rank,
        "wild_label": Card.rank_label(engine.wild_rank) if engine.wild_rank > 0 else "",
        # 音频播报用：第几手 / 第几局 / 这一手是什么牌型
        "play_seq": _play_seq,
        "round_seq": _round_seq,
        "last_pattern_label": engine.last_pattern.label() if engine.last_pattern != null else "",
        "last_pattern_kind": engine.last_pattern.kind if engine.last_pattern != null else CardPattern.Kind.INVALID,
        "last_pattern_rank": engine.last_pattern.main_rank if engine.last_pattern != null else 0,
        "last_pattern_length": engine.last_pattern.length if engine.last_pattern != null else 1,
        # 报警音乐判断：三家当前手牌数；0 表示已出完
        "hand_counts": _hand_counts(),
    }
    table_changed.emit(table)

func _hand_counts() -> Array:
    var out: Array = []
    for player in engine.players:
        out.append(player.hand.size())
    return out

func _emit_phase() -> void:
    # 发牌期间不亮叫分面板：引擎早在发牌时就进了 BIDDING，直接下发会让面板盖在动画上
    if _dealing:
        return
    phase_changed.emit({
        "phase": engine.phase,
        "bid_visible": engine.phase == GameEngine.Phase.BIDDING and engine.current_seat == HUMAN_SEAT,
        "bidding": engine.phase == GameEngine.Phase.BIDDING,
        "my_turn": _can_human_act(),
        "can_pass": _can_human_pass(),
        "landlord_seat": engine.landlord_seat,
        "settled": engine.phase == GameEngine.Phase.SETTLE,
    })

func _emit_status() -> void:
    var text := ""
    if _dealing:
        # 引擎此刻已是 BIDDING，按阶段渲染会写出"请选择叫分" —— 而玩家其实还在等发牌
        status_changed.emit("发牌中…")
        return
    match engine.phase:
        GameEngine.Phase.BIDDING:
            if engine.current_seat == HUMAN_SEAT:
                text = "请选择叫分"
            else:
                text = "等待 %s 叫分…" % _name_of(engine.current_seat)
        GameEngine.Phase.PLAYING:
            if engine.current_seat == HUMAN_SEAT:
                if _can_human_pass():
                    text = "轮到你出牌 · 需压过 %s" % _name_of(engine.last_play_seat)
                else:
                    text = "轮到你出牌 · 本轮由你领出"
            else:
                text = "等待 %s 出牌…" % _name_of(engine.current_seat)
        _:
            text = ""
    status_changed.emit(text)

# ---------------------------------------------------------------- 辅助

func _can_human_act() -> bool:
    if _paused:
        return false
    return engine.phase == GameEngine.Phase.PLAYING and engine.current_seat == HUMAN_SEAT

func _can_human_pass() -> bool:
    if not _can_human_act():
        return false
    if engine.last_pattern == null or not engine.last_pattern.is_valid():
        return false
    return engine.last_play_seat != HUMAN_SEAT

## 牌 id → 牌对象的还原已移到对局服务（`OfflineGameSession.cards_from_ids`）：
## "哪些牌属于我的手牌"是权威状态的一部分，不该由呈现层自己维护映射。

func _name_of(seat: int) -> String:
    if seat < 0 or seat >= engine.players.size():
        return "玩家"
    return engine.players[seat].name

func _reset_round_state() -> void:
    _ready_pending = false
    _selected.clear()
    _hints.clear()
    _hint_index = -1
    _seat_plays.clear()
    _seat_badges.clear()