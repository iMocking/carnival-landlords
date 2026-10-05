class_name MatchRecord
extends RefCounted
## 单局对战记录（个人中心「历史对局」）。主键使用 ULID。

var id: String = ""
var played_at: int = 0
var role: String = "农民"
var won: bool = false
var multiplier: int = 1
var gold_delta: int = 0
var points_delta: int = 0
var opponent_names: Array = []
## 本局玩法主键（`GameMode.CLASSIC` 等）。"我的战绩"要按玩法分别统计胜率，
## 因此从这一版开始随记录一起持久化；旧存档没有这个字段，读档时回退成经典场。
var mode_id: String = GameMode.CLASSIC

static func create(p_role: String, p_won: bool, p_multiplier: int, p_gold_delta: int, p_points_delta: int,
        p_opponents: Array, p_mode_id: String = GameMode.CLASSIC) -> MatchRecord:
    var record := MatchRecord.new()
    record.id = Ulid.generate()
    record.played_at = int(Time.get_unix_time_from_system())
    record.role = p_role
    record.won = p_won
    record.multiplier = maxi(p_multiplier, 1)
    record.gold_delta = p_gold_delta
    record.points_delta = p_points_delta
    record.opponent_names = p_opponents.duplicate()
    record.mode_id = p_mode_id if not p_mode_id.is_empty() else GameMode.CLASSIC
    return record

static func from_dict(data: Dictionary) -> MatchRecord:
    var record := MatchRecord.new()
    record.id = str(data.get("id", ""))
    if record.id.is_empty() or not Ulid.is_valid(record.id):
        record.id = Ulid.generate()
    record.played_at = int(data.get("played_at", 0))
    record.role = str(data.get("role", "农民"))
    record.won = bool(data.get("won", false))
    record.multiplier = maxi(1, int(data.get("multiplier", 1)))
    record.gold_delta = int(data.get("gold_delta", 0))
    record.points_delta = int(data.get("points_delta", 0))
    record.opponent_names = data.get("opponents", [])
    var mode_id := str(data.get("mode_id", ""))
    # 旧存档没有 mode_id：回退到经典场（历史上只有经典场与它规则相同的高倍场）
    record.mode_id = mode_id if not mode_id.is_empty() else GameMode.CLASSIC
    return record

func to_dict() -> Dictionary:
    return {
        "id": id,
        "played_at": played_at,
        "role": role,
        "won": won,
        "multiplier": multiplier,
        "gold_delta": gold_delta,
        "points_delta": points_delta,
        "opponents": opponent_names,
        "mode_id": mode_id,
    }

## 本局玩法的显示名（找不到时回退成主键，绝不显示空白）
func mode_name() -> String:
    return str(GameMode.find(mode_id).get("name", mode_id))

func result_text() -> String:
    return "胜利" if won else "失败"

func time_text() -> String:
    if played_at <= 0:
        return "--"
    var dt := Time.get_datetime_dict_from_unix_time(played_at)
    return "%02d-%02d %02d:%02d" % [int(dt.get("month", 1)), int(dt.get("day", 1)), int(dt.get("hour", 0)), int(dt.get("minute", 0))]

func gold_text() -> String:
    return "%s%d" % ["+" if gold_delta >= 0 else "", gold_delta]