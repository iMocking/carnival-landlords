# 一键导出 Android APK（默认调试包，可直接装到手机上测试）
#   用法：
#     powershell -ExecutionPolicy Bypass -File tools\export_android.ps1
#     powershell -ExecutionPolicy Bypass -File tools\export_android.ps1 -Release -Part minor
#   版本号由 version.json 管理：默认每次打包 patch +1、versionCode +1；
#   产物按版本命名（如 build/waiting-for-landlord-v1.0.1-b2-debug.apk），旧包不会被覆盖。
param(
    [string]$Godot = "D:\apps\godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$JavaHome = "D:\apps\jdk17",
    [string]$Output = "",
    [ValidateSet("patch", "minor", "major")][string]$Part = "patch",
    [switch]$Release,
    [switch]$NoBump,
    [switch]$AllowOverwrite,
    [switch]$NoExport
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }
if (-not (Test-Path "$JavaHome\bin\java.exe")) { throw "JDK not found: $JavaHome" }
$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"

# 0) 编辑器设置里的 Java SDK 路径：Godot 拿它跑 keytool / apksigner，**为空时连 debug 包都拒绝导出**
#    （只设 JAVA_HOME 不够），而报出来的只是一句笼统的 "configuration errors"，很难查。
#    而 Godot 编辑器退出时会用内存里的设置覆盖这个文件，手工填的那次很容易被冲掉，
#    所以这里只在它为空时补一次。
#    注意：必须用 .NET 的显式 UTF-8 读写 —— `Get-Content`/`Set-Content` 在 PowerShell 5.1 下
#    按系统 ANSI 解码无 BOM 的 UTF-8 文件，写回去就把文件写成乱码了（踩过这个坑）。
$editorSettings = Join-Path $env:APPDATA "Godot\editor_settings-4.7.tres"
if (Test-Path $editorSettings) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($editorSettings, [System.Text.Encoding]::UTF8)
    if ($text -match 'export/android/java_sdk_path\s*=\s*""') {
        $javaPath = $JavaHome -replace '\\', '/'
        $text = $text -replace 'export/android/java_sdk_path\s*=\s*""', "export/android/java_sdk_path = `"$javaPath`""
        [System.IO.File]::WriteAllText($editorSettings, $text, $utf8)
        Write-Host "[fix] 编辑器设置的 Java SDK 路径为空，已补成 $javaPath"
    }
}

# 1) 版本号：默认 patch +1 / versionCode +1；-NoBump 只同步当前版本
$modeName = if ($Release) { "release" } else { "debug" }
$action = if ($NoBump) { "--sync" } else { "--bump" }
$versionArgs = @("--headless", "--path", $root, "--script", "res://tools/version.gd", "--", $action, "--part=$Part", "--mode=$modeName")
$versionOutput = & $Godot @versionArgs
if ($LASTEXITCODE -ne 0) { throw "version step failed (exit $LASTEXITCODE)" }

$versionLine = @($versionOutput | Where-Object { $_ -match "VERSION=" }) | Select-Object -Last 1
$artifactLine = @($versionOutput | Where-Object { $_ -match "ARTIFACT=" }) | Select-Object -Last 1
if (-not $versionLine -or -not $artifactLine) { throw "cannot parse version tool output" }
$version = ($versionLine -replace "^.*VERSION=", "") | ConvertFrom-Json
$defaultOutput = $artifactLine -replace "^.*ARTIFACT=", ""
if ([string]::IsNullOrWhiteSpace($Output)) { $Output = $defaultOutput }
$Output = $Output -replace "\\", "/"
$apk = Join-Path $root $Output

# 2) 防覆盖：版本号没变（-NoBump）且同名产物已存在时，必须显式 -AllowOverwrite
if ((Test-Path $apk) -and -not $AllowOverwrite) {
    throw "artifact already exists: $Output (version unchanged?) - use -AllowOverwrite to rebuild on purpose"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $apk) | Out-Null

Write-Host ("[version] {0} (build {1})" -f $version.name, $version.code)
Write-Host "[artifact] $Output"

if ($NoExport) {
    Write-Host "[skip] -NoExport：版本步骤已完成，未执行导出"
    exit 0
}

# 3) 导出到版本化路径
$exportMode = if ($Release) { "--export-release" } else { "--export-debug" }
Write-Host "[export] $Output ($exportMode)"
& $Godot --headless --path $root $exportMode "Android" $Output
if ($LASTEXITCODE -ne 0) {
    if (Test-Path $apk) { Remove-Item -Force $apk }
    throw "export failed (exit $LASTEXITCODE)"
}

# 4) 成功产物记入 build/build-history.csv（build/ 不入库，只是本机台账）
$item = Get-Item $apk
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash
$history = Join-Path $root "build\build-history.csv"
if (-not (Test-Path $history)) {
    "time,mode,version,build,file,size_bytes,sha256" | Out-File -FilePath $history -Encoding utf8
}
$record = "{0},{1},{2},{3},{4},{5},{6}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $modeName, $version.name, $version.code, $Output, $item.Length, $sha
$record | Add-Content -Path $history -Encoding utf8

Write-Host ("[done] {0} ({1:N1} MB)" -f $item.FullName, ($item.Length / 1MB))
Write-Host "[install] adb install -r `"$apk`"  (or copy the APK to the phone and tap it)"
Write-Host "[history] $history"