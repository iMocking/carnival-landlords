# Ensure a PowerShell script file is stored as UTF-8 WITH BOM.
#
# Why this file exists
# --------------------
# Windows PowerShell 5.1 (the `powershell.exe` that ships with Windows) assumes
# a script file without a byte order mark is encoded in the system ANSI code page.
# This repository writes all comments and messages in Chinese, so a BOM-less
# UTF-8 script is decoded as GBK: a multi-byte character can swallow the closing
# quote of a string literal, and the script then fails to PARSE -- long before
# any of its own code could run and report the problem.
#
# PowerShell 7 (`pwsh`) reads BOM-less UTF-8 correctly, so the bug only shows up
# on machines running Windows PowerShell, which is exactly where it is hardest
# to diagnose. Any editor or tool that rewrites the file without a BOM
# (including automated refactors) silently reintroduces it.
#
# So rather than relying on everyone remembering, `make smoke` calls this script
# first and repairs the file in place. Keep THIS file pure ASCII: it has to be
# readable no matter which code page the host is using.
#
# Usage:
#   powershell -NoProfile -File scripts/ensure-utf8-bom.ps1 -Path scripts/smoke.ps1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

$resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
$full = $resolved.Path

$bytes = [System.IO.File]::ReadAllBytes($full)
if ($bytes.Length -eq 0) {
    Write-Host "ensure-utf8-bom: file is empty, nothing to do: $full"
    exit 0
}

$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
if ($hasBom) {
    exit 0
}

$bom = [byte[]](0xEF, 0xBB, 0xBF)
$combined = New-Object byte[] ($bom.Length + $bytes.Length)
[Array]::Copy($bom, 0, $combined, 0, $bom.Length)
[Array]::Copy($bytes, 0, $combined, $bom.Length, $bytes.Length)

[System.IO.File]::WriteAllBytes($full, $combined)
Write-Host "ensure-utf8-bom: added UTF-8 BOM to $full"
exit 0
