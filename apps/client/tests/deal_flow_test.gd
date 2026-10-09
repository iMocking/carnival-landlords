extends SceneTree
## 发牌环节回归测试（"先发牌、再叫分" + 手牌不压头像）。
##   godot --headless --path . --script res://tests/deal_flow_test.gd
##
## 盯四件事：
##   1) **顺序**：进牌桌先发牌 —— 发牌期间不下发手牌、不亮叫分面板、叫分请求被拒绝；
##   2) **动画真的在跑**：`DealAnimator` 里有牌，而且用的是**牌池**（节点数远少于 51 张）；
##   3) **交接**：发牌结束后手牌 17 张、动画层清空、叫分恢复正常；
##   4) **版面**：满手牌（地主 20 张）时最左边的牌不得压住左下角"我的头像"，
##      而手牌行本身仍然贴着页面留白（`page_padding_test` 锁的就是后者，不能被这条改坏）。
##
## 为什么值得单独立一条：发牌是"引擎已经发完、屏幕还在演"的一段错位时间。
## 这段时间里引擎状态是 BIDDING，任何照着 `engine.phase` 写 UI 的代码都会提前把
## 叫分面板推上来 —— 而那正是这个测试要拦住的事。

const HUMAN_SEAT := 0
const MAX_WAIT_MS := 8000
## 地主的手牌：17 张底牌 + 3 张底牌，是版面最挤的情况
const WORST_HAND := GameEngine.HAND_SIZE + GameEngine.BOTTOM_SIZE

var _app: AppViewModel
var _page: MainView
var _checks := 0
var _failures := 0

func _initialize() -> void:
    _run()

func _run() -> void:
    _app = AppViewModel.new()
    _app.profile = PlayerProfile.create("发牌测试员")
    root.size = Vector2i(1280, 720)
    _page = load("res://src/view/main_view.tscn").instantiate()
    # 必须先 setup() 再 add_child()：add_child() 会立即触发 _ready()，而 _ready() 里就要读 app
    _page.setup(_app)
    root.add_child(_page)
    _page.size = Vector2(1280, 720)
    # `SceneTree._initialize()` 期间 `add_child()` 的节点要等到**第一帧**才跑 `_ready()`，
    # 而 ViewModel 与全部控件都是在 `_ready()` 里建的。先让过一帧再断言。
    await process_frame

    await _deal_stage()
    await _clearance_stage()
    _test_deal_floor()

    print("checks=%d failures=%d" % [_checks, _failures])
    if _failures == 0:
        print("DEAL FLOW PASS")
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _frames(n: int) -> void:
    for i in n:
        await process_frame

## 按脚本类名（`class_name`）找牌桌上的第一个控件
func _first_of_type(type_name: String) -> Control:
    var found := _page.find_children("*", type_name, true, false)
    if found.is_empty():
        return null
    return found[0] as Control

## 发牌动画层里每张临时牌的当前位置（按下标对齐，用来比较"有没有在动"）
func _pool_positions(animator: Control) -> Array:
    var out: Array = []
    for child in animator.get_children():
        out.append((child as Control).position)
    return out

# ---------------------------------------------------------------- 1. 发牌 -> 叫分

func _deal_stage() -> void:
    var vm := _page.view_model()
    _check(vm != null, "牌桌已经建好 ViewModel")
    if vm == null:
        return
    var engine := vm.engine
    var hand := _page.find_child("HandRow", true, false) as CardRow
    var status := _page.find_child("StatusLabel", true, false) as Label

    # 进牌桌的第一帧就已经在发牌了
    _check(vm.is_dealing(), "进牌桌的第一时间就处于发牌阶段")
    _check(hand != null and hand.get_child_count() == 0, "发牌期间手牌区还是空的（没有凭空摆好的牌）")
    _check(status != null and status.text.contains("发牌"), "发牌期间的状态文案是「发牌中…」")
    # `_bid_panel` 没有显式 name，按**脚本类名**找（`find_children` 认得 `class_name`），
    # 比依赖 Godot 给节点自动起的名字稳。
    var bid_panel := _first_of_type("BidPanel")
    _check(bid_panel != null and not bid_panel.visible, "发牌期间不亮叫分面板")

    # 把叫分权强行按到人类座位上：这样"叫分被拒绝"才只可能是发牌挡下来的，
    # 而不是"还没轮到人"。发牌期间 AI 计时器同样被挡着，所以这个座位不会被抢走。
    engine.current_seat = HUMAN_SEAT
    vm.request_bid(3)
    _check(engine.players[HUMAN_SEAT].bid < 0, "发牌期间叫分请求被拒绝（引擎没有记录这一手）")

    # 动画在下一帧（call_deferred）才起：此时牌池已建好且正在飞
    await _frames(3)
    var animator := _page.find_child("DealAnimator", true, false) as DealAnimator
    _check(animator != null, "牌桌含发牌动画层")
    if animator != null:
        _check(animator.is_running(), "发牌动画正在运行")
        _check(animator.get_child_count() == GameEngine.SEAT_COUNT * GameEngine.HAND_SIZE,
            "发牌动画为每张牌建了一个节点（%d）" % animator.get_child_count())
        # 但同一时刻在画的只有"正在飞"的那几张：其余节点 visible=false，不参与绘制。
        # 这条也顺带钉住了另一个坑 —— 曾经为了省节点做过"牌池 + 复用槽位"，
        # 结果槽位一复用就把已经落定的牌抢走再飞一次，自己的手牌根本累积不起来。
        var flying := animator.flying_count()
        _check(flying > 0 and flying <= 12,
            "同时在空中的牌只有个位数（%d 张，理论上限 ceil(flight/stagger)+1 = 10）" % flying)
        # 光有节点不算数：牌必须真的在逐帧移动。
        # （这一条抓到过真问题 —— `Callable.bind()` 的参数顺序会把 tween 的进度值挤到第一个参数上，
        #  结果是节点建得好好的、位置也摆了，但每帧都在报类型错误，牌一动不动。）
        var before := _pool_positions(animator)
        await _frames(10)
        var after := _pool_positions(animator)
        var moved := false
        for i in mini(before.size(), after.size()):
            if (before[i] as Vector2).distance_to(after[i] as Vector2) > 1.0:
                moved = true
                break
        _check(moved, "发牌动画真的在逐帧移动（不是把牌摆到起点就不管了）")

    # 等发牌走完（时长由 GameViewModel 给出，这里只等状态翻面）
    var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
    while vm.is_dealing() and Time.get_ticks_msec() < deadline:
        await process_frame
    _check(not vm.is_dealing(), "发牌在 %d ms 内结束" % MAX_WAIT_MS)

    _check(hand != null and hand.get_child_count() == GameEngine.HAND_SIZE,
        "发牌结束后手牌 %d 张（实际 %d）" % [GameEngine.HAND_SIZE, hand.get_child_count() if hand != null else -1])
    if animator != null:
        _check(not animator.is_running() and animator.get_child_count() == 0,
            "发牌结束后动画层已清空（牌与真手牌交接，不残留重复的牌）")
    _check(bid_panel != null and bid_panel.visible, "发牌结束后（轮到我）叫分面板亮起")

    vm.request_bid(2)
    _check(engine.players[HUMAN_SEAT].bid == 2, "发牌结束后叫分恢复正常（记到 2 分）")

# ---------------------------------------------------------------- 3. 时长下限

## 发牌动画必须铺满发牌音效：`Special_Dispatch` 实测 3.87s，而默认节奏只有 1.88s ——
## 不做这条下限，观感就是"牌早发完了，音效还在响、被硬生生掐断"。
##
## 这里直接量 `_deal_plan()` 的输出（纯逻辑，不需要场景），三种情形都钉住：
## 不设下限 = 默认节奏；设了下限 = 整段被拉长；**单张飞行时长不变**（只是节奏变疏）。
func _test_deal_floor() -> void:
    var vm := GameViewModel.new()
    var span := float(GameEngine.HAND_SIZE * GameEngine.SEAT_COUNT - 1)
    var natural := GameViewModel.DEAL_CARD_FLIGHT + GameViewModel.DEAL_CARD_STAGGER * span \
        + GameViewModel.DEAL_TAIL

    var plain: Dictionary = vm._deal_plan()
    _check(absf(float(plain["duration"]) - natural) < 0.001,
        "不设下限时用默认节奏（%.2fs）" % float(plain["duration"]))
    _check(absf(float(plain["flight"]) - GameViewModel.DEAL_CARD_FLIGHT) < 0.001,
        "默认单张飞行时长 = %.2fs" % GameViewModel.DEAL_CARD_FLIGHT)

    # 音效长度（取一个明显比默认节奏长的值）
    var sound := 3.87
    vm.deal_min_seconds = sound
    var stretched: Dictionary = vm._deal_plan()
    _check(float(stretched["duration"]) >= sound - 0.001,
        "设了下限后整段发牌 ≥ 音效时长（%.2fs ≥ %.2fs）" % [float(stretched["duration"]), sound])
    _check(float(stretched["stagger"]) > GameViewModel.DEAL_CARD_STAGGER,
        "补足时长靠拉长逐张间隔（%.3fs > %.3fs）"
            % [float(stretched["stagger"]), GameViewModel.DEAL_CARD_STAGGER])
    _check(absf(float(stretched["flight"]) - GameViewModel.DEAL_CARD_FLIGHT) < 0.001,
        "补足时长**不改**单张飞行时长（牌速观感不变）")

    # 下限比默认节奏短时不该无谓地缩短动画
    vm.deal_min_seconds = 0.5
    var short_floor: Dictionary = vm._deal_plan()
    _check(absf(float(short_floor["duration"]) - natural) < 0.001,
        "下限比默认节奏短时仍然用默认节奏（%.2fs）" % float(short_floor["duration"]))

    # 这条下限之所以存在，是因为真实音效确实比默认节奏长 —— 顺手把它钉住
    var path := "res://assets/audio/Sound/Special/Special_Dispatch.mp3"
    _check(ResourceLoader.exists(path), "发牌音效资源存在")
    var stream := load(path) as AudioStreamMP3
    _check(stream != null and stream.get_length() > natural,
        "发牌音效（%.2fs）比默认节奏（%.2fs）长 —— 所以需要这条下限"
            % [stream.get_length() if stream != null else 0.0, natural])

# ---------------------------------------------------------------- 2. 手牌与头像的版面

## 手牌带必须在**行内**再向中间收拢，让最左边的牌停在左下角"我的头像"右缘之外。
## 三种视口比例都验：宽屏 / 全面屏 / 平板 —— 头像与手牌都是按视口高算的，比例不同最容易翻车。
func _clearance_stage() -> void:
    var hand := _page.find_child("HandRow", true, false) as CardRow
    var avatar := _page.find_child("MyAvatar", true, false) as Control
    if hand == null or avatar == null:
        _check(false, "牌桌找不到 HandRow / MyAvatar")
        return
    for view in [Vector2i(1280, 720), Vector2i(1720, 720), Vector2i(1280, 960)]:
        root.size = view
        _page.size = Vector2(view)
        await _frames(8)
        var tag := "%dx%d" % [view.x, view.y]
        var side := AppPage.SIDE_PADDING
        # 行本身仍然贴着页面留白：这条约定被 page_padding_test 锁着，收拢只能在行内部发生
        _check(is_equal_approx(hand.position.x, side),
            "%s 手牌行左侧仍是页面留白（期望 %.0f，实际 %.0f）" % [tag, side, hand.position.x])
        _check(is_equal_approx(hand.position.x + hand.size.x, float(view.x) - side),
            "%s 手牌行右侧仍是页面留白" % tag)

        var card_w := hand.card_size.x
        var left_edge := hand.position.x + hand.slot_center(0, WORST_HAND).x - card_w * 0.5
        var right_edge := hand.position.x + hand.slot_center(WORST_HAND - 1, WORST_HAND).x + card_w * 0.5
        _check(left_edge >= avatar.position.x + avatar.size.x - 0.5,
            "%s 满手牌（%d 张）最左边的牌不压住头像（牌左缘 %.1f ≥ 头像右缘 %.1f）"
                % [tag, WORST_HAND, left_edge, avatar.position.x + avatar.size.x])
        # 只收左边会让整手牌看着往右偏，所以两侧收拢量必须一样（牌带居中）
        var left_gap := left_edge - hand.position.x
        var right_gap := (hand.position.x + hand.size.x) - right_edge
        _check(absf(left_gap - right_gap) <= 1.0,
            "%s 手牌带在行内居中（左净空 %.1f ≈ 右净空 %.1f）" % [tag, left_gap, right_gap])
