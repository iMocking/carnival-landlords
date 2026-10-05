package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// MatchRecord 是玩家个人中心「我的战绩」里的一行。
//
// 字段与客户端 src/model/match_record.gd 对齐，
// 因此客户端登录后可以直接把服务端下发的战绩渲染到原有界面上，不需要改数据结构。
//
// mode_id 从第一版就要落库：客户端"我的战绩"要按玩法分别统计胜率，
// 早期版本没有这个字段，导致旧记录只能粗暴归到经典场。
type MatchRecord struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (MatchRecord) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 战绩字段。
func (MatchRecord) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable().Comment("ULID 主键（与客户端 MatchRecord.id 同构）"),
		field.String("user_id").NotEmpty(),
		field.String("room_id").Default("").Comment("房间 ID"),
		field.String("table_id").Default("").Comment("牌桌 ID"),
		field.String("hand_id").Default("").Comment("小局 ID，用于跳转到对局详情"),
		field.String("mode_id").NotEmpty().Comment("玩法主键，如 mode_classic"),
		field.Int("hand_index").Default(1).Positive().Comment("该局入场后的第几小局"),
		field.String("role").NotEmpty().Comment("身份：地主 / 农民"),
		field.Bool("won").Default(false).Comment("是否获胜"),
		field.Int("multiplier").Default(1).Positive().Comment("结算倍数（含叫分、炸弹、春天）"),
		field.Int("base_score").Default(1).Positive().Comment("叫分底分"),
		field.Int64("stake").Default(0).NonNegative().Comment("该玩法的底注"),
		field.Int64("gold_delta").Default(0).
			Comment("金币实际增减（已按输家余额上限截断，可能小于名义值）"),
		field.Int64("points_delta").Default(0).Comment("积分增减"),
		field.Bool("is_offline").Default(false).
			Comment("是否来自离线对局（客户端本地权威结算、联网后回传，见 REC-06）"),
		field.Int64("credited_points").Default(0).NonNegative().
			Comment("离线回传时**服务端实际发放**的积分（受每日上限截断，可能小于 points_delta；线上对局恒为 0）"),
		field.Int("bomb_count").Default(0).NonNegative().Comment("本局打出的炸弹数"),
		field.Int("play_count").Default(0).NonNegative().Comment("本局出牌手数"),
		field.JSON("opponent_names", []string{}).Comment("对手昵称，展示用"),
		field.Time("played_at").Comment("对局时间"),
	}
}

// Indexes 战绩查询路径。
func (MatchRecord) Indexes() []ent.Index {
	return []ent.Index{
		// "我的战绩"：按玩家 + 时间倒序翻页。
		index.Fields("user_id", "played_at"),
		index.Fields("user_id", "mode_id"),
		// 按玩法聚合的**跨用户**查询（玩法排行榜：GROUP BY user_id WHERE mode_id=?）。
		// 上面那两个索引都以 user_id 打头，对"某玩法下所有人的得分"这种查询
		// 完全用不上；没有这个索引时排行榜会退化成全表扫描。
		index.Fields("mode_id", "played_at"),
		index.Fields("hand_id"),
		// 离线回传要按"玩家 + 当天 + 是否离线"累加已发放积分来算剩余额度。
		index.Fields("user_id", "is_offline", "played_at"),
	}
}
