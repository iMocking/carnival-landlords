class_name AudioLibrary
extends RefCounted
## 真实斗地主音频资源映射（来源见 assets/audio/README.md）。
## 所有逻辑名 -> 文件名的对应关系集中在这里；AudioDirector 只负责播放，
## 替换/屏蔽素材时不需要改视图与 ViewModel。
##
## H5 原版的命名规则：
##   单张 = Man_<n>，对子 = Man_dui<n>，三张 = Man_tuple<n>
##   顺子/连对/飞机/三带一/三带二/四带二/炸弹/王炸 = Man_<牌型>
## 序号 n 就是**牌面值**：A -> 1、2 -> 2、3 -> 3 … 10 -> 10、J -> 11、Q -> 12、K -> 13，
## 小王 -> 14、大王 -> 15。注意它**不是**按斗地主的大小顺序（3 最小）编号的 ——
## 曾经误按 3 -> 1、4 -> 2 换算，于是"出对 4 播报对二、出对 9 播报对七"，
## 整族语音都错开两张。对子/三张只用到 1..13。

const ROOT := "res://assets/audio/Sound"

## 通用音效映射（不含语音）
const SFX := {
    "click": "Special/SpecOk.mp3",
    "select": "Special/SpecSelectCard.mp3",
    "deal": "Special/Special_Dispatch.mp3",
    "deal_fold": "Special/DealFold.mp3",
    "play": "Special/Special_give.mp3",
    "pass": "Special/SpecCancelOrReturn.mp3",
    "warn": "Special/Special_alert.mp3",
    "bid": "Special/Special_querendizhu.mp3",
    "bomb": "Special/Special_Bomb_New.mp3",
    "rocket": "Special/Special_Long_Bomb.mp3",
    "win": "MusicEx/MusicEx_Win.mp3",
    "lose": "MusicEx/MusicEx_Lose.mp3",
    "coin": "Special/Special_huodehuanledou.mp3",
    "level_up": "Special/Special_Jueseshengji.mp3",
    "clap": "Special/clap.mp3",
    "flower": "Special/Special_flower.mp3",
    "star": "Special/Special_star.mp3",
    "plane": "Special/Special_plane.mp3",
    "give": "Special/Special_give.mp3",
    "alert": "Special/Special_alert.mp3",
}

## 背景音乐
const MUSIC := {
    "lobby": "MusicEx/MusicEx_Welcome.mp3",
    "game": "MusicEx/MusicEx_Normal.mp3",
    "alert": "MusicEx/MusicEx_Normal2.mp3",
    "result_win": "MusicEx/MusicEx_Win.mp3",
    "result_lose": "MusicEx/MusicEx_Lose.mp3",
}

## 座位 -> 语音性别：0 我（默认男声）/ 1 小智（男）/ 2 小美（女）
const VOICE_GENDER := ["Man", "Man", "Woman"]

static func path(relative: String) -> String:
    return ROOT + "/" + relative

static func exists(relative: String) -> bool:
    return not _resolve(relative).is_empty()

## 把逻辑相对路径解析成当前可加载的资源路径：
## 优先用已成功导入的 .mp3；Godot 对少数 MPEG 2.5 文件解码失败时改用同名的 .wav。
static func _resolve(relative: String) -> String:
    if relative.is_empty():
        return ""
    if ResourceLoader.exists(path(relative)):
        return relative
    var alt := relative.get_basename() + ".wav"
    if ResourceLoader.exists(path(alt)):
        return alt
    return ""

## 逻辑音效名 -> 相对路径；文件不存在时返回空串，让 AudioDirector 回退到程序化合成。
static func sfx_rel(sound: String) -> String:
    if not SFX.has(sound):
        return ""
    return _resolve(SFX[sound])

## 背景音乐名 -> 相对路径
static func music_rel(track: String) -> String:
    if not MUSIC.has(track):
        return ""
    return _resolve(MUSIC[track])

static func gender_of_seat(seat: int) -> String:
    if seat >= 0 and seat < VOICE_GENDER.size():
        return VOICE_GENDER[seat]
    return "Man"

## 牌值 -> 语音序号：音频包按**牌面值**编号，序号就是牌面本身。
##   A -> 1、2 -> 2、3..10 -> 3..10、J -> 11、Q -> 12、K -> 13、小王 -> 14、大王 -> 15
## 例：出对 4 用 Man_dui4（"对四"），单张 A 用 Man_1（"尖"），单张 2 用 Man_2（"二"）。
static func rank_index(main_rank: int, max_index: int = 15) -> int:
    var index := main_rank
    match main_rank:
        Card.Rank.ACE:
            index = 1
        Card.Rank.TWO:
            index = 2
        Card.Rank.SMALL_JOKER:
            index = 14
        Card.Rank.BIG_JOKER:
            index = 15
    return clampi(index, 1, max_index)

## 牌型 + 牌值 -> 语音文件（相对 Sound/ 的路径）。
## 某个性别缺失时自动回退到另一性别；两者都缺失返回空串。
static func pattern_voice_rel(gender: String, kind: int, main_rank: int, _length: int = 1) -> String:
    var rel := _resolve(_pattern_voice_rel_for(gender, kind, main_rank))
    if rel != "":
        return rel
    var other := "Woman" if gender == "Man" else "Man"
    return _resolve(_pattern_voice_rel_for(other, kind, main_rank))

static func _pattern_voice_rel_for(gender: String, kind: int, main_rank: int) -> String:
    var suffix := ""
    match kind:
        CardPattern.Kind.SINGLE:
            suffix = str(rank_index(main_rank, 15))
        CardPattern.Kind.PAIR:
            suffix = "dui%d" % rank_index(main_rank, 13)
        CardPattern.Kind.TRIPLE:
            suffix = "tuple%d" % rank_index(main_rank, 13)
        CardPattern.Kind.TRIPLE_SINGLE:
            suffix = "sandaiyi"
        CardPattern.Kind.TRIPLE_PAIR:
            suffix = "sandaiyidui"
        CardPattern.Kind.STRAIGHT:
            suffix = "shunzi"
        CardPattern.Kind.DOUBLE_STRAIGHT:
            suffix = "liandui"
        CardPattern.Kind.AIRPLANE, CardPattern.Kind.AIRPLANE_SINGLE, CardPattern.Kind.AIRPLANE_PAIR:
            suffix = "feiji"
        CardPattern.Kind.FOUR_TWO_SINGLE:
            suffix = "sidaier"
        CardPattern.Kind.FOUR_TWO_PAIR:
            suffix = "sidailiangdui"
        CardPattern.Kind.BOMB:
            suffix = "zhadan"
        CardPattern.Kind.ROCKET:
            suffix = "wangzha"
        _:
            return ""
    return "%s/%s_%s.mp3" % [gender, gender, suffix]

## 叫分语音：0 = 不叫，1~3 = 1~3 分（与原版 ScoreOrder_1/2/3 对应）
static func bid_voice_rel(gender: String, score: int) -> String:
    var suffix := ""
    if score <= 0:
        suffix = "NoOrder"
    elif score == 1:
        suffix = "ScoreOrder1"
    elif score == 2:
        suffix = "ScoreOrder2"
    else:
        suffix = "ScoreOrder3"
    return _voice_rel(gender, suffix)

static func pass_voice_rel(gender: String, variant: int) -> String:
    return _voice_rel(gender, "buyao%d" % clampi(variant, 1, 4))

static func alarm_voice_rel(gender: String, count: int) -> String:
    return _voice_rel(gender, "baojing%d" % clampi(count, 1, 2))

static func _voice_rel(gender: String, suffix: String) -> String:
    var rel := _resolve("%s/%s_%s.mp3" % [gender, gender, suffix])
    if rel != "":
        return rel
    var other := "Woman" if gender == "Man" else "Man"
    return _resolve("%s/%s_%s.mp3" % [other, other, suffix])

## 牌型特效音（对应 H5 的 O5 表：顺子->星星、连对->花、飞机->飞机、炸弹->炸弹…）
static func pattern_effect_rel(kind: int) -> String:
    var rel := ""
    match kind:
        CardPattern.Kind.STRAIGHT:
            rel = "Special/Special_star.mp3"
        CardPattern.Kind.DOUBLE_STRAIGHT:
            rel = "Special/Special_flower.mp3"
        CardPattern.Kind.AIRPLANE, CardPattern.Kind.AIRPLANE_SINGLE, CardPattern.Kind.AIRPLANE_PAIR:
            rel = "Special/Special_plane.mp3"
        CardPattern.Kind.BOMB:
            rel = "Special/Special_Bomb_New.mp3"
        CardPattern.Kind.ROCKET:
            rel = "Special/Special_Long_Bomb.mp3"
        CardPattern.Kind.INVALID:
            return ""
        _:
            rel = "Special/Special_give.mp3"
    return _resolve(rel)
