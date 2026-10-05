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
    Write-Host "冒烟失败。提示：若服务端跑在 prod 模式，验证码不会返回（body.dev_code 为空），" -ForegroundColor Yellow
    Write-Host "此时请改用 CL_APP_ENV=dev，或直接从服务端日志里取验证码后手工验证。" -ForegroundColor Yellow
    exit 1
}

function Invoke-Api {
    <#
      统一的请求封装。返回值一定是解包后的哈希表：
        @{ code = <int>; message = <string>; body = <object>; status = <http 状态码> }
      网络层错误会被转成 code = -1，交给调用方判定，避免到处写 try/catch。

      注意 `body` 对应服务端信封里的 `body` 字段（决策 D-01，早期叫 `data`）。
      这里跟随改名而不是保留旧名：中间多一层同义词映射，
      会让"响应里到底叫什么"这件事在两个地方各说一套。
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
            body    = $json.body
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
                body    = $content.body
                status  = $status
            }
        }
        return @{ code = -1; message = $_.Exception.Message; body = $null; status = $status }
    }
}

# Test-ClientUlid 复刻客户端 `apps/client/src/core/ulid.gd` 的 Ulid.is_valid()：
# 长度必须恰好 26，且每个字符都落在 Crockford 字母表内（没有 I / L / O / U，也没有下划线）。
#
# 为什么冒烟要单独验这一条：服务端早期用 `ord_` / `room_` 之类前缀生成 ID，
# 长度 30 且含下划线，**一定过不了客户端这个校验**；而客户端把校验失败当作"ID 非法"，
# 会触发兜底或按未登录处理，表现在玩家侧是资产挂错、莫名要求重登，
# 而服务端日志与存档看起来都完全正常 —— 属于最难排查的一类问题。
# 所以在真实响应上跑一遍同款校验，比只信单元测试更让人放心。
function Test-ClientUlid {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value) -or $Value.Length -ne 26) { return $false }
    $alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    foreach ($ch in $Value.ToCharArray()) {
        if ($alphabet.IndexOf($ch) -lt 0) { return $false }
    }
    return $true
}

# New-Ulid 生成一个合法的 26 位 ULID（与服务端 id.New / 客户端 Ulid.generate 同构）。
#
# 冒烟只需要"形状合法"，因此按 48 位毫秒时间戳 + 80 位随机数拼出来即可。
# 用 5 位一组手工编码而不是引入依赖：这段逻辑本身就是被验证对象的一部分，
# 借助第三方库反而看不出两端字母表是否一致。
function New-Ulid {
    $alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    $sb = New-Object System.Text.StringBuilder

    $ms = [int64][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    for ($i = 9; $i -ge 0; $i--) {
        [void]$sb.Append($alphabet[[int](($ms -shr ($i * 5)) -band 31)])
    }

    $bytes = New-Object byte[] 10
    # 用 Create() + GetBytes 而不是 .NET Core 才有的 RandomNumberGenerator::Fill：
    # 后者在 Windows PowerShell 5.1（.NET Framework）上不存在，会让脚本在旧宿主下报错。
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }

    for ($c = 0; $c -lt 16; $c++) {
        $value = 0
        for ($b = 0; $b -lt 5; $b++) {
            $pos = ($c * 5) + $b
            $byteIndex = [int][Math]::Floor($pos / 8)
            $bitIndex = 7 - ($pos % 8)
            $bit = 0
            if ($byteIndex -lt $bytes.Length) { $bit = ($bytes[$byteIndex] -shr $bitIndex) -band 1 }
            $value = (($value -shl 1) -bor $bit)
        }
        [void]$sb.Append($alphabet[$value])
    }
    return $sb.ToString()
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
    Fail-AndExit -Name "健康检查 /healthz" -Reason "无法连接到 $BaseUrl（$probeDetail）。请先 make compose-up（整套容器），或 make dev（只起 PG/Redis + 本机 API）；两者都占用 8080，不要同时运行。"
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

# ---------------------------------------------------------------- 1b. 信封字段名（决策 D-01）
# 业务响应必须是 `{code, message, body, request_id}`。
# 这里**同时断言 `data` 不存在**：D-01 明确要求不要为了兼容而同时输出两个字段 ——
# 那会让每个响应体翻倍，并且"到底该读哪个"会变成永久的技术债。
# 客户端契约（apps/client/docs/server-api-catalog.json）从一开始写的就是 `body`。
$envelopeOK = $false
$envelopeDetail = ""
try {
    $envRaw = Invoke-WebRequest -Method GET -Uri "$BaseUrl/api/v1/config/version" -UseBasicParsing -TimeoutSec 15
    $envJson = $envRaw.Content | ConvertFrom-Json
    $hasBody = $null -ne $envJson.PSObject.Properties['body']
    $hasData = $null -ne $envJson.PSObject.Properties['data']
    $hasReqID = $null -ne $envJson.PSObject.Properties['request_id']
    if ($hasBody -and -not $hasData -and $hasReqID) {
        $envelopeOK = $true
        $envelopeDetail = "字段为 code/message/body/request_id，且未同时输出 data"
    } else {
        $envelopeDetail = "body=$hasBody data=$hasData request_id=$hasReqID（期望 body=True data=False request_id=True）"
    }
} catch {
    $envelopeDetail = $_.Exception.Message
}
if ($envelopeOK) {
    Write-Step -Name "响应信封字段名（body，无 data）" -Status "PASS" -Detail $envelopeDetail
    $script:Passed++
} else {
    Write-Step -Name "响应信封字段名（body，无 data）" -Status "FAIL" -Detail $envelopeDetail
    $script:Failed++
}

# ---------------------------------------------------------------- 1c. 配置下发（CFG 系列）
# 客户端**启动时还没有令牌**，所以配置必须在登录前就能匿名拿到。
# 这里也顺带验证分类接口与 bootstrap 的版本号一致 —— 不一致会让客户端
# 反复重拉，或者该更新时不更新。
$configOK = $false
$configDetail = ""
try {
    $boot = Invoke-WebRequest -Method GET -Uri "$BaseUrl/api/v1/config/bootstrap" -UseBasicParsing -TimeoutSec 15
    $bootJson = ($boot.Content | ConvertFrom-Json).body
    $skinsResp = Invoke-Api -Method GET -Path "/api/v1/config/skins"
    $actResp = Invoke-Api -Method GET -Path "/api/v1/config/activities"
    $achvResp = Invoke-Api -Method GET -Path "/api/v1/config/achievements"

    $v = [string]$bootJson.config_version
    $sameVersion = ([string]$skinsResp.body.config_version -eq $v) -and
                   ([string]$actResp.body.config_version -eq $v) -and
                   ([string]$achvResp.body.config_version -eq $v)
    # 分类接口的内容必须与 bootstrap 同源（两份数据源会漂移）
    $sameSkins = (@($bootJson.skins).Count -eq @($skinsResp.body.items).Count)
    $sameAchievements = (@($bootJson.achievements).Count -eq @($achvResp.body.items).Count)

    if ($v -and $sameVersion -and $sameSkins -and $sameAchievements) {
        $configOK = $true
        $configDetail = "版本=$v 皮肤 $($skinsResp.body.items.Count) 项 成就 $($achvResp.body.items.Count) 项（分类接口同版本同源）"
    } else {
        $configDetail = "版本=$v 同版本=$sameVersion 皮肤同源=$sameSkins 成就同源=$sameAchievements"
    }
} catch {
    $configDetail = $_.Exception.Message
}
if ($configOK) {
    Write-Step -Name "配置下发（匿名 + 版本号一致）" -Status "PASS" -Detail $configDetail
    $script:Passed++
} else {
    Write-Step -Name "配置下发（匿名 + 版本号一致）" -Status "FAIL" -Detail $configDetail
    $script:Failed++
}

# ---------------------------------------------------------------- 2. 发验证码
$codeResp = Invoke-Api -Method POST -Path "/api/v1/auth/code" -Body @{ email = $Email; purpose = "login" }
if ($codeResp.code -ne 0) {
    Fail-AndExit -Name "发送验证码" -Reason "code=$($codeResp.code) message=$($codeResp.message)"
}
$devCode = [string]$codeResp.body.dev_code
if (-not $devCode) {
    Fail-AndExit -Name "发送验证码" -Reason "服务端没有返回 body.dev_code（说明跑在非 dev 模式），无法继续自动化验证"
}
Write-Step -Name "发送验证码" -Status "PASS" -Detail "dev_code=$devCode（有效期 $($codeResp.body.expires_in) 秒）"
$script:Passed++

# ---------------------------------------------------------------- 3. 验证码登录（自动注册）
$login = Invoke-Api -Method POST -Path "/api/v1/auth/login/code" -Body @{ email = $Email; code = $devCode }
if ($login.code -ne 0) {
    Fail-AndExit -Name "验证码登录" -Reason "code=$($login.code) message=$($login.message)"
}
$accessToken = [string]$login.body.tokens.access_token
$refreshToken = [string]$login.body.tokens.refresh_token
if (-not $accessToken) {
    Fail-AndExit -Name "验证码登录" -Reason "响应里没有 body.tokens.access_token"
}
$isNew = [bool]$login.body.is_new_user
Write-Step -Name "验证码登录" -Status "PASS" -Detail "新账号=$isNew 昵称=$($login.body.profile.nickname)"
$script:Passed++

# ---------------------------------------------------------------- 3b. 设备凭证 game_token（D-09）
# 三件套里的第三件：长期设备凭证，让客户端下次启动跳过登录页。
# 这里验证四件事：签发、能换回同一身份与可用会话、伪造被拒、access token 不能冒充它。
$gameToken = [string]$login.body.game_token.token
$deviceID = [string]$login.body.device_id
if (-not $gameToken) {
    Fail-AndExit -Name "设备凭证 game_token" -Reason "登录响应里没有 body.game_token.token"
}
$gameTTL = [int64]$login.body.game_token.expires_in
if ($gameTTL -gt (330 * 24 * 3600) -and $deviceID) {
    Write-Step -Name "签发设备凭证 game_token" -Status "PASS" `
        -Detail ("设备 {0} 有效期 {1} 天（长期凭证，可吊销）" -f $deviceID, [int][Math]::Round($gameTTL / 86400))
    $script:Passed++
} else {
    Write-Step -Name "签发设备凭证 game_token" -Status "FAIL" `
        -Detail "expires_in=$gameTTL（期望一年量级） device_id=$deviceID"
    $script:Failed++
}

# 用设备凭证静默换回会话：**不带任何 Authorization 头**，这正是"免重登"的场景。
$verify = Invoke-Api -Method POST -Path "/api/v1/auth/verify" -Body @{ game_token = $gameToken }
if ($verify.code -ne 0) {
    Write-Step -Name "设备凭证换会话 /auth/verify" -Status "FAIL" -Detail "code=$($verify.code) message=$($verify.message)"
    $script:Failed++
} else {
    # 关键不止"返回了身份"，而是换回来的 access token **真的能用**：
    # 否则客户端只是拿到一个好看的 user_id，后续接口照样全部 401。
    $silentToken = [string]$verify.body.tokens.access_token
    $probe = Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $silentToken
    $sameUser = ([string]$verify.body.user_id -eq [string]$login.body.profile.id)
    if ($sameUser -and $probe.code -eq 0 -and [string]$verify.body.device_id -eq $deviceID) {
        Write-Step -Name "设备凭证换会话 /auth/verify" -Status "PASS" `
            -Detail "同一账号（$($verify.body.user_id)），换回的 access token 可用"
        $script:Passed++
    } else {
        Write-Step -Name "设备凭证换会话 /auth/verify" -Status "FAIL" `
            -Detail "同一账号=$sameUser 探测 code=$($probe.code) device=$($verify.body.device_id)"
        $script:Failed++
    }
}

# 伪造的凭证必须被拒（HMAC 完整性）
$forged = $gameToken.Substring(0, $gameToken.Length - 1) + $(if ($gameToken.EndsWith("A")) { "B" } else { "A" })
$forgedResp = Invoke-Api -Method POST -Path "/api/v1/auth/verify" -Body @{ game_token = $forged }
if ($forgedResp.code -ne 0) {
    Write-Step -Name "拒绝伪造的设备凭证" -Status "PASS" -Detail "code=$($forgedResp.code)"
    $script:Passed++
} else {
    Write-Step -Name "拒绝伪造的设备凭证" -Status "FAIL" -Detail "篡改后的凭证竟然通过了校验"
    $script:Failed++
}

# access token 不能当设备凭证用（audience 隔离）——
# 否则一枚泄漏的长期凭证就能直接调所有业务接口，而不是只能换一次会话。
$crossResp = Invoke-Api -Method POST -Path "/api/v1/auth/verify" -Body @{ game_token = $accessToken }
if ($crossResp.code -ne 0) {
    Write-Step -Name "设备凭证与访问令牌相互隔离" -Status "PASS" -Detail "code=$($crossResp.code)"
    $script:Passed++
} else {
    Write-Step -Name "设备凭证与访问令牌相互隔离" -Status "FAIL" -Detail "access token 被当成了设备凭证"
    $script:Failed++
}

# ---------------------------------------------------------------- 3c. WebSocket 帧字段名
# 连一次**真实** WS，读第一帧（hello），确认消息体字段是 body 而不是 data。
#
# 为什么值得单列一步：WS 帧字段名错了不会有任何编译或运行时报错 ——
# 服务端照常发，客户端 quietly 读不到消息体，表现是"连上了但界面不动"。
# 只靠结构体序列化的单测不足以覆盖"实际发出去的那一帧长什么样"。
function Get-WsFirstFrame {
    param([string]$Url, [int]$TimeoutMs = 10000)
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        # 用 Task.Wait + .Result 而**不是** GetAwaiter().GetResult()：
        # 后者在 PowerShell 里会把 .NET 内部的 VoidTaskResult 当成输出对象吐出来，
        # 于是本函数的"返回值"变成字符串 "System.Threading.Tasks.VoidTaskResult"，
        # ConvertFrom-Json 随即报"无效的 JSON 基元"。这是只在 PowerShell 里会踩到的坑。
        $connectTask = $ws.ConnectAsync([Uri]$Url, [System.Threading.CancellationToken]::None)
        if (-not $connectTask.Wait($TimeoutMs)) { throw "WebSocket 连接超时（${TimeoutMs}ms）" }

        $buf = New-Object byte[] 16384
        $seg = [System.ArraySegment[byte]]::new($buf)
        $recvTask = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        if (-not $recvTask.Wait($TimeoutMs)) { throw "WebSocket 接收首帧超时（${TimeoutMs}ms）" }
        $res = $recvTask.Result

        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
    } finally {
        try { $ws.Dispose() } catch { }
    }
}

$wsUrl = ($BaseUrl -replace '^http', 'ws') + "/api/v1/ws/game?token=$accessToken"
try {
    $frameText = Get-WsFirstFrame -Url $wsUrl
    $frame = $frameText | ConvertFrom-Json
    $frameHasBody = $null -ne $frame.PSObject.Properties['body']
    $frameHasData = $null -ne $frame.PSObject.Properties['data']
    if ($frameHasBody -and -not $frameHasData -and [string]$frame.type -eq 'hello') {
        Write-Step -Name "WebSocket 帧字段名（body，无 data）" -Status "PASS" `
            -Detail "首帧 type=hello，消息体字段为 body 且未输出 data"
        $script:Passed++
    } else {
        Write-Step -Name "WebSocket 帧字段名（body，无 data）" -Status "FAIL" `
            -Detail "type=$($frame.type) body=$frameHasBody data=$frameHasData"
        $script:Failed++
    }
} catch {
    Write-Step -Name "WebSocket 帧字段名（body，无 data）" -Status "FAIL" -Detail "WS 连接或接收失败：$($_.Exception.Message)"
    $script:Failed++
}

# ---------------------------------------------------------------- 4. 刷新令牌
$refresh = Invoke-Api -Method POST -Path "/api/v1/auth/refresh" -Body @{ refresh_token = $refreshToken }
if ($refresh.code -ne 0) {
    # 刷新失败不致命（主流程用 access_token 也能走完），但值得报出来。
    Write-Step -Name "刷新令牌" -Status "FAIL" -Detail "code=$($refresh.code) message=$($refresh.message)"
    $script:Failed++
} else {
    Write-Step -Name "刷新令牌" -Status "PASS" -Detail "已换发新令牌"
    $script:Passed++
    $accessToken = [string]$refresh.body.tokens.access_token
}

# ---------------------------------------------------------------- 5. 读取档案与钱包
$me = Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken
if ($me.code -ne 0) {
    Fail-AndExit -Name "读取档案 /user/profile" -Reason "code=$($me.code) message=$($me.message)"
}
$goldBefore = [int64]$me.body.wallet.gold
$diamondBefore = [int64]$me.body.wallet.diamond
Write-Step -Name "读取档案 /user/profile" -Status "PASS" -Detail "等级=$($me.body.progress.level) 金币=$goldBefore 钻石=$diamondBefore"
$script:Passed++

# ---------------------------------------------------------------- 6. 活动总览
$overview = Invoke-Api -Method GET -Path "/api/v1/activity/center" -Token $accessToken
if ($overview.code -ne 0) {
    Write-Step -Name "活动总览 /activity/center" -Status "FAIL" -Detail "code=$($overview.code) message=$($overview.message)"
    $script:Failed++
} else {
    $taskCount = @($overview.body.daily_tasks).Count
    $achCount = @($overview.body.achievements).Count
    Write-Step -Name "活动总览 /activity/center" -Status "PASS" -Detail "每日任务=$taskCount 成就=$achCount 今日已签到=$($overview.body.sign_in.signed_today)"
    $script:Passed++
}

# ---------------------------------------------------------------- 7. 签到
$signIn = Invoke-Api -Method POST -Path "/api/v1/activity/checkin" -Token $accessToken
if ($signIn.code -eq 0) {
    Write-Step -Name "每日签到" -Status "PASS" -Detail "第 $($signIn.body.day_index) 天，获得 $((@($signIn.body.rewards) | ForEach-Object { $_.label }) -join '、')"
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
    $goldAfter = [int64]$buy.body.balances.gold
    Write-Step -Name "购买金币礼包" -Status "PASS" -Detail "金币 $goldBefore -> $goldAfter（订单 $($buy.body.order.id)）"
    $script:Passed++

    # ------------------------------------------------------------ 8b. 实体 ID 形态（D-04）
    # 服务端下发给客户端的实体 ID 必须是纯 ULID；见 Test-ClientUlid 的注释。
    $orderId = [string]$buy.body.order.id
    if (Test-ClientUlid -Value $orderId) {
        Write-Step -Name "实体 ID 形态（客户端同款校验）" -Status "PASS" -Detail "订单 ID 通过客户端 Ulid.is_valid：$orderId"
        $script:Passed++
    } else {
        Write-Step -Name "实体 ID 形态（客户端同款校验）" -Status "FAIL" -Detail "订单 ID 过不了客户端校验（长度 $($orderId.Length)）：$orderId"
        $script:Failed++
    }

    # 幂等验证：同一个幂等键再买一次，余额必须不变。
    $buyAgain = Invoke-Api -Method POST -Path "/api/v1/shop/purchase" -Token $accessToken `
        -Body @{ good_id = "gold_100k"; idempotency_key = "smoke-$Email-gold100k" }
    if ($buyAgain.code -eq 0 -and [int64]$buyAgain.body.balances.gold -eq $goldAfter) {
        Write-Step -Name "购买幂等（同幂等键重放）" -Status "PASS" -Detail "余额保持不变：$goldAfter"
        $script:Passed++
    } else {
        Write-Step -Name "购买幂等（同幂等键重放）" -Status "FAIL" `
            -Detail "余额被重复扣/加：$goldAfter -> $([int64]$buyAgain.body.balances.gold)"
        $script:Failed++
    }
}

# ---------------------------------------------------------------- 8b. 模拟充值（PAY 系列）
# 走一遍"档位 -> 下单 -> 支付 -> 到账"。这是**唯一动钱**的链路，必须端到端验。
# 本项目不对接任何真实现金支付，因此这里付的是模拟通道。
$pkgs = Invoke-Api -Method GET -Path "/api/v1/pay/packages" -Token $accessToken
$pkg = @($pkgs.body.packages) | Select-Object -First 1
if ($pkgs.code -ne 0 -or -not $pkg) {
    Write-Step -Name "充值档位 /pay/packages" -Status "FAIL" -Detail "code=$($pkgs.code) 档位数=$(@($pkgs.body.packages).Count)"
    $script:Failed++
} else {
    Write-Step -Name "充值档位 /pay/packages" -Status "PASS" -Detail "共 $(@($pkgs.body.packages).Count) 档，首档 $($pkg.name) 需付款=$($pkg.need_pay)"
    $script:Passed++

    $diaBefore = [int64](Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken).body.wallet.diamond

    $order = Invoke-Api -Method POST -Path "/api/v1/pay/order/create" -Token $accessToken `
        -Body @{ package_id = $pkg.id; idempotency_key = "smoke-$Email-$($pkg.id)" }
    if ($order.code -ne 0 -or -not $order.body.need_pay) {
        Write-Step -Name "创建充值订单 /pay/order/create" -Status "FAIL" -Detail "code=$($order.code) need_pay=$($order.body.need_pay)"
        $script:Failed++
    } else {
        $orderID = [string]$order.body.order.id
        Write-Step -Name "创建充值订单 /pay/order/create" -Status "PASS" -Detail "订单 $orderID 待支付 need_pay=true"
        $script:Passed++

        # 下单只是生成待支付订单，**不应该**先加钻石
        $diaMid = [int64](Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken).body.wallet.diamond
        if ($diaMid -eq $diaBefore) {
            Write-Step -Name "未支付不加钻石" -Status "PASS" -Detail "仍为 $diaMid"
            $script:Passed++
        } else {
            Write-Step -Name "未支付不加钻石" -Status "FAIL" -Detail "$diaBefore -> $diaMid（下单就发货了）"
            $script:Failed++
        }

        # 模拟支付
        $paid = Invoke-Api -Method POST -Path "/api/v1/pay/order/$orderID/mock-pay" -Token $accessToken
        $diaAfter = [int64](Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken).body.wallet.diamond
        if ($paid.code -eq 0 -and $diaAfter -eq ($diaBefore + [int64]$pkg.amount)) {
            Write-Step -Name "模拟支付到账" -Status "PASS" -Detail "钻石 $diaBefore -> $diaAfter（+$($pkg.amount)）"
            $script:Passed++
        } else {
            Write-Step -Name "模拟支付到账" -Status "FAIL" -Detail "code=$($paid.code) 钻石 $diaBefore -> $diaAfter（期望 +$($pkg.amount)）"
            $script:Failed++
        }

        # 订单列表里能看到它
        $payOrders = Invoke-Api -Method GET -Path "/api/v1/pay/order?page=1&page_size=20" -Token $accessToken
        $found = @($payOrders.body.items | Where-Object { $_.id -eq $orderID }).Count -eq 1
        if ($payOrders.code -eq 0 -and $found) {
            Write-Step -Name "支付订单列表 /pay/order" -Status "PASS" -Detail "共 $($payOrders.body.total) 单，含本单"
            $script:Passed++
        } else {
            Write-Step -Name "支付订单列表 /pay/order" -Status "FAIL" -Detail "code=$($payOrders.code) 命中=$found"
            $script:Failed++
        }
    }
}

# ---------------------------------------------------------------- 8c. 成就与改名卡
# 成就：列表与汇总必须出自同一份计算（汇总就是列表的统计，不该各算一遍）。
$achv = Invoke-Api -Method GET -Path "/api/v1/achievements" -Token $accessToken
$achvSum = Invoke-Api -Method GET -Path "/api/v1/achievements/summary" -Token $accessToken
if ($achv.code -eq 0 -and $achvSum.code -eq 0 -and
        $achvSum.body.total -eq @($achv.body.items).Count -and $achvSum.body.total -gt 0) {
    Write-Step -Name "成就 /achievements + /summary" -Status "PASS" `
        -Detail "共 $($achvSum.body.total) 项，已达成 $($achvSum.body.completed)，可领 $($achvSum.body.claimable)"
    $script:Passed++
} else {
    Write-Step -Name "成就 /achievements + /summary" -Status "FAIL" `
        -Detail "code=$($achv.code)/$($achvSum.code) 列表 $(@($achv.body.items).Count) 汇总 $($achvSum.body.total)"
    $script:Failed++
}

# 改名卡：买一张 -> 用掉 -> 昵称应变化；再用一次应因"未拥有"被拒。
$buyRename = Invoke-Api -Method POST -Path "/api/v1/shop/purchase" -Token $accessToken `
    -Body @{ good_id = "item_rename"; idempotency_key = "smoke-$Email-rename" }
if ($buyRename.code -ne 0) {
    Write-Step -Name "改名卡流程" -Status "FAIL" -Detail "购买失败 code=$($buyRename.code) message=$($buyRename.message)"
    $script:Failed++
} else {
    $newName = "改名" + (New-Ulid).Substring(20)
    $renamed = Invoke-Api -Method POST -Path "/api/v1/user/rename-card/use" -Token $accessToken -Body @{ nickname = $newName }
    $nickAfter = [string](Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken).body.nickname
    # 卡已用掉，第二次必须被拒（否则就是"一张卡改名无限次"）
    $again = Invoke-Api -Method POST -Path "/api/v1/user/rename-card/use" -Token $accessToken -Body @{ nickname = $newName + "X" }

    # 第二次必须是**客户端错误**（400 系），不能是 5xx：
    # 这里原先返回 90002（依赖服务不可用 / 503），因为"数量为 0 的行仍存在"
    # 会让扣减把 count 写成 -1、撞上 NonNegative 检查约束。
    # 那会让客户端显示"服务开小差了"，而正确提示是"你没有改名卡"。
    $againIsClientError = ($again.status -ge 400 -and $again.status -lt 500)
    if ($renamed.code -eq 0 -and $nickAfter -eq $newName -and $againIsClientError) {
        Write-Step -Name "改名卡流程" -Status "PASS" -Detail "昵称已改为 $nickAfter；重复使用被拒 code=$($again.code)（4xx）"
        $script:Passed++
    } else {
        Write-Step -Name "改名卡流程" -Status "FAIL" `
            -Detail "code=$($renamed.code) 昵称=$nickAfter（期望 $newName） 二次 code=$($again.code) status=$($again.status)"
        $script:Failed++
    }
}

# ---------------------------------------------------------------- 8d. 皮肤批量装备与重置
# 买一款付费牌桌皮肤 -> 与免费卡背一起批量装备 -> 再试一个没买的（必须整批被拒）
# -> 重置回默认。最后两步验的是**原子性**：被拒的那一批不能已经改了一半。
$buySkin = Invoke-Api -Method POST -Path "/api/v1/skins/table_ocean/purchase" -Token $accessToken
if ($buySkin.code -ne 0) {
    Write-Step -Name "皮肤批量装备与重置" -Status "FAIL" -Detail "购买皮肤失败 code=$($buySkin.code) message=$($buySkin.message)"
    $script:Failed++
} else {
    $equippedList = Invoke-Api -Method POST -Path "/api/v1/skins/equip-batch" -Token $accessToken `
        -Body @{ skin_ids = @("table_ocean", "card_classic") }
    $tableNow = @($equippedList.body.items | Where-Object { $_.equipped -and $_.kind -eq 'table' }) | Select-Object -First 1
    $batchOK = ($equippedList.code -eq 0) -and ($tableNow.id -eq 'table_ocean')

    # 没买过的皮肤：整批必须被拒，且**桌面仍是 table_ocean**（不能改了一半）
    $rejected = Invoke-Api -Method POST -Path "/api/v1/skins/equip-batch" -Token $accessToken `
        -Body @{ skin_ids = @("table_ocean", "table_imperial") }
    $tableAfterReject = @($equippedList.body.items | Where-Object { $_.equipped -and $_.kind -eq 'table' }) | Select-Object -First 1
    $afterReject = Invoke-Api -Method GET -Path "/api/v1/skins" -Token $accessToken
    $tableAfter = @($afterReject.body.items | Where-Object { $_.equipped -and $_.kind -eq 'table' }) | Select-Object -First 1
    $atomic = ($rejected.code -ne 0) -and ($tableAfter.id -eq 'table_ocean')

    # 重置回默认
    $reset = Invoke-Api -Method POST -Path "/api/v1/skins/reset" -Token $accessToken
    $tableReset = @($reset.body.items | Where-Object { $_.equipped -and $_.kind -eq 'table' }) | Select-Object -First 1
    $resetOK = ($reset.code -eq 0) -and ($tableReset.id -eq 'table_classic')

    if ($batchOK -and $atomic -and $resetOK) {
        Write-Step -Name "皮肤批量装备与重置" -Status "PASS" `
            -Detail "批量装备=$($tableNow.id)；未拥有者整批被拒 code=$($rejected.code) 且未改半；重置=$($tableReset.id)"
        $script:Passed++
    } else {
        Write-Step -Name "皮肤批量装备与重置" -Status "FAIL" `
            -Detail "批量=$batchOK 原子=$atomic 重置=$resetOK（$($tableNow.id)/$($tableAfter.id)/$($tableReset.id) 拒 code=$($rejected.code)）"
        $script:Failed++
    }
}

# ---------------------------------------------------------------- 9. 背包与权益
$props = Invoke-Api -Method GET -Path "/api/v1/inventory" -Token $accessToken
if ($props.code -ne 0) {
    Write-Step -Name "背包 /inventory" -Status "FAIL" -Detail "code=$($props.code) message=$($props.message)"
    $script:Failed++
} else {
    Write-Step -Name "背包 /inventory" -Status "PASS" -Detail "记牌器=$($props.body.entitlements.card_counter) 提示符=$($props.body.entitlements.hint_count)"
    $script:Passed++
}

# ---------------------------------------------------------------- 10. 榜单
# 两类榜分两条路径：`:mode_id` 是**玩法**（客户端语义），账号级榜在 /account/:board。
# 这里都要验，而且不能只验"返回 200" —— 要验它把**口径与窗口**如实回报了，
# 否则客户端看到 `"metric": ""` 会以为服务端没认出参数（这个 bug 出现过一次）。
$rank = Invoke-Api -Method GET -Path "/api/v1/leaderboards/account/points?limit=5"
if ($rank.code -ne 0) {
    Write-Step -Name "账号积分榜 /leaderboards/account/points" -Status "FAIL" -Detail "code=$($rank.code) message=$($rank.message)"
    $script:Failed++
} else {
    Write-Step -Name "账号积分榜 /leaderboards/account/points" -Status "PASS" `
        -Detail "board=$($rank.body.board) 返回 $(@($rank.body.items).Count) 条"
    $script:Passed++
}

# 玩法榜：用**种子数据一定覆盖到的**玩法（种子给每个测试玩家都写了 mode_classic）
$modeRank = Invoke-Api -Method GET -Path "/api/v1/leaderboards/mode_classic?limit=5"
$modeWins = Invoke-Api -Method GET -Path "/api/v1/leaderboards/mode_classic?metric=wins&period=weekly"
# 未知玩法必须是**客户端错误**，不能是 500 或空榜
$modeBad = Invoke-Api -Method GET -Path "/api/v1/leaderboards/not_a_real_mode"
# 好友榜尚未实现，必须给出可读的原因而不是"未知玩法"
$modeFriends = Invoke-Api -Method GET -Path "/api/v1/leaderboards/friends"

$modeOK = ($modeRank.code -eq 0) -and
          ([string]$modeRank.body.metric -eq 'points') -and
          ([string]$modeRank.body.period -eq 'total') -and
          (@($modeRank.body.items).Count -gt 0) -and
          ([string]$modeWins.body.metric -eq 'wins') -and
          ([string]$modeWins.body.period -eq 'weekly') -and
          ($modeBad.code -ne 0) -and ($modeFriends.code -ne 0)
if ($modeOK) {
    $first = @($modeRank.body.items)[0]
    Write-Step -Name "玩法榜 /leaderboards/:mode_id" -Status "PASS" `
        -Detail "mode_classic 前 $([math]::Min(5,@($modeRank.body.items).Count)) 名（首名 $($first.nickname)=$($first.score)）；口径/窗口正确回显；未知玩法 code=$($modeBad.code)；好友榜 code=$($modeFriends.code)"
    $script:Passed++
} else {
    Write-Step -Name "玩法榜 /leaderboards/:mode_id" -Status "FAIL" `
        -Detail "code=$($modeRank.code) metric=$($modeRank.body.metric) period=$($modeRank.body.period) 条数=$(@($modeRank.body.items).Count) 未知玩法=$($modeBad.code)"
    $script:Failed++
}

# ---------------------------------------------------------------- 11. 账单流水
$tx = Invoke-Api -Method GET -Path "/api/v1/wallet/transactions?page=1&page_size=10" -Token $accessToken
if ($tx.code -ne 0) {
    Write-Step -Name "账单流水 /wallet/transactions" -Status "FAIL" -Detail "code=$($tx.code) message=$($tx.message)"
    $script:Failed++
} else {
    Write-Step -Name "账单流水 /wallet/transactions" -Status "PASS" -Detail "累计 $($tx.body.total) 条（本页 $(@($tx.body.items).Count) 条）"
    $script:Passed++
}

# ---------------------------------------------------------------- 12b. 离线进度回传（REC-06）
# 模拟"离线打了两局、联网后补报"。要同时验证四件事：
#   1) 积分按净额入账；
#   2) **金币与钻石一个都不变**（离线不产出硬通货）；
#   3) 同批重放不重复加分、但仍确认接收（客户端据此才敢清本地队列）；
#   4) 服务端返回权威快照，供客户端整体替换本地值。
$profileBefore = Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken
$pointsBefore = [int64]$profileBefore.body.wallet.points
$goldBefore2 = [int64]$profileBefore.body.wallet.gold
# 字段名是单数 diamond —— 服务端所有钱包接口（/user/me、/wallet、/shop）统一用它，
# 回传快照也必须一致：同一个余额在不同接口叫不同名字会变成客户端的静默 bug。
$diaBefore2 = [int64]$profileBefore.body.wallet.diamond

$offlineIds = @((New-Ulid), (New-Ulid))
$offlineRecords = @(
    @{ id = $offlineIds[0]; mode_id = "mode_classic"; role = "农民"; won = $true; multiplier = 2; points_delta = 20; played_at = 0 },
    @{ id = $offlineIds[1]; mode_id = "mode_classic"; role = "地主"; won = $false; multiplier = 1; points_delta = -5; played_at = 0 }
)
$report = Invoke-Api -Method POST -Path "/api/v1/matches/report" -Token $accessToken -Body @{ records = $offlineRecords }
if ($report.code -ne 0) {
    Write-Step -Name "离线进度回传 /matches/report" -Status "FAIL" -Detail "code=$($report.code) message=$($report.message)"
    $script:Failed++
} else {
    $credited = [int64]$report.body.credited
    $fresh = [int]$report.body.fresh_count
    $net = [int64]$report.body.net
    $ok = ($fresh -eq 2) -and ($net -eq 15) -and ($credited -eq 15) -and
          ([int64]$report.body.snapshot.points -eq ($pointsBefore + 15)) -and
          ([int64]$report.body.snapshot.gold -eq $goldBefore2) -and
          ([int64]$report.body.snapshot.diamond -eq $diaBefore2)
    if ($ok) {
        Write-Step -Name "离线进度回传 /matches/report" -Status "PASS" -Detail "净额=$net 入账=$credited 积分 $pointsBefore -> $($report.body.snapshot.points)（金币/钻石未变）"
        $script:Passed++
    } else {
        Write-Step -Name "离线进度回传 /matches/report" -Status "FAIL" -Detail "新入账=$fresh 净额=$net 入账=$credited 快照=$($report.body.snapshot | ConvertTo-Json -Compress)"
        $script:Failed++
    }

    # 重放：同一条都不该再加分，但仍要回 accepted
    $replay = Invoke-Api -Method POST -Path "/api/v1/matches/report" -Token $accessToken -Body @{ records = $offlineRecords }
    if ($replay.code -eq 0 -and [int64]$replay.body.credited -eq 0 -and
            [int]$replay.body.fresh_count -eq 0 -and @($replay.body.accepted).Count -eq 2) {
        Write-Step -Name "离线回传幂等（同批重放）" -Status "PASS" -Detail "不重复加分，且两条都已确认接收"
        $script:Passed++
    } else {
        Write-Step -Name "离线回传幂等（同批重放）" -Status "FAIL" -Detail "code=$($replay.code) 入账=$($replay.body.credited) 新入账=$($replay.body.fresh_count) accepted=$(@($replay.body.accepted).Count)"
        $script:Failed++
    }

    # 非法记录必须整批拒绝（而不是悄悄丢掉几条）
    $badReport = Invoke-Api -Method POST -Path "/api/v1/matches/report" -Token $accessToken -Body @{ records = @(
        @{ id = "ord_$($offlineIds[0])"; mode_id = "mode_classic"; role = "农民"; won = $true; multiplier = 1; points_delta = 10; played_at = 0 }
    ) }
    if ($badReport.code -ne 0) {
        Write-Step -Name "离线回传拒绝非法 ID" -Status "PASS" -Detail "code=$($badReport.code)（带前缀的 ID 被拒）"
        $script:Passed++
    } else {
        Write-Step -Name "离线回传拒绝非法 ID" -Status "FAIL" -Detail "非法 ID 竟然被接受"
        $script:Failed++
    }
}

# ---------------------------------------------------------------- 12b. 每日计数与战绩详情（REC-05 / REC-02）
$daily = Invoke-Api -Method GET -Path "/api/v1/user/statistics/daily" -Token $accessToken
if ($daily.code -eq 0 -and [string]$daily.body.date -and $null -ne $daily.body.daily_stat) {
    Write-Step -Name "今日计数 /user/statistics/daily" -Status "PASS" `
        -Detail "date=$($daily.body.date) 今日对局=$($daily.body.daily_stat.games) 胜=$($daily.body.daily_stat.wins)"
    $script:Passed++
} else {
    Write-Step -Name "今日计数 /user/statistics/daily" -Status "FAIL" -Detail "code=$($daily.code) date=$($daily.body.date)"
    $script:Failed++
}

# 用**刚才离线回传的那条记录**查详情：跨"上报"与"查询"两条路径的交叉验证，
# 顺带确认离线战绩确实进了同一张战绩表（而不是只在回传响应里走个过场）。
$offlineID = [string]$offlineIds[0]
$detail = Invoke-Api -Method GET -Path "/api/v1/matches/$offlineID" -Token $accessToken
# 别人的/不存在的 ID 必须是 404，而不是"能查到"或 500
$missing = Invoke-Api -Method GET -Path ("/api/v1/matches/" + (New-Ulid)) -Token $accessToken
$detailOK = ($detail.code -eq 0) -and ([string]$detail.body.id -eq $offlineID) -and ($missing.code -ne 0)
if ($detailOK) {
    Write-Step -Name "战绩详情 /matches/:match_id" -Status "PASS" `
        -Detail "离线回传的这局可查（is_offline=$($detail.body.is_offline)）；不存在的 ID 返回 code=$($missing.code)"
    $script:Passed++
} else {
    Write-Step -Name "战绩详情 /matches/:match_id" -Status "FAIL" `
        -Detail "code=$($detail.code) id=$($detail.body.id)（期望 $offlineID） 不存在者 code=$($missing.code)"
    $script:Failed++
}

# ---------------------------------------------------------------- 12c. 头像上传（USER-03）
# 走完整链路：上传 -> 拿到 URL -> **用普通 GET 把文件取回来**（验证静态目录真的挂上了）
# -> 再传一个伪装成 .png 的文本，必须被拒（否则等于允许往公开目录写任意字节）。
#
# 这里用 curl.exe 而不是 Invoke-RestMethod：本仓库的脚本要在 Windows PowerShell 5.1
# 下能跑（`-Form` 参数是 PowerShell 6+ 才有的），冒烟脚本一直保持 5.1 兼容。
function Invoke-MultipartUpload {
    param([string]$Url, [string]$Token, [string]$FilePath)
    $raw = & curl.exe -s -X POST $Url -H "Authorization: Bearer $Token" `
        -F "file=@$FilePath" -w "`n%{http_code}" --max-time 30 2>$null
    $text = ($raw -join "`n")
    $idx = $text.LastIndexOf("`n")
    if ($idx -lt 0) { return @{ status = 0; body = $text } }
    return @{
        status = [int]$text.Substring($idx + 1).Trim()
        body   = $text.Substring(0, $idx)
    }
}

$pngBytes = [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")
$tmpDir = [System.IO.Path]::GetTempPath()
$tmpPng = Join-Path $tmpDir "smoke-avatar-$([guid]::NewGuid().ToString('N')).png"
[System.IO.File]::WriteAllBytes($tmpPng, $pngBytes)
# 后缀**故意写成 .png**：检验服务端是按真实内容还是按文件名判定类型
$fakePng = Join-Path $tmpDir "smoke-avatar-$([guid]::NewGuid().ToString('N')).png"
[System.IO.File]::WriteAllText($fakePng, "this is definitely not an image")

$uploadOK = $false
$uploadDetail = ""
try {
    $up = Invoke-MultipartUpload -Url "$BaseUrl/api/v1/user/avatar" -Token $accessToken -FilePath $tmpPng
    $avatarUrl = ""
    if ($up.status -eq 200) { $avatarUrl = [string](($up.body | ConvertFrom-Json).body.avatar_url) }

    # 用普通 GET 取回文件：这一步才真正证明"静态目录挂载 + URL 可访问"
    $fetched = Invoke-WebRequest -Method GET -Uri "$BaseUrl$avatarUrl" -UseBasicParsing -TimeoutSec 15
    $sameBytes = ($fetched.RawContentLength -eq $pngBytes.Length)

    $bad = Invoke-MultipartUpload -Url "$BaseUrl/api/v1/user/avatar" -Token $accessToken -FilePath $fakePng

    # 档案里也要带上新头像地址（否则客户端拿到 URL 却读不到）
    $profAfter = Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken

    if ($up.status -eq 200 -and $avatarUrl -and $fetched.StatusCode -eq 200 -and $sameBytes -and
            $bad.status -ge 400 -and [string]$profAfter.body.avatar_url -eq $avatarUrl) {
        $uploadOK = $true
        $uploadDetail = "URL=$avatarUrl 匿名 GET 可取回（$($pngBytes.Length) 字节）；伪装成 png 的文本被拒（HTTP $($bad.status)）；档案已同步"
    } else {
        $uploadDetail = "上传 HTTP $($up.status) URL=$avatarUrl 取回=$($fetched.StatusCode) 字节相同=$sameBytes 伪装拒绝=$($bad.status) 档案=$($profAfter.body.avatar_url)"
    }
} catch {
    $uploadDetail = $_.Exception.Message
} finally {
    Remove-Item -LiteralPath $tmpPng, $fakePng -ErrorAction SilentlyContinue
}
if ($uploadOK) {
    Write-Step -Name "头像上传 /user/avatar" -Status "PASS" -Detail $uploadDetail
    $script:Passed++
} else {
    Write-Step -Name "头像上传 /user/avatar" -Status "FAIL" -Detail $uploadDetail
    $script:Failed++
}
# ---------------------------------------------------------------- 13. 邮箱
$mailList = Invoke-Api -Method GET -Path "/api/v1/mail?page=1&page_size=10" -Token $accessToken
if ($mailList.code -ne 0) {
    Write-Step -Name "邮箱列表 /mail" -Status "FAIL" -Detail "code=$($mailList.code) message=$($mailList.message)"
    $script:Failed++
} else {
    Write-Step -Name "邮箱列表 /mail" -Status "PASS" -Detail "未读 $((Invoke-Api -Method GET -Path '/api/v1/notifications/unread-count' -Token $accessToken).body.unread)"
    $script:Passed++
}

# ---------------------------------------------------------------- 13. 匹配
if ($SkipMatch) {
    Write-Step -Name "对局匹配" -Status "SKIP" -Detail "已指定 -SkipMatch"
    $script:Skipped++
} else {
    $match = Invoke-Api -Method POST -Path "/api/v1/match/quick" -Token $accessToken -Body @{ mode_id = "mode_classic" }
    if ($match.code -ne 0) {
        Write-Step -Name "对局匹配" -Status "FAIL" -Detail "code=$($match.code) message=$($match.message)"
        $script:Failed++
    } else {
        Write-Step -Name "对局匹配" -Status "PASS" -Detail "状态=$($match.body.status) 队列位置=$($match.body.position)"
        $script:Passed++

        # 票据 ID（需求 MATCH-01 要求返回 ticket_id）：客户端拿它查状态与取消匹配。
        # 之前没有这个字段，取消匹配只能靠"当前用户"隐式表达 ——
        # 那让客户端无法表达"取消我刚才那一次匹配"。
        $ticketID = [string]$match.body.ticket_id
        if ($ticketID -and (Test-ClientUlid -Value $ticketID)) {
            Write-Step -Name "匹配票据 ticket_id" -Status "PASS" -Detail "ticket_id=$ticketID（合法 ULID）"
            $script:Passed++
        } else {
            Write-Step -Name "匹配票据 ticket_id" -Status "FAIL" -Detail "ticket_id 缺失或不是合法 ULID：'$ticketID'"
            $script:Failed++
        }

        # 按票据查状态（GET /match/tickets/:id）
        $ticketStatus = Invoke-Api -Method GET -Path "/api/v1/match/tickets/$ticketID" -Token $accessToken
        if ($ticketStatus.code -eq 0 -and [string]$ticketStatus.body.status -eq 'queued') {
            Write-Step -Name "按票据查匹配状态" -Status "PASS" -Detail "status=$($ticketStatus.body.status)"
            $script:Passed++
        } else {
            Write-Step -Name "按票据查匹配状态" -Status "FAIL" -Detail "code=$($ticketStatus.code) status=$($ticketStatus.body.status)"
            $script:Failed++
        }

        # 在线状态（USER-09）：此刻正处于匹配队列中，HTTP 侧的答案必须与匹配状态一致。
        # 这是两条独立路径（HTTP 查、匹配队列）之间的交叉验证 ——
        # 只断言"接口返回 200"是没意义的，要断言它**说对了**。
        $presence = Invoke-Api -Method GET -Path "/api/v1/user/online-status" -Token $accessToken
        if ($presence.code -eq 0 -and $presence.body.matching -eq $true -and
                $presence.body.in_room -eq $false) {
            Write-Step -Name "在线状态 /user/online-status" -Status "PASS" `
                -Detail "matching=$($presence.body.matching) in_room=$($presence.body.in_room) online=$($presence.body.online)（与匹配状态一致）"
            $script:Passed++
        } else {
            Write-Step -Name "在线状态 /user/online-status" -Status "FAIL" `
                -Detail "code=$($presence.code) matching=$($presence.body.matching) in_room=$($presence.body.in_room)"
            $script:Failed++
        }

        # 拿一个**别人的/伪造的**票据 ID 必须被拒（不能取消别人的匹配）
        $foreign = Invoke-Api -Method DELETE -Path ("/api/v1/match/tickets/" + (New-Ulid)) -Token $accessToken
        if ($foreign.code -ne 0) {
            Write-Step -Name "拒绝非本人票据" -Status "PASS" -Detail "code=$($foreign.code)"
            $script:Passed++
        } else {
            Write-Step -Name "拒绝非本人票据" -Status "FAIL" -Detail "伪造的票据竟然取消了匹配"
            $script:Failed++
        }

        # 匹配成功后房间由 WebSocket 推送；这里只验证"能取消"这条 HTTP 路径。
        $cancel = Invoke-Api -Method DELETE -Path "/api/v1/match/tickets/$ticketID" -Token $accessToken
        if ($cancel.code -eq 0) {
            Write-Step -Name "取消匹配" -Status "PASS" -Detail "status=$($cancel.body.status)"
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
$afterLogout = Invoke-Api -Method GET -Path "/api/v1/user/profile" -Token $accessToken
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
