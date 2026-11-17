<#
.SYNOPSIS
    Claude 痕迹清理 · Windows
.DESCRIPTION
    默认 DryRun：只列出会动什么。加 -Apply 才执行：
      1) 备份到 -BackupRoot（默认 D:\ClaudeBackups\<时间戳>）并生成 SHA-256 清单
      2) 删除一律送回收站，不永久删除
    保护清单内的路径永不触碰。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File cleanup_traces.ps1 -DryRun
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File cleanup_traces.ps1 -Apply
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File cleanup_traces.ps1 -Apply -Only claude-code,claude-app
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Apply,
    [string[]]$Only = @('all'),
    [string]$BackupRoot = 'D:\ClaudeBackups',
    [switch]$Keychain
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

if (-not $Apply) { $DryRun = $true }
if ($Apply -and $DryRun -and -not $PSBoundParameters.ContainsKey('DryRun')) { $DryRun = $false }
if ($Apply -and $PSBoundParameters.ContainsKey('DryRun') -and $DryRun) {
    Write-Host '同时给了 -Apply 和 -DryRun，按 DryRun 处理。' -ForegroundColor Yellow
    $Apply = $false
}

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $BackupRoot $stamp
$home_  = $env:USERPROFILE

$targets = @(
    @{ Scope='claude-code'; Path="$home_\.claude\cache" }
    @{ Scope='claude-code'; Path="$home_\.claude\stats-cache.json" }
    @{ Scope='claude-code'; Path="$home_\.claude\telemetry" }
    @{ Scope='claude-code'; Path="$home_\.claude\usage.jsonl" }
    @{ Scope='claude-code'; Path="$home_\.claude\usage.with-fix.jsonl" }
    @{ Scope='claude-code'; Path="$env:LOCALAPPDATA\claude-code\Cache" }
    @{ Scope='claude-code'; Path="$env:LOCALAPPDATA\claude-code\logs" }
    @{ Scope='claude-code'; Path="$home_\.claude\ant-did" }
    @{ Scope='claude-code'; Path="$home_\.claude\ant-device-registry.json" }
    @{ Scope='claude-app';  Path="$env:APPDATA\Claude" }
    @{ Scope='claude-app';  Path="$env:LOCALAPPDATA\AnthropicClaude" }
)

$protected = @(
    "$home_\.claude\projects"
    "$home_\.claude\sessions"
    "$home_\.claude\history.jsonl"
    "$home_\.claude\file-history"
    "$home_\.claude\skills"
    "$home_\.claude\plugins"
    "$home_\.claude\hooks"
    "$home_\.claude\commands"
    "$home_\.claude\agents"
    "$home_\.claude\mcp-servers"
    "$home_\.claude\CLAUDE.md"
    "$home_\.claude\settings.json"
    "$home_\.claude\settings.local.json"
    "$home_\.claude\backups"
)

function Test-Protected {
    param([string]$Path)
    foreach ($p in $protected) {
        if ($Path -eq $p -or $Path.StartsWith($p + '\')) { return $true }
    }
    return $false
}

function Test-Scope {
    param([string]$Scope)
    if ($Only -contains 'all') { return $true }
    return $Only -contains $Scope
}

function Get-Size {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $s = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object Length -Sum).Sum
    } else {
        $s = (Get-Item -LiteralPath $Path -Force).Length
    }
    if (-not $s) { $s = 0 }
    return ('{0:N1} MB' -f ($s / 1MB))
}

Write-Host 'Claude 痕迹清理 · Windows'
Write-Host ("模式：{0}" -f $(if ($Apply) { 'APPLY（会真的动文件）' } else { 'DRY-RUN（只打印）' }))
Write-Host ("范围：{0}" -f ($Only -join ','))
Write-Host ("备份：{0}" -f $backup)
Write-Host ('-' * 68)

$plan = @()
foreach ($t in $targets) {
    if (-not (Test-Scope $t.Scope)) { continue }
    if (-not (Test-Path -LiteralPath $t.Path)) { continue }
    if (Test-Protected $t.Path) { Write-Host ("[跳过·保护] {0}" -f $t.Path) -ForegroundColor DarkYellow; continue }
    Write-Host ("[计划] {0,-10} {1,-12} {2}" -f (Get-Size $t.Path), $t.Scope, $t.Path)
    $plan += $t
}

# 需要精确匹配的零散目标
$globTargets = @()
if (Test-Scope 'editor' -or Test-Scope 'system') {
    Write-Host ''
    Write-Host '[零散目标] 需按名字精确匹配，脚本不自动删：'
    foreach ($g in @("$home_\.vscode\extensions\anthropic.*",
                     "$env:APPDATA\Code\User\globalStorage\anthropic.*")) {
        Get-ChildItem -Path $g -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host ("  - {0}  ({1})" -f $_.FullName, (Get-Size $_.FullName))
            $globTargets += $_.FullName
        }
    }
}

# 浏览器提示
if (Test-Scope 'browser') {
    Write-Host ''
    Write-Host '[浏览器] 请用浏览器自带「站点数据」管理删除，脚本不直接改数据库：'
    Write-Host '  Chrome/Edge -> 设置 -> 隐私、搜索和服务 -> 第三方 Cookie -> 查看所有站点数据'
    Write-Host '  域名：claude.ai  anthropic.com  claude.com  withpersona.com'
    Write-Host '  详见 references/03b-cleanup-windows.md 第 4.5 节'
}

Write-Host ''
if ($plan.Count -eq 0 -and $globTargets.Count -eq 0) {
    Write-Host '没有匹配到需要清理的目标。'
    exit 0
}

if (-not $Apply) {
    Write-Host 'DRY-RUN 结束。确认无误后加 -Apply 执行。'
    Write-Host '提醒：执行前请先退出 Claude 桌面端与 Claude Code。'
    exit 0
}

# 进程检查
$proc = Get-Process Claude -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host '检测到 Claude 进程在运行，请先正常退出后重跑。' -ForegroundColor Red
    exit 1
}

# 备份
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($t in $plan) {
    $rel = $t.Path.Replace($home_, '').TrimStart('\')
    $dst = Join-Path $backup $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    try { Copy-Item -LiteralPath $t.Path -Destination $dst -Recurse -Force } catch {
        Write-Host ("备份失败（继续）: {0} -> {1}" -f $t.Path, $_.Exception.Message) -ForegroundColor Yellow
    }
}
Get-ChildItem $backup -Recurse -File -Force |
    Get-FileHash -Algorithm SHA256 |
    Select-Object Path, Hash |
    Export-Csv (Join-Path $backup 'MANIFEST.csv') -NoTypeInformation -Encoding UTF8
$fileCount = (Get-ChildItem $backup -Recurse -File -Force).Count
Write-Host ("备份完成：{0}（{1} 个文件已校验）" -f $backup, $fileCount) -ForegroundColor Green

# 送回收站
function Move-ToRecycleBin {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

foreach ($t in $plan) {
    try {
        Move-ToRecycleBin $t.Path
        Write-Host ("已送回收站: {0}" -f $t.Path)
    } catch {
        Write-Host ("失败: {0} -> {1}" -f $t.Path, $_.Exception.Message) -ForegroundColor Yellow
    }
}
foreach ($g in $globTargets) {
    try { Move-ToRecycleBin $g; Write-Host ("已送回收站: {0}" -f $g) } catch { }
}

# 凭据管理器
if ($Keychain) {
    $keys = cmdkey /list | Select-String -Pattern 'Target:.*Claude' -AllMatches
    foreach ($k in $keys) {
        $name = ($k.Line -replace '.*Target:\s*', '').Trim()
        cmdkey /delete:$name | Out-Null
        Write-Host ("已删除凭据: {0}" -f $name)
    }
}

# 系统层
ipconfig /flushdns | Out-Null
Write-Host '已清 DNS 缓存'
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$hit = Select-String -Path $hosts -Pattern 'claude|anthropic' -ErrorAction SilentlyContinue
if ($hit) {
    Write-Host '注意：hosts 里有相关条目，请手工检查：' -ForegroundColor Yellow
    $hit | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.LineNumber, $_.Line) }
}
Set-Clipboard -Value ' '

Write-Host ('-' * 68)
Write-Host '完成。'
Write-Host ("回滚：Copy-Item '{0}\*' '<原路径>' -Recurse -Force，或从回收站还原。" -f $backup)
Write-Host '提醒：浏览器站点数据、凭据、支付/手机号/硬件指纹不在本脚本范围内。'
