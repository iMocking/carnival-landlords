class_name Ulid
extends RefCounted
## ULID 生成器：48 位毫秒时间戳 + 80 位随机数，Crockford Base32 编码，共 26 个字符。
## 同一毫秒内通过递增随机部分保证单调性，适合作为全局唯一实体 ID（卡牌、玩家、对局）。

const CROCKFORD := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const RANDOM_BYTE_COUNT := 10
const TIME_CHAR_COUNT := 10

static var _crypto: Crypto = null
static var _last_ms: int = -1
static var _last_random := PackedByteArray()

## 生成一个 26 字符的 ULID 字符串。
static func generate() -> String:
    var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
    if now_ms < _last_ms:
        now_ms = _last_ms
    var random_bytes: PackedByteArray
    if now_ms == _last_ms and _last_random.size() == RANDOM_BYTE_COUNT:
        random_bytes = _increment(_last_random)
    else:
        random_bytes = _random_bytes(RANDOM_BYTE_COUNT)
    _last_ms = now_ms
    _last_random = random_bytes
    return _encode_time(now_ms) + _encode_random(random_bytes)

## 校验字符串是否为合法 ULID（长度与字符集）。
static func is_valid(value: String) -> bool:
    if value.length() != TIME_CHAR_COUNT + 16:
        return false
    for i in value.length():
        if CROCKFORD.find(value[i]) < 0:
            return false
    return true

static func _crypto_instance() -> Crypto:
    if _crypto == null:
        _crypto = Crypto.new()
    return _crypto

static func _random_bytes(count: int) -> PackedByteArray:
    var bytes := _crypto_instance().generate_random_bytes(count)
    if bytes.size() == count:
        return bytes
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var fallback := PackedByteArray()
    fallback.resize(count)
    for i in count:
        fallback[i] = rng.randi_range(0, 255)
    return fallback

static func _increment(bytes: PackedByteArray) -> PackedByteArray:
    var result := bytes.duplicate()
    var index := result.size() - 1
    while index >= 0:
        if result[index] == 255:
            result[index] = 0
            index -= 1
        else:
            result[index] = result[index] + 1
            break
    return result

static func _encode_time(time_ms: int) -> String:
    var out := ""
    for i in range(TIME_CHAR_COUNT - 1, -1, -1):
        out += CROCKFORD[(time_ms >> (i * 5)) & 0x1F]
    return out

static func _encode_random(bytes: PackedByteArray) -> String:
    var out := ""
    @warning_ignore("integer_division")
    var char_count := (bytes.size() * 8) / 5
    for c in char_count:
        out += CROCKFORD[_read_bits(bytes, c * 5, 5)]
    return out

static func _read_bits(bytes: PackedByteArray, offset: int, bit_count: int) -> int:
    var value := 0
    for i in bit_count:
        var pos := offset + i
        var byte_index := pos >> 3
        var bit_index := 7 - (pos & 7)
        var bit := 0
        if byte_index >= 0 and byte_index < bytes.size():
            bit = (bytes[byte_index] >> bit_index) & 1
        value = (value << 1) | bit
    return value