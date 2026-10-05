class_name LocalEchoTransport
extends RefCounted
## 离线欠账上报的**服务端替身**（测试 / 本地联调用）。
##
## 它按 REC-06 的服务端口径实现，用来在服务端落地之前就能端到端验证
## "离线游玩 → 队列 → 上报 → 清队"这条链路（开发计划 D-15 / REC-06）：
##   * **幂等**：同一个 `id` 重复上报不会重复加积分，但仍会回"已接收"，
##     这样客户端才敢把队列清掉（否则重试会永远清不干净）；
##   * **每日上限**：只发放上限内的积分，超出的部分客户端会以服务端权威值为准，
##     因此不会出现"客户端自己把超额部分记进去"的错账；
##   * **可注入失败**：`fail_next = true` 让下一次上报失败，用来验证"失败不清队"。

## 下一次上报是否失败（模拟断网）
var fail_next := false
## 每日积分上限（服务端权威）
var daily_cap := 1000
## 调用次数，用来断言"重试确实发生了"
var calls := 0
## 最近一次收到的批次（便于断言上报内容）
var last_batch: Array = []

var _seen := {}
var _points := 0
var _gold := 0
var _diamonds := 0
## 今天已经发放出去的离线积分（用于每日额度）
var _granted_today := 0

func _init(seed_points: int = 0, seed_gold: int = 0, seed_diamonds: int = 0) -> void:
    _points = seed_points
    _gold = seed_gold
    _diamonds = seed_diamonds

## 服务端当前的权威数值。
## 字段名用**单数 `diamond`**，与服务端所有钱包接口一致（见 OfflineService
## 的 `_apply_authoritative_snapshot` 注释）—— 替身若与真实现命名不同，
## 这条链路就会在切换实现的瞬间坏掉。
func snapshot() -> Dictionary:
    return {"points": _points, "gold": _gold, "diamond": _diamonds}

func server_points() -> int:
    return _points

func accepted_count() -> int:
    return _seen.size()

## 服务端侧 REC-06 的替身实现
##
## 口径（与 D-15 一致，两侧都要照这个来）：
##   * 一批记录先求**净积分**（`points_delta` 有正有负，输了就是负的）；
##   * 净额**为负则忽略**，不抵扣线上积分 —— 离线是练习/补贴性质，
##     不该让玩家因为离线输牌而损失线上资产；
##   * 净额为正时只发放"剩余每日额度"内的部分，超出部分不补。
func post_offline_batch(batch: Array) -> Dictionary:
    calls += 1
    last_batch = batch.duplicate(true)
    if fail_next:
        fail_next = false
        return {"ok": false, "message": "网络不可用"}

    var accepted: Array = []
    var net := 0
    var fresh := false
    for entry in batch:
        var id := str((entry as Dictionary).get("id", ""))
        if id.is_empty():
            continue
        # 幂等：已入账的 id 也回"已接收"，让客户端能把它从队列里剔除
        accepted.append(id)
        if _seen.has(id):
            continue
        _seen[id] = true
        fresh = true
        net += int((entry as Dictionary).get("points_delta", 0))

    var credited := 0
    if fresh and net > 0:
        credited = mini(net, maxi(0, daily_cap - _granted_today))
        _granted_today += credited
        _points += credited

    return {
        "ok": true,
        "accepted": accepted,
        "credited": credited,
        "net": net,
        "snapshot": snapshot(),
        "message": "",
    }

## 模拟新的一天（每日额度重置）
func start_new_day() -> void:
    _granted_today = 0
