<#
.SYNOPSIS
    狂欢斗地主服务端端到端冒烟脚本。

.DESCRIPTION
    按"真实玩家会走的顺序"把核心链路走一遍：健康检查 -> 拿验证码 -> 注册/登录
    -> 读档案 -> 领活动奖励 -> 买商品 -> 看榜单 -> 匹配 -> 退出匹配。

    每一步都打印 PASS / FAIL / SKIP，遇到硬失败立刻退出（返回非零码），
    因此可以直接挂在 CI 或发布流程里当"冒烟门禁"。

    关于 SKIP：脚本**宁可跳过也不猜测**。凡是不能从当前代码确认的接口，
    都会打印 SKIP 与原因，而不是编一个路径去请求 ——
    一个撒谎的冒烟脚本比没有冒烟脚本更危险。

.PARAMETER BaseUrl
    服务端地址，默认 http://127.0.0.1:8080。

.PARAMETER Email
    用于冒烟的邮箱。默认带时间戳，保证每次都是新账号（因此会走注册路径）。

.PARAMETER SkipMatch
    跳过匹配环节。默认会尝试匹配一次；单实例、无第二名玩家时，
    匹配会停在队列里（12 秒后由机器人补位），这一步用 -SkipMatch 可以省时间。

.EXAMPLE
    pwsh -File scripts/smoke.ps1

.EXAMPLE
    pwsh -File scripts/smoke.ps1 -BaseUrl http://10.0.0.5:8080 -SkipMatch
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Email = "",
    [switch]$SkipMatch
)

$ErrorActionPreference = "Stop"

# 统一用 UTF-8 输出，否则 Windows PowerShell 会把中文打成乱码。
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

$script:Failed = 0
$script:Passed = 0
$script:Skipped = 0

function Write-Step {
    param([string]$Name, [string]$Status, [string]$Detail = "")
    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "SKIP" { "Yellow" }
        default { "Gray" }
    }
    $line = "{0,-4} {1}" -f $Status, $Name
    if ($Detail) { $line += "  —— $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Fail-AndExit {
    param([string]$Name, [string]$Reason)
    Write-Step -Name $Name -Status "FAIL" -Detail $Reason
    Write-Host ""
    Write-Host "冒烟失败。提示：若服务端跑在 prod 模式，验证码不会返回（data.dev_code 为空），" -ForegroundColor Yellow
    Write-Host "此时请改用 CL_APP_ENV=dev，或直接从服务端日志里取验证码后手工验证。" -ForegroundColor Yellow
    exit 1
}

function Invoke-Api {
    <#
      统一的请求封装。返回值一定是解包后的哈希表：
        @{ code = <int>; message = <string>; data = <object>; status = <http 状态码> }
      网络层错误会被转成 code = -1，交给调用方判定，避免到处写 try/catch。
    #>
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $uri = "$BaseUrl$Path"
    $headers = @{ "Accept" = "application/json" }
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }

    $params = @{ Method = $Method; Uri = $uri; Headers = $headers; TimeoutSec = 30 }
    if ($null -ne $Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 8 -Compress)
        $params["ContentType"] = "application/json; charset=utf-8"
    }

    try {
        $resp = Invoke-WebRequest @params -UseBasicParsing
        $json = $resp.Content | ConvertFrom-Json
        return @{
            code    = [int]$json.code
            message = [string]$json.message
            data    = $json.data
            status  = [int]$resp.StatusCode
        }
    }
    catch {
        $status = 0
        $content = $null
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = 0 }
        }
        # ErrorDetails.Message 是 PowerShell 为 HTTP 错误响应体填充的原始文本，
        # 比自己去 GetResponseStream 更可靠：后者在响应已被释放时会抛异常，
        # 于是 code 永远读成 -1，看起来像"服务端根本没返回错误码"。
        $raw = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $raw = $_.ErrorDetails.Message
        }
        if ($raw) {
            try { $content = $raw | ConvertFrom-Json } catch { $content = $null }
        }
        if ($null -ne $content) {
            return @{
                code    = [int]$content.code
                message = [string]$content.message
                data    = $content.data
                status  = $status
            }
        }
        return @{ code = -1; message = $_.Exception.Message; data = $null; status = $status }
    }
}

if (-not $Email) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    $Email = "smoke+$stamp@example.com"
}

Write-Host ""
Write-Host "=== 狂欢斗地主 服务端冒烟 ===" -ForegroundColor Cyan
Write-Host "目标: $BaseUrl"
Write-Host "邮箱: $Email"
Write-Host ""

# ---------------------------------------------------------------- 1. 健康检查
# 探针接口刻意**不使用业务响应信封**（它回答的是"进程活着吗"，
# 而不是"这次业务调用成功了吗"），因此这里直接取原始 JSON。
$probeOk = $false
$probeDetail = ""
try {
    $probeRaw = Invoke-WebRequest -Method GET -Uri "$BaseUrl/healthz" -UseBasicParsing -TimeoutSec 15
    if ($probeRaw.StatusCode -eq 200) {
        $probeOk = $true
        $probeJson = $probeRaw.Content | ConvertFrom-Json
        $probeDetail = "service=$($probeJson.service) version=$($probeJson.version)"
    }
} catch {
    $probeDetail = $_.Exception.Message
}
if (-not $probeOk) {
    Fail-AndExit -Name "健康检查 /healthz" -Reason "无法连接到 $BaseUrl（$probeDetail）。请先 make compose-up 或 make run。"
}
Write-Step -Name "健康检查 /healthz" -Status "PASS" -Detail $probeDetail
$script:Passed++

# 就绪检查会逐个探 PostgreSQL / Redis / Casbin —— 一份体检报告比"活着"有用得多。
try {
    $readyRaw = Invoke-WebRequest -Method GET -Uri "$BaseUrl/readyz" -UseBasicParsing -TimeoutSec 15
    $readyJson = $readyRaw.Content | ConvertFrom-Json
    Write-Step -Name "就绪检查 /readyz" -Status "PASS" `
        -Detail "postgres=$($readyJson.checks.postgres) redis=$($readyJson.checks.redis) casbin=$($readyJson.checks.casbin)"
    $script:Passed++
} catch {
    Write-Step -Name "就绪检查 /readyz" -Status "FAIL" -Detail $_.Exception.Message
    $script:Failed++
}

# ---------------------------------------------------------------- 2. 发验证码
$codeResp = Invoke-Api -Method POST -Path "/api/v1/auth/code" -Body @{ email = $Email; purpose = "login" }
if ($codeResp.code -ne 0) {
    Fail-AndExit -Name "发送验证码" -Reason "code=$($codeResp.code) message=$($codeResp.message)"
}
$devCode = [string]$codeResp.data.dev_code
if (-not $devCode) {
    Fail-AndExit -Name "发送验证码" -Reason "服务端没有返回 data.dev_code（说明跑在非 dev 模式），无法继续自动化验证"
}
Write-Step -Name "发送验证码" -Status "PASS" -Detail "dev_code=$devCode（有效期 $($codeResp.data.expires_in) 秒）"
$script:Passed++

# ---------------------------------------------------------------- 3. 验证码登录（自动注册）
$login = Invoke-Api -Method POST -Path "/api/v1/auth/login/code" -Body @{ email = $Email; code = $devCode }
if ($login.code -ne 0) {
    Fail-AndExit -Name "验证码登录" -Reason "code=$($login.code) message=$($login.message)"
}
$accessToken = [string]$login.data.tokens.access_token
$refreshToken = [string]$login.data.tokens.refresh_token
if (-not $accessToken) {
    Fail-AndExit -Name "验证码登录" -Reason "响应里没有 data.tokens.access_token"
}
$isNew = [bool]$login.data.is_new_user
Write-Step -Name "验证码登录" -Status "PASS" -Detail "新账号=$isNew 昵称=$($login.data.profile.nickname)"
$script:Passed++

# ---------------------------------------------------------------- 4. 刷新令牌
$refresh = Invoke-Api -Method POST -Path "/api/v1/auth/refresh" -Body @{ refresh_token = $refreshToken }
if ($refresh.code -ne 0) {
    # 刷新失败不致命（主流程用 access_token 也能走完），但值得报出来。
    Write-Step -Name "刷新令牌" -Status "FAIL" -Detail "code=$($refresh.code) message=$($refresh.message)"
    $script:Failed++
} else {
    Write-Step -Name "刷新令牌" -Status "PASS" -Detail "已换发新令牌"
    $script:Passed++
    $accessToken = [string]$refresh.data.tokens.access_token
}

# ---------------------------------------------------------------- 5. 读取档案与钱包
$me = Invoke-Api -Method GET -Path "/api/v1/user/me" -Token $accessToken
if ($me.code -ne 0) {
    Fail-AndExit -Name "读取档案 /user/me" -Reason "code=$($me.code) message=$($me.message)"
}
$goldBefore = [int64]$me.data.wallet.gold
$diamondBefore = [int64]$me.data.wallet.diamond
Write-Step -Name "读取档案 /user/me" -Status "PASS" -Detail "等级=$($me.data.progress.level) 金币=$goldBefore 钻石=$diamondBefore"
$script:Passed++

# ---------------------------------------------------------------- 6. 活动总览
$overview = Invoke-Api -Method GET -Path "/api/v1/activity/overview" -Token $accessToken
if ($overview.code -ne 0) {
    Write-Step -Name "活动总览 /activity/overview" -Status "FAIL" -Detail "code=$($overview.code) message=$($overview.message)"
    $script:Failed++
} else {
    $taskCount = @($overview.data.daily_tasks).Count
    $achCount = @($overview.data.achievements).Count
    Write-Step -Name "活动总览 /activity/overview" -Status "PASS" -Detail "每日任务=$taskCount 成就=$achCount 今日已签到=$($overview.data.sign_in.signed_today)"
    $script:Passed++
}

# ---------------------------------------------------------------- 7. 签到
$signIn = Invoke-Api -Method POST -Path "/api/v1/activity/sign-in" -Token $accessToken
if ($signIn.code -eq 0) {
    Write-Step -Name "每日签到" -Status "PASS" -Detail "第 $($signIn.data.day_index) 天，获得 $((@($signIn.data.rewards) | ForEach-Object { $_.label }) -join '、')"
    $script:Passed++
} elseif ($signIn.code -eq 50004) {
    # 今天已经签过了：这是正常的业务分支，不算失败。
    Write-Step -Name "每日签到" -Status "PASS" -Detail "今日已签到（幂等分支）"
    $script:Passed++
} else {
    Write-Step -Name "每日签到" -Status "FAIL" -Detail "code=$($signIn.code) message=$($signIn.message)"
    $script:Failed++
}

# ---------------------------------------------------------------- 8. 钻石直购（金币礼包）
# gold_100k 售价 6 钻石；新账号有 30 钻石，因此这一单必然能成。
$buy = Invoke-Api -Method POST -Path "/api/v1/shop/purchase" -Token $accessToken `
    -Body @{ good_id = "gold_100k"; idempotency_key = "smoke-$Email-gold100k" }
if ($buy.code -ne 0) {
    Write-Step -Name "购买金币礼包" -Status "FAIL" -Detail "code=$($buy.code) message=$($buy.message)"
    $script:Failed++
} else {
    $goldAfter = [int64]$buy.data.balances.gold
    Write-Step -Name "购买金币礼包" -Status "PASS" -Detail "金币 $goldBefore -> $goldAfter（订单 $($buy.data.order.id)）"
    $script:Passed++

    # 幂等验证：同一个幂等键再买一次，余额必须不变。
    $buyAgain = Invoke-Api -Method POST -Path "/api/v1/shop/purchase" -Token $accessToken `
        -Body @{ good_id = "gold_100k"; idempotency_key = "smoke-$Email-gold100k" }
    if ($buyAgain.code -eq 0 -and [int64]$buyAgain.data.balances.gold -eq $goldAfter) {
        Write-Step -Name "购买幂等（同幂等键重放）" -Status "PASS" -Detail "余额保持不变：$goldAfter"
        $script:Passed++
    } else {
        Write-Step -Name "购买幂等（同幂等键重放）" -Status "FAIL" `
            -Detail "余额被重复扣/加：$goldAfter -> $([int64]$buyAgain.data.balances.gold)"
        $script:Failed++
    }
}

# ---------------------------------------------------------------- 9. 背包与权益
$props = Invoke-Api -Method GET -Path "/api/v1/user/me/props" -Token $accessToken
if ($props.code -ne 0) {
    Write-Step -Name "背包 /user/me/props" -Status "FAIL" -Detail "code=$($props.code) message=$($props.message)"
    $script:Failed++
} else {
    Write-Step -Name "背包 /user/me/props" -Status "PASS" -Detail "记牌器=$($props.data.entitlements.card_counter) 提示符=$($props.data.entitlements.hint_count)"
    $script:Passed++
}

# ---------------------------------------------------------------- 10. 榜单
$rank = Invoke-Api -Method GET -Path "/api/v1/rank/points/top?limit=5"
if ($rank.code -ne 0) {
    Write-Step -Name "积分榜 /rank/points/top" -Status "FAIL" -Detail "code=$($rank.code) message=$($rank.message)"
    $script:Failed++
} else {
    Write-Step -Name "积分榜 /rank/points/top" -Status "PASS" -Detail "返回 $(@($rank.data.items).Count) 条"
    $script:Passed++
}

# ---------------------------------------------------------------- 11. 账单流水
$tx = Invoke-Api -Method GET -Path "/api/v1/user/me/wallet/transactions?page=1&page_size=10" -Token $accessToken
if ($tx.code -ne 0) {
    Write-Step -Name "账单流水" -Status "FAIL" -Detail "code=$($tx.code) message=$($tx.message)"
    $script:Failed++
} else {
    Write-Step -Name "账单流水" -Status "PASS" -Detail "累计 $($tx.data.total) 条（本页 $(@($tx.data.items).Count) 条）"
    $script:Passed++
}

# ---------------------------------------------------------------- 12. 邮箱
$mailList = Invoke-Api -Method GET -Path "/api/v1/mail?page=1&page_size=10" -Token $accessToken
if ($mailList.code -ne 0) {
    Write-Step -Name "邮箱列表 /mail" -Status "FAIL" -Detail "code=$($mailList.code) message=$($mailList.message)"
    $script:Failed++
} else {
    Write-Step -Name "邮箱列表 /mail" -Status "PASS" -Detail "未读 $((Invoke-Api -Method GET -Path '/api/v1/mail/unread-count' -Token $accessToken).data.unread)"
    $script:Passed++
}

# ---------------------------------------------------------------- 13. 匹配
if ($SkipMatch) {
    Write-Step -Name "对局匹配" -Status "SKIP" -Detail "已指定 -SkipMatch"
    $script:Skipped++
} else {
    $match = Invoke-Api -Method POST -Path "/api/v1/game/match" -Token $accessToken -Body @{ mode_id = "mode_classic" }
    if ($match.code -ne 0) {
        Write-Step -Name "对局匹配" -Status "FAIL" -Detail "code=$($match.code) message=$($match.message)"
        $script:Failed++
    } else {
        Write-Step -Name "对局匹配" -Status "PASS" -Detail "状态=$($match.data.status) 队列位置=$($match.data.position)"
        $script:Passed++

        # 匹配成功后房间由 WebSocket 推送；这里只验证"能取消"这条 HTTP 路径。
        $cancel = Invoke-Api -Method POST -Path "/api/v1/game/match/cancel" -Token $accessToken
        if ($cancel.code -eq 0) {
            Write-Step -Name "取消匹配" -Status "PASS" -Detail "status=$($cancel.data.status)"
            $script:Passed++
        } else {
            Write-Step -Name "取消匹配" -Status "FAIL" -Detail "code=$($cancel.code) message=$($cancel.message)"
            $script:Failed++
        }
    }
}

# ---------------------------------------------------------------- 14. 登出
$logout = Invoke-Api -Method POST -Path "/api/v1/auth/logout" -Token $accessToken
if ($logout.code -eq 0) {
    Write-Step -Name "登出" -Status "PASS" -Detail "会话已销毁"
    $script:Passed++
} else {
    Write-Step -Name "登出" -Status "FAIL" -Detail "code=$($logout.code) message=$($logout.message)"
    $script:Failed++
}

# 登出后 access_token 必须失效（会话在 Redis 里，因此是立刻生效的）。
$afterLogout = Invoke-Api -Method GET -Path "/api/v1/user/me" -Token $accessToken
if ($afterLogout.status -eq 401 -or $afterLogout.code -eq 20003 -or $afterLogout.code -eq 20001) {
    Write-Step -Name "登出后令牌失效" -Status "PASS" -Detail "code=$($afterLogout.code)"
    $script:Passed++
} else {
    Write-Step -Name "登出后令牌失效" -Status "FAIL" -Detail "仍然可用（code=$($afterLogout.code)），会话撤销可能没生效"
    $script:Failed++
}

# ---------------------------------------------------------------- 汇总
Write-Host ""
Write-Host "=== 冒烟结果：PASS $script:Passed / FAIL $script:Failed / SKIP $script:Skipped ===" -ForegroundColor Cyan
if ($script:Failed -gt 0) {
    exit 1
}
Write-Host "全部通过。" -ForegroundColor Green
exit 0
