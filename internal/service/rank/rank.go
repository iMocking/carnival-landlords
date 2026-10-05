// Package rank 是排行榜服务：积分榜 / 金币榜 / 胜场榜 / 最高连胜榜。
//
// ## 为什么用 Redis ZSET
//
// 排行榜是典型的"读多写少、只要前 N 名"的数据：
//   - 写入发生在结算之后（每个玩家每小局 4 次 ZADD），是低频顺序写；
//   - 读取要按分数排序取区间，还要能 O(logN) 地问"我第几名"。
//
// ZSET 正好同时满足这两点：ZADD O(logN)，ZREVRANGE 取头部，
// ZREVRANK 直接给出名次。用 SQL 实现同样的语义要写窗口函数，
// 数据量一大就会把数据库拖垮 —— 而排行榜恰恰是最容易被刷的接口。
//
// ## 权威值只来自 users 表
//
// 榜单分数**永远是** users 行上的 points / gold / wins / max_streak，
// 没有任何接口接收客户端上报的分数。刷榜的常见做法是"客户端声明我得了多少分"，
// 这里从设计上就不给这个口子：客户端能做的只有打牌，分数由服务端结算产生。
//
// ## 为什么分数为 0 / 负数不进榜
//
// 新注册玩家的四个值都是 0。如果把 0 也写进 ZSET，榜单会被"全 0 大军"填满，
// 前 200 名毫无意义，而且每次清理都要扫全表。因此约定：
// **score <= 0 视为下榜**（ZREM），只有真正有分数的玩家才在榜上。
// 金币会随消费下降，降到 0 时会自动离开金币榜，这正是想要的行为。
//
// ## 同分怎么办
//
// ZSET 对同分成员按成员名（这里是 userID）字典序排列，而 ZREVRANGE 是**逆序**遍历，
// 于是榜单上同分时后注册的玩家（ULID 更大）排在前面。
// 这个规则来自 Redis 本身，与写入先后、与节点重启都无关，
// 因此同一份数据两次请求的顺序永远一致。我们只依赖"确定"，
// 不再自己发明排序规则。
//
// 为什么**不**把分数取负后改用 ZRANGE 换来"同分先注册的在前"：
// 那样 Redis 里存的就不是玩家的真实分数，运维用 redis-cli 核对榜单时
// 会看到 -1200 这种数字，对账成本远大于这点排序上的美观。
package rank

import (
	"context"
	"database/sql"
	"errors"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/service/view"
)

// Board 排行榜类型。
type Board string

// 四个榜单。
const (
	// BoardPoints 积分榜。积分只用于排行榜与匹配分池，不可消费，最稳定。
	BoardPoints Board = "points"
	// BoardGold 金币榜。金币会随消费下降，榜单会跟着往下掉。
	BoardGold Board = "gold"
	// BoardWins 胜场榜。累计胜场，只增不减。
	BoardWins Board = "wins"
	// BoardStreak 最高连胜榜。历史最高连胜，只增不减。
	BoardStreak Board = "streak"
)

// allBoards 全部榜单，顺序固定（批量刷新与遍历都按它输出）。
var allBoards = []Board{BoardPoints, BoardGold, BoardWins, BoardStreak}

// AllBoards 返回全部榜单类型。
//
// 返回副本而不是内部切片：调用方改了它，就会悄无声息地改变
// 所有地方"刷哪些榜"的行为，这种 bug 极难定位。
func AllBoards() []Board {
	out := make([]Board, len(allBoards))
	copy(out, allBoards)
	return out
}

// Valid 判断榜单类型是否合法。
func (b Board) Valid() bool {
	switch b {
	case BoardPoints, BoardGold, BoardWins, BoardStreak:
		return true
	default:
		return false
	}
}

// Label 中文名，用于日志与后台展示。
func (b Board) Label() string {
	switch b {
	case BoardPoints:
		return "积分榜"
	case BoardGold:
		return "金币榜"
	case BoardWins:
		return "胜场榜"
	case BoardStreak:
		return "最高连胜榜"
	default:
		return string(b)
	}
}

// 榜单条数的上下限。
const (
	// maxTopN Top 一次最多返回多少名。上限存在的意义是防止
	// "n=100000"这种请求把整个 ZSET 拉进内存。
	maxTopN = 200
	// defaultTopN n <= 0 时的默认条数。
	defaultTopN = 10
	// maxAroundRadius Around 的 radius 上限，避免一次拉出整个榜。
	maxAroundRadius = 100
	// rebuildBatch Rebuild 每次扫描 users 表的条数。
	rebuildBatch = 500
)

// Entry 排行榜一行。
//
// 这里没有直接复用 view.Brief：Brief 是"玩家档案"，
// 带邮箱、胜率等榜单不需要的字段；榜单行只表达"第几名、谁、多少分"。
// VIP 的判定复用 view.IsVIP，避免"榜上说不是 VIP、个人中心说是"这种两套口径。
type Entry struct {
	Rank        int    `json:"rank"`
	UserID      string `json:"user_id"`
	Nickname    string `json:"nickname"`
	AvatarIndex int    `json:"avatar_index"`
	Level       int    `json:"level"`
	Score       int64  `json:"score"`
	VIP         bool   `json:"vip"`
}

// userLoader 回表补齐展示字段（昵称 / 头像 / 等级 / VIP）。
//
// 抽成字段而不是直接写死成 ent 查询，是为了让"取 ZSET 区间 → 回表 → 组行"
// 这条主流程可以在不接数据库的情况下单测（见 rank_test.go）：
// 排行榜最容易被写错的是名次与同分顺序，而那部分逻辑与数据库无关。
type userLoader func(ctx context.Context, ids []string) (map[string]*ent.User, error)

// Service 排行榜服务。
type Service struct {
	client *ent.Client
	// db 用于**按玩法**的榜单聚合（见 mode.go）。
	//
	// 账号级榜单（rank.go 的四个榜）不需要它：那些分数直接取自 users 行，
	// 走 ent 就够了。而玩法榜要跨用户聚合 match_records，
	// 手写 SQL 比用 ent 的 GroupBy/Aggregate 更直观也更可控。
	db    *sql.DB
	redis *redisx.Client
	log   *zap.Logger
	// load 回表查询，默认走 ent；测试里可替换。
	load userLoader
}

// New 构造排行榜服务。db 允许为 nil（只使用账号级榜单时不需要它）。
func New(client *ent.Client, db *sql.DB, redis *redisx.Client, log *zap.Logger) *Service {
	s := &Service{client: client, db: db, redis: redis, log: log}
	s.load = s.queryUsers
	return s
}

// Update 把玩家的榜单分数写入 Redis ZSET。score 为该榜单的权威值。
//
// 传 0 或负数表示"该玩家不该出现在这个榜上"，执行的是 ZREM 而不是写入 0 分。
func (s *Service) Update(ctx context.Context, userID string, board Board, score int64) error {
	if !board.Valid() {
		return apperr.ErrInvalidParam.WithMessage("未知榜单 %q", board)
	}
	if userID == "" {
		return apperr.ErrInvalidParam.WithMessage("缺少用户 ID")
	}
	if s.redis == nil {
		return apperr.ErrDependency.WithMessage("排行榜依赖 Redis")
	}
	return s.apply(ctx, s.redis.Raw(), userID, board, score)
}

// UpdateAll 一次性刷新某玩家的全部榜单（结算后调用）。
//
// 四个榜用一条 pipeline 发出去：结算路径上每个玩家都要刷一次，
// 4 次网络往返在每局结算里是白白多出来的延迟，pipeline 之后只剩 1 次。
func (s *Service) UpdateAll(ctx context.Context, u *ent.User) error {
	if u == nil || u.ID == "" {
		return apperr.ErrInvalidParam.WithMessage("缺少用户")
	}
	if s.redis == nil {
		return apperr.ErrDependency.WithMessage("排行榜依赖 Redis")
	}

	pipe := s.redis.Raw().TxPipeline()
	for _, board := range allBoards {
		if err := s.apply(ctx, pipe, u.ID, board, scoreOf(u, board)); err != nil {
			return err
		}
	}
	if _, err := pipe.Exec(ctx); err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// Top 取榜单前 n 名（n 上限 200）。会回表补昵称/头像/等级；用户已不存在时跳过。
func (s *Service) Top(ctx context.Context, board Board, n int) ([]Entry, error) {
	if !board.Valid() {
		return nil, apperr.ErrInvalidParam.WithMessage("未知榜单 %q", board)
	}
	if s.redis == nil {
		return nil, apperr.ErrDependency.WithMessage("排行榜依赖 Redis")
	}
	n = clampTopN(n)

	rows, err := s.redis.Raw().ZRevRangeWithScores(ctx, s.key(board), 0, int64(n-1)).Result()
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return s.entries(ctx, rows, 1)
}

// RankOf 查询某玩家的名次（1 开始）。不在榜返回 0。
func (s *Service) RankOf(ctx context.Context, board Board, userID string) (int, error) {
	if !board.Valid() {
		return 0, apperr.ErrInvalidParam.WithMessage("未知榜单 %q", board)
	}
	if userID == "" {
		return 0, nil
	}
	if s.redis == nil {
		return 0, apperr.ErrDependency.WithMessage("排行榜依赖 Redis")
	}

	rank, err := s.redis.Raw().ZRevRank(ctx, s.key(board), userID).Result()
	if errors.Is(err, redis.Nil) {
		// 不在榜不是错误：没打过牌、分数为 0 的玩家本来就不该在榜上。
		return 0, nil
	}
	if err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}
	return int(rank) + 1, nil
}

// Around 取某玩家附近的榜单（前后各 radius 名），用于"我的排名"面板。
//
// 玩家不在榜时返回空列表（而不是报错）：客户端拿到空列表就显示"还没有上榜"，
// 比让它去解析一个错误码简单。radius <= 0 时退化成"只取他自己那一行"。
func (s *Service) Around(ctx context.Context, board Board, userID string, radius int) ([]Entry, error) {
	if !board.Valid() {
		return nil, apperr.ErrInvalidParam.WithMessage("未知榜单 %q", board)
	}
	if s.redis == nil {
		return nil, apperr.ErrDependency.WithMessage("排行榜依赖 Redis")
	}
	if radius < 0 {
		radius = 0
	}
	if radius > maxAroundRadius {
		radius = maxAroundRadius
	}

	rank, err := s.RankOf(ctx, board, userID)
	if err != nil {
		return nil, err
	}
	if rank == 0 {
		return []Entry{}, nil
	}

	start, stop := aroundWindow(rank, radius)
	rows, err := s.redis.Raw().ZRevRangeWithScores(ctx, s.key(board), start, stop).Result()
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	return s.entries(ctx, rows, int(start)+1)
}

// Rebuild 从数据库全量重建某榜单（运维/对账用）。分批扫描 users 表，避免一次加载全部。
//
// 重建过程写成"临时键 → RENAME"，而不是"先 DEL 再逐批 ZADD"：
// 后者会让线上在这几秒里读到一个空榜或者半个榜。
// RENAME 在 Redis 里是原子的，读请求要么看到旧榜、要么看到完整的新榜。
//
// 返回写进榜单的玩家数（分数为 0 的不计）。
func (s *Service) Rebuild(ctx context.Context, board Board) (int, error) {
	if !board.Valid() {
		return 0, apperr.ErrInvalidParam.WithMessage("未知榜单 %q", board)
	}
	if s.redis == nil {
		return 0, apperr.ErrDependency.WithMessage("排行榜依赖 Redis")
	}
	if s.client == nil {
		return 0, apperr.ErrDependency.WithMessage("重建榜单需要数据库连接")
	}

	tmp := s.redis.Keys().LeaderboardRebuild(string(board))
	// 上一次重建如果中途失败，临时键会残留；先清掉，
	// 否则这次重建会把上一次的陈旧数据一起 RENAME 进正式榜。
	if err := s.redis.Del(ctx, tmp); err != nil {
		return 0, apperr.ErrDependency.WithCause(err)
	}

	written := 0
	lastID := ""
	// 按主键游标分页。userID 是 ULID（字典序 = 时间序），
	// 所以 ID > lastID 这种游标分页既不会漏也不会重，且不依赖 OFFSET。
	for {
		// 同样只取算分需要的列：全量重建会扫过整张 users 表，
		// 把设置、密码哈希这些字段一起读出来纯属浪费。
		q := s.client.User.Query().
			Select(user.FieldID, user.FieldPoints, user.FieldGold, user.FieldWins, user.FieldMaxStreak).
			Order(ent.Asc(user.FieldID)).
			Limit(rebuildBatch)
		if lastID != "" {
			q = q.Where(user.IDGT(lastID))
		}
		rows, err := q.All(ctx)
		if err != nil {
			return written, apperr.ErrDependency.WithCause(err)
		}
		if len(rows) == 0 {
			break
		}

		pipe := s.redis.Raw().Pipeline()
		pending := 0
		for _, u := range rows {
			lastID = u.ID
			if score := scoreOf(u, board); score > 0 {
				pipe.ZAdd(ctx, tmp, redis.Z{Score: float64(score), Member: u.ID})
				pending++
			}
		}
		if pending > 0 {
			if _, err := pipe.Exec(ctx); err != nil {
				return written, apperr.ErrDependency.WithCause(err)
			}
			written += pending
		}
		if len(rows) < rebuildBatch {
			break
		}
	}

	key := s.key(board)
	if written == 0 {
		// 全员 0 分（例如新开的服）：RENAME 一个不存在的键会报错，直接删正式键。
		if err := s.redis.Del(ctx, key); err != nil {
			return 0, apperr.ErrDependency.WithCause(err)
		}
		return 0, nil
	}
	if err := s.redis.Raw().Rename(ctx, tmp, key).Err(); err != nil {
		return written, apperr.ErrDependency.WithCause(err)
	}
	return written, nil
}

// ---------------- 内部

// key 返回榜单的 ZSET 键。走 Keys 注册表，避免键名手写漂移。
func (s *Service) key(board Board) string {
	return s.redis.Keys().Leaderboard(string(board))
}

// apply 写入一次榜单分数。
//
// 注意这里的 score 一定是 users 行上的值（见 scoreOf），
// 没有任何路径能让客户端指定自己的分数。
func (s *Service) apply(ctx context.Context, r redis.Cmdable, userID string, board Board, score int64) error {
	key := s.key(board)
	var err error
	if score <= 0 {
		err = r.ZRem(ctx, key, userID).Err()
	} else {
		// ZSET 的 score 是 float64。积分 / 金币是 int64，
		// 超过 2^53 才会丢精度 —— 那个量级在这个游戏里不存在。
		err = r.ZAdd(ctx, key, redis.Z{Score: float64(score), Member: userID}).Err()
	}
	if err != nil {
		return apperr.ErrDependency.WithCause(err)
	}
	return nil
}

// entries 把 ZSET 区间翻译成榜单行。
//
// 回表补齐展示字段**只查一次**（IDIn），不是每条一次：
// 200 名的榜单如果按行查就是 200 次往返，这是排行榜最经典的 N+1。
func (s *Service) entries(ctx context.Context, rows []redis.Z, startRank int) ([]Entry, error) {
	if len(rows) == 0 {
		return []Entry{}, nil
	}
	ids := make([]string, 0, len(rows))
	seen := make(map[string]struct{}, len(rows))
	for _, z := range rows {
		uid, ok := z.Member.(string)
		if !ok || uid == "" {
			continue
		}
		if _, dup := seen[uid]; dup {
			continue
		}
		seen[uid] = struct{}{}
		ids = append(ids, uid)
	}

	users, err := s.load(ctx, ids)
	if err != nil {
		return nil, err
	}
	return buildEntries(rows, startRank, users), nil
}

// queryUsers 默认的回表实现。
//
// 只取榜单要展示的几列：users 是很宽的一张表（客户端设置、密码哈希都在上面），
// Top 又是被刷得最凶的接口之一，少读几列是实打实的省 IO。
// 代价是这里的列清单必须与 buildEntries 用到的字段保持一致 ——
// 改 buildEntries 时记得回来加列。
func (s *Service) queryUsers(ctx context.Context, ids []string) (map[string]*ent.User, error) {
	out := make(map[string]*ent.User, len(ids))
	if len(ids) == 0 {
		// 空榜不发查询：Top 一个空榜是很常见的请求（新服、冷门榜）。
		return out, nil
	}
	if s.client == nil {
		return nil, apperr.ErrDependency.WithMessage("排行榜回表查询缺少数据库连接")
	}
	users, err := s.client.User.Query().
		Where(user.IDIn(ids...)).
		Select(
			user.FieldID,
			user.FieldNickname,
			user.FieldAvatarIndex,
			user.FieldLevel,
			user.FieldVipExpireAt,
		).
		All(ctx)
	if err != nil {
		return nil, apperr.ErrDependency.WithCause(err)
	}
	for _, u := range users {
		out[u.ID] = u
	}
	return out, nil
}

// buildEntries 组行。startRank 是 rows[0] 的名次（1 开始）。
//
// 回表查不到的用户（注销 / 被清理）直接跳过，名次因此出现空档 —— 这是刻意的：
// 空档说明"榜上确实有这个位置，只是号没了"，而不是把后面所有人的名次往前挪
// （那会让玩家看到"我第 5 名"下次刷新又变成第 6 名）。
func buildEntries(rows []redis.Z, startRank int, users map[string]*ent.User) []Entry {
	out := make([]Entry, 0, len(rows))
	for i, z := range rows {
		uid, ok := z.Member.(string)
		if !ok || uid == "" {
			continue
		}
		u := users[uid]
		if u == nil {
			continue
		}
		out = append(out, Entry{
			Rank:        startRank + i,
			UserID:      uid,
			Nickname:    u.Nickname,
			AvatarIndex: u.AvatarIndex,
			Level:       u.Level,
			Score:       int64(z.Score),
			VIP:         view.IsVIP(u),
		})
	}
	return out
}

// scoreOf 取某个榜单在 users 行上的权威值。
//
// 这是"榜单分数从哪来"的**唯一**答案：加新榜时只改这里与 allBoards，
// 读取路径（Top / Around / RankOf）完全不需要知道分数是怎么算的。
func scoreOf(u *ent.User, board Board) int64 {
	if u == nil {
		return 0
	}
	switch board {
	case BoardPoints:
		return u.Points
	case BoardGold:
		return u.Gold
	case BoardWins:
		return u.Wins
	case BoardStreak:
		return int64(u.MaxStreak)
	default:
		return 0
	}
}

// clampTopN 归一化 Top 的条数。
func clampTopN(n int) int {
	if n <= 0 {
		return defaultTopN
	}
	if n > maxTopN {
		return maxTopN
	}
	return n
}

// aroundWindow 算出"我附近的榜单"要取的 ZSET 区间（0 基、闭区间）。
//
// rank 是 1 基名次。靠前时整体后移而不是被截断：
// 第 1 名也要能拿到后面 2*radius 个人，否则面板上只剩半屏。
func aroundWindow(rank, radius int) (int64, int64) {
	if rank < 1 {
		rank = 1
	}
	if radius <= 0 {
		idx := int64(rank - 1)
		return idx, idx
	}
	if rank-1 <= radius {
		return 0, int64(2 * radius)
	}
	return int64(rank - 1 - radius), int64(rank - 1 + radius)
}
