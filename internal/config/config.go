// Package config 负责服务端配置的加载。
//
// 加载顺序（后者覆盖前者）：
//  1. 内置默认值（保证零配置也能起来，便于本地开发）
//  2. YAML 配置文件（CONFIG_FILE 指向，默认 ./configs/config.yaml，不存在则跳过）
//  3. 环境变量（生产环境推荐只走环境变量，密钥不进仓库）
//
// 刻意不引入 viper：配置项数量可控，显式覆盖比反射魔法更容易排查线上问题。
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Duration 让 YAML 里可以写 "15m" / "720h" 这类人类可读的时长。
//
// 直接用 time.Duration 不行：yaml.v3 会把它当 int64 解析，"15m" 会直接报错。
type Duration time.Duration

// UnmarshalYAML 实现 yaml.Unmarshaler。
func (d *Duration) UnmarshalYAML(value *yaml.Node) error {
	var raw string
	if err := value.Decode(&raw); err != nil {
		return fmt.Errorf("时长必须是字符串（如 15m）: %w", err)
	}
	parsed, err := time.ParseDuration(raw)
	if err != nil {
		return fmt.Errorf("无法解析时长 %q: %w", raw, err)
	}
	*d = Duration(parsed)
	return nil
}

// Std 返回标准库时长。
func (d Duration) Std() time.Duration { return time.Duration(d) }

// Config 是服务端的全部配置。
type Config struct {
	App      App      `yaml:"app"`
	HTTP     HTTP     `yaml:"http"`
	Postgres Postgres `yaml:"postgres"`
	Redis    Redis    `yaml:"redis"`
	JWT      JWT      `yaml:"jwt"`
	Mail     Mail     `yaml:"mail"`
	Game     Game     `yaml:"game"`
	Offline  Offline  `yaml:"offline"`
	Upload   Upload   `yaml:"upload"`
	Log      Log      `yaml:"log"`
}

// App 应用级配置。
type App struct {
	Name string `yaml:"name"`
	Env  string `yaml:"env"` // dev / test / prod
	// Debug 打开后：允许模拟支付、返回验证码明文、Gin 走 debug 模式。
	Debug bool `yaml:"debug"`
}

// IsProd 生产环境判定。模拟支付等危险能力一律要求非生产。
func (a App) IsProd() bool {
	return strings.EqualFold(a.Env, "prod") || strings.EqualFold(a.Env, "production")
}

// Upload 是本地文件上传配置。
//
// 现阶段**不接对象存储（OSS）**：上传的文件直接落到本地磁盘的 PublicDir 下，
// 由 HTTP 服务以静态资源形式对外提供。这样做的取舍是明确的：
//
//   - 好处：零外部依赖，本地起步与联调不需要任何云账号；
//   - 代价：**多副本部署会读到不同的文件**（每个实例只有自己收到的那份），
//     所以水平扩容前必须换成 OSS 或共享存储，或把上传路由粘到单实例。
//
// 将来接 OSS 时，只需替换"把字节写到哪里"这一步，接口形状与返回的 URL
// 字段都不用改 —— 这正是现在就把 URL 写成相对路径的原因。
type Upload struct {
	// PublicDir 静态资源根目录。启动时若不存在会创建。
	PublicDir string `yaml:"public_dir"`
	// URLPrefix 静态资源对外路径前缀（形如 /static）。
	URLPrefix string `yaml:"url_prefix"`
	// AvatarDir 头像在根目录下的子目录名。
	AvatarDir string `yaml:"avatar_dir"`
	// MaxAvatarBytes 单张头像大小上限（字节）。
	MaxAvatarBytes int64 `yaml:"max_avatar_bytes"`
	// PublicBaseURL 生成绝对 URL 用的前缀（留空则返回相对路径）。
	// 反向代理/ CDN 场景下由运维填写，代码不猜自己的对外域名。
	PublicBaseURL string `yaml:"public_base_url"`
}

// HTTP 是 HTTP 服务配置。
type HTTP struct {
	Addr            string   `yaml:"addr"`
	ReadTimeout     Duration `yaml:"read_timeout"`
	WriteTimeout    Duration `yaml:"write_timeout"`
	ShutdownTimeout Duration `yaml:"shutdown_timeout"`
	// TrustedProxies 为空表示不信任任何代理（Gin 默认信任全部，生产上很危险）。
	TrustedProxies []string `yaml:"trusted_proxies"`
	CORSOrigins    []string `yaml:"cors_origins"`
	// RateLimitPerMinute 单 IP 每分钟请求上限，0 表示关闭。
	RateLimitPerMinute int `yaml:"rate_limit_per_minute"`
}

// Postgres 数据库配置。
type Postgres struct {
	Host            string   `yaml:"host"`
	Port            int      `yaml:"port"`
	User            string   `yaml:"user"`
	Password        string   `yaml:"password"`
	Database        string   `yaml:"database"`
	SSLMode         string   `yaml:"ssl_mode"`
	MaxOpenConns    int      `yaml:"max_open_conns"`
	MaxIdleConns    int      `yaml:"max_idle_conns"`
	ConnMaxLifetime Duration `yaml:"conn_max_lifetime"`
	// AutoMigrate 启动时执行 ent 自动建表（开发用；生产请用 cmd/migrate 显式执行）。
	AutoMigrate bool `yaml:"auto_migrate"`
}

// DSN 拼装 pgx 连接串。
func (p Postgres) DSN() string {
	return fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		p.Host, p.Port, p.User, p.Password, p.Database, p.SSLMode)
}

// Redis 缓存 / 匹配 / 会话配置。
type Redis struct {
	Addr     string `yaml:"addr"`
	Password string `yaml:"password"`
	DB       int    `yaml:"db"`
	PoolSize int    `yaml:"pool_size"`
	// KeyPrefix 用于多环境共用一个 Redis 实例时隔离键空间。
	KeyPrefix string `yaml:"key_prefix"`
}

// JWT 令牌配置。
type JWT struct {
	Secret          string   `yaml:"secret"`
	Issuer          string   `yaml:"issuer"`
	AccessTTL       Duration `yaml:"access_ttl"`
	RefreshTTL      Duration `yaml:"refresh_ttl"`
	AccessAudience  string   `yaml:"access_audience"`
	RefreshAudience string   `yaml:"refresh_audience"`
	// GameAudience 与 AccessAudience / RefreshAudience **必须不同**：
	// game_token 是长期设备凭证（默认 1 年），若与 access 共用 audience，
	// 一个泄漏的 game_token 就不只是"能换会话"，而是**能当 access token 直接调业务接口**，
	// 且有效期长达一年。audience 隔离让三类令牌无法互相冒用。
	GameAudience string `yaml:"game_audience"`
	// GameTTL game_token 有效期。按 D-09 建议 1 年。
	//
	// 为什么敢给一年：它的作用是"这台设备上次是谁"，让客户端跳过登录页。
	// 长期有效与"可吊销"是配套的 —— 纯无状态的长命 JWT 才是危险的，
	// 而这里每次校验都会查 Redis 里的设备记录并回读账号状态（见 auth.VerifyGameToken）。
	GameTTL Duration `yaml:"game_ttl"`
	// MaxActiveSessions 单个账号允许同时在线的会话数，超出踢掉最早的（Redis 里存会话列表）。
	MaxActiveSessions int `yaml:"max_active_sessions"`
}

// Mail 邮件（邮箱验证码）配置。
type Mail struct {
	Driver string `yaml:"driver"` // log / smtp。开发默认 log，只把验证码打日志。
	Host   string `yaml:"host"`
	Port   int    `yaml:"port"`
	User   string `yaml:"user"`
	Pass   string `yaml:"pass"`
	From   string `yaml:"from"`
	// FromName 发件人显示名。
	FromName string `yaml:"from_name"`
	// CodeTTL 验证码有效期。
	CodeTTL Duration `yaml:"code_ttl"`
	// CodeLength 验证码位数。
	CodeLength int `yaml:"code_length"`
	// SendInterval 同一邮箱两次发送的最小间隔（防刷）。
	SendInterval Duration `yaml:"send_interval"`
	// DailyLimit 同一邮箱每天最多发多少封。
	DailyLimit int `yaml:"daily_limit"`
	// Subject 验证码邮件标题模板，%s 会被替换为验证码。
	Subject string `yaml:"subject"`
}

// Game 玩法与对局参数。
type Game struct {
	// InitialGold / InitialDiamonds 新账号初始虚拟币（对齐客户端 START_GOLD / START_DIAMONDS）。
	InitialGold     int64 `yaml:"initial_gold"`
	InitialDiamonds int64 `yaml:"initial_diamonds"`
	// MatchInterval 匹配器扫描间隔。
	MatchInterval Duration `yaml:"match_interval"`
	// MatchTimeout 等待超过该时长仍未成桌则触发机器人补位。
	MatchTimeout Duration `yaml:"match_timeout"`
	// MatchScoreRange 匹配时允许的积分差（随等待时间线性放宽）。
	MatchScoreRange int64 `yaml:"match_score_range"`
	// RoomIdleTimeout 房间内无人操作多久后回收。
	RoomIdleTimeout Duration `yaml:"room_idle_timeout"`
	// TurnTimeout 单次出牌超时（秒），超时自动过牌 / 托管。
	TurnTimeout Duration `yaml:"turn_timeout"`
	// BidTimeout 叫分超时（秒）。
	BidTimeout Duration `yaml:"bid_timeout"`
	// ReconnectGrace 掉线后保留座位多久（期间可重连）。
	ReconnectGrace Duration `yaml:"reconnect_grace"`
	// BotEnabled 匹配超时后是否用机器人补位（对齐欢乐斗地主的"机器人陪玩"）。
	BotEnabled bool `yaml:"bot_enabled"`
	// BotDelay 机器人出牌思考时长。
	BotDelay Duration `yaml:"bot_delay"`
	// MaxRooms 单实例最多同时承载的房间数，0 表示不限。
	MaxRooms int `yaml:"max_rooms"`
}

// Offline 离线进度回传（REC-06）的配置。
//
// 为什么单独一段而不是塞进 Game：它是**经济口径**，不是对局规则。
// 数值调优（每日给多少积分）会随运营变，而对局规则相对稳定，分开放便于各自调整。
type Offline struct {
	// PointsDailyCap 每天允许通过离线对局获得的积分上限。
	//
	// 这个上限是**唯一的**防刷手段：离线对局由客户端本地权威结算，
	// 服务端只能事后接收，因此必须把"离线能换来多少线上积分"钉死在这里。
	// 0 表示完全不允许离线积分入账（用于临时关停该功能）。
	PointsDailyCap int64 `yaml:"points_daily_cap"`
	// MaxRecordsPerBatch 单次上报最多接受多少条记录。
	// 防止一次请求塞进几万条把事务拖死；超出的部分整批拒绝而不是截断 ——
	// 截断会让客户端以为"剩下的下次再报"，而实际上永远报不上去。
	MaxRecordsPerBatch int `yaml:"max_records_per_batch"`
}

// Log 日志配置。
type Log struct {
	Level  string `yaml:"level"`  // debug / info / warn / error
	Format string `yaml:"format"` // console / json
}

// Default 返回一份可以直接跑起来的默认配置。
func Default() Config {
	return Config{
		App: App{Name: "carnival-landlords-server", Env: "dev", Debug: true},
		HTTP: HTTP{
			Addr:               ":8080",
			ReadTimeout:        Duration(15 * time.Second),
			WriteTimeout:       Duration(30 * time.Second),
			ShutdownTimeout:    Duration(10 * time.Second),
			CORSOrigins:        []string{"*"},
			RateLimitPerMinute: 600,
		},
		Upload: Upload{
			PublicDir:      "./public",
			URLPrefix:      "/static",
			AvatarDir:      "avatars",
			MaxAvatarBytes: 2 << 20, // 2 MiB
		}, Postgres: Postgres{
			Host: "127.0.0.1", Port: 5432, User: "postgres", Password: "postgres",
			Database: "carnival_landlords", SSLMode: "disable",
			MaxOpenConns: 30, MaxIdleConns: 10, ConnMaxLifetime: Duration(time.Hour),
			AutoMigrate: true,
		},
		Redis: Redis{Addr: "127.0.0.1:6379", DB: 0, PoolSize: 20, KeyPrefix: "cl"},
		JWT: JWT{
			Secret: "carnival-landlords-dev-secret-change-me",
			Issuer: "carnival-landlords",
			// 对局期间需要长时间在线，access 给 24h，refresh 给 30 天。
			AccessTTL:         Duration(24 * time.Hour),
			RefreshTTL:        Duration(30 * 24 * time.Hour),
			AccessAudience:    "cl-client",
			RefreshAudience:   "cl-refresh",
			GameAudience:      "cl-game",
			GameTTL:           Duration(365 * 24 * time.Hour),
			MaxActiveSessions: 3,
		},
		Mail: Mail{
			Driver: "log", Port: 587, FromName: "狂欢斗地主",
			CodeTTL: Duration(10 * time.Minute), CodeLength: 6,
			SendInterval: Duration(time.Minute), DailyLimit: 20,
			Subject: "【狂欢斗地主】登录验证码 %s",
		},
		Game: Game{
			InitialGold: 2000, InitialDiamonds: 30,
			MatchInterval:   Duration(time.Second),
			MatchTimeout:    Duration(12 * time.Second),
			MatchScoreRange: 800,
			RoomIdleTimeout: Duration(10 * time.Minute),
			TurnTimeout:     Duration(20 * time.Second),
			BidTimeout:      Duration(15 * time.Second),
			ReconnectGrace:  Duration(2 * time.Minute),
			BotEnabled:      true,
			BotDelay:        Duration(1200 * time.Millisecond),
		},
		Offline: Offline{
			// 每天 300 积分：按"离线 3~5 局 ≈ 一局线上对局的积分"量级起步
			// （线上农民赢一把 10×倍数，地主 20×倍数）。
			// 这个数偏保守：先让"离线有正反馈"成立，再按运营需要上调。
			PointsDailyCap:     300,
			MaxRecordsPerBatch: 50,
		},
		Log: Log{Level: "info", Format: "console"},
	}
}

// Load 依次应用默认值、YAML、环境变量。
func Load() (Config, error) {
	cfg := Default()

	path := env("CONFIG_FILE", "configs/config.yaml")
	if raw, err := os.ReadFile(path); err == nil {
		if err := yaml.Unmarshal(raw, &cfg); err != nil {
			return cfg, fmt.Errorf("解析配置文件 %s 失败: %w", path, err)
		}
	} else if !os.IsNotExist(err) {
		return cfg, fmt.Errorf("读取配置文件 %s 失败: %w", path, err)
	}

	applyEnv(&cfg)
	if err := cfg.Validate(); err != nil {
		return cfg, err
	}
	return cfg, nil
}

// Validate 做最小必要校验，避免带病启动。
func (c Config) Validate() error {
	if c.JWT.Secret == "" {
		return fmt.Errorf("jwt.secret 不能为空")
	}
	if c.App.IsProd() {
		if strings.Contains(c.JWT.Secret, "change-me") {
			return fmt.Errorf("生产环境必须通过 JWT_SECRET 覆盖默认密钥")
		}
		if c.App.Debug {
			return fmt.Errorf("生产环境不允许开启 app.debug")
		}
		if c.Postgres.AutoMigrate {
			return fmt.Errorf("生产环境不允许开启 postgres.auto_migrate，请使用 cmd/migrate")
		}
	}
	if c.HTTP.Addr == "" {
		return fmt.Errorf("http.addr 不能为空")
	}
	if c.Postgres.Database == "" {
		return fmt.Errorf("postgres.database 不能为空")
	}
	if c.Mail.CodeLength < 4 || c.Mail.CodeLength > 8 {
		return fmt.Errorf("mail.code_length 必须在 4~8 之间")
	}
	return nil
}

// applyEnv 用环境变量覆盖配置。命名规则：CL_<段>_<字段>，例如 CL_POSTGRES_HOST。
func applyEnv(cfg *Config) {
	cfg.App.Name = env("CL_APP_NAME", cfg.App.Name)
	cfg.App.Env = env("CL_APP_ENV", cfg.App.Env)
	cfg.App.Debug = envBool("CL_APP_DEBUG", cfg.App.Debug)

	cfg.HTTP.Addr = env("CL_HTTP_ADDR", cfg.HTTP.Addr)
	if v := env("CL_HTTP_CORS_ORIGINS", ""); v != "" {
		cfg.HTTP.CORSOrigins = splitList(v)
	}
	if v := env("CL_HTTP_TRUSTED_PROXIES", ""); v != "" {
		cfg.HTTP.TrustedProxies = splitList(v)
	}
	cfg.HTTP.RateLimitPerMinute = envInt("CL_HTTP_RATE_LIMIT", cfg.HTTP.RateLimitPerMinute)

	cfg.Postgres.Host = env("CL_POSTGRES_HOST", cfg.Postgres.Host)
	cfg.Postgres.Port = envInt("CL_POSTGRES_PORT", cfg.Postgres.Port)
	cfg.Postgres.User = env("CL_POSTGRES_USER", cfg.Postgres.User)
	cfg.Postgres.Password = env("CL_POSTGRES_PASSWORD", cfg.Postgres.Password)
	cfg.Postgres.Database = env("CL_POSTGRES_DATABASE", cfg.Postgres.Database)
	cfg.Postgres.SSLMode = env("CL_POSTGRES_SSLMODE", cfg.Postgres.SSLMode)
	cfg.Postgres.MaxOpenConns = envInt("CL_POSTGRES_MAX_OPEN_CONNS", cfg.Postgres.MaxOpenConns)
	cfg.Postgres.AutoMigrate = envBool("CL_POSTGRES_AUTO_MIGRATE", cfg.Postgres.AutoMigrate)

	cfg.Redis.Addr = env("CL_REDIS_ADDR", cfg.Redis.Addr)
	cfg.Redis.Password = env("CL_REDIS_PASSWORD", cfg.Redis.Password)
	cfg.Redis.DB = envInt("CL_REDIS_DB", cfg.Redis.DB)
	cfg.Redis.PoolSize = envInt("CL_REDIS_POOL_SIZE", cfg.Redis.PoolSize)
	cfg.Redis.KeyPrefix = env("CL_REDIS_KEY_PREFIX", cfg.Redis.KeyPrefix)

	cfg.JWT.Secret = env("CL_JWT_SECRET", cfg.JWT.Secret)
	cfg.JWT.Issuer = env("CL_JWT_ISSUER", cfg.JWT.Issuer)
	cfg.JWT.AccessTTL = envDuration("CL_JWT_ACCESS_TTL", cfg.JWT.AccessTTL)
	cfg.JWT.RefreshTTL = envDuration("CL_JWT_REFRESH_TTL", cfg.JWT.RefreshTTL)
	cfg.JWT.GameAudience = env("CL_JWT_GAME_AUDIENCE", cfg.JWT.GameAudience)
	cfg.JWT.GameTTL = envDuration("CL_JWT_GAME_TTL", cfg.JWT.GameTTL)
	cfg.JWT.MaxActiveSessions = envInt("CL_JWT_MAX_ACTIVE_SESSIONS", cfg.JWT.MaxActiveSessions)

	cfg.Mail.Driver = env("CL_MAIL_DRIVER", cfg.Mail.Driver)
	cfg.Mail.Host = env("CL_MAIL_HOST", cfg.Mail.Host)
	cfg.Mail.Port = envInt("CL_MAIL_PORT", cfg.Mail.Port)
	cfg.Mail.User = env("CL_MAIL_USER", cfg.Mail.User)
	cfg.Mail.Pass = env("CL_MAIL_PASS", cfg.Mail.Pass)
	cfg.Mail.From = env("CL_MAIL_FROM", cfg.Mail.From)
	cfg.Mail.CodeTTL = envDuration("CL_MAIL_CODE_TTL", cfg.Mail.CodeTTL)
	cfg.Mail.DailyLimit = envInt("CL_MAIL_DAILY_LIMIT", cfg.Mail.DailyLimit)

	cfg.Game.InitialGold = envInt64("CL_GAME_INITIAL_GOLD", cfg.Game.InitialGold)
	cfg.Game.InitialDiamonds = envInt64("CL_GAME_INITIAL_DIAMONDS", cfg.Game.InitialDiamonds)
	cfg.Game.TurnTimeout = envDuration("CL_GAME_TURN_TIMEOUT", cfg.Game.TurnTimeout)
	cfg.Game.BotEnabled = envBool("CL_GAME_BOT_ENABLED", cfg.Game.BotEnabled)
	cfg.Game.MaxRooms = envInt("CL_GAME_MAX_ROOMS", cfg.Game.MaxRooms)

	cfg.Offline.PointsDailyCap = envInt64("CL_OFFLINE_POINTS_DAILY_CAP", cfg.Offline.PointsDailyCap)
	cfg.Offline.MaxRecordsPerBatch = envInt("CL_OFFLINE_MAX_RECORDS_PER_BATCH", cfg.Offline.MaxRecordsPerBatch)

	cfg.Log.Level = env("CL_LOG_LEVEL", cfg.Log.Level)
	cfg.Log.Format = env("CL_LOG_FORMAT", cfg.Log.Format)
}

func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			return parsed
		}
	}
	return fallback
}

func envInt64(key string, fallback int64) int64 {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if parsed, err := strconv.ParseInt(v, 10, 64); err == nil {
			return parsed
		}
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if parsed, err := strconv.ParseBool(v); err == nil {
			return parsed
		}
	}
	return fallback
}

func envDuration(key string, fallback Duration) Duration {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if parsed, err := time.ParseDuration(v); err == nil {
			return Duration(parsed)
		}
	}
	return fallback
}

func splitList(v string) []string {
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}
