package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent/schema/mixin"
)

// User 是玩家账号 + 档案 + 钱包的**单一权威行**。
//
// ## 为什么钱包不拆成独立表
//
// 常见做法是 user / wallet 两张表。这里刻意合并，原因很实在：
// 斗地主的每一次结算都要同时改"金币 + 积分 + 战绩计数"，
// 拆表就必然引入跨表事务与"User 改了 Wallet 没改"的不一致窗口。
// 合并成一行后，一次 UPDATE ... WHERE id = ? AND version = ? 就能原子地完成全部变更。
//
// 代价是这一行比较宽、写热点集中。对这个体量的游戏完全可接受：
// 一个房间最多 3 个玩家在结算时写一次，PG 的行锁足够。
//
// ## 数值字段的口径
//
//   - gold / diamonds / points：**余额快照**。每一次变动都必须在
//     wallet_transactions 里留下一条流水，余额与流水之和必须永远相等（见 wallet 服务）。
//   - version：乐观锁。任何改余额的语句都带 version 条件，
//     影响行数为 0 就说明并发冲突，直接让客户端重试，而不是盲写覆盖。
type User struct {
	ent.Schema
}

// Mixin 加上时间戳。
func (User) Mixin() []ent.Mixin {
	return []ent.Mixin{mixin.Time{}}
}

// Fields 用户字段。
func (User) Fields() []ent.Field {
	return []ent.Field{
		field.String("id").
			Unique().Immutable().
			Comment("ULID 主键（与客户端 id 体系一致）"),

		// ---------------- 账号
		field.String("email").
			Unique().NotEmpty().
			Comment("登录邮箱，写入前统一转小写"),
		field.String("password_hash").
			Sensitive().
			Comment("bcrypt 哈希，永不返回客户端"),
		field.String("nickname").
			Unique().NotEmpty().
			Comment("昵称，全局唯一（排行榜与牌桌都靠它识别）"),
		field.Int("avatar_index").
			Default(0).NonNegative().
			Comment("头像序号，客户端按序号程序化绘制"),
		field.String("role").
			Default(string(catalog.RolePlayer)).
			Comment("平台角色：player / gm / admin，Casbin 据此授权"),
		field.String("status").
			Default("active").
			Comment("账号状态：active / banned"),
		field.String("ban_reason").
			Default("").
			Comment("封禁原因，展示给玩家"),
		field.Time("banned_until").
			Optional().Nillable().
			Comment("封禁到期时间，nil 表示永久"),
		field.Time("vip_expire_at").
			Optional().Nillable().
			Comment("VIP 到期时间，nil 表示非 VIP"),

		// ---------------- 等级与虚拟币
		field.Int("level").
			Default(1).Positive().
			Comment("等级，由经验推导"),
		field.Int64("exp").
			Default(0).NonNegative().
			Comment("累计经验"),
		field.Int64("gold").
			Default(0).NonNegative().
			Comment("金币余额（软通货，对局产出与消耗）"),
		field.Int64("diamonds").
			Default(0).NonNegative().
			Comment("钻石余额（硬通货，任务/签到产出，商城消耗）"),
		field.Int64("points").
			Default(0).NonNegative().
			Comment("积分，用于排行榜与匹配分池"),

		// ---------------- 战绩（与客户端 PlayerProfile 对齐）
		field.Int64("games").Default(0).NonNegative().Comment("总对局数"),
		field.Int64("wins").Default(0).NonNegative().Comment("总胜场"),
		field.Int64("landlord_games").Default(0).NonNegative().Comment("当地主的局数"),
		field.Int64("landlord_wins").Default(0).NonNegative().Comment("当地主的胜场"),
		field.Int64("bombs_total").Default(0).NonNegative().Comment("累计炸弹数"),
		field.Int("max_multiplier").Default(0).NonNegative().Comment("历史最高倍数"),
		field.Int("max_streak").Default(0).NonNegative().Comment("历史最高连胜"),
		field.Int("current_streak").Default(0).NonNegative().Comment("当前连胜"),

		// ---------------- 客户端设置（跨设备同步）
		field.Bool("music_enabled").Default(true),
		field.Bool("sfx_enabled").Default(true),
		field.Bool("tts_enabled").Default(true),
		field.Bool("vibrate_enabled").Default(true),
		field.Bool("quick_hint_enabled").Default(true),
		field.Int("card_speed").Default(2).Min(0).Max(4),
		field.Int("hint_level").Default(1).Min(0).Max(2),
		field.Bool("auto_sort_hand").Default(false),
		field.String("table_skin_id").Default(catalog.DefaultTableSkin),
		field.String("card_skin_id").Default(catalog.DefaultCardSkin),

		// ---------------- 登录信息
		field.Time("last_login_at").Optional().Nillable(),
		field.String("last_login_ip").Default(""),

		field.Int64("version").
			Default(0).
			Comment("乐观锁版本号，改余额时作为 UPDATE 条件"),
	}
}

// Indexes 常用查询路径。
func (User) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("role"),
		index.Fields("status"),
		index.Fields("points"),
		index.Fields("gold"),
		index.Fields("vip_expire_at"),
	}
}
