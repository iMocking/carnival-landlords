# 客户端 headless 自测批量运行器（重构护栏）
#   用法：
#     powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
#     powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Only rules,settings
#     powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -List
#   全部用例退出码 0 才算通过；任一失败则本脚本退出码为 1。
#
#   为什么需要它：`src/` 的服务层剥离（离线服务抽取）必须保证"行为不变"，
#   而现有 19 个 headless 测试就是这件事唯一的证据来源。逐条手敲命令既慢又容易漏，
#   所以把清单固定在这里 —— 新增测试要同步加进 $Tests，否则它会静默地不被守护。
param(
    [string]$Godot = "D:\apps\godot\Godot_v4.7.2-stable_win64_console.exe",
    [string[]]$Only = @(),
    [switch]$List,
    [switch]$Quiet,
    [switch]$SkipImport
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }

# 顺序与 README「自测」章节一致：先纯逻辑，再依赖资源/场景的
$Tests = @(
    "card_art_test",
    "audio_test",
    "audio_library_test",
    "rules_smoke_test",
    "mode_rules_test",
    "mode_flow_test",
    "viewmodel_integration_test",
    "deal_flow_test",
    "app_flow_test",
    "profile_menu_test",
    "ui_refactor_test",
    "login_field_test",
    "result_ready_test",
    "font_theme_test",
    "branding_test",
    "boot_splash_test",
    "version_test",
    "safe_area_test",
    "page_padding_test",
    "settings_test",
    "activity_shop_test",
    "offline_sync_test",
    "service_mode_test",
    "account_identity_test",
    "view_boundary_test",
    "service_contract_test",
    "net_transport_test",
    "online_service_test",
    "game_session_test",
    "drag_select_test"
)

if ($List) {
    $Tests | ForEach-Object { $_ }
    exit 0
}

$selected = if ($Only.Count -gt 0) {
    $Tests | Where-Object { $name = $_; ($Only | Where-Object { $name -like "*$_*" }).Count -gt 0 }
} else {
    $Tests
}
if ($selected.Count -eq 0) { throw "no test matched -Only $($Only -join ',')" }

# 把当前目录切到客户端根，但**必须能还原**。
#
# 这里刻意不用裸 Set-Location：它会把调用方的当前目录留在 apps/client，
# 于是"先跑客户端测试、再跑后端冒烟"这种组合命令会在错误的目录里找 scripts\smoke.ps1，
# 报"找不到路径"，而退出码可能还是上一个命令的 0 —— 看起来像通过了，实际什么都没跑。
# Push/Pop 成对出现，三个出口都还原。
Push-Location $root

try {
# 先扫一遍导入与全局类名缓存。
# 不加这一步会踩一个很迷惑的坑：新增带 `class_name` 的脚本后直接跑测试，
# Godot 会报 "Identifier ... not declared in the current scope" 这类**解析错误**，
# 看起来像代码写错了，实际只是全局类名缓存还没更新。
if (-not $SkipImport) {
    $prevEapImport = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Godot --headless --path $root --import 2>&1 | Out-Null
    $ErrorActionPreference = $prevEapImport
}

$failed = @()
$totalChecks = 0

foreach ($t in $selected) {
    # Godot 会把无害告警写到 stderr（例如"非等值对锚点会被 _ready 覆盖"）。
    # 在 $ErrorActionPreference='Stop' 下，原生命令的 stderr 会被当成终止性错误，
    # 于是整个 runner 会在第一条告警处中断 —— 所以这里临时放宽，只看退出码。
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & $Godot --headless --path $root --script "res://tests/$t.gd" 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    $text = ($out | Out-String)

    # 汇总断言数（各测试打印格式不完全一致，取出现过的最大值）
    foreach ($m in [regex]::Matches($text, "checks=(\d+)")) {
        $n = [int]$m.Groups[1].Value
        if ($n -gt 0) { $totalChecks += $n; break }
    }

    if ($code -eq 0) {
        if (-not $Quiet) {
            $ev = @($out | Where-Object { $_ -match "checks=|failures=|ALL PASS" } | Select-Object -Last 1)
            Write-Host ("[PASS] {0,-30} {1}" -f $t, ($ev -join ""))
        }
    } else {
        $failed += $t
        Write-Host ("[FAIL] {0,-30} exit={1}" -f $t, $code)
        $out | Select-Object -Last 30 | ForEach-Object { Write-Host "        $_" }
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host ("ALL PASS  {0}/{1} 用例，累计断言约 {2}" -f $selected.Count, $selected.Count, $totalChecks)
    $code = 0
} else {
    Write-Host ("FAILED {0}/{1}: {2}" -f $failed.Count, $selected.Count, ($failed -join ", "))
    $code = 1
}
} finally {
    # finally 保证异常路径也还原目录
    Pop-Location
}
exit $code
