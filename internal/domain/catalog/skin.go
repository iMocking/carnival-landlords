package catalog

// 主题皮肤目录（纯数据）。与客户端 src/model/skin_catalog.gd 对齐：
// 皮肤不含任何图片资源，客户端全部按颜色程序化绘制，因此服务端只需要下发
// 「ID + 名称 + 价格」，颜色由客户端本地目录决定（换配色不需要改协议）。
//
// 服务端只判断"你有没有这个皮肤"，不关心它长什么样。

// SkinKind 皮肤种类。
type SkinKind string

// 皮肤种类：牌桌背景 / 卡牌。
const (
	SkinKindTable SkinKind = "table"
	SkinKindCard  SkinKind = "card"
)

// 默认皮肤 ID（免费，人人拥有）。
const (
	DefaultTableSkin = "table_classic"
	DefaultCardSkin  = "card_classic"
)

// Skin 皮肤定义。Price 单位为钻石，0 表示免费。
type Skin struct {
	ID    string   `json:"id"`
	Name  string   `json:"name"`
	Desc  string   `json:"desc"`
	Kind  SkinKind `json:"kind"`
	Price int64    `json:"price"`
}

// skins 皮肤目录。数值与顺序对齐客户端 SkinCatalog。
var skins = []Skin{
	// 牌桌背景
	{ID: "table_classic", Name: "经典绿呢", Desc: "红木厅堂 · 翠绿台面", Kind: SkinKindTable, Price: 0},
	{ID: "table_ocean", Name: "深海蓝", Desc: "靛蓝厅堂 · 湖蓝台面", Kind: SkinKindTable, Price: 30},
	{ID: "table_wood", Name: "红木桌", Desc: "棋牌室实木质感", Kind: SkinKindTable, Price: 45},
	{ID: "table_sunset", Name: "落日橙", Desc: "暖色晚霞", Kind: SkinKindTable, Price: 45},
	{ID: "table_night", Name: "暗夜金", Desc: "低调奢华", Kind: SkinKindTable, Price: 60},
	{ID: "table_imperial", Name: "鎏金殿", Desc: "金銮殿同款", Kind: SkinKindTable, Price: 150},
	// 卡牌
	{ID: "card_classic", Name: "经典蓝背", Desc: "标准扑克牌面 · 设计图同款蓝菱背", Kind: SkinKindCard, Price: 0},
	{ID: "card_porcelain", Name: "青花瓷", Desc: "青花釉色", Kind: SkinKindCard, Price: 40},
	{ID: "card_gold", Name: "鎏金", Desc: "金边奢华", Kind: SkinKindCard, Price: 70},
	{ID: "card_night", Name: "暗夜", Desc: "深色护眼", Kind: SkinKindCard, Price: 90},
	{ID: "card_rose", Name: "玫瑰金", Desc: "暖粉金属光", Kind: SkinKindCard, Price: 120},
}

// Skins 返回全部皮肤。
func Skins() []Skin {
	out := make([]Skin, len(skins))
	copy(out, skins)
	return out
}

// FindSkin 按 ID 查皮肤。
func FindSkin(id string) (Skin, bool) {
	for _, s := range skins {
		if s.ID == id {
			return s, true
		}
	}
	return Skin{}, false
}

// SkinsByKind 返回某一类皮肤。
func SkinsByKind(kind SkinKind) []Skin {
	out := make([]Skin, 0, len(skins))
	for _, s := range skins {
		if s.Kind == kind {
			out = append(out, s)
		}
	}
	return out
}

// IsFreeSkin 判断皮肤是否免费（免费皮肤不需要购买记录即视为拥有）。
func IsFreeSkin(id string) bool {
	s, ok := FindSkin(id)
	return ok && s.Price <= 0
}
