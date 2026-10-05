// Command seed 创建初始账号与测试数据。
//
// # 它解决什么问题
//
// 一个新环境起来之后是**空的**：没有人能登录、没有战绩、没有排行榜、
// 商城与背包都是空的。手工造这些数据既慢又容易造得**不自洽**
// （比如战绩有 12 局但统计写着 0 局，或者排行榜里没有任何人）。
// 这个命令把"一套能立刻点得动、且各页面对得上"的数据一次造出来。
//
// 用法：
//
//	go run ./cmd/seed                       # 3 类账号 + 6 个测试玩家 + 数据
//	go run ./cmd/seed -players 12 -matches 20
//	go run ./cmd/seed -accounts-only        # 只建账号，不造数据
//	go run ./cmd/seed -force                # 生产环境也执行（危险，见下）
//
// # 安全边界
//
//   - **默认拒绝在生产环境运行**：它会创建已知密码的账号。生产环境要用必须
//     显式 -force，并且会再打印一条警告。
//   - **可反复执行**：账号按邮箱判重；钱包走确定性幂等键；战绩/每日统计用
//     确定性 ULID 主键 + ON CONFLICT DO NOTHING。重复执行不会产生重复数据。
//   - 它不碰任何真实支付，也不会给账号发真钱 —— 全是虚拟币。
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"

	"carnival-landlords/internal/casbin"
	"carnival-landlords/internal/config"
	"carnival-landlords/internal/domain/catalog"
	"entgo.io/ent/dialect/sql"

	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/dailystat"
	"carnival-landlords/internal/ent/matchrecord"
	"carnival-landlords/internal/infra/mailer"
	"carnival-landlords/internal/infra/pg"
	"carnival-landlords/internal/infra/redisx"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/id"
	"carnival-landlords/internal/pkg/logger"
	"carnival-landlords/internal/pkg/token"
	"carnival-landlords/internal/service/activity"
	"carnival-landlords/internal/service/auth"
	"carnival-landlords/internal/service/mail"
	"carnival-landlords/internal/service/rank"
	"carnival-landlords/internal/service/reward"
	"carnival-landlords/internal/service/shop"
	"carnival-landlords/internal/service/wallet"
)

// 种子账号的固定约定。写死在代码里而不是配置里，是因为它们就是"开发环境的口令"，
// 放进配置文件反而容易被误带到生产。
const (
	seedDomain      = "carnival.local"
	adminEmail      = "admin@" + seedDomain
	operatorEmail   = "operator@" + seedDomain
	defaultPassword = "Seed@123456"
)

type options struct {
	players       int
	matches       int
	password      string
	accountsOnly  bool
	force         bool
	resetPassword bool
}

func main() {
	var opt options
	flag.IntVar(&opt.players, "players", 6, "生成的测试玩家数量")
	flag.IntVar(&opt.matches, "matches", 12, "每个测试玩家生成的对局记录数")
	flag.StringVar(&opt.password, "password", defaultPassword, "种子账号的密码")
	flag.BoolVar(&opt.accountsOnly, "accounts-only", false, "只创建账号，不生成测试数据")
	flag.BoolVar(&opt.resetPassword, "reset-password", false,
		"把已存在种子账号的密码重设为 -password（默认不动，避免把正在用的人踢下线）")
	flag.BoolVar(&opt.force, "force", false, "允许在生产环境执行（危险）")
	flag.Parse()

	if err := run(opt); err != nil {
		fmt.Fprintln(os.Stderr, "\n种子数据生成失败:", err)
		os.Exit(1)
	}
}

func run(opt options) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	log, err := logger.New(cfg.Log, cfg.App.Env)
	if err != nil {
		return err
	}
	defer func() { _ = log.Sync() }()

	if cfg.App.IsProd() && !opt.force {
		return fmt.Errorf("当前环境是 %s，seed 会创建已知密码的账号，"+
			"如确需执行请显式加 -force", cfg.App.Env)
	}
	if cfg.App.IsProd() {
		log.Warn("⚠ 正在生产环境生成种子数据（-force 已开启），请确认这是你的本意")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	// ---------------- 基础设施
	pgClient, err := pg.Open(ctx, cfg.Postgres, log)
	if err != nil {
		return err
	}
	defer func() { _ = pgClient.Close() }()
	if err := pg.Migrate(ctx, pgClient.Client, pgClient.DB, log); err != nil {
		return fmt.Errorf("同步表结构失败: %w", err)
	}
	rdb, err := redisx.New(ctx, cfg.Redis, log)
	if err != nil {
		return err
	}
	defer func() { _ = rdb.Close() }()

	enforcer, err := casbin.New(ctx, pgClient.Client, log)
	if err != nil {
		return err
	}
	// 注意：**路由权限策略（p 规则）不在这里同步**。
	// 它由 `internal/transport/api` 的 NewRouter 依据真实路由表写入
	//（route -> 允许的角色），种子命令拿不到那份路由表，硬凑一份必然与
	// 真实路由漂移 —— 那比不同步更糟。因此若这是全新数据库且还没启动过
	// api，请先启动一次（它会自动同步），再跑 seed；否则种子管理员登录后会 403。
	// 下面 EnsureSeedRole 负责的是**角色绑定**（g 规则），两件事互相独立。

	// ---------------- 服务
	walletSvc := wallet.New(pgClient.Client, rdb, log)
	granter := reward.New(walletSvc)
	authSvc := auth.New(auth.Deps{
		Client: pgClient.Client, Redis: rdb,
		Tokens: token.NewManager(cfg.JWT), Sender: mailer.New(cfg.Mail, log),
		Roles: enforcer, Wallet: walletSvc, Config: cfg, Logger: log,
	})
	shopSvc := shop.New(shop.Deps{Client: pgClient.Client, Wallet: walletSvc, Granter: granter, Logger: log})
	rankSvc := rank.New(pgClient.Client, pgClient.DB, rdb, log)
	mailSvc := mail.New(pgClient.Client, granter, log)

	// ---------------- 账号
	accounts := []struct {
		email    string
		nickname string
		role     catalog.Role
	}{
		{adminEmail, "超级管理员", catalog.RoleAdmin},
		{operatorEmail, "运营小助手", catalog.RoleOperator},
	}
	for i := 1; i <= opt.players; i++ {
		accounts = append(accounts, struct {
			email    string
			nickname string
			role     catalog.Role
		}{
			email:    fmt.Sprintf("player%d@%s", i, seedDomain),
			nickname: fmt.Sprintf("测试玩家%02d", i),
			role:     catalog.RolePlayer,
		})
	}

	fmt.Println("\n================ 账号 ================")
	fmt.Printf("%-32s %-12s %-10s %s\n", "邮箱", "昵称", "角色", "状态")
	created, existing := 0, 0
	var warnNickname []string
	type seeded struct {
		id       string
		nickname string
		role     catalog.Role
		index    int
	}
	var seededUsers []seeded
	for i, a := range accounts {
		userID, isNew, err := authSvc.EnsureSeedUser(ctx, auth.SeedUserInput{
			Email: a.email, Nickname: a.nickname,
			Password: opt.password, ResetPassword: opt.resetPassword,
		})
		if err != nil {
			// 昵称被占用是**可预期**的情况（老库里的历史账号可能正占着它），
			// 给一个能直接照做的提示，而不是把整个种子流程打断。
			if apperr.From(err).Code == apperr.CodeNicknameTaken {
				return fmt.Errorf("创建账号 %s 失败：昵称「%s」已被其它账号占用，"+
					"请改名或先处理该账号", a.email, a.nickname)
			}
			return fmt.Errorf("创建账号 %s 失败: %w", a.email, err)
		}
		// 昵称对齐：让种子账号的显示名收敛到期望值。
		// 这一步同时会**释放**被旧种子账号占着的昵称（例如它把
		// "运营小助手"占着，而这个名字本该属于运营账号）。
		aligned, err := authSvc.AlignSeedNickname(ctx, userID, a.nickname)
		if err != nil {
			return fmt.Errorf("对齐 %s 的昵称失败: %w", a.email, err)
		}
		if !aligned {
			warnNickname = append(warnNickname,
				fmt.Sprintf("%s 想用昵称「%s」但已被占用，保留原昵称", a.email, a.nickname))
		}
		if isNew {
			created++
		} else {
			existing++
		}
		// 角色每次都对一遍：账号可能是上一次跑出来的，角色未必是这次想要的。
		if err := authSvc.EnsureSeedRole(ctx, userID, a.role); err != nil {
			return fmt.Errorf("设置 %s 的角色失败: %w", a.email, err)
		}
		status := "已存在"
		if isNew {
			status = "新建"
		}
		fmt.Printf("%-32s %-12s %-10s %s\n", a.email, a.nickname, a.role, status)
		seededUsers = append(seededUsers, seeded{id: userID, nickname: a.nickname, role: a.role, index: i})
	}
	fmt.Printf("\n账号合计：新建 %d 个，已存在 %d 个\n", created, existing)
	if opt.resetPassword {
		fmt.Printf("密码：%s（已重设全部种子账号）\n", opt.password)
	} else {
		fmt.Printf("密码：%s（仅新建账号；已存在的账号保持原密码，需要统一请加 -reset-password）\n",
			opt.password)
	}
	for _, w := range warnNickname {
		fmt.Printf("注意：%s\n", w)
	}

	// 探测 API 是否在运行（仅用于结尾给出准确提示，失败不影响种子本身）。
	running := false
	if resp, err := http.Get("http://127.0.0.1" + cfg.HTTP.Addr + "/readyz"); err == nil {
		running = resp.StatusCode == http.StatusOK
		_ = resp.Body.Close()
	}
	if opt.accountsOnly {
		fmt.Println("\n-accounts-only 已指定，跳过测试数据。")
		return nil
	}

	// ---------------- 每个玩家的数据
	fmt.Println("\n================ 测试数据 ================")
	var seededPlayers []seeded
	for _, s := range seededUsers {
		if s.role == catalog.RolePlayer {
			seededPlayers = append(seededPlayers, s)
		}
	}
	for i, s := range seededPlayers {
		if err := seedPlayer(ctx, seedDeps{
			client: pgClient.Client, wallet: walletSvc, shop: shopSvc, mail: mailSvc,
		}, s.id, s.nickname, i, opt.matches); err != nil {
			return fmt.Errorf("为 %s 生成数据失败: %w", s.nickname, err)
		}
	}

	// ---------------- 排行榜回填
	//
	// 排行榜是 Redis ZSET，不随数据库里的 points/gold 自动更新。
	// 不回填的话，新环境的大厅会显示"榜单为空"，而战绩页却有数据 ——
	// 那种不一致最容易让人以为排行榜接口坏了。
	total := 0
	for _, board := range rank.AllBoards() {
		n, err := rankSvc.Rebuild(ctx, board)
		if err != nil {
			return fmt.Errorf("重建 %s 榜失败: %w", board, err)
		}
		total += n
	}
	fmt.Printf("排行榜已回填：%d 条（%v）\n", total, rank.AllBoards())

	fmt.Println("\n种子数据生成完成。")
	fmt.Println()
	// 这一条必须显眼：Casbin 的策略（含"用户 -> 角色"的绑定）在 API 进程里是
	// **内存索引**，不随数据库变化自动更新。seed 是另一个进程，它写进去的新绑定
	// 对正在运行的 API 不可见 —— 表现是种子出来的运营账号"登录成功但处处 403"，
	// 而权限确实配对了，很容易被误判成权限体系有 bug。
	if running {
		fmt.Println("⚠ API 正在运行：Casbin 策略是内存索引，seed 写入的角色绑定它看不到。")
		fmt.Println("  请执行  docker compose restart api  （或先停 API、跑完 seed 再启动）," +
			"否则种子账号会出现'能登录但处处 403'。")
	} else {
		fmt.Println("提示：API 未在运行，启动它会一次性加载全部策略，无需额外操作。")
	}
	fmt.Println("提示：清空测试数据请直接 drop 数据库后重跑 migrate（seed 不提供删除操作，" +
		"避免一个能删账号的命令被误用）。")
	return nil
}

// seedDeps 是造数据需要的服务集合。
type seedDeps struct {
	client *ent.Client
	wallet *wallet.Service
	shop   *shop.Service
	mail   *mail.Service
}

// seedPlayer 为一个玩家生成一整套自洽的数据。
//
// "自洽"是这里的关键要求，而不是"有数据就行"：
//   - 战绩记录、用户身上的累计统计、当天的 daily_stat 三者必须对得上，
//     否则战绩页说有 12 局、统计页说 0 局；
//   - 背包里的道具、拥有的皮肤、订单与钱包流水都走**真实的下单/发放路径**，
//     这样订单页、账单页、背包页看到的是同一件事的不同侧面。
func seedPlayer(ctx context.Context, d seedDeps, userID, nickname string, ordinal, matches int) error {
	// 1) 虚拟币。走账本而不是直接改余额：这样"余额 == 流水之和"从一开始就成立，
	//    账单页也立刻有内容。用确定性幂等键，重跑不会重复发放。
	gold := int64(500_000 + ordinal*50_000)
	diamond := int64(2_000)
	points := int64(1_000 + ordinal*137)
	if _, err := d.wallet.Apply(ctx, userID, []wallet.Delta{
		{
			Currency: wallet.Gold, Amount: gold, Reason: "seed_grant",
			RefType: "user", RefID: userID, Remark: "种子数据：初始金币",
			IdemKey: wallet.IdemKey("seed_grant", userID, string(wallet.Gold)),
		},
		{
			Currency: wallet.Diamond, Amount: diamond, Reason: "seed_grant",
			RefType: "user", RefID: userID, Remark: "种子数据：初始钻石",
			IdemKey: wallet.IdemKey("seed_grant", userID, string(wallet.Diamond)),
		},
		{
			Currency: wallet.Points, Amount: points, Reason: "seed_grant",
			RefType: "user", RefID: userID, Remark: "种子数据：初始积分",
			IdemKey: wallet.IdemKey("seed_grant", userID, string(wallet.Points)),
		},
	}, nil); err != nil {
		return fmt.Errorf("发放虚拟币失败: %w", err)
	}

	// 2) 买两件道具 + 一款皮肤。走真实购买路径（会写订单与流水），
	//    这样商城/背包/订单三个页面互相印证。
	for _, goodID := range []string{"item_card_counter", "item_hint_pack"} {
		idem := id.Deterministic("seed:purchase:" + userID + ":" + goodID)
		if _, err := d.shop.Purchase(ctx, userID, goodID, idem); err != nil {
			return fmt.Errorf("购买 %s 失败: %w", goodID, err)
		}
	}
	// 皮肤重复购买会返回"已经拥有"，对种子来说这正是"已就绪"，不算失败。
	if _, _, err := d.shop.PurchaseSkin(ctx, userID, "table_ocean"); err != nil &&
		apperr.From(err).Code != apperr.CodeConflict {
		return fmt.Errorf("购买皮肤失败: %w", err)
	}

	// 3) 一封带附件的欢迎邮件。幂等键保证重跑只投递一次。
	if _, err := d.mail.Send(ctx, mail.SendInput{
		UserID:   userID,
		Category: "system",
		Sender:   "运营团队",
		Title:    "欢迎来到狂欢斗地主",
		Body:     "这是一封种子数据邮件，附件里的金币可以直接领取。\n\n祝你玩得开心。",
		Attachments: []catalog.Reward{
			{Kind: catalog.RewardGold, Amount: 10_000, Label: "10000金币"},
		},
		IdemKey: "seed:welcome:" + userID,
	}); err != nil {
		return fmt.Errorf("投递欢迎邮件失败: %w", err)
	}

	// 4) 对局记录。主键用确定性 ULID，配合 ON CONFLICT DO NOTHING 实现幂等；
	//    同时累计出用户身上的统计字段，保证战绩页与统计页一致。
	modes := []string{"mode_classic", "mode_quick", "mode_tournament"}
	now := time.Now()
	var games, wins, landlordGames, landlordWins, bombs int64
	maxMultiplier, bestStreak, goldEarned := 0, 0, int64(0)
	streak := 0

	for i := 0; i < matches; i++ {
		recordID := id.Deterministic(fmt.Sprintf("seed:match:%s:%d", userID, i))
		isLandlord := i%3 == 0
		// 造一个**有不小波动**的胜负序列：全赢或全输的假数据看不出榜单与
		// 胜率计算是否正确（比如胜率恒为 100% 时，除零或取整错误都不会暴露）。
		won := (i*7+ordinal*3)%10 >= 4
		bombCount := i % 4
		multiplier := 1 + i%3
		pointsDelta := int64(10 + i*3)
		if !won {
			pointsDelta = -pointsDelta / 2
		}
		goldDelta := pointsDelta * 100

		playedAt := now.Add(-time.Duration(i)*3*time.Hour - time.Duration(ordinal)*17*time.Minute)
		create := d.client.MatchRecord.Create().
			SetID(recordID).
			SetUserID(userID).
			SetRoomID("seed-room").
			SetModeID(modes[i%len(modes)]).
			SetHandIndex(1).
			SetRole(map[bool]string{true: "landlord", false: "farmer"}[isLandlord]).
			SetWon(won).
			SetMultiplier(multiplier).
			SetBaseScore(1 + i%3).
			SetStake(100).
			SetGoldDelta(goldDelta).
			SetPointsDelta(pointsDelta).
			SetBombCount(bombCount).
			SetPlayCount(8 + i%7).
			// opponent_names 是必填的 JSON 字段，不能留空。
			SetOpponentNames([]string{"测试玩家01", "测试玩家02"}).
			SetPlayedAt(playedAt)
		// 用 CreateBulk 而不是 Create().OnConflict().DoNothing() 来做"插入或忽略"。
		//
		// 原因是实测出来的：`Create()....OnConflict(...).DoNothing().Exec(ctx)`
		// 走的是 ent 的 **upsert-one** 路径，SQL 里带 `RETURNING`；
		// 当冲突真的发生、记录被跳过时没有任何行返回，`Exec` 直接报
		// `sql: no rows in result set`。
		//
		// 后果很具体：**第一次跑成功、第二次跑必失败** —— 恰好是"幂等"
		// 最该成立的时候。CreateBulk 只回报影响行数，跳过时返回 0，没有这个问题。
		if err := d.client.MatchRecord.CreateBulk(create).
			OnConflict(sql.ConflictColumns(matchrecord.FieldID), sql.DoNothing()).
			Exec(ctx); err != nil {
			return fmt.Errorf("写入战绩失败: %w", err)
		}

		games++
		if won {
			wins++
			streak++
			if streak > bestStreak {
				bestStreak = streak
			}
		} else {
			streak = 0
		}
		if isLandlord {
			landlordGames++
			if won {
				landlordWins++
			}
		}
		bombs += int64(bombCount)
		if multiplier > maxMultiplier {
			maxMultiplier = multiplier
		}
		goldEarned += goldDelta
	}

	// 5) 把累计统计写回用户行。成就是**累计口径**（取自用户行），
	//    所以这一步同时让成就页有了进度。
	if _, err := d.client.User.UpdateOneID(userID).
		SetGames(games).SetWins(wins).
		SetLandlordGames(landlordGames).SetLandlordWins(landlordWins).
		SetBombsTotal(bombs).
		SetMaxMultiplier(maxMultiplier).
		SetMaxStreak(bestStreak).
		SetCurrentStreak(streak).
		Save(ctx); err != nil {
		return fmt.Errorf("写回累计统计失败: %w", err)
	}

	// 6) 当天统计。今日计数（每日任务用）读的是这张表，不写它就会出现
	//    "战绩页有今天的对局，任务进度却是 0"。
	//
	// 日期必须用 activity.TodayKey()，而不是自己 Format：
	// 服务端读今日计数时用的就是那个函数，两边各算一次"今天"，
	// 一旦时区或日界口径有差异，种出来的数据就会刚好落在"昨天"，
	// 表现为任务进度永远是 0，而战绩页却正常。
	today := activity.TodayKey()
	statID := id.Deterministic("seed:dailystat:" + userID + ":" + today)
	// 同样用 CreateBulk（理由见上面战绩那段的注释）。
	if err := d.client.DailyStat.CreateBulk(
		d.client.DailyStat.Create().
			SetID(statID).
			SetUserID(userID).
			SetDate(today).
			SetGames(games).
			SetWins(wins).
			SetBombs(bombs).
			SetBestStreak(bestStreak).
			SetLandlordWins(landlordWins).
			SetGoldEarned(goldEarned),
	).OnConflict(sql.ConflictColumns(dailystat.FieldID), sql.DoNothing()).
		Exec(ctx); err != nil {
		return fmt.Errorf("写入当天统计失败: %w", err)
	}

	fmt.Printf("  %-12s 金币 %-9d 钻石 %-6d 积分 %-6d 战绩 %d 局（胜 %d）\n",
		nickname, gold, diamond, points, games, wins)
	return nil
}
