package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/ent/schema/mixin"
)

// DailyStat 是玩家**当天**的行为计数。
//
// 每日任务的进度全部来自这张表，而不是让客户端上报"我打了 3 局"。
// 每个字段都是一个可被服务端独立验证的事实：
//
//	games        完成的结算局数（结算成功才算，中途退出不算）
//	wins         胜场
//	bombs        打出的炸弹数（服务端从操作流水里数，客户端说了不算）
//	best_streak  当天最高连胜
//	landlord_wins 当天以地主身份获胜的次数
//	tournament_games 当天完成的比赛场小局数
//
// date 用 'YYYY-MM-DD' **字符串**而不是 timestamp：跨天判定只需要回答
// "是不是同一天"，字符串最直接，也免得为时区问题纠结（按服务器本地时区切天）。
type DailyStat struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (DailyStat) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 每日统计字段。
func (DailyStat) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").Unique().Immutable(),
		field.String("user_id").NotEmpty(),
		field.String("date").NotEmpty().Comment("本地日期，格式 YYYY-MM-DD"),
		field.Int64("games").Default(0).NonNegative(),
		field.Int64("wins").Default(0).NonNegative(),
		field.Int64("bombs").Default(0).NonNegative(),
		field.Int("best_streak").Default(0).NonNegative(),
		field.Int64("landlord_wins").Default(0).NonNegative(),
		field.Int64("tournament_games").Default(0).NonNegative(),
		field.Int64("gold_earned").Default(0).NonNegative().Comment("当天对局净收入的累加（仅统计正数部分）"),
	}
}

// Indexes 每人每天一行。
func (DailyStat) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("user_id", "date").Unique(),
		index.Fields("date"),
	}
}
