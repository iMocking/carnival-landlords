package auth

import (
	"context"

	"carnival-landlords/internal/domain/catalog"
	"carnival-landlords/internal/ent"
	"carnival-landlords/internal/ent/user"
	"carnival-landlords/internal/pkg/apperr"
	"carnival-landlords/internal/pkg/password"
	"carnival-landlords/internal/pkg/validate"
)

// SeedUserInput 是种子建号的入参。
type SeedUserInput struct {
	Email    string
	Nickname string
	Password string
	// ResetPassword 为 true 时，对已存在的账号重设密码。
	//
	// 默认 false 是刻意的：种子账号可能已经被人改过密码并用它登录，
	// 悄悄改掉会把人踢下线且没有任何提示。需要"统一密码"这种确定性时
	// 由调用方显式打开（见 cmd/seed 的 -reset-password）。
	ResetPassword bool
}

// EnsureSeedUser 供 `cmd/seed` 使用的建号入口：账号已存在则直接返回。
//
// # 与 Register 的区别，以及为什么必须另开一个入口
//
// `Register` 要求先通过**邮箱验证码**校验（`verifyCode`），因为它是面向
// 公网的自助注册。种子脚本没有邮箱可收码，硬要模拟一遍
// "发码 -> 读回码 -> 建号"只是把"这是本地可信操作"这个事实藏起来。
//
// 所以这条路径**刻意跳过验证码**，代价是它绝不能出现在 HTTP 层：
//   - 本仓库没有任何 handler 引用它（接口清单里不存在这个入口）；
//   - 生产环境由调用方拒绝，见 `cmd/seed` 的 -force 判断与显式警告。
//
// 返回值 created 表示这次是否真的建了号，便于脚本汇报"新建 N 个、已存在 M 个"。
func (s *Service) EnsureSeedUser(ctx context.Context, in SeedUserInput) (userID string, created bool, err error) {
	email, err := validate.Email(in.Email)
	if err != nil {
		return "", false, err
	}

	// 已存在：按需重设密码后返回，不重复建号（种子脚本要能反复执行）。
	if u, qErr := s.client.User.Query().Where(user.EmailEQ(email)).Only(ctx); qErr == nil {
		if in.ResetPassword {
			hash, hErr := password.Hash(in.Password)
			if hErr != nil {
				return "", false, apperr.ErrInvalidParam.WithMessage("密码不可用：%v", hErr)
			}
			if _, uErr := s.client.User.UpdateOneID(u.ID).
				SetPasswordHash(hash).Save(ctx); uErr != nil {
				return "", false, apperr.ErrDependency.WithCause(uErr)
			}
		}
		return u.ID, false, nil
	} else if !ent.IsNotFound(qErr) {
		return "", false, apperr.ErrDependency.WithCause(qErr)
	}

	hash, err := password.Hash(in.Password)
	if err != nil {
		return "", false, apperr.ErrInvalidParam.WithMessage("密码不可用：%v", err)
	}

	// 昵称为空时用邮箱，省得调用方每次都要编一个。
	nickname := in.Nickname
	if nickname == "" {
		nickname = email
	}
	u, err := s.createUser(ctx, email, nickname, hash, "127.0.0.1")
	if err != nil {
		return "", false, err
	}
	return u.ID, true, nil
}

// AlignSeedNickname 把种子账号的昵称对齐成期望值（不一致才改）。
//
// 为什么需要它：种子账号的邮箱是固定的，但昵称可能被上一轮种子、
// 或早期手工测试改过。不对齐就会出现两种坏情况：
//   - 想给运营用的昵称被某个旧的种子账号占着，导致**后面所有账号都建不出来**；
//   - 文档说"管理员叫超级管理员"，实际列表里是另一个名字，看的人一头雾水。
//
// 冲突时**不报错**：返回 false 表示"改不动，保留原昵称"，由调用方提示。
// 种子命令不该因为一个昵称就被整体中断。
func (s *Service) AlignSeedNickname(ctx context.Context, userID, want string) (bool, error) {
	if want == "" {
		return true, nil
	}
	u, err := s.client.User.Get(ctx, userID)
	if err != nil {
		return false, apperr.ErrDependency.WithCause(err)
	}
	if u.Nickname == want {
		return true, nil
	}
	if _, err := s.client.User.UpdateOneID(userID).SetNickname(want).Save(ctx); err != nil {
		if ent.IsConstraintError(err) {
			return false, nil // 被别人占着，保留原名
		}
		return false, apperr.ErrDependency.WithCause(err)
	}
	return true, nil
}

// EnsureSeedRole 直接为种子账号绑定角色（含 Casbin）。
//
// 与 `admin.SetRole` 的分工：那条是**运营操作**，会写审计并撤销会话；
// 这里是建号时的初始角色，没有"操作者"，因此不写审计。
//
// 之所以仍然放在 auth 而不是让种子脚本自己改两处（users.role + Casbin），
// 是因为"数据库里的角色"与"Casbin 里的绑定"必须同时改：
// 只改前者，账号看起来是管理员但没有任何权限（表现为满屏 403）；
// 只改后者，则是权限在但角色显示不对。这种"两个真相"最容易在脚本里漏掉一半。
func (s *Service) EnsureSeedRole(ctx context.Context, userID string, role catalog.Role) error {
	switch role {
	case catalog.RolePlayer, catalog.RoleOperator, catalog.RoleAdmin:
	default:
		return apperr.ErrInvalidParam.WithMessage("未知角色 %q", role)
	}
	if _, err := s.client.User.UpdateOneID(userID).SetRole(string(role)).Save(ctx); err != nil {
		if ent.IsNotFound(err) {
			return apperr.ErrAccountNotFound
		}
		return apperr.ErrDependency.WithCause(err)
	}
	if s.roles != nil {
		if err := s.roles.AssignRole(userID, role); err != nil {
			return err
		}
	}
	// 会话里缓存了角色快照，改了角色就必须撤销，否则降权要等令牌过期才生效。
	if err := s.sessions.UpdateRole(ctx, userID, role); err != nil {
		return err
	}
	return nil
}
